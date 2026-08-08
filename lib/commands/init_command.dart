import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:crypto/crypto.dart';
import 'package:tapster/models/tapster_config.dart';
import 'package:tapster/services/config_service.dart';
import 'package:tapster/services/github_service.dart';
import 'package:tapster/utils/repo_utils.dart';
import 'package:tapster/utils/string_buffer_extensions.dart';

class InitCommand extends Command {
  @override
  final name = 'init';

  @override
  final description = 'Create or update a Tapster configuration file';

  InitCommand() {
    argParser.addFlag(
      'force',
      abbr: 'f',
      help: 'Force overwrite an already-configured target',
      negatable: false,
    );
    argParser.addMultiOption(
      'target',
      abbr: 't',
      help:
          'Distribution target(s) to configure: homebrew/formula, homebrew/cask, scoop',
      allowed: ['homebrew/formula', 'homebrew/cask', 'scoop'],
      defaultsTo: ['homebrew/formula'],
    );
    argParser.addFlag(
      'private',
      help: 'Create hosting repositories as private (default: public)',
      negatable: false,
    );
    argParser.addFlag(
      'yes',
      abbr: 'y',
      help: 'Skip the repository creation confirmation',
      negatable: false,
    );
  }

  @override
  Future<void> run() async {
    if (argResults == null) return;

    final force = argResults!['force'] as bool;
    final targets = argResults!['target'] as List<String>;

    final configService = ConfigService();
    final configExists = await configService.configExists(null);

    TapsterConfig config;
    String? githubUsername;

    if (configExists) {
      // Load existing config
      config = await configService.loadConfig(null);
      final buffer = StringBuffer()
        ..writeSuccess('Existing configuration loaded (${config.name})');
      print(buffer.toString());
    } else {
      // Fresh config — ask common fields
      print('Creating new configuration:');
      githubUsername = await _getGithubUsername();
      config = await _askCommonFields(githubUsername);
    }

    // Resolve GitHub username for defaults (if not already fetched)
    githubUsername ??= await _getGithubUsername();

    // Process each target
    var changed = false;
    final configuredTargets = <String>[];
    for (final target in targets) {
      final alreadyConfigured = _isTargetConfigured(config, target);

      if (alreadyConfigured && !force) {
        final buffer = StringBuffer()
          ..writeWarning('Target "$target" is already configured, skipping');
        print(buffer.toString());
        print('    Use --force to overwrite');
        print('');
        continue;
      }

      if (alreadyConfigured && force) {
        final buffer = StringBuffer()
          ..writeWarning('Overwriting existing "$target" configuration');
        print(buffer.toString());
      }

      config = await _configureTarget(config, target, githubUsername);
      changed = true;
      configuredTargets.add(target);
    }

    if (!changed) {
      print('No changes made.');
      return;
    }

    // Save configuration
    await _saveConfig(config);

    final buffer = StringBuffer()
      ..writeSuccess('Configuration saved to .tapster.yaml');
    print(buffer.toString());

    // 引导步骤：为本次新配置的目标创建托管仓库（tap/bucket），幂等
    if (configuredTargets.isNotEmpty) {
      await _createHostingRepos(config, configuredTargets);
    }
  }

  // ── Hosting repositories ────────────────────────────────────────

  /// 为本次新配置的目标创建托管仓库（Homebrew tap / Scoop bucket）。
  ///
  /// 创建公开仓库是外向操作：默认交互确认（默认 yes），--yes 跳过、
  /// --private 建私有仓库（对 scoop 警告）。已存在的仓库自动跳过。
  /// 配置已保存，创建失败不致命——提示重跑 init（幂等）或手动创建。
  Future<void> _createHostingRepos(
    TapsterConfig config,
    List<String> targets,
  ) async {
    final isPrivate = argResults!['private'] as bool;
    final skipConfirm = argResults!['yes'] as bool;

    final repos = <(String, String, String)>[];
    for (final target in targets) {
      final resolved = _resolveHostingRepo(config, target);
      if (resolved != null) repos.add((target, resolved.$1, resolved.$2));
    }
    if (repos.isEmpty) return;

    if (isPrivate) {
      final warn = StringBuffer()
        ..writeWarning('Private repositories requested');
      print(warn.toString());
      print('    Note: Scoop buckets must be public to be installable.');
    }

    print('');
    final bullet = StringBuffer()
      ..writeBullet('Hosting repositories');
    print(bullet.toString());

    final githubService = GitHubService();
    var failures = 0;
    for (final (target, owner, repo) in repos) {
      final fullName = '$owner/$repo';
      final exists = await githubService.repositoryExists(owner, repo);

      if (exists) {
        final buffer = StringBuffer()
          ..writeSuccess('Repository exists ($target): $fullName');
        print(buffer.toString());
        continue;
      }

      if (!skipConfirm) {
        stdout.write('Create repository $fullName ($target)? (Y/n): ');
        final input = stdin.readLineSync()?.trim().toLowerCase() ?? 'y';
        if (input == 'n' || input == 'no') {
          final buffer = StringBuffer()
            ..writeWarning('Skipped: $fullName');
          print(buffer.toString());
          continue;
        }
      }

      try {
        await githubService.createRepository(owner, repo, public: !isPrivate);
        final buffer = StringBuffer()
          ..writeSuccess('Repository created ($target): $fullName');
        print(buffer.toString());
      } catch (e) {
        final buffer = StringBuffer()
          ..writeError('Failed to create ($target): $fullName');
        print(buffer.toString());
        print('    $e');
        failures++;
      }
    }

    if (failures > 0) {
      print('');
      final warn = StringBuffer()
        ..writeWarning('Some repositories could not be created');
      print(warn.toString());
      print('    The configuration is saved. Rerun "tapster init -t <target>"');
      print('    (idempotent) or create the repositories on GitHub.');
      exit(1);
    }
  }

  /// 目标 → 托管仓库 (owner, repo)；未知目标返回 null。
  (String, String)? _resolveHostingRepo(TapsterConfig config, String target) {
    switch (target) {
      case 'homebrew/formula':
        return resolveTapRepo(config.formula!.tap);
      case 'homebrew/cask':
        return resolveTapRepo(config.cask!.tap);
      case 'scoop':
        final parts = config.scoop!.bucket.split('/');
        if (parts.length != 2) {
          throw Exception(
            'Invalid scoop bucket: ${config.scoop!.bucket} '
            '(expected owner/bucket)',
          );
        }
        return (parts[0], parts[1]);
      default:
        return null;
    }
  }

  // ── Cask ───────────────────────────────────────────────────────

  Future<CaskConfig> _askCask(
    TapsterConfig config,
    String? githubUsername,
  ) async {
    final defaultOwner = githubUsername ?? 'user';

    print('');
    print('── Cask configuration ──');
    final tap = await _askString('Cask tap', '$defaultOwner/homebrew-cask');
    final asset = await _askString(
      'App archive path (.zip)',
      'build/macos/${config.name}.zip',
    );
    final appName = await _askString(
      'App name (e.g. MyApp.app)',
      '${config.name}.app',
    );

    final checksum = await _maybeCalculateChecksum(asset);
    return CaskConfig(
      tap: tap,
      asset: asset,
      appName: appName,
      checksum: checksum,
    );
  }

  // ── Common fields ──────────────────────────────────────────────

  Future<TapsterConfig> _askCommonFields(String? githubUsername) async {
    final defaultOwner = githubUsername ?? 'user';

    final name = await _askString('Package name', 'my-package');
    // version 可选：版本由远端 Release tag 决定，配置生成后无需维护
    final description = await _askString('Description', 'A sample package');
    final repository = await _askString(
      'Repository URL',
      'https://github.com/$defaultOwner/$name.git',
    );
    final license = await _askString('License', 'MIT');

    final homepage = repository.endsWith('.git')
        ? repository.substring(0, repository.length - 4)
        : repository;

    return TapsterConfig(
      name: name,
      description: description,
      homepage: homepage,
      repository: repository,
      license: license,
    );
  }

  // ── Formula ────────────────────────────────────────────────────

  Future<FormulaConfig> _askFormula(
    TapsterConfig config,
    String? githubUsername,
  ) async {
    final defaultOwner = githubUsername ?? 'user';

    print('');
    print('── Formula configuration ──');
    // 默认标准命名（一个 tap 托管所有工具），setup 命令负责创建仓库
    final tap = await _askString('Tap name', defaultTapName(defaultOwner));
    final asset = await _askString('Binary file path', 'build/${config.name}');
    final depsInput = await _askString(
      'Dependencies (comma-separated, leave empty if none)',
      '',
    );
    final dependencies = depsInput.trim().isEmpty
        ? <String>[]
        : depsInput
              .split(',')
              .map((d) => d.trim())
              .where((d) => d.isNotEmpty)
              .toList();

    final checksum = await _maybeCalculateChecksum(asset);
    return FormulaConfig(
      tap: tap,
      asset: asset,
      checksum: checksum,
      dependencies: dependencies,
    );
  }

  // ── Scoop ──────────────────────────────────────────────────────

  Future<ScoopConfig> _askScoop(
    TapsterConfig config,
    String? githubUsername,
  ) async {
    final defaultOwner = githubUsername ?? 'user';

    print('');
    print('── Scoop configuration ──');
    // 默认标准命名（仓库名即 bucket 名），setup 命令负责创建仓库
    final bucket = await _askString(
      'Scoop bucket',
      defaultBucketName(defaultOwner),
    );
    final asset = await _askString(
      'App archive path (.zip)',
      'build/windows/${config.name}.zip',
    );
    final arch = await _askString('Architecture', '64bit');

    final shortcutsInput = await _askString(
      'Shortcuts (comma-separated, leave empty if none)',
      '',
    );
    final shortcuts = shortcutsInput.trim().isEmpty
        ? <String>[]
        : shortcutsInput
              .split(',')
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty)
              .toList();

    final checksum = await _maybeCalculateChecksum(asset);
    return ScoopConfig(
      bucket: bucket,
      asset: asset,
      arch: arch,
      checksum: checksum,
      shortcuts: shortcuts,
    );
  }

  Future<String> _askString(String prompt, String defaultValue) async {
    if (defaultValue.trim().isEmpty) {
      stdout.write('$prompt: ');
    } else {
      final buffer = StringBuffer()
        ..write('$prompt: ')
        ..writeGreyDefault('[$defaultValue]')
        ..write(' ');
      stdout.write(buffer.toString());
    }
    final input = stdin.readLineSync()?.trim() ?? '';
    return input.isEmpty ? defaultValue : input;
  }

  Future<String?> _calculateFileChecksum(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return null;
      final bytes = await file.readAsBytes();
      return sha256.convert(bytes).toString();
    } catch (e) {
      final buffer = StringBuffer()
        ..writeWarning('Could not calculate checksum for $filePath: $e');
      print(buffer.toString());
      return null;
    }
  }

  Future<TapsterConfig> _configureTarget(
    TapsterConfig config,
    String target,
    String? githubUsername,
  ) async {
    switch (target) {
      case 'homebrew/formula':
        final f = await _askFormula(config, githubUsername);
        return config.copyWith(formula: f);
      case 'homebrew/cask':
        final c = await _askCask(config, githubUsername);
        return config.copyWith(cask: c);
      case 'scoop':
        final s = await _askScoop(config, githubUsername);
        return config.copyWith(scoop: s);
      default:
        return config;
    }
  }

  Future<String?> _getGithubUsername() async {
    try {
      final result = await Process.run('gh', ['api', 'user']);
      if (result.exitCode == 0) {
        final output = result.stdout as String;
        final match = RegExp(r'"login":\s*"([^"]+)"').firstMatch(output);
        if (match != null) return match.group(1);
      }
    } catch (_) {}

    try {
      final result = await Process.run('git', [
        'config',
        '--global',
        'github.user',
      ]);
      if (result.exitCode == 0) {
        final username = (result.stdout as String).trim();
        if (username.isNotEmpty) return username;
      }
    } catch (_) {}

    try {
      final result = await Process.run('git', [
        'config',
        '--global',
        'user.name',
      ]);
      if (result.exitCode == 0) {
        final username = (result.stdout as String).trim();
        if (username.isNotEmpty) return username;
      }
    } catch (_) {}

    return null;
  }

  // ── Target configuration ───────────────────────────────────────

  bool _isTargetConfigured(TapsterConfig config, String target) {
    switch (target) {
      case 'homebrew/formula':
        return config.formula != null;
      case 'homebrew/cask':
        return config.cask != null;
      case 'scoop':
        return config.scoop != null;
      default:
        return false;
    }
  }

  // ── Helpers ────────────────────────────────────────────────────

  Future<String?> _maybeCalculateChecksum(String filePath) async {
    if (await File(filePath).exists()) {
      return await _calculateFileChecksum(filePath);
    } else {
      final buffer = StringBuffer()
        ..writeWarning('Asset file not found at $filePath');
      print(buffer.toString());
      print(
        '    Checksum will be resolved from the remote release digest on publish',
      );
      return null;
    }
  }

  Future<void> _saveConfig(TapsterConfig config) async {
    try {
      final configService = ConfigService();
      await configService.saveConfig(config, '.tapster.yaml');
    } catch (e) {
      final buffer = StringBuffer()
        ..writeError('Failed to save configuration: $e');
      print(buffer.toString());
      exit(1);
    }
  }
}

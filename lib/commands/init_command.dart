import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:crypto/crypto.dart';
import 'package:tapster/models/tapster_config.dart';
import 'package:tapster/services/config_service.dart';
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
        ..writeSuccess(
          'Existing configuration loaded (version: ${config.version})',
        );
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
    final version = await _askString('Version', '1.0.0');
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
      version: version,
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
    final tap = await _askString('Tap name', '$defaultOwner/homebrew-tools');
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
    final bucket = await _askString(
      'Scoop bucket',
      '$defaultOwner/scoop-bucket',
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
        '    Checksum will be left empty — run "tapster upgrade" later to fill it',
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

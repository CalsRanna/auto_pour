import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:cli_spin/cli_spin.dart';
import 'package:tapster/models/tapster_config.dart';
import 'package:tapster/services/asset_service.dart';
import 'package:tapster/services/cask_service.dart';
import 'package:tapster/services/config_service.dart';
import 'package:tapster/services/formula_service.dart';
import 'package:tapster/services/git_service.dart';
import 'package:tapster/services/github_service.dart';
import 'package:tapster/services/scoop_service.dart';
import 'package:tapster/utils/repo_utils.dart';
import 'package:tapster/utils/string_buffer_extensions.dart';

/// 分发：读取远端仓库的 Release 信息（tag + asset digest）→ 生成
/// manifest（formula/cask/scoop）→ 写入用户设置的托管仓库。
///
/// 被发布仓库自己的 CI 负责构建、打 tag、创建 Release、上传 asset；
/// tapster 只负责分发，Release 创建/上传不属于 tapster。
class PublishCommand extends Command {
  @override
  final name = 'publish';

  @override
  final description =
      'Generate distribution artifacts and push them to hosting repos';

  PublishCommand() {
    argParser.addOption(
      'version',
      help: 'Release version (defaults to the latest remote release tag)',
    );
    argParser.addOption(
      'output',
      abbr: 'o',
      help: 'Output directory for generated artifacts',
      defaultsTo: 'dist',
    );
    argParser.addFlag(
      'dry-run',
      help: 'Generate artifacts only, do not push to hosting repos',
      negatable: false,
    );
    argParser.addMultiOption(
      'target',
      abbr: 't',
      help:
          'Target distribution(s) to publish: homebrew/formula, homebrew/cask, scoop',
      allowed: ['homebrew/formula', 'homebrew/cask', 'scoop'],
      defaultsTo: [],
    );
  }

  @override
  Future<void> run() async {
    if (argResults == null) return;

    try {
      // Load configuration
      final spinner = CliSpin()..start();
      final config = await ConfigService().loadConfig(null);
      spinner.stop();

      final buffer = StringBuffer()
        ..writeSuccess('Configuration loaded (.tapster.yaml)');
      print(buffer.toString());

      final dryRun = argResults!['dry-run'] as bool;

      // Fetch remote release info (authoritative tag + asset digests)
      final repoString = parseRepoString(config.repository);
      final release = await GitHubService()
          .fetchLatestRelease(repoString.$1, repoString.$2);

      // Resolve release version: --version > remote release tag > local git tag
      final version = await _resolveVersion(config, release);

      // Determine which targets to publish
      final selectedTargets = argResults!['target'] as List<String>;
      final publishFormula = _shouldPublish(
        'homebrew/formula',
        selectedTargets,
        config.formula != null,
      );
      final publishCask = _shouldPublish(
        'homebrew/cask',
        selectedTargets,
        config.cask != null,
      );
      final publishScoop = _shouldPublish(
        'scoop',
        selectedTargets,
        config.scoop != null,
      );

      if (!publishFormula && !publishCask && !publishScoop) {
        final warn = StringBuffer()
          ..writeWarning('No distribution target selected');
        print(warn.toString());
        print('    Nothing to publish.');
        print('    Configure a target first: tapster init -t <target>');
        exit(1);
      }

      if (release == null) {
        final warn = StringBuffer()
          ..writeWarning(
            'No remote release found for ${repoString.$1}/${repoString.$2}',
          );
        print(warn.toString());
        print('    Checksums will fall back to config or local assets.');
        print('    The hosting repo CI should create the release first.');
      } else {
        print(
          '    Remote release: ${release.tagName} '
          '(${release.assetDigests.length} asset(s) with digest)',
        );
      }

      final outputDir = argResults!['output'] as String;
      final buffer2 = StringBuffer()
        ..writeBullet(
          '${dryRun ? 'Generating (dry run)' : 'Publishing'} version $version',
        );
      print(buffer2.toString());

      // Generate artifacts
      final results = <String, String>{};
      if (publishFormula && config.formula != null) {
        final formula = await FormulaService().generateFormula(
          config,
          await _withFormulaChecksum(
            config.formula!,
            release,
            config.formula!.asset,
          ),
          version: version,
        );
        final path = '$outputDir/Formula/${config.name}.rb';
        await _writeArtifact(path, formula);
        results['homebrew/formula'] = path;
      }

      if (publishCask && config.cask != null) {
        final cask = await CaskService().generateCask(
          config,
          await _withCaskChecksum(
            config.cask!,
            release,
            config.cask!.asset,
          ),
          version: version,
        );
        final path = '$outputDir/Casks/${config.name}.rb';
        await _writeArtifact(path, cask);
        results['homebrew/cask'] = path;
      }

      if (publishScoop && config.scoop != null) {
        final manifest = await ScoopService().generateScoopManifest(
          config,
          await _withScoopChecksum(
            config.scoop!,
            release,
            config.scoop!.asset,
          ),
          version: version,
        );
        final path = '$outputDir/${config.name}.json';
        await _writeArtifact(path, manifest);
        results['scoop'] = path;
      }

      // Push to hosting repos (unless dry run)
      if (dryRun) {
        print('');
        final dry = StringBuffer()
          ..writeWarning('Dry run complete — nothing was pushed');
        print(dry.toString());
        for (final entry in results.entries) {
          print('    Would push ${entry.key}: ${entry.value}');
        }
      } else {
        await _pushResults(config, results, version);
        print('');
        final success = StringBuffer()
          ..writeSuccess('Distribution completed successfully!');
        print(success.toString());
        for (final entry in results.entries) {
          print('    ${entry.key}: ${entry.value}');
        }
      }
    } catch (e) {
      final buffer = StringBuffer()..writeErrorBullet('Publish failed');
      print(buffer.toString());
      print('    $e');
      exit(1);
    }
  }

  /// 解析发布版本：`--version` > 远端最新 release tag > 本地 git tag。
  Future<String> _resolveVersion(
    TapsterConfig config,
    ReleaseInfo? release,
  ) async {
    final explicit = argResults!['version'] as String?;
    if (explicit != null && explicit.isNotEmpty) {
      // 配置 version 可选（版本来自远端 Release）；仅在配置显式提供时对比
      if (config.version != null && explicit != config.version) {
        final buffer = StringBuffer()
          ..writeWarning(
            'Version $explicit differs from config version ${config.version}',
          );
        print(buffer.toString());
      }
      return explicit;
    }

    if (release != null) {
      return GitService.stripVersionPrefix(release.tagName);
    }

    final localTag = await GitService().resolveCurrentTag();
    if (localTag != null) {
      final buffer = StringBuffer()
        ..writeWarning(
          'No remote release found, falling back to local git tag $localTag',
        );
      print(buffer.toString());
      return localTag;
    }

    throw Exception(
      'No release found for ${parseRepoString(config.repository).$1}/'
      '${parseRepoString(config.repository).$2} and no local git tag. '
      'Let the hosting repo CI create the release, or pass --version.',
    );
  }

  /// 解析目标的 SHA256：远端 asset digest > 配置预置 > 本地 asset 计算。
  ///
  /// 生成服务读 `config.*.checksum` 非空时不再触碰本地 asset，
  /// 因此这里把解析结果写回子配置。
  Future<FormulaConfig> _withFormulaChecksum(
    FormulaConfig formula,
    ReleaseInfo? release,
    String assetPath,
  ) async {
    final checksum = await _resolveChecksum(
      release: release,
      assetPath: assetPath,
      configuredChecksum: formula.checksum,
      targetLabel: 'formula',
    );
    return formula.copyWith(checksum: checksum);
  }

  Future<CaskConfig> _withCaskChecksum(
    CaskConfig cask,
    ReleaseInfo? release,
    String assetPath,
  ) async {
    final checksum = await _resolveChecksum(
      release: release,
      assetPath: assetPath,
      configuredChecksum: cask.checksum,
      targetLabel: 'cask',
    );
    return cask.copyWith(checksum: checksum);
  }

  Future<ScoopConfig> _withScoopChecksum(
    ScoopConfig scoop,
    ReleaseInfo? release,
    String assetPath,
  ) async {
    final checksum = await _resolveChecksum(
      release: release,
      assetPath: assetPath,
      configuredChecksum: scoop.checksum,
      targetLabel: 'scoop',
    );
    return scoop.copyWith(checksum: checksum);
  }

  Future<String> _resolveChecksum({
    required ReleaseInfo? release,
    required String assetPath,
    required String? configuredChecksum,
    required String targetLabel,
  }) async {
    // 1. 远端 digest（按 asset 文件名匹配）——权威，与已发布 asset 一致
    final assetName = assetPath.split('/').last;
    if (release != null) {
      final digest = release.assetDigests[assetName];
      if (digest != null) return digest;
    }

    // 2. 配置预置
    if (configuredChecksum != null && configuredChecksum.isNotEmpty) {
      return configuredChecksum;
    }

    // 3. 本地 asset 计算
    final assetFile = File(assetPath);
    if (await assetFile.exists()) {
      final info = await AssetService().getAssetInfo(assetPath);
      return info.checksum;
    }

    throw Exception(
      'No checksum available for $targetLabel: no remote digest for '
      '$assetName, no configured checksum, and no local asset at $assetPath.',
    );
  }

  /// 推送 manifest 到各托管仓库。
  Future<void> _pushResults(
    TapsterConfig config,
    Map<String, String> results,
    String version,
  ) async {
    final githubService = GitHubService();
    final message = 'Add ${config.name} $version';

    if (results.containsKey('homebrew/formula')) {
      final repo = resolveTapRepo(config.formula!.tap);
      await githubService.pushFile(
        owner: repo.$1,
        repo: repo.$2,
        path: 'Formula/${config.name}.rb',
        content: File(results['homebrew/formula']!).readAsStringSync(),
        message: message,
      );
      final buffer = StringBuffer()
        ..writeSuccess('Formula pushed to ${repo.$1}/${repo.$2}');
      print(buffer.toString());
      print('    Formula/${config.name}.rb');
    }

    if (results.containsKey('homebrew/cask')) {
      final repo = resolveTapRepo(config.cask!.tap);
      await githubService.pushFile(
        owner: repo.$1,
        repo: repo.$2,
        path: 'Casks/${config.name}.rb',
        content: File(results['homebrew/cask']!).readAsStringSync(),
        message: message,
      );
      final buffer = StringBuffer()
        ..writeSuccess('Cask pushed to ${repo.$1}/${repo.$2}');
      print(buffer.toString());
      print('    Casks/${config.name}.rb');
    }

    if (results.containsKey('scoop')) {
      final bucket = config.scoop!.bucket;
      final parts = bucket.split('/');
      if (parts.length != 2) {
        throw Exception('Invalid scoop bucket: $bucket (expected owner/bucket)');
      }
      await githubService.pushFile(
        owner: parts[0],
        repo: parts[1],
        path: '${config.name}.json',
        content: File(results['scoop']!).readAsStringSync(),
        message: message,
      );
      final buffer = StringBuffer()
        ..writeSuccess('Scoop manifest pushed to $bucket');
      print(buffer.toString());
      print('    ${config.name}.json');
    }
  }

  Future<void> _writeArtifact(String path, String content) async {
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsString(content);
  }

  bool _shouldPublish(String target, List<String> selected, bool isConfigured) {
    if (selected.isEmpty) return isConfigured;
    return selected.contains(target) && isConfigured;
  }
}

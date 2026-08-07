import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:cli_spin/cli_spin.dart';
import 'package:tapster/models/tapster_config.dart';
import 'package:tapster/services/cask_service.dart';
import 'package:tapster/services/config_service.dart';
import 'package:tapster/services/formula_service.dart';
import 'package:tapster/services/git_service.dart';
import 'package:tapster/services/scoop_service.dart';
import 'package:tapster/utils/string_buffer_extensions.dart';

/// 生成分发产物（formula/cask/scoop manifest）到本地目录。
///
/// tapster 只做分发——不创建 Release、不上传 asset、不推送任何仓库。
/// 这些执行动作由 CI 完成，本命令只产出 manifest 文件供 CI 推送。
class PublishCommand extends Command {
  @override
  final name = 'publish';

  @override
  final description =
      'Generate distribution artifacts (formula/cask/scoop manifests)';

  PublishCommand() {
    argParser.addOption(
      'version',
      help: 'Release version (defaults to the latest git tag)',
    );
    argParser.addOption(
      'output',
      abbr: 'o',
      help: 'Output directory for generated artifacts',
      defaultsTo: 'dist',
    );
    argParser.addMultiOption(
      'target',
      abbr: 't',
      help:
          'Target distribution(s) to generate: homebrew/formula, homebrew/cask, scoop',
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
      final configService = ConfigService();
      final config = await configService.loadConfig(null);
      spinner.stop();

      final buffer = StringBuffer()
        ..writeSuccess(
          'Configuration loaded (.tapster.yaml, version: ${config.version})',
        );
      print(buffer.toString());

      // Resolve release version (git tag by default, --version overrides)
      final version = await _resolveVersion(config);

      // Determine which targets to generate
      final selectedTargets = argResults!['target'] as List<String>;
      final generateFormula = _shouldGenerate(
        'homebrew/formula',
        selectedTargets,
        config.formula != null,
      );
      final generateCask = _shouldGenerate(
        'homebrew/cask',
        selectedTargets,
        config.cask != null,
      );
      final generateScoop = _shouldGenerate(
        'scoop',
        selectedTargets,
        config.scoop != null,
      );

      if (!generateFormula && !generateCask && !generateScoop) {
        final warn = StringBuffer()
          ..writeWarning('No distribution target selected');
        print(warn.toString());
        print('    Nothing to generate.');
        print('    Configure a target first: tapster init -t <target>');
        exit(1);
      }

      // Generate artifacts
      final outputDir = argResults!['output'] as String;
      final buffer2 = StringBuffer()
        ..writeBullet('Generating distribution artifacts to $outputDir');
      print(buffer2.toString());
      print('    Version: $version');

      final results = <String, String>{};
      if (generateFormula && config.formula != null) {
        final formula = await FormulaService().generateFormula(
          config,
          config.formula!,
          version: version,
        );
        final path = '$outputDir/Formula/${config.name}.rb';
        await _writeArtifact(path, formula);
        results['Homebrew formula'] = path;
      }

      if (generateCask && config.cask != null) {
        final cask = await CaskService().generateCask(
          config,
          config.cask!,
          version: version,
        );
        final path = '$outputDir/Casks/${config.name}.rb';
        await _writeArtifact(path, cask);
        results['Homebrew cask'] = path;
      }

      if (generateScoop && config.scoop != null) {
        final manifest = await ScoopService().generateScoopManifest(
          config,
          config.scoop!,
          version: version,
        );
        final path = '$outputDir/${config.name}.json';
        await _writeArtifact(path, manifest);
        results['Scoop manifest'] = path;
      }

      // Summary
      print('');
      final success = StringBuffer()
        ..writeSuccess('Distribution artifacts generated successfully!');
      print(success.toString());
      print('    Version: $version');
      for (final entry in results.entries) {
        print('    ${entry.key}: ${entry.value}');
      }
      print('');
      print('    Push these files to their target repositories from CI:');
      for (final entry in results.entries) {
        print('      ${entry.value}');
      }
    } catch (e) {
      final buffer = StringBuffer()..writeErrorBullet('Publish failed');
      print(buffer.toString());
      print('    $e');
      exit(1);
    }
  }

  /// 解析发布版本：`--version` 优先，否则取最近 git tag。
  Future<String> _resolveVersion(TapsterConfig config) async {
    final explicit = argResults!['version'] as String?;
    if (explicit != null && explicit.isNotEmpty) {
      if (explicit != config.version) {
        final buffer = StringBuffer()
          ..writeWarning(
            'Version $explicit differs from config version ${config.version}',
          );
        print(buffer.toString());
        print('    Using $explicit for artifact generation');
      }
      return explicit;
    }

    final gitService = GitService();
    final tagVersion = await gitService.resolveCurrentTag();
    if (tagVersion == null) {
      throw Exception(
        'No git tag found. Create a tag first (git tag v1.0.0) '
        'or pass --version explicitly.',
      );
    }

    if (tagVersion != config.version) {
      final buffer = StringBuffer()
        ..writeWarning(
          'Git tag version $tagVersion differs from config version '
          '${config.version}',
        );
      print(buffer.toString());
      print('    Consider running "tapster upgrade" to sync the config');
    }
    return tagVersion;
  }

  Future<void> _writeArtifact(String path, String content) async {
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsString(content);
  }

  bool _shouldGenerate(String target, List<String> selected, bool isConfigured) {
    if (selected.isEmpty) return isConfigured;
    return selected.contains(target) && isConfigured;
  }
}

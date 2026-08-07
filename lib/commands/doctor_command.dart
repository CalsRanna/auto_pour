import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:cli_spin/cli_spin.dart';
import 'package:tapster/models/tapster_config.dart';
import 'package:tapster/services/config_service.dart';
import 'package:tapster/services/git_service.dart';
import 'package:tapster/utils/string_buffer_extensions.dart';

/// 检查配置完整性与分发产物生成能力。
///
/// 不再检查 git/gh/brew/网络环境——tapster 只做分发，
/// 发布执行（Release、上传、推送）由 CI 负责。
class DoctorCommand extends Command {
  @override
  final name = 'doctor';

  @override
  final description =
      'Check configuration and artifact generation readiness';

  DoctorCommand() {
    argParser.addFlag(
      'verbose',
      abbr: 'v',
      help: 'Show detailed diagnostic information',
      negatable: false,
    );
  }

  @override
  Future<void> run() async {
    if (argResults == null) return;

    final verbose = argResults!['verbose'] as bool;
    print('Doctor summary (to see all details, run tapster doctor -v):');

    final issues = <String>[];
    final warnings = <String>[];

    // 1. Configuration file
    final spinner = CliSpin()..start();
    TapsterConfig? config;
    try {
      config = await ConfigService().loadConfig(null);
      spinner.stop();
      final buffer = StringBuffer()
        ..writeSuccess('Configuration (.tapster.yaml)');
      print(buffer.toString());
      if (verbose) {
        print('    name: ${config.name}');
        print('    version: ${config.version}');
      }
    } catch (e) {
      spinner.stop();
      final buffer = StringBuffer()..writeError('Configuration');
      print(buffer.toString());
      print('    $e');
      issues.add('Configuration is invalid: $e');
      _displaySummary(issues, warnings);
      return;
    }

    // 2. Distribution targets
    final targets = <String, Map<String, String>>{
      if (config.formula != null)
        'formula': {
          'tap': config.formula!.tap,
          'asset': config.formula!.asset,
          'checksum': config.formula!.checksum ?? '',
        },
      if (config.cask != null)
        'cask': {
          'tap': config.cask!.tap,
          'asset': config.cask!.asset,
          'checksum': config.cask!.checksum ?? '',
        },
      if (config.scoop != null)
        'scoop': {
          'tap': config.scoop!.bucket,
          'asset': config.scoop!.asset,
          'checksum': config.scoop!.checksum ?? '',
        },
    };

    if (targets.isEmpty) {
      final buffer = StringBuffer()
        ..writeError('Distribution targets');
      print(buffer.toString());
      print('    No target configured — run "tapster init -t <target>"');
      issues.add('No distribution target configured');
    } else {
      final buffer = StringBuffer()
        ..writeSuccess(
          'Distribution targets (${targets.length}): '
          '${targets.keys.join(', ')}',
        );
      print(buffer.toString());
    }

    // 3. Checksum availability for each target
    for (final entry in targets.entries) {
      await _checkChecksumAvailability(
        entry.key,
        entry.value['asset']!,
        entry.value['checksum']!,
        verbose,
        issues,
        warnings,
      );
    }

    // 4. Git tag (publish resolves the version from tags)
    await _checkGitTag(verbose, warnings);

    // 5. Output directory writability
    await _checkOutputDirectory(verbose, issues);

    _displaySummary(issues, warnings);
  }

  Future<void> _checkChecksumAvailability(
    String target,
    String assetPath,
    String configuredChecksum,
    bool verbose,
    List<String> issues,
    List<String> warnings,
  ) async {
    if (configuredChecksum.isNotEmpty) {
      final buffer = StringBuffer()
        ..writeSuccess('$target: checksum configured');
      print(buffer.toString());
      if (verbose) {
        print('    ${configuredChecksum.substring(0, 16)}...');
      }
      return;
    }

    final assetFile = File(assetPath);
    if (await assetFile.exists()) {
      final buffer = StringBuffer()
        ..writeSuccess('$target: asset available ($assetPath)');
      print(buffer.toString());
      if (verbose) {
        print('    checksum will be computed from the local asset');
      }
      return;
    }

    final buffer = StringBuffer()..writeError('$target: checksum unavailable');
    print(buffer.toString());
    print(
      '    Neither a configured checksum nor a local asset: $assetPath',
    );
    print(
      '    Fix: add a checksum to .tapster.yaml, or build the asset first',
    );
    issues.add('$target has no checksum source');
  }

  Future<void> _checkGitTag(bool verbose, List<String> warnings) async {
    final gitService = GitService();
    final isRepo = await gitService.isGitRepository();
    if (!isRepo) {
      final buffer = StringBuffer()
        ..writeWarning('Git repository');
      print(buffer.toString());
      print(
        '    Not inside a git repository — publish cannot resolve the '
        'version from tags',
      );
      warnings.add('Not inside a git repository');
      return;
    }

    final tag = await gitService.resolveCurrentTag();
    if (tag == null) {
      final buffer = StringBuffer()
        ..writeWarning('Git tag');
      print(buffer.toString());
      print(
        '    No tag found on HEAD — publish requires a tag (or --version)',
      );
      print('    Fix: git tag v1.0.0 && git push origin v1.0.0');
      warnings.add('No git tag found');
      return;
    }

    final buffer = StringBuffer()..writeSuccess('Git tag ($tag)');
    print(buffer.toString());
  }

  Future<void> _checkOutputDirectory(
    bool verbose,
    List<String> issues,
  ) async {
    const outputDir = 'dist';
    final probe = File('$outputDir/.tapster-write-test');
    try {
      await probe.parent.create(recursive: true);
      await probe.writeAsString('test');
      await probe.delete();
      final buffer = StringBuffer()..writeSuccess('Output directory ($outputDir)');
      print(buffer.toString());
    } catch (e) {
      final buffer = StringBuffer()..writeError('Output directory ($outputDir)');
      print(buffer.toString());
      print('    Cannot write to $outputDir: $e');
      issues.add('Output directory is not writable: $outputDir');
    }
  }

  void _displaySummary(List<String> issues, List<String> warnings) {
    print('');
    if (issues.isEmpty && warnings.isEmpty) {
      final buffer = StringBuffer()..writeBullet('No issues found!');
      print('$buffer');
      return;
    }
    if (warnings.isNotEmpty) {
      final buffer = StringBuffer()
        ..writeWarning('${warnings.length} warning(s) found');
      print('$buffer');
    }
    if (issues.isNotEmpty) {
      final buffer = StringBuffer()
        ..writeError('${issues.length} issue(s) found');
      print('$buffer');
      exit(1);
    }
  }
}

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:cli_spin/cli_spin.dart';
import 'package:tapster/models/tapster_config.dart';
import 'package:tapster/services/config_service.dart';
import 'package:tapster/services/git_service.dart';
import 'package:tapster/services/github_service.dart';
import 'package:tapster/utils/repo_utils.dart';
import 'package:tapster/utils/string_buffer_extensions.dart';

/// 检查分发就绪状态：配置完整性、gh 认证、checksum 可得性、
/// 远端 release、git tag、输出目录。
///
/// 分发的执行（推送托管仓库）依赖本地 gh 凭据，因此 gh 是检查项之一。
class DoctorCommand extends Command {
  @override
  final name = 'doctor';

  @override
  final description = 'Check distribution readiness (config, gh, checksums)';

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
        print('    version: ${config.version ?? '-'}');
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

    // 3. gh authentication (pushing to hosting repos depends on it)
    await _checkGhAuth(verbose, issues);

    // 4. Remote release (authoritative version + asset digests)
    ReleaseInfo? release;
    if (issues.isEmpty) {
      release = await _checkRemoteRelease(
        config,
        verbose,
        issues,
        warnings,
      );
    }

    // 5. Checksum availability for each target
    for (final entry in targets.entries) {
      await _checkChecksumAvailability(
        entry.key,
        entry.value['asset']!,
        entry.value['checksum']!,
        release,
        verbose,
        issues,
        warnings,
      );
    }

    // 6. Git tag (version fallback; publish prefers the remote release)
    await _checkGitTag(verbose, warnings);

    // 7. Output directory writability
    await _checkOutputDirectory(verbose, issues);

    _displaySummary(issues, warnings);
  }

  Future<void> _checkGhAuth(bool verbose, List<String> issues) async {
    final githubService = GitHubService();
    if (await githubService.isAuthenticated()) {
      final buffer = StringBuffer()..writeSuccess('GitHub CLI (gh)');
      print(buffer.toString());
      if (verbose) {
        print('    gh is installed and authenticated');
        print('    Used to read releases and push manifests to hosting repos');
      }
    } else {
      final buffer = StringBuffer()..writeError('GitHub CLI (gh)');
      print(buffer.toString());
      print('    gh is not installed or not authenticated.');
      print('    Fix: gh auth login');
      issues.add('GitHub CLI not authenticated');
    }
  }

  Future<ReleaseInfo?> _checkRemoteRelease(
    TapsterConfig config,
    bool verbose,
    List<String> issues,
    List<String> warnings,
  ) async {
    final repoString = parseRepoString(config.repository);
    final release = await GitHubService()
        .fetchLatestRelease(repoString.$1, repoString.$2);

    if (release == null) {
      final buffer = StringBuffer()
        ..writeWarning('Remote release (${repoString.$1}/${repoString.$2})');
      print(buffer.toString());
      print('    No release found — checksums must come from config or '
          'local assets.');
      print('    The hosting repo CI should create the release first.');
      warnings.add('No remote release found');
    } else {
      final buffer = StringBuffer()
        ..writeSuccess(
          'Remote release (${release.tagName}, '
          '${release.assetDigests.length} asset(s) with digest)',
        );
      print(buffer.toString());
      if (verbose) {
        for (final entry in release.assetDigests.entries) {
          print('    ${entry.key}: ${entry.value.substring(0, 16)}...');
        }
      }
    }
    return release;
  }

  Future<void> _checkChecksumAvailability(
    String target,
    String assetPath,
    String configuredChecksum,
    ReleaseInfo? release,
    bool verbose,
    List<String> issues,
    List<String> warnings,
  ) async {
    final assetName = assetPath.split('/').last;

    // 1. Remote digest
    final remoteDigest = release?.assetDigests[assetName];
    if (remoteDigest != null) {
      final buffer = StringBuffer()
        ..writeSuccess('$target: checksum from remote release');
      print(buffer.toString());
      if (verbose) {
        print('    ${remoteDigest.substring(0, 16)}...');
      }
      return;
    }

    // 2. Configured checksum
    if (configuredChecksum.isNotEmpty) {
      final buffer = StringBuffer()
        ..writeSuccess('$target: checksum configured');
      print(buffer.toString());
      if (verbose) {
        print('    ${configuredChecksum.substring(0, 16)}...');
      }
      return;
    }

    // 3. Local asset
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
    print('    No remote digest for $assetName, no configured checksum, '
        'and no local asset at $assetPath.');
    print('    Fix: publish a release first, or add a checksum to '
        '.tapster.yaml');
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
        '    Not inside a git repository — version will come from the '
        'remote release only',
      );
      warnings.add('Not inside a git repository');
      return;
    }

    final tag = await gitService.resolveCurrentTag();
    if (tag == null) {
      final buffer = StringBuffer()
        ..writeWarning('Git tag');
      print(buffer.toString());
      print('    No tag found on HEAD — publish will use the remote release '
          'tag (or --version)');
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
      final buffer = StringBuffer()
        ..writeSuccess('Output directory ($outputDir)');
      print(buffer.toString());
    } catch (e) {
      final buffer = StringBuffer()
        ..writeError('Output directory ($outputDir)');
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

import 'package:args/command_runner.dart';
import 'package:cli_spin/cli_spin.dart';
import 'package:tapster/services/dependency_service.dart';
import 'package:tapster/utils/string_buffer_extensions.dart';

class DoctorCommand extends Command {
  @override
  final name = 'doctor';

  @override
  final description = 'Check system environment for Homebrew publishing';

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

    await _runNormalDoctor(verbose);
  }

  Future<void> _checkAndDisplay(
    String component,
    bool verbose,
    Map<String, int> issuesCount,
    DependencyService dependencyService,
  ) async {
    final spinner = CliSpin()..start();

    Map<String, dynamic> result;

    try {
      result = await dependencyService.checkDoctorComponent(component);
    } catch (e) {
      result = <String, dynamic>{
        'valid': false,
        'issues': ['Failed to check $component: $e'],
      };
    } finally {
      spinner.stop();
    }

    // Count issues
    final issueCount = (result['issues'] as List).length;
    issuesCount[component] = issueCount;

    // Display the result immediately
    _displayComponentResult(component, result, verbose);
  }

  void _displayComponentResult(
    String component,
    Map<String, dynamic> result,
    bool verbose,
  ) {
    switch (component) {
      case 'git':
        if (result['valid'] && (result['issues'] as List).isEmpty) {
          final buffer = StringBuffer()
            ..writeSuccess('Git (${result['version']})');
          print(buffer.toString());
          if (verbose) {
            final buffer2 = StringBuffer()
              ..writeBullet('    Git ${result['version']}');
            print(buffer2.toString());
            final buffer3 = StringBuffer()
              ..writeBullet('    User config: configured');
            print(buffer3.toString());
          }
        } else {
          final buffer = StringBuffer()..writeWarning('Git');
          print(buffer.toString());
          if (verbose) {
            print('    ${result['version']}');
            for (final issue in result['issues']) {
              print('    $issue');
            }
            if (result['issues'].any((issue) => issue.contains('config'))) {
              print('    Fix: Set git config --global user.name "Your Name"');
              print(
                '          git config --global user.email "your.email@example.com"',
              );
            }
          }
        }
        break;

      case 'github':
        if (result['valid'] && (result['issues'] as List).isEmpty) {
          final version = result['version'] as String;
          final cleanVersion = version.split('\n').first;
          final buffer = StringBuffer()
            ..writeSuccess('GitHub CLI ($cleanVersion)');
          print(buffer.toString());
          if (verbose) {
            final buffer2 = StringBuffer()..writeBullet('    gh $cleanVersion');
            print(buffer2.toString());
            if (result['authenticated'] == true) {
              final buffer3 = StringBuffer()
                ..writeBullet('    GitHub CLI: authenticated');
              print(buffer3.toString());
              if (result['username'] != null) {
                final buffer4 = StringBuffer()
                  ..writeBullet('    Account: ${result['username']}');
                print(buffer4.toString());
              }
              if (result['auth_method'] != null) {
                final buffer5 = StringBuffer()
                  ..writeBullet('    Auth method: ${result['auth_method']}');
                print(buffer5.toString());
              }
            }
            if (result['api_access'] == true) {
              final buffer6 = StringBuffer()
                ..writeBullet('    GitHub API: accessible');
              print(buffer6.toString());
            }
          }
        } else {
          final buffer = StringBuffer()..writeWarning('GitHub CLI');
          print(buffer.toString());
          if (verbose) {
            print('    ${result['version']}');
            for (final issue in result['issues']) {
              print('    $issue');
            }
            if (result['authenticated'] != true) {
              print('    Fix: gh auth login to authenticate with GitHub');
            }
          }
        }
        break;

      case 'homebrew':
        if (result['valid'] && (result['issues'] as List).isEmpty) {
          final buffer = StringBuffer()
            ..writeSuccess('Homebrew (${result['version']})');
          print(buffer.toString());
          if (verbose) {
            final buffer2 = StringBuffer()
              ..writeBullet('    Homebrew ${result['version']}');
            print(buffer2.toString());
            if (result['taps'] != null) {
              final taps = result['taps'] as List;
              final buffer3 = StringBuffer()
                ..writeBullet('    ${taps.length} taps installed');
              print(buffer3.toString());
              for (final tap in taps.take(3)) {
                final buffer4 = StringBuffer()..writeBullet('    $tap');
                print(buffer4.toString());
              }
              if (taps.length > 3) {
                final buffer5 = StringBuffer()
                  ..writeBullet('    ... and ${taps.length - 3} more');
                print(buffer5.toString());
              }
            }
          }
        } else {
          final buffer = StringBuffer()..writeWarning('Homebrew');
          print(buffer.toString());
          if (verbose) {
            print('    ${result['version']}');
            for (final issue in result['issues']) {
              print('    $issue');
            }
          }
        }
        break;

      case 'network':
        if (result['valid'] && (result['issues'] as List).isEmpty) {
          final buffer = StringBuffer()
            ..writeSuccess('Network connectivity to GitHub');
          print(buffer.toString());
          if (verbose) {
            final buffer2 = StringBuffer()
              ..writeBullet('    GitHub: accessible');
            print(buffer2.toString());
            if (result['api_accessible'] == true) {
              final buffer3 = StringBuffer()
                ..writeBullet('    GitHub API: accessible');
              print(buffer3.toString());
              if (result['rate_limit_remaining'] != null) {
                final buffer4 = StringBuffer()
                  ..writeBullet(
                    '    Rate limit: ${result['rate_limit_remaining']} remaining',
                  );
                print(buffer4.toString());
              }
            }
            if (result['ssh_working'] == true) {
              final buffer5 = StringBuffer()
                ..writeBullet('    SSH to GitHub: working');
              print(buffer5.toString());
            }
          }
        } else {
          final buffer = StringBuffer()
            ..writeWarning('Network connectivity to GitHub');
          print(buffer.toString());
          if (verbose) {
            for (final issue in result['issues']) {
              print('    $issue');
            }
          }
        }
        break;
    }
  }

  Future<void> _runNormalDoctor(bool verbose) async {
    print('Doctor summary (to see all details, run tapster doctor -v):');

    final issuesCount = <String, int>{};
    final dependencyService = DependencyService();

    // Small delay to ensure proper timing
    await Future.delayed(const Duration(milliseconds: 100));

    // Check each component with spinner and display immediately
    await _checkAndDisplay('git', verbose, issuesCount, dependencyService);
    await _checkAndDisplay('github', verbose, issuesCount, dependencyService);
    await _checkAndDisplay('homebrew', verbose, issuesCount, dependencyService);
    await _checkAndDisplay('network', verbose, issuesCount, dependencyService);

    // Summary
    final totalIssues = issuesCount.values.fold(0, (sum, count) => sum + count);
    if (totalIssues == 0) {
      final buffer = StringBuffer()..writeBullet('No issues found!');
      print('\n$buffer');
    } else {
      var message = '$totalIssues issue${totalIssues > 1 ? 's' : ''} found!';
      final buffer = StringBuffer()..writeWarning(message);
      print('\n$buffer');
    }
  }
}

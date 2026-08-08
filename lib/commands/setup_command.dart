import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:cli_spin/cli_spin.dart';
import 'package:tapster/services/config_service.dart';
import 'package:tapster/services/github_service.dart';
import 'package:tapster/utils/repo_utils.dart';
import 'package:tapster/utils/string_buffer_extensions.dart';

/// 创建分发所需的托管仓库（Homebrew tap / Scoop bucket）。
///
/// 读取配置中已配置的目标，为缺失的托管仓库执行 `gh repo create`
/// （创建用户自己的仓库，与 pushFile 同属发布侧准备；不碰被发布
/// 仓库的 Release——那是被发布仓库 CI 的职责）。已存在的仓库跳过
/// （幂等），可直接衔接 `tapster publish`。
class SetupCommand extends Command {
  @override
  final name = 'setup';

  @override
  final description =
      'Create hosting repositories (tap/bucket) for the configured targets';

  SetupCommand() {
    argParser.addMultiOption(
      'target',
      abbr: 't',
      help:
          'Target(s) to set up: homebrew/formula, homebrew/cask, scoop '
          '(defaults to all configured targets)',
      allowed: ['homebrew/formula', 'homebrew/cask', 'scoop'],
      defaultsTo: [],
    );
    argParser.addFlag(
      'dry-run',
      help: 'Show which repositories would be created without creating them',
      negatable: false,
    );
    argParser.addFlag(
      'private',
      help: 'Create private repositories (default: public)',
      negatable: false,
    );
    argParser.addFlag(
      'yes',
      abbr: 'y',
      help: 'Skip the confirmation prompt before creating repositories',
      negatable: false,
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
      final isPrivate = argResults!['private'] as bool;
      final skipConfirm = argResults!['yes'] as bool;
      final selectedTargets = argResults!['target'] as List<String>;

      // Determine which targets to set up (default: all configured)
      final targets = <(String, String, String)>[
        if (_shouldSetup('homebrew/formula', selectedTargets, config.formula != null))
          ('homebrew/formula', config.formula!.tap, ''),
        if (_shouldSetup('homebrew/cask', selectedTargets, config.cask != null))
          ('homebrew/cask', config.cask!.tap, ''),
        if (_shouldSetup('scoop', selectedTargets, config.scoop != null))
          ('scoop', '', config.scoop!.bucket),
      ];

      if (targets.isEmpty) {
        final warn = StringBuffer()
          ..writeWarning('No distribution target selected');
        print(warn.toString());
        print('    Configure a target first: tapster init -t <target>');
        exit(1);
      }

      // Resolve (owner, repo) for each target
      final repos = <(String, String, String)>[];
      for (final (target, tap, bucket) in targets) {
        String owner;
        String repo;
        if (target == 'scoop') {
          final parts = bucket.split('/');
          if (parts.length != 2) {
            throw Exception(
              'Invalid scoop bucket: $bucket (expected owner/bucket)',
            );
          }
          owner = parts[0];
          repo = parts[1];
        } else {
          final resolved = resolveTapRepo(tap);
          owner = resolved.$1;
          repo = resolved.$2;
        }
        repos.add((target, owner, repo));
      }

      if (isPrivate) {
        final warn = StringBuffer()
          ..writeWarning('Private repositories requested');
        print(warn.toString());
        print('    Note: Scoop buckets must be public to be installable.');
      }

      print('');
      final bullet = StringBuffer()
        ..writeBullet('${dryRun ? 'Would set up' : 'Setting up'} '
            '${repos.length} hosting repo(s)');
      print(bullet.toString());

      // Check existence and create missing ones
      final githubService = GitHubService();
      var created = 0;
      var existing = 0;

      for (final (target, owner, repo) in repos) {
        final fullName = '$owner/$repo';
        final exists = await githubService.repositoryExists(owner, repo);

        if (exists) {
          final buffer = StringBuffer()
            ..writeSuccess('Repository exists ($target): $fullName');
          print(buffer.toString());
          existing++;
          continue;
        }

        if (dryRun) {
          final buffer = StringBuffer()
            ..writeWarning('Would create ($target): $fullName');
          print(buffer.toString());
          continue;
        }

        // Confirm before creating a public repository
        if (!skipConfirm) {
          stdout.write('Create repository $fullName ($target)? (y/N): ');
          final input = stdin.readLineSync()?.trim().toLowerCase() ?? 'n';
          if (input != 'y' && input != 'yes') {
            final buffer = StringBuffer()
              ..writeWarning('Skipped: $fullName');
            print(buffer.toString());
            continue;
          }
        }

        await githubService.createRepository(owner, repo, public: !isPrivate);
        final buffer = StringBuffer()
          ..writeSuccess('Repository created ($target): $fullName');
        print(buffer.toString());
        created++;
      }

      // Summary
      print('');
      if (dryRun) {
        final dry = StringBuffer()
          ..writeWarning('Dry run complete — nothing was created');
        print(dry.toString());
      } else if (created > 0 || existing > 0) {
        final success = StringBuffer()
          ..writeSuccess('Setup complete: $created created, $existing existed');
        print(success.toString());
        print('    Next: tapster publish');
      }
    } catch (e) {
      final buffer = StringBuffer()..writeErrorBullet('Setup failed');
      print(buffer.toString());
      print('    $e');
      exit(1);
    }
  }

  bool _shouldSetup(String target, List<String> selected, bool isConfigured) {
    if (selected.isEmpty) return isConfigured;
    return selected.contains(target) && isConfigured;
  }
}

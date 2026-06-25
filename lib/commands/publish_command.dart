import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:cli_spin/cli_spin.dart';
import 'package:tapster/models/tapster_config.dart';
import 'package:tapster/services/cask_service.dart';
import 'package:tapster/services/config_service.dart';
import 'package:tapster/services/formula_service.dart';
import 'package:tapster/services/github_service.dart';
import 'package:tapster/services/scoop_service.dart';
import 'package:tapster/utils/string_buffer_extensions.dart';

void _displayStepFailure(String stepName, dynamic error) {
  final buffer = StringBuffer()..writeError('$stepName failed');
  print(buffer.toString());
  final buffer2 = StringBuffer()..writeErrorBullet('$error');
  print(buffer2.toString());
}

void _displayStepSuccess(String stepName, Map<String, dynamic> result) {
  switch (stepName) {
    case 'Create GitHub Release':
      final buffer = StringBuffer()
        ..writeSuccess('GitHub release created (${result['tag']})');
      print(buffer.toString());
      print('    Tag: ${result['tag']}');
      print('    Release ID: ${result['release_id']}');
      if (result['assets'] is Map<String, dynamic>) {
        final assets = result['assets'] as Map<String, dynamic>;
        if (assets.isNotEmpty) {
          print('    Assets uploaded: ${assets.length}');
          for (final assetName in assets.keys) {
            final assetInfo = assets[assetName] as Map<String, dynamic>;
            final buffer = StringBuffer()
              ..writeBullet('    $assetName (${assetInfo['size']} bytes)');
            print(buffer.toString());
          }
        }
      }
      break;

    case 'Generate Formula':
      final buffer = StringBuffer()
        ..writeSuccess(
          'Homebrew formula generated (${result['formula_file']})',
        );
      print(buffer.toString());
      final formula = result['formula'] as String;
      final lines = formula.split('\n');
      print('    Formula length: ${lines.length} lines');
      break;

    case 'Push Formula to Tap':
      final buffer = StringBuffer()
        ..writeSuccess('Homebrew tap pushed (${result['tap_repo']})');
      print(buffer.toString());
      print('    Tap repository: ${result['tap_repo']}');
      print('    Formula file: ${result['formula_file']}');
      break;

    case 'Generate Cask':
      final buffer = StringBuffer()
        ..writeSuccess('Homebrew cask generated (${result['cask_file']})');
      print(buffer.toString());
      break;

    case 'Push Cask to Tap':
      final buffer = StringBuffer()
        ..writeSuccess('Homebrew cask pushed (${result['tap_repo']})');
      print(buffer.toString());
      print('    Tap repository: ${result['tap_repo']}');
      print('    Cask file: ${result['cask_file']}');
      break;

    case 'Generate Scoop Manifest':
      final buffer = StringBuffer()
        ..writeSuccess('Scoop manifest generated (${result['manifest_file']})');
      print(buffer.toString());
      break;

    case 'Push Scoop Manifest to Bucket':
      final buffer = StringBuffer()
        ..writeSuccess('Scoop manifest pushed (${result['bucket']})');
      print(buffer.toString());
      print('    Bucket: ${result['bucket']}');
      print('    Manifest file: ${result['manifest_file']}');
      break;
  }
}

class PublishCommand extends Command {
  @override
  final name = 'publish';

  @override
  final description = 'Publish Homebrew package';

  PublishCommand() {
    argParser.addFlag(
      'force',
      abbr: 'f',
      help: 'Force overwrite existing release with the same version',
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

    // Show start message
    print('Publish summary (to see all details, run tapster publish -v):');

    try {
      // Load configuration
      final spinner = CliSpin()..start();

      final configService = ConfigService();
      final configPath = '.tapster.yaml';
      final configFile = File(configPath);

      if (!await configFile.exists()) {
        spinner.stop();
        final buffer = StringBuffer()
          ..writeError('Configuration file not found');
        print(buffer.toString());
        print('    No configuration file found at: $configPath');
        print('    Create a configuration file first: tapster init');
        print('');
        exit(1);
      }

      // Load existing configuration
      final config = await configService.loadConfig(null);
      spinner.stop();
      final buffer = StringBuffer()
        ..writeSuccess(
          'Configuration loaded ($configPath, version: ${config.version})',
        );
      print(buffer.toString());

      final force = argResults!['force'] as bool;
      await _executePublishWorkflow(force: force);
    } catch (e) {
      final buffer = StringBuffer()..writeErrorBullet('Publishing failed');
      print(buffer.toString());
      exit(1);
    }
  }

  Future<bool> _checkReleaseExists(String tagName, String repo) async {
    try {
      final result = await Process.run('gh', [
        'release',
        'view',
        tagName,
        '--repo',
        repo,
      ]);
      return result.exitCode == 0;
    } catch (e) {
      return false;
    }
  }

  List<String> _collectAssetPaths(
    TapsterConfig config,
    bool publishFormula,
    bool publishCask,
    bool publishScoop,
  ) {
    final paths = <String>[];
    if (publishFormula && config.formula != null) {
      paths.add(config.formula!.asset);
    }
    if (publishCask && config.cask != null) {
      paths.add(config.cask!.asset);
    }
    if (publishScoop && config.scoop != null) {
      paths.add(config.scoop!.asset);
    }
    return paths;
  }

  Future<void> _executePublishWorkflow({bool force = false}) async {
    try {
      final configService = ConfigService();
      final config = await configService.loadConfig(null);

      final githubService = GitHubService();

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

      // Parse repository info
      final repoUri = Uri.parse(config.repository);
      final repoParts = repoUri.path
          .split('/')
          .where((p) => p.isNotEmpty)
          .toList();
      if (repoParts.length < 2) {
        throw Exception('Invalid repository URL format');
      }
      final targetOwner = repoParts[0];
      final targetRepo = repoParts[1].replaceAll('.git', '');
      final targetRepoString = '$targetOwner/$targetRepo';

      // Step 1: Create GitHub Release (shared across all targets)
      final releaseStep = PublishStep(
        name: 'Create GitHub Release',
        description: 'Creating GitHub release with assets',
        action: () async {
          final tagName = 'v${config.version}';
          final releaseName = 'v${config.version}';
          final releaseNotes =
              'Release ${config.version}\n\n${config.description}';

          int? releaseId;

          // Check if release already exists
          final alreadyExists = await _checkReleaseExists(
            tagName,
            targetRepoString,
          );
          if (!alreadyExists || force) {
            releaseId = await githubService.createReleaseCLI(
              tagName: tagName,
              name: releaseName,
              notes: releaseNotes,
              repo: targetRepoString,
              draft: false,
              prerelease: false,
              force: force,
            );
          } else {
            final buf = StringBuffer()
              ..writeWarning('Release $tagName already exists');
            print(buf.toString());
            print('    Adding assets from current platform');
          }

          // Upload all assets that exist locally
          for (final assetPath in _collectAssetPaths(
            config,
            publishFormula,
            publishCask,
            publishScoop,
          )) {
            final assetFile = File(assetPath);
            if (await assetFile.exists()) {
              await githubService.uploadAsset(
                tagName: tagName,
                assetPath: assetPath,
                repo: targetRepoString,
              );
            } else {
              final buf = StringBuffer()
                ..writeWarningBullet(
                  'Asset not found locally, skipping upload: $assetPath',
                );
              print(buf.toString());
            }
          }

          return {'release_id': releaseId, 'tag': tagName};
        },
      );

      final steps = <PublishStep>[releaseStep];

      // Step 2: Formula (if configured and selected)
      if (publishFormula && config.formula != null) {
        final formulaService = FormulaService();
        final formulaConfig = config.formula!;
        final fullTapPath = _resolveTapPath(config, formulaConfig.tap);

        steps.add(
          PublishStep(
            name: 'Generate Formula',
            description: 'Generating Homebrew formula',
            action: () async {
              final formula = await formulaService.generateFormula(
                config,
                formulaConfig,
              );
              return {'formula': formula, 'formula_file': '${config.name}.rb'};
            },
          ),
        );

        steps.add(
          PublishStep(
            name: 'Push Formula to Tap',
            description: 'Pushing formula to tap repository',
            action: () async {
              final formula = await formulaService.generateFormula(
                config,
                formulaConfig,
              );
              await _pushRubyFileToTap(
                fullTapPath: fullTapPath,
                fileName: 'Formula/${config.name}.rb',
                content: formula,
                config: config,
              );
              return {
                'formula_file': 'Formula/${config.name}.rb',
                'tap_repo': fullTapPath,
              };
            },
          ),
        );
      }

      // Step 3: Cask (if configured and selected)
      if (publishCask && config.cask != null) {
        final caskService = CaskService();
        final caskConfig = config.cask!;
        final fullTapPath = _resolveTapPath(config, caskConfig.tap);

        steps.add(
          PublishStep(
            name: 'Generate Cask',
            description: 'Generating Homebrew cask',
            action: () async {
              await caskService.generateCask(config, caskConfig);
              return {'cask_file': '${config.name}.rb'};
            },
          ),
        );

        steps.add(
          PublishStep(
            name: 'Push Cask to Tap',
            description: 'Pushing cask to tap repository',
            action: () async {
              final cask = await caskService.generateCask(config, caskConfig);
              await _pushRubyFileToTap(
                fullTapPath: fullTapPath,
                fileName: 'Casks/${config.name}.rb',
                content: cask,
                config: config,
              );
              return {
                'cask_file': 'Casks/${config.name}.rb',
                'tap_repo': fullTapPath,
              };
            },
          ),
        );
      }

      // Step 4: Scoop (if configured and selected)
      if (publishScoop && config.scoop != null) {
        final scoopService = ScoopService();
        final scoopConfig = config.scoop!;

        steps.add(
          PublishStep(
            name: 'Generate Scoop Manifest',
            description: 'Generating Scoop manifest',
            action: () async {
              await scoopService.generateScoopManifest(config, scoopConfig);
              return {'manifest_file': '${config.name}.json'};
            },
          ),
        );

        steps.add(
          PublishStep(
            name: 'Push Scoop Manifest to Bucket',
            description: 'Pushing manifest to Scoop bucket',
            action: () async {
              final manifest = await scoopService.generateScoopManifest(
                config,
                scoopConfig,
              );
              await _pushFileToRepo(
                repoPath: scoopConfig.bucket,
                fileName: '${config.name}.json',
                content: manifest,
                config: config,
              );
              return {
                'manifest_file': '${config.name}.json',
                'bucket': scoopConfig.bucket,
              };
            },
          ),
        );
      }

      // Execute all steps
      final results = <String, dynamic>{};
      for (final step in steps) {
        final spinner = CliSpin()..start();
        step.spinner = spinner;

        try {
          final result = await step.action();
          results[step.name] = result;
          spinner.stop();
          _displayStepSuccess(step.name, result);
        } catch (e) {
          spinner.stop();
          _displayStepFailure(step.name, e);
          rethrow;
        }
      }

      print('');
      final buffer = StringBuffer()
        ..writeSuccess('Publishing completed successfully!');
      print(buffer.toString());
    } catch (e) {
      rethrow;
    }
  }

  Future<void> _pushFileToRepo({
    required String repoPath,
    required String fileName,
    required String content,
    required TapsterConfig config,
    bool isHomebrewTap = false,
  }) async {
    final parts = repoPath.split('/');
    final owner = parts[0];
    final tapName = parts[1];

    final repoName = isHomebrewTap
        ? (tapName.startsWith('homebrew-') ? tapName : 'homebrew-$tapName')
        : tapName;

    // Check if repo exists, create if not
    try {
      final checkRepo = '$owner/$repoName';
      final checkResult = await Process.run('gh', ['repo', 'view', checkRepo]);
      if (checkResult.exitCode != 0) {
        print('Creating repository: $owner/$repoName');
        final createResult = await Process.run('gh', [
          'repo',
          'create',
          checkRepo,
          '--public',
          '--add-readme',
        ]);
        if (createResult.exitCode != 0) {
          throw Exception(
            'Failed to create repository: ${createResult.stderr}',
          );
        }
      }
    } catch (e) {
      print('Could not verify repository, continuing anyway');
    }

    // Push file via GitHub API
    final encodedContent = base64Encode(utf8.encode(content));

    String? sha;
    try {
      final checkResult = await Process.run('gh', [
        'api',
        'repos/$owner/$repoName/contents/$fileName',
      ]);
      if (checkResult.exitCode == 0) {
        final fileData = jsonDecode(checkResult.stdout) as Map<String, dynamic>;
        sha = fileData['sha'] as String?;
      }
    } catch (e) {
      sha = null;
    }

    final apiArgs = [
      'api',
      '-X',
      'PUT',
      'repos/$owner/$repoName/contents/$fileName',
      '-f',
      'message=Add ${config.name} ${config.version}',
      '-f',
      'content=$encodedContent',
      '-f',
      'branch=main',
    ];

    if (sha != null) {
      apiArgs.add('-f');
      apiArgs.add('sha=$sha');
    }

    final apiResult = await Process.run('gh', apiArgs);
    if (apiResult.exitCode != 0) {
      throw Exception(
        'Failed to push file: ${apiResult.stdout}\n${apiResult.stderr}',
      );
    }
  }

  Future<void> _pushRubyFileToTap({
    required String fullTapPath,
    required String fileName,
    required String content,
    required TapsterConfig config,
  }) async {
    await _pushFileToRepo(
      repoPath: fullTapPath,
      fileName: fileName,
      content: content,
      config: config,
      isHomebrewTap: true,
    );
  }

  String _resolveTapPath(TapsterConfig config, String tap) {
    if (tap.contains('/')) return tap;
    final repoUri = Uri.parse(config.repository);
    final owner = repoUri.path.split('/').where((p) => p.isNotEmpty).first;
    return '$owner/$tap';
  }

  bool _shouldPublish(String target, List<String> selected, bool isConfigured) {
    if (selected.isEmpty) return isConfigured;
    return selected.contains(target) && isConfigured;
  }
}

class PublishStep {
  final String name;
  final String description;
  final Future<Map<String, dynamic>> Function() action;
  CliSpin? spinner;

  PublishStep({
    required this.name,
    required this.description,
    required this.action,
  });
}

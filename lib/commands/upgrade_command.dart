import 'dart:io';
import 'package:args/command_runner.dart';
import 'package:cli_spin/cli_spin.dart';
import 'package:tapster/models/tapster_config.dart';
import 'package:tapster/services/config_service.dart';
import 'package:tapster/services/asset_service.dart';
import 'package:tapster/utils/string_buffer_extensions.dart';

class UpgradeCommand extends Command {
  @override
  final name = 'upgrade';

  @override
  final description = 'Upgrade .tapster.yaml configuration file with new asset checksum and version';

  UpgradeCommand() {
    argParser.addFlag(
      'dry-run',
      abbr: 'd',
      help: 'Show what would be upgraded without making changes',
      negatable: false,
    );
    argParser.addOption(
      'config',
      abbr: 'c',
      help: 'Path to configuration file',
      defaultsTo: '.tapster.yaml',
    );
    argParser.addOption(
      'target',
      abbr: 't',
      help: 'Distribution target to upgrade: formula, cask, scoop',
      allowed: ['formula', 'cask', 'scoop'],
    );
  }

  @override
  Future<void> run() async {
    if (argResults == null) return;

    final dryRun = argResults!['dry-run'] as bool;
    final configPath = argResults!['config'] as String;

    if (dryRun) {
      print('🔍 Upgrade dry run (no changes will be made):');
    } else {
      print('🔄 Upgrading .tapster.yaml configuration:');
    }

    try {
      // Load configuration
      final spinner = CliSpin()..start();
      final configService = ConfigService();
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
      final config = await configService.loadConfig(configPath);
      spinner.stop();
      final buffer = StringBuffer()
        ..writeSuccess('Configuration loaded ($configPath, version: ${config.version})');
      print(buffer.toString());

    // Determine which target to upgrade
    final selectedTarget = argResults!['target'] as String?;
    String assetPath;
    String? currentChecksum;
    String targetLabel;

    if (selectedTarget != null) {
      targetLabel = selectedTarget;
      switch (selectedTarget) {
        case 'formula':
          if (config.formula == null) {
            final buf = StringBuffer()..writeError('Formula not configured');
            print(buf.toString());
            exit(1);
          }
          assetPath = config.formula!.asset;
          currentChecksum = config.formula!.checksum;
          break;
        case 'cask':
          if (config.cask == null) {
            final buf = StringBuffer()..writeError('Cask not configured');
            print(buf.toString());
            exit(1);
          }
          assetPath = config.cask!.asset;
          currentChecksum = config.cask!.checksum;
          break;
        case 'scoop':
          if (config.scoop == null) {
            final buf = StringBuffer()..writeError('Scoop not configured');
            print(buf.toString());
            exit(1);
          }
          assetPath = config.scoop!.asset;
          currentChecksum = config.scoop!.checksum;
          break;
        default:
          final buf = StringBuffer()..writeError('Unknown target: $selectedTarget');
          print(buf.toString());
          exit(1);
      }
    } else {
      // No target specified — use first configured
      if (config.formula != null) {
        assetPath = config.formula!.asset;
        currentChecksum = config.formula!.checksum;
        targetLabel = 'formula';
      } else if (config.cask != null) {
        assetPath = config.cask!.asset;
        currentChecksum = config.cask!.checksum;
        targetLabel = 'cask';
      } else if (config.scoop != null) {
        assetPath = config.scoop!.asset;
        currentChecksum = config.scoop!.checksum;
        targetLabel = 'scoop';
      } else {
        final buf = StringBuffer()..writeError('No distribution target configured');
        print(buf.toString());
        exit(1);
      }
    }

      // Check asset file
      final assetService = AssetService();
      final assetFile = File(assetPath);

      if (!await assetFile.exists()) {
        final buf = StringBuffer()..writeError('Asset file not found');
        print(buf.toString());
        print('    Asset file not found: $assetPath');
        exit(1);
      }

      // Get current asset info
      final assetInfo = await assetService.getAssetInfo(assetPath);
      print('    Target: $targetLabel');
      print('    Asset: $assetPath');
      print('    Size: ${assetInfo.size} bytes');
      print('    Current checksum: ${assetInfo.checksum}');

      // Compare checksums
      if (currentChecksum == assetInfo.checksum) {
        print('');
        final buffer = StringBuffer()
          ..writeWarning('Asset checksum unchanged');
        print(buffer.toString());
        print('    The asset file has not been modified since the last upgrade.');
        print('    No upgrade needed.');
        print('');
        return;
      }

      print('');
      final buffer2 = StringBuffer()
        ..writeSuccess('Asset checksum changed');
      print(buffer2.toString());
      print('    Previous checksum: ${currentChecksum ?? "none"}');
      print('    New checksum: ${assetInfo.checksum}');
      print('');

      // Generate new version suggestion
      final newVersion = _suggestNewVersion(config.version);
      print('💡 Suggested new version: $newVersion');

      // Ask for version confirmation
      print('');
      stdout.write('📝 Enter new version (or press Enter to use suggestion): ');
      final userInput = stdin.readLineSync()?.trim() ?? '';
      final finalVersion = userInput.isEmpty ? newVersion : userInput;

      // Validate version format
      if (!_isValidVersion(finalVersion)) {
        final buffer = StringBuffer()
          ..writeError('Invalid version format');
        print(buffer.toString());
        print('    Version should be in format like: 1.0.0, 1.2.3, etc.');
        print('');
        exit(1);
      }

      print('');
      print('📋 Upgrade summary:');
      print('    Version: ${config.version} → $finalVersion');
      print('    Checksum: ${currentChecksum ?? "none"} → ${assetInfo.checksum}');
      print('');

      if (dryRun) {
        final buffer = StringBuffer()
          ..writeWarning('Dry run complete');
        print(buffer.toString());
        print('    No changes were made to the configuration file.');
        print('');
        return;
      }

      // Ask for final confirmation
      stdout.write('✅ Confirm upgrade? (y/N): ');
      final confirmation = stdin.readLineSync()?.trim().toLowerCase() ?? 'n';

      if (confirmation != 'y' && confirmation != 'yes') {
        print('');
        final buffer = StringBuffer()
          ..writeWarning('Upgrade cancelled');
        print(buffer.toString());
        print('');
        return;
      }

      // Update configuration
      TapsterConfig upgradedConfig;
      switch (targetLabel) {
        case 'formula':
          upgradedConfig = config.copyWith(
            version: finalVersion,
            formula: config.formula!.copyWith(checksum: assetInfo.checksum),
          );
          break;
        case 'cask':
          upgradedConfig = config.copyWith(
            version: finalVersion,
            cask: config.cask!.copyWith(checksum: assetInfo.checksum),
          );
          break;
        case 'scoop':
          upgradedConfig = config.copyWith(
            version: finalVersion,
            scoop: config.scoop!.copyWith(checksum: assetInfo.checksum),
          );
          break;
        default:
          upgradedConfig = config.copyWith(version: finalVersion);
      }

      // Save configuration
      final saveSpinner = CliSpin()..start();
      await configService.saveConfig(upgradedConfig, configPath);
      saveSpinner.stop();

      final successBuffer = StringBuffer()
        ..writeSuccess('Configuration upgraded successfully!');
      print(successBuffer.toString());
      print('    Version: $finalVersion');
      print('    Checksum: ${assetInfo.checksum}');
      print('');
      print('🎉 You can now publish the new version with: tapster publish');

    } catch (e) {
      final buffer = StringBuffer()
        ..writeErrorBullet('Upgrade failed');
      print(buffer.toString());
      print('    $e');
      print('');
      exit(1);
    }
  }

  String _suggestNewVersion(String currentVersion) {
    try {
      final parts = currentVersion.split('.');
      if (parts.length >= 3) {
        final major = int.parse(parts[0]);
        final minor = int.parse(parts[1]);
        final patch = int.parse(parts[2]);
        return '$major.$minor.${patch + 1}';
      }
    } catch (e) {
      // If parsing fails, just append .1
      return '$currentVersion.1';
    }
    return currentVersion;
  }

  bool _isValidVersion(String version) {
    final versionRegex = RegExp(r'^\d+(\.\d+)*$');
    return versionRegex.hasMatch(version);
  }
}
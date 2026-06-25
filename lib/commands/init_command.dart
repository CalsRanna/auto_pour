import 'dart:io';
import 'package:args/command_runner.dart';
import 'package:crypto/crypto.dart';
import 'package:tapster/services/config_service.dart';
import 'package:tapster/models/tapster_config.dart';
import 'package:tapster/utils/string_buffer_extensions.dart';

class InitCommand extends Command {
  @override
  final name = 'init';

  @override
  final description = 'Create a Tapster configuration file interactively';

  InitCommand() {
    argParser.addFlag(
      'force',
      help: 'Force overwrite existing config file',
      negatable: false,
    );
  }

  @override
  Future<void> run() async {
    if (argResults == null) return;

    final force = argResults!['force'] as bool;

    print('Welcome to Tapster Configuration Generator:');

    // Check if config already exists
    final configService = ConfigService();
    final configExists = await configService.configExists(null);

    if (configExists && !force) {
      final buffer = StringBuffer()
        ..writeWarning('Configuration file .tapster.yaml already exists.');
      print(buffer.toString());
      if (!await _askBool('Overwrite existing configuration?', false)) {
        print('\nConfiguration generation cancelled.');
        return;
      }
    }

    final config = await _manualConfig();

    // Save configuration
    await _saveConfig(config);

    // Show next steps
    print('\nConfiguration file created successfully!');
  }

  Future<TapsterConfig> _manualConfig() async {
    // Project type selection
    print('\nChoose project type:');
    print('  [1] CLI tool → Homebrew Formula');
    print('  [2] macOS GUI → Homebrew Cask');
    print('  [3] Windows GUI → Scoop');
    print('  [4] Cross-platform CLI → Formula + Scoop');
    print('  [5] Cross-platform GUI → Cask + Scoop');
    final typeChoice = await _askString('Type', '1');

    // Get GitHub username for defaults
    final githubUsername = await _getGithubUsername();
    final defaultOwner = githubUsername ?? 'user';

    // Common fields
    final name = await _askString('Asset name', 'my_asset');
    final version = await _askString('Version', '1.0.0');
    final description = await _askString('Description', 'A sample Homebrew package');
    final repository = await _askString('Repository URL', 'https://github.com/$defaultOwner/$name.git');
    final license = await _askString('License', 'MIT');

    // Generate homepage from repository URL
    final homepage = repository.endsWith('.git')
        ? repository.substring(0, repository.length - 4)
        : repository;

    // Type-specific configuration
    FormulaConfig? formula;
    CaskConfig? cask;
    ScoopConfig? scoop;

    switch (typeChoice) {
      case '1':
        final binaryPath = await _askString('Binary file path', 'build/$name');
        final dependencies = await _collectDependencies();
        final tap = await _askString('Publish tap', '');
        String? checksum;
        if (await File(binaryPath).exists()) {
          checksum = await _calculateFileChecksum(binaryPath);
        } else {
          final buffer = StringBuffer()
            ..writeWarning('Binary file not found at $binaryPath');
          print(buffer.toString());
        }
        formula = FormulaConfig(
          tap: tap,
          asset: binaryPath,
          checksum: checksum,
          dependencies: dependencies,
        );
        break;

      case '2':
        final binaryPath = await _askString('App archive path (.zip)', 'build/$name.zip');
        final tap = await _askString('Cask tap', '');
        final appName = await _askString('App name (e.g. MyApp.app)', '$name.app');
        String? checksum;
        if (await File(binaryPath).exists()) {
          checksum = await _calculateFileChecksum(binaryPath);
        } else {
          final buffer = StringBuffer()
            ..writeWarning('Asset file not found at $binaryPath');
          print(buffer.toString());
        }
        cask = CaskConfig(
          tap: tap,
          asset: binaryPath,
          appName: appName,
          checksum: checksum,
        );
        break;

      case '3':
        final binaryPath = await _askString('App archive path (.zip)', 'build/$name.zip');
        final bucket = await _askString('Scoop bucket', '$defaultOwner/scoop-bucket');
        final arch = await _askString('Architecture', '64bit');
        String? checksum;
        if (await File(binaryPath).exists()) {
          checksum = await _calculateFileChecksum(binaryPath);
        } else {
          final buffer = StringBuffer()
            ..writeWarning('Asset file not found at $binaryPath');
          print(buffer.toString());
        }
        scoop = ScoopConfig(
          bucket: bucket,
          asset: binaryPath,
          arch: arch,
          checksum: checksum,
        );
        break;

      case '4':
        // macOS/Linux — Formula
        final formulaAsset = await _askString('macOS/Linux binary path', 'build/macos/$name');
        final dependencies = await _collectDependencies();
        final tap = await _askString('Formula tap', '');
        String? formulaChecksum;
        if (await File(formulaAsset).exists()) {
          formulaChecksum = await _calculateFileChecksum(formulaAsset);
        } else {
          final buffer = StringBuffer()
            ..writeWarning('Formula asset file not found at $formulaAsset');
          print(buffer.toString());
        }
        formula = FormulaConfig(
          tap: tap,
          asset: formulaAsset,
          checksum: formulaChecksum,
          dependencies: dependencies,
        );
        // Windows — Scoop
        final winAsset = await _askString('Windows app archive path (.zip)', 'build/windows/$name.zip');
        final bucket = await _askString('Scoop bucket', '$defaultOwner/scoop-bucket');
        final arch = await _askString('Architecture', '64bit');
        String? winChecksum;
        if (await File(winAsset).exists()) {
          winChecksum = await _calculateFileChecksum(winAsset);
        } else {
          final buffer = StringBuffer()
            ..writeWarning('Windows asset file not found at $winAsset');
          print(buffer.toString());
        }
        scoop = ScoopConfig(
          bucket: bucket,
          asset: winAsset,
          arch: arch,
          checksum: winChecksum,
        );
        break;

      case '5':
        // macOS
        final macAsset = await _askString('macOS app archive path (.zip)', 'build/macos/$name.zip');
        final caskTap = await _askString('Cask tap', '');
        final appName = await _askString('macOS App name (e.g. MyApp.app)', '$name.app');
        String? macChecksum;
        if (await File(macAsset).exists()) {
          macChecksum = await _calculateFileChecksum(macAsset);
        } else {
          final buffer = StringBuffer()
            ..writeWarning('macOS asset file not found at $macAsset');
          print(buffer.toString());
        }
        cask = CaskConfig(
          tap: caskTap,
          asset: macAsset,
          appName: appName,
          checksum: macChecksum,
        );
        // Windows
        final winAsset = await _askString('Windows app archive path (.zip)', 'build/windows/$name.zip');
        final bucket = await _askString('Scoop bucket', '$defaultOwner/scoop-bucket');
        final arch = await _askString('Architecture', '64bit');
        String? winChecksum;
        if (await File(winAsset).exists()) {
          winChecksum = await _calculateFileChecksum(winAsset);
        } else {
          final buffer = StringBuffer()
            ..writeWarning('Windows asset file not found at $winAsset');
          print(buffer.toString());
        }
        scoop = ScoopConfig(
          bucket: bucket,
          asset: winAsset,
          arch: arch,
          checksum: winChecksum,
        );
        break;

      default:
        final binaryPath = await _askString('Binary file path', 'build/$name');
        final dependencies = await _collectDependencies();
        final tap = await _askString('Publish tap', '');
        String? checksum;
        if (await File(binaryPath).exists()) {
          checksum = await _calculateFileChecksum(binaryPath);
        } else {
          final buffer = StringBuffer()
            ..writeWarning('Binary file not found at $binaryPath');
          print(buffer.toString());
        }
        formula = FormulaConfig(
          tap: tap,
          asset: binaryPath,
          checksum: checksum,
          dependencies: dependencies,
        );
        break;
    }

    return TapsterConfig(
      name: name,
      version: version,
      description: description,
      homepage: homepage,
      repository: repository,
      license: license,
      formula: formula,
      cask: cask,
      scoop: scoop,
    );
  }

  Future<List<String>> _collectDependencies() async {
    final depsInput = await _askString(
      'Dependencies (comma-separated, leave empty if none)',
      '',
    );

    final deps = <String>[];
    if (depsInput.trim().isNotEmpty) {
      deps.addAll(
        depsInput
            .split(',')
            .map((dep) => dep.trim())
            .where((dep) => dep.isNotEmpty),
      );
    }

    return deps;
  }

  Future<String?> _getGithubUsername() async {
    try {
      // Try GitHub CLI first
      final result = await Process.run('gh', ['api', 'user']);
      if (result.exitCode == 0) {
        final output = result.stdout as String;
        final match = RegExp(r'"login":\s*"([^"]+)"').firstMatch(output);
        if (match != null) {
          return match.group(1);
        }
      }
    } catch (e) {
      // GitHub CLI not available or failed
    }

    try {
      // Try git config
      final result = await Process.run('git', [
        'config',
        '--global',
        'github.user',
      ]);
      if (result.exitCode == 0) {
        final username = (result.stdout as String).trim();
        if (username.isNotEmpty) {
          return username;
        }
      }
    } catch (e) {
      // Git config not available
    }

    try {
      // Try git user.name as fallback
      final result = await Process.run('git', [
        'config',
        '--global',
        'user.name',
      ]);
      if (result.exitCode == 0) {
        final username = (result.stdout as String).trim();
        if (username.isNotEmpty) {
          return username;
        }
      }
    } catch (e) {
      // Git config not available
    }

    return null;
  }

  Future<String?> _calculateFileChecksum(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        return null;
      }

      final bytes = await file.readAsBytes();
      final digest = sha256.convert(bytes);
      return digest.toString();
    } catch (e) {
      final buffer = StringBuffer()
        ..writeWarning('Could not calculate checksum for $filePath: $e');
      print(buffer.toString());
      return null;
    }
  }

  Future<void> _saveConfig(TapsterConfig config) async {
    try {
      final configService = ConfigService();
      await configService.saveConfig(config, '.tapster.yaml');
      final buffer = StringBuffer()
        ..writeSuccess('Configuration saved to .tapster.yaml');
      print(buffer.toString());
    } catch (e) {
      final buffer = StringBuffer()
        ..writeError('Failed to save configuration: $e');
      print(buffer.toString());
      exit(1);
    }
  }

  Future<String> _askString(String prompt, String defaultValue) async {
    if (defaultValue.trim().isEmpty) {
      stdout.write('$prompt: ');
    } else {
      // Use ansix for gray default value
      final buffer = StringBuffer()
        ..write('$prompt: ')
        ..writeGreyDefault('[$defaultValue]')
        ..write(' ');
      stdout.write(buffer.toString());
    }
    final input = stdin.readLineSync()?.trim() ?? '';
    return input.isEmpty ? defaultValue : input;
  }

  Future<bool> _askBool(String prompt, bool defaultValue) async {
    final defaultStr = defaultValue ? 'Y/n' : 'y/N';
    // Use ansix for gray default value
    final buffer = StringBuffer()
      ..write('$prompt: ')
      ..writeGreyDefault('[$defaultStr]')
      ..write(' ');
    stdout.write(buffer.toString());
    final input = stdin.readLineSync()!.trim().toLowerCase();

    if (input.isEmpty) return defaultValue;
    return input == 'y' || input == 'yes';
  }
}

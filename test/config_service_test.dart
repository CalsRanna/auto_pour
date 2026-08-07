import 'dart:io';

import 'package:tapster/models/tapster_config.dart';
import 'package:tapster/services/config_service.dart';
import 'package:test/test.dart';

TapsterConfig _sampleConfig() {
  return TapsterConfig(
    name: 'my-cli',
    version: '1.2.3',
    description: 'A test CLI tool',
    homepage: 'https://github.com/owner/my-cli',
    repository: 'https://github.com/owner/my-cli.git',
    license: 'MIT',
    formula: FormulaConfig(
      tap: 'owner/homebrew-tools',
      asset: 'build/my-cli',
      checksum: 'a' * 64,
      dependencies: ['openssl'],
    ),
  );
}

void main() {
  group('ConfigService save/load round-trip', () {
    late Directory tempDir;
    late String configPath;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('tapster_test');
      configPath = '${tempDir.path}/.tapster.yaml';
    });

    tearDown(() async {
      await tempDir.delete(recursive: true);
    });

    test('round-trips all top-level and formula fields', () async {
      final service = ConfigService();
      await service.saveConfig(_sampleConfig(), configPath);

      final loaded = await service.loadConfig(configPath);
      expect(loaded.name, 'my-cli');
      expect(loaded.version, '1.2.3');
      expect(loaded.description, 'A test CLI tool');
      expect(loaded.homepage, 'https://github.com/owner/my-cli');
      expect(loaded.repository, 'https://github.com/owner/my-cli.git');
      expect(loaded.license, 'MIT');
      expect(loaded.formula, isNotNull);
      expect(loaded.formula!.tap, 'owner/homebrew-tools');
      expect(loaded.formula!.asset, 'build/my-cli');
      expect(loaded.formula!.checksum, 'a' * 64);
      expect(loaded.formula!.dependencies, ['openssl']);
    });

    test('round-trips cask and scoop fields', () async {
      final config = _sampleConfig().copyWith(
        formula: null,
        removeFormula: true,
        cask: CaskConfig(
          tap: 'owner/homebrew-cask',
          asset: 'build/macos/my-app.zip',
          appName: 'MyApp.app',
          checksum: 'b' * 64,
        ),
        scoop: ScoopConfig(
          bucket: 'owner/scoop-bucket',
          asset: 'build/windows/my-app.zip',
          arch: 'arm64',
          checksum: 'c' * 64,
          shortcuts: ['MyApp'],
        ),
      );

      final service = ConfigService();
      await service.saveConfig(config, configPath);

      final loaded = await service.loadConfig(configPath);
      expect(loaded.formula, isNull);
      expect(loaded.cask!.tap, 'owner/homebrew-cask');
      expect(loaded.cask!.appName, 'MyApp.app');
      expect(loaded.scoop!.bucket, 'owner/scoop-bucket');
      expect(loaded.scoop!.arch, 'arm64');
      expect(loaded.scoop!.shortcuts, ['MyApp']);
    });

    test('migrates legacy flat format to nested formula', () async {
      final legacy = '''
name: my-cli
version: 1.0.0
description: A test CLI tool
homepage: https://github.com/owner/my-cli
repository: https://github.com/owner/my-cli.git
license: MIT
tap: owner/homebrew-tools
asset: build/my-cli
checksum: ddd
dependencies:
  - openssl
''';
      File(configPath).writeAsStringSync(legacy);

      final loaded = await ConfigService().loadConfig(configPath);
      expect(loaded.formula, isNotNull);
      expect(loaded.formula!.tap, 'owner/homebrew-tools');
      expect(loaded.formula!.checksum, 'ddd');
      expect(loaded.formula!.dependencies, ['openssl']);
    });
  });
}

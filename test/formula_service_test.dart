import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:tapster/models/tapster_config.dart';
import 'package:tapster/services/formula_service.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

void main() {
  group('FormulaService.generateFormula', () {
    test('renders template with configured checksum', () async {
      final config = sampleConfig(
        formula: FormulaConfig(
          tap: 'owner/homebrew-tools',
          asset: 'build/my-cli',
          checksum: 'a' * 64,
          dependencies: ['openssl'],
        ),
      );

      final formula = await FormulaService().generateFormula(
        config,
        config.formula!,
        version: '1.2.3',
      );

      expect(formula, contains('class MyCli < Formula'));
      expect(formula, contains('desc "A test CLI tool"'));
      expect(formula, contains('homepage "https://github.com/owner/my-cli"'));
      expect(formula, contains('license "MIT"'));
      expect(
        formula,
        contains(
          'url "https://github.com/owner/my-cli/releases/download/'
          'v1.2.3/my-cli"',
        ),
      );
      expect(formula, contains('sha256 "${'a' * 64}"'));
      expect(formula, contains('depends_on "openssl"'));
      expect(formula, contains('bin.install "my-cli"'));
    });

    test('uses the version parameter in the download URL', () async {
      final config = sampleConfig();

      final formula = await FormulaService().generateFormula(
        config,
        config.formula!,
        version: '2.0.0',
      );

      expect(
        formula,
        contains(
          'https://github.com/owner/my-cli/releases/download/v2.0.0/my-cli',
        ),
      );
    });

    test('uses the asset file name in the download URL when it differs '
        'from the package name', () async {
      // 多平台发布：asset 名带平台后缀（tapster-macos），URL 必须指向它，
      // 与 cask/scoop 一致，也才能匹配远端 digest 解析。
      final config = sampleConfig(
        formula: FormulaConfig(
          tap: 'owner/homebrew-tools',
          asset: 'build/my-cli-macos',
          checksum: 'a' * 64,
        ),
      );

      final formula = await FormulaService().generateFormula(
        config,
        config.formula!,
        version: '1.2.3',
      );

      expect(
        formula,
        contains(
          'url "https://github.com/owner/my-cli/releases/download/'
          'v1.2.3/my-cli-macos"',
        ),
      );
      expect(formula, contains('bin.install "my-cli-macos"'));
    });

    test('computes checksum from local asset when not configured', () async {
      final tempDir = await Directory.systemTemp.createTemp('tapster_test');
      addTearDown(() => tempDir.delete(recursive: true));

      final assetPath = '${tempDir.path}/my-cli';
      final bytes = [1, 2, 3, 4, 5];
      await File(assetPath).writeAsBytes(bytes);
      final expectedChecksum = sha256.convert(bytes).toString();

      final config = sampleConfig(
        formula: FormulaConfig(
          tap: 'owner/homebrew-tools',
          asset: assetPath,
        ),
      );

      final formula = await FormulaService().generateFormula(
        config,
        config.formula!,
        version: '1.2.3',
      );

      expect(formula, contains('sha256 "$expectedChecksum"'));
    });

    test('converts hyphenated package names to Ruby class names', () async {
      final config = sampleConfig(name: 'my-cool-tool');

      final formula = await FormulaService().generateFormula(
        config,
        config.formula!,
        version: '1.2.3',
      );

      expect(formula, contains('class MyCoolTool < Formula'));
    });
  });
}

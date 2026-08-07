import 'package:tapster/models/tapster_config.dart';

/// 构造测试用配置（默认带 formula 目标）。
TapsterConfig sampleConfig({
  String name = 'my-cli',
  String version = '1.2.3',
  FormulaConfig? formula,
  CaskConfig? cask,
  ScoopConfig? scoop,
}) {
  return TapsterConfig(
    name: name,
    version: version,
    description: 'A test CLI tool',
    homepage: 'https://github.com/owner/my-cli',
    repository: 'https://github.com/owner/my-cli.git',
    license: 'MIT',
    formula: formula ??
        FormulaConfig(
          tap: 'owner/homebrew-tools',
          asset: 'build/my-cli',
          checksum: 'a' * 64,
        ),
    cask: cask,
    scoop: scoop,
  );
}

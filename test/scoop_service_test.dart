import 'dart:convert';

import 'package:tapster/models/tapster_config.dart';
import 'package:tapster/services/scoop_service.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

void main() {
  group('ScoopService.generateScoopManifest', () {
    test('renders manifest with version, url, hash and autoupdate', () async {
      final config = sampleConfig(
        name: 'my-app',
        scoop: ScoopConfig(
          bucket: 'owner/scoop-bucket',
          asset: 'build/windows/my-app.zip',
          arch: '64bit',
          checksum: 'c' * 64,
        ),
      );

      final manifestJson = await ScoopService().generateScoopManifest(
        config,
        config.scoop!,
        version: '1.2.3',
      );
      final manifest = jsonDecode(manifestJson) as Map<String, dynamic>;

      expect(manifest['version'], '1.2.3');
      expect(manifest['description'], 'A test CLI tool');
      expect(
        manifest['url'],
        'https://github.com/owner/my-cli/releases/download/v1.2.3/'
        'my-app.zip',
      );
      expect(manifest['hash'], 'sha256:${'c' * 64}');
      expect(manifest['bin'], 'my-app.exe');
      expect(manifest['checkver'], {
        'github': 'https://github.com/owner/my-cli',
      });
      expect(manifest['autoupdate'], isNotNull);
      // 64bit 是默认值，不应输出 architecture 字段
      expect(manifest.containsKey('architecture'), isFalse);
    });

    test('uses the version parameter in the download URL', () async {
      final config = sampleConfig(
        scoop: ScoopConfig(
          bucket: 'owner/scoop-bucket',
          asset: 'build/windows/my-app.zip',
          checksum: 'c' * 64,
        ),
      );

      final manifestJson = await ScoopService().generateScoopManifest(
        config,
        config.scoop!,
        version: '4.0.0',
      );
      final manifest = jsonDecode(manifestJson) as Map<String, dynamic>;

      expect(manifest['version'], '4.0.0');
      expect(
        manifest['url'],
        'https://github.com/owner/my-cli/releases/download/v4.0.0/'
        'my-app.zip',
      );
    });

    test('emits architecture field for non-default arch', () async {
      final config = sampleConfig(
        scoop: ScoopConfig(
          bucket: 'owner/scoop-bucket',
          asset: 'build/windows/my-app.zip',
          arch: 'arm64',
          checksum: 'c' * 64,
        ),
      );

      final manifestJson = await ScoopService().generateScoopManifest(
        config,
        config.scoop!,
        version: '1.2.3',
      );
      final manifest = jsonDecode(manifestJson) as Map<String, dynamic>;

      expect(manifest['architecture'], 'arm64');
    });

    test('emits shortcuts when configured', () async {
      final config = sampleConfig(
        name: 'my-app',
        scoop: ScoopConfig(
          bucket: 'owner/scoop-bucket',
          asset: 'build/windows/my-app.zip',
          checksum: 'c' * 64,
          shortcuts: ['MyApp'],
        ),
      );

      final manifestJson = await ScoopService().generateScoopManifest(
        config,
        config.scoop!,
        version: '1.2.3',
      );
      final manifest = jsonDecode(manifestJson) as Map<String, dynamic>;

      expect(manifest['shortcuts'], [
        ['my-app.exe', 'MyApp'],
      ]);
    });

    test('renames bin to the package name when the asset name differs', () async {
      // 多平台发布：asset 名带平台后缀（my-app-windows.zip），
      // 用户应直接敲包名（my-cli），Scoop 数组语法重命名安装
      final config = sampleConfig(
        scoop: ScoopConfig(
          bucket: 'owner/scoop-bucket',
          asset: 'build/windows/my-app-windows.zip',
          checksum: 'c' * 64,
        ),
      );

      final manifestJson = await ScoopService().generateScoopManifest(
        config,
        config.scoop!,
        version: '1.2.3',
      );
      final manifest = jsonDecode(manifestJson) as Map<String, dynamic>;

      expect(manifest['bin'], [
        ['my-app-windows.exe', 'my-cli'],
      ]);
    });

    test('renames shortcut targets when bin is renamed', () async {
      final config = sampleConfig(
        scoop: ScoopConfig(
          bucket: 'owner/scoop-bucket',
          asset: 'build/windows/my-app-windows.zip',
          checksum: 'c' * 64,
          shortcuts: ['MyApp'],
        ),
      );

      final manifestJson = await ScoopService().generateScoopManifest(
        config,
        config.scoop!,
        version: '1.2.3',
      );
      final manifest = jsonDecode(manifestJson) as Map<String, dynamic>;

      expect(manifest['bin'], [
        ['my-app-windows.exe', 'my-cli'],
      ]);
      expect(manifest['shortcuts'], [
        ['my-cli.exe', 'MyApp'],
      ]);
    });
  });
}

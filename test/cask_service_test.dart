import 'package:tapster/models/tapster_config.dart';
import 'package:tapster/services/cask_service.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

void main() {
  group('CaskService.generateCask', () {
    test('renders template with version and checksum', () async {
      final config = sampleConfig(
        name: 'my-app',
        cask: CaskConfig(
          tap: 'owner/homebrew-cask',
          asset: 'build/macos/my-app.zip',
          appName: 'MyApp.app',
          checksum: 'b' * 64,
        ),
      );

      final cask = await CaskService().generateCask(
        config,
        config.cask!,
        version: '1.2.3',
      );

      expect(cask, contains('cask "my-app" do'));
      expect(cask, contains('version "1.2.3"'));
      expect(cask, contains('sha256 "${'b' * 64}"'));
      expect(
        cask,
        contains(
          'url "https://github.com/owner/my-cli/releases/download/'
          'v1.2.3/my-app.zip"',
        ),
      );
      expect(cask, contains('name "MyApp"'));
      expect(cask, contains('app "MyApp.app"'));
      expect(cask, contains('desc "A test CLI tool"'));
    });

    test('uses the version parameter in the download URL', () async {
      final config = sampleConfig(
        cask: CaskConfig(
          tap: 'owner/homebrew-cask',
          asset: 'build/macos/my-app.zip',
          appName: 'MyApp.app',
          checksum: 'b' * 64,
        ),
      );

      final cask = await CaskService().generateCask(
        config,
        config.cask!,
        version: '3.1.4',
      );

      expect(
        cask,
        contains(
          'https://github.com/owner/my-cli/releases/download/v3.1.4/'
          'my-app.zip',
        ),
      );
      expect(cask, contains('version "3.1.4"'));
    });
  });
}

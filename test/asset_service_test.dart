import 'package:tapster/services/asset_service.dart';
import 'package:test/test.dart';

void main() {
  group('AssetService.basename', () {
    test('strips unix-style directories', () {
      expect(AssetService.basename('build/my-app.zip'), 'my-app.zip');
      expect(AssetService.basename('build/windows/my-app.zip'), 'my-app.zip');
    });

    test('strips windows-style directories', () {
      expect(AssetService.basename(r'build\my-app.zip'), 'my-app.zip');
      expect(
        AssetService.basename(r'build\windows\my-app.exe'),
        'my-app.exe',
      );
    });

    test('keeps bare file names unchanged', () {
      expect(AssetService.basename('my-app.zip'), 'my-app.zip');
      expect(AssetService.basename('my-app.exe'), 'my-app.exe');
    });

    test('handles mixed separators', () {
      expect(
        AssetService.basename(r'build/windows\my-app.zip'),
        'my-app.zip',
      );
    });
  });
}

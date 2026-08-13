import 'package:tapster/models/tapster_config.dart';
import 'package:tapster/services/asset_service.dart';

class CaskService {
  static const String caskTemplate = '''
cask "{{NAME}}" do
  version "{{VERSION}}"
  sha256 "{{SHA256}}"
  url "{{URL}}"
  name "{{APP_NAME}}"
  desc "{{DESCRIPTION}}"
  homepage "{{HOMEPAGE}}"

  app "{{APP_TARGET}}"

  zap trash: [
    "~/Library/Application Support/{{APP_NAME}}",
  ]
end
''';

  Future<String> generateCask(
    TapsterConfig config,
    CaskConfig caskConfig, {
    required String version,
  }) async {
    final assetService = AssetService();

    String sha256;
    if (caskConfig.checksum != null) {
      sha256 = caskConfig.checksum!;
    } else {
      final assetInfo = await assetService.getAssetInfo(caskConfig.asset);
      sha256 = assetInfo.checksum;
    }

    final url = _buildDownloadUrl(config, version, caskConfig.asset);

    // 注意：Homebrew Cask DSL 没有 license 方法（formula 有），模板中不得使用
    final context = <String, String>{
      'NAME': config.name,
      'VERSION': version,
      'SHA256': sha256,
      'URL': url,
      'APP_NAME': caskConfig.appName.replaceAll('.app', ''),
      'APP_TARGET': caskConfig.appName,
      'DESCRIPTION': config.description,
      'HOMEPAGE': config.homepage,
    };

    return _renderTemplate(caskTemplate, context);
  }

  String _renderTemplate(String template, Map<String, String> context) {
    var result = template;
    for (final entry in context.entries) {
      result = result.replaceAll('{{${entry.key}}}', entry.value);
    }
    return result;
  }

  String _buildDownloadUrl(TapsterConfig config, String version, String assetPath) {
    final repo = config.repository.replaceAll('.git', '');
    final assetFileName = AssetService.basename(assetPath);
    return '$repo/releases/download/v$version/$assetFileName';
  }
}

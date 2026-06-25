import 'dart:convert';
import 'package:tapster/models/tapster_config.dart';
import 'package:tapster/services/asset_service.dart';

class ScoopService {
  Future<String> generateScoopManifest(TapsterConfig config, ScoopConfig scoopConfig) async {
    final assetService = AssetService();

    String sha256;
    if (scoopConfig.checksum != null) {
      sha256 = scoopConfig.checksum!;
    } else {
      final assetInfo = await assetService.getAssetInfo(scoopConfig.asset);
      sha256 = assetInfo.checksum;
    }

    final url = _buildDownloadUrl(config, config.version, scoopConfig.asset);

    final manifest = <String, dynamic>{
      'version': config.version,
      'description': config.description,
      'homepage': config.homepage,
      'license': config.license,
      'url': url,
      'hash': 'sha256:$sha256',
      'bin': _extractBinaryName(scoopConfig.asset),
      'checkver': {
        'github': config.repository.replaceAll('.git', ''),
      },
      'autoupdate': {
        'url': _buildDownloadUrl(config, r'$version', scoopConfig.asset),
        'hash': {
          'url': '$url.sha256',
        },
      },
    };

    if (scoopConfig.shortcuts.isNotEmpty) {
      manifest['shortcuts'] = scoopConfig.shortcuts
          .map((s) => [_extractBinaryName(scoopConfig.asset), s])
          .toList();
    }

    if (scoopConfig.arch != '64bit') {
      manifest['architecture'] = scoopConfig.arch;
    }

    const encoder = JsonEncoder.withIndent('    ');
    return encoder.convert(manifest);
  }

  String _extractBinaryName(String assetPath) {
    var fileName = assetPath.split('/').last;
    if (fileName.endsWith('.zip')) {
      fileName = fileName.substring(0, fileName.length - 4);
    }
    if (!fileName.endsWith('.exe')) {
      fileName = '$fileName.exe';
    }
    return fileName;
  }

  String _buildDownloadUrl(TapsterConfig config, String version, String assetPath) {
    final repo = config.repository.replaceAll('.git', '');
    final assetFileName = assetPath.split('/').last;
    return '$repo/releases/download/v$version/$assetFileName';
  }
}

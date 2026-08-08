import 'dart:convert';
import 'package:tapster/models/tapster_config.dart';
import 'package:tapster/services/asset_service.dart';

class ScoopService {
  Future<String> generateScoopManifest(
    TapsterConfig config,
    ScoopConfig scoopConfig, {
    required String version,
  }) async {
    final assetService = AssetService();

    String sha256;
    if (scoopConfig.checksum != null) {
      sha256 = scoopConfig.checksum!;
    } else {
      final assetInfo = await assetService.getAssetInfo(scoopConfig.asset);
      sha256 = assetInfo.checksum;
    }

    final url = _buildDownloadUrl(config, version, scoopConfig.asset);

    // 用户命令名 = 包名：asset 文件名带平台后缀（tapster-windows.exe）时，
    // 用 Scoop 数组语法重命名安装，用户直接敲包名；同名则保持简单字符串
    final binName = _extractBinaryName(scoopConfig.asset);
    final baseName = binName.endsWith('.exe')
        ? binName.substring(0, binName.length - 4)
        : binName;
    final renamesToPackageName = baseName != config.name;

    final manifest = <String, dynamic>{
      'version': version,
      'description': config.description,
      'homepage': config.homepage,
      'license': config.license,
      'url': url,
      'hash': 'sha256:$sha256',
      'bin': renamesToPackageName ? [[binName, config.name]] : binName,
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
      // shortcuts 引用 bin 里的可执行文件名，重命名后必须指向新命令名
      final shortcutTarget = renamesToPackageName ? '${config.name}.exe' : binName;
      manifest['shortcuts'] = scoopConfig.shortcuts
          .map((s) => [shortcutTarget, s])
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

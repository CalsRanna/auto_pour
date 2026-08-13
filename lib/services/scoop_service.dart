import 'dart:convert';
import 'package:tapster/models/tapster_config.dart';
import 'package:tapster/services/asset_service.dart';
import 'package:tapster/utils/repo_utils.dart';

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

    final assetName = AssetService.basename(scoopConfig.asset);
    final url = _buildDownloadUrl(config, version, scoopConfig.asset);

    // zip 内 exe 名：显式 bin 声明优先，缺省按 asset 基名推导
    // （契约：`X.zip` 内二进制名为 `X.exe`；不一致时必须显式声明 bin）
    final binName = scoopConfig.bin ?? _extractBinaryName(assetName);
    final baseName = binName.endsWith('.exe')
        ? binName.substring(0, binName.length - 4)
        : binName;
    final renamesToPackageName = baseName != config.name;

    final (owner, repo) = parseRepoString(config.repository);

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
        // digest 来自 GitHub API（release asset 的 digest 字段，
        // 自带 sha256: 前缀）——GitHub Release 没有 .sha256 文件，
        // 固定 URL 会 404
        'hash': {
          'url': 'https://api.github.com/repos/$owner/$repo/releases/tags/'
              r'v$version',
          'jsonpath': '\$.assets[?(@.name==\'$assetName\')].digest',
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

  String _extractBinaryName(String assetFileName) {
    var fileName = assetFileName;
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
    final assetFileName = AssetService.basename(assetPath);
    return '$repo/releases/download/v$version/$assetFileName';
  }
}

import 'dart:convert';
import 'dart:io';

/// GitHub 分发所需的最小能力集（基于 gh CLI）。
///
/// tapster 只负责分发：读取远端仓库的 Release 信息（tag + asset digest），
/// 并把生成的 manifest 写入托管仓库。Release 的创建、asset 上传属于
/// 被发布仓库自己的 CI——tapster 不碰这些。
class GitHubService {
  static const String ghCommand = 'gh';

  /// 获取远端仓库最新的非 draft Release 及其 asset digest。
  ///
  /// [requiredAssets] 非空时，在最近 10 个非 draft 的 v* release 中
  /// 选第一个包含全部所需 asset digest 的；都没有时回退为其中最新
  /// 的一个（调用方根据 [ReleaseInfo.assetDigests] 判断缺哪些）。
  ///
  /// 返回 `null` 表示没有可用 Release（如仓库无 Release、非 v* tag、
  /// 或 gh 不可用/未认证）。
  Future<ReleaseInfo?> fetchLatestRelease(
    String owner,
    String repo, {
    Set<String>? requiredAssets,
  }) async {
    try {
      final result = await _runGh([
        'api',
        'repos/$owner/$repo/releases',
        '--jq',
        '[.[] | select(.draft == false and (.tag_name | startswith("v")))][0:10]',
      ]);
      if (result.exitCode != 0 || result.stdout.trim().isEmpty) return null;

      final releases = jsonDecode(result.stdout) as List;
      if (releases.isEmpty) return null;

      // 选第一个包含全部所需 asset 的 release；都没有则取最新
      ReleaseInfo? fallback;
      for (final raw in releases) {
        final info = _parseRelease(raw as Map<String, dynamic>);
        if (info == null) continue;
        fallback ??= info;
        if (requiredAssets == null ||
            info.assetDigests.keys.toSet().containsAll(requiredAssets)) {
          return info;
        }
      }
      return fallback;
    } catch (e) {
      return null;
    }
  }

  /// 按 tag 获取指定 Release（供 `--version` 场景：digest 必须来自
  /// 对应版本的 Release，而不是最新版）。
  ///
  /// tag 无 `v` 前缀时自动补 `v` 重试。找不到返回 `null`。
  Future<ReleaseInfo?> fetchReleaseByTag(
    String owner,
    String repo,
    String tag,
  ) async {
    final normalized = tag.startsWith('v') ? tag : 'v$tag';
    for (final candidate in {normalized, normalized.substring(1)}) {
      try {
        final result = await _runGh([
          'api',
          'repos/$owner/$repo/releases/tags/$candidate',
        ]);
        if (result.exitCode != 0) continue;
        final data = jsonDecode(result.stdout) as Map<String, dynamic>;
        return _parseRelease(data);
      } catch (e) {
        // try the other form
      }
    }
    return null;
  }

  ReleaseInfo? _parseRelease(Map<String, dynamic> data) {
    final tagName = data['tag_name'] as String?;
    if (tagName == null) return null;

    final digests = <String, String>{};
    final assets = data['assets'] as List? ?? [];
    for (final asset in assets) {
      if (asset is Map<String, dynamic>) {
        final name = asset['name'] as String?;
        final digest = asset['digest'] as String?;
        if (name != null && digest != null) {
          digests[name] = stripDigestPrefix(digest);
        }
      }
    }

    return ReleaseInfo(tagName: tagName, assetDigests: digests);
  }

  /// 推送文件到仓库（GitHub Contents API）。
  ///
  /// 文件已存在时自动携带 sha 覆盖。用本地 gh 的认证凭据，
  /// 目标仓库通常是用户自己的托管仓库。
  Future<void> pushFile({
    required String owner,
    required String repo,
    required String path,
    required String content,
    required String message,
  }) async {
    final encodedContent = base64Encode(utf8.encode(content));

    // 已存在的文件需要携带 sha 才能覆盖
    String? sha;
    try {
      final checkResult = await _runGh([
        'api',
        'repos/$owner/$repo/contents/$path',
        '--jq',
        '.sha',
      ]);
      if (checkResult.exitCode == 0 && checkResult.stdout.trim().isNotEmpty) {
        sha = checkResult.stdout.trim();
      }
    } catch (e) {
      sha = null;
    }

    final args = [
      'api',
      '-X',
      'PUT',
      'repos/$owner/$repo/contents/$path',
      '-f',
      'message=$message',
      '-f',
      'content=$encodedContent',
      '-f',
      'branch=main',
    ];
    if (sha != null) {
      args.addAll(['-f', 'sha=$sha']);
    }

    final result = await _runGh(args);
    if (result.exitCode != 0) {
      throw GitHubException(
        'Failed to push $path to $owner/$repo: ${result.stderr}',
      );
    }
  }

  /// 检查 gh 是否已安装并认证（分发依赖本地 gh 凭据）。
  Future<bool> isAuthenticated() async {
    try {
      final result = await _runGh(['auth', 'status']);
      return result.exitCode == 0;
    } catch (e) {
      return false;
    }
  }

  /// 仓库是否存在（`gh api repos/{owner}/{repo}`，404 → false）。
  ///
  /// 供 setup 命令幂等判断：已存在的 tap/bucket 跳过创建。
  Future<bool> repositoryExists(String owner, String repo) async {
    try {
      final result = await _runGh(['api', 'repos/$owner/$repo']);
      return result.exitCode == 0;
    } catch (e) {
      return false;
    }
  }

  /// 创建仓库（`gh repo create {owner}/{repo} --public|--private`）。
  ///
  /// 用于 setup：创建托管仓库（tap/bucket）。创建的是用户自己的仓库，
  /// 与 pushFile 同属发布侧准备；public 默认 true——Scoop bucket
  /// 必须公开才能被 scoop 安装。
  Future<void> createRepository(
    String owner,
    String repo, {
    bool public = true,
  }) async {
    final result = await _runGh([
      'repo',
      'create',
      '$owner/$repo',
      public ? '--public' : '--private',
    ]);
    if (result.exitCode != 0) {
      throw GitHubException(
        'Failed to create repository $owner/$repo: ${result.stderr}',
      );
    }
  }

  /// 去掉 digest 的算法前缀：`sha256:hex` → `hex`。
  static String stripDigestPrefix(String digest) {
    final colonIndex = digest.indexOf(':');
    return colonIndex >= 0 ? digest.substring(colonIndex + 1) : digest;
  }

  Future<ProcessResult> _runGh(List<String> args) async {
    return await Process.run(ghCommand, args);
  }
}

/// 远端 Release 的摘要信息。
class ReleaseInfo {
  final String tagName;

  /// asset 文件名 → sha256 hex（无 digest 的 asset 不收录）。
  final Map<String, String> assetDigests;

  ReleaseInfo({required this.tagName, required this.assetDigests});

  factory ReleaseInfo.fromJson(Map<String, dynamic> json) {
    final tagName = json['tag_name'] as String;
    final digests = <String, String>{};
    final assets = json['assets'] as List? ?? [];
    for (final asset in assets) {
      if (asset is Map<String, dynamic>) {
        final name = asset['name'] as String?;
        final digest = asset['digest'] as String?;
        if (name != null && digest != null) {
          digests[name] = GitHubService.stripDigestPrefix(digest);
        }
      }
    }
    return ReleaseInfo(tagName: tagName, assetDigests: digests);
  }
}

class GitHubException implements Exception {
  final String message;

  GitHubException(this.message);

  @override
  String toString() => message;
}

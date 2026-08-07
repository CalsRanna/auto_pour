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
  /// 返回 `null` 表示没有可用 Release（如仓库无 Release、非 v* tag、
  /// 或 gh 不可用/未认证）。
  Future<ReleaseInfo?> fetchLatestRelease(String owner, String repo) async {
    try {
      final result = await _runGh([
        'api',
        'repos/$owner/$repo/releases',
        '--jq',
        '[.[] | select(.draft == false and (.tag_name | startswith("v")))][0]',
      ]);
      if (result.exitCode != 0 || result.stdout.trim().isEmpty) return null;

      final data = jsonDecode(result.stdout) as Map<String, dynamic>;
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
    } catch (e) {
      return null;
    }
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

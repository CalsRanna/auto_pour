import 'dart:io';

/// Git 相关的最小能力集。
///
/// tapster 只做分发（生成分发产物），版本号从 git tag 解析，
/// 因此仅需要读取 tag 的能力——不执行任何 tag 创建、推送等写操作。
class GitService {
  /// 解析当前 HEAD 最近的 tag（如 `v1.2.3` → `1.2.3`）。
  ///
  /// 非 git 仓库、没有 tag、或 git 不可用时返回 `null`。
  Future<String?> resolveCurrentTag() async {
    try {
      final result = await Process.run(
        'git',
        ['describe', '--tags', '--abbrev=0'],
      );
      if (result.exitCode != 0) return null;
      final tag = result.stdout.trim();
      if (tag.isEmpty) return null;
      return stripVersionPrefix(tag);
    } catch (_) {
      return null;
    }
  }

  /// 当前目录是否在 git 仓库内。
  Future<bool> isGitRepository() async {
    try {
      final result = await Process.run(
        'git',
        ['rev-parse', '--is-inside-work-tree'],
      );
      return result.exitCode == 0 && result.stdout.trim() == 'true';
    } catch (_) {
      return false;
    }
  }

  /// 去掉 tag 的前导 `v`（如 `v1.2.3` → `1.2.3`）。
  static String stripVersionPrefix(String tag) {
    return tag.startsWith('v') ? tag.substring(1) : tag;
  }
}

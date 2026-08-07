// 仓库地址与托管仓库名解析工具。

/// 仓库 URL（`https://github.com/owner/repo`、`git@github.com:owner/repo`）
/// → (owner, repo)。
(String, String) parseRepoString(String repository) {
  var s = repository.trim();
  if (s.endsWith('.git')) s = s.substring(0, s.length - 4);

  if (s.contains('github.com/')) {
    s = s.substring(s.indexOf('github.com/') + 'github.com/'.length);
  } else if (s.contains('github.com:')) {
    s = s.substring(s.indexOf('github.com:') + 'github.com:'.length);
  }

  final parts = s.split('/').where((p) => p.isNotEmpty).toList();
  if (parts.length < 2) {
    throw FormatException('Invalid repository URL: $repository');
  }
  return (parts[0], parts[1]);
}

/// tap 名（`owner/name`）→ (owner, 托管仓库名)。
///
/// Homebrew 命名规范：tap `owner/inspire` 对应仓库 `owner/homebrew-inspire`；
/// 名字已以 `homebrew-` 开头时不重复加前缀。
(String, String) resolveTapRepo(String tap) {
  final parts = tap.split('/');
  if (parts.length != 2) {
    throw FormatException('Invalid tap: $tap (expected owner/name)');
  }
  final owner = parts[0];
  final name = parts[1].startsWith('homebrew-')
      ? parts[1]
      : 'homebrew-${parts[1]}';
  return (owner, name);
}

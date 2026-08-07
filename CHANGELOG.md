## 1.1.0

- **职责修正：分发 = 读远端 + 生成 + 写托管仓库**。`publish` 读远端仓库的 Release 信息
  （tag + asset digest），生成 manifest，并推送托管仓库（Homebrew tap / Scoop bucket）。
  被发布仓库自己的 CI 负责构建、打 tag、创建 Release、上传 asset（只碰自己，零跨仓库凭据）。
- 版本从远端最新 Release tag 解析（`--version` 可覆盖，本地 git tag 作 fallback）。
- checksum 从远端 Release asset 的 digest 读取（权威，跨环境构建一致），配置预置/本地
  asset 作 fallback。
- `--dry-run` 只生成产物不推送；`-o` 指定输出目录（默认 `dist/`）。
- 托管仓库解析遵循 Homebrew 命名规范：`tap: owner/inspire` → `owner/homebrew-inspire`。
- `doctor` 检查 gh 认证、远端 Release 可达性、checksum 可得性、输出目录。
- gh 成为运行依赖（读取远端 Release、推送托管仓库）；恢复裁剪版 `GitHubService`
  （不含 Release 创建/上传——那是仓库 B 的 CI 的职责）。
- 新增 `repo_utils`（仓库 URL / tap 名解析）与对应测试。

## 1.0.0

- Initial version.

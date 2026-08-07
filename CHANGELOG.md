## 1.1.0

- **架构重构：tapster 只做分发**。`publish` 不再创建 Release、上传 asset、推送 manifest——改为生成分发产物到本地目录（`-o`，默认 `dist/`），执行动作移交 CI。
- 发布版本从 git tag 自动解析（`--version` 可覆盖），与配置 version 不一致时警告。
- `doctor` 从环境检查改为配置/生成能力检查（不再依赖 gh CLI / brew / 网络）。
- 删除 `github_service` / `homebrew_service` / `network_service` / `dependency_service`，移除 `http` / `process_run` 依赖。
- `git_service` 裁剪为 tag 解析。
- 修复：formula 生成在配置预置 checksum 时不再要求本地 asset 存在（此前仅 cask/scoop 生效）。
- 新增 test/ 测试套件（manifest 生成、配置序列化/迁移、版本解析）。

## 1.0.0

- Initial version.

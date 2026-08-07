# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 项目概述

这是一个用 Dart 编写的命令行工具，名为 "tapster"，**只做分发（distribution）**：读取远端仓库的 Release 信息（tag + asset digest），基于 `.tapster.yaml` 配置生成 Homebrew Formula / Cask 和 Scoop manifest，并写入用户设置的托管仓库（tap / bucket）。

**职责边界（重要）**：

```
被发布仓库（仓库 B）自己的 CI：构建 → 打 tag → 创建 Release → 上传 asset
  只碰自己的仓库，GITHUB_TOKEN 足够，零跨仓库凭据

tapster（发布侧，本地，gh 已登录）：读远端 Release 信息 → 生成 manifest → 写入托管仓库
```

- tapster **不做**：构建、创建 Release、上传 asset（这些是被发布仓库自己的 CI 的职责）
- tapster **做**：读远端状态（gh 已登录可读公开数据）、生成 manifest、推送托管仓库（本地凭据写用户自己的仓库）
- **gh 是运行依赖**：读取远端 Release（`gh api`）和推送托管仓库（Contents API）都通过 gh

项目包含四个主要命令：`init`（配置生成）、`publish`（分发：读远端 → 生成 → 推送托管仓库）、`doctor`（分发就绪检查）、`upgrade`（配置升级）。

支持三种分发目标：
- **Homebrew Formula** — 适用于 CLI 工具（macOS / Linux）
- **Homebrew Cask** — 适用于 macOS GUI 应用
- **Scoop** — 适用于 Windows GUI 应用

一个项目可同时配置多个目标（如 Cask + Scoop 跨平台 GUI，或 Formula + Scoop 跨平台 CLI），产物推送到不同的托管仓库。

## 开发环境

### 技术栈
- **语言**: Dart 3.9.0+
- **框架**: Dart CLI (args 包)
- **配置文件**: YAML (.tapster.yaml)
- **测试**: Dart test framework

### 运行时依赖
- **GitHub CLI (`gh`)**：读取远端 Release（`gh api repos/{owner}/{repo}/releases`）、推送托管仓库（Contents API）——通过 `Process.run` 调用，不是 pub 依赖
- **Git**：版本解析的 fallback（`git describe --tags`）

### 核心 pub 依赖
- `args`: 命令行参数解析
- `yaml`: YAML 配置文件处理
- `crypto`: 哈希计算
- `cli_spin`: 命令行进度指示器

> 不依赖 `http`、`process_run`——GitHub 交互统一走 `gh` CLI（`GitHubService`）。

### 开发命令

```bash
# 运行分析
dart analyze

# 运行测试
dart test

# 运行程序
dart run bin/tapster.dart [command]

# 构建发布版本
dart compile exe bin/tapster.dart -o tapster
```

## 项目架构

### 核心模块

#### 命令层 (lib/commands/)
- `init_command.dart`: 交互式配置生成器（`-t` 指定 target，支持追加/覆盖，默认 homebrew/formula）
- `publish_command.dart`: 分发命令（读远端 Release → 生成 manifest → 推送托管仓库；`--dry-run` 只生成、`--version` 覆盖、`-t` 选择目标、`-o` 输出目录）
- `doctor_command.dart`: 分发就绪检查（配置有效性、gh 认证、远端 Release、checksum 可得性、输出目录）
- `upgrade_command.dart`: 配置升级（更新 version + checksum，支持 `-t` 指定目标）

#### 服务层 (lib/services/)
- `config_service.dart`: 配置文件管理（YAML 读/写/验证，支持旧版扁平格式自动迁移）
- `github_service.dart`: gh 封装——`fetchLatestRelease`（远端 tag + asset digests）、`pushFile`（Contents API 推送，自动处理 sha 覆盖）、`isAuthenticated`；`ReleaseInfo` 模型
- `formula_service.dart`: Homebrew formula 模板生成（内置轻量模板引擎）
- `cask_service.dart`: Homebrew cask 模板生成
- `scoop_service.dart`: Scoop JSON manifest 生成
- `asset_service.dart`: 二进制资源处理（SHA256 哈希计算、文件验证）
- `git_service.dart`: git tag 解析（`resolveCurrentTag`，版本 fallback）

> 已删除（不属于分发职责）：`homebrew_service.dart`、`network_service.dart`、`dependency_service.dart`。

#### 数据模型 (lib/models/)
- `tapster_config.dart`: 主配置模型，包含：
  - `TapsterConfig`: 基本信息（名称、版本、描述、主页、仓库、许可证）
  - `FormulaConfig`: formula 子配置（tap、asset、checksum、dependencies）
  - `CaskConfig`: cask 子配置（tap、asset、appName、checksum）
  - `ScoopConfig`: scoop 子配置（bucket、asset、arch、checksum、shortcuts）

#### 工具 (lib/utils/)
- `config_validator.dart`: 配置验证逻辑（必填字段、格式校验）
- `repo_utils.dart`: 仓库 URL / tap 名解析（`parseRepoString`、`resolveTapRepo`）
- `status_markers.dart`: 状态标记枚举（✓ ✗ ! •）
- `string_buffer_extensions.dart`: StringBuffer 扩展（彩色终端输出）

### 关键特性

1. **配置驱动**: 所有操作基于 `.tapster.yaml` 配置文件，支持嵌套 formula/cask/scoop 子配置
2. **多目标分发**: 一个项目可同时配置 Formula、Cask、Scoop，产物输出到 `dist/` 并推送各托管仓库
3. **跨平台支持**: 同一版本可在不同平台上分次分发（`-t` 过滤目标），Release 共享
4. **版本来自远端 Release**: `publish` 默认读远端最新 Release tag 解析版本（`--version` 可覆盖，本地 git tag 作 fallback）
5. **权威 checksum**: 从远端 Release asset 读取 digest（sha256，`gh api` 的 `digest` 字段），跨环境构建也一致；配置预置/本地 asset 作 fallback
6. **推送托管仓库**: 生成后自动写入（formula/cask → `owner/homebrew-{tap}`，scoop → bucket 仓库），用本地 gh 凭据；`--dry-run` 只生成
7. **模板生成**: 自动生成 Homebrew formula/cask 和 Scoop manifest
8. **文件路径规范**: Formula 推送 `Formula/{name}.rb`，Cask 推送 `Casks/{name}.rb`，Scoop 推送 `{name}.json`
9. **旧版兼容**: 自动迁移扁平格式配置到嵌套格式

### 开发注意事项

- 所有配置都通过 `TapsterConfig` 模型进行类型安全访问
- 使用 `ConfigService` 进行配置文件的读取和验证
- **manifest 生成服务（formula/cask/scoop）的 `generateXxx` 必须接收显式 `version` 参数**，不要从 `config.version` 读取（版本来自远端 Release）
- **manifest 生成服务对 checksum 的处理**：配置预置时不得读取本地 asset（跨平台时 asset 可能不在本地）——检查 `checksum` 非空时短路，只在为空时调用 `AssetService.getAssetInfo`
- GitHub 交互统一走 `GitHubService`（gh CLI），不要在命令层直接 `Process.run('gh', ...)`
- 仓库解析用 `repo_utils.dart` 的 `parseRepoString` / `resolveTapRepo`，不要重复实现
- **tapster 不创建 Release、不上传 asset**（`gh release create` / `gh release upload` 不属于 tapster，是被发布仓库自己的 CI 的职责）
- 命令行输出使用标准格式，成功使用 ✓（绿色），失败使用 ✗（红色），警告使用 !（黄色）
- 错误处理包含详细的上下文信息和建议解决方案

### 测试策略

测试文件位于 `test/` 目录，主要测试：
- manifest 生成逻辑（模板渲染、version 参数化、checksum 来源优先级）
- 配置序列化/反序列化、旧版扁平格式迁移
- 版本解析（tag → 版本号）
- `ReleaseInfo` 解析（tag、asset digest、`stripDigestPrefix`）
- 仓库/tap 解析（`parseRepoString`、`resolveTapRepo`）

运行测试：`dart test`

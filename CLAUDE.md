# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 项目概述

这是一个用 Dart 编写的命令行工具，名为 "tapster"，**只做分发（distribution）**：基于 `.tapster.yaml` 配置生成 Homebrew Formula / Cask 和 Scoop manifest 分发产物。

**职责边界（重要）**：tapster 不构建、不创建 GitHub Release、不上传 asset、不推送任何仓库。这些执行动作属于 CI（README 提供 GitHub Actions workflow 示例）。tapster 本地零网络、零 gh 依赖，唯一的 git 依赖是从 tag 解析版本号。

项目包含四个主要命令：`init`（配置生成）、`publish`（分发产物生成）、`doctor`（配置/生成能力检查）、`upgrade`（配置升级）。

支持三种分发目标：
- **Homebrew Formula** — 适用于 CLI 工具（macOS / Linux）
- **Homebrew Cask** — 适用于 macOS GUI 应用
- **Scoop** — 适用于 Windows GUI 应用

一个项目可同时配置多个目标（如 Cask + Scoop 跨平台 GUI，或 Formula + Scoop 跨平台 CLI），产物推送到不同的仓库（由 CI 推送）。

## 开发环境

### 技术栈
- **语言**: Dart 3.9.0+
- **框架**: Dart CLI (args 包)
- **配置文件**: YAML (.tapster.yaml)
- **测试**: Dart test framework

### 核心依赖
- `args`: 命令行参数解析
- `yaml`: YAML 配置文件处理
- `crypto`: 哈希计算
- `cli_spin`: 命令行进度指示器

> 不依赖 `http`、`process_run`、GitHub CLI——任何远程操作代码都不应出现。

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
- `publish_command.dart`: 分发产物生成器（`-o` 输出目录、`--version` 覆盖、`-t` 选择目标）
- `doctor_command.dart`: 配置/生成能力检查（配置有效性、checksum 可得性、git tag、输出目录）
- `upgrade_command.dart`: 配置升级（更新 version + checksum，支持 `-t` 指定目标）

#### 服务层 (lib/services/)
- `config_service.dart`: 配置文件管理（YAML 读/写/验证，支持旧版扁平格式自动迁移）
- `formula_service.dart`: Homebrew formula 模板生成（内置轻量模板引擎）
- `cask_service.dart`: Homebrew cask 模板生成
- `scoop_service.dart`: Scoop JSON manifest 生成
- `asset_service.dart`: 二进制资源处理（SHA256 哈希计算、文件验证）
- `git_service.dart`: git tag 解析（`resolveCurrentTag`，版本号来源）

> 已删除（远程操作/环境检查，职责移交 CI）：`github_service.dart`、`homebrew_service.dart`、`network_service.dart`、`dependency_service.dart`。

#### 数据模型 (lib/models/)
- `tapster_config.dart`: 主配置模型，包含：
  - `TapsterConfig`: 基本信息（名称、版本、描述、主页、仓库、许可证）
  - `FormulaConfig`: formula 子配置（tap、asset、checksum、dependencies）
  - `CaskConfig`: cask 子配置（tap、asset、appName、checksum）
  - `ScoopConfig`: scoop 子配置（bucket、asset、arch、checksum、shortcuts）

#### 工具 (lib/utils/)
- `config_validator.dart`: 配置验证逻辑（必填字段、格式校验）
- `status_markers.dart`: 状态标记枚举（✓ ✗ ! •）
- `string_buffer_extensions.dart`: StringBuffer 扩展（彩色终端输出）

### 关键特性

1. **配置驱动**: 所有操作基于 `.tapster.yaml` 配置文件，支持嵌套 formula/cask/scoop 子配置
2. **多目标分发**: 一个项目可同时配置 Formula、Cask、Scoop，产物输出到不同目录（`dist/Formula/`、`dist/Casks/`、`dist/`）
3. **跨平台支持**: 同一版本可在不同平台上分次生成产物（`-t` 过滤目标，产物由 CI 推送）
4. **版本来自 git tag**: `publish` 默认从最近 git tag 解析版本（`--version` 可覆盖），与配置 version 不一致时警告
5. **预置校验和**: 所有三个目标均支持预计算 SHA256，配置预置优先，否则从本地 asset 计算（formula 服务同样适用——见下）
6. **模板生成**: 自动生成 Homebrew formula/cask 和 Scoop manifest
7. **文件路径规范**: Formula 产物在 `Formula/{name}.rb`，Cask 在 `Casks/{name}.rb`，Scoop 在 `{name}.json`（相对输出目录）
8. **旧版兼容**: 自动迁移扁平格式配置到嵌套格式

### 开发注意事项

- 所有配置都通过 `TapsterConfig` 模型进行类型安全访问
- 使用 `ConfigService` 进行配置文件的读取和验证
- **manifest 生成服务（formula/cask/scoop）的 `generateXxx` 必须接收显式 `version` 参数**，不要从 `config.version` 读取（版本来自 tag）
- **manifest 生成服务对 checksum 的处理**：配置预置时不得读取本地 asset（跨平台时 asset 可能不在本地）——检查 `checksum` 非空时短路，只在为空时调用 `AssetService.getAssetInfo`
- 命令行输出使用标准格式，成功使用 ✓（绿色），失败使用 ✗（红色），警告使用 !（黄色）
- 错误处理包含详细的上下文信息和建议解决方案
- **禁止引入**：gh CLI 调用、GitHub API 请求、git push、git tag 创建——这些属于 CI 职责
- 测试文件位于 `test/`，主要覆盖 manifest 生成（版本参数化、checksum 来源优先级）、配置序列化/迁移、版本解析

### 测试策略

测试文件位于 `test/` 目录，主要测试：
- manifest 生成逻辑（模板渲染、version 参数化、checksum 来源优先级）
- 配置序列化/反序列化、旧版扁平格式迁移
- 版本解析（tag → 版本号）

运行测试：`dart test`

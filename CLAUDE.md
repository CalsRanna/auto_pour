# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 项目概述

这是一个用 Dart 编写的命令行工具，名为 "tapster"，用于自动化 Homebrew/Scoop 包发布流程。项目包含四个主要命令：`init`（配置生成）、`publish`（包发布）、`doctor`（环境检查）、`upgrade`（配置升级）。

支持三种分发目标：
- **Homebrew Formula** — 适用于 CLI 工具（macOS / Linux）
- **Homebrew Cask** — 适用于 macOS GUI 应用
- **Scoop** — 适用于 Windows GUI 应用

一个项目可同时配置多个目标（如 Cask + Scoop 跨平台 GUI，或 Formula + Scoop 跨平台 CLI），推送到不同的仓库。

## 开发环境

### 技术栈
- **语言**: Dart 3.9.0+
- **框架**: Dart CLI (args 包)
- **配置文件**: YAML (.tapster.yaml)
- **测试**: Dart test framework

### 核心依赖
- `args`: 命令行参数解析
- `yaml`: YAML 配置文件处理
- `http`: HTTP 请求（GitHub API）
- `crypto`: 哈希计算
- `cli_spin`: 命令行进度指示器
- `process_run`: 子进程执行

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
- `init_command.dart`: 交互式配置生成器（5 种项目类型：Formula、Cask、Scoop、Formula+Scoop、Cask+Scoop）
- `publish_command.dart`: 包发布流程（支持 `-t` 选择目标、`-f` 强制覆盖）
- `doctor_command.dart`: 环境检查工具（git、gh CLI、brew、网络连通性）
- `upgrade_command.dart`: 配置升级（更新 version + checksum，支持 `-t` 指定目标）

#### 服务层 (lib/services/)
- `config_service.dart`: 配置文件管理（YAML 读/写/验证，支持旧版扁平格式自动迁移）
- `github_service.dart`: GitHub API 集成（认证、版本发布、资源上传）
- `formula_service.dart`: Homebrew formula 模板生成（内置轻量模板引擎）
- `cask_service.dart`: Homebrew cask 模板生成
- `scoop_service.dart`: Scoop JSON manifest 生成
- `asset_service.dart`: 二进制资源处理（SHA256 哈希计算、文件验证）
- `homebrew_service.dart`: Homebrew tap 操作
- `git_service.dart`: Git 操作（tag、push、status）
- `network_service.dart`: 网络连接检查（GitHub 连通性、API 速率限制、SSH）
- `dependency_service.dart`: 依赖管理（聚合各服务的环境检查）

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
2. **多目标发布**: 一个项目可同时配置 Formula、Cask、Scoop，推送到不同的仓库
3. **跨平台支持**: 同一版本可在不同平台上分次发布（Release 共享，各自推送目标仓库）
4. **预置校验和**: 所有三个目标均支持预计算 SHA256，避免跨平台时读取不到本地 asset
5. **资源管理**: 自动处理二进制文件的哈希计算和上传
6. **GitHub 集成**: 基于 GitHub CLI (`gh`) 进行 Release 创建、Asset 上传、文件推送
7. **模板生成**: 自动生成 Homebrew formula/cask 和 Scoop manifest
8. **环境检查**: 验证开发环境和依赖
9. **文件路径规范**: Formula 推送到 `Formula/{name}.rb`，Cask 推送到 `Casks/{name}.rb`
10. **旧版兼容**: 自动迁移扁平格式配置到嵌套格式

### 开发注意事项

- 所有配置都通过 `TapsterConfig` 模型进行类型安全访问
- 使用 `ConfigService` 进行配置文件的读取和验证
- GitHub 操作通过 `GitHubService` 和 `gh` CLI 统一管理
- 命令行输出使用标准格式，成功使用 ✓（绿色），失败使用 ✗（红色），警告使用 !（黄色）
- 错误处理包含详细的上下文信息和建议解决方案
- Publish 工作流使用 `PublishStep` 步骤模式统一执行
- Release 已存在时使用显式前置检查，而非异常控制流

### 测试策略

测试文件位于 `test/` 目录，主要测试：
- 配置验证逻辑
- 模型序列化/反序列化
- 服务层的核心功能

运行测试：`dart test`

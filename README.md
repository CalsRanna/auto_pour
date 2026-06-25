# Tapster - 包发布自动化工具

Tapster 是一个用 Dart 编写的命令行工具，用于自动化 Homebrew 包和 Scoop 包的发布流程。通过 `.tapster.yaml` 配置文件管理整个发布过程：创建 GitHub Release、生成 Formula/Cask/Scoop Manifest、推送到对应的仓库。

支持跨平台发布——同一版本可在不同操作系统上分次发布，每个平台推送到各自的目标仓库。

## ✨ 功能特性

- 🚀 **自动化发布流程**: 一键完成从 GitHub Release 到多目标发布的完整流程
- 📝 **配置驱动**: 通过 `.tapster.yaml` 配置文件管理项目信息和发布设置
- 🎯 **多目标支持**: 同时支持 Homebrew Formula、Homebrew Cask、Scoop 三种分发目标
- 🌐 **跨平台发布**: 同一版本可在 macOS/Windows/Linux 上分次发布，Release 共享、仓库独立
- 🔐 **GitHub 集成**: 基于 GitHub CLI (`gh`) 进行版本发布和资源上传
- 🏗️ **模板生成**: 自动生成符合规范的 Formula/Cask Ruby 文件和 Scoop JSON manifest
- 🔍 **环境检查**: 内置 `doctor` 命令，检查 git、gh CLI、brew、网络连接
- 📦 **资源管理**: 自动处理二进制文件和 SHA256 哈希值计算
- 🛡️ **配置验证**: 严格验证配置文件的完整性和正确性
- 🎯 **交互式配置**: 通过向导式界面生成项目配置，支持追加/覆盖
- 🔄 **配置升级**: `upgrade` 命令自动更新 version 和 checksum
- 🔧 **强制发布**: `-f` 覆盖已存在的版本发布

## 📋 系统要求

- **Dart**: 3.9.0 或更高版本
- **Git**: 已安装并配置用户信息
- **GitHub CLI**: 已安装并完成认证 (`gh auth login`)
- **Homebrew**: 已安装（可选，用于环境检查）

## 🚀 快速开始

### 1. 安装 Tapster

```bash
# 克隆仓库
git clone https://github.com/tapster/tapster.git
cd tapster

# 获取依赖
dart pub get

# 直接运行
dart run bin/tapster.dart --help

# 或构建可执行文件
dart compile exe bin/tapster.dart -o tapster
```

### 2. 创建配置文件

```bash
# 首次创建（默认 homebrew/formula 目标）
tapster init

# 追加 cask 配置到已有项目
tapster init -t homebrew/cask

# 追加 scoop 配置
tapster init -t scoop

# 一次性配置多个目标
tapster init -t homebrew/cask -t scoop
```

### 3. 检查环境

```bash
# 检查发布环境是否配置正确
dart run bin/tapster.dart doctor

# 详细模式
dart run bin/tapster.dart doctor -v
```

### 4. 发布包

```bash
# 发布所有已配置的目标
dart run bin/tapster.dart publish

# 发布指定目标（跨平台时常用）
dart run bin/tapster.dart publish -t homebrew/cask     # macOS 上
dart run bin/tapster.dart publish -t scoop    # Windows 上

# 强制覆盖已存在的版本
dart run bin/tapster.dart publish -f
```

## ⚙️ 配置文件

Tapster 使用 `.tapster.yaml` 配置文件管理项目信息，支持嵌套的 formula/cask/scoop 子配置：

### Formula 配置（CLI 工具）

```yaml
name: my-cli
version: 1.0.0
description: A command-line tool
homepage: https://github.com/username/my-cli
repository: https://github.com/username/my-cli.git
license: MIT

formula:
  tap: homebrew-tools
  asset: build/my-cli
  checksum: a1b2c3d4e5f6...
  dependencies:
    - openssl
```

### Cask 配置（macOS GUI）

```yaml
name: my-app
version: 1.0.0
description: A macOS application
homepage: https://github.com/username/my-app
repository: https://github.com/username/my-app.git
license: MIT

cask:
  tap: homebrew-cask
  asset: build/macos/my-app.zip
  app_name: MyApp.app
  checksum: a1b2c3d4e5f6...
```

### Scoop 配置（Windows GUI）

```yaml
name: my-app
version: 1.0.0
description: A Windows application
homepage: https://github.com/username/my-app
repository: https://github.com/username/my-app.git
license: MIT

scoop:
  bucket: username/scoop-bucket
  asset: build/windows/my-app.zip
  arch: 64bit
  checksum: a1b2c3d4e5f6...
  shortcuts:
    - MyApp
```

### 跨平台配置（Cask + Scoop）

```yaml
name: my-app
version: 1.0.0
description: A cross-platform GUI application
homepage: https://github.com/username/my-app
repository: https://github.com/username/my-app.git
license: MIT

cask:
  tap: homebrew-cask
  asset: build/macos/my-app.zip
  app_name: MyApp.app
  checksum: abc123...

scoop:
  bucket: username/scoop-bucket
  asset: build/windows/my-app.zip
  arch: 64bit
  checksum: def456...
```

### 配置字段说明

#### 顶层字段

| 字段 | 类型 | 必需 | 说明 |
|------|------|------|------|
| `name` | String | ✅ | 包名（只允许小写字母、数字和连字符） |
| `version` | String | ✅ | 版本号（遵循语义化版本规范） |
| `description` | String | ✅ | 包的描述信息 |
| `homepage` | String | ✅ | 项目主页 URL |
| `repository` | String | ✅ | Git 仓库地址 |
| `license` | String | ✅ | 许可证名称 |
| `formula` | Object | ❌ | Formula 子配置 |
| `cask` | Object | ❌ | Cask 子配置 |
| `scoop` | Object | ❌ | Scoop 子配置 |

> 至少需要配置一个分发目标（formula / cask / scoop）

#### Formula 子字段

| 字段 | 类型 | 必需 | 说明 |
|------|------|------|------|
| `tap` | String | ✅ | 目标 Tap 名称（如 `homebrew-tools` 或 `owner/tap`） |
| `asset` | String | ✅ | 二进制文件路径 |
| `checksum` | String | ❌ | 预计算的 SHA256 校验和 |
| `dependencies` | List | ❌ | Homebrew 依赖包列表 |

#### Cask 子字段

| 字段 | 类型 | 必需 | 说明 |
|------|------|------|------|
| `tap` | String | ✅ | 目标 Cask Tap 名称 |
| `asset` | String | ✅ | App 归档文件路径（.zip） |
| `app_name` | String | ✅ | App 名称（如 `MyApp.app`） |
| `checksum` | String | ❌ | 预计算的 SHA256 校验和 |

#### Scoop 子字段

| 字段 | 类型 | 必需 | 说明 |
|------|------|------|------|
| `bucket` | String | ✅ | Scoop bucket 仓库（如 `owner/scoop-bucket`） |
| `asset` | String | ✅ | App 归档文件路径（.zip） |
| `arch` | String | ❌ | 架构（`64bit` / `32bit` / `arm64`，默认 `64bit`） |
| `checksum` | String | ❌ | 预计算的 SHA256 校验和 |
| `shortcuts` | List | ❌ | Scoop shortcuts 列表 |

## 🛠️ 命令详解

### `init` - 初始化配置

创建或更新 `.tapster.yaml` 配置文件。默认配置 `formula` 目标，通过 `-t` 指定其他目标：

```bash
tapster init [选项]
```

**选项：**
- `-f, --force`: 强制覆盖已配置的目标
- `-t, --target`: 分发目标（`homebrew/formula` / `homebrew/cask` / `scoop`），默认 `formula`，可多次使用

**典型用法：**

```bash
# 首次创建（默认 homebrew/formula）
tapster init

# 为已有项目追加 cask 配置
tapster init -t homebrew/cask

# 为已有项目追加 scoop 配置
tapster init -t scoop

# 一次性配置多个目标
tapster init -t homebrew/cask -t scoop

# 强制覆盖已有的 formula 配置
tapster init -f
```

### `doctor` - 环境检查

```bash
tapster doctor [选项]
```

**选项：**
- `-v, --verbose`: 显示详细的诊断信息

**检查项目：**
- Git 版本和配置（user.name、user.email）
- GitHub CLI 安装和认证状态
- Homebrew 安装状态
- 网络连接和 GitHub API 访问

### `publish` - 发布包

```bash
tapster publish [选项]
```

**选项：**
- `-f, --force`: 强制覆盖已存在的版本发布
- `-t, --target`: 指定发布目标（`homebrew/formula` / `homebrew/cask` / `scoop`），可多次使用

**发布流程：**
1. 加载和验证配置文件
2. 创建 GitHub Release（如已存在则追加 asset）
3. 上传本地 asset 文件到 Release
4. 生成并推送 Formula → `Formula/{name}.rb`（如配置）
5. 生成并推送 Cask → `Casks/{name}.rb`（如配置）
6. 生成并推送 Scoop manifest → `{name}.json`（如配置）

**跨平台发布示例：**

```bash
# macOS 上（发布 Cask）
tapster publish -t homebrew/cask

# Windows 上（发布 Scoop，Release 已存在则追加 asset）
tapster publish -t scoop
```

### `upgrade` - 配置升级

更新 `.tapster.yaml` 中的 version 和 asset checksum：

```bash
tapster upgrade [选项]
```

**选项：**
- `-d, --dry-run`: 预览升级内容，不实际修改
- `-c, --config`: 指定配置文件路径
- `-t, --target`: 指定升级目标（`homebrew/formula` / `homebrew/cask` / `scoop`）

**流程：**
1. 加载配置，计算当前 asset 的 SHA256
2. 对比已有 checksum，如有变化则提示
3. 建议新版本号（patch +1）
4. 确认后更新配置并保存

## 🏗️ 项目架构

```
lib/
├── commands/                  # 命令层
│   ├── init_command.dart      # 交互式配置生成
│   ├── publish_command.dart   # 发布流程编排
│   ├── doctor_command.dart    # 环境检查
│   └── upgrade_command.dart   # 配置升级
├── services/                  # 服务层
│   ├── config_service.dart    # YAML 读/写/验证/迁移
│   ├── github_service.dart    # GitHub CLI 封装
│   ├── formula_service.dart   # Formula 模板渲染
│   ├── cask_service.dart      # Cask 模板渲染
│   ├── scoop_service.dart     # Scoop manifest 生成
│   ├── asset_service.dart     # 资源处理与哈希计算
│   ├── dependency_service.dart # 依赖聚合
│   ├── git_service.dart       # Git 操作
│   ├── homebrew_service.dart  # Homebrew 集成
│   └── network_service.dart   # 网络检查
├── models/                    # 数据模型
│   └── tapster_config.dart    # 配置模型 (TapsterConfig / FormulaConfig / CaskConfig / ScoopConfig)
└── utils/                     # 工具类
    ├── config_validator.dart  # 配置验证
    ├── status_markers.dart    # 状态标记
    └── string_buffer_extensions.dart # 彩色输出
```

## 🔧 开发

### 环境设置

```bash
git clone https://github.com/tapster/tapster.git
cd tapster
dart pub get
```

### 常用命令

```bash
# 代码分析
dart analyze

# 运行测试
dart test

# 开发模式运行
dart run bin/tapster.dart [command]

# 构建可执行文件
dart compile exe bin/tapster.dart -o tapster
```

## 📝 示例工作流

### 新项目发布（单平台）

```bash
mkdir my-cli && cd my-cli
# 默认 homebrew/formula
tapster init
# ... 构建二进制 ...
tapster doctor
tapster publish
```

### 跨平台 GUI 发布

```bash
# 1. 初始化（一次性配置两个目标）
mkdir my-app && cd my-app
tapster init -t homebrew/cask -t scoop

# 2. macOS 上构建并发布
# ... 构建 macOS .zip ...
tapster upgrade -t homebrew/cask
tapster publish -t homebrew/cask

# 3. Windows 上构建并发布
# ... 构建 Windows .zip ...
tapster upgrade -t scoop
tapster publish -t scoop
```

### 更新已有版本

```bash
# 重新构建后，升级配置并发布
tapster upgrade       # 自动更新 version + checksum
tapster publish       # 发布新版本
```

## 🐛 故障排除

### 常见问题

**1. GitHub CLI 认证失败**
```bash
gh auth login
gh auth status
```

**2. 配置文件验证失败**
```bash
tapster doctor -v
tapster init --force
```

**3. 发布权限不足**
- 确保对目标仓库有写入权限
- 检查 GitHub CLI 访问令牌权限

**4. Asset 文件未找到**
- 确保 `asset` 路径正确
- 使用 `checksum` 预置值可避免跨平台时 asset 不存在的问题
- 跨平台发布时使用 `-t` 指定当前平台的目标

**5. 跨平台发布时 scoop manifest 生成失败**
- 在配置中预置 `scoop.checksum`，避免依赖本地 asset 文件

## 🤝 贡献

欢迎贡献代码！

1. Fork 项目
2. 创建功能分支 (`git checkout -b feature/AmazingFeature`)
3. 提交更改 (`git commit -m 'Add some AmazingFeature'`)
4. 推送到分支 (`git push origin feature/AmazingFeature`)
5. 创建 Pull Request

## 📄 许可证

本项目采用 MIT 许可证。详情请参阅 [LICENSE](LICENSE) 文件。

## 🙏 致谢

- [Dart](https://dart.dev/) - 编程语言
- [GitHub CLI](https://cli.github.com/) - GitHub 命令行工具
- [Homebrew](https://brew.sh/) - macOS 包管理器
- [Scoop](https://scoop.sh/) - Windows 包管理器

---

**Made with ❤️ by the Tapster team**

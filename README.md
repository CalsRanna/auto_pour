# Tapster - 分发工具

Tapster 是一个用 Dart 编写的命令行工具，**只做分发（distribution）**：基于 `.tapster.yaml` 配置文件，生成 Homebrew Formula / Cask 和 Scoop manifest 分发产物。

tapster **不做**构建、不创建 GitHub Release、不上传 asset、不推送任何仓库——这些执行动作属于 CI。tapster 产出 manifest 文件，由你的 CI 流水线推送到对应的目标仓库。

支持跨平台发布——同一版本可在不同操作系统上分次构建，每个平台生成各自的分发产物。

## ✨ 功能特性

- 📝 **配置驱动**: 通过 `.tapster.yaml` 配置文件管理项目信息和发布设置
- 🎯 **多目标支持**: 同时支持 Homebrew Formula、Homebrew Cask、Scoop 三种分发目标
- 🌐 **跨平台分发**: 同一版本可在 macOS/Windows/Linux 上分次生成产物，Release 共享、仓库独立
- 🏗️ **模板生成**: 自动生成符合规范的 Formula/Cask Ruby 文件和 Scoop JSON manifest
- 📦 **资源管理**: 自动处理 SHA256 哈希值计算（配置预置优先）
- 🏷️ **版本来自 git tag**: 发布版本自动从最近 tag 解析，无需手动维护
- 🛡️ **配置验证**: 严格验证配置文件的完整性和正确性
- 🎯 **交互式配置**: 通过向导式界面生成项目配置，支持追加/覆盖
- 🔄 **配置升级**: `upgrade` 命令自动更新 version 和 checksum
- 🔍 **生成检查**: `doctor` 命令检查配置完整性与分发产物生成能力

**职责边界**：tapster 只负责"生成分发产物"。创建 Release、上传 asset、推送 manifest 到 tap/bucket 仓库全部由 CI 完成（见 [CI 集成](#-ci-集成)）。

## 📋 系统要求

- **Dart**: 3.9.0 或更高版本
- **Git**: 已安装（用于从 tag 解析版本号）

> 不需要 GitHub CLI、Homebrew 或网络认证——tapster 本地零网络操作。

## 🚀 快速开始

### 1. 安装 Tapster

```bash
# 克隆仓库
git clone https://github.com/CalsRanna/auto_pour.git
cd auto_pour

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

### 3. 检查配置与生成能力

```bash
# 检查配置完整性、checksum 可得性、git tag、输出目录
dart run bin/tapster.dart doctor

# 详细模式
dart run bin/tapster.dart doctor -v
```

### 4. 生成分发产物

```bash
# 生成所有已配置目标的分发产物（版本从最近 git tag 解析）
dart run bin/tapster.dart publish

# 指定输出目录
dart run bin/tapster.dart publish -o dist

# 只生成指定目标
dart run bin/tapster.dart publish -t homebrew/cask

# 显式指定版本（跳过 tag 解析）
dart run bin/tapster.dart publish --version 2.0.0
```

产物结构（直接对应目标仓库布局）：

```
dist/
├── Formula/tapster.rb    # → Homebrew tap 的 Formula/ 目录
├── Casks/MyApp.rb        # → Cask tap 的 Casks/ 目录
└── my-app.json           # → Scoop bucket 的根目录
```

## 🔄 典型工作流

```bash
# 1. 初始化配置（一次性）
tapster init -t homebrew/cask -t scoop

# 2. 构建（按项目实际情况，此处以 tapster 自身为例）
dart compile exe bin/tapster.dart -o build/tapster

# 3. 升级配置：计算新 checksum、确认版本
tapster upgrade

# 4. 打 tag（发布版本以 tag 为准）
git tag v2.0.0 && git push origin v2.0.0

# 5. 生成分发产物
tapster publish -o dist

# 6. 推送到目标仓库（CI 完成，见下节）
```

## 🤖 CI 集成

tapster 的发布执行全部在 CI 中完成。以下是一个完整的 GitHub Actions workflow 示例：

```yaml
name: Publish
on:
  push:
    tags: ['v*']

jobs:
  publish:
    runs-on: ubuntu-latest
    permissions:
      contents: write
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0          # 需要 tag 历史

      # 1. 构建（按项目实际情况填写）
      - run: dart compile exe bin/tapster.dart -o build/tapster

      # 2. 安装 tapster 并生成分发产物（版本自动取自 git tag）
      - run: |
          dart pub get
          dart compile exe bin/tapster.dart -o tapster
          ./tapster publish -o dist

      # 3. 创建 Release 并上传 asset
      - run: |
          gh release create "v$(git describe --tags --abbrev=0)" \
            build/tapster --generate-notes

      # 4. 推送 manifest 到 tap 仓库（Contents API）
      #    需要目标仓库的写权限：请使用带该权限的独立 token
      - run: |
          gh api -X PUT repos/{owner}/homebrew-taps/contents/Formula/tapster.rb \
            -f message="release v$(git describe --tags --abbrev=0)" \
            -f content="$(base64 < dist/Formula/tapster.rb)" \
            -f branch=main
```

### 跨平台发布

macOS / Windows 的构建产物分别在不同平台上构建，Release 共享、manifest 各自推送：

```yaml
jobs:
  publish-macos:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4
        with: { fetch-depth: 0 }
      - run: # ... 构建 macOS 产物 ...
      - run: tapster publish -t homebrew/cask -o dist
      - run: gh release create "v$(git describe --tags --abbrev=0)" build/macos/*.zip --generate-notes || true
      - run: # ... 推送 dist/Casks/*.rb 到 cask tap ...

  publish-windows:
    runs-on: windows-latest
    steps:
      - uses: actions/checkout@v4
        with: { fetch-depth: 0 }
      - run: # ... 构建 Windows 产物 ...
      - run: tapster publish -t scoop -o dist
      - run: gh release upload "v$(git describe --tags --abbrev=0)" build/windows/*.zip || true
      - run: # ... 推送 dist/*.json 到 bucket ...
```

> `gh release create` 仅在首次触发时创建 Release；第二个平台用 `gh release upload` 追加 asset（`|| true` 容忍 asset 已存在）。

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
>
> `version` 是"期望版本"，实际发布版本以 git tag 为准（不一致时 publish 会警告）

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

### `publish` - 生成分发产物

读取配置并生成分发产物到输出目录。**不执行任何远程操作**——创建 Release、上传 asset、推送 manifest 由 CI 完成。

```bash
tapster publish [选项]
```

**选项：**
- `-o, --output`: 输出目录（默认 `dist`）
- `--version`: 发布版本（默认从最近 git tag 解析，如 `v1.2.3` → `1.2.3`）
- `-t, --target`: 指定目标（`homebrew/formula` / `homebrew/cask` / `scoop`），可多次使用

**生成流程：**
1. 加载和验证配置文件
2. 解析版本（`--version` 优先，否则取最近 git tag；与配置 version 不一致时警告）
3. 生成 Formula → `dist/Formula/{name}.rb`（如配置）
4. 生成 Cask → `dist/Casks/{name}.rb`（如配置）
5. 生成 Scoop manifest → `dist/{name}.json`（如配置）

**checksum 解析**：配置预置值优先；未预置时从本地 asset 计算；两者皆无则报错。

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

> 发布版本最终以 git tag 为准，upgrade 后记得打 tag：`git tag v1.1.0 && git push origin v1.1.0`

### `doctor` - 生成能力检查

检查配置完整性与分发产物生成能力：

```bash
tapster doctor [选项]
```

**选项：**
- `-v, --verbose`: 显示详细的诊断信息

**检查项目：**
- 配置文件存在且通过验证
- 至少配置了一个分发目标
- 每个目标的 checksum 可得（配置预置，或 asset 本地存在）
- git 仓库中可解析 tag（发布前提，警告级）
- 输出目录可写

## 🏗️ 项目架构

```
lib/
├── commands/                  # 命令层
│   ├── init_command.dart      # 交互式配置生成
│   ├── publish_command.dart   # 分发产物生成（版本从 git tag 解析）
│   ├── doctor_command.dart    # 配置/生成能力检查
│   └── upgrade_command.dart   # 配置升级
├── services/                  # 服务层
│   ├── config_service.dart    # YAML 读/写/验证/迁移
│   ├── formula_service.dart   # Formula 模板渲染
│   ├── cask_service.dart      # Cask 模板渲染
│   ├── scoop_service.dart     # Scoop manifest 生成
│   ├── asset_service.dart     # 资源处理与哈希计算
│   └── git_service.dart       # git tag 解析
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
git clone https://github.com/CalsRanna/auto_pour.git
cd auto_pour
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
git tag v1.0.0
tapster publish -o dist
# CI：创建 Release、上传 asset、推送 dist/Formula/*.rb 到 tap
```

### 跨平台 GUI 发布

```bash
# 1. 初始化（一次性配置两个目标）
mkdir my-app && cd my-app
tapster init -t homebrew/cask -t scoop

# 2. macOS 上构建并生成产物
# ... 构建 macOS .zip ...
tapster upgrade -t homebrew/cask
tapster publish -t homebrew/cask -o dist

# 3. Windows 上构建并生成产物
# ... 构建 Windows .zip ...
tapster upgrade -t scoop
tapster publish -t scoop -o dist

# 4. CI 分别推送两个平台的 manifest
```

## 🐛 故障排除

**1. publish 报 "No git tag found"**
```bash
git tag v1.0.0
# 或显式指定版本
tapster publish --version 1.0.0
```

**2. 配置文件验证失败**
```bash
tapster doctor -v
tapster init --force
```

**3. checksum 不可得（asset 不在本地也未预置）**
- 在 `.tapster.yaml` 中预置 `checksum`（`tapster upgrade` 可计算）
- 跨平台发布时，各平台在本地构建后分别执行 `upgrade` + `publish -t`

**4. 发布版本与配置版本不一致的警告**
- 正常现象：publish 以 git tag 为准
- 想同步：运行 `tapster upgrade` 更新配置

**5. CI 推送 manifest 到目标仓库失败**
- 确认 CI 使用的 token 对目标仓库（tap/bucket）有写权限
- Contents API 需要 `repo` scope

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
- [Homebrew](https://brew.sh/) - macOS 包管理器
- [Scoop](https://scoop.sh/) - Windows 包管理器

---

**Made with ❤️ by the Tapster team**

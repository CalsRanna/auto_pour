# Tapster - 分发工具

Tapster 是一个用 Dart 编写的命令行工具，**只做分发（distribution）**：读取远端仓库的 Release 信息（tag + asset digest），基于 `.tapster.yaml` 配置生成 Homebrew Formula / Cask 和 Scoop manifest，并写入用户设置的托管仓库（tap / bucket）。

**职责边界**：

```
被发布仓库（仓库 B）自己的 CI：构建 → 打 tag → 创建 Release → 上传 asset
  只碰自己的仓库，GITHUB_TOKEN 足够，零跨仓库凭据

tapster（发布侧，本地，gh 已登录）：读远端 Release 信息 → 生成 manifest → 写入托管仓库
```

tapster **不做**构建、不创建 Release、不上传 asset——这些是被发布仓库自己的 CI 的职责。tapster 的"分发"是：读远端状态（gh 已登录可读公开数据）、生成 manifest、写托管仓库（本地凭据写用户自己的仓库）。

支持跨平台发布——同一版本可在不同操作系统上分次构建，每个平台生成各自的分发产物。

## ✨ 功能特性

- 📝 **配置驱动**: 通过 `.tapster.yaml` 配置文件管理项目信息和发布设置
- 🎯 **多目标支持**: 同时支持 Homebrew Formula、Homebrew Cask、Scoop 三种分发目标
- 🌐 **跨平台分发**: 同一版本可在 macOS/Windows/Linux 上分次生成产物，Release 共享、仓库独立
- 🏷️ **版本来自远端 Release**: 发布版本自动从远端最新 Release tag 解析（`--version` 可覆盖），配置**不含版本号**，生成后无需修改
- 📦 **权威 checksum**: 自动从远端 Release asset 读取 digest（sha256），跨环境构建也一致
- 🏗️ **模板生成**: 自动生成符合规范的 Formula/Cask Ruby 文件和 Scoop JSON manifest
- 📤 **推送托管仓库**: 生成后自动写入托管仓库（Homebrew tap / Scoop bucket），用本地 gh 凭据
- 🛡️ **配置验证**: 严格验证配置文件的完整性和正确性
- 🎯 **交互式配置**: 通过向导式界面生成项目配置，支持追加/覆盖
- 🛠️ **托管仓库自动创建**: `init` 保存配置后自动创建分发所需的 tap/bucket（幂等，`--private` / `--yes` 控制）
- 🔍 **就绪检查**: `doctor` 命令检查配置、gh 认证、checksum 可得性、远端 Release

## 📋 系统要求

- **Dart**: 3.9.0 或更高版本
- **Git**: 已安装（版本解析的 fallback 来源）
- **GitHub CLI**: 已安装并认证（`gh auth login`）——读取远端 Release、推送托管仓库都依赖它

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
# 首次创建（默认 homebrew/formula + scoop —— CLI 工具形态，建 tap + bucket）
tapster init

# CLI 工具只需 formula（macOS/Linux）
tapster init -t homebrew/formula

# GUI 应用形态：cask + scoop（cask 进同一个 tap 的 Casks/ 目录）
tapster init -t homebrew/cask -t scoop
```

### 3. 检查分发就绪状态

```bash
# 检查配置完整性、gh 认证、远端 Release、checksum 可得性、输出目录
dart run bin/tapster.dart doctor

# 详细模式
dart run bin/tapster.dart doctor -v
```

### 4. 分发

```bash
# 发布所有已配置目标（默认：读远端 Release → 生成 manifest → 推送托管仓库）
dart run bin/tapster.dart publish

# 只生成不推送（预览产物）
dart run bin/tapster.dart publish --dry-run

# 只分发指定目标
dart run bin/tapster.dart publish -t homebrew/cask

# 显式指定版本（跳过远端 Release tag 解析）
dart run bin/tapster.dart publish --version 2.0.0
```

产物会生成到 `dist/`（可用 `-o` 指定），结构直接对应目标仓库布局：

```
dist/
├── Formula/tapster.rb    # → Homebrew tap 的 Formula/ 目录
├── Casks/MyApp.rb        # → Cask tap 的 Casks/ 目录
└── my-app.json           # → Scoop bucket 的根目录
```

## 🔄 典型工作流

```bash
# 1. 初始化配置 + 创建托管仓库（一次性；仓库已存在自动跳过，幂等）
tapster init -t homebrew/formula -t scoop
#   …问答结束保存配置后，提示创建托管仓库 (Y/n)…
#   ✓ Configuration saved to .tapster.yaml
#   ✓ Repository created: CalsRanna/homebrew-tap
#   ✓ Repository created: CalsRanna/scoop-bucket
#   自定义仓库名：init 时手动输入；--private 私有、--yes 跳过确认
#   （注意私有 bucket 无法被 scoop 安装）

# 2. 构建并打 tag（被发布仓库自己的 CI 会构建并创建 Release）
git tag v2.0.0 && git push origin v2.0.0
#   → 仓库 B 的 CI：构建 → 创建 Release v2.0.0 → 上传 asset

# 3. 分发（等 Release 建好后，发布侧执行）
tapster publish
#   → 读远端 Release v2.0.0 + asset digest
#   → 生成 manifest（checksum 与已发布 asset 一致）
#   → 推送托管仓库
```

## 🤖 被发布仓库的 CI

**tapster 不需要在 CI 里跑**——它跑在发布侧（通常是开发者的本地，gh 已登录）。被发布仓库（仓库 B）自己的 CI 只负责构建和 Release：

```yaml
# .github/workflows/publish.yml —— 放在被发布仓库（如你分发的工具仓库）
name: Publish
on:
  push:
    tags: ['v*']

permissions:
  contents: write

jobs:
  publish:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0

      # 1. 构建（按项目实际情况填写）
      - run: dart compile exe bin/tapster.dart -o build/tapster

      # 2. 创建 Release 并上传 asset（只碰当前仓库，GITHUB_TOKEN 足够）
      - run: gh release create "${{ github.ref_name }}" build/tapster --generate-notes
        env:
          GH_TOKEN: ${{ github.token }}
```

Release 建好后，在发布侧（本地）执行 `tapster publish`：

```bash
tapster publish
# 输出示例：
#   Remote release: v2.0.0 (1 asset(s) with digest)
#   ✓ Formula pushed to CalsRanna/homebrew-tap
```

### 跨平台发布

Dart AOT 编译不支持交叉编译：每个平台在对应 runner 上构建，**asset 名带平台后缀**（tapster 按 asset 文件名匹配远端 digest，URL 与 checksum 才能对得上）：

```yaml
jobs:
  # 先建空 Release（各平台 job 并行 upload，必须先存在）
  create-release:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: gh release create "${{ github.ref_name }}" --generate-notes
        env:
          GH_TOKEN: ${{ github.token }}

  publish:
    needs: create-release
    strategy:
      fail-fast: false
      matrix:
        include:
          - os: macos-latest
            asset: my-cli-macos
          - os: ubuntu-latest
            asset: my-cli-linux
          - os: windows-latest
            asset: my-cli-windows.exe
    runs-on: ${{ matrix.os }}
    steps:
      - uses: actions/checkout@v4
        with: { fetch-depth: 0 }
      - run: dart compile exe bin/main.dart -o build/${{ matrix.asset }}
      - run: gh release upload "${{ github.ref_name }}" "build/${{ matrix.asset }}" --clobber
        env:
          GH_TOKEN: ${{ github.token }}
```

> `gh release create` 先建空 Release；各平台 job 用 `gh release upload` 并行追加 asset（`--clobber` 容忍重跑）。tag 名用 `${{ github.ref_name }}`（含 `v` 前缀，不要写成 `v${{ github.ref_name }}`）；**不要用 `$GITHUB_REF_NAME`**——Windows runner 默认 shell 是 PowerShell，会把 `$GITHUB_REF_NAME` 展开成空字符串，导致 `gh release upload` 报 release not found。
>
> 之后在发布侧分平台执行 `tapster publish -t homebrew/formula`（macOS / Linux）或 `tapster publish -t scoop`（Windows），各自推送托管仓库。由于 checksum 来自远端 asset digest（按 asset 文件名匹配），跨平台构建也保持一致。

## ⚙️ 配置文件

Tapster 使用 `.tapster.yaml` 配置文件管理项目信息，支持嵌套的 formula/cask/scoop 子配置：

### Formula 配置（CLI 工具）

```yaml
name: my-cli
# 无需 version：发布版本由远端 Release tag 自动解析
description: A command-line tool
homepage: https://github.com/username/my-cli
repository: https://github.com/username/my-cli.git
license: MIT

formula:
  tap: username/tap          # → 仓库 username/homebrew-tap
  asset: build/my-cli
  # checksum 由远端 asset digest 自动解析（可选 fallback，一般无需填写）
  dependencies:
    - openssl
```

### Cask 配置（macOS GUI）

```yaml
name: my-app
description: A macOS application
homepage: https://github.com/username/my-app
repository: https://github.com/username/my-app.git
license: MIT

cask:
  tap: username/tap          # → 仓库 username/homebrew-tap
  asset: build/macos/my-app.zip
  app_name: MyApp.app
```

### Scoop 配置（Windows GUI）

```yaml
name: my-app
description: A Windows application
homepage: https://github.com/username/my-app
repository: https://github.com/username/my-app.git
license: MIT

scoop:
  bucket: username/scoop-bucket # 一个 bucket 托管所有工具
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
| `version` | String | ❌ | 可选；发布版本由远端 Release tag 自动解析，通常无需填写 |
| `description` | String | ✅ | 包的描述信息 |
| `homepage` | String | ✅ | 项目主页 URL |
| `repository` | String | ✅ | Git 仓库地址 |
| `license` | String | ✅ | 许可证名称 |
| `formula` | Object | ❌ | Formula 子配置 |
| `cask` | Object | ❌ | Cask 子配置 |
| `scoop` | Object | ❌ | Scoop 子配置 |

> 至少需要配置一个分发目标（formula / cask / scoop）
>
> `version` 可选且无需维护：配置生成后不再变化，版本始终来自远端 Release

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
| `bucket` | String | ✅ | Scoop bucket 仓库（如 `owner/scoop-bucket`，仓库名即 bucket 名） |
| `asset` | String | ✅ | App 归档文件路径（.zip） |
| `arch` | String | ❌ | 架构（`64bit` / `32bit` / `arm64`，默认 `64bit`） |
| `checksum` | String | ❌ | 预计算的 SHA256 校验和 |
| `shortcuts` | List | ❌ | Scoop shortcuts 列表 |

## 🛠️ 命令详解

### `init` - 初始化配置 + 创建托管仓库

创建或更新 `.tapster.yaml` 配置文件（版本由远端 Release 解析，配置生成后无需修改）。保存配置后引导创建分发所需的托管仓库（tap/bucket），已存在的自动跳过：

```bash
tapster init [选项]
```

**选项：**
- `-f, --force`: 强制覆盖已配置的目标
- `-t, --target`: 分发目标（`homebrew/formula` / `homebrew/cask` / `scoop`），默认 `homebrew/formula + scoop`（CLI 工具形态），可多次使用
- `--private`: 创建私有托管仓库（注意私有 bucket 无法被 scoop 安装）
- `-y, --yes`: 跳过仓库创建确认

### `publish` - 分发

读取远端 Release 信息，生成分发产物并推送到托管仓库：

```bash
tapster publish [选项]
```

**选项：**
- `--dry-run`: 只生成产物到 `-o` 目录，不推送托管仓库
- `-o, --output`: 输出目录（默认 `dist`）
- `--version`: 发布版本（默认从远端最新 Release tag 解析，如 `v1.2.3` → `1.2.3`）
- `-t, --target`: 指定目标（`homebrew/formula` / `homebrew/cask` / `scoop`），可多次使用

**分发流程：**
1. 加载和验证配置文件
2. 读远端最新 Release（`gh api`）：tag 作为版本号，asset digest 作为 checksum
3. 生成 Formula → `dist/Formula/{name}.rb`（如配置）
4. 生成 Cask → `dist/Casks/{name}.rb`（如配置）
5. 生成 Scoop manifest → `dist/{name}.json`（如配置）
6. 推送到托管仓库：formula → `Formula/{name}.rb`、cask → `Casks/{name}.rb`、
   scoop → `{name}.json`（`--dry-run` 跳过此步）

**版本解析优先级**：`--version` > 远端最新 Release tag > 本地 git tag。

**checksum 解析优先级**：远端 Release asset digest（权威，与已发布 asset 一致）>
配置预置 > 本地 asset 计算。

**托管仓库解析**：`tap: owner/tap` → 仓库 `owner/homebrew-tap`（Homebrew
命名规范，已带 `homebrew-` 前缀则不重复）；`bucket: owner/scoop-bucket` → 直接推送
`owner/scoop-bucket`（仓库名即 bucket 名）。一个 tap/bucket 可托管多个工具，
按工具名分发不同 manifest 即可。

### `doctor` - 分发就绪检查

检查分发所需的前置条件：

```bash
tapster doctor [选项]
```

**选项：**
- `-v, --verbose`: 显示详细的诊断信息

**检查项目：**
- 配置文件存在且通过验证
- 至少配置了一个分发目标
- gh 已安装并认证（读取远端 Release、推送托管仓库的依赖）
- 远端 Release 可达（tag + asset digest 可读）
- 每个目标的 checksum 可得（远端 digest / 配置预置 / 本地 asset，任一即可）
- git 仓库中可解析 tag（版本 fallback，警告级）
- 输出目录可写

## 🏗️ 项目架构

```
lib/
├── commands/                  # 命令层
│   ├── init_command.dart      # 交互式配置生成 + 创建托管仓库（幂等）
│   ├── publish_command.dart   # 分发：读远端 Release → 生成 → 推送托管仓库
│   └── doctor_command.dart    # 分发就绪检查
├── services/                  # 服务层
│   ├── config_service.dart    # YAML 读/写/验证/迁移
│   ├── github_service.dart    # gh 封装：远端 Release 读取 + Contents API 推送 + 仓库创建
│   ├── formula_service.dart   # Formula 模板渲染
│   ├── cask_service.dart      # Cask 模板渲染
│   ├── scoop_service.dart     # Scoop manifest 生成
│   ├── asset_service.dart     # 资源处理与哈希计算
│   └── git_service.dart       # git tag 解析（版本 fallback）
├── models/                    # 数据模型
│   └── tapster_config.dart    # 配置模型 (TapsterConfig / FormulaConfig / CaskConfig / ScoopConfig)
└── utils/                     # 工具类
    ├── config_validator.dart  # 配置验证
    ├── repo_utils.dart        # 仓库 URL / tap 名解析
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
# 默认 homebrew/formula + scoop（CLI 形态；只要 formula 用 -t homebrew/formula）
tapster init
# ... 构建二进制 ...

# 1. 打 tag → 仓库 B 的 CI 构建并创建 Release
git tag v1.0.0 && git push origin v1.0.0

# 2. 等 Release 建好后，本地分发
tapster doctor
tapster publish
# → 读远端 v1.0.0 + asset digest → 生成 formula → 推 homebrew-tap
```

### 跨平台 GUI 发布

```bash
# 1. 初始化（一次性配置两个目标）
mkdir my-app && cd my-app
tapster init -t homebrew/cask -t scoop

# 2. 打 tag → 仓库 B 的 CI 分别构建 macOS/Windows 产物并上传到同一 Release
git tag v2.0.0 && git push origin v2.0.0

# 3. macOS 上分发 cask（checksum 自动取远端 macOS asset 的 digest）
tapster publish -t homebrew/cask

# 4. Windows 上分发 scoop（checksum 自动取远端 Windows asset 的 digest）
tapster publish -t scoop
```

## 🐛 故障排除

**1. publish 报 "No release found ... no local git tag"**
- 先让仓库 B 的 CI 打 tag 并创建 Release
- 或显式指定版本：`tapster publish --version 1.0.0`

**2. 配置文件验证失败**
```bash
tapster doctor -v
tapster init --force
```

**3. gh 未认证（读取远端、推送托管仓库都依赖 gh）**
```bash
gh auth login
gh auth status
```

**4. 远端 Release 没有 asset digest 时 checksum 不可得**
- 在 `.tapster.yaml` 中预置 `checksum`（fallback 来源）
- 或本地有 asset 时 tapster 自动计算

**5. 推送托管仓库失败**
- 确认本地 gh 登录的账号对托管仓库（tap/bucket）有写权限
- 确认 tap 命名正确：`owner/tap` 对应仓库 `owner/homebrew-tap`

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

# Tapster - 分发工具

Tapster 是一个命令行工具，帮你把 GitHub 上的工具**一键分发到 Homebrew 和 Scoop**：

```
你打一个 tag（v1.2.3）
  → 云端 CI 自动构建三个平台的二进制并创建 GitHub Release
  → 你运行 tapster publish
  → macOS 用户 brew install 你的工具，Windows 用户 scoop install 你的工具
```

之后每次发版，重复这两步即可，全程不需要手动上传文件、手算校验和、手写安装脚本。

**职责边界**：

```
被发布仓库（你的工具仓库）自己的 CI：构建 → 打 tag → 创建 Release → 上传 asset
  只碰自己的仓库，GITHUB_TOKEN 足够，零跨仓库凭据

tapster（发布侧，本地，gh 已登录）：读远端 Release 信息 → 生成 manifest → 写入托管仓库
```

tapster **不做**构建、不创建 Release、不上传 asset——这些是你工具仓库 CI 的职责。tapster 的"分发"是：读远端状态（gh 已登录可读公开数据）、生成 manifest、写托管仓库（本地凭据写用户自己的仓库）。

## ✨ 功能特性

- 📝 **配置驱动**: 通过 `.tapster.yaml` 配置文件管理项目信息和发布设置
- 🎯 **多目标支持**: 同时支持 Homebrew Formula、Homebrew Cask、Scoop 三种分发目标
- 🏷️ **版本与校验和自动解析**: 版本来自远端 Release tag，checksum 来自远端 asset digest（GitHub 官方 digest 字段），**配置生成后永不修改**，杜绝手填校验和
- 🌐 **双平台 Formula**: 配置 `linux_asset` 后生成 `if OS.mac? ... else ... end` 条件 formula，Linux 用户 brew install 装到正确二进制
- 🛡️ **就绪检查**: `doctor` 检查配置、gh 认证、远端 Release、asset 完整性、checksum 可得性
- 🔍 **精确版本分发**: `publish --version` 按 tag 精确读取对应 Release 的 digest，不会串版本
- 📤 **推送托管仓库**: 生成后自动写入托管仓库（Homebrew tap / Scoop bucket），用本地 gh 凭据

## 📋 系统要求

- **Dart**: 3.9.0 或更高版本（仅编译时；已安装 tapster 可忽略）
- **Git**: 已安装
- **GitHub CLI**: 已安装并认证（`gh auth login`）——读取远端 Release、推送托管仓库都依赖它

## 🚀 快速开始（新工具从零接入）

假设你有一个 GitHub 仓库 `you/awesome-cli`，想让它能被 `brew install awesome-cli` 和 `scoop install awesome-cli` 安装。

### 第 1 步：安装 tapster（一次性）

```bash
brew tap CalsRanna/tap
brew install tapster
```

### 第 2 步：登录 gh（一次性）

```bash
gh auth login
gh auth status   # 确认已认证
```

### 第 3 步：给你的工具仓库加 Release 流水线（一次性）

在工具仓库创建 `.github/workflows/release.yml`，**照抄下面这个模板**，只需改三处：工具名、编译命令、打包方式：

```yaml
name: Release

on:
  push:
    tags: ['v*']

permissions:
  contents: write

jobs:
  # 先建空 Release（各平台 job 并行 upload，必须先存在）
  # --draft=false 显式发布：草稿 Release 会被 tapster 忽略；
  # 已存在则跳过，保证重跑幂等
  create-release:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: gh release view "${{ github.ref_name }}" >/dev/null 2>&1 || gh release create "${{ github.ref_name }}" --generate-notes --draft=false
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

      - uses: dart-lang/setup-dart@v1
        with:
          sdk: 3.10.1

      - run: dart pub get

      - name: Resolve version from pubspec
        shell: bash
        run: |
          VERSION=$(grep '^version:' pubspec.yaml | awk '{print $2}')
          echo "VERSION=$VERSION" >> "$GITHUB_ENV"

      - name: Compile
        shell: bash
        run: |
          mkdir -p build    # CI 没有本地 build 目录，必须显式创建
          dart compile exe bin/main.dart -o "build/${{ matrix.asset }}" -DAPP_VERSION="$VERSION"

      - name: Upload asset
        shell: bash
        run: gh release upload "${{ github.ref_name }}" "build/${{ matrix.asset }}" --clobber
        env:
          GH_TOKEN: ${{ github.token }}
```

**asset 命名契约**（重要）：asset 名必须带平台后缀（`my-cli-macos` / `my-cli-linux` / `my-cli-windows.exe`），tapster 按 asset **文件名**匹配远端 digest，URL 与 checksum 才能对得上。三个平台的名字要与第 4 步配置里的 `asset` / `linux_asset` 完全一致。

**Windows 打包注意**：如果 Windows 产物是 zip（GUI 应用），zip 内的 exe 名必须等于 asset 基名 + `.exe`（`MyApp-Windows.zip` 内是 `MyApp-Windows.exe`），否则 scoop 安装后命令指向不存在的文件。不一致时要么在打包步骤重命名 exe，要么在第 4 步配置里显式声明 `bin:` 字段。

> 建议再加一个 `ci.yml`（push 触发 analyze + test，PR 也触发），保证每次推送云端自动验证编译。

### 第 4 步：初始化 tapster 配置（一次性）

在工具仓库目录执行：

```bash
tapster init -t homebrew/formula -t scoop
```

交互式问答生成 `.tapster.yaml`（保存后会自动引导创建托管仓库；**建议所有工具共用一个 tap**：tap 填 `you/tap`，bucket 填 `you/scoop-bucket`——一个 tap/bucket 托管所有工具，后续新工具直接跳过建仓库步骤）。

也可以手写，最小配置如下：

```yaml
name: my-cli                        # 用户安装后的命令名（小写+连字符）
description: What my tool does
homepage: https://github.com/you/awesome-cli
repository: https://github.com/you/awesome-cli.git
license: MIT

formula:
  tap: you/tap                      # → 仓库 you/homebrew-tap
  asset: build/my-cli-macos         # 与 release.yml 的 macOS asset 名一致
  linux_asset: build/my-cli-linux   # 可选；提供则双平台 formula
  dependencies: []                  # brew 依赖（如 gh）

scoop:
  bucket: you/scoop-bucket          # 仓库名即 bucket 名
  asset: build/my-cli-windows.exe   # 与 release.yml 的 Windows asset 名一致
  # bin: my-cli-windows.exe         # 仅当 zip 内 exe 名与 asset 基名不一致时
  shortcuts: []                     # GUI 应用可加开始菜单快捷方式
```

**注意**：不要写 `version` 和 `checksum`——版本来自远端 Release tag、checksum 来自远端 asset digest，配置写死反而会随构建过期。

### 第 5 步：发版（每次发布重复）

```bash
# 1. bump 版本号（pubspec.yaml: version: 1.0.0+1 → 1.0.1+2）
git commit -m "chore: bump version to 1.0.1+2" && git push

# 2. 打 tag 推送（纯 git 操作，本地不需要构建，云端自动构建三平台）
git tag v1.0.1 && git push origin v1.0.1

# 3. 等云端构建完成（GitHub Actions 页面或 gh run watch）
```

### 第 6 步：分发（每次发布重复）

```bash
tapster doctor      # 就绪检查：配置、gh、远端 Release、asset 完整性
tapster publish     # 生成 manifest 并推送托管仓库
# 输出示例：
#   Remote release: v1.0.1 (3 asset(s) with digest)
#   ✓ Formula pushed to you/homebrew-tap
#   ✓ Scoop manifest pushed to you/scoop-bucket
```

### 验证

```bash
# macOS（用户侧）
brew tap you/tap
brew install my-cli

# Windows（用户侧）
scoop bucket add scoop-bucket https://github.com/you/scoop-bucket
scoop install my-cli
```

## 🔄 典型工作流回顾

```bash
# 一次性
brew tap CalsRanna/tap && brew install tapster
cd my-tool && tapster init -t homebrew/formula -t scoop

# 每次发版
git tag v1.0.1 && git push origin v1.0.1   # → 云端构建 + Release
tapster doctor && tapster publish          # → 分发到 tap/bucket
```

## ⚙️ 配置文件

`.tapster.yaml` 支持嵌套的 formula/cask/scoop 子配置，字段说明：

### 顶层字段

| 字段 | 类型 | 必需 | 说明 |
|------|------|------|------|
| `name` | String | ✅ | 包名（只允许小写字母、数字和连字符），即用户安装后的命令名 |
| `version` | String | ❌ | 可选；发布版本由远端 Release tag 自动解析，通常无需填写 |
| `description` | String | ✅ | 包的描述信息 |
| `homepage` | String | ✅ | 项目主页 URL |
| `repository` | String | ✅ | Git 仓库地址 |
| `license` | String | ✅ | 许可证名称 |
| `formula` | Object | ❌ | Formula 子配置 |
| `cask` | Object | ❌ | Cask 子配置 |
| `scoop` | Object | ❌ | Scoop 子配置 |

> 至少需要配置一个分发目标（formula / cask / scoop）

### Formula 子字段（CLI 工具，macOS / Linux）

| 字段 | 类型 | 必需 | 说明 |
|------|------|------|------|
| `tap` | String | ✅ | 目标 Tap 名称（`you/tap` → 仓库 `you/homebrew-tap`） |
| `asset` | String | ✅ | macOS 二进制文件路径（远端 Release asset 文件名） |
| `linux_asset` | String | ❌ | Linux 二进制 asset。提供时生成 `if OS.mac? ... else ... end` 双平台 formula |
| `checksum` | String | ❌ | 预计算校验和（**不推荐**：远端 digest 权威，配置值会随构建过期） |
| `dependencies` | List | ❌ | Homebrew 依赖包列表 |

### Cask 子字段（macOS GUI）

| 字段 | 类型 | 必需 | 说明 |
|------|------|------|------|
| `tap` | String | ✅ | 目标 Cask Tap 名称（建议与 formula 共用 `you/tap`） |
| `asset` | String | ✅ | App 归档文件路径（.zip，内含 `.app` 在根目录） |
| `app_name` | String | ✅ | App 名称（如 `MyApp.app`） |

### Scoop 子字段（Windows）

| 字段 | 类型 | 必需 | 说明 |
|------|------|------|------|
| `bucket` | String | ✅ | Scoop bucket 仓库（如 `you/scoop-bucket`，仓库名即 bucket 名） |
| `asset` | String | ✅ | App 归档文件路径（.zip 或 .exe） |
| `bin` | String | ❌ | zip 内可执行文件名。缺省按 asset 基名推导（`X.zip` → `X.exe`），**zip 内二进制名与 asset 基名不一致时必须设置** |
| `arch` | String | ❌ | 架构（`64bit` / `32bit` / `arm64`，默认 `64bit`） |
| `shortcuts` | List | ❌ | Scoop shortcuts 列表 |

> Scoop manifest 的 `autoupdate.hash` 从 GitHub API 读取 asset digest
> （`api.github.com` 的 jsonpath 提取），因此 `scoop update` 升级时校验和始终与远端一致。

## 🛠️ 命令详解

### `init` - 初始化配置 + 创建托管仓库

```bash
tapster init [选项]
```

**选项：**
- `-f, --force`: 强制覆盖已配置的目标
- `-t, --target`: 分发目标（`homebrew/formula` / `homebrew/cask` / `scoop`），默认 `homebrew/formula + scoop`（CLI 工具形态），可多次使用
- `--private`: 创建私有托管仓库（注意私有 bucket 无法被 scoop 安装）
- `-y, --yes`: 跳过仓库创建确认

保存配置后引导创建分发所需的托管仓库（tap/bucket），已存在的自动跳过（幂等）。

### `publish` - 分发

```bash
tapster publish [选项]
```

**选项：**
- `--dry-run`: 只生成产物到 `-o` 目录，不推送托管仓库
- `-o, --output`: 输出目录（默认 `dist`）
- `--version`: 发布版本（默认从远端最新 Release tag 解析）。**指定时按 tag 精确读取对应 Release 的 digest**——远端没有该 Release 会直接报错，不会生成版本与校验和不匹配的 manifest
- `-t, --target`: 指定目标（`homebrew/formula` / `homebrew/cask` / `scoop`），可多次使用

**分发流程：**
1. 加载和验证配置文件
2. 读远端 Release 信息（`gh api`）：tag 作为版本号，asset digest 作为 checksum（在最近 10 个 Release 中优先选包含全部所需 asset 的；草稿 Release 会被忽略）
3. 生成 Formula / Cask / Scoop manifest
4. 推送到托管仓库（`--dry-run` 跳过此步）

**checksum 解析优先级**：远端 Release asset digest（权威）> 本地 asset 计算 > 配置预置（带过期警告）。

### `doctor` - 分发就绪检查

```bash
tapster doctor [选项]
```

**选项：**
- `-v, --verbose`: 显示详细的诊断信息

**检查项目：**
- 配置文件存在且通过验证
- 至少配置了一个分发目标
- gh 已安装并认证
- 远端 Release 可达（tag + asset digest 可读），所选 Release 是否缺 asset
- 每个目标的 checksum 可得（远端 digest / 本地 asset / 配置预置，任一即可）
- git 仓库中可解析 tag（版本 fallback，警告级）
- 输出目录可写

## 🐛 故障排除

| 症状 | 原因 | 解决 |
|------|------|------|
| `doctor` 显示旧版本 / 缺 asset | 最新 Release 是草稿，或该 Release 缺某个平台的 asset | `gh release edit vX.Y.Z --draft=false`；等 CI 上传完所有 asset 再 publish |
| publish 报 "No release found for tag vX.Y.Z" | `--version` 指定的 Release 不存在 | 先让 CI 创建该版本的 Release，或不传 `--version` |
| scoop 装完命令找不到 | zip 内 exe 名与 asset 基名不一致（`bin` 指向了不存在的文件） | 在 `.tapster.yaml` 显式声明 `bin:`，或在打包时重命名 exe |
| Linux 用户 brew 装到 macOS 二进制 | formula 没配 `linux_asset` | 配置 `linux_asset` 后重新 `tapster publish` |
| CI `dart pub get` 失败 "requires the Flutter SDK" | 项目依赖了 Flutter 插件（如 package_info_plus） | 纯 Dart CLI 移除该依赖（检查是否真的被引用） |
| CI 编译报 "Cannot open file ... build/xxx" | CI 没有本地 build 目录 | 编译前 `mkdir -p build` |
| publish 报 "No checksum available" | 远端无该 asset 的 digest、本地无文件、配置无 checksum | 先让 CI 创建 Release 并上传 asset，或检查 asset 名拼写 |
| brew 命令整体报错（如 `brew upgrade` 都失败） | tap 里某个 manifest 无效（如 cask 用了不支持的语法） | 修复并重新 publish 对应 manifest；tap 内所有 manifest 都会被 brew 解析 |
| 推送托管仓库失败 | 本地 gh 账号对托管仓库无写权限 | 确认托管仓库 owner 与 gh 登录账号一致 |

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
│   ├── formula_service.dart   # Formula 模板渲染（含双平台条件块）
│   ├── cask_service.dart      # Cask 模板渲染
│   ├── scoop_service.dart     # Scoop manifest 生成（autoupdate 走 GitHub API）
│   ├── asset_service.dart     # 资源处理、哈希计算、跨平台路径
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

## 📄 许可证

本项目采用 MIT 许可证。详情请参阅 [LICENSE](LICENSE)。

## 🙏 致谢

- [Dart](https://dart.dev/) - 编程语言
- [Homebrew](https://brew.sh/) - macOS 包管理器
- [Scoop](https://scoop.sh/) - Windows 包管理器

---

**Made with ❤️ by the Tapster team**

#!/bin/bash
# 本地构建（macOS）：输出名与 Release asset 名一致（tapster-macos），
# 便于 tapster upgrade/publish 按文件名匹配远端 digest。
# Linux / Windows 二进制由 CI 在对应 runner 上构建（Dart 不支持交叉编译）。

set -e

mkdir -p build
dart compile exe bin/tapster.dart -o build/tapster-macos

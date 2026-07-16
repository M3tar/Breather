# Breather

[English](README.md) | [简体中文](README.zh-CN.md)

Breather 是一款原生 macOS 菜单栏休息提醒应用。它会在工作时安静地显示倒计时，并在需要休息时呈现专注、清晰的全屏休息界面，帮助你暂时离开屏幕。

## 功能特点

- 菜单栏倒计时，支持开始、暂停、重置和立即休息。
- 可配置工作时长、短休息和长休息计划。
- 在多个显示器上显示全屏休息界面。
- 支持纯色、月亮和太阳休息背景。
- 支持延后、跳过和自动补休。
- 连续多次延后或跳过后显示额外提醒。
- 可配置菜单栏外观、主题色、进度样式和图标。
- 支持休息通知以及进入、结束休息时的提示音。
- 支持空闲检测，可将离开电脑的时间视为已经休息。
- 使用 macOS 原生登录项能力，可选择开机自动启动。
- 支持浅色、深色和跟随系统外观。

## 系统要求

- macOS 15 或更高版本。
- 从源码构建需要带有 macOS 15 SDK 的 Xcode。

## 下载安装

已经发布的版本可以在 [GitHub Releases](https://github.com/M3tar/Breather/releases) 页面下载。

下载所需版本的 DMG，打开后将 **Breather** 拖入 **Applications（应用程序）** 文件夹即可。

早期版本可能尚未使用 Apple Developer ID 签名，也可能尚未通过 Apple 公证。第一次打开时，macOS 可能显示安全提示。安装前请先查看对应版本的发布说明。

如果 macOS 阻止打开未签名版本，并且你已经确认安装包来自本仓库：

1. 先尝试打开一次 **Breather**，然后关闭系统警告。
2. 打开 **系统设置**，进入 **隐私与安全性**。
3. 向下滚动到 **安全性**，找到 Breather 并点击 **仍要打开**。
4. 在随后出现的确认窗口中点击 **打开**。

“仍要打开”按钮通常只会在应用被阻止后的一小时内出现。仅对来源可信的安装包执行此操作。详情参见 [Apple 关于打开身份不明开发者应用的说明](https://support.apple.com/zh-cn/guide/mac-help/open-a-mac-app-from-an-unknown-developer-mh40616/mac)。

## 从源码构建和运行

克隆仓库并打开 Xcode 工程：

```sh
git clone git@github.com:M3tar/Breather.git
cd Breather
open Breather.xcodeproj
```

在 Xcode 中选择 **Breather** Scheme，然后按 `Command + R` 运行。

也可以使用命令行构建：

```sh
xcodebuild \
  -project Breather.xcodeproj \
  -scheme Breather \
  -configuration Debug \
  -derivedDataPath build/DerivedData \
  CLANG_MODULE_CACHE_PATH=build/ModuleCache \
  build
```

仓库仍然提供 Swift Package 可执行目标，方便开发时快速运行：

```sh
swift run Breather
```

## 构建 DMG

使用以下命令生成压缩的发布 DMG：

```sh
./scripts/build-dmg.sh 0.1.0
```

生成的文件位于：

```text
dist/Breather-0.1.0.dmg
```

`build/` 和 `dist/` 保存自动生成的文件，不会提交到 Git 仓库。

## 项目结构

```text
Breather.xcodeproj/           Xcode 工程
Package.swift                 Swift Package 配置
Sources/Breather/App/         App 生命周期与入口
Sources/Breather/Core/        设置、规则和计时调度
Sources/Breather/Features/    菜单栏、设置和休息界面
Sources/Breather/System/      通知、空闲检测和登录项
Sources/Breather/Resources/   图片、背景和声音资源
scripts/build-dmg.sh          DMG 打包脚本
```

## 项目状态

Breather 目前仍在持续开发中。在 1.0 版本之前，界面、设置和发布方式都可能发生变化。

## 许可证

Breather 源代码采用 [MIT License](LICENSE) 开源。

Breather 原创图标由 M3tar 绘制。

相关声音和背景图片的版权归各自原权利人所有。这些素材不适用 Breather 源代码所采用的 MIT License。

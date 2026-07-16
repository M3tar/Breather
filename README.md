# Breather

[English](README.md) | [简体中文](README.zh-CN.md)

Breather is a native macOS menu bar app that gently reminds you to take regular breaks. It stays out of the way while you work, then presents a focused full-screen rest overlay when it is time to pause.

## Features

- Menu bar countdown with start, pause, reset, and rest-now actions.
- Configurable work, short-break, and long-break schedules.
- Full-screen rest overlays across multiple displays.
- Solid, moon, and sun rest backgrounds.
- Snooze, skip, and make-up rest flows.
- Reminders after several skipped or snoozed breaks.
- Configurable menu bar appearance, theme, progress style, and icon.
- Rest notifications and start/end sounds.
- Idle detection that can treat time away from the Mac as a completed rest.
- Optional launch at login using the native macOS login-item service.
- Light, dark, and system appearance modes.

## Requirements

- macOS 15 or later.
- Xcode with the macOS 15 SDK to build from source.

## Download

Published builds are available from [GitHub Releases](https://github.com/M3tar/Breather/releases).

Download the DMG for the version you want, open it, and drag **Breather** into the **Applications** folder.

Early releases may not yet be signed with an Apple Developer ID or notarized by Apple. In that case, macOS may show a security warning when the app is opened for the first time. Review the release notes before installing a build.

If macOS blocks an unsigned release and you have verified that it came from this repository:

1. Try to open **Breather** once, then close the warning.
2. Open **System Settings** and select **Privacy & Security**.
3. Scroll down to **Security** and click **Open Anyway** for Breather.
4. Confirm by clicking **Open** in the next dialog.

The **Open Anyway** button is available for about one hour after the blocked launch attempt. Only override this protection for a build you trust. See [Apple's guidance on opening an app from an unidentified developer](https://support.apple.com/guide/mac-help/open-a-mac-app-from-an-unknown-developer-mh40616/mac).

## Build and Run

Clone the repository and open the Xcode project:

```sh
git clone git@github.com:M3tar/Breather.git
cd Breather
open Breather.xcodeproj
```

Select the **Breather** scheme in Xcode, then press `Command + R`.

You can also build from the command line:

```sh
xcodebuild \
  -project Breather.xcodeproj \
  -scheme Breather \
  -configuration Debug \
  -derivedDataPath build/DerivedData \
  CLANG_MODULE_CACHE_PATH=build/ModuleCache \
  build
```

The repository also includes a Swift Package executable for quick development runs:

```sh
swift run Breather
```

## Build a DMG

Create a compressed release DMG with:

```sh
./scripts/build-dmg.sh 0.1.0
```

The resulting file is written to:

```text
dist/Breather-0.1.0.dmg
```

The `build/` and `dist/` directories contain generated files and are not committed to the repository.

## Project Structure

```text
Breather.xcodeproj/           Xcode project
Package.swift                 Swift Package configuration
Sources/Breather/App/         App lifecycle and entry points
Sources/Breather/Core/        Settings, rules, and scheduling
Sources/Breather/Features/    Menu bar, settings, and rest overlay UI
Sources/Breather/System/      Notifications, idle detection, and login item
Sources/Breather/Resources/   App images, backgrounds, and sounds
scripts/build-dmg.sh          DMG packaging script
```

## Status

Breather is under active development. Interfaces, settings, and release behavior may change before version 1.0.

## License

The Breather source code is available under the [MIT License](LICENSE).

The original Breather icons are created by M3tar. Copyright in the included sound effects and background images remains with their respective rights holders. These assets are not covered by the MIT License that applies to the Breather source code.

# Breather

[English](README.md) | [简体中文](README.zh-CN.md)

Breather is a native macOS menu bar app that gently reminds you to take regular breaks. It stays out of the way while you work, then presents a focused full-screen rest overlay when it is time to pause.

## Features

- Menu bar countdown with start, pause, reset, and rest-now actions.
- Configurable work and short-break schedules.
- Full-screen rest overlays across multiple displays.
- Solid, moon, and sun rest backgrounds.
- Snooze, skip, and make-up rest flows.
- Reminders after several skipped or snoozed breaks.
- Configurable menu bar appearance, theme, progress style, and icon.
- Rest notifications and start/end sounds.
- Idle detection that can treat time away from the Mac as a completed rest.
- Optional launch at login using the native macOS login-item service.
- Light, dark, and system appearance modes.

## Version History

### 0.2.0 — Settings and Pause Refinements

- Reorganized General, Schedule, and Rest Screen settings with native macOS controls and clearer hierarchy.
- Added optional automatic timer pause for AirPlay and wired display mirroring, without treating a running meeting app as active sharing.
- Improved pause and mirroring status presentation, including precise next-stage durations and recovery actions.
- Fixed numeric-field editing and next-cycle rule application so unapplied values no longer leak into the current cycle.
- Separated Xcode Debug notification identity from installed releases and added supported custom notification sounds.
- Updated new-user defaults, including a 30-minute work cycle, segmented progress, and mirroring protection enabled.

### 0.1.0 — Initial Public Preview

Breather 0.1.0 establishes the complete core break-reminder experience:

- Menu bar countdown with pause, resume, reset, and rest-now actions.
- Configurable work duration, short-break duration, pre-break notification timing, and idle threshold.
- Full-screen rest countdowns across every connected display.
- Solid, moon, and sun backgrounds, with customizable prompts, supporting text, translucency, and transitions.
- Snooze, skip, Esc-to-skip, and follow-up reminders after repeatedly missed breaks.
- Idle detection that recognizes time away from the Mac as a completed rest.
- Separate sounds for pre-break notifications, rest start, and rest completion.
- Custom menu bar icons, theme colors, progress styles, and center-square styles.
- Light, dark, and system appearance modes, automatic settings persistence, and optional launch at login.
- A universal DMG for both Apple silicon and Intel Macs.

See the [0.1.0 release notes](https://github.com/M3tar/Breather/releases/tag/v0.1.0) for the product overview and installation notes.

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

Xcode Debug builds use the separate display name **Breather Debug** and bundle identifier `com.mercury.breather.debug`. Installed release builds keep `com.mercury.breather`, so their notification permissions and settings are intentionally independent.

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
./scripts/build-dmg.sh 0.2.0
```

The resulting file is written to:

```text
dist/Breather-0.2.0.dmg
```

The script creates a Release archive, verifies the app and DMG, removes temporary DMG staging files, and unregisters Xcode's intermediate release app from LaunchServices.

When testing a DMG, quit **Breather Debug**, copy Breather to Applications, eject the mounted DMG, and launch only `/Applications/Breather.app`. If a development Mac has accumulated older release registrations, review and reset them with:

```sh
./scripts/reset-local-release-registration.sh --dry-run
./scripts/reset-local-release-registration.sh --apply
```

The reset script changes LaunchServices registration only. It never deletes an app or its settings.

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
scripts/reset-local-release-registration.sh
                              Local release-registration repair tool
```

## Status

Breather is under active development. Interfaces, settings, and release behavior may change before version 1.0.

## License

The Breather source code is available under the [MIT License](LICENSE).

The original Breather icons are created by M3tar. Copyright in the included sound effects and background images remains with their respective rights holders. These assets are not covered by the MIT License that applies to the Breather source code.

import AppKit
import SwiftUI
import Vision
import XCTest
@testable import Breather

@MainActor
final class MenuBarPauseVisualRegressionTests: XCTestCase {
    func testGeneralSettingsPickerValueUpdatesImmediately() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["BREATHER_WINDOW_TEST"] == "1",
            "Run this window-backed test separately from video rendering tests."
        )
        let previousLanguage = UserDefaults.standard.string(forKey: AppLanguage.preferenceKey)
        defer {
            if let previousLanguage {
                UserDefaults.standard.set(previousLanguage, forKey: AppLanguage.preferenceKey)
            } else {
                UserDefaults.standard.removeObject(forKey: AppLanguage.preferenceKey)
            }
            LocalizationRefresh.shared.refresh()
        }

        UserDefaults.standard.set(AppLanguage.simplifiedChinese.rawValue, forKey: AppLanguage.preferenceKey)
        let suiteName = "SettingsPickerLanguageSwitchTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let notificationService = VisualTestSettingsNotificationService()
        let view = GeneralSettingsScreen(
            settingsStore: SettingsStore(userDefaults: defaults),
            notificationService: notificationService,
            restSoundService: RestSoundService()
        )
        let hostingView = NSHostingView(rootView: view.frame(width: 760, height: 560))
        hostingView.frame = NSRect(x: 0, y: 0, width: 760, height: 560)
        let window = NSWindow(contentRect: hostingView.frame, styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hostingView
        window.makeKeyAndOrderFront(nil)
        defer {
            window.orderOut(nil)
            window.contentView = nil
            window.close()
        }

        func snapshot() throws -> NSBitmapImageRep {
            hostingView.layoutSubtreeIfNeeded()
            let bitmap = try XCTUnwrap(hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds))
            hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
            return bitmap
        }

        let chinese = try snapshot()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        let authorizationChecksBeforeSwitch = notificationService.authorizationCheckCount
        UserDefaults.standard.set(AppLanguage.english.rawValue, forKey: AppLanguage.preferenceKey)
        LocalizationRefresh.shared.refresh()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        let english = try snapshot()

        let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("BreatherVisualAudit")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try XCTUnwrap(chinese.representation(using: .png, properties: [:]))
            .write(to: directory.appendingPathComponent("picker-before-language-change.png"))
        try XCTUnwrap(english.representation(using: .png, properties: [:]))
            .write(to: directory.appendingPathComponent("picker-after-language-change.png"))

        let textRequest = VNRecognizeTextRequest()
        textRequest.recognitionLevel = .accurate
        textRequest.recognitionLanguages = ["en-US", "zh-Hans"]
        try VNImageRequestHandler(cgImage: try XCTUnwrap(english.cgImage), options: [:]).perform([textRequest])
        let englishText = (textRequest.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        let chineseRequest = VNRecognizeTextRequest()
        chineseRequest.recognitionLevel = .accurate
        chineseRequest.recognitionLanguages = ["zh-Hans"]
        try VNImageRequestHandler(cgImage: try XCTUnwrap(english.cgImage), options: [:]).perform([chineseRequest])
        let chineseText = (chineseRequest.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        // OCR can include the native popup arrows in the same text observation.
        XCTAssertTrue(englishText.contains { $0.contains("Match system") }, "Appearance picker should show its English value")
        XCTAssertTrue(englishText.contains { $0.contains("Achievement") }, "Sound picker should show its English value")
        XCTAssertFalse(chineseText.contains("跟随系统"), "Appearance picker kept a Chinese value")
        XCTAssertFalse(chineseText.contains("成就"), "Sound picker kept a Chinese value")
        XCTAssertEqual(
            notificationService.authorizationCheckCount,
            authorizationChecksBeforeSwitch,
            "Switching languages should not restart the settings screen's notification task"
        )
    }

    func testSidebarUpdatesWhenLanguageChangesWithoutNavigation() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["BREATHER_WINDOW_TEST"] == "1",
            "Run this window-backed test separately; it interferes with video rendering tests in the shared XCTest process."
        )
        let previousLanguage = UserDefaults.standard.string(forKey: AppLanguage.preferenceKey)
        defer {
            if let previousLanguage {
                UserDefaults.standard.set(previousLanguage, forKey: AppLanguage.preferenceKey)
            } else {
                UserDefaults.standard.removeObject(forKey: AppLanguage.preferenceKey)
            }
            LocalizationRefresh.shared.refresh()
        }

        UserDefaults.standard.set(AppLanguage.simplifiedChinese.rawValue, forKey: AppLanguage.preferenceKey)
        let sidebar = SettingsSidebar(
            selectedSection: .constant(.general),
            hasAvailableUpdate: false,
            onQuit: {}
        )
        let hostingView = NSHostingView(rootView: sidebar.frame(width: 200, height: 560))
        hostingView.frame = NSRect(x: 0, y: 0, width: 200, height: 560)
        let window = NSWindow(contentRect: hostingView.frame, styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hostingView
        window.makeKeyAndOrderFront(nil)
        defer {
            window.orderOut(nil)
            window.contentView = nil
            window.close()
        }

        func snapshot() throws -> NSBitmapImageRep {
            hostingView.layoutSubtreeIfNeeded()
            let bitmap = try XCTUnwrap(hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds))
            hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
            return bitmap
        }

        let chinese = try snapshot()
        UserDefaults.standard.set(AppLanguage.english.rawValue, forKey: AppLanguage.preferenceKey)
        LocalizationRefresh.shared.refresh()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        let english = try snapshot()

        let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("BreatherVisualAudit")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try XCTUnwrap(chinese.representation(using: .png, properties: [:]))
            .write(to: directory.appendingPathComponent("sidebar-before-language-change.png"))
        try XCTUnwrap(english.representation(using: .png, properties: [:]))
            .write(to: directory.appendingPathComponent("sidebar-after-language-change.png"))

        var changedPixels = 0
        for y in 0..<english.pixelsHigh {
            for x in 0..<english.pixelsWide {
                guard let first = chinese.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                      let second = english.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                if abs(first.redComponent - second.redComponent)
                    + abs(first.greenComponent - second.greenComponent)
                    + abs(first.blueComponent - second.blueComponent) > 0.15 {
                    changedPixels += 1
                }
            }
        }
        XCTAssertGreaterThan(changedPixels, 100, "Sidebar labels should update without changing the selected section")
    }

    func testLocalizedMenuRenders() throws {
        let previousLanguage = UserDefaults.standard.string(forKey: AppLanguage.preferenceKey)
        defer {
            if let previousLanguage {
                UserDefaults.standard.set(previousLanguage, forKey: AppLanguage.preferenceKey)
            } else {
                UserDefaults.standard.removeObject(forKey: AppLanguage.preferenceKey)
            }
            LocalizationRefresh.shared.refresh()
        }

        let suiteName = "MenuBarLocalizationVisualTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settingsStore = SettingsStore(userDefaults: defaults)
        let scheduler = BreakScheduler(
            settingsStore: settingsStore,
            notificationService: VisualTestNotificationService(),
            idleMonitor: VisualTestIdleMonitor(),
            pauseResumeSessionStore: PauseResumeSessionStore(userDefaults: defaults)
        )
        let updateMonitor = UpdateMonitor(userDefaults: defaults, installedVersion: "0.3.0")
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("BreatherVisualAudit", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        for language in [AppLanguage.simplifiedChinese, .traditionalChinese, .english] {
            UserDefaults.standard.set(language.rawValue, forKey: AppLanguage.preferenceKey)
            LocalizationRefresh.shared.refresh()
            let bitmap = try render(scheduler: scheduler, updateMonitor: updateMonitor)
            let image = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            try image.write(to: directory.appendingPathComponent("menu-\(language.rawValue).png"), options: .atomic)
        }
    }

    func testNextStepDurationUsesExactReadableUnits() {
        XCTAssertEqual(MenuBarView.formattedNextStepDuration(30), "30 秒")
        XCTAssertEqual(MenuBarView.formattedNextStepDuration(120), "2 分钟")
        XCTAssertEqual(MenuBarView.formattedNextStepDuration(128), "2 分 8 秒")
    }

    func testWorkingNextStepUsesTheCurrentCycleBreakInsteadOfPendingRules() {
        var currentCycleRules = BreakRules()
        currentCycleRules.shortBreakDuration = 30
        var savedRules = currentCycleRules
        savedRules.shortBreakDuration = 58

        XCTAssertEqual(
            MenuBarView.nextStepDetail(
                for: .working,
                currentCycleRules: currentCycleRules,
                savedRules: savedRules
            ),
            "休息 30 秒"
        )
    }

    func testDarkMenuStatesRenderDistinctActionsAndMirrorExplanation() throws {
        let suiteName = "MenuBarPauseVisualRegressionTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settingsStore = SettingsStore(userDefaults: defaults)
        settingsStore.settings.menuBarPopoverAppearance = .dark
        settingsStore.settings.menuBarPopoverThemeColor = .jadeCore
        settingsStore.settings.menuBarPopoverProgressStyle = .radix
        settingsStore.settings.autoPauseDuringDisplayMirroring = true
        settingsStore.rules.workDuration = 20 * 60

        let scheduler = BreakScheduler(
            settingsStore: settingsStore,
            notificationService: VisualTestNotificationService(),
            idleMonitor: VisualTestIdleMonitor(),
            pauseResumeSessionStore: PauseResumeSessionStore(userDefaults: defaults)
        )
        let updateMonitor = UpdateMonitor(userDefaults: defaults, installedVersion: "0.3.0")

        let normal = try render(scheduler: scheduler, updateMonitor: updateMonitor)

        scheduler.togglePause()
        let userPaused = try render(scheduler: scheduler, updateMonitor: updateMonitor)
        settingsStore.settings.menuBarPopoverAppearance = .light
        let lightUserPaused = try render(scheduler: scheduler, updateMonitor: updateMonitor)

        settingsStore.settings.menuBarPopoverAppearance = .dark
        scheduler.continueUserPause()
        scheduler.setDisplayMirroringActive(true)
        let mirroring = try render(scheduler: scheduler, updateMonitor: updateMonitor)
        settingsStore.settings.menuBarPopoverAppearance = .light
        let lightMirroring = try render(scheduler: scheduler, updateMonitor: updateMonitor)

        let fullFrame = NSRect(x: 0, y: 0, width: 320, height: 420)
        let actionsFrame = NSRect(x: 20, y: 346, width: 280, height: 66)

        XCTAssertGreaterThan(pixelDifference(normal, userPaused, in: fullFrame), 0.04)
        XCTAssertGreaterThan(pixelDifference(normal, userPaused, in: actionsFrame), 0.10)
        XCTAssertGreaterThan(pixelDifference(userPaused, mirroring, in: fullFrame), 0.04)
        XCTAssertGreaterThan(pixelDifference(userPaused, mirroring, in: actionsFrame), 0.10)

        let normalProgressBottom = strongestHorizontalEdgeY(in: normal, pointRange: 230..<248)
        let normalActionsTop = strongestHorizontalEdgeY(in: normal, pointRange: 340..<360)
        XCTAssertEqual(normalActionsTop - normalProgressBottom, 106, accuracy: 1)

        assertPauseCardIsCentered(
            in: userPaused,
            expectedGap: 25,
            cardTopRange: 260..<280,
            cardBottomRange: 315..<330,
            lowerContentTopRange: 340..<360
        )
        assertPauseCardIsCentered(
            in: mirroring,
            expectedGap: 14,
            cardTopRange: 250..<270,
            cardBottomRange: 315..<332,
            lowerContentTopRange: 332..<345
        )

        try writeVisualAuditImages(
            normal: normal,
            userPaused: userPaused,
            lightUserPaused: lightUserPaused,
            mirroring: mirroring,
            lightMirroring: lightMirroring
        )
    }

    func testSettingsScreensRenderAtNarrowAndWideWidths() async throws {
        let previousLanguage = UserDefaults.standard.string(forKey: AppLanguage.preferenceKey)
        defer {
            if let previousLanguage {
                UserDefaults.standard.set(previousLanguage, forKey: AppLanguage.preferenceKey)
            } else {
                UserDefaults.standard.removeObject(forKey: AppLanguage.preferenceKey)
            }
            LocalizationRefresh.shared.refresh()
        }

        let suiteName = "SettingsResizeVisualTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settingsStore = SettingsStore(userDefaults: defaults)
        let updateMonitor = UpdateMonitor(
            userDefaults: defaults,
            installedVersion: "0.3.0",
            checkRelease: { _ in
                UpdateCheckResponse(.available(AvailableUpdate(
                    version: "0.4.0",
                    releaseURL: URL(string: "https://github.com/M3tar/Breather/releases/tag/v0.4.0")!
                )))
            }
        )
        await updateMonitor.checkNow()
        let notificationService = VisualTestSettingsNotificationService()
        let soundService = RestSoundService()
        let screens: [(name: String, view: AnyView)] = [
            (
                "general",
                AnyView(
                    GeneralSettingsScreen(
                        settingsStore: settingsStore,
                        notificationService: notificationService,
                        restSoundService: soundService
                    )
                )
            ),
            (
                "schedule",
                AnyView(
                    ScheduleSettingsScreen(
                        settingsStore: settingsStore,
                        isWaitingToApplyRules: false,
                        onApplyRulesToCurrentCycle: {},
                        notificationService: notificationService,
                        onOpenNotificationSettings: {}
                    )
                )
            ),
            (
                "menu-bar",
                AnyView(MenuBarSettingsScreen(settingsStore: settingsStore))
            ),
            (
                "rest",
                AnyView(
                    RestOverlaySettingsScreen(
                        settingsStore: settingsStore,
                        restSoundService: soundService,
                        onPreviewRestOverlay: {}
                    )
                )
            ),
            (
                "about-update",
                AnyView(AboutSettingsScreen(updateMonitor: updateMonitor))
            )
        ]

        let settingsView = AnyView(
            SettingsView(
                settingsStore: settingsStore,
                updateMonitor: updateMonitor,
                notificationService: notificationService,
                restSoundService: soundService,
                onApplyRulesToCurrentCycle: {},
                onPreviewRestOverlay: {}
            )
        )
        for language in [AppLanguage.simplifiedChinese, .traditionalChinese, .english] {
            UserDefaults.standard.set(language.rawValue, forKey: AppLanguage.preferenceKey)
            LocalizationRefresh.shared.refresh()

            for screen in screens {
                try assertSettingsScreenRenders(
                    screen.view,
                    name: "\(language.rawValue)-\(screen.name)",
                    width: 592,
                    height: 560
                )
                try assertSettingsScreenRenders(
                    screen.view,
                    name: "\(language.rawValue)-\(screen.name)",
                    width: 790,
                    height: 640
                )
            }

            try assertSettingsScreenRenders(
                settingsView,
                name: "\(language.rawValue)-window",
                width: 760,
                height: 560
            )
            try assertSettingsScreenRenders(
                settingsView,
                name: "\(language.rawValue)-window",
                width: 960,
                height: 680
            )
        }
    }

    func testAvailableUpdateShowsHeaderIcon() async throws {
        let suiteName = "MenuBarUpdateVisualTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settingsStore = SettingsStore(userDefaults: defaults)
        let scheduler = BreakScheduler(
            settingsStore: settingsStore,
            notificationService: VisualTestNotificationService(),
            idleMonitor: VisualTestIdleMonitor(),
            pauseResumeSessionStore: PauseResumeSessionStore(userDefaults: defaults)
        )
        let updateMonitor = UpdateMonitor(
            userDefaults: defaults,
            installedVersion: "0.3.0",
            checkRelease: { _ in
                UpdateCheckResponse(.available(AvailableUpdate(
                    version: "0.4.0",
                    releaseURL: URL(string: "https://github.com/M3tar/Breather/releases/tag/v0.4.0")!
                )))
            }
        )

        let withoutUpdate = try render(scheduler: scheduler, updateMonitor: updateMonitor)
        await updateMonitor.checkNow()
        let withUpdate = try render(scheduler: scheduler, updateMonitor: updateMonitor)

        XCTAssertGreaterThan(
            pixelDifference(
                withoutUpdate,
                withUpdate,
                in: NSRect(x: 222, y: 20, width: 64, height: 43)
            ),
            0.01
        )

        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("BreatherVisualAudit", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let image = try XCTUnwrap(withUpdate.representation(using: .png, properties: [:]))
        try image.write(to: directory.appendingPathComponent("menu-update-icon.png"), options: .atomic)

        settingsStore.settings.menuBarPopoverAppearance = .dark
        let darkUpdate = try render(scheduler: scheduler, updateMonitor: updateMonitor)
        let darkImage = try XCTUnwrap(darkUpdate.representation(using: .png, properties: [:]))
        try darkImage.write(to: directory.appendingPathComponent("menu-update-icon-dark.png"), options: .atomic)
    }

    private func assertSettingsScreenRenders(
        _ view: AnyView,
        name: String,
        width: CGFloat,
        height: CGFloat
    ) throws {
        let hostingView = NSHostingView(
            rootView: AnyView(
                view
                    .frame(width: width, height: height, alignment: .topLeading)
                    .background(Color(nsColor: .windowBackgroundColor))
            )
        )
        hostingView.frame = NSRect(x: 0, y: 0, width: width, height: height)
        hostingView.layoutSubtreeIfNeeded()

        let bitmap = try XCTUnwrap(hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds))
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
        let horizontalScale = Double(bitmap.pixelsWide) / width
        let verticalScale = Double(bitmap.pixelsHigh) / height
        XCTAssertGreaterThanOrEqual(horizontalScale, 1)
        XCTAssertEqual(horizontalScale, verticalScale, accuracy: 0.01)

        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("BreatherVisualAudit", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        let sizeSuffix = "\(Int(width))x\(Int(height))"
        try data.write(
            to: directory.appendingPathComponent("settings-\(name)-\(sizeSuffix).png"),
            options: .atomic
        )
    }

    private func render(
        scheduler: BreakScheduler,
        updateMonitor: UpdateMonitor
    ) throws -> NSBitmapImageRep {
        let hostingView = NSHostingView(
            rootView: MenuBarView(
                scheduler: scheduler,
                updateMonitor: updateMonitor,
                onOpenSettings: {},
                onOpenUpdate: { _ in },
                onQuit: {}
            )
        )
        hostingView.frame = NSRect(x: 0, y: 0, width: 320, height: 420)
        hostingView.layoutSubtreeIfNeeded()

        let bitmap = try XCTUnwrap(hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds))
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
        return bitmap
    }

    private func pixelDifference(
        _ lhs: NSBitmapImageRep,
        _ rhs: NSBitmapImageRep,
        in frame: NSRect
    ) -> Double {
        let scaleX = Double(lhs.pixelsWide) / 320.0
        let scaleY = Double(lhs.pixelsHigh) / 420.0
        let minX = max(0, Int(frame.minX * scaleX))
        let maxX = min(lhs.pixelsWide, Int(frame.maxX * scaleX))
        let minY = max(0, Int(frame.minY * scaleY))
        let maxY = min(lhs.pixelsHigh, Int(frame.maxY * scaleY))
        var changedPixels = 0
        var totalPixels = 0

        for y in minY..<maxY {
            for x in minX..<maxX {
                guard let left = lhs.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                      let right = rhs.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else {
                    continue
                }

                totalPixels += 1
                let difference = abs(left.redComponent - right.redComponent)
                    + abs(left.greenComponent - right.greenComponent)
                    + abs(left.blueComponent - right.blueComponent)
                    + abs(left.alphaComponent - right.alphaComponent)
                if difference > 0.08 {
                    changedPixels += 1
                }
            }
        }

        guard totalPixels > 0 else { return 0 }
        return Double(changedPixels) / Double(totalPixels)
    }

    private func assertPauseCardIsCentered(
        in bitmap: NSBitmapImageRep,
        expectedGap: Double,
        cardTopRange: Range<Double>,
        cardBottomRange: Range<Double>,
        lowerContentTopRange: Range<Double>,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let progressBottom = strongestHorizontalEdgeY(in: bitmap, pointRange: 230..<248)
        let cardTop = strongestHorizontalEdgeY(in: bitmap, pointRange: cardTopRange)
        let cardBottom = strongestHorizontalEdgeY(in: bitmap, pointRange: cardBottomRange)
        let lowerContentTop = strongestHorizontalEdgeY(in: bitmap, pointRange: lowerContentTopRange)
        let upperGap = cardTop - progressBottom
        let lowerGap = lowerContentTop - cardBottom

        XCTAssertEqual(upperGap, expectedGap, accuracy: 1, file: file, line: line)
        XCTAssertEqual(lowerGap, expectedGap, accuracy: 1, file: file, line: line)
    }

    private func strongestHorizontalEdgeY(
        in bitmap: NSBitmapImageRep,
        pointRange: Range<Double>
    ) -> Double {
        let scaleX = Double(bitmap.pixelsWide) / 320.0
        let scaleY = Double(bitmap.pixelsHigh) / 420.0
        let minX = max(0, Int(48 * scaleX))
        let maxX = min(bitmap.pixelsWide, Int(294 * scaleX))
        let minY = max(1, Int(pointRange.lowerBound * scaleY))
        let maxY = min(bitmap.pixelsHigh, Int(pointRange.upperBound * scaleY))
        var strongestRow = minY
        var strongestScore = -Double.infinity

        for y in minY..<maxY {
            var score = 0.0
            for x in minX..<maxX {
                guard let previous = bitmap.colorAt(x: x, y: y - 1)?.usingColorSpace(.deviceRGB),
                      let current = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else {
                    continue
                }
                score += abs(previous.redComponent - current.redComponent)
                    + abs(previous.greenComponent - current.greenComponent)
                    + abs(previous.blueComponent - current.blueComponent)
            }
            if score > strongestScore {
                strongestScore = score
                strongestRow = y
            }
        }

        return Double(strongestRow) / scaleY
    }

    private func writeVisualAuditImages(
        normal: NSBitmapImageRep,
        userPaused: NSBitmapImageRep,
        lightUserPaused: NSBitmapImageRep,
        mirroring: NSBitmapImageRep,
        lightMirroring: NSBitmapImageRep
    ) throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("BreatherVisualAudit", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        for (name, bitmap) in [
            ("dark-normal.png", normal),
            ("dark-user-paused.png", userPaused),
            ("light-user-paused.png", lightUserPaused),
            ("dark-mirroring.png", mirroring),
            ("light-mirroring.png", lightMirroring)
        ] {
            let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            try data.write(to: directory.appendingPathComponent(name), options: .atomic)
        }
    }
}

@MainActor
private final class VisualTestNotificationService: BreakNotificationSending {
    func sendPreBreakNotification(playSound: Bool, soundEffect: RestSoundEffect) {}
}

@MainActor
private final class VisualTestSettingsNotificationService: NotificationSettingsServicing {
    private(set) var authorizationCheckCount = 0

    func authorizationStatus() async -> NotificationPermissionStatus {
        authorizationCheckCount += 1
        return .authorized
    }

    func requestAuthorization() async -> NotificationPermissionStatus {
        .authorized
    }

    func sendPreviewNotification(
        playSound: Bool,
        soundEffect: RestSoundEffect
    ) async -> NotificationPreviewResult {
        .delivered
    }
}

private final class VisualTestIdleMonitor: IdleTimeProviding {
    var idleSeconds: TimeInterval = 0
}

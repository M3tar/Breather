import AppKit
import SwiftUI
import Vision
import XCTest
@testable import Breather

@MainActor
final class SettingsLayoutTests: XCTestCase {
    func testUpdateFeedbackDoesNotReplayAfterPageSwitch() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["BREATHER_WINDOW_TEST"] == "1")
        let previous = UserDefaults.standard.string(forKey: AppLanguage.preferenceKey)
        defer { restoreLanguage(previous) }
        let suite = "UpdateFeedbackLayout.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let monitor = UpdateMonitor(userDefaults: defaults, installedVersion: "0.5.0",
                                    checkRelease: { _ in UpdateCheckResponse(.upToDate) })
        // Establish a future automatic-check deadline before presenting the page.
        await monitor.checkNow()
        let host = NSHostingView(rootView: AnyView(EmptyView()))
        host.frame = NSRect(x: 0, y: 0, width: 650, height: 650)
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.orderOut(nil); window.contentView = nil; window.close() }

        UserDefaults.standard.set(AppLanguage.english.rawValue, forKey: AppLanguage.preferenceKey)
        LocalizationRefresh.shared.refresh()
        func presentAbout() async throws {
            host.rootView = AnyView(AboutSettingsScreen(updateMonitor: monitor))
            try await Task.sleep(for: .milliseconds(150))
            host.layoutSubtreeIfNeeded()
        }
        func containsResult() throws -> Bool {
            let text = try recognizedText(in: host).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
            return text.localizedCaseInsensitiveContains("up to date")
        }
        try await presentAbout()
        XCTAssertFalse(try containsResult())
        await monitor.checkNow()
        try await Task.sleep(for: .milliseconds(450))
        host.layoutSubtreeIfNeeded()
        XCTAssertTrue(try containsResult())
        host.rootView = AnyView(Text("Another page"))
        try await Task.sleep(for: .milliseconds(450))
        try await presentAbout()
        XCTAssertFalse(try containsResult(), "Returning must not replay the monitor's cached result")
    }

    func testClosingRetainedWindowClearsFeedbackAndResetsHover() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["BREATHER_WINDOW_TEST"] == "1")
        _ = NSApplication.shared
        let feedback = SettingsToastPresenter(successDuration: .milliseconds(30))
        let host = NSHostingView(rootView: SettingsFeedbackWindowObserver(
            onLeave: feedback.disappear, onReturn: feedback.appear))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.contentView = nil; window.close() }
        try await Task.sleep(for: .milliseconds(100))
        feedback.appear()
        feedback.show(SettingsToastMessage(text: "first"))
        feedback.setHovered(true)
        window.close()
        XCTAssertNil(feedback.message, "A retained hosting view must not keep the closed window's toast")
        window.orderFront(nil)
        // The test runner may be inactive; invoke AppKit's key-window lifecycle
        // directly rather than taking focus from the user's foreground app.
        window.becomeKey()
        try await Task.sleep(for: .milliseconds(100))
        feedback.show(SettingsToastMessage(text: "new visit"))
        XCTAssertEqual(feedback.message?.text, "new visit")
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertNil(feedback.message, "Closing also resets the previous hover pause")
    }

    func testAboutActionToastScreenshotsAcrossLanguages() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["BREATHER_WINDOW_TEST"] == "1")
        let previous = UserDefaults.standard.string(forKey: AppLanguage.preferenceKey)
        defer { restoreLanguage(previous) }
        let app = NSApplication.shared
        let previousIcon = app.applicationIconImage
        let sourceRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        app.applicationIconImage = NSImage(contentsOf: sourceRoot.appendingPathComponent("Sources/Breather/Resources/Assets.xcassets/AppIcon.appiconset/icon_128x128@2x.png"))
        defer { app.applicationIconImage = previousIcon }
        let suite = "AboutToastScreenshots.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let screenshots = ProcessInfo.processInfo.environment["BREATHER_SCREENSHOT_DIR"].map { URL(fileURLWithPath: $0) } ?? root
        try FileManager.default.createDirectory(at: screenshots, withIntermediateDirectories: true)
        let controller = DiagnosticsController(directory: root.appendingPathComponent("logs"), userDefaults: defaults)
        defer { controller.stop() }
        let monitor = UpdateMonitor(userDefaults: defaults, installedVersion: "0.5.0",
                                    checkRelease: { _ in UpdateCheckResponse(.upToDate) })
        await monitor.checkNow()
        let host = NSHostingView(rootView: AnyView(EmptyView()))
        host.frame = NSRect(x: 0, y: 0, width: 840, height: 700)
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        // SwiftUI's layer-backed content must be on screen for complete bitmap captures.
        window.orderFront(nil)
        defer { window.orderOut(nil); window.contentView = nil; window.close() }

        func settle() async throws {
            try await Task.sleep(for: .milliseconds(450))
            host.layoutSubtreeIfNeeded()
        }
        func capture(_ name: String) throws {
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                .write(to: screenshots.appendingPathComponent(name + ".png"))
        }
        for language in [AppLanguage.simplifiedChinese, .traditionalChinese, .english] {
            await monitor.checkNow() // Clear the preceding language's simulated available-release cache.
            UserDefaults.standard.set(language.rawValue, forKey: AppLanguage.preferenceKey)
            LocalizationRefresh.shared.refresh()
            host.rootView = AnyView(AboutSettingsScreen(updateMonitor: monitor, diagnostics: controller)
                .background(Color(nsColor: .windowBackgroundColor)).preferredColorScheme(.light))
            try await settle()
            let originalBounds = try recognizedText(in: host).first { $0.topCandidates(1).first?.string.localizedCaseInsensitiveCompare("Check for updates") == .orderedSame }?.boundingBox
            try capture("about-\(language.rawValue)-idle")
            await controller.clearLogs()
            try await settle()
            XCTAssertEqual(controller.message?.text, L.tr("日志已清除"))
            try capture("about-\(language.rawValue)-cleared")
            await controller.export(to: root.appendingPathComponent("report.zip"))
            try await settle()
            XCTAssertEqual(controller.message?.text, L.tr("日志已导出"))
            XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("report.zip").path))
            try capture("about-\(language.rawValue)-exported")
            await controller.export(to: root.appendingPathComponent("missing/report.zip"))
            try await settle()
            XCTAssertEqual(controller.message?.isError, true)
            try capture("about-\(language.rawValue)-failed")
            if language == .english {
                let text = try recognizedText(in: host).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
                XCTAssertTrue(text.contains("export"), text)
                XCTAssertTrue(text.localizedCaseInsensitiveContains("try again"), text)
            }
            if language == .english {
                let updatedBounds = try recognizedText(in: host).first { $0.topCandidates(1).first?.string.localizedCaseInsensitiveCompare("Check for updates") == .orderedSame }?.boundingBox
                XCTAssertNotNil(originalBounds)
                XCTAssertEqual(updatedBounds, originalBounds, "Toasts must not move the update controls")
            }
            host.rootView = AnyView(EmptyView())
            try await settle()
            XCTAssertNil(controller.message)

            let failedMonitor = UpdateMonitor(userDefaults: defaults, installedVersion: "0.5.0",
                checkRelease: { _ in throw URLError(.notConnectedToInternet) })
            await failedMonitor.checkNow()
            for (width, scheme, suffix) in [(840.0, ColorScheme.light, "update-failed"),
                                            (550.0, .light, "update-failed-narrow"),
                                            (1040.0, .light, "update-failed-wide"),
                                            (840.0, .dark, "update-failed-dark")] {
                window.setContentSize(NSSize(width: width, height: 700))
                host.frame = NSRect(x: 0, y: 0, width: width, height: 700)
                host.rootView = AnyView(AboutSettingsScreen(updateMonitor: failedMonitor, diagnostics: controller)
                    .background(Color(nsColor: .windowBackgroundColor)).preferredColorScheme(scheme))
                try await settle()
                await failedMonitor.checkNow()
                try await settle()
                try capture("about-\(language.rawValue)-\(suffix)")
                if language == .english {
                    let results = try recognizedText(in: host)
                    let feedbackLines = results.filter { observation in
                        let text = observation.topCandidates(1).first?.string.lowercased() ?? ""
                        return text.contains("failed") || text.contains("connection") || text.contains("try again")
                    }
                    XCTAssertFalse(feedbackLines.isEmpty)
                    for line in feedbackLines {
                        XCTAssertGreaterThan(line.boundingBox.minX * width, min(width, SettingsWindowMetrics.contentMaxWidth) / 2 + 40,
                                             "Feedback must stay to the right of the centered app icon")
                    }
                }
                if width > SettingsWindowMetrics.contentMaxWidth {
                    await controller.clearLogs()
                    try await settle()
                    try capture("about-\(language.rawValue)-cleared-wide")
                    await controller.export(to: root.appendingPathComponent("report.zip"))
                    try await settle()
                    try capture("about-\(language.rawValue)-exported-wide")
                }
                host.rootView = AnyView(EmptyView())
                try await settle()
            }
            window.setContentSize(NSSize(width: 840, height: 700))
            host.frame = NSRect(x: 0, y: 0, width: 840, height: 700)

            let availableMonitor = UpdateMonitor(userDefaults: defaults, installedVersion: "0.5.0",
                checkRelease: { _ in UpdateCheckResponse(.available(AvailableUpdate(
                    version: "0.6.0", releaseURL: URL(string: "https://github.com/M3tar/Breather/releases/tag/v0.6.0")!
                ))) })
            await availableMonitor.checkNow()
            host.rootView = AnyView(AboutSettingsScreen(updateMonitor: availableMonitor, diagnostics: controller)
                .background(Color(nsColor: .windowBackgroundColor)).preferredColorScheme(.light))
            try await settle()
            try capture("about-\(language.rawValue)-available")
            XCTAssertEqual(availableMonitor.availableUpdate?.version, "0.6.0")
            if language == .english {
                try await Task.sleep(for: .milliseconds(3200))
                host.layoutSubtreeIfNeeded()
                let text = try recognizedText(in: host).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
                XCTAssertTrue(text.contains("0.6.0"), "A known release must remain after the toast timeout: \(text)")
                XCTAssertTrue(text.localizedCaseInsensitiveContains("download"), text)
                host.rootView = AnyView(EmptyView())
                try await settle()
                host.rootView = AnyView(AboutSettingsScreen(updateMonitor: availableMonitor, diagnostics: controller))
                try await settle()
                let returnedText = try recognizedText(in: host).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
                XCTAssertTrue(returnedText.contains("0.6.0"))
                XCTAssertTrue(returnedText.localizedCaseInsensitiveContains("download"))
            }
            host.rootView = AnyView(EmptyView())
            try await settle()
        }
    }

    func testRuntimeLogHelpOpensOnHoverAndClosesOnExitOrRemoval() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["BREATHER_WINDOW_TEST"] == "1")
        _ = NSApplication.shared
        let host = NSHostingView(rootView: SettingsHelp(message: "Stored only on this Mac, using up to 20 MB.")
            .frame(width: 18, height: 18).padding(30))
        host.frame = NSRect(x: 0, y: 0, width: 200, height: 100)
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFront(nil)
        defer { window.orderOut(nil); window.contentView = nil; window.close() }
        try await Task.sleep(for: .milliseconds(100))
        host.layoutSubtreeIfNeeded()
        let button = try XCTUnwrap(descendants(RuntimeLogHelpButton.self, in: host).first)
        XCTAssertNotNil(button.image, "questionmark.circle must be available in SF Symbols")
        button.updateTrackingAreas()
        XCTAssertTrue(button.trackingAreas.contains { $0.options.contains(.mouseEnteredAndExited) })
        let entered = try XCTUnwrap(NSEvent.enterExitEvent(with: .mouseEntered, location: .zero,
            modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil,
            eventNumber: 0, trackingNumber: 0, userData: nil))
        button.mouseEntered(with: entered)
        XCTAssertTrue(button.helpPanel?.isVisible == true, "Entering the help icon must open the actual help panel")
        let panel = try XCTUnwrap(button.helpPanel)
        let englishWidth = panel.frame.width
        XCTAssertLessThanOrEqual(englishWidth, 320)
        XCTAssertFalse(panel.canBecomeKey)
        XCTAssertFalse(panel.canBecomeMain)
        XCTAssertTrue(panel.ignoresMouseEvents)
        button.mouseExited(with: entered)
        XCTAssertFalse(button.helpPanel?.isVisible == true)
        button.performClick(nil)
        XCTAssertTrue(button.helpPanel?.isVisible == true)
        button.updateMessage("僅保存在本機，最多佔用 20 MB。")
        XCTAssertFalse(button.helpPanel?.isVisible == true)
        XCTAssertEqual(button.accessibilityLabel(), "僅保存在本機，最多佔用 20 MB。")
        button.mouseEntered(with: entered)
        XCTAssertTrue(button.helpPanel?.isVisible == true)
        let chinesePanel = try XCTUnwrap(button.helpPanel)
        XCTAssertLessThan(chinesePanel.frame.width, englishWidth, "Shorter help should have a narrower panel")
        XCTAssertLessThan(chinesePanel.frame.height, 45)
        if let output = ProcessInfo.processInfo.environment["BREATHER_SCREENSHOT_DIR"] {
            let directory = URL(fileURLWithPath: output)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", NSAppearance.Name.darkAqua)] {
                button.appearance = NSAppearance(named: appearance)
                button.closeHelp()
                button.updateMessage("仅保存在本机，最多占用 20 MB。")
                button.showHelp()
                try await Task.sleep(for: .milliseconds(100))
                let view = try XCTUnwrap(button.helpPanel?.contentView)
                view.layoutSubtreeIfNeeded()
                let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
                view.cacheDisplay(in: view.bounds, to: bitmap)
                try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                    .write(to: directory.appendingPathComponent("runtime-log-help-\(name).png"))
            }
        }
        window.close()
        XCTAssertNil(button.helpPanel, "Closing a retained window must release its help panel")
        window.makeKeyAndOrderFront(nil)
        button.showHelp()
        XCTAssertTrue(button.helpPanel?.isVisible == true)
        host.isHidden = true
        XCTAssertNil(button.helpPanel, "Hiding an ancestor must close its help panel")
        host.isHidden = false
        button.showHelp()
        window.contentView = nil
        XCTAssertNil(button.helpPanel, "Leaving the page must close the help panel")
    }

    func testRuntimeLogControlsAcrossLanguagesAndRecordingStates() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["BREATHER_WINDOW_TEST"] == "1")
        let previous = UserDefaults.standard.string(forKey: AppLanguage.preferenceKey)
        defer { restoreLanguage(previous) }
        let suite = "RuntimeLogLayout.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        defer { try? FileManager.default.removeItem(at: directory) }
        let controller = DiagnosticsController(directory: directory, userDefaults: defaults)
        defer { controller.stop() }
        let screenshots = FileManager.default.temporaryDirectory.appendingPathComponent("BreatherRuntimeLogsAudit")
        try FileManager.default.createDirectory(at: screenshots, withIntermediateDirectories: true)

        for language in [AppLanguage.simplifiedChinese, .traditionalChinese, .english] {
            UserDefaults.standard.set(language.rawValue, forKey: AppLanguage.preferenceKey)
            LocalizationRefresh.shared.refresh()
            for width in [350.0, 550.0] {
                let host = NSHostingView(rootView:
                    SettingsGroup(L.tr("反馈")) {
                        DiagnosticsSettingsGroup(controller: controller)
                    }
                    .padding(20).frame(width: width, height: 230, alignment: .top)
                    .background(Color(nsColor: .windowBackgroundColor)).preferredColorScheme(.light)
                )
                host.frame = NSRect(x: 0, y: 0, width: width, height: 230)
                let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                window.contentView = host
                defer {
                    window.orderOut(nil)
                    window.contentView = nil
                    window.close()
                }
                try await Task.sleep(for: .milliseconds(150))
                host.layoutSubtreeIfNeeded()
                let recordingSwitch = try XCTUnwrap(descendants(NSSwitch.self, in: host).first)
                XCTAssertTrue(descendants(NSSegmentedControl.self, in: host).isEmpty)
                for enabled in [false, true] {
                    recordingSwitch.state = enabled ? .on : .off
                    XCTAssertTrue(recordingSwitch.sendAction(recordingSwitch.action, to: recordingSwitch.target))
                    try await Task.sleep(for: .milliseconds(80))
                    host.layoutSubtreeIfNeeded()
                    XCTAssertEqual(controller.isEnabled, enabled)
                    XCTAssertEqual(recordingSwitch.state, enabled ? .on : .off)
                    XCTAssertTrue(host.bounds.contains(host.convert(recordingSwitch.bounds, from: recordingSwitch)))
                    if language == .english {
                        let text = try recognizedText(in: host).compactMap { $0.topCandidates(1).first?.string }
                            .joined(separator: " ")
                        XCTAssertTrue(text.contains("Export"), "Existing logs must remain exportable when recording is off")
                        XCTAssertTrue(text.contains("Clear"))
                        XCTAssertFalse(text.contains("20 MB"), "The privacy note belongs in help, not visible UI")
                        XCTAssertFalse(text.contains("Record logs"))
                        XCTAssertFalse(text.contains("Log files"))
                        if width == 550 {
                            let lines = try recognizedText(in: host).compactMap { $0.topCandidates(1).first?.string }
                            XCTAssertTrue(lines.contains { $0.contains("Runtime logs") })
                        }
                    }
                }
                let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: bitmap)
                try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                    .write(to: screenshots.appendingPathComponent("logs-\(language.rawValue)-\(Int(width)).png"))
            }
        }
        controller.setEnabled(false)
        await controller.store.flush()
    }

    func testNotificationSettingsStatesKeepSystemEntryAcrossLanguages() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["BREATHER_WINDOW_TEST"] == "1")
        let previous = UserDefaults.standard.string(forKey: AppLanguage.preferenceKey)
        defer { restoreLanguage(previous) }
        let suite = "NotificationSettingsStates.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let service = LayoutTestNotificationService()
        let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("BreatherPreBreakAudit")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        for language in [AppLanguage.simplifiedChinese, .traditionalChinese, .english] {
            UserDefaults.standard.set(language.rawValue, forKey: AppLanguage.preferenceKey)
            LocalizationRefresh.shared.refresh()
            for width in [550.0, 800.0] {
                service.status = .denied
                let host = NSHostingView(rootView: GeneralSettingsScreen(
                    settingsStore: SettingsStore(userDefaults: defaults),
                    notificationService: service, restSoundService: RestSoundService()
                ).frame(width: width, height: 600).preferredColorScheme(.light))
                host.frame = NSRect(x: 0, y: 0, width: width, height: 600)
                let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                window.contentView = host
                defer {
                    window.orderOut(nil)
                    window.contentView = nil
                    window.close()
                }
                for status in [NotificationPermissionStatus.denied, .notDetermined, .alertsDisabled] {
                    service.status = status
                    NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: nil)
                    try await Task.sleep(for: .milliseconds(180))
                    host.layoutSubtreeIfNeeded()
                    if language == .english {
                        let text = try recognizedText(in: host).compactMap {
                            $0.topCandidates(1).first?.string
                        }.joined(separator: " ")
                        XCTAssertTrue(text.contains(L.tr("打开系统设置…").replacingOccurrences(of: "…", with: "")))
                        XCTAssertTrue(text.contains(L.tr("重新检测")))
                        XCTAssertTrue(text.contains(status.title))
                        XCTAssertFalse(text.contains("Request permission"))
                    }
                    let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                    host.cacheDisplay(in: host.bounds, to: bitmap)
                    try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                        .write(to: directory.appendingPathComponent("general-\(status)-\(language.rawValue)-\(Int(width)).png"))
                }
            }
        }
    }

    func testFocusedNotificationSettingsShowsSoundAndPermissionsInShortViewport() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["BREATHER_WINDOW_TEST"] == "1")
        let previous = UserDefaults.standard.string(forKey: AppLanguage.preferenceKey)
        defer { restoreLanguage(previous) }
        UserDefaults.standard.set(AppLanguage.english.rawValue, forKey: AppLanguage.preferenceKey)
        let suite = "NotificationSettingsFocus.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let host = NSHostingView(rootView: GeneralSettingsScreen(
            settingsStore: SettingsStore(userDefaults: defaults),
            notificationService: LayoutTestNotificationService(), restSoundService: RestSoundService(),
            focusNotifications: true
        ).frame(width: 550, height: 300))
        host.frame = NSRect(x: 0, y: 0, width: 550, height: 300)
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer {
            window.orderOut(nil)
            window.contentView = nil
            window.close()
        }
        try await Task.sleep(for: .milliseconds(250))
        host.layoutSubtreeIfNeeded()
        let text = try recognizedText(in: host).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
        XCTAssertTrue(text.contains("Notification sound"), "Opening the notification area should expose the sound setting")
        XCTAssertTrue(text.contains("System notifications"), "The permission setting should be visible in a short viewport")
    }

    func testPreBreakNotificationChoiceHidesDetailsAndPreservesTimeAcrossLanguages() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["BREATHER_WINDOW_TEST"] == "1")
        let previous = UserDefaults.standard.string(forKey: AppLanguage.preferenceKey)
        defer { restoreLanguage(previous) }
        let suite = "PreBreakNotificationLayout.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SettingsStore(userDefaults: defaults)
        let service = LayoutTestNotificationService()
        let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("BreatherPreBreakAudit")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        for language in [AppLanguage.simplifiedChinese, .traditionalChinese, .english] {
            UserDefaults.standard.set(language.rawValue, forKey: AppLanguage.preferenceKey)
            LocalizationRefresh.shared.refresh()
            for width in [550.0, 800.0] {
                store.rules.preBreakNotificationEnabled = true
                store.preBreakNotificationSeconds = 45
                service.status = .denied
                let host = NSHostingView(rootView:
                    ScheduleSettingsScreen(settingsStore: store, isWaitingToApplyRules: false,
                                           onApplyRulesToCurrentCycle: {}, notificationService: service,
                                           onOpenNotificationSettings: {})
                        .frame(width: width, height: 900)
                        .preferredColorScheme(.light)
                )
                host.frame = NSRect(x: 0, y: 0, width: width, height: 900)
                let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                window.contentView = host
                defer {
                    window.orderOut(nil)
                    window.contentView = nil
                    window.close()
                }
                try await Task.sleep(for: .milliseconds(180))
                host.layoutSubtreeIfNeeded()
                let choice = try XCTUnwrap(descendants(NSSegmentedControl.self, in: host).first {
                    $0.label(forSegment: 0) == L.tr("不通知")
                })
                XCTAssertEqual(choice.selectedSegment, 1)
                let time = try XCTUnwrap(descendants(NSStepper.self, in: host).first { $0.integerValue == 45 })
                XCTAssertEqual(host.convert(choice.bounds, from: choice).maxX,
                               host.convert(time.bounds, from: time).maxX, accuracy: 1)
                time.integerValue = 46
                XCTAssertTrue(time.sendAction(time.action, to: time.target))
                XCTAssertEqual(store.preBreakNotificationSeconds, 46)
                host.layoutSubtreeIfNeeded()
                if language == .english {
                    let observations = try recognizedText(in: host)
                    let text = observations.compactMap {
                        $0.topCandidates(1).first?.string
                    }.joined(separator: " ")
                    XCTAssertTrue(text.contains("Notifications not allowed"))
                    XCTAssertFalse(text.contains("Notifications allowed"))
                    let title = try XCTUnwrap(observations.first {
                        $0.topCandidates(1).first?.string.contains("Advance notice") == true
                    })
                    let status = try XCTUnwrap(observations.first {
                        $0.topCandidates(1).first?.string.contains("Notifications not allowed") == true
                    })
                    XCTAssertEqual(title.boundingBox.midY, status.boundingBox.midY, accuracy: 0.015,
                                   "The permission link should stay beside the duration label at supported widths")
                }
                let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: bitmap)
                try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                    .write(to: directory.appendingPathComponent("notification-\(language.rawValue)-\(Int(width)).png"))

                choice.selectedSegment = 0
                XCTAssertTrue(choice.sendAction(choice.action, to: choice.target))
                try await Task.sleep(for: .milliseconds(150))
                host.layoutSubtreeIfNeeded()
                XCTAssertFalse(store.rules.preBreakNotificationEnabled)
                XCTAssertFalse(descendants(NSStepper.self, in: host).contains { $0.integerValue == 46 })
                XCTAssertEqual(store.preBreakNotificationSeconds, 46)
                let checksWhileDisabled = service.authorizationCheckCount
                NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: nil)
                try await Task.sleep(for: .milliseconds(100))
                XCTAssertEqual(service.authorizationCheckCount, checksWhileDisabled)

                choice.selectedSegment = 1
                XCTAssertTrue(choice.sendAction(choice.action, to: choice.target))
                try await Task.sleep(for: .milliseconds(150))
                host.layoutSubtreeIfNeeded()
                XCTAssertTrue(store.rules.preBreakNotificationEnabled)
                XCTAssertTrue(descendants(NSStepper.self, in: host).contains { $0.integerValue == 46 })
                XCTAssertGreaterThan(service.authorizationCheckCount, checksWhileDisabled)
                service.status = .authorized
                NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: nil)
                try await Task.sleep(for: .milliseconds(100))
                if language == .english {
                    let text = try recognizedText(in: host).compactMap {
                        $0.topCandidates(1).first?.string
                    }.joined(separator: " ")
                    XCTAssertFalse(text.contains("Notifications not allowed"))
                    XCTAssertTrue(text.contains("Notifications allowed"))
                }
                let enabledBitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: enabledBitmap)
                try XCTUnwrap(enabledBitmap.representation(using: .png, properties: [:]))
                    .write(to: directory.appendingPathComponent("notification-enabled-\(language.rawValue)-\(Int(width)).png"))

                service.status = .alertsDisabled
                NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: nil)
                try await Task.sleep(for: .milliseconds(100))
                host.layoutSubtreeIfNeeded()
                if language == .english {
                    let text = try recognizedText(in: host).compactMap {
                        $0.topCandidates(1).first?.string
                    }.joined(separator: " ")
                    XCTAssertTrue(text.contains("Desktop alerts off"))
                    XCTAssertFalse(text.contains("Notifications not allowed"),
                                   "Disabling alerts must not be presented as missing permission")
                }
                let alertsBitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: alertsBitmap)
                try XCTUnwrap(alertsBitmap.representation(using: .png, properties: [:]))
                    .write(to: directory.appendingPathComponent("notification-alerts-disabled-\(language.rawValue)-\(Int(width)).png"))
            }
        }
    }

    func testAutomaticRestRuleKeepsControlsAlignedAndShowsRelevantDetails() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["BREATHER_WINDOW_TEST"] == "1")
        let previous = UserDefaults.standard.string(forKey: AppLanguage.preferenceKey)
        defer { restoreLanguage(previous) }
        UserDefaults.standard.set(AppLanguage.english.rawValue, forKey: AppLanguage.preferenceKey)
        let suite = "AutomaticRestRuleLayout.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SettingsStore(userDefaults: defaults)

        for width in [550.0, 800.0] {
            store.settings.automaticRestMode = .lockOrSleep
            store.automaticRestSeconds = 300
            let host = NSHostingView(rootView:
                ScheduleSettingsScreen(settingsStore: store, isWaitingToApplyRules: false,
                                       onApplyRulesToCurrentCycle: {},
                                       notificationService: LayoutTestNotificationService(),
                                       onOpenNotificationSettings: {})
                    .frame(width: width, height: 900)
                    .preferredColorScheme(.light)
            )
            host.frame = NSRect(x: 0, y: 0, width: width, height: 900)
            let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
            defer {
                window.orderOut(nil)
                window.contentView = nil
                window.close()
            }
            settle(host)
            let picker = try XCTUnwrap(descendants(NSPopUpButton.self, in: host).first {
                $0.accessibilityLabel() == "Automatically count as a break"
            })
            let durationStepper = try XCTUnwrap(descendants(NSStepper.self, in: host).first { $0.integerValue == 300 && $0.maxValue == 1800 })
            let pickerBounds = host.convert(picker.bounds, from: picker)
            let durationBounds = host.convert(durationStepper.bounds, from: durationStepper)
            XCTAssertEqual(pickerBounds.maxX, durationBounds.maxX, accuracy: 1,
                           "Indenting the dependent label must preserve right-aligned controls")
            durationStepper.integerValue = 360
            XCTAssertTrue(durationStepper.sendAction(durationStepper.action, to: durationStepper.target))
            XCTAssertEqual(store.automaticRestSeconds, 360)

            for mode in AutomaticRestMode.allCases {
                store.settings.automaticRestMode = mode
                settle(host)
                let help = try XCTUnwrap(descendants(RuntimeLogHelpButton.self, in: host).first)
                let expectedHelp = switch mode {
                case .disabled: L.tr("关闭时，锁屏或睡眠只暂停计时，不会自动完成休息。")
                case .lockOrSleep: L.tr("锁屏或睡眠达到设定时长，视为完成休息；返回后重新开始工作计时。")
                case .lockSleepOrIdle: L.tr("锁屏、睡眠或无操作达到设定时长，视为完成休息；返回后重新开始工作计时。")
                }
                XCTAssertEqual(help.message, expectedHelp, "Help must follow the selected option")
                XCTAssertTrue(descendants(NSPopUpButton.self, in: host).contains { $0 === picker },
                              "Changing the mode must preserve the native picker")
                let fields = descendants(NSTextField.self, in: host).filter(\.isEditable)
                XCTAssertEqual(fields.count, mode.isEnabled ? 6 : 5)
                XCTAssertEqual(fields.contains { $0.stringValue == "360" }, mode.isEnabled)
                let observations = try recognizedText(in: host)
                let text = observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
                XCTAssertEqual(text.contains("At least"), mode.isEnabled)
                XCTAssertEqual(text.contains("Reading or watching videos"), mode.includesIdle, "The inactivity warning must be visible only when enabled")
                XCTAssertTrue(text.contains("screen sharing"), "The essential scope limit must remain visible")
                XCTAssertTrue(text.contains("AirPlay"), "Supported mirroring must be visible without opening help")
                if mode.isEnabled {
                    let parent = try XCTUnwrap(observations.first {
                        $0.topCandidates(1).first?.string.contains("Automatically count as a break") == true
                    })
                    let child = try XCTUnwrap(observations.first {
                        $0.topCandidates(1).first?.string.hasPrefix("At least") == true
                    })
                    XCTAssertGreaterThanOrEqual((child.boundingBox.minX - parent.boundingBox.minX) * width, 16,
                                                "The duration must visibly belong to its parent setting")
                    if mode.includesIdle {
                        let note = try XCTUnwrap(observations.first {
                            $0.topCandidates(1).first?.string.hasPrefix("Reading or watching videos") == true
                        })
                        let bounds = host.convert(picker.bounds, from: picker)
                        let pickerBottom = host.isFlipped ? bounds.maxY : host.bounds.height - bounds.minY
                        let noteTop = (1 - note.boundingBox.maxY) * host.bounds.height
                        let noteBottom = (1 - note.boundingBox.minY) * host.bounds.height
                        let durationTop = (1 - child.boundingBox.maxY) * host.bounds.height
                        XCTAssertGreaterThan(noteTop, pickerBottom, "The option note must follow the selector, even in a narrow window")
                        XCTAssertLessThan(noteBottom, durationTop, "The option note must precede the duration setting")
                    }
                }
                XCTAssertEqual(store.automaticRestSeconds, 360, "Hiding the duration must preserve its value")
            }
        }
    }

    func testSettingsViewAppliesAutomaticRestEditsAndFlushesOnWindowClose() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["BREATHER_WINDOW_TEST"] == "1")
        let suite = "CycleRulesUI.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SettingsStore(userDefaults: defaults)
        store.shortBreakSeconds = 60
        store.automaticRestSeconds = 120
        store.activateSavedRulesForCurrentCycle()
        var applications = 0
        var pendingExpectation: XCTestExpectation?
        func expectApplication(_ description: String, when edit: () -> Void) async {
            let applied = expectation(description: description)
            pendingExpectation = applied
            defer { pendingExpectation = nil }
            edit()
            await fulfillment(of: [applied], timeout: 5)
        }
        let host = NSHostingView(rootView: SettingsView(settingsStore: store,
            updateMonitor: UpdateMonitor(userDefaults: defaults, installedVersion: "0.5.0",
                checkRelease: { _ in UpdateCheckResponse(.upToDate) }),
            notificationService: LayoutTestNotificationService(), restSoundService: RestSoundService(),
            onApplyRulesToCurrentCycle: {
                applications += 1
                store.activateSavedRulesForCurrentCycle()
                pendingExpectation?.fulfill()
            },
            onPreviewRestOverlay: {}))
        host.frame = NSRect(x: 0, y: 0, width: 1080, height: 900)
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.orderOut(nil); window.contentView = nil; window.close() }
        settle(host)
        store.automaticRestSeconds = 90
        try await Task.sleep(for: .milliseconds(1100))
        XCTAssertEqual(applications, 0)
        XCTAssertEqual(store.effectiveAutomaticRestThreshold, 120)
        XCTAssertTrue(store.hasPendingRuleChanges)
        await expectApplication("Switching to immediate applies the pending threshold") {
            store.settings.ruleChangeEffect = .immediate
        }
        XCTAssertEqual(applications, 1)
        XCTAssertEqual(store.effectiveAutomaticRestThreshold, 90)
        await expectApplication("The automatic rest mode and duration apply together") {
            store.settings.automaticRestMode = .lockSleepOrIdle
            store.automaticRestSeconds = 45
        }
        XCTAssertEqual(applications, 2)
        XCTAssertEqual(store.currentAutomaticRestMode, .lockSleepOrIdle)
        XCTAssertEqual(store.effectiveAutomaticRestThreshold, 60)
        await expectApplication("Changing the short break updates the effective threshold") {
            store.shortBreakSeconds = 180
        }
        XCTAssertEqual(applications, 3, "Linked edits must apply together, once")
        XCTAssertEqual(store.currentCycleRules.shortBreakDuration, 180)
        XCTAssertEqual(store.effectiveAutomaticRestThreshold, 180)
        store.settings.showCountdownInMenuBar.toggle()
        try await Task.sleep(for: .milliseconds(1100))
        XCTAssertEqual(applications, 3, "Unrelated preferences must not restart the timer")
        store.automaticRestSeconds = 240
        settle(host)
        window.close()
        XCTAssertEqual(applications, 4)
        XCTAssertEqual(store.effectiveAutomaticRestThreshold, 240)
        try await Task.sleep(for: .milliseconds(1100))
        XCTAssertEqual(applications, 4, "The cancelled delayed apply must not replay")
    }

    func testClosingSettingsCommitsEditedSecondsBeforeChoosingCycleEffect() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["BREATHER_WINDOW_TEST"] == "1")
        for effect in RuleChangeEffect.allCases {
            let suite = "CycleRulesEditingUI.\(UUID().uuidString)"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let store = SettingsStore(userDefaults: defaults)
            store.settings.ruleChangeEffect = effect
            store.automaticRestSeconds = 120
            store.activateSavedRulesForCurrentCycle()
            var applications = 0
            let host = NSHostingView(rootView: SettingsView(settingsStore: store,
                updateMonitor: UpdateMonitor(userDefaults: defaults, installedVersion: "0.5.0",
                    checkRelease: { _ in UpdateCheckResponse(.upToDate) }),
                notificationService: LayoutTestNotificationService(), restSoundService: RestSoundService(),
                onApplyRulesToCurrentCycle: { applications += 1; store.activateSavedRulesForCurrentCycle() },
                onPreviewRestOverlay: {}))
            host.frame = NSRect(x: 0, y: 0, width: 1080, height: 900)
            let window = NSWindow(contentRect: host.frame, styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
            defer { window.orderOut(nil); window.contentView = nil; window.close() }
            settle(host)
            let field = try XCTUnwrap(descendants(SelectAllNumericTextField.self, in: host).first {
                $0.stringValue == "120"
            })
            XCTAssertTrue(window.makeFirstResponder(field))
            let editor = try XCTUnwrap(field.currentEditor() as? NSTextView)
            editor.selectAll(nil)
            editor.insertText("240", replacementRange: editor.selectedRange())
            XCTAssertEqual(store.automaticRestSeconds, 120, "Editing is committed on end-editing")
            window.close()
            try await Task.sleep(for: .milliseconds(1100))
            XCTAssertEqual(store.automaticRestSeconds, 240, "Closing must save the text being edited")
            XCTAssertEqual(store.effectiveAutomaticRestThreshold, effect == .immediate ? 240 : 120)
            XCTAssertEqual(applications, effect == .immediate ? 1 : 0)
            XCTAssertEqual(store.hasPendingRuleChanges, effect == .nextCycle)
        }
    }

    func testAutomaticRestSecondsPreviewAndModeAdjustment() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["BREATHER_WINDOW_TEST"] == "1")
        let previous = UserDefaults.standard.string(forKey: AppLanguage.preferenceKey)
        defer { restoreLanguage(previous) }
        let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("build/review/automatic-rest")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for language in [AppLanguage.simplifiedChinese, .traditionalChinese, .english] {
            UserDefaults.standard.set(language.rawValue, forKey: AppLanguage.preferenceKey)
            for width in [550.0, 800.0] {
                let suite = "AutomaticRestSecondsUI.\(UUID().uuidString)"
                let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
                defer { defaults.removePersistentDomain(forName: suite) }
                let store = SettingsStore(userDefaults: defaults)
                store.shortBreakSeconds = 37
                store.activateSavedRulesForCurrentCycle()
                store.automaticRestSeconds = 45
                let host = NSHostingView(rootView: AnyView(
                    ScheduleSettingsScreen(settingsStore: store, isWaitingToApplyRules: false,
                        onApplyRulesToCurrentCycle: {}, notificationService: LayoutTestNotificationService(),
                        onOpenNotificationSettings: {}).preferredColorScheme(.light)))
                // Keep the test viewport fixed when the replacement page is just a label.
                host.sizingOptions = []
                host.frame = NSRect(x: 0, y: 0, width: width, height: 1000)
                let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                window.contentView = host
                defer { window.orderOut(nil); window.contentView = nil; window.close() }
                settle(host)
                let picker = try XCTUnwrap(descendants(NSPopUpButton.self, in: host).first {
                    $0.accessibilityLabel() == L.tr("自动计为休息")
                })
                let seconds = try XCTUnwrap(descendants(NSStepper.self, in: host).first { $0.maxValue == 1800 })
                XCTAssertEqual(seconds.integerValue, 45)
                let lockHelp = try XCTUnwrap(descendants(RuntimeLogHelpButton.self, in: host).first)
                XCTAssertEqual(lockHelp.message, L.tr("锁屏或睡眠达到设定时长，视为完成休息；返回后重新开始工作计时。"))
                if language == .english {
                    let text = try recognizedText(in: host).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
                    XCTAssertTrue(text.contains("At least 37 sec"), text)
                }
                XCTAssertEqual(descendants(NSTextField.self, in: host).filter(\.isEditable).count, 6)
                func capture(_ mode: String) throws {
                    let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                    host.cacheDisplay(in: host.bounds, to: bitmap)
                    try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                        .write(to: directory.appendingPathComponent("seconds-\(language.rawValue)-\(Int(width))-\(mode).png"))
                    if mode == "returned", width == 800 {
                        let visiblePicker = try XCTUnwrap(descendants(NSPopUpButton.self, in: host).first {
                            $0.accessibilityLabel() == L.tr("自动计为休息")
                        })
                        let bounds = host.convert(visiblePicker.bounds, from: visiblePicker)
                        let image = try XCTUnwrap(bitmap.cgImage)
                        let scale = CGFloat(image.width) / host.bounds.width
                        let top = host.isFlipped ? bounds.minY : host.bounds.height - bounds.maxY
                        let region = NSRect(x: 0, y: max(0, top - 50) * scale,
                                            width: CGFloat(image.width), height: 230 * scale)
                        let detail = NSBitmapImageRep(cgImage: try XCTUnwrap(image.cropping(to: region)))
                        try XCTUnwrap(detail.representation(using: .png, properties: [:]))
                            .write(to: directory.appendingPathComponent("seconds-\(language.rawValue)-detail.png"))
                    }
                    for field in descendants(NSTextField.self, in: host).filter(\.isEditable) {
                        let rect = host.convert(field.bounds, from: field)
                        XCTAssertGreaterThanOrEqual(rect.minX, 0)
                        XCTAssertLessThanOrEqual(rect.maxX, width)
                    }
                }
                try capture("lock")
                picker.selectItem(withTitle: L.tr("锁屏、睡眠或无操作"))
                XCTAssertTrue(picker.sendAction(picker.action, to: picker.target))
                settle(host)
                XCTAssertEqual(store.automaticRestSeconds, 60)
                XCTAssertEqual(seconds.integerValue, 60)
                let help = try XCTUnwrap(descendants(RuntimeLogHelpButton.self, in: host).first)
                XCTAssertEqual(help.message, L.tr("锁屏、睡眠或无操作达到设定时长，视为完成休息；返回后重新开始工作计时。"),
                               "Help explains behavior; the dynamic minimum belongs below the duration label")
                XCTAssertFalse(help.message.contains(L.tr("阅读或看视频时若无键鼠操作，也可能被计为休息。")),
                               "The inactivity warning belongs on the page, not in help")
                try capture("idle")
                if language == .english {
                    let text = try recognizedText(in: host).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
                    XCTAssertTrue(text.contains("Adjusted to 60 sec"))
                    if width == 550 {
                        RunLoop.main.run(until: Date().addingTimeInterval(3.2))
                        settle(host)
                        let afterTimeout = try recognizedText(in: host).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
                        XCTAssertFalse(afterTimeout.contains("Adjusted to"))
                        XCTAssertTrue(afterTimeout.contains("At least 60 sec"))
                    }
                }
                // Replacing the page releases its transient feedback and native help.
                host.rootView = AnyView(Text("Another page"))
                settle(host)
                host.rootView = AnyView(ScheduleSettingsScreen(settingsStore: store, isWaitingToApplyRules: false,
                    onApplyRulesToCurrentCycle: {}, notificationService: LayoutTestNotificationService(),
                    onOpenNotificationSettings: {}).preferredColorScheme(.light))
                settle(host)
                if language == .english {
                    let observations = try recognizedText(in: host)
                    let text = observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
                    XCTAssertFalse(text.contains("Adjusted to"))
                    XCTAssertTrue(text.contains("At least 60 sec"), text)
                    let title = try XCTUnwrap(observations.first { $0.topCandidates(1).first?.string == "At least" })
                    let hint = try XCTUnwrap(observations.first { $0.topCandidates(1).first?.string.contains("At least 60 sec") == true })
                    // OCR can shift a line box by several points. Locate the first glyph's
                    // visible pixels so moving a divider does not create a false alignment failure.
                    let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                    host.cacheDisplay(in: host.bounds, to: bitmap)
                    let scale = CGFloat(bitmap.pixelsWide) / width
                    func leadingGlyph(_ observation: VNRecognizedTextObservation) throws -> CGFloat {
                        let candidate = try XCTUnwrap(observation.topCandidates(1).first)
                        let start = candidate.string.startIndex
                        let glyph = try XCTUnwrap(candidate.boundingBox(for: start..<candidate.string.index(after: start)))
                        let rect = glyph.boundingBox
                        let left = max(0, Int(floor(rect.minX * CGFloat(bitmap.pixelsWide))) - 4)
                        let right = min(bitmap.pixelsWide, Int(ceil(rect.maxX * CGFloat(bitmap.pixelsWide))) + 4)
                        let top = max(0, Int(floor((1 - rect.maxY) * CGFloat(bitmap.pixelsHigh))) - 2)
                        let bottom = min(bitmap.pixelsHigh, Int(ceil((1 - rect.minY) * CGFloat(bitmap.pixelsHigh))) + 2)
                        for x in left..<right {
                            for y in top..<bottom {
                                let color = try XCTUnwrap(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
                                if max(color.redComponent, color.greenComponent, color.blueComponent) < 0.7 {
                                    return CGFloat(x) / scale
                                }
                            }
                        }
                        XCTFail("No visible glyph pixels found")
                        return .infinity
                    }
                    XCTAssertEqual(try leadingGlyph(title), try leadingGlyph(hint), accuracy: 2,
                                   "The hint must share its label's leading edge")
                    let textGap = (title.boundingBox.minY - hint.boundingBox.maxY) * host.bounds.height
                    XCTAssertGreaterThan(textGap, 0)
                    XCTAssertLessThan(textGap, 12, "Supporting text must stay close to the main row")
                }
                try capture("returned")
                store.shortBreakSeconds = 90
                store.automaticRestSeconds = 90
                store.activateSavedRulesForCurrentCycle()
                store.shortBreakSeconds = 30
                store.automaticRestSeconds = 60
                settle(host)
                try capture("pending-cycle")
                let currentHelp = try XCTUnwrap(descendants(RuntimeLogHelpButton.self, in: host).first {
                    $0.accessibilityIdentifier() == "current-cycle-help"
                })
                let effectControl = try XCTUnwrap(descendants(NSSegmentedControl.self, in: host).first {
                    $0.label(forSegment: 0) == L.tr("下个周期")
                })
                let effectBounds = host.convert(effectControl.bounds, from: effectControl)
                let helpBounds = host.convert(currentHelp.bounds, from: currentHelp)
                let statusGap = host.isFlipped ? helpBounds.minY - effectBounds.maxY : effectBounds.minY - helpBounds.maxY
                XCTAssertGreaterThanOrEqual(statusGap, 8, "The action row needs clearance below the effect control")
                XCTAssertLessThanOrEqual(statusGap, 14, "Pending status must stay grouped with its effect control")
                let seconds90 = String(format: L.tr("%lld 秒"), 90)
                XCTAssertEqual(currentHelp.message, String(format:
                    L.tr("本周期：短休息 %@。\n锁屏、睡眠或无操作达到 %@，即视为完成休息。"), seconds90, seconds90))
                if width == 800 {
                    currentHelp.showHelp()
                    let content = try XCTUnwrap(currentHelp.helpPanel?.contentView)
                    settle(content)
                    let bitmap = try XCTUnwrap(content.bitmapImageRepForCachingDisplay(in: content.bounds))
                    content.cacheDisplay(in: content.bounds, to: bitmap)
                    try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                        .write(to: directory.appendingPathComponent("current-cycle-help-\(language.rawValue).png"))
                    currentHelp.closeHelp()
                }
                if language == .english {
                    let text = try recognizedText(in: host).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
                    XCTAssertTrue(text.contains("Saved for the next session"), text)
                    XCTAssertTrue(text.contains("Apply and restart timer"), text)
                    XCTAssertTrue(text.contains("At least 60 sec"), text)
                    XCTAssertTrue(currentHelp.message.contains("short breaks last 90 sec"))
                    XCTAssertTrue(currentHelp.message.contains("for 90 sec counts as a completed break."))
                }
                store.settings.ruleChangeEffect = .immediate
                host.rootView = AnyView(ScheduleSettingsScreen(settingsStore: store, isWaitingToApplyRules: true,
                    onApplyRulesToCurrentCycle: {}, notificationService: LayoutTestNotificationService(),
                    onOpenNotificationSettings: {}).preferredColorScheme(.light))
                settle(host)
                try capture("immediate")
                if language == .english {
                    let text = try recognizedText(in: host).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
                    XCTAssertTrue(text.contains("Changes restart the current timer."), text)
                }
            }
        }
    }

    func testPendingCycleHelpUsesActiveModeAndClosesWhenPendingChangesEnd() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["BREATHER_WINDOW_TEST"] == "1")
        let previous = UserDefaults.standard.string(forKey: AppLanguage.preferenceKey)
        defer { restoreLanguage(previous) }
        for language in [AppLanguage.simplifiedChinese, .traditionalChinese, .english] {
            UserDefaults.standard.set(language.rawValue, forKey: AppLanguage.preferenceKey)
            for activeMode in AutomaticRestMode.allCases {
                let suite = "PendingCycleHelp.\(UUID().uuidString)"
                let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
                defer { defaults.removePersistentDomain(forName: suite) }
                let store = SettingsStore(userDefaults: defaults)
                store.settings.ruleChangeEffect = .nextCycle
                store.shortBreakSeconds = 41
                store.settings.automaticRestMode = activeMode
                store.automaticRestSeconds = 120
                store.activateSavedRulesForCurrentCycle()
                let savedMode: AutomaticRestMode = activeMode == .disabled ? .lockSleepOrIdle : .disabled
                store.settings.automaticRestMode = savedMode
                store.shortBreakSeconds = 43
                store.automaticRestSeconds = 180
                func page() -> AnyView {
                    AnyView(ScheduleSettingsScreen(settingsStore: store, isWaitingToApplyRules: false,
                        onApplyRulesToCurrentCycle: { store.activateSavedRulesForCurrentCycle() },
                        notificationService: LayoutTestNotificationService(), onOpenNotificationSettings: {}))
                }
                let host = NSHostingView(rootView: page())
                host.sizingOptions = []
                host.frame = NSRect(x: 0, y: 0, width: 550, height: 1000)
                let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                window.contentView = host
                defer { window.orderOut(nil); window.contentView = nil; window.close() }
                func pendingHelp() -> RuntimeLogHelpButton? {
                    descendants(RuntimeLogHelpButton.self, in: host).first {
                        $0.accessibilityIdentifier() == "current-cycle-help"
                    }
                }
                settle(host)
                let help = try XCTUnwrap(pendingHelp())
                let short = String(format: L.tr("%lld 秒"), 41)
                let threshold = String(format: L.tr("%lld 秒"), 120)
                let expected: String
                switch activeMode {
                case .disabled:
                    expected = String(format: L.tr("本周期：短休息 %@。\n自动计为休息已关闭。"), short)
                case .lockOrSleep:
                    expected = String(format: L.tr("本周期：短休息 %@。\n锁屏或睡眠达到 %@，即视为完成休息。"), short, threshold)
                case .lockSleepOrIdle:
                    expected = String(format: L.tr("本周期：短休息 %@。\n锁屏、睡眠或无操作达到 %@，即视为完成休息。"), short, threshold)
                }
                XCTAssertEqual(help.message, expected, "Pending edits must not replace the active cycle's explanation")
                help.showHelp()
                XCTAssertTrue(help.helpPanel?.isVisible == true)
                host.rootView = AnyView(Text("Another page"))
                settle(host)
                XCTAssertNil(help.helpPanel, "Leaving the page must close the pending-cycle explanation")
                host.rootView = page()
                settle(host)
                let returnedHelp = try XCTUnwrap(pendingHelp())
                XCTAssertEqual(returnedHelp.message, expected)
                XCTAssertNil(returnedHelp.helpPanel, "Returning must not reopen the explanation")
                returnedHelp.showHelp()
                XCTAssertTrue(returnedHelp.helpPanel?.isVisible == true)
                store.activateSavedRulesForCurrentCycle()
                settle(host)
                XCTAssertNil(pendingHelp(), "Applying the saved rules must remove the pending status")
                XCTAssertNil(returnedHelp.helpPanel, "Removing the pending status must close its explanation")
            }
        }
    }

    private func restoreLanguage(_ previous: String?) {
        if let previous {
            UserDefaults.standard.set(previous, forKey: AppLanguage.preferenceKey)
        } else {
            UserDefaults.standard.removeObject(forKey: AppLanguage.preferenceKey)
        }
        LocalizationRefresh.shared.refresh()
    }

    private func settle(_ host: NSView) {
        RunLoop.main.run(until: Date().addingTimeInterval(0.15))
        host.layoutSubtreeIfNeeded()
    }

    private func descendants<View: NSView>(_ type: View.Type, in view: NSView) -> [View] {
        if let matching = view as? View { return [matching] }
        return view.subviews.flatMap { descendants(type, in: $0) }
    }

    private func recognizedText(in host: NSView) throws -> [VNRecognizedTextObservation] {
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en-US"]
        try VNImageRequestHandler(cgImage: XCTUnwrap(bitmap.cgImage), options: [:]).perform([request])
        return request.results ?? []
    }

    func testOneLineDescriptionDoesNotReserveAnEmptySecondLine() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["BREATHER_WINDOW_TEST"] == "1")
        let previous = UserDefaults.standard.string(forKey: AppLanguage.preferenceKey)
        defer {
            if let previous {
                UserDefaults.standard.set(previous, forKey: AppLanguage.preferenceKey)
            } else {
                UserDefaults.standard.removeObject(forKey: AppLanguage.preferenceKey)
            }
            LocalizationRefresh.shared.refresh()
        }
        for language in [AppLanguage.simplifiedChinese, .traditionalChinese, .english] {
            UserDefaults.standard.set(language.rawValue, forKey: AppLanguage.preferenceKey)
            func cardHeight(width: CGFloat) -> CGFloat {
                let card = RestContentOption(mode: .snowy, isSelected: false,
                                             thumbnail: RestThemeThumbnailConfiguration(mode: .snowy, settings: AppSettings(), duration: 30),
                                             onSelect: {})
                let host = NSHostingView(rootView: card.frame(width: width))
                return host.fittingSize.height
            }
            let wide = cardHeight(width: 240)
            let narrow = cardHeight(width: 140)
            XCTAssertGreaterThan(narrow - wide, 8, "Only actual wrapping should add a description line in \(language)")
            XCTAssertLessThan(narrow - wide, 24)
        }
    }

    func testRestTextPickerWidthsTrackSelectionInSettingsScreen() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["BREATHER_WINDOW_TEST"] == "1")
        let previous = UserDefaults.standard.string(forKey: AppLanguage.preferenceKey)
        defer {
            if let previous {
                UserDefaults.standard.set(previous, forKey: AppLanguage.preferenceKey)
            } else {
                UserDefaults.standard.removeObject(forKey: AppLanguage.preferenceKey)
            }
            LocalizationRefresh.shared.refresh()
        }
        UserDefaults.standard.set(AppLanguage.english.rawValue, forKey: AppLanguage.preferenceKey)
        let suite = "RestTextPickerLayout.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SettingsStore(userDefaults: defaults)
        store.settings.restOverlayPrompt = .random
        store.settings.restOverlaySubtitle = .random
        let view = RestOverlaySettingsScreen(settingsStore: store, restSoundService: RestSoundService(), onPreviewRestOverlay: {})
        let host = NSHostingView(rootView: view.frame(width: 550, height: 1700))
        host.frame = NSRect(x: 0, y: 0, width: 550, height: 1700)
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer {
            window.orderOut(nil)
            window.contentView = nil
            window.close()
        }
        func popups(in view: NSView) -> [NSPopUpButton] {
            if let popup = view as? NSPopUpButton { return [popup] }
            return view.subviews.flatMap { popups(in: $0) }
        }
        func settle() {
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
            host.layoutSubtreeIfNeeded()
        }
        settle()
        let main = try XCTUnwrap(popups(in: host).first { $0.accessibilityLabel() == "Main message" })
        let supporting = try XCTUnwrap(popups(in: host).first { $0.accessibilityLabel() == "Supporting text" })
        let shortWidth = supporting.frame.width
        let initialControls = host.convert(main.bounds, from: main).union(host.convert(supporting.bounds, from: supporting))
        XCTAssertEqual(main.frame.width, shortWidth, accuracy: 1)
        XCTAssertLessThanOrEqual(shortWidth, 140)
        for (name, subtitle) in [("long", RestOverlaySubtitle.softenShoulders), ("longest", .leaveScreen), ("random", .random)] {
            store.settings.restOverlaySubtitle = subtitle
            settle()
            XCTAssertTrue(popups(in: host).contains { $0 === supporting }, "The native control must survive row wrapping for \(name)")
            if subtitle == .random {
                XCTAssertEqual(supporting.frame.width, shortWidth, accuracy: 1)
            } else {
                XCTAssertGreaterThan(supporting.frame.width, shortWidth)
                XCTAssertLessThanOrEqual(supporting.frame.width, 360)
            }
            let controls = host.convert(main.bounds, from: main).union(host.convert(supporting.bounds, from: supporting))
            if subtitle == .random {
                XCTAssertEqual(controls.height, initialControls.height, accuracy: 1, "Random must restore the compact row layout")
            }
            XCTAssertEqual(supporting.cell?.title, subtitle.title)
            XCTAssertEqual(supporting.titleOfSelectedItem, subtitle.title)
            let region = CGRect(x: 0, y: controls.minY - 50, width: 550, height: controls.height + 90)
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: region))
            host.cacheDisplay(in: region, to: bitmap)
            if subtitle == .leaveScreen {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.recognitionLanguages = ["en-US"]
                try VNImageRequestHandler(cgImage: try XCTUnwrap(bitmap.cgImage), options: [:]).perform([request])
                let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
                XCTAssertTrue(text.contains("Step away from the screen."), "Truncation must preserve the original sentence's beginning")
                XCTAssertTrue(text.contains("Give yourself"), "Use the available width instead of shortening the text to its first clause")
                XCTAssertFalse(text.contains("little space"), "The full sentence belongs in the menu, without a duplicate preview below the control")
            }
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                .write(to: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("rest-text-\(name).png"))
        }
    }

    func testThemeColumnsDependOnWidthAcrossLanguages() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["BREATHER_WINDOW_TEST"] == "1",
                          "Run window layout checks separately from video rendering tests.")
        let previous = UserDefaults.standard.string(forKey: AppLanguage.preferenceKey)
        defer {
            if let previous {
                UserDefaults.standard.set(previous, forKey: AppLanguage.preferenceKey)
            } else {
                UserDefaults.standard.removeObject(forKey: AppLanguage.preferenceKey)
            }
            LocalizationRefresh.shared.refresh()
        }
        for language in [AppLanguage.simplifiedChinese, .traditionalChinese, .english] {
            UserDefaults.standard.set(language.rawValue, forKey: AppLanguage.preferenceKey)
            for width in [800.0, 720.0, 672.0, 550.0, 410.0] {
                let view = RestThemePicker(settings: .constant(AppSettings()), duration: 30, isResting: false)
                    .frame(width: width, alignment: .topLeading)
                    .frame(height: 750, alignment: .topLeading)
                    .background(Color(nsColor: .windowBackgroundColor))
                let host = NSHostingView(rootView: view)
                host.frame = NSRect(x: 0, y: 0, width: width, height: 750)
                let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                window.contentView = host
                window.makeKeyAndOrderFront(nil)
                defer {
                    window.orderOut(nil)
                    window.contentView = nil
                    window.close()
                }
                host.layoutSubtreeIfNeeded()
                let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: bitmap)
                let image = try XCTUnwrap(bitmap.cgImage)
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.recognitionLanguages = ["en-US"]
                try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
                // Every real thumbnail has the same countdown. Compare its positions
                // rather than relying on OCR accuracy for Chinese theme names.
                var boxes: [CGRect] = []
                for observation in request.results ?? [] {
                    let text = observation.topCandidates(1).first?.string ?? ""
                    if text.replacingOccurrences(of: " ", with: "") == "00:30" {
                        boxes.append(observation.boundingBox)
                    }
                }
                boxes.sort { first, second in
                    if abs(first.midY - second.midY) > 0.03 { return first.midY > second.midY }
                    return first.midX < second.midX
                }
                XCTAssertGreaterThanOrEqual(boxes.count, 3)
                guard boxes.count >= 3 else { continue }
                if width >= 672 {
                    XCTAssertEqual(boxes[0].midY, boxes[1].midY, accuracy: 0.03)
                    XCTAssertEqual(boxes[0].midY, boxes[2].midY, accuracy: 0.03,
                                   "Three columns must fit in every language at the same width")
                } else if width == 550 {
                    XCTAssertEqual(boxes[0].midY, boxes[1].midY, accuracy: 0.03)
                    XCTAssertGreaterThan(boxes[0].midY - boxes[2].midY, 0.1)
                } else {
                    XCTAssertGreaterThan(boxes[0].midY - boxes[1].midY, 0.1)
                    XCTAssertGreaterThan(boxes[1].midY - boxes[2].midY, 0.1)
                }
                let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("BreatherLayoutAudit")
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                    .write(to: directory.appendingPathComponent("themes-\(language.rawValue)-\(Int(width)).png"))
            }
        }
    }
}

@MainActor
private final class LayoutTestNotificationService: NotificationSettingsServicing {
    var status: NotificationPermissionStatus = .authorized
    private(set) var authorizationCheckCount = 0

    func authorizationStatus() async -> NotificationPermissionStatus {
        authorizationCheckCount += 1
        return status
    }

    func requestAuthorization() async -> NotificationPermissionStatus {
        XCTFail("The schedule screen must not request permission automatically")
        return status
    }

    func sendPreviewNotification(playSound: Bool, soundEffect: RestSoundEffect) async -> NotificationPreviewResult {
        XCTFail("The schedule screen must not send preview notifications")
        return .failed
    }
}

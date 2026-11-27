import AppKit
import SwiftUI
import XCTest
@testable import Breather

@MainActor
final class InstalledReleaseNoticeTests: XCTestCase {
    func testFreshInstallOnlyRecordsBaseline() throws {
        try withDefaults { defaults in
            XCTAssertNil(launch("0.6.0", in: defaults).pendingNotes)
            XCTAssertNil(launch("0.6.0", in: defaults, hasPreviousUse: true).pendingNotes)
        }
    }

    func testUpgradeStaysPendingAcrossLaunchesUntilDismissed() throws {
        try withDefaults { defaults in
            XCTAssertNil(launch("0.5.0", in: defaults).pendingNotes)
            XCTAssertEqual(launch("0.6.0", in: defaults).pendingNotes?.version, "0.6.0")

            let reopened = launch("0.6.0", in: defaults)
            XCTAssertNotNil(reopened.pendingNotes)
            reopened.dismiss()
            XCTAssertNil(reopened.pendingNotes)
            XCTAssertNil(launch("0.6.0", in: defaults).pendingNotes)
            XCTAssertNil(launch("0.5.0", in: defaults).pendingNotes)
            XCTAssertNil(launch("0.6.0", in: defaults).pendingNotes)
        }
    }

    func testFirstVersionWithNoticeCanRecognizeLegacyUse() throws {
        try withDefaults { defaults in
            let migrated = launch("0.6.0", in: defaults, hasPreviousUse: true)
            XCTAssertEqual(migrated.pendingNotes?.highlights.count, 3)
            XCTAssertNil(launch("0.5.0", in: defaults).pendingNotes)
            XCTAssertNotNil(launch("0.6.0", in: defaults).pendingNotes)
        }
    }

    func testSkippingVersionsUsesOnlyInstalledSummaryAndAllowsMoreHighlights() throws {
        try withDefaults { defaults in
            let old = launch("0.6.0", in: defaults, hasPreviousUse: true)
            let new = InstalledReleaseNotice(userDefaults: defaults, installedVersion: "1.3.0", hasPreviousUse: false) { version in
                InstalledReleaseNotes(version: version, highlights: ["First", "Second", "Third", "Fourth"])
            }
            old.dismiss()
            XCTAssertEqual(new.pendingNotes?.version, "1.3.0")
            XCTAssertEqual(new.pendingNotes?.highlights, ["First", "Second", "Third", "Fourth"])
            XCTAssertEqual(InstalledReleaseNotice(userDefaults: defaults, installedVersion: "1.3.0", hasPreviousUse: false) {
                InstalledReleaseNotes(version: $0, highlights: ["Only this version"])
            }.pendingNotes?.version, "1.3.0")
        }
    }

    func testVersionsWithoutNotesDoNotReplayPreviousNotes() throws {
        try withDefaults { defaults in
            XCTAssertNotNil(launch("0.6.0", in: defaults, hasPreviousUse: true).pendingNotes)
            XCTAssertNil(InstalledReleaseNotice(userDefaults: defaults, installedVersion: "999.0.0", hasPreviousUse: true) {
                InstalledReleaseNotes(version: $0, highlights: [])
            }.pendingNotes)
            XCTAssertNil(launch("999.0.0", in: defaults).pendingNotes)
            XCTAssertNil(launch("0.6.0", in: defaults).pendingNotes)
        }
    }

    func testBundledNotesHaveCopyForEachSupportedLanguage() throws {
        let notes = try XCTUnwrap(InstalledReleaseNotes.bundled(for: "0.7.0"))
        XCTAssertEqual(notes.localizedHighlights(language: .simplifiedChinese),
                       ["查看近 30 天的休息记录", "提醒时可选「我刚休息过」", "修复雨滴和小恐龙动画提前停止的问题"])
        XCTAssertEqual(notes.localizedHighlights(language: .traditionalChinese),
                       ["查看近 30 天的休息記錄", "提醒時可選「我剛休息過」", "修正雨滴與小恐龍動畫提早停止的問題"])
        XCTAssertEqual(notes.localizedHighlights(language: .english),
                       ["View your last 30 days of breaks", "Choose “I just took a break”", "Fixed rain and dinosaur animations stopping early"])
        XCTAssertEqual(String(format: L.tr("已更新到 %@", language: .english), notes.version), "Updated to 0.7.0")
        XCTAssertEqual(L.tr("关闭本版更新提示", language: .english), "Dismiss update summary")
    }

    func testNarrowSidebarRendersNotesAndRemovesDismissedCard() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["BREATHER_WINDOW_TEST"] == "1")
        let appDefaults = UserDefaults.standard
        let oldLanguage = appDefaults.string(forKey: AppLanguage.preferenceKey)
        defer {
            appDefaults.set(oldLanguage, forKey: AppLanguage.preferenceKey)
            LocalizationRefresh.shared.refresh()
        }
        _ = NSApplication.shared

        try withDefaults { defaults in
            _ = launch("0.6.0", in: defaults)
            let notice = launch("0.7.0", in: defaults)
            let frame = NSRect(x: 0, y: 0, width: 150, height: SettingsWindowMetrics.minimumSize.height)
            let host = NSHostingView(rootView: SettingsSidebar(
                selectedSection: .constant(.schedule), hasAvailableUpdate: false,
                installedReleaseNotice: notice, onQuit: {}
            ).frame(width: frame.width, height: frame.height))
            host.frame = frame
            let window = NSWindow(contentRect: frame, styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
            window.makeKeyAndOrderFront(nil)
            defer { window.orderOut(nil); window.contentView = nil; window.close() }

            for language in [AppLanguage.simplifiedChinese, .traditionalChinese, .english] {
                appDefaults.set(language.rawValue, forKey: AppLanguage.preferenceKey)
                LocalizationRefresh.shared.refresh()
                window.appearance = NSAppearance(named: language == .english ? .darkAqua : .aqua)
                RunLoop.main.run(until: Date().addingTimeInterval(0.1))
                host.layoutSubtreeIfNeeded()

                try captureSidebar(host, named: language.rawValue)
                let notes = try XCTUnwrap(notice.pendingNotes)
                let card = SettingsReleaseNotesCard(notes: notes, onDismiss: notice.dismiss)
                let cardHost = NSHostingView(rootView: card.frame(width: frame.width - 16))
                let cardHeight = cardHost.fittingSize.height
                XCTAssertGreaterThan(cardHeight, 65)
                XCTAssertLessThan(cardHeight, 185, "Short summaries should size to their content")

                if language == .english {
                    let manyNotes = InstalledReleaseNotes(version: notes.version,
                        highlights: (1...14).map { "Core change \($0) with an explanation" })
                    let longCard = NSHostingView(rootView: SettingsReleaseNotesCard(notes: manyNotes, onDismiss: {})
                        .frame(width: frame.width - 16))
                    XCTAssertGreaterThan(longCard.fittingSize.height, cardHeight)
                    XCTAssertLessThan(longCard.fittingSize.height, 230, "Long summaries should scroll within the card")

                    window.orderOut(nil)
                    window.makeKeyAndOrderFront(nil)
                    XCTAssertNotNil(notice.pendingNotes)
                    try clickCloseButton(in: window, cardHeight: cardHeight)
                    RunLoop.main.run(until: Date().addingTimeInterval(0.1))
                    host.layoutSubtreeIfNeeded()
                    XCTAssertNil(notice.pendingNotes)
                    XCTAssertNil(launch("0.7.0", in: defaults).pendingNotes)
                    try captureSidebar(host, named: "dismissed")
                }
            }
        }
    }

    private func clickCloseButton(in window: NSWindow, cardHeight: CGFloat) throws {
        // The button aligns with the bottom of the two-line English title.
        let location = NSPoint(x: window.contentLayoutRect.width - 29,
                               y: SettingsFooterMetrics.height + 4 + cardHeight - 27)
        let mouseUp = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseUp, location: location,
            modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil,
            eventNumber: 2, clickCount: 1, pressure: 0))
        let mouseDown = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown, location: location,
            modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil,
            eventNumber: 1, clickCount: 1, pressure: 1))
        NSApp.postEvent(mouseUp, atStart: true)
        window.sendEvent(mouseDown)
        window.sendEvent(mouseUp)
    }

    private func captureSidebar(_ host: NSView, named name: String) throws {
        guard let output = ProcessInfo.processInfo.environment["BREATHER_SCREENSHOT_DIR"] else { return }
        let directory = URL(fileURLWithPath: output, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: directory.appendingPathComponent("installed-release-\(name).png"), options: .atomic)
    }

    private func launch(_ version: String, in defaults: UserDefaults, hasPreviousUse: Bool = false) -> InstalledReleaseNotice {
        InstalledReleaseNotice(userDefaults: defaults, installedVersion: version, hasPreviousUse: hasPreviousUse)
    }

    private func withDefaults(_ body: (UserDefaults) throws -> Void) throws {
        let suite = "InstalledReleaseNoticeTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(defaults)
    }
}

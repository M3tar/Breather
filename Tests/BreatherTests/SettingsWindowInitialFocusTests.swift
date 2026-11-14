import AppKit
import SwiftUI
import XCTest
@testable import Breather

@MainActor
final class SettingsWindowInitialFocusTests: XCTestCase {
    func testOpeningSettingsFocusesSelectedSidebarWithoutEditingWorkDuration() throws {
        let harness = try makeHarness()
        defer { close(harness) }

        XCTAssertTrue(harness.window.initialFirstResponder === harness.sidebar)
        XCTAssertTrue(harness.window.firstResponder === harness.sidebar)
        XCTAssertEqual(harness.sidebar.selectedRow, 0)
        XCTAssertNil(harness.workDuration.currentEditor())
        XCTAssertEqual(harness.workDuration.stringValue, "40")
    }

    func testReturningToOpenWindowPreservesEditingButReopeningFocusesSidebar() throws {
        let harness = try makeHarness()
        defer { close(harness) }
        XCTAssertTrue(harness.window.makeFirstResponder(harness.workDuration))
        let editor = try XCTUnwrap(harness.workDuration.currentEditor())

        NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: harness.window)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        XCTAssertTrue(harness.workDuration.currentEditor() === editor)

        harness.window.close()
        harness.window.makeKeyAndOrderFront(nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        XCTAssertTrue(harness.window.firstResponder === harness.sidebar)
        XCTAssertEqual(harness.sidebar.selectedRow, 0)
        XCTAssertNil(harness.workDuration.currentEditor())
    }

    func testClickingIntoNumericEditingDoesNotRefocusSidebarOnUpdate() throws {
        let harness = try makeHarness()
        defer { close(harness) }
        XCTAssertTrue(harness.window.makeFirstResponder(harness.workDuration))
        let editor = try XCTUnwrap(harness.workDuration.currentEditor())

        harness.store.settings.showCountdownInMenuBar.toggle()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        XCTAssertTrue(harness.workDuration.currentEditor() === editor)
        XCTAssertEqual(harness.sidebar.selectedRow, 0)
    }

    func testSidebarKeepsNativeTabNavigation() throws {
        let harness = try makeHarness()
        defer { close(harness) }
        XCTAssertTrue(harness.window.makeFirstResponder(harness.sidebar))

        harness.window.selectNextKeyView(harness.sidebar)

        XCTAssertFalse(harness.window.firstResponder === harness.sidebar)
        XCTAssertNotNil(harness.window.firstResponder)
    }

    private struct Harness {
        let window: NSWindow
        let sidebar: NSTableView
        let workDuration: SelectAllNumericTextField
        let store: SettingsStore
        let defaults: UserDefaults
        let suite: String
    }

    private func makeHarness() throws -> Harness {
        let suite = "SettingsWindowInitialFocusTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let store = SettingsStore(userDefaults: defaults)
        store.workMinutes = 40
        let host = NSHostingView(rootView: SettingsView(
            settingsStore: store,
            updateMonitor: UpdateMonitor(userDefaults: defaults, installedVersion: "0.3.0"),
            notificationService: FocusTestNotificationService(),
            restSoundService: RestSoundService(),
            onApplyRulesToCurrentCycle: {}, onPreviewRestOverlay: {}
        ))
        host.frame = NSRect(x: 0, y: 0, width: 1080, height: 720)
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        let views = descendants(host)
        let sidebar = try XCTUnwrap(views.compactMap { $0 as? NSTableView }.first)
        let workDuration = try XCTUnwrap(views.compactMap { $0 as? SelectAllNumericTextField }.first { $0.stringValue == "40" })
        return Harness(window: window, sidebar: sidebar, workDuration: workDuration, store: store, defaults: defaults, suite: suite)
    }

    private func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap { descendants($0) }
    }

    private func close(_ harness: Harness) {
        harness.window.makeFirstResponder(nil)
        harness.window.close()
        harness.window.contentView = nil
        harness.defaults.removePersistentDomain(forName: harness.suite)
    }
}

@MainActor
private final class FocusTestNotificationService: NotificationSettingsServicing {
    func authorizationStatus() async -> NotificationPermissionStatus { .authorized }
    func requestAuthorization() async -> NotificationPermissionStatus { .authorized }
    func sendPreviewNotification(playSound: Bool, soundEffect: RestSoundEffect) async -> NotificationPreviewResult { .delivered }
}

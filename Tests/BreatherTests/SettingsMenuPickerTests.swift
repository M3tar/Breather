import AppKit
import SwiftUI
import XCTest
@testable import Breather

@MainActor
final class SettingsMenuPickerTests: XCTestCase {
    func testDefaultAnnotationAppearsOnlyInExpandedMenuTitle() throws {
        let host = NSHostingView(rootView: SettingsMenuPicker("Speed", selection: .constant(0), options: [
            SettingsMenuOption(value: 0, title: "0.5×", menuTitle: "0.5× (Default)"),
            SettingsMenuOption(value: 1, title: "1×")
        ]))
        host.frame = NSRect(x: 0, y: 0, width: 220, height: 40)
        host.layoutSubtreeIfNeeded()
        let popup = try XCTUnwrap(findPopup(in: host))
        XCTAssertEqual(popup.itemTitle(at: 0), "0.5× (Default)")
        XCTAssertEqual(popup.cell?.title, "0.5×")
        XCTAssertEqual(popup.itemTitle(at: 1), "1×")
    }

    func testNativeSelectionWaitsForMatchingWidthAndPreservesFullSentence() async throws {
        let sentence = "Step away from the screen. Give yourself a little space."
        var selection = 0
        let options = [SettingsMenuOption(value: 0, title: "Random"),
                       SettingsMenuOption(value: 1, title: sentence)]
        func picker(_ value: Int) -> some View {
            SettingsMenuPicker("Supporting text",
                               selection: Binding(get: { value }, set: { selection = $0 }), options: options)
                .fixedSize()
        }
        let host = NSHostingView(rootView: picker(selection))
        host.frame = NSRect(x: 0, y: 0, width: 500, height: 40)
        host.layoutSubtreeIfNeeded()
        let popup = try XCTUnwrap(findPopup(in: host))
        let initialHeight = popup.frame.height
        for nextSelection in [1, 0, 1, 0] {
            let oldLabel = options[selection].title
            popup.selectItem(at: nextSelection)
            popup.synchronizeTitleAndSelectedItem()
            // Native menu selection happens before the binding and SwiftUI layout.
            // The full sentence must never be inserted into the old compact width.
            XCTAssertEqual(popup.cell?.title, oldLabel)
            _ = popup.sendAction(popup.action!, to: popup.target)
            XCTAssertEqual(selection, nextSelection)
            host.rootView = picker(selection)
            let selected = options[selection]
            let displayed = selected.title
            let measurement = NSPopUpButtonCell(textCell: "", pullsDown: false)
            measurement.addItem(withTitle: displayed)
            measurement.font = popup.font
            measurement.controlSize = popup.controlSize
            measurement.bezelStyle = popup.bezelStyle
            let width = min(360, max(96, ceil(measurement.cellSize.width)))
            for _ in 0..<4 {
                try await Task.sleep(for: .milliseconds(10))
                host.layoutSubtreeIfNeeded()
                XCTAssertEqual(popup.cell?.title, displayed)
                XCTAssertEqual(popup.frame.width, width, accuracy: 1, "A new sentence must already have its matching width")
                XCTAssertEqual(popup.frame.height, initialHeight, accuracy: 1)
                XCTAssertEqual(popup.titleOfSelectedItem, selected.title)
                XCTAssertEqual(popup.toolTip, selected.title)
                XCTAssertEqual(popup.accessibilityHelp(), selected.title)
                XCTAssertEqual(popup.accessibilityValue() as? String, selected.title)
            }
        }
        XCTAssertTrue(findPopup(in: host) === popup)
    }

    func testWidthFollowsSelectedItemAndKeepsFullMenuTitles() async throws {
        var selection = 0
        let longTitle = "Relax your neck and shoulders. Take it slow."
        let options = [SettingsMenuOption(value: 0, title: "Random"),
                       SettingsMenuOption(value: 1, title: longTitle)]
        func picker(_ value: Int) -> some View {
            SettingsMenuPicker("Supporting text",
                               selection: Binding(get: { value }, set: { selection = $0 }),
                               options: options).fixedSize()
        }
        let host = NSHostingView(rootView: picker(selection))
        host.frame = NSRect(x: 0, y: 0, width: 500, height: 40)
        host.layoutSubtreeIfNeeded()
        let popup = try XCTUnwrap(findPopup(in: host))
        let shortWidth = popup.frame.width
        XCTAssertLessThanOrEqual(shortWidth, 140, "A short selection must not inherit the longest menu title's width")

        selection = 1
        host.rootView = picker(selection)
        try await Task.sleep(for: .milliseconds(30))
        host.layoutSubtreeIfNeeded()
        XCTAssertTrue(findPopup(in: host) === popup)
        XCTAssertGreaterThan(popup.frame.width, shortWidth)
        XCTAssertLessThanOrEqual(popup.frame.width, 360)
        XCTAssertEqual(popup.titleOfSelectedItem, longTitle)
        XCTAssertEqual(popup.toolTip, longTitle)
        XCTAssertEqual(popup.itemTitle(at: 1), longTitle)

        selection = 0
        host.rootView = picker(selection)
        try await Task.sleep(for: .milliseconds(30))
        host.layoutSubtreeIfNeeded()
        XCTAssertEqual(popup.titleOfSelectedItem, "Random")
        XCTAssertLessThanOrEqual(popup.frame.width, 140)
        XCTAssertEqual(popup.frame.width, shortWidth, accuracy: 1)
    }

    func testTranslationUpdatesSelectedTitleWithoutReplacingControlOrMenuItems() async throws {
        var selection = AppearancePreference.system
        var writes = 0
        let binding = Binding(get: { selection }, set: { selection = $0; writes += 1 })
        func picker(_ language: AppLanguage) -> SettingsMenuPicker<AppearancePreference> {
            SettingsMenuPicker(L.tr("应用外观", language: language), selection: binding,
                options: AppearancePreference.allCases.map {
                    SettingsMenuOption(value: $0, title: L.tr(sourceTitle($0), context: "appearance", language: language))
                })
        }
        let host = NSHostingView(rootView: picker(.simplifiedChinese))
        host.frame = NSRect(x: 0, y: 0, width: 220, height: 30)
        host.layoutSubtreeIfNeeded()
        let popup = try XCTUnwrap(findPopup(in: host))
        let items = popup.itemArray
        XCTAssertEqual(popup.titleOfSelectedItem, L.tr("跟随系统", context: "appearance", language: .simplifiedChinese))

        for language in [AppLanguage.english, .traditionalChinese, .simplifiedChinese] {
            host.rootView = picker(language)
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(30))
            host.layoutSubtreeIfNeeded()
            XCTAssertTrue(findPopup(in: host) === popup)
            XCTAssertEqual(popup.itemArray.count, items.count)
            for (before, after) in zip(items, popup.itemArray) { XCTAssertTrue(before === after) }
            XCTAssertEqual(popup.titleOfSelectedItem, L.tr("跟随系统", context: "appearance", language: language))
            XCTAssertEqual(selection, .system)
            XCTAssertEqual(writes, 0, "Relabeling must not change persisted settings")
        }
        popup.selectItem(at: 1)
        _ = popup.sendAction(popup.action!, to: popup.target)
        XCTAssertEqual(selection, AppearancePreference.allCases[1])
        XCTAssertEqual(writes, 1)
    }

    func testSeparatorsDoNotShiftSelectionAndDisabledStateReachesNativeControl() async throws {
        var selection = RestSoundEffect.none
        let binding = Binding(get: { selection }, set: { selection = $0 })
        let options = [
            SettingsMenuOption(value: RestSoundEffect.random, title: "Random"),
            SettingsMenuOption(value: .none, title: "None", separatorBefore: true)
        ]
        let picker = SettingsMenuPicker("Sound", selection: binding, options: options)
        let host = NSHostingView(rootView: picker.disabled(true))
        host.frame = NSRect(x: 0, y: 0, width: 150, height: 30)
        host.layoutSubtreeIfNeeded()
        let popup = try XCTUnwrap(findPopup(in: host))
        XCTAssertEqual(popup.titleOfSelectedItem, "None")
        XCTAssertTrue(popup.itemArray[1].isSeparatorItem)
        XCTAssertFalse(popup.isEnabled)
        host.rootView = picker.disabled(false)
        try await Task.sleep(for: .milliseconds(30))
        host.layoutSubtreeIfNeeded()
        XCTAssertTrue(popup.isEnabled)
        popup.selectItem(at: 0)
        _ = popup.sendAction(popup.action!, to: popup.target)
        XCTAssertEqual(selection, .random)
        popup.selectItem(at: 2)
        _ = popup.sendAction(popup.action!, to: popup.target)
        XCTAssertEqual(selection, .none)
    }

    private func sourceTitle(_ preference: AppearancePreference) -> String {
        switch preference {
        case .system: "跟随系统"
        case .light: "浅色"
        case .dark: "深色"
        }
    }

    private func findPopup(in view: NSView) -> NSPopUpButton? {
        if let popup = view as? NSPopUpButton { return popup }
        return view.subviews.lazy.compactMap { self.findPopup(in: $0) }.first
    }
}

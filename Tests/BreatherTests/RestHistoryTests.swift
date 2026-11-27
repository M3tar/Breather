import ScreenCaptureKit
import SwiftUI
import XCTest
@testable import Breather

@MainActor
final class RestHistoryTests: XCTestCase {
    func testRecordTimeRespectsHourCycleAndPads24HourMorning() throws {
        let calendar = Calendar.current
        let morning = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 19, hour: 9, minute: 42)))
        let afternoon = try XCTUnwrap(calendar.date(byAdding: .hour, value: 4, to: morning))
        let noon = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 19, hour: 12, minute: 1)))
        let twelveHour = Locale(identifier: "en-US-u-hc-h12")
        for localeID in ["zh-CN-u-hc-h23", "zh-TW-u-hc-h23", "en-US-u-hc-h23"] {
            let locale = Locale(identifier: localeID)
            XCTAssertEqual(RestHistoryScreen.recordTime(noon, locale: locale), "12:01")
            XCTAssertEqual(RestHistoryScreen.recordTime(morning, locale: locale), "09:42")
            XCTAssertEqual(RestHistoryScreen.recordTime(afternoon, locale: locale), "13:42")
        }
        for (time, expected) in [(morning, "9:42 AM"), (afternoon, "1:42 PM"), (noon, "12:01 PM")] {
            let text = RestHistoryScreen.recordTime(time, locale: twelveHour)
            XCTAssertEqual(text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " "), expected)
        }
    }

    func testRetentionRestartReplayAndDayTotals() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 20, hour: 12)))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let file = directory.appendingPathComponent("history.json")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = RestHistory(file: file, now: now, calendar: calendar)
        for offset in [-30, -29, -7] {
            let date = try XCTUnwrap(calendar.date(byAdding: .day, value: offset, to: now))
            store.record(RestEvent(id: UUID(), date: date, source: .automatic))
        }
        for index in (0..<24).reversed() {
            let event = RestEvent(id: UUID(), date: now.addingTimeInterval(Double(index * 60)), source: index < 21 ? .manual : .skipped)
            store.record(event)
            store.record(event)
        }
        let snapshot = RestHistory(file: file, now: now, calendar: calendar)
        let day = try XCTUnwrap(snapshot.days(7).last)
        XCTAssertEqual(day.completed, 21)
        XCTAssertEqual(day.skipped, 3)
        XCTAssertEqual(day.events.map(\.date), day.events.map(\.date).sorted())
        XCTAssertEqual(snapshot.days(7).flatMap(\.events).count, 24)
        XCTAssertEqual(snapshot.days(30).flatMap(\.events).count, 26)
        snapshot.refresh(at: calendar.date(byAdding: .day, value: 1, to: now)!)
        XCTAssertEqual(snapshot.events.count, 25)
        let later = calendar.date(byAdding: .day, value: 31, to: now)!
        XCTAssertTrue(RestHistory(file: file, now: later, calendar: calendar).events.isEmpty)
        XCTAssertEqual(try JSONDecoder().decode([RestEvent].self, from: Data(contentsOf: file)), [])
    }

    func testMonthWith24EventsCanScrollToLastRow() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let calendar = Calendar.current
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 24, hour: 8))!
        let history = RestHistory(file: directory.appendingPathComponent("history.json"), now: now)
        let standard = RestHistory(file: directory.appendingPathComponent("standard.json"), now: now)
        // Mirror the approved many-records artboard, including its historical selection.
        let start = calendar.startOfDay(for: calendar.date(byAdding: .day, value: -29, to: now)!)
        let selected = calendar.date(byAdding: .day, value: 15, to: start)!
        let counts = [3,5,2,4,5,0,0,3,2,6,4,3,0,1,4,3,5,2,4,0,0,4,6,3,5,0,0,2,5,3]
        let times = [582,638,686,850,937,988]
        let sources: [RestSource] = [.countdown, .automatic, .manual]
        for (index, count) in counts.enumerated() {
            let day = calendar.date(byAdding: .day, value: index, to: start)!
            func append(_ minute: Int, _ source: RestSource) {
                let date = calendar.date(byAdding: .minute, value: minute, to: day)!
                history.record(RestEvent(id: UUID(), date: date, source: source))
            }
            for row in 0..<count {
                let date = calendar.date(byAdding: .minute, value: times[row], to: day)!
                standard.record(RestEvent(id: UUID(), date: date, source: sources[(row + index + 1) % 3]))
            }
            for minute in [3,9,15,24].contains(index) ? [825] : [20,25].contains(index) ? [675, 920] : [] {
                let date = calendar.date(byAdding: .minute, value: minute, to: day)!
                standard.record(RestEvent(id: UUID(), date: date, source: .skipped))
            }
            if index == 15 {
                for row in 0..<24 {
                    append(515 + 29 * row + row / 2, [5,12,19].contains(row) ? .skipped : sources[row % 3])
                }
            } else {
                for row in 0..<count { append(times[row], sources[(row + index + 1) % 3]) }
                if [3,9,24].contains(index) { append(825, .skipped) }
                if [20,25].contains(index) { append(675, .skipped); append(920, .skipped) }
            }
        }
        func screen(_ selection: Date, scheme: ColorScheme, range: Int = 30) -> AnyView {
            AnyView(RestHistoryScreen(range: range, selection: selection)
                .environmentObject(selection == selected ? history : standard).environment(\.colorScheme, scheme).id("\(selection.timeIntervalSince1970)-\(scheme)-\(range)"))
        }
        let host = NSHostingView(rootView: screen(selected, scheme: .light))
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 864, height: 740),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFront(nil)
        defer { window.orderOut(nil); window.contentView = nil; window.close() }
        try await Task.sleep(for: .milliseconds(600))
        func scrollViews(in view: NSView) -> [NSScrollView] {
            (view as? NSScrollView).map { [$0] } ?? view.subviews.flatMap { scrollViews(in: $0) }
        }
        func pointerArea(in view: NSView) -> RestHistoryTrackingView? {
            if let area = view as? RestHistoryTrackingView, area.bounds.height > 44 { return area }
            return view.subviews.lazy.compactMap { pointerArea(in: $0) }.first
        }
        // A tracking area created beneath a stationary pointer must wait for actual movement.
        func cellTracker(in view: NSView) -> RestHistoryTrackingView? {
            if let area = view as? RestHistoryTrackingView, area.bounds.height <= 44 { return area }
            return view.subviews.lazy.compactMap { cellTracker(in: $0) }.first
        }
        let cell = try XCTUnwrap(cellTracker(in: host))
        let original = cell.changed
        var positions: [UnitPoint?] = []
        cell.changed = { positions.append($0) }
        let center = cell.convert(CGPoint(x: cell.bounds.midX, y: cell.bounds.midY), to: nil)
        let movement = try XCTUnwrap(NSEvent.mouseEvent(with: .mouseMoved, location: center, modifierFlags: [],
            timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 0, pressure: 0))
        cell.mouseEntered(with: movement)
        XCTAssertTrue(positions.isEmpty)
        cell.mouseMoved(with: movement)
        XCTAssertEqual(positions.compactMap { $0 }.last, .center)
        cell.mouseExited(with: movement)
        XCTAssertEqual(positions.count, 2)
        XCTAssertNil(positions.last ?? nil)
        let outside = cell.convert(CGPoint(x: -30, y: -30), to: nil)
        let outsideMove = try XCTUnwrap(NSEvent.mouseEvent(with: .mouseMoved, location: outside, modifierFlags: [],
            timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 0, pressure: 0))
        cell.mouseMoved(with: outsideMove)
        XCTAssertNil(positions.last ?? nil)
        cell.changed = original
        let area = try XCTUnwrap(pointerArea(in: host))
        XCTAssertTrue(area.trackingAreas.contains { $0.options.contains(.mouseMoved) })
        XCTAssertNil(area.hitTest(CGPoint(x: 10, y: 10)))
        let point = area.convert(CGPoint(x: area.bounds.width * 0.87, y: area.bounds.height * 0.78), to: nil)
        let move = try XCTUnwrap(NSEvent.mouseEvent(with: .mouseMoved, location: point, modifierFlags: [], timestamp: 0,
                                                   windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 0, pressure: 0))
        area.mouseMoved(with: move)
        try await Task.sleep(for: .milliseconds(250))
        func captureComposited(_ name: String) async throws {
            guard let destination = ProcessInfo.processInfo.environment["BREATHER_HISTORY_EVIDENCE"] else { return }
            // A layer cache flattens 3D transforms incorrectly. Sample the composited test window.
            let windows = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
            let target = try XCTUnwrap(windows.windows.first { $0.windowID == CGWindowID(window.windowNumber) })
            let config = SCStreamConfiguration()
            config.width = Int(target.frame.width)
            config.height = Int(target.frame.height)
            config.showsCursor = false
            let image = try await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(desktopIndependentWindow: target),
                                                                    configuration: config)
            try XCTUnwrap(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
                .write(to: URL(fileURLWithPath: destination).appendingPathComponent(name + ".png"))
        }
        try await captureComposited("card-hover")
        let scroll = try XCTUnwrap(scrollViews(in: host).first)
        XCTAssertFalse(scroll.hasVerticalScroller)
        XCTAssertEqual(scroll.contentView.bounds.height, 4.5 * 30, accuracy: 0.5)
        let cardLayer = try XCTUnwrap(sequence(first: try XCTUnwrap(scroll.layer), next: { $0.superlayer })
            .prefix(while: { $0 !== host.layer }).first { $0.transform.m34 != 0 })
        let hoveredTransform = cardLayer.transform
        let document = try XCTUnwrap(scroll.documentView)
        let last = document.bounds.height - scroll.contentView.bounds.height
        XCTAssertGreaterThan(last, 0)
        // Deliver the wheel event to the view under the pointer while the card is tilted.
        let wheel = try XCTUnwrap(CGEvent(scrollWheelEvent2Source: nil, units: .pixel,
                                          wheelCount: 1, wheel1: -90, wheel2: 0, wheel3: 0))
        let screenPoint = window.convertPoint(toScreen: point)
        wheel.location = CGPoint(x: screenPoint.x, y: try XCTUnwrap(NSScreen.screens.first).frame.maxY - screenPoint.y)
        let target = try XCTUnwrap(host.hitTest(host.superview?.convert(point, from: nil) ?? point))
        target.scrollWheel(with: try XCTUnwrap(NSEvent(cgEvent: wheel)))
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertGreaterThan(scroll.contentView.bounds.minY, 0)
        XCTAssertTrue(CATransform3DEqualToTransform(cardLayer.transform, hoveredTransform))
        try await captureComposited("card-hover-scrolled")
        area.mouseExited(with: move)
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertTrue(CATransform3DIsIdentity(cardLayer.transform))
        try await captureComposited("card-exit-scrolled")
        scroll.contentView.scroll(to: .zero)
        scroll.reflectScrolledClipView(scroll.contentView)
        try captureHistoryWindow(host, named: "calendar-top")
        scroll.contentView.scroll(to: CGPoint(x: 0, y: last))
        scroll.reflectScrolledClipView(scroll.contentView)
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(scroll.contentView.bounds.minY, last, accuracy: 1)
        try captureHistoryWindow(host, named: "calendar-bottom")
        func clickDay(_ point: CGPoint) throws {
            let location = host.convert(point, to: nil)
            func event(_ type: NSEvent.EventType, _ number: Int) throws -> NSEvent {
                try XCTUnwrap(NSEvent.mouseEvent(with: type, location: location, modifierFlags: [], timestamp: 0,
                    windowNumber: window.windowNumber, context: nil, eventNumber: number, clickCount: 1,
                    pressure: type == .leftMouseDown ? 1 : 0))
            }
            let up = try event(.leftMouseUp, 2)
            NSApp.postEvent(up, atStart: true)
            window.sendEvent(try event(.leftMouseDown, 1))
            window.sendEvent(up)
        }
        // Second column of the fixed Nov 2026 fixture: Nov 24, then Nov 10.
        window.makeKeyAndOrderFront(nil)
        try clickDay(CGPoint(x: 205, y: 345))
        try await Task.sleep(for: .milliseconds(600))
        XCTAssertLessThan(try XCTUnwrap(scrollViews(in: host).first?.documentView).bounds.height, 140)
        try clickDay(CGPoint(x: 205, y: 250))
        try await Task.sleep(for: .milliseconds(600))
        XCTAssertEqual(try XCTUnwrap(scrollViews(in: host).first).contentView.bounds.minY, 0, accuracy: 1)
        if ProcessInfo.processInfo.environment["BREATHER_HISTORY_EVIDENCE"] != nil {
            for (name, date, scheme, range) in [
                ("calendar-mixed-dark", selected, ColorScheme.dark, 30),
                ("calendar-clean", history.today, .light, 30),
                ("calendar-clean-dark", history.today, .dark, 30),
                ("week", history.today, .light, 7),
                ("week-dark", history.today, .dark, 7)
            ] {
                host.rootView = screen(date, scheme: scheme, range: range)
                try await Task.sleep(for: .milliseconds(200))
                try captureHistoryWindow(host, named: name)
                if name == "calendar-clean" || name == "calendar-clean-dark" {
                    let tracking = try XCTUnwrap(pointerArea(in: host))
                    let spot = tracking.convert(CGPoint(x: tracking.bounds.width * 0.8, y: tracking.bounds.height * 0.25), to: nil)
                    let hover = try XCTUnwrap(NSEvent.mouseEvent(with: .mouseMoved, location: spot, modifierFlags: [],
                        timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 0, pressure: 0))
                    tracking.mouseMoved(with: hover)
                    try await Task.sleep(for: .milliseconds(250))
                    try await captureComposited(name + "-hover")
                    tracking.mouseExited(with: hover)
                    try await Task.sleep(for: .milliseconds(250))
                    try captureHistoryWindow(host, named: name + "-exit")
                }
            }
        }


    }

    func testNarrowSixRowCalendarKeepsListVisibleInAllLanguages() async throws {
        let defaults = UserDefaults.standard
        let previous = defaults.string(forKey: AppLanguage.preferenceKey)
        defer {
            if let previous { defaults.set(previous, forKey: AppLanguage.preferenceKey) }
            else { defaults.removeObject(forKey: AppLanguage.preferenceKey) }
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        // Nov 1 was a Sunday: a Monday-first grid needs a sixth row.
        let day = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 30, hour: 8))!
        let history = RestHistory(file: directory.appendingPathComponent("events.json"), now: day)
        for i in 0..<24 {
            history.record(RestEvent(id: UUID(), date: day.addingTimeInterval(Double(i * 60)),
                                     source: i < 21 ? .manual : .skipped))
        }
        let host = NSHostingView(rootView: AnyView(EmptyView()))
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 560, height: 530),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFront(nil)
        defer { window.orderOut(nil); window.contentView = nil; window.close() }
        func findScroll(in view: NSView) -> NSScrollView? {
            if let scroll = view as? NSScrollView { return scroll }
            return view.subviews.lazy.compactMap { findScroll(in: $0) }.first
        }
        for language in [AppLanguage.simplifiedChinese, .traditionalChinese, .english] {
            defaults.set(language.rawValue, forKey: AppLanguage.preferenceKey)
            host.rootView = AnyView(RestHistoryScreen(range: 30).environmentObject(history).id(language))
            try await Task.sleep(for: .milliseconds(180))
            let scroll = try XCTUnwrap(findScroll(in: host))
            let visible = host.bounds.intersection(scroll.convert(scroll.bounds, to: host))
            XCTAssertGreaterThanOrEqual(visible.height, 29, "\(language.rawValue) host \(host.bounds) list \(scroll.convert(scroll.bounds, to: host))")
            XCTAssertGreaterThan(try XCTUnwrap(scroll.documentView).bounds.height, visible.height)
        }

        // The wrapped English legend needs additional vertical room at 320 pt.
        // Scroll the page to its end and verify that the inner event list is reachable.
        window.setContentSize(NSSize(width: 320, height: 530))
        try await Task.sleep(for: .milliseconds(200))
        let page = try XCTUnwrap(findScroll(in: host))
        let pageDocument = try XCTUnwrap(page.documentView)
        let list = try XCTUnwrap(pageDocument.subviews.lazy.compactMap { findScroll(in: $0) }.first)
        let bottom = pageDocument.bounds.height - page.contentView.bounds.height
        XCTAssertGreaterThan(bottom, 0)
        page.contentView.scroll(to: CGPoint(x: 0, y: bottom))
        page.reflectScrolledClipView(page.contentView)
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertGreaterThanOrEqual(host.bounds.intersection(list.convert(list.bounds, to: host)).height, 30)

    }

    func testRecognizedDayCopyAndStateAcrossSources() {
        let date = Date()
        for sources: [RestSource] in [[.manual], [.automatic], [.automatic, .manual], [.countdown], [.manual, .skipped], [.skipped], []] {
            let day = RestDay(id: date, events: sources.map { RestEvent(id: UUID(), date: date, source: $0) })
            if sources.contains(.skipped) {
                XCTAssertFalse(day.clean)
                XCTAssertEqual(day.message(today: false).0, sources.count > 1 ? "Nice Move!" : "Busy Day!")
            } else if sources.isEmpty {
                XCTAssertFalse(day.clean)
                XCTAssertEqual(day.message(today: true).0, L.tr("今天还没有休息记录"))
            } else {
                XCTAssertTrue(day.clean)
                XCTAssertEqual(day.message(today: true).0, "Awesome! 🎉")
                if !sources.contains(.countdown) {
                    XCTAssertEqual(day.message(today: true).1, L.tr("今天也有好好休息，太厉害了吧！"))
                    XCTAssertEqual(day.message(today: false).1, L.tr("那天也有好好休息，太厉害了吧！"))
                }
            }
        }
    }

    func testDamagedLedgerSurvivesUntilRetry() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        let invalid = Data("incomplete".utf8)
        try invalid.write(to: file)
        let store = RestHistory(file: file)
        let event = RestEvent(id: UUID(), date: Date(), source: .countdown)
        store.record(event)
        XCTAssertTrue(store.unavailable)
        XCTAssertEqual(try Data(contentsOf: file), invalid)
        try Data("[]".utf8).write(to: file)
        store.retry()
        XCTAssertFalse(store.unavailable)
        XCTAssertEqual(store.events, [event])
    }
}

@MainActor
func captureHistoryWindow(_ view: NSView, named name: String) throws {
    guard let destination = ProcessInfo.processInfo.environment["BREATHER_HISTORY_EVIDENCE"] else { return }
    view.layoutSubtreeIfNeeded()
    let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
    view.cacheDisplay(in: view.bounds, to: bitmap)
    let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
    try png.write(to: URL(fileURLWithPath: destination).appendingPathComponent(name + ".png"))
}

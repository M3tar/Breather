import AppKit
import SwiftUI
import XCTest
@testable import Breather

@MainActor
final class SettingsNumericInputInteractionTests: XCTestCase {
    func testPastedNonIntegerInputDoesNotChangeTheSavedValue() throws {
        let harness = try makeHarness(value: 90, range: 0...1800)
        defer { close(harness.window) }
        for text in ["60.5", "-120", "+120", "6e2", "60 sec", "6 0", "", "99999999999999999999999999"] {
            let editor = try beginEditing(harness.textField, in: harness.window)
            editor.selectAll(nil)
            editor.insertText(text, replacementRange: editor.selectedRange())
            XCTAssertEqual(harness.textField.stringValue, text, "Do not silently rewrite the edit")
            XCTAssertEqual(harness.valueBox.value, 90)
            harness.window.makeFirstResponder(nil)
            XCTAssertEqual(harness.textField.stringValue, "90", text)
            XCTAssertEqual(harness.valueBox.value, 90, text)
            XCTAssertEqual(harness.valueBox.writeCount, 0, "Reject invalid edits before calling the binding")
        }
    }

    func testCorrectedEditAndWholeIntegerRangeLimitsCommitNormally() throws {
        let harness = try makeHarness(value: 90, minimum: 60, range: 0...1800)
        defer { close(harness.window) }
        let editor = try beginEditing(harness.textField, in: harness.window)
        editor.selectAll(nil)
        editor.insertText("60.5", replacementRange: editor.selectedRange())
        editor.selectAll(nil)
        editor.insertText("75", replacementRange: editor.selectedRange())
        harness.window.makeFirstResponder(nil)
        XCTAssertEqual(harness.valueBox.value, 75)
        for (text, expected) in [(" 90\n", 90), ("00060", 60), ("0", 60), ("45", 60), ("1800", 1800), ("1801", 1800)] {
            let editor = try beginEditing(harness.textField, in: harness.window)
            editor.selectAll(nil)
            editor.insertText(text, replacementRange: editor.selectedRange())
            harness.window.makeFirstResponder(nil)
            XCTAssertEqual(harness.valueBox.value, expected, text)
            XCTAssertEqual(harness.textField.stringValue, "\(expected)", text)
        }
    }

    func testReturnRejectsNegativeInputWithoutCommitting() throws {
        let harness = try makeHarness(value: 90, range: 0...1800)
        defer { close(harness.window) }
        let editor = try beginEditing(harness.textField, in: harness.window)
        editor.selectAll(nil)
        editor.insertText("-120", replacementRange: editor.selectedRange())
        XCTAssertEqual(harness.textField.delegate?.control?(harness.textField, textView: editor,
            doCommandBy: #selector(NSResponder.insertNewline(_:))), true)
        XCTAssertEqual(harness.textField.stringValue, "90")
        XCTAssertEqual(harness.valueBox.value, 90)
        XCTAssertEqual(harness.valueBox.writeCount, 0)
    }

    func testReturnCommitsTheClampedValueOnlyOnce() throws {
        let harness = try makeHarness(value: 120, minimum: 60)
        defer { close(harness.window) }
        let editor = try beginEditing(harness.textField, in: harness.window)
        harness.textField.stringValue = "45"
        let handled = harness.textField.delegate?.control?(harness.textField, textView: editor,
            doCommandBy: #selector(NSResponder.insertNewline(_:)))
        XCTAssertEqual(handled, true)
        XCTAssertNil(harness.textField.currentEditor())
        XCTAssertEqual(harness.valueBox.value, 60)
        XCTAssertEqual(harness.textField.stringValue, "60")
        XCTAssertEqual(harness.valueBox.writeCount, 1)
    }

    func testCommitDisplaysTheValueAcceptedByTheBinding() throws {
        let harness = try makeHarness(value: 120, minimum: 60)
        defer { close(harness.window) }
        _ = try beginEditing(harness.textField, in: harness.window)
        harness.textField.stringValue = "45"
        harness.window.makeFirstResponder(nil)
        XCTAssertEqual(harness.valueBox.value, 60)
        XCTAssertEqual(harness.textField.stringValue, "60")
    }

    func testEmptyAndOversizedInputKeepAValidValue() throws {
        let harness = try makeHarness(value: 45)
        defer { close(harness.window) }
        for input in ["", "99999999999999999999999999"] {
            _ = try beginEditing(harness.textField, in: harness.window)
            harness.textField.stringValue = input
            harness.window.makeFirstResponder(nil)
            XCTAssertEqual(harness.valueBox.value, 45)
            XCTAssertEqual(harness.textField.stringValue, "45")
        }
    }

    func testCommandASelectsTheEntireNumericValue() throws {
        let harness = try makeHarness(value: 120)
        defer { close(harness.window) }

        let editor = try beginEditing(harness.textField, in: harness.window)
        editor.setSelectedRange(NSRange(location: 1, length: 0))

        let event = try XCTUnwrap(
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: .command,
                timestamp: 0,
                windowNumber: harness.window.windowNumber,
                context: nil,
                characters: "a",
                charactersIgnoringModifiers: "a",
                isARepeat: false,
                keyCode: 0
            )
        )
        XCTAssertTrue(harness.textField.performKeyEquivalent(with: event))

        XCTAssertEqual(editor.selectedRange(), NSRange(location: 0, length: 3))
        editor.insertText("45", replacementRange: editor.selectedRange())
        XCTAssertEqual(harness.textField.stringValue, "45")
        XCTAssertEqual(harness.valueBox.value, 120)

        harness.window.makeFirstResponder(nil)
        XCTAssertEqual(harness.valueBox.value, 45)
    }

    func testClickingBlankSettingsAreaEndsNumericEditing() throws {
        let harness = try makeHarness(value: 120)
        defer { close(harness.window) }

        _ = try beginEditing(harness.textField, in: harness.window)
        XCTAssertNotNil(harness.textField.currentEditor())

        let insideEvent = try makeMouseDown(
            at: harness.textField.convert(
                NSPoint(x: harness.textField.bounds.midX, y: harness.textField.bounds.midY),
                to: nil
            ),
            in: harness.window
        )
        let numericTextField = try XCTUnwrap(harness.textField as? SelectAllNumericTextField)
        numericTextField.handleMouseDown(insideEvent)
        XCTAssertNotNil(harness.textField.currentEditor())

        harness.textField.stringValue = "999"
        let event = try XCTUnwrap(
            NSEvent.mouseEvent(
                with: .leftMouseDown,
                location: NSPoint(x: 220, y: 80),
                modifierFlags: [],
                timestamp: 0,
                windowNumber: harness.window.windowNumber,
                context: nil,
                eventNumber: 1,
                clickCount: 1,
                pressure: 1
            )
        )
        XCTAssertEqual(event.windowNumber, harness.window.windowNumber)
        XCTAssertFalse(
            harness.textField.bounds.contains(
                harness.textField.convert(event.locationInWindow, from: nil)
            )
        )
        NSApp.sendEvent(event)

        XCTAssertNil(harness.textField.currentEditor())
        XCTAssertEqual(harness.textField.stringValue, "180")
        XCTAssertEqual(harness.valueBox.value, 180)
    }

    private func makeHarness(value: Int, minimum: Int = 1, range: ClosedRange<Int> = 1...180) throws -> (
        window: NSWindow,
        hostingView: NSHostingView<AnyView>,
        textField: NSTextField,
        valueBox: ValueBox
    ) {
        let valueBox = ValueBox(value)
        let hostingView = NSHostingView(
            rootView: AnyView(
                ZStack(alignment: .topLeading) {
                    Color.clear
                    DurationStepper(
                        value: Binding(
                            get: { valueBox.value },
                            set: { valueBox.writeCount += 1; valueBox.value = max(minimum, $0) }
                        ),
                        range: range,
                        unit: "分钟"
                    )
                    .padding(16)
                }
                .frame(width: 280, height: 120)
            )
        )
        hostingView.frame = NSRect(x: 0, y: 0, width: 280, height: 120)

        let window = NSWindow(
            contentRect: hostingView.frame,
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.makeKeyAndOrderFront(nil)
        hostingView.layoutSubtreeIfNeeded()

        let textField = try XCTUnwrap(firstTextField(in: hostingView))
        return (window, hostingView, textField, valueBox)
    }

    private func makeMouseDown(at location: NSPoint, in window: NSWindow) throws -> NSEvent {
        try XCTUnwrap(
            NSEvent.mouseEvent(
                with: .leftMouseDown,
                location: location,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: window.windowNumber,
                context: nil,
                eventNumber: 1,
                clickCount: 1,
                pressure: 1
            )
        )
    }

    private func beginEditing(_ textField: NSTextField, in window: NSWindow) throws -> NSTextView {
        XCTAssertTrue(window.makeFirstResponder(textField))
        return try XCTUnwrap(textField.currentEditor() as? NSTextView)
    }

    private func close(_ window: NSWindow) {
        window.makeFirstResponder(nil)
        window.orderOut(nil)
    }

    private func firstTextField(in view: NSView) -> NSTextField? {
        if let textField = view as? NSTextField {
            return textField
        }
        for subview in view.subviews {
            if let textField = firstTextField(in: subview) {
                return textField
            }
        }
        return nil
    }

    private final class ValueBox {
        var value: Int
        var writeCount = 0

        init(_ value: Int) {
            self.value = value
        }
    }
}

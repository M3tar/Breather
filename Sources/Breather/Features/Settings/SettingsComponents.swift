import AppKit
import SwiftUI

enum SettingsWindowMetrics {
    static let minimumSize = CGSize(width: 760, height: 560)
    static let defaultSize = CGSize(width: 1080, height: 720)
    static let contentMaxWidth: CGFloat = 840
}

enum SettingsFooterMetrics {
    static let height: CGFloat = 40
}

struct SettingsScreenContainer<Content: View>: View {
    @ViewBuilder let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                content
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
            .frame(maxWidth: SettingsWindowMetrics.contentMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .scrollDismissesKeyboard(.immediately)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

struct SettingsGroup<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)

            GroupBox {
                VStack(spacing: 0) {
                    content
                }
                .padding(.vertical, 2)
            }
            .groupBoxStyle(.automatic)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SettingsRow<Control: View>: View {
    let title: String
    let description: String?
    @ViewBuilder let control: Control

    init(
        title: String,
        description: String? = nil,
        @ViewBuilder control: () -> Control
    ) {
        self.title = title
        self.description = description
        self.control = control()
    }

    var body: some View {
        SettingsRowLayout {
            label
            control
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.leading, 14)
        .padding(.trailing, 14)
        .padding(.vertical, 10)
    }

    private var label: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.body)

            if let description {
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Reposition the same label and control when a row needs to wrap. Duplicating
/// them in ViewThatFits would recreate native controls when the selection grows.
private struct SettingsRowLayout: Layout {
    private let horizontalSpacing: CGFloat = 38
    private let verticalSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = measure(width: proposal.width, subviews: subviews)
        return CGSize(width: sizes.width, height: sizes.stacked
            ? sizes.label.height + verticalSpacing + sizes.control.height
            : max(sizes.label.height, sizes.control.height))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let sizes = measure(width: bounds.width, subviews: subviews)
        let labelY = sizes.stacked ? bounds.minY : bounds.midY - sizes.label.height / 2
        let controlY = sizes.stacked
            ? bounds.minY + sizes.label.height + verticalSpacing
            : bounds.midY - sizes.control.height / 2
        subviews[0].place(at: CGPoint(x: bounds.minX, y: labelY), anchor: .topLeading,
                          proposal: ProposedViewSize(sizes.label))
        subviews[1].place(at: CGPoint(x: bounds.maxX - sizes.control.width, y: controlY), anchor: .topLeading,
                          proposal: ProposedViewSize(sizes.control))
    }

    private func measure(width: CGFloat?, subviews: Subviews) -> (width: CGFloat, label: CGSize, control: CGSize, stacked: Bool) {
        let labelIdeal = subviews[0].sizeThatFits(.unspecified)
        let control = subviews[1].sizeThatFits(.unspecified)
        let idealWidth = labelIdeal.width + horizontalSpacing + control.width
        let available = width.flatMap { $0.isFinite ? $0 : nil } ?? idealWidth
        let stacked = available < idealWidth
        let labelWidth = stacked ? available : max(0, available - horizontalSpacing - control.width)
        let label = subviews[0].sizeThatFits(ProposedViewSize(width: labelWidth, height: nil))
        return (available, label, control, stacked)
    }
}

struct SettingsDivider: View {
    var body: some View {
        Divider()
            .padding(.leading, 14)
            .padding(.trailing, 14)
    }
}

struct SettingsSwitch: View {
    let title: String
    @Binding var isOn: Bool

    init(_ title: String, isOn: Binding<Bool>) {
        self.title = title
        _isOn = isOn
    }

    var body: some View {
        Toggle(title, isOn: $isOn)
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
    }
}

struct SoundEffectControl: View {
    @Binding var selection: RestSoundEffect
    let onPreview: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            SettingsMenuPicker(L.tr("提示音"), selection: $selection, options:
                RestSoundEffect.fixedCases.map { SettingsMenuOption(value: $0, title: $0.title) }
                + [SettingsMenuOption(value: .random, title: RestSoundEffect.random.title, separatorBefore: true),
                   SettingsMenuOption(value: .none, title: RestSoundEffect.none.title)]
            )
            .fixedSize()

            Button(action: onPreview) {
                Image(systemName: "play.circle")
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .disabled(selection == .none)
            .help(L.tr("播放提示音"))
            .accessibilityLabel(L.tr("播放提示音"))
        }
    }
}

struct DurationStepper: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    let unit: String

    var body: some View {
        HStack(spacing: 6) {
            NumericTextField(value: $value, range: range)
                .frame(minWidth: 48, idealWidth: 54, minHeight: 22)

            Text(unit)
                .foregroundStyle(.secondary)
                .fixedSize()

            NativeStepper(value: $value, range: range)
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}

private struct NativeStepper: NSViewRepresentable {
    @Binding var value: Int
    let range: ClosedRange<Int>

    func makeNSView(context: Context) -> EditingAwareStepper {
        let stepper = EditingAwareStepper()
        stepper.minValue = Double(range.lowerBound)
        stepper.maxValue = Double(range.upperBound)
        stepper.increment = 1
        stepper.intValue = Int32(value)
        stepper.controlSize = .small
        stepper.target = context.coordinator
        stepper.action = #selector(Coordinator.valueChanged(_:))
        return stepper
    }

    func updateNSView(_ stepper: EditingAwareStepper, context: Context) {
        context.coordinator.parent = self
        stepper.minValue = Double(range.lowerBound)
        stepper.maxValue = Double(range.upperBound)
        stepper.intValue = Int32(value)
        stepper.isEnabled = range.lowerBound < range.upperBound
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    @MainActor
    final class Coordinator: NSObject {
        var parent: NativeStepper

        init(parent: NativeStepper) {
            self.parent = parent
        }

        @objc func valueChanged(_ sender: NSStepper) {
            parent.value = Int(sender.intValue)
        }
    }

    final class EditingAwareStepper: NSStepper {
        override func mouseDown(with event: NSEvent) {
            window?.makeFirstResponder(nil)
            super.mouseDown(with: event)
        }
    }
}

private struct NumericTextField: NSViewRepresentable {
    @Binding var value: Int
    let range: ClosedRange<Int>

    func makeNSView(context: Context) -> NSTextField {
        let textField = SelectAllNumericTextField()
        textField.delegate = context.coordinator
        textField.alignment = .right
        textField.bezelStyle = .roundedBezel
        textField.controlSize = .small
        textField.font = .monospacedDigitSystemFont(
            ofSize: NSFont.smallSystemFontSize,
            weight: .regular
        )
        textField.stringValue = "\(value)"
        return textField
    }

    func updateNSView(_ textField: NSTextField, context: Context) {
        context.coordinator.parent = self
        guard textField.currentEditor() == nil else {
            return
        }
        textField.stringValue = "\(value)"
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    static func dismantleNSView(_ textField: NSTextField, coordinator: Coordinator) {
        (textField as? SelectAllNumericTextField)?.stopMonitoringExternalClicks()
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: NumericTextField

        init(parent: NumericTextField) {
            self.parent = parent
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let textField = notification.object as? NSTextField else {
                return
            }

            let digitsOnly = textField.stringValue.filter(\.isNumber)
            if digitsOnly != textField.stringValue {
                textField.stringValue = digitsOnly
            }
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            guard let textField = notification.object as? NSTextField else {
                return
            }
            commit(textField)
        }

        func control(
            _ control: NSControl,
            textView: NSTextView,
            doCommandBy commandSelector: Selector
        ) -> Bool {
            guard commandSelector == #selector(NSResponder.insertNewline(_:)),
                  let textField = control as? NSTextField else {
                return false
            }

            commit(textField)
            textField.window?.makeFirstResponder(nil)
            return true
        }

        private func commit(_ textField: NSTextField) {
            guard let parsedValue = Int(textField.stringValue) else {
                textField.stringValue = "\(parent.value)"
                return
            }

            let committedValue = clamped(parsedValue)
            parent.value = committedValue
            textField.stringValue = "\(committedValue)"
        }

        private func clamped(_ input: Int) -> Int {
            min(max(input, parent.range.lowerBound), parent.range.upperBound)
        }
    }
}

final class SelectAllNumericTextField: NSTextField {
    private var externalClickMonitor: Any?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        if event.type == .keyDown,
           modifiers == .command,
           event.charactersIgnoringModifiers?.lowercased() == "a",
           let editor = currentEditor() {
            editor.selectAll(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func becomeFirstResponder() -> Bool {
        let didBecomeFirstResponder = super.becomeFirstResponder()
        if didBecomeFirstResponder {
            startMonitoringExternalClicks()
        }
        return didBecomeFirstResponder
    }

    override func textDidEndEditing(_ notification: Notification) {
        stopMonitoringExternalClicks()
        super.textDidEndEditing(notification)
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil {
            stopMonitoringExternalClicks()
        }
        super.viewWillMove(toWindow: newWindow)
    }

    private func startMonitoringExternalClicks() {
        stopMonitoringExternalClicks()
        externalClickMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] event in
            self?.handleMouseDown(event) ?? event
        }
    }

    @discardableResult
    func handleMouseDown(_ event: NSEvent) -> NSEvent {
        guard let window,
              event.windowNumber == window.windowNumber else {
            return event
        }

        let locationInField = convert(event.locationInWindow, from: nil)
        guard !bounds.contains(locationInField) else {
            return event
        }

        window.makeFirstResponder(nil)
        return event
    }

    func stopMonitoringExternalClicks() {
        if let externalClickMonitor {
            NSEvent.removeMonitor(externalClickMonitor)
            self.externalClickMonitor = nil
        }
    }
}

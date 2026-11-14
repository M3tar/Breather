import AppKit
import SwiftUI

struct DiagnosticsSettingsGroup: View {
    @ObservedObject var controller: DiagnosticsController
    var onFeedback: (SettingsToastMessage?) -> Void = { _ in }
    @State private var confirmsClear = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsRowLayout {
                HStack(spacing: 12) {
                    Image(systemName: "doc.text")
                        .frame(width: 18)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    HStack(alignment: .firstTextBaseline, spacing: SettingsRowMetrics.helpIconSpacing) {
                        Text(L.tr("运行日志"))
                        SettingsHelp(message: L.tr("仅保存在本机，最多占用 20 MB。"), identifier: "runtime-log-help")
                            .frame(width: 18, height: 18)
                            .alignmentGuide(.firstTextBaseline) { dimensions in
                                dimensions.height / 2 + NSFont.systemFont(ofSize: NSFont.systemFontSize).capHeight / 2
                            }
                    }
                }
                HStack(spacing: 16) {
                    logActions
                    Toggle(L.tr("运行日志"), isOn: Binding(
                        get: { controller.isEnabled },
                        // AppKit can deliver the selection while SwiftUI is updating this view.
                        set: { enabled in Task { @MainActor in controller.setEnabled(enabled) } }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                }
                .fixedSize()
            }
            .disabled(controller.isExporting)
        }
        .onReceive(controller.$message.dropFirst(), perform: onFeedback)
        .onChange(of: controller.storageHasError) { _, hasError in
            if hasError { reportStorageError() }
        }
        .onAppear { if controller.storageHasError { reportStorageError() } }
        .onDisappear { controller.dismissMessage() }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .alert(L.tr("清除运行日志？"), isPresented: $confirmsClear) {
            Button(L.tr("取消"), role: .cancel) { }
            Button(L.tr("清除"), role: .destructive) { Task { await controller.clearLogs() } }
        } message: {
            Text(L.tr("将清除本机保存的运行日志，已导出的文件不受影响。"))
        }
    }

    private func reportStorageError() {
        onFeedback(SettingsToastMessage(text: L.tr("暂时无法记录日志，将自动重试。"), isError: true))
    }

    private var logActions: some View {
        HStack(spacing: 8) {
            if controller.isExporting { ProgressView().controlSize(.small) }
            Button(L.tr("导出…")) { Task { await controller.exportLogs() } }
                .accessibilityLabel(L.tr("导出日志…"))
            Button(L.tr("清除…")) {
                controller.dismissMessage()
                confirmsClear = true
            }
                .accessibilityLabel(L.tr("清除日志…"))
        }
    }
}

// A native tracking area makes hover explicit, rather than relying on delayed tooltips.
struct SettingsHelp: NSViewRepresentable {
    let message: String
    var identifier = "settings-help"

    func makeNSView(context: Context) -> RuntimeLogHelpButton {
        let button = RuntimeLogHelpButton(message: message)
        button.setAccessibilityIdentifier(identifier)
        return button
    }

    func updateNSView(_ button: RuntimeLogHelpButton, context: Context) {
        button.updateMessage(message)
    }

    static func dismantleNSView(_ button: RuntimeLogHelpButton, coordinator: ()) {
        button.closeHelp()
    }
}

final class RuntimeLogHelpButton: NSButton {
    private(set) var message: String
    private(set) var helpPanel: RuntimeLogHelpPanel?
    private var hoverArea: NSTrackingArea?

    init(message: String) {
        self.message = message
        super.init(frame: .zero)
        title = ""
        isBordered = false
        imagePosition = .imageOnly
        image = NSImage(systemSymbolName: "questionmark.circle", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: NSFont.systemFontSize, weight: .regular))
        contentTintColor = .secondaryLabelColor
        setAccessibilityIdentifier("runtime-log-help")
        setAccessibilityLabel(message)
        target = self
        action = #selector(showHelp)
    }

    required init?(coder: NSCoder) { nil }

    func updateMessage(_ value: String) {
        guard value != message else { return }
        closeHelp()
        message = value
        setAccessibilityLabel(value)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: .zero,
            options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self)
        addTrackingArea(area)
        hoverArea = area
    }

    override func mouseEntered(with event: NSEvent) { showHelp() }
    override func mouseExited(with event: NSEvent) { closeHelp() }

    @objc func showHelp() {
        guard let parent = window, !isHiddenOrHasHiddenAncestor, helpPanel?.isVisible != true else { return }
        closeHelp()
        let font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        let textWidth = ceil((message as NSString).size(withAttributes: [.font: font]).width)
        let isDark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let content = NSHostingView(rootView: Text(message)
            .font(.system(size: font.pointSize, weight: .regular))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(width: min(textWidth, 296), alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background {
                RuntimeLogHelpMaterial()
                    .overlay(.white.opacity(isDark ? 0.04 : 0.72))
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(.white.opacity(isDark ? 0.12 : 0.75), lineWidth: 0.5)
            })
        let panel = RuntimeLogHelpPanel(contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = true
        panel.appearance = effectiveAppearance
        panel.ignoresMouseEvents = true
        panel.contentView = content
        let size = content.fittingSize
        let anchor = parent.convertToScreen(convert(bounds, to: nil))
        let screen = parent.screen?.visibleFrame ?? anchor.insetBy(dx: -500, dy: -500)
        let x = min(max(anchor.midX - size.width / 2, screen.minX + 8), screen.maxX - size.width - 8)
        let below = anchor.minY - size.height - 6
        let y = below >= screen.minY + 8 ? below : anchor.maxY + 6
        panel.setFrame(NSRect(origin: CGPoint(x: x, y: y), size: size), display: false)
        helpPanel = panel
        parent.addChildWindow(panel, ordered: .above)
        panel.orderFront(nil)
    }

    @objc func closeHelp() {
        guard let panel = helpPanel else { return }
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
        panel.close()
        helpPanel = nil
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        closeHelp()
        NotificationCenter.default.removeObserver(self)
        super.viewWillMove(toWindow: newWindow)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        for name in [NSWindow.willCloseNotification, NSWindow.didMiniaturizeNotification,
                     NSWindow.didResignKeyNotification] {
            NotificationCenter.default.addObserver(self, selector: #selector(closeHelp), name: name, object: window)
        }
    }

    override func viewDidHide() {
        super.viewDidHide()
        closeHelp()
    }
}

// Tooltip-style help must never take keyboard focus from the settings window.
final class RuntimeLogHelpPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

// Blur the parent window behind this separate, nonactivating help panel.
// AppKit adapts the popover material to appearance and Reduce Transparency.
private struct RuntimeLogHelpMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

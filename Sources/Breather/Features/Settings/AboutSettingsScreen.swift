import AppKit
import SwiftUI

struct AboutSettingsScreen: View {
    @ObservedObject var updateMonitor: UpdateMonitor
    var diagnostics: DiagnosticsController? = nil
    @StateObject private var feedback = SettingsToastPresenter()
    @Environment(\.openURL) private var openURL

    private let repositoryURL = URL(string: "https://github.com/M3tar/Breather")!
    private let feedbackURL = URL(
        string: "mailto:1191527614@qq.com?subject=Breather%20%E5%8F%8D%E9%A6%88"
    )!
    private let githubFeedbackURL = URL(
        string: "https://github.com/M3tar/Breather/issues/new"
    )!

    var body: some View {
        SettingsScreenContainer {
            VStack(spacing: 8) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 80, height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
                    .accessibilityHidden(true)

                Text("Breather")
                    .font(.title2.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 4)
            .padding(.bottom, 16)

            versionAndUpdateGroup

            feedbackGroup

            SettingsGroup(L.tr("支持项目")) {
                AboutActionRow(
                    title: L.tr("在 GitHub 点星标"),
                    systemImage: "star",
                    destination: repositoryURL
                )
            }
        }
        .overlay {
            GeometryReader { geometry in
                // Match the leading-aligned, capped content column, not the viewport edge.
                let contentWidth = min(geometry.size.width, SettingsWindowMetrics.contentMaxWidth)
                let edgeInset = SettingsWindowMetrics.contentHorizontalPadding
                SettingsToastOverlay(presenter: feedback)
                    .frame(maxWidth: min(340, max(0, (contentWidth - 80) / 2 - edgeInset - 16)), alignment: .trailing)
                    .padding(.trailing, edgeInset)
                    .padding(.top, 22)
                    .frame(width: contentWidth, alignment: .trailing)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .background {
            SettingsFeedbackWindowObserver(onLeave: {
                feedback.disappear()
                diagnostics?.dismissMessage()
            }, onReturn: feedback.appear)
                .frame(width: 0, height: 0)
        }
        .onReceive(updateMonitor.$status.dropFirst()) { feedback.receive($0) }
        .onAppear {
            feedback.appear()
            Task { await updateMonitor.checkIfDue() }
        }
        .onDisappear { feedback.disappear() }
    }

    private var versionAndUpdateGroup: some View {
        GroupBox {
            VStack(spacing: 0) {
                SettingsRow(title: L.tr("版本")) {
                    Text(versionDescription)
                        .foregroundStyle(.secondary)
                }

                SettingsDivider()

                SettingsRow(title: L.tr("检查更新"), description: updateMonitor.availableUpdate.map { UpdateStatus.available($0).message }) {
                    HStack(spacing: 8) {
                        if updateMonitor.status.isChecking {
                            ProgressView()
                                .controlSize(.small)
                                .accessibilityLabel(L.tr("正在检查更新"))
                        }

                        Button(updateMonitor.availableUpdate == nil ? L.tr("检查更新") : L.tr("重新检查")) {
                            Task { await updateMonitor.checkNow() }
                        }
                        .disabled(updateMonitor.status.isChecking)

                        if let update = updateMonitor.availableUpdate {
                            Button(L.tr("前往 GitHub 下载")) {
                                openURL(update.releaseURL)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.blue)
                        }
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .groupBoxStyle(.automatic)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var feedbackGroup: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(L.tr("反馈"))
                    .font(.headline)
                    .fixedSize()

                Text(L.tr("谢谢你下载 Breather！发现了 Bug、有特别想要的功能，或者只是想夸夸设计者？都欢迎告诉我。"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            GroupBox {
                VStack(spacing: 0) {
                    AboutActionRow(
                        title: L.tr("发送邮件反馈"),
                        systemImage: "envelope",
                        destination: feedbackURL
                    )

                    SettingsDivider()

                    AboutActionRow(
                        title: L.tr("在 GitHub 提交反馈"),
                        systemImage: "bubble.left",
                        destination: githubFeedbackURL
                    )

                    if let diagnostics {
                        SettingsDivider()
                        DiagnosticsSettingsGroup(controller: diagnostics, onFeedback: feedback.show)
                    }
                }
                .padding(.vertical, 2)
            }
            .groupBoxStyle(.automatic)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var versionDescription: String {
        let version = installedVersion
        let build = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleVersion"
        ) as? String

        guard !version.isEmpty else { return L.tr("开发版本") }
        guard let build, !build.isEmpty else { return version }
        return L.tr("\(version)（构建 \(build)）")
    }

    private var installedVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }
}

private struct AboutActionRow: View {
    let title: String
    let systemImage: String
    let destination: URL

    var body: some View {
        Link(destination: destination) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .frame(width: 18)
                    .foregroundStyle(.secondary)

                Text(title)

                Spacer(minLength: 12)

                Image(systemName: "arrow.up.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// One presentation lifetime for all action results on the About page.
struct SettingsToastMessage: Identifiable, Equatable {
    let id = UUID()
    let text: String
    var isError = false
}

@MainActor
final class SettingsToastPresenter: ObservableObject {
    @Published private(set) var message: SettingsToastMessage?
    private var isVisible = false
    private var acceptsUpdateResult = false
    private var isHovered = false
    private var dismissalTask: Task<Void, Never>?
    private var remaining: Duration?
    private var deadline: ContinuousClock.Instant?
    private let successDuration: Duration
    private let failureDuration: Duration
    private let now: () -> ContinuousClock.Instant

    init(successDuration: Duration = .seconds(3), failureDuration: Duration = .seconds(8),
         now: @escaping () -> ContinuousClock.Instant = { ContinuousClock().now }) {
        self.successDuration = successDuration
        self.failureDuration = failureDuration
        self.now = now
    }

    func appear() { isVisible = true }

    func show(_ result: SettingsToastMessage?) {
        guard isVisible else { return }
        guard let result else { dismiss(); return }
        dismissalTask?.cancel()
        dismissalTask = nil
        deadline = nil
        // Replace directly so a newer result does not blink through an empty state.
        message = result
        remaining = result.isError ? failureDuration : successDuration
        scheduleDismissal()
    }

    func setHovered(_ hovered: Bool) {
        guard isHovered != hovered else { return }
        isHovered = hovered
        if hovered {
            if let deadline { remaining = max(.zero, now().duration(to: deadline)) }
            dismissalTask?.cancel()
            dismissalTask = nil
            deadline = nil
        } else {
            scheduleDismissal()
        }
    }

    private func scheduleDismissal() {
        guard !isHovered, let id = message?.id, let remaining else { return }
        deadline = now().advanced(by: remaining)
        dismissalTask = Task { [weak self] in
            do { try await Task.sleep(for: remaining) } catch { return }
            guard !Task.isCancelled, let self, self.message?.id == id, !self.isHovered else { return }
            self.dismiss()
        }
    }

    func receive(_ status: UpdateStatus) {
        if case .checking = status {
            acceptsUpdateResult = isVisible
            show(nil)
            return
        }
        // Only a check observed during this visit may produce transient feedback.
        // Available releases remain visible through UpdateMonitor.availableUpdate.
        guard acceptsUpdateResult else { return }
        acceptsUpdateResult = false
        switch status {
        case .idle, .checking, .available: show(nil)
        case .upToDate: show(SettingsToastMessage(text: status.message))
        case .noDownload: show(SettingsToastMessage(text: status.message, isError: true))
        case let .failed(text): show(SettingsToastMessage(text: text, isError: true))
        }
    }

    func dismiss() {
        dismissalTask?.cancel()
        dismissalTask = nil
        remaining = nil
        deadline = nil
        isHovered = false
        message = nil
    }

    func disappear() {
        isVisible = false
        acceptsUpdateResult = false
        dismiss()
    }
}

// Keep all motion in the overlay; the settings rows never participate in its layout.
struct SettingsToastOverlay: View {
    @ObservedObject var presenter: SettingsToastPresenter
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .top) {
            if let message = presenter.message {
                SettingsToast(message: message, dismiss: presenter.dismiss)
                    .onHover(perform: presenter.setHovered)
                    .transition(reduceMotion ? .opacity : .asymmetric(
                        insertion: .offset(y: -12).combined(with: .scale(scale: 0.95, anchor: .top)).combined(with: .opacity),
                        removal: .offset(y: -12).combined(with: .scale(scale: 0.95, anchor: .top)).combined(with: .opacity)))
            }
        }
        .animation(reduceMotion ? .easeOut(duration: 0.15) : .spring(duration: presenter.message == nil ? 0.2 : 0.3, bounce: 0),
                   value: presenter.message?.id)
        .allowsHitTesting(presenter.message != nil)
    }
}

struct SettingsToast: View {
    @Environment(\.colorScheme) private var colorScheme
    private var palette: FeedbackPalette { FeedbackPalette(isDark: colorScheme == .dark) }
    let message: SettingsToastMessage
    let dismiss: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: message.isError ? "exclamationmark.circle" : "checkmark.circle.fill")
                .font(.system(size: 16, weight: .medium))
                .frame(width: 18, height: 20)
                .foregroundStyle(message.isError ? palette.failure : palette.success)
                .contentTransition(reduceMotion ? .opacity : .symbolEffect(.replace))
                .accessibilityHidden(true)
            Text(message.text)
                .font(.callout)
                .foregroundStyle(palette.text)
                .fixedSize(horizontal: false, vertical: true)
                .id(message.id)
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 4)))
            if message.isError {
                Button(action: dismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(palette.secondaryText)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(L.tr("关闭提示"))
                .accessibilityLabel(L.tr("关闭提示"))
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(palette.border, lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
        .accessibilityElement(children: .contain)
    }
}

// Radix Colors: Gray 2/6/11/12, Jade 11 and Tomato 11 (sRGB light/dark palettes).
// https://www.radix-ui.com/colors/docs/palette-composition/understanding-the-scale
private struct FeedbackPalette {
    let isDark: Bool
    var surface: Color { color(light: 0xF9F9F9, dark: 0x191919) }
    var border: Color { color(light: 0xD9D9D9, dark: 0x3A3A3A) }
    var text: Color { color(light: 0x202020, dark: 0xEEEEEE) }
    var secondaryText: Color { color(light: 0x646464, dark: 0xB4B4B4) }
    var success: Color { color(light: 0x208368, dark: 0x1FD8A4) }
    var failure: Color { color(light: 0xD13415, dark: 0xFF977D) }

    private func color(light: UInt32, dark: UInt32) -> Color {
        let value = isDark ? dark : light
        return Color(.sRGB, red: Double((value >> 16) & 0xff) / 255,
                     green: Double((value >> 8) & 0xff) / 255, blue: Double(value & 0xff) / 255)
    }
}

// SwiftUI can retain a settings page after its NSWindow closes. Observe the owning
// window only; save panels and confirmation sheets must not invalidate action results.
struct SettingsFeedbackWindowObserver: NSViewRepresentable {
    var onLeave: () -> Void
    var onReturn: () -> Void

    func makeNSView(context: Context) -> SettingsFeedbackWindowView { SettingsFeedbackWindowView() }
    func updateNSView(_ view: SettingsFeedbackWindowView, context: Context) {
        view.onLeave = onLeave
        view.onReturn = onReturn
    }
}

final class SettingsFeedbackWindowView: NSView {
    var onLeave: () -> Void = {}
    var onReturn: () -> Void = {}

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        NotificationCenter.default.removeObserver(self)
        super.viewWillMove(toWindow: newWindow)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        for name in [NSWindow.willCloseNotification, NSWindow.didMiniaturizeNotification] {
            NotificationCenter.default.addObserver(self, selector: #selector(leave), name: name, object: window)
        }
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didDeminiaturizeNotification] {
            NotificationCenter.default.addObserver(self, selector: #selector(returnToPage), name: name, object: window)
        }
    }

    @objc private func leave() { onLeave() }
    @objc private func returnToPage() { onReturn() }
}

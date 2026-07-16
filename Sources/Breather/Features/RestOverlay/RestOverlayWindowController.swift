import AppKit
import QuartzCore
import SwiftUI

@MainActor
final class RestOverlayWindowController {
    private let scheduler: BreakScheduler
    private let onSnooze: () -> Void
    private let onSkip: () -> Void
    private var windows: [NSPanel] = []
    private var dismissalState: RestOverlayDismissalState?
    private var keyMonitor: Any?
    private var previewTask: Task<Void, Never>?

    init(scheduler: BreakScheduler, onSnooze: @escaping () -> Void, onSkip: @escaping () -> Void) {
        self.scheduler = scheduler
        self.onSnooze = onSnooze
        self.onSkip = onSkip
    }

    func show() {
        hide(animated: false)
        let copy = RestOverlayCopy(
            settings: scheduler.settingsStore.settings,
            showsRecoveryNudge: scheduler.shouldShowRecoveryNudge
        )
        let dismissalState = RestOverlayDismissalState()
        self.dismissalState = dismissalState

        showWindows {
            RestOverlayView(
                scheduler: self.scheduler,
                dismissalState: dismissalState,
                copy: copy,
                onSnooze: { [weak self] in
                    self?.snoozeFromOverlay()
                },
                onSkip: { [weak self] in
                    self?.skipFromOverlay()
                }
            )
        }

        showVisibleWindows()
        installEscapeMonitor()
    }

    func preview() {
        hide(animated: false)
        let copy = RestOverlayCopy(settings: scheduler.settingsStore.settings)
        let dismissalState = RestOverlayDismissalState()
        self.dismissalState = dismissalState

        showWindows {
            RestOverlayPreviewView(
                dismissalState: dismissalState,
                copy: copy,
                background: self.scheduler.settingsStore.settings.restOverlayBackground,
                translucentBackground: self.scheduler.settingsStore.settings.restOverlayTranslucentBackground,
                onClose: { [weak self] in
                    self?.hide()
                }
            )
        }

        showVisibleWindows()
        previewTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            await MainActor.run {
                self?.hide()
            }
        }
    }

    func hide() {
        hide(animated: scheduler.settingsStore.settings.restOverlayFadeAnimation)
    }

    private func hide(animated: Bool) {
        keyMonitor.map(NSEvent.removeMonitor)
        keyMonitor = nil
        previewTask?.cancel()
        previewTask = nil

        let closingWindows = windows
        let closingDismissalState = dismissalState
        windows.removeAll()
        dismissalState = nil

        guard !closingWindows.isEmpty else {
            return
        }

        guard animated else {
            close(closingWindows)
            return
        }

        if scheduler.settingsStore.settings.restOverlayBackground == .sun,
           let closingDismissalState {
            closingWindows.forEach { window in
                window.alphaValue = 1
            }
            closingDismissalState.frozenTime = scheduler.formattedTime
            closingDismissalState.isDismissing = true
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(220))
                self.close(closingWindows)
            }
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.42
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            closingWindows.forEach { window in
                window.animator().alphaValue = 0
            }
        } completionHandler: {
            Task { @MainActor in
                self.close(closingWindows)
            }
        }
    }

    private func showWindows<Content: View>(@ViewBuilder content: @escaping () -> Content) {
        windows = NSScreen.screens.map { screen in
            let window = OverlayPanel(
                contentRect: screen.frame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            window.level = .screenSaver
            window.alphaValue = scheduler.settingsStore.settings.restOverlayFadeAnimation ? 0 : 1
            window.backgroundColor = .clear
            window.isOpaque = false
            window.hasShadow = false
            window.hidesOnDeactivate = false
            window.collectionBehavior = [
                .canJoinAllSpaces,
                .fullScreenAuxiliary,
                .stationary
            ]
            window.contentView = NSHostingView(rootView: content())
            window.setFrame(screen.frame, display: true)
            window.orderFrontRegardless()
            return window
        }
    }

    private func showVisibleWindows() {
        guard scheduler.settingsStore.settings.restOverlayFadeAnimation else {
            windows.forEach { window in
                window.alphaValue = 1
            }
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.55
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            windows.forEach { window in
                window.animator().alphaValue = 1
            }
        }
    }

    private func close(_ closingWindows: [NSPanel]) {
        closingWindows.forEach { window in
            window.orderOut(nil)
            window.contentView = nil
            window.close()
        }
    }

    private func installEscapeMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return event }
            guard let settings = self?.scheduler.settingsStore.settings,
                  settings.allowEscToSkip,
                  settings.allowSkip,
                  !settings.strictMode else { return event }
            self?.skipFromOverlay()
            return nil
        }
    }

    private func snoozeFromOverlay() {
        hide()
        DispatchQueue.main.async { [onSnooze] in
            onSnooze()
        }
    }

    private func skipFromOverlay() {
        hide()
        DispatchQueue.main.async { [onSkip] in
            onSkip()
        }
    }
}

private final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

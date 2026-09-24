import AppKit
import Combine
import QuartzCore
import SwiftUI

struct RestOverlayScreen: Equatable {
    let id: UInt32
    let frame: CGRect

    @MainActor static var connected: [Self] {
        NSScreen.screens.compactMap { screen in
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32 else { return nil }
            return Self(id: id, frame: screen.frame)
        }
    }
}

@MainActor
final class RestOverlayWindowController {
    private let scheduler: BreakScheduler
    private let onSnooze: () -> Void
    private let onSkip: () -> Void
    private let screens: () -> [RestOverlayScreen]
    private let mouseLocation: () -> CGPoint
    private let reduceMotion: () -> Bool
    private let presentsWindows: Bool
    private let ambientSoundService: RestAmbientSoundPlaying
    private(set) var windows: [UInt32: NSPanel] = [:]
    private(set) var session: RestOverlaySession?
    // Focus routing only; every display renders the same animated session.
    private(set) var keyboardScreenID: UInt32?
    private var keyMonitor: Any?
    private var previewTask: Task<Void, Never>?
    private var cancellables: Set<AnyCancellable> = []
    let availability: RestOverlayAvailability

    init(
        scheduler: BreakScheduler, onSnooze: @escaping () -> Void, onSkip: @escaping () -> Void,
        availability: RestOverlayAvailability = RestOverlayAvailability(),
        screens: @escaping () -> [RestOverlayScreen] = { RestOverlayScreen.connected },
        mouseLocation: @escaping () -> CGPoint = { NSEvent.mouseLocation },
        reduceMotion: @escaping () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion },
        presentsWindows: Bool = true,
        ambientSoundService: RestAmbientSoundPlaying = RestAmbientSoundService()
    ) {
        self.scheduler = scheduler
        self.onSnooze = onSnooze
        self.onSkip = onSkip
        self.availability = availability
        self.screens = screens
        self.mouseLocation = mouseLocation
        self.reduceMotion = reduceMotion
        self.presentsWindows = presentsWindows
        self.ambientSoundService = ambientSoundService

        scheduler.$state.sink { [weak availability] state in
            availability?.isResting = state == .resting
        }.store(in: &cancellables)
        scheduler.$remainingSeconds.sink { [weak self] seconds in
            guard let self, self.scheduler.isResting, let session = self.session,
                  session.kind == .rest else { return }
            session.updateRemaining(seconds)
        }.store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in self?.reconcileScreens() }
            .store(in: &cancellables)
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.publisher(for: NSWorkspace.willSleepNotification)
            .merge(with: workspace.publisher(for: NSWorkspace.sessionDidResignActiveNotification))
            .sink { [weak self] _ in
                self?.session?.setAnimationPaused(true)
                self?.ambientSoundService.stop()
            }
            .store(in: &cancellables)
        workspace.publisher(for: NSWorkspace.didWakeNotification)
            .merge(with: workspace.publisher(for: NSWorkspace.sessionDidBecomeActiveNotification))
            .sink { [weak self] _ in
                self?.session?.setAnimationPaused(false)
                self?.startAmbientSoundIfNeeded()
            }
            .store(in: &cancellables)
    }

    func show() {
        guard scheduler.isResting else { return }
        hide(animated: false)
        let countdownDelay = curtainCountdownDelay(for: scheduler.settingsStore.settings)
        scheduler.deferCurrentRestCountdown(by: countdownDelay)
        session = RestOverlaySession(
            kind: .rest, settings: scheduler.settingsStore.settings,
            totalSeconds: Int(scheduler.settingsStore.currentCycleRules.shortBreakDuration),
            remainingSeconds: scheduler.remainingSeconds,
            showsRecoveryNudge: scheduler.shouldShowRecoveryNudge,
            countdownDelay: countdownDelay
        )
        present()
        startAmbientSoundIfNeeded()
    }

    func preview() {
        guard !scheduler.isResting else { return }
        hide(animated: false)
        let countdownDelay = curtainCountdownDelay(for: scheduler.settingsStore.settings)
        let preview = RestOverlaySession(
            kind: .preview, settings: scheduler.settingsStore.settings,
            totalSeconds: Int(scheduler.settingsStore.rules.shortBreakDuration),
            countdownDelay: countdownDelay
        )
        session = preview
        present()
        startAmbientSoundIfNeeded()
        previewTask = Task { @MainActor [weak self, weak preview] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
                guard !Task.isCancelled, let self, let preview,
                      self.session?.id == preview.id else { return }
                preview.updatePreview()
                if preview.remainingSeconds == 0 {
                    self.closePresentation(id: preview.id)
                    return
                }
            }
        }
    }

    /// A scheduler transition must not dismiss an unrelated preview.
    func hideRest() {
        guard session?.kind == .rest else { return }
        hide()
    }

    func hide() { hide(animated: session?.fadeAnimation == true && !reduceMotion()) }

    func closePresentation(id: UUID) {
        guard session?.id == id else { return }
        hide()
    }

    func shutdown() {
        hide(animated: false)
        cancellables.removeAll()
    }

    private func present() {
        guard session != nil else { return }
        let connected = screens()
        keyboardScreenID = connected.first { $0.frame.contains(mouseLocation()) }?.id ?? connected.first?.id
        reconcileScreens()
        installEscapeMonitor()
    }

    /// Reuses the same session and clock across display hot-plug and resolution changes.
    func reconcileScreens() {
        guard let session else { return }
        let connected = screens()
        let ids = Set(connected.map(\.id))
        for id in Array(windows.keys) where !ids.contains(id) {
            if let window = windows.removeValue(forKey: id) { close([window]) }
        }
        if !ids.contains(keyboardScreenID ?? UInt32.max) {
            keyboardScreenID = connected.first?.id
        }
        for screen in connected {
            if let window = windows[screen.id] {
                window.setFrame(screen.frame, display: true)
            } else {
                let panel = OverlayPanel(
                    contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel],
                    backing: .buffered, defer: false
                )
                panel.isReleasedWhenClosed = false
                panel.level = .screenSaver
                panel.backgroundColor = .clear
                panel.isOpaque = false
                panel.hasShadow = false
                panel.hidesOnDeactivate = false
                panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
                panel.contentView = NSHostingView(rootView: RestOverlayScreenView(
                    settingsStore: scheduler.settingsStore, session: session,
                    onSnooze: { [weak self] in self?.snoozeFromOverlay(id: session.id) },
                    onSkip: { [weak self] in self?.skipFromOverlay(id: session.id) },
                    onClose: { [weak self] in self?.closePresentation(id: session.id) }
                ))
                panel.setFrame(screen.frame, display: true)
                windows[screen.id] = panel
                if presentsWindows {
                    let animated = session.fadeAnimation && !reduceMotion()
                    panel.alphaValue = animated ? 0 : 1
                    panel.orderFrontRegardless()
                    if animated {
                        NSAnimationContext.runAnimationGroup { context in
                            context.duration = 0.55
                            panel.animator().alphaValue = 1
                        }
                    }
                }
            }
        }
        if presentsWindows, let id = keyboardScreenID {
            windows[id]?.makeKey()
        }
    }

    private func hide(animated: Bool) {
        ambientSoundService.stop()
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        previewTask?.cancel()
        previewTask = nil
        let closingWindows = Array(windows.values)
        windows.removeAll()
        keyboardScreenID = nil
        guard let closingSession = session else { close(closingWindows); return }
        session = nil
        closingSession.beginDismissal()
        guard animated, presentsWindows else { close(closingWindows); return }

        if closingSession.contentMode == .curtain {
            // Keep the transparent panels alive until the opening film completes.
            closingWindows.forEach { $0.alphaValue = 1 }
            Task { @MainActor in
                try? await Task.sleep(for: CurtainTiming.openingDuration)
                self.close(closingWindows)
            }
        } else if closingSession.background == .sun {
            // Preserve the existing sun treatment: content fades before its background.
            closingWindows.forEach { $0.alphaValue = 1 }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(220))
                self.close(closingWindows)
            }
        } else {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.42
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                closingWindows.forEach { $0.animator().alphaValue = 0 }
            } completionHandler: {
                Task { @MainActor in self.close(closingWindows) }
            }
        }
    }

    private func curtainCountdownDelay(for settings: AppSettings) -> TimeInterval {
        guard settings.restOverlayContentMode == .curtain,
              settings.restOverlayFadeAnimation,
              !reduceMotion() else { return 0 }
        return CurtainTiming.closingDuration
    }

    private func startAmbientSoundIfNeeded() {
        guard let session, session.contentMode == .rainy,
              session.rainAmbienceEnabled, !session.isAnimationPaused,
              !session.isDismissing else {
            ambientSoundService.stop()
            return
        }
        ambientSoundService.playRain()
    }

    private func close(_ panels: [NSPanel]) {
        panels.forEach {
            $0.orderOut(nil)
            $0.contentView = nil
            $0.close()
        }
    }

    private func installEscapeMonitor() {
        guard presentsWindows else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.keyCode == 53, let session = self.session,
                  self.windows.values.contains(where: { $0 === event.window }) else { return event }
            return self.handleEscape(id: session.id) ? nil : event
        }
    }

    @discardableResult
    func handleEscape(id: UUID) -> Bool {
        guard let session, session.id == id else { return false }
        if session.kind == .preview {
            closePresentation(id: id)
            return true
        }
        let settings = scheduler.settingsStore.settings
        guard settings.allowEscToSkip, settings.allowSkip, !settings.strictMode else { return false }
        skipFromOverlay(id: id)
        return true
    }

    func snoozeFromOverlay(id: UUID) {
        guard session?.id == id, session?.kind == .rest, scheduler.isResting,
              !scheduler.settingsStore.settings.strictMode else { return }
        hide()
        onSnooze()
    }

    func skipFromOverlay(id: UUID) {
        let settings = scheduler.settingsStore.settings
        guard session?.id == id, session?.kind == .rest, scheduler.isResting,
              settings.allowSkip, !settings.strictMode else { return }
        hide()
        onSkip()
    }
}

struct RestOverlayScreenView: View {
    @ObservedObject var settingsStore: SettingsStore
    @ObservedObject var session: RestOverlaySession
    let onSnooze: () -> Void
    let onSkip: () -> Void
    let onClose: () -> Void

    var body: some View {
        Group {
            if session.kind == .rest {
                RestOverlayView(settingsStore: settingsStore, session: session,
                                onSnooze: onSnooze, onSkip: onSkip)
            } else {
                RestOverlayPreviewView(session: session,
                                       onClose: onClose)
            }
        }
    }
}

private final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

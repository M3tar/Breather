import AppKit
import Combine
import SwiftUI

private struct SettingsResetTransitionKey: EnvironmentKey {
    static let defaultValue: SettingsResetTransition? = nil
}
private struct SettingsResetFreezesPreviewsKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var settingsResetFreezesPreviews: Bool {
        get { self[SettingsResetFreezesPreviewsKey.self] }
        set { self[SettingsResetFreezesPreviewsKey.self] = newValue }
    }
    var settingsResetTransition: SettingsResetTransition? {
        get { self[SettingsResetTransitionKey.self] }
        set { self[SettingsResetTransitionKey.self] = newValue }
    }
}

/// Owns only the optional visual feedback. The caller owns the reset transaction.
@MainActor final class SettingsResetTransition: ObservableObject {
    enum Phase { case idle, confirming, committing, waiting, settling, capturing, playing }
    private(set) var phase: Phase = .idle
    @Published private(set) var freezesPreviews = false
    private(set) var generation = 0
    private(set) var surface: ResetHaloSurface?
    private(set) var snapshot: ResetHaloFrame?
    private(set) var oldSnapshot: ResetHaloFrame?
    private var oldSignature: [String] = []
    private var contentRevision = 0
    private(set) var lastStopReason = ""
    private(set) var dismissedAt = 0.0
    private(set) var preparationMS = 0.0
    private(set) var captureTimings: [String: Double] = [:]
    // Includes native layout settling and B capture. A is prepared during the
    // receipt; missed visual deadlines never delay or undo the reset transaction.
    private let preparationLimit = 0.20
    // Disabled in the app. The standalone integration harness can collect actual
    // drawable timestamps without changing sequencing or the renderer.
    var samples = ResetHaloSamples(enabled: false)
    private weak var host: NSView?
    private weak var stage: NSView?
    private weak var store: SettingsStore?
    private var gpu: ResetHaloGPU?
    private var pendingConfirmation = false
    private var prepared = false
    private var receiptReady = false
    private var task: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []
    private var subscriptions: Set<AnyCancellable> = []
    private var inputMonitor: Any?

    var hasResources: Bool { surface != nil || snapshot != nil || oldSnapshot != nil || task != nil }
    var coversCommittedContent: Bool {
        oldSnapshot != nil && phase != .idle && phase != .confirming
    }
    func contentUpdated() { contentRevision += 1 }
    private var eligible: Bool {
        guard let window = host?.window else { return false }
        return window.isVisible && window.isKeyWindow && !window.isMiniaturized
            && window.occlusionState.contains(.visible) && !NSApp.isHidden
            && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    func attach(host: NSView, stage: NSView, store: SettingsStore) {
        guard self.host !== host else { return }
        detach()
        self.host = host; self.stage = stage; self.store = store
        store.objectWillChange.sink { [weak self] in
            guard let self, self.phase != .committing else { return }
            self.cancel("content-changed")
        }.store(in: &subscriptions)
        func observe(_ name: Notification.Name, _ action: @escaping @MainActor (NSWindow?, NSView?) -> Void) {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { note in
                let window = note.object as? NSWindow, view = note.object as? NSView
                MainActor.assumeIsolated { action(window, view) }
            })
        }
        for name in [NSWindow.willCloseNotification, NSWindow.willMiniaturizeNotification,
                     NSWindow.didResizeNotification, NSWindow.didChangeBackingPropertiesNotification,
                     NSWindow.didChangeScreenProfileNotification] {
            observe(name) { [weak self] window, _ in
                guard let self, window === self.host?.window else { return }
                self.cancel("window-changed")
            }
        }
        observe(NSWindow.didResignKeyNotification) { [weak self] window, _ in
            guard let self, window === self.host?.window else { return }
            // Native sheet ownership changes key status during presentation.
            if self.phase == .confirming || self.phase == .waiting { return }
            self.cancel("resign-key")
        }
        observe(NSWindow.didChangeOcclusionStateNotification) { [weak self] changedWindow, _ in
            guard let self, let window = self.host?.window, changedWindow === window,
                  !window.occlusionState.contains(.visible) else { return }
            self.cancel("occluded")
        }
        for name in [NSApplication.willHideNotification, NSApplication.didResignActiveNotification] {
            observe(name) { [weak self] _, _ in self?.cancel("app-hidden-or-inactive") }
        }
        observe(NSView.boundsDidChangeNotification) { [weak self] _, view in
            guard let self, self.phase == .capturing || self.phase == .playing,
                  let host = self.host, let clip = view as? NSClipView, clip.isDescendant(of: host) else { return }
            self.cancel("scroll")
        }
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.cancel("accessibility-changed") } })
        inputMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown, .scrollWheel]) { [weak self] event in
            MainActor.assumeIsolated {
                if let self, event.window === self.host?.window { self.cancel("input") }
            }
            return event
        }
    }

    func prepareForConfirmation() {
        cancel("new-confirmation")
        dismissedAt = 0; preparationMS = 0; captureTimings = [:]
        host?.window?.makeFirstResponder(nil)
        pendingConfirmation = true; phase = .confirming
        guard eligible else { return }
        freezesPreviews = true
        let token = generation, existingGPU = gpu
        task = Task { @MainActor [weak self] in
            do {
                let gpu: ResetHaloGPU
                if let existingGPU { gpu = existingGPU }
                else { gpu = try await Task.detached(priority: .utility) { let value = try ResetHaloGPU(); try value.warm(); return value }.value }
                try Task.checkCancellation()
                guard let self, self.generation == token, self.phase == .confirming,
                      let stage = self.stage, let host = self.host, let window = host.window else { return }
                self.gpu = gpu
                let view = ResetHaloSurface(frame: stage.bounds, gpu: gpu)
                stage.addSubview(view); self.surface = view
                // Capture A while the user reads the receipt, before committing.
                // The native sheet is a separate window and is not in this tree.
                let deadline = CACurrentMediaTime() + 2
                var signature = ResetHaloCapture.signature(host)
                while true {
                    try await Task.sleep(for: .milliseconds(16))
                    try Task.checkCancellation()
                    guard self.generation == token, CACurrentMediaTime() < deadline else { throw CancellationError() }
                    host.layoutSubtreeIfNeeded(); host.displayIfNeeded()
                    let next = ResetHaloCapture.signature(host)
                    if self.receiptReady, next == signature, window.attachedSheet != nil { break }
                    signature = next
                }
                let size = host.bounds.size, scale = window.backingScaleFactor
                let (old, _) = try await ResetHaloCapture.capture(host: host, gpu: gpu, revision: token, scale: scale,
                    valid: { self.generation == token && self.phase == .confirming && window.isVisible
                        && host.bounds.size == size && window.backingScaleFactor == scale
                        && CACurrentMediaTime() < deadline }, samples: self.samples, requiresOpaqueContent: true)
                let capturedSignature = ResetHaloCapture.signature(host)
                try await view.prime(old.texture)
                try Task.checkCancellation()
                guard self.generation == token else { return }
                guard capturedSignature == ResetHaloCapture.signature(host) else { throw CancellationError() }
                self.oldSnapshot = old; self.oldSignature = capturedSignature
                self.prepared = true; self.task = nil
            } catch {
                guard let self, self.generation == token else { return }
                self.cancel("preparation-unavailable")
            }
        }
    }

    func confirmationDismissed() {
        guard pendingConfirmation else { return }
        pendingConfirmation = false; cancel("confirmation-cancelled")
    }

    func confirmationContentReady(generation token: Int) {
        guard token == generation, pendingConfirmation, phase == .confirming else { return }
        receiptReady = true
    }

    func restore(_ commit: () -> Void) {
        guard pendingConfirmation else { return } // Duplicate confirmation never commits twice.
        pendingConfirmation = false
        let canPlay = phase == .confirming && prepared && oldSnapshot != nil
            && host.map { ResetHaloCapture.signature($0) == oldSignature
                && $0.bounds.size == oldSnapshot?.size && $0.window?.backingScaleFactor == oldSnapshot?.scale } == true
        task?.cancel(); task = nil
        let sheet = host?.window?.attachedSheet
        let committedRevision = contentRevision
        let scrollPositions = host.map { ResetHaloScrollPosition.capture(in: $0) } ?? []
        if canPlay, let oldSnapshot { surface?.hold(oldSnapshot.texture) }
        phase = .committing
        host?.window?.makeFirstResponder(nil)
        if canPlay {
            // The halo owns the visible transition. Native controls underneath
            // its old-frame cover must reach their final state before B capture.
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction, commit)
        } else {
            commit()
        }
        guard canPlay, let host, let window = host.window, let gpu, let surface, let oldSnapshot else {
            cancel("visual-unavailable"); return
        }
        phase = .waiting
        let token = generation, size = host.bounds.size, scale = window.backingScaleFactor
        task = Task { @MainActor [weak self, weak host, weak window, weak sheet] in
            do {
                // SwiftUI onDismiss occurs before the native sheet has finished moving.
                let timeout = CACurrentMediaTime() + 2
                while let window, window.attachedSheet != nil || sheet?.isVisible == true || !window.isKeyWindow {
                    guard CACurrentMediaTime() < timeout else { throw CancellationError() }
                    try await Task.sleep(for: .milliseconds(8))
                }
                try Task.checkCancellation()
                guard let self, let host, let window, self.generation == token, self.eligible else { throw CancellationError() }
                self.dismissedAt = CACurrentMediaTime()
                self.phase = .settling
                @MainActor func valid() -> Bool {
                    self.generation == token && self.eligible && host.bounds.size == size
                        && window.backingScaleFactor == scale && window.attachedSheet == nil
                        && CACurrentMediaTime() - self.dismissedAt <= self.preparationLimit
                }
                // Wait for the actual SwiftUI update, then stable native values
                // and scroll geometry. A timer alone cannot prove B is ready.
                var stableSignature: [String]?
                while true {
                    try Task.checkCancellation()
                    guard valid() else { throw CancellationError() }
                    host.layoutSubtreeIfNeeded(); host.displayIfNeeded()
                    scrollPositions.forEach { $0.restore() }
                    let signature = ResetHaloCapture.signature(host) + ResetHaloScrollPosition.signature(in: host)
                    if self.contentRevision > committedRevision, signature == stableSignature { break }
                    stableSignature = signature
                    try await Task.sleep(for: .milliseconds(8))
                }
                self.phase = .capturing
                let (frame, _) = try await ResetHaloCapture.capture(host: host, gpu: gpu, revision: token, scale: scale,
                    valid: valid, samples: self.samples, requiresOpaqueContent: true)
                self.captureTimings = frame.timings.merging(["oldCaptureMS": oldSnapshot.timings["wallMS"] ?? 0]) { _, new in new }
                self.preparationMS = (CACurrentMediaTime() - self.dismissedAt) * 1000
                try Task.checkCancellation()
                guard valid() else { throw CancellationError() }
                self.snapshot = frame; self.phase = .playing
                surface.isValid = { [weak self, weak host, weak window] in
                    guard let self, let host, let window else { return false }
                    return self.generation == token && self.eligible && host.bounds.size == size
                        && window.backingScaleFactor == scale && window.attachedSheet == nil
                }
                surface.finished = { [weak self] reason in self?.cancel(reason) }
                surface.begin(oldSnapshot.texture, replacement: frame.texture, samples: self.samples)
                self.task = nil
            } catch {
                guard let self, self.generation == token else { return }
                if self.dismissedAt > 0 {
                    self.preparationMS = (CACurrentMediaTime() - self.dismissedAt) * 1000
                }
                self.cancel(self.preparationMS > self.preparationLimit * 1000 ? "late-capture" : "interrupted")
            }
        }
    }

    func cancel(_ reason: String) {
        generation += 1; lastStopReason = reason
        task?.cancel(); task = nil; prepared = false; receiptReady = false
        surface?.finished = nil; surface?.isValid = nil
        surface?.dispose(); surface = nil; snapshot = nil; oldSnapshot = nil; oldSignature = []
        phase = .idle
        if freezesPreviews { freezesPreviews = false }
    }

    func detach() {
        pendingConfirmation = false; cancel("detached")
        observers.forEach { NotificationCenter.default.removeObserver($0); NSWorkspace.shared.notificationCenter.removeObserver($0) }
        observers.removeAll()
        subscriptions.removeAll()
        if let inputMonitor { NSEvent.removeMonitor(inputMonitor) }; inputMonitor = nil
        host = nil; stage = nil; store = nil; gpu = nil
    }
}

/// Retain the same viewport on the same scroll view. If conditional rows shrink
/// the document, AppKit clamps to the nearest available position.
@MainActor private struct ResetHaloScrollPosition {
    weak var clip: NSClipView?
    let origin: NSPoint
    func restore() {
        guard let clip else { return }
        var proposed = clip.bounds; proposed.origin = origin
        let target = clip.constrainBoundsRect(proposed).origin
        if clip.bounds.origin != target {
            clip.scroll(to: target)
            (clip.superview as? NSScrollView)?.reflectScrolledClipView(clip)
        }
    }
    static func capture(in root: NSView) -> [Self] {
        var result: [Self] = []
        if let clip = root as? NSClipView { result.append(Self(clip: clip, origin: clip.bounds.origin)) }
        return result + root.subviews.flatMap { capture(in: $0) }
    }
    static func signature(in root: NSView) -> [String] {
        capture(in: root).map { "\($0.clip?.bounds ?? .zero)|\($0.clip?.documentView?.bounds ?? .zero)" }
    }
}

/// Capture only the current settings content; sidebar and window chrome stay live.
struct SettingsResetTransitionContent<Content: View>: NSViewRepresentable {
    @ObservedObject var transition: SettingsResetTransition
    let store: SettingsStore
    @ViewBuilder let content: () -> Content
    @Environment(\.colorScheme) private var colorScheme

    final class Container: NSView {
        let host = NSHostingView(rootView: AnyView(EmptyView()))
        weak var transition: SettingsResetTransition?
        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true; host.frame = bounds; host.autoresizingMask = [.width, .height]
            addSubview(host)
        }
        required init?(coder: NSCoder) { nil }
        override func viewDidChangeEffectiveAppearance() {
            super.viewDidChangeEffectiveAppearance(); transition?.cancel("appearance-changed")
        }
    }
    func makeNSView(context: Context) -> Container {
        let view = Container(frame: .zero)
        view.transition = transition
        transition.attach(host: view.host, stage: view, store: store)
        return view
    }
    func updateNSView(_ view: Container, context: Context) {
        view.host.rootView = AnyView(content()
            .transaction { transaction in
                // Preserve the same rule across the NSHostingView boundary and
                // subsequent observable-object updates while the cover is up.
                if transition.coversCommittedContent {
                    transaction.animation = nil
                    transaction.disablesAnimations = true
                }
            }
            .environment(\.settingsResetTransition, transition)
            .environment(\.settingsResetFreezesPreviews, transition.freezesPreviews)
            .environment(\.colorScheme, colorScheme)
            .frame(maxWidth: .infinity, maxHeight: .infinity))
        transition.contentUpdated()
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: Container, context: Context) -> CGSize? {
        guard let width = proposal.width, let height = proposal.height, width.isFinite, height.isFinite else { return nil }
        return CGSize(width: width, height: height)
    }
    static func dismantleNSView(_ view: Container, coordinator: ()) { view.transition?.detach() }
}

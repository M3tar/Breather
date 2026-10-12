import AppKit
import Combine
import CoreGraphics

/// Sleep has public NSWorkspace notifications. Lock notifications and the lock
/// session key are undocumented system signals, kept together at this boundary.
@MainActor
final class ComputerActivityMonitor {
    enum Event: Sendable {
        case sleep, wake, lock, unlock, sessionActive, sessionInactive
    }

    static let screenLockedNotification = Notification.Name("com.apple.screenIsLocked")
    static let screenUnlockedNotification = Notification.Name("com.apple.screenIsUnlocked")

    private(set) var state = ComputerActivityState()
    var onStateChanged: ((ComputerActivityState) -> Void)?

    private let workspaceCenter: NotificationCenter
    private let distributedCenter: NotificationCenter
    private let readSession: @MainActor () -> (isLocked: Bool?, isSessionActive: Bool?)
    private var observations: [AnyCancellable] = []
    private var isRunning = false

    init(
        workspaceCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
        distributedCenter: NotificationCenter = DistributedNotificationCenter.default(),
        readSession: @escaping @MainActor () -> (isLocked: Bool?, isSessionActive: Bool?) = ComputerActivityMonitor.currentSession
    ) {
        self.workspaceCenter = workspaceCenter
        self.distributedCenter = distributedCenter
        self.readSession = readSession
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        observe(workspaceCenter, NSWorkspace.willSleepNotification, event: .sleep)
        observe(workspaceCenter, NSWorkspace.didWakeNotification, event: .wake)
        observe(workspaceCenter, NSWorkspace.sessionDidResignActiveNotification, event: .sessionInactive)
        observe(workspaceCenter, NSWorkspace.sessionDidBecomeActiveNotification, event: .sessionActive)
        observe(distributedCenter, Self.screenLockedNotification, event: .lock)
        observe(distributedCenter, Self.screenUnlockedNotification, event: .unlock)
        var initial = ComputerActivityState()
        refreshSession(in: &initial)
        publish(initial)
    }

    func stop() {
        isRunning = false
        observations.removeAll()
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name, event: Event) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            // Synchronous main-queue delivery records sleep before execution stops.
            MainActor.assumeIsolated { self?.handle(event) }
        }
        observations.append(AnyCancellable { center.removeObserver(token) })
    }

    private func handle(_ event: Event) {
        guard isRunning else { return }
        var next = state
        switch event {
        case .sleep: next.isSleeping = true
        case .wake:
            next.isSleeping = false
            // Waking the machine does not imply that the user has unlocked it.
            refreshSession(in: &next)
        case .lock: next.isLocked = true
        case .unlock: next.isLocked = false
        case .sessionInactive: next.isSessionActive = false
        case .sessionActive:
            next.isSessionActive = true
            refreshSession(in: &next)
        }
        publish(next)
    }

    private func refreshSession(in state: inout ComputerActivityState) {
        let current = readSession()
        if let locked = current.isLocked { state.isLocked = locked }
        if let active = current.isSessionActive { state.isSessionActive = active }
    }

    private func publish(_ next: ComputerActivityState) {
        guard next != state else { return }
        state = next
        onStateChanged?(next)
    }

    private static func currentSession() -> (isLocked: Bool?, isSessionActive: Bool?) {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else { return (nil, nil) }
        return (session["CGSSessionScreenIsLocked"] as? Bool, session[kCGSessionOnConsoleKey as String] as? Bool)
    }
}

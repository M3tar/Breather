import CoreGraphics
import Foundation

@MainActor
protocol DisplayMirroringProviding: AnyObject {
    var isMirroring: Bool { get }
    var onMirroringChanged: ((Bool) -> Void)? { get set }
    func start()
    func stop()
    func refresh()
}

@MainActor
final class DisplayMirroringMonitor: DisplayMirroringProviding {
    private(set) var isMirroring = false
    var onMirroringChanged: ((Bool) -> Void)?

    private var isRunning = false
    private var pendingMirroringEndTask: Task<Void, Never>?

    func start() {
        guard !isRunning else {
            refreshState()
            return
        }

        isRunning = true
        CGDisplayRegisterReconfigurationCallback(
            displayMirroringReconfigurationCallback,
            Unmanaged.passUnretained(self).toOpaque()
        )
        refreshState()
    }

    func stop() {
        guard isRunning else { return }

        isRunning = false
        pendingMirroringEndTask?.cancel()
        pendingMirroringEndTask = nil
        CGDisplayRemoveReconfigurationCallback(
            displayMirroringReconfigurationCallback,
            Unmanaged.passUnretained(self).toOpaque()
        )
        publish(false)
    }

    func refresh() {
        guard isRunning else { return }
        refreshState()
    }

    fileprivate func displayConfigurationDidChange() {
        guard isRunning else { return }
        refreshState()
    }

    private func refreshState() {
        let currentState = Self.currentMirroringState()

        if currentState {
            pendingMirroringEndTask?.cancel()
            pendingMirroringEndTask = nil
            publish(true)
            return
        }

        guard isMirroring else {
            publish(false)
            return
        }

        pendingMirroringEndTask?.cancel()
        pendingMirroringEndTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled, let self, self.isRunning else { return }
            guard !Self.currentMirroringState() else { return }
            self.publish(false)
            self.pendingMirroringEndTask = nil
        }
    }

    private func publish(_ newValue: Bool) {
        guard isMirroring != newValue else { return }
        isMirroring = newValue
        onMirroringChanged?(newValue)
    }

    private static func currentMirroringState() -> Bool {
        var displayCount: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &displayCount) == .success,
              displayCount > 0 else {
            return false
        }

        var displays = Array(repeating: CGDirectDisplayID(), count: Int(displayCount))
        guard CGGetActiveDisplayList(displayCount, &displays, &displayCount) == .success else {
            return false
        }

        return displays.prefix(Int(displayCount)).contains {
            CGDisplayIsInMirrorSet($0) != 0
        }
    }
}

private func displayMirroringReconfigurationCallback(
    _ display: CGDirectDisplayID,
    _ flags: CGDisplayChangeSummaryFlags,
    _ userInfo: UnsafeMutableRawPointer?
) {
    guard let userInfo else { return }
    let monitor = Unmanaged<DisplayMirroringMonitor>.fromOpaque(userInfo).takeUnretainedValue()
    Task { @MainActor in
        monitor.displayConfigurationDidChange()
    }
}

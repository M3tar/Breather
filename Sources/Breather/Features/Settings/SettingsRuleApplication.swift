import Combine
import Foundation

/// Owns the delayed application to the active timer, independently of visual feedback.
@MainActor final class SettingsRuleApplication: ObservableObject {
    @Published private(set) var isWaiting = false
    private var task: Task<Void, Never>?

    func schedule(after delay: Duration = .milliseconds(900), apply: @escaping @MainActor () -> Void) {
        cancel(); isWaiting = true
        task = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: delay) } catch { return }
            guard !Task.isCancelled, let self else { return }
            self.task = nil; self.isWaiting = false
            apply()
        }
    }

    func update(store: SettingsStore, after delay: Duration = .milliseconds(900),
                apply: @escaping @MainActor () -> Void) {
        guard store.settings.ruleChangeEffect == .immediate, store.hasPendingRuleChanges else {
            cancel()
            return
        }
        schedule(after: delay) {
            // The cycle may have advanced or the user may have changed policy during the delay.
            guard store.settings.ruleChangeEffect == .immediate, store.hasPendingRuleChanges else { return }
            apply()
        }
    }

    func finishPending(store: SettingsStore, apply: @MainActor () -> Void) {
        cancel()
        if store.settings.ruleChangeEffect == .immediate, store.hasPendingRuleChanges { apply() }
    }

    func cancel() {
        task?.cancel(); task = nil; isWaiting = false
    }

    deinit { task?.cancel() }
}

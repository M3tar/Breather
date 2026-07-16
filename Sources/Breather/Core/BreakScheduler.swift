import Foundation

enum BreakState: Equatable {
    case working
    case notifying
    case resting
    case snoozing
    case paused
    case idleRested
}

@MainActor
final class BreakScheduler: ObservableObject {
    @Published private(set) var state: BreakState = .working
    @Published private(set) var remainingSeconds: Int
    @Published private(set) var statusText: String = "工作结束后，休息 30 秒"
    @Published private(set) var consecutiveMissedBreaks: Int = 0

    let settingsStore: SettingsStore

    var onRestStarted: (() -> Void)?
    var onRestEnded: (() -> Void)?
    var onRestBegan: (() -> Void)?
    var onRestFinished: (() -> Void)?

    private let notificationService: NotificationService
    private let idleMonitor: IdleMonitor
    private var timer: Timer?
    private var notificationSent = false
    private var previousStateBeforePause: BreakState = .working

    init(
        settingsStore: SettingsStore,
        notificationService: NotificationService,
        idleMonitor: IdleMonitor
    ) {
        self.settingsStore = settingsStore
        self.notificationService = notificationService
        self.idleMonitor = idleMonitor
        self.remainingSeconds = Int(settingsStore.rules.workDuration)
        updateStatusText()
    }

    var isPaused: Bool {
        state == .paused
    }

    var isResting: Bool {
        state == .resting
    }

    var shouldShowRecoveryNudge: Bool {
        consecutiveMissedBreaks >= settingsStore.settings.recoveryNudgeThreshold
    }

    var menuBarTitle: String {
        guard settingsStore.settings.showCountdownInMenuBar else { return "Breather" }
        if settingsStore.settings.showSeconds {
            return formattedTime
        }
        let minutes = max(1, Int(ceil(Double(remainingSeconds) / 60.0)))
        return "\(minutes)m"
    }

    var formattedTime: String {
        let minutes = remainingSeconds / 60
        let seconds = remainingSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    func start() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
    }

    func togglePause() {
        if state == .paused {
            state = previousStateBeforePause
            if state == .resting {
                onRestStarted?()
            }
        } else {
            previousStateBeforePause = state
            state = .paused
            onRestEnded?()
        }
        updateStatusText()
    }

    func resetWorkCycle() {
        let wasResting = state == .resting
        state = .working
        remainingSeconds = Int(settingsStore.rules.workDuration)
        notificationSent = false
        onRestEnded?()
        if wasResting {
            onRestFinished?()
        }
        updateStatusText()
    }

    func applyCurrentRulesToCurrentCycle() {
        notificationSent = false

        switch state {
        case .resting:
            remainingSeconds = Int(settingsStore.rules.shortBreakDuration)
            onRestStarted?()
        case .snoozing:
            remainingSeconds = Int(settingsStore.settings.snoozeDuration)
            onRestEnded?()
        case .paused:
            switch previousStateBeforePause {
            case .resting:
                remainingSeconds = Int(settingsStore.rules.shortBreakDuration)
            case .snoozing:
                remainingSeconds = Int(settingsStore.settings.snoozeDuration)
            case .working, .notifying, .idleRested, .paused:
                remainingSeconds = Int(settingsStore.rules.workDuration)
            }
        case .working, .notifying, .idleRested:
            state = .working
            remainingSeconds = Int(settingsStore.rules.workDuration)
            onRestEnded?()
        }

        updateStatusText()
    }

    func startRestNow() {
        beginRest()
    }

    func skipBreak() {
        let settings = settingsStore.settings
        guard state == .resting, settings.allowSkip, !settings.strictMode else { return }
        consecutiveMissedBreaks += 1
        resetWorkCycle()
    }

    func snoozeBreak() {
        let settings = settingsStore.settings
        guard state == .resting, !settings.strictMode else { return }
        consecutiveMissedBreaks += 1
        state = .snoozing
        remainingSeconds = Int(settings.snoozeDuration)
        notificationSent = true
        onRestEnded?()
        updateStatusText()
    }

    private func tick() {
        guard state != .paused else { return }

        if state == .idleRested {
            if idleMonitor.idleSeconds < 2 {
                resetWorkCycle()
            } else {
                updateStatusText()
            }
            return
        }

        if idleMonitor.idleSeconds >= settingsStore.settings.idleThreshold,
           state == .working || state == .notifying || state == .snoozing {
            state = .idleRested
            remainingSeconds = Int(settingsStore.rules.workDuration)
            notificationSent = false
            consecutiveMissedBreaks = 0
            onRestEnded?()
            updateStatusText()
            return
        }

        remainingSeconds = max(0, remainingSeconds - 1)

        if state == .working,
           !notificationSent,
           remainingSeconds <= Int(settingsStore.rules.preBreakNotificationOffset) {
            state = .notifying
            notificationSent = true
            notificationService.sendPreBreakNotification(
                playSound: settingsStore.settings.notificationSoundEnabled,
                soundEffect: settingsStore.settings.notificationSoundEffect
            )
        }

        if remainingSeconds == 0 {
            switch state {
            case .working, .notifying:
                beginRest()
            case .resting:
                consecutiveMissedBreaks = 0
                resetWorkCycle()
            case .snoozing:
                beginRest()
            case .paused, .idleRested:
                break
            }
        }

        updateStatusText()
    }

    private func beginRest() {
        state = .resting
        remainingSeconds = Int(settingsStore.rules.shortBreakDuration)
        notificationSent = false
        updateStatusText()
        onRestStarted?()
        onRestBegan?()
    }

    private func updateStatusText() {
        switch state {
        case .working, .notifying:
            statusText = "工作结束后，休息 \(Int(settingsStore.rules.shortBreakDuration)) 秒"
        case .resting:
            statusText = "请眺望远方"
        case .snoozing:
            statusText = "\(formattedSnoozeDuration(remainingSeconds))后补休"
        case .paused:
            statusText = "已暂停"
        case .idleRested:
            statusText = "已休息，重新开始"
        }
    }

    private func formattedSnoozeDuration(_ seconds: Int) -> String {
        if seconds >= 60 {
            let minutes = max(1, Int(ceil(Double(seconds) / 60.0)))
            return "\(minutes) 分钟"
        }
        return "\(max(1, seconds)) 秒"
    }
}

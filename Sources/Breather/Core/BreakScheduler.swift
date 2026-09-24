import Foundation

enum BreakState: Equatable {
    case working
    case notifying
    case resting
    case snoozing
    case paused
    case idleRested
}

enum PauseReason: Hashable {
    case user
    case displayMirroring
}

@MainActor
final class BreakScheduler: ObservableObject {
    @Published private(set) var state: BreakState = .working
    @Published private(set) var remainingSeconds: Int
    @Published private(set) var statusText: String = "工作结束后，休息 30 秒"
    @Published private(set) var consecutiveMissedBreaks: Int = 0
    @Published private(set) var pauseReasons: Set<PauseReason> = []
    @Published private(set) var pauseResumeSession: PauseResumeSession?
    @Published private(set) var pauseResumeRemainingSeconds: Int?

    let settingsStore: SettingsStore

    var onRestStarted: (() -> Void)?
    var onRestEnded: (() -> Void)?
    var onRestBegan: (() -> Void)?
    var onRestFinished: (() -> Void)?
    var onDisplayMirroringPauseBegan: (() -> Void)?

    private let notificationService: any BreakNotificationSending
    private let idleMonitor: any IdleTimeProviding
    private let pauseResumeSessionStore: PauseResumeSessionStore
    private let now: () -> Date
    private var timer: Timer?
    private var notificationSent = false
    private var previousStateBeforePause: BreakState = .working
    private var restCountdownStartsAt: Date?

    init(
        settingsStore: SettingsStore,
        notificationService: any BreakNotificationSending,
        idleMonitor: any IdleTimeProviding,
        pauseResumeSessionStore: PauseResumeSessionStore = PauseResumeSessionStore(),
        now: @escaping () -> Date = Date.init
    ) {
        self.settingsStore = settingsStore
        self.notificationService = notificationService
        self.idleMonitor = idleMonitor
        self.pauseResumeSessionStore = pauseResumeSessionStore
        self.now = now
        self.remainingSeconds = Int(settingsStore.currentCycleRules.workDuration)
        updateStatusText()
    }

    var isPaused: Bool {
        state == .paused
    }

    var isResting: Bool {
        state == .resting
    }

    var isUserPauseActive: Bool {
        pauseReasons.contains(.user)
    }

    var isDisplayMirroringPauseActive: Bool {
        pauseReasons.contains(.displayMirroring)
    }

    var shouldShowRecoveryNudge: Bool {
        consecutiveMissedBreaks >= settingsStore.settings.recoveryNudgeThreshold
    }

    var menuBarTitle: String {
        if isDisplayMirroringPauseActive {
            return "镜像中"
        }

        if isUserPauseActive {
            if let pauseResumeRemainingSeconds {
                let minutes = max(1, Int(ceil(Double(pauseResumeRemainingSeconds) / 60.0)))
                return "暂停 \(minutes)m"
            }
            return "已暂停"
        }

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

    var pauseStatusText: String? {
        if isDisplayMirroringPauseActive {
            return "屏幕镜像中 · 休息提醒已暂停"
        }
        if let pauseResumeRemainingSeconds, isUserPauseActive {
            return "已暂停 · \(formattedDuration(pauseResumeRemainingSeconds))后重新开始"
        }
        if isUserPauseActive {
            return "已暂停 · 直到手动继续"
        }
        return nil
    }

    var pauseContextTitle: String? {
        if isDisplayMirroringPauseActive {
            return "屏幕镜像中"
        }
        if isUserPauseActive {
            return "Breather 已暂停"
        }
        return nil
    }

    var pauseContextDetail: String? {
        if isDisplayMirroringPauseActive {
            return "休息提醒已暂停"
        }
        if let pauseResumeRemainingSeconds, isUserPauseActive {
            return "\(formattedDuration(pauseResumeRemainingSeconds))后重新开始完整工作周期"
        }
        if isUserPauseActive {
            return "不会提醒休息，直到你手动继续"
        }
        return nil
    }

    var pauseContextFootnote: String? {
        if isDisplayMirroringPauseActive {
            return "检测到 AirPlay 或有线屏幕镜像"
        }
        return nil
    }

    func start() {
        timer?.invalidate()
        _ = refreshPauseResumeSession()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
    }

    func restorePauseResumeSessionIfNeeded() {
        guard let session = pauseResumeSessionStore.load() else { return }
        guard !session.isExpired(at: now()) else {
            pauseResumeSessionStore.clear()
            return
        }

        pauseResumeSession = session
        updatePauseResumeRemainingSeconds(at: now())
        addPauseReason(.user)
    }

    func refreshPauseAfterWakeOrUnlock() {
        _ = refreshPauseResumeSession()
    }

    func beginPauseAutoResume(until resumesAt: Date) {
        let currentDate = now()
        guard resumesAt > currentDate else {
            cancelPauseAutoResume()
            return
        }

        if !isUserPauseActive {
            addPauseReason(.user)
        }

        let session = PauseResumeSession(startedAt: currentDate, resumesAt: resumesAt)
        pauseResumeSession = session
        pauseResumeSessionStore.save(session)
        updatePauseResumeRemainingSeconds(at: currentDate)
        updateStatusText()
    }

    func cancelPauseAutoResume() {
        pauseResumeSession = nil
        pauseResumeRemainingSeconds = nil
        pauseResumeSessionStore.clear()
        updateStatusText()
    }

    func continueUserPause() {
        guard isUserPauseActive else { return }

        cancelPauseAutoResume()
        pauseReasons.remove(.user)
        restoreStateAfterOrdinaryPauseIfPossible()
        updateStatusText()
    }

    func setDisplayMirroringActive(_ isActive: Bool) {
        if isActive {
            guard settingsStore.settings.autoPauseDuringDisplayMirroring else { return }
            addPauseReason(.displayMirroring)
        } else {
            removeDisplayMirroringPauseReason()
        }
    }

    func disableDisplayMirroringAutoPause() {
        setDisplayMirroringActive(false)
    }

    func togglePause() {
        guard !isDisplayMirroringPauseActive else { return }

        if isUserPauseActive {
            continueUserPause()
        } else {
            addPauseReason(.user)
        }
        updateStatusText()
    }

    func resetWorkCycle() {
        let wasResting = state == .resting
        restCountdownStartsAt = nil

        settingsStore.activateSavedRulesForCurrentCycle()

        pauseResumeSession = nil
        pauseResumeRemainingSeconds = nil
        pauseResumeSessionStore.clear()

        if isDisplayMirroringPauseActive {
            pauseReasons.remove(.user)
            remainingSeconds = Int(settingsStore.currentCycleRules.workDuration)
            previousStateBeforePause = .working
            notificationSent = false
            onRestEnded?()
            updateStatusText()
            return
        }

        pauseReasons.removeAll()
        state = .working
        previousStateBeforePause = .working
        remainingSeconds = Int(settingsStore.currentCycleRules.workDuration)
        notificationSent = false
        onRestEnded?()
        if wasResting {
            onRestFinished?()
        }
        updateStatusText()
    }

    func applyCurrentRulesToCurrentCycle() {
        settingsStore.activateSavedRulesForCurrentCycle()
        notificationSent = false

        if isDisplayMirroringPauseActive {
            previousStateBeforePause = .working
            remainingSeconds = Int(settingsStore.currentCycleRules.workDuration)
            onRestEnded?()
            updateStatusText()
            return
        }

        switch state {
        case .resting:
            remainingSeconds = Int(settingsStore.currentCycleRules.shortBreakDuration)
            onRestStarted?()
        case .snoozing:
            remainingSeconds = Int(settingsStore.settings.snoozeDuration)
            onRestEnded?()
        case .paused:
            switch previousStateBeforePause {
            case .resting:
                remainingSeconds = Int(settingsStore.currentCycleRules.shortBreakDuration)
            case .snoozing:
                remainingSeconds = Int(settingsStore.settings.snoozeDuration)
            case .working, .notifying, .idleRested, .paused:
                remainingSeconds = Int(settingsStore.currentCycleRules.workDuration)
            }
        case .working, .notifying, .idleRested:
            state = .working
            remainingSeconds = Int(settingsStore.currentCycleRules.workDuration)
            onRestEnded?()
        }

        updateStatusText()
    }

    func startRestNow() {
        guard !isDisplayMirroringPauseActive else { return }
        pauseReasons.remove(.user)
        pauseResumeSession = nil
        pauseResumeRemainingSeconds = nil
        pauseResumeSessionStore.clear()
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
        restCountdownStartsAt = nil
        remainingSeconds = Int(settings.snoozeDuration)
        notificationSent = true
        onRestEnded?()
        updateStatusText()
    }

    func tick() {
        if refreshPauseResumeSession() {
            return
        }
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
            remainingSeconds = Int(settingsStore.currentCycleRules.workDuration)
            notificationSent = false
            consecutiveMissedBreaks = 0
            onRestEnded?()
            updateStatusText()
            return
        }

        if state == .resting, let restCountdownStartsAt {
            guard now() >= restCountdownStartsAt else {
                updateStatusText()
                return
            }
            self.restCountdownStartsAt = nil
        }

        remainingSeconds = max(0, remainingSeconds - 1)

        if state == .working,
           !notificationSent,
           remainingSeconds <= Int(settingsStore.currentCycleRules.preBreakNotificationOffset) {
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

    private func addPauseReason(_ reason: PauseReason) {
        guard !pauseReasons.contains(reason) else {
            updateStatusText()
            return
        }

        if pauseReasons.isEmpty {
            previousStateBeforePause = state
        }

        pauseReasons.insert(reason)
        state = .paused
        onRestEnded?()

        if reason == .displayMirroring {
            onDisplayMirroringPauseBegan?()
        }
        updateStatusText()
    }

    private func removeDisplayMirroringPauseReason() {
        guard pauseReasons.contains(.displayMirroring) else { return }

        pauseReasons.remove(.displayMirroring)
        prepareFreshWorkCycleAfterProtectedPause()
    }

    private func prepareFreshWorkCycleAfterProtectedPause() {
        settingsStore.activateSavedRulesForCurrentCycle()
        remainingSeconds = Int(settingsStore.currentCycleRules.workDuration)
        notificationSent = false
        previousStateBeforePause = .working
        onRestEnded?()

        if pauseReasons.isEmpty {
            state = .working
        } else {
            state = .paused
        }
        updateStatusText()
    }

    private func restoreStateAfterOrdinaryPauseIfPossible() {
        guard pauseReasons.isEmpty else {
            state = .paused
            return
        }

        state = previousStateBeforePause == .paused ? .working : previousStateBeforePause
        if state == .resting {
            onRestStarted?()
        }
    }

    @discardableResult
    private func refreshPauseResumeSession() -> Bool {
        guard let session = pauseResumeSession else { return false }
        let currentDate = now()

        if session.isExpired(at: currentDate) {
            pauseResumeSession = nil
            pauseResumeRemainingSeconds = nil
            pauseResumeSessionStore.clear()
            pauseReasons.remove(.user)
            prepareFreshWorkCycleAfterProtectedPause()
            return true
        }

        updatePauseResumeRemainingSeconds(at: currentDate)
        updateStatusText()
        return false
    }

    private func updatePauseResumeRemainingSeconds(at date: Date) {
        guard let resumesAt = pauseResumeSession?.resumesAt else {
            pauseResumeRemainingSeconds = nil
            return
        }

        pauseResumeRemainingSeconds = max(0, Int(ceil(resumesAt.timeIntervalSince(date))))
    }

    private func beginRest() {
        state = .resting
        restCountdownStartsAt = nil
        remainingSeconds = Int(settingsStore.currentCycleRules.shortBreakDuration)
        notificationSent = false
        updateStatusText()
        onRestStarted?()
        onRestBegan?()
    }

    func deferCurrentRestCountdown(by duration: TimeInterval) {
        guard state == .resting, duration > 0 else { return }
        restCountdownStartsAt = now().addingTimeInterval(duration)
    }

    private func updateStatusText() {
        if let pauseStatusText {
            statusText = pauseStatusText
            return
        }

        switch state {
        case .working, .notifying:
            statusText = "工作结束后，休息 \(Int(settingsStore.currentCycleRules.shortBreakDuration)) 秒"
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

    private func formattedDuration(_ seconds: Int) -> String {
        if seconds >= 60 {
            let minutes = max(1, Int(ceil(Double(seconds) / 60.0)))
            return "\(minutes) 分钟"
        }
        return "\(max(1, seconds)) 秒"
    }

    private func formattedSnoozeDuration(_ seconds: Int) -> String {
        if seconds >= 60 {
            let minutes = max(1, Int(ceil(Double(seconds) / 60.0)))
            return "\(minutes) 分钟"
        }
        return "\(max(1, seconds)) 秒"
    }
}

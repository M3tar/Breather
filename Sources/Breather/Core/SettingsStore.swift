import Foundation

/// Only pages with a meaningful set of app-owned preferences expose a reset action.
enum SettingsResetScope: CaseIterable {
    case schedule, menuBar, restOverlay

    func restoringDefaults(in settings: AppSettings) -> AppSettings {
        let defaults = AppSettings()
        var restored = settings
        switch self {
        case .schedule:
            restored.ruleChangeEffect = defaults.ruleChangeEffect
            restored.allowSkip = defaults.allowSkip
            restored.allowEscToSkip = defaults.allowEscToSkip
            restored.snoozeDuration = defaults.snoozeDuration
            restored.recoveryNudgeThreshold = defaults.recoveryNudgeThreshold
            restored.strictMode = defaults.strictMode
            restored.autoPauseDuringDisplayMirroring = defaults.autoPauseDuringDisplayMirroring
            restored.automaticRestMode = defaults.automaticRestMode
            restored.automaticRestThreshold = defaults.automaticRestThreshold
        case .menuBar:
            restored.showMenuBarIcon = defaults.showMenuBarIcon
            restored.menuBarIcon = defaults.menuBarIcon
            restored.showCountdownInMenuBar = defaults.showCountdownInMenuBar
            restored.showSeconds = defaults.showSeconds
            restored.menuBarPopoverThemeColor = defaults.menuBarPopoverThemeColor
            restored.menuBarPopoverProgressStyle = defaults.menuBarPopoverProgressStyle
            restored.menuBarPopoverSquareStyle = defaults.menuBarPopoverSquareStyle
            restored.menuBarPopoverSquareColorMode = defaults.menuBarPopoverSquareColorMode
            restored.menuBarPopoverAppearance = defaults.menuBarPopoverAppearance
        case .restOverlay:
            restored.restOverlayPrompt = defaults.restOverlayPrompt
            restored.restOverlayContentMode = defaults.restOverlayContentMode
            restored.curtainPalette = defaults.curtainPalette
            restored.cloudTrainPlaybackSpeed = defaults.cloudTrainPlaybackSpeed
            restored.cloudTrainForegroundSpeed = defaults.cloudTrainForegroundSpeed
            restored.restOverlaySubtitle = defaults.restOverlaySubtitle
            restored.restOverlayBackground = defaults.restOverlayBackground
            restored.restOverlayFadeAnimation = defaults.restOverlayFadeAnimation
            restored.restOverlayTranslucentBackground = defaults.restOverlayTranslucentBackground
            restored.rainAmbienceEnabled = defaults.rainAmbienceEnabled
            restored.playRestStartSound = defaults.playRestStartSound
            restored.playRestEndSound = defaults.playRestEndSound
            restored.restStartSoundEffect = defaults.restStartSoundEffect
            restored.restEndSoundEffect = defaults.restEndSoundEffect
        }
        return restored
    }
}

/// Saved preferences and the active cycle are separate, complete values.
struct CycleConfiguration: Equatable {
    let rules: BreakRules
    let automaticRestMode: AutomaticRestMode
    let automaticRestThreshold: TimeInterval

    init(rules: BreakRules, settings: AppSettings) {
        self.rules = rules
        automaticRestMode = settings.automaticRestMode
        automaticRestThreshold = AutomaticRestDuration.normalized(settings.automaticRestThreshold,
            mode: settings.automaticRestMode, shortBreak: rules.shortBreakDuration)
    }
}

@MainActor
final class SettingsStore: ObservableObject {
    @Published var rules: BreakRules {
        didSet {
            normalizeAutomaticRestDuration()
            saveRules()
        }
    }

    @Published private(set) var currentCycleConfiguration: CycleConfiguration

    var currentCycleRules: BreakRules { currentCycleConfiguration.rules }
    var currentAutomaticRestMode: AutomaticRestMode { currentCycleConfiguration.automaticRestMode }
    var savedCycleConfiguration: CycleConfiguration { CycleConfiguration(rules: rules, settings: settings) }

    @Published var settings: AppSettings {
        didSet {
            normalizeAutomaticRestDuration()
            saveSettings()
        }
    }

    private let userDefaults: UserDefaults
    private static let rulesKey = "breather.rules"
    private static let settingsKey = "breather.settings"
    private var isRestoringDefaults = false

    static func hasSavedPreferences(in userDefaults: UserDefaults = .standard) -> Bool {
        userDefaults.data(forKey: rulesKey) != nil || userDefaults.data(forKey: settingsKey) != nil
    }

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        let savedRules = Self.load(BreakRules.self, key: Self.rulesKey, from: userDefaults) ?? BreakRules()
        let savedSettings = Self.load(AppSettings.self, key: Self.settingsKey, from: userDefaults) ?? AppSettings()
        self.rules = savedRules
        self.settings = savedSettings
        self.currentCycleConfiguration = CycleConfiguration(rules: savedRules, settings: savedSettings)
        normalizeAutomaticRestDuration()
    }

    func isDefault(for scope: SettingsResetScope) -> Bool {
        scope.restoringDefaults(in: settings) == settings
            && (scope != .schedule || rules == BreakRules())
    }

    func restoreDefaults(for scope: SettingsResetScope) {
        // Validate the final pair, not default settings against the old rules.
        isRestoringDefaults = true
        // Install the default next-cycle policy before publishing new rules.
        settings = scope.restoringDefaults(in: settings)
        if scope == .schedule {
            rules = BreakRules()
        }
        isRestoringDefaults = false
        normalizeAutomaticRestDuration()
    }

    var hasPendingRuleChanges: Bool {
        savedCycleConfiguration != currentCycleConfiguration
    }

    func activateSavedRulesForCurrentCycle() {
        currentCycleConfiguration = savedCycleConfiguration
    }

    var workMinutes: Int {
        get { Int(rules.workDuration / 60) }
        set { rules.workDuration = TimeInterval(newValue * 60) }
    }

    var shortBreakSeconds: Int {
        get { Int(rules.shortBreakDuration) }
        set { rules.shortBreakDuration = TimeInterval(newValue) }
    }

    var preBreakNotificationSeconds: Int {
        get { Int(rules.preBreakNotificationOffset) }
        set { rules.preBreakNotificationOffset = TimeInterval(min(120, max(1, newValue))) }
    }

    var automaticRestSeconds: Int {
        get { Int(settings.automaticRestThreshold) }
        set { settings.automaticRestThreshold = TimeInterval(newValue) }
    }

    var automaticRestMinimumSeconds: Int {
        AutomaticRestDuration.minimum(mode: settings.automaticRestMode, shortBreak: rules.shortBreakDuration)
    }

    var effectiveAutomaticRestThreshold: TimeInterval {
        currentCycleConfiguration.automaticRestThreshold
    }

    private func normalizeAutomaticRestDuration() {
        guard !isRestoringDefaults else { return }
        let value = AutomaticRestDuration.normalized(settings.automaticRestThreshold,
            mode: settings.automaticRestMode, shortBreak: rules.shortBreakDuration)
        guard settings.automaticRestThreshold != value else { return }
        settings.automaticRestThreshold = value
    }

    var snoozeMinutes: Int {
        get { Int(settings.snoozeDuration / 60) }
        set { settings.snoozeDuration = TimeInterval(newValue * 60) }
    }

    var recoveryNudgeThreshold: Int {
        get { settings.recoveryNudgeThreshold }
        set { settings.recoveryNudgeThreshold = newValue }
    }

    private func saveRules() {
        save(rules, key: Self.rulesKey)
    }

    private func saveSettings() {
        save(settings, key: Self.settingsKey)
    }

    private func save<T: Encodable>(_ value: T, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        userDefaults.set(data, forKey: key)
    }

    private static func load<T: Decodable>(_ type: T.Type, key: String, from userDefaults: UserDefaults) -> T? {
        guard let data = userDefaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}

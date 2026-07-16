import Foundation

@MainActor
final class SettingsStore: ObservableObject {
    @Published var rules: BreakRules {
        didSet { saveRules() }
    }

    @Published var settings: AppSettings {
        didSet { saveSettings() }
    }

    private let userDefaults: UserDefaults
    private let rulesKey = "breather.rules"
    private let settingsKey = "breather.settings"

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        self.rules = Self.load(BreakRules.self, key: rulesKey, from: userDefaults) ?? BreakRules()
        self.settings = Self.load(AppSettings.self, key: settingsKey, from: userDefaults) ?? AppSettings()
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
        set { rules.preBreakNotificationOffset = TimeInterval(newValue) }
    }

    var idleMinutes: Int {
        get { Int(settings.idleThreshold / 60) }
        set { settings.idleThreshold = TimeInterval(newValue * 60) }
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
        save(rules, key: rulesKey)
    }

    private func saveSettings() {
        save(settings, key: settingsKey)
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

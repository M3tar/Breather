import Foundation

struct BreakRules: Codable, Equatable {
    var workDuration: TimeInterval = 30 * 60
    var shortBreakDuration: TimeInterval = 30
    var longBreakEnabled: Bool = false
    var longBreakEveryShortBreaks: Int = 4
    var longBreakDuration: TimeInterval = 5 * 60
    var preBreakNotificationEnabled: Bool = true
    var preBreakNotificationOffset: TimeInterval = 20

    init() {}

    private enum CodingKeys: String, CodingKey {
        case workDuration, shortBreakDuration, longBreakEnabled
        case longBreakEveryShortBreaks, longBreakDuration
        case preBreakNotificationEnabled, preBreakNotificationOffset
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        workDuration = try container.decodeIfPresent(TimeInterval.self, forKey: .workDuration) ?? workDuration
        shortBreakDuration = try container.decodeIfPresent(TimeInterval.self, forKey: .shortBreakDuration) ?? shortBreakDuration
        longBreakEnabled = try container.decodeIfPresent(Bool.self, forKey: .longBreakEnabled) ?? longBreakEnabled
        longBreakEveryShortBreaks = try container.decodeIfPresent(Int.self, forKey: .longBreakEveryShortBreaks) ?? longBreakEveryShortBreaks
        longBreakDuration = try container.decodeIfPresent(TimeInterval.self, forKey: .longBreakDuration) ?? longBreakDuration

        let savedOffset = try container.decodeIfPresent(TimeInterval.self, forKey: .preBreakNotificationOffset)
            ?? preBreakNotificationOffset
        // Older versions represented the notification choice with the duration alone.
        preBreakNotificationEnabled = try container.decodeIfPresent(Bool.self, forKey: .preBreakNotificationEnabled)
            ?? (savedOffset > 0)
        preBreakNotificationOffset = savedOffset > 0 ? min(120, max(1, savedOffset)) : preBreakNotificationOffset
    }
}

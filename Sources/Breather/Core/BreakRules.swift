import Foundation

struct BreakRules: Codable, Equatable {
    var workDuration: TimeInterval = 30 * 60
    var shortBreakDuration: TimeInterval = 30
    var longBreakEnabled: Bool = false
    var longBreakEveryShortBreaks: Int = 4
    var longBreakDuration: TimeInterval = 5 * 60
    var preBreakNotificationOffset: TimeInterval = 20
}

import Foundation

enum AutomaticRestMode: String, Codable, CaseIterable, Identifiable {
    case disabled
    case lockOrSleep
    case lockSleepOrIdle

    var id: String { rawValue }
    var isEnabled: Bool { self != .disabled }
    var includesIdle: Bool { self == .lockSleepOrIdle }

    var title: String {
        switch self {
        case .disabled: L.tr("关闭")
        case .lockOrSleep: L.tr("锁屏或睡眠")
        case .lockSleepOrIdle: L.tr("锁屏、睡眠或无操作")
        }
    }
}

/// One seconds-based policy for persistence, editing and runtime recognition.
enum AutomaticRestDuration {
    static let maximum = 30 * 60

    static func minimum(mode: AutomaticRestMode, shortBreak: TimeInterval) -> Int {
        let duration = shortBreak.isFinite ? shortBreak.rounded(.up) : 30
        return max(mode.includesIdle ? 60 : 1, Int(min(Double(maximum), max(1, duration))))
    }

    static func normalized(_ value: TimeInterval, mode: AutomaticRestMode,
                           shortBreak: TimeInterval) -> TimeInterval {
        let lower = mode.isEnabled ? minimum(mode: mode, shortBreak: shortBreak) : 1
        let seconds = value.isFinite ? value.rounded(.up) : 5 * 60
        return min(Double(maximum), max(Double(lower), seconds))
    }

}

struct ComputerActivityState: Codable, Equatable, Sendable {
    var isLocked = false
    var isSleeping = false
    var isSessionActive = true

    var isUnavailable: Bool { isLocked || isSleeping || !isSessionActive }
    var canCountAsRest: Bool { isLocked || isSleeping }
}

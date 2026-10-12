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
        case .lockOrSleep: L.tr("锁屏或电脑睡眠")
        case .lockSleepOrIdle: L.tr("锁屏、睡眠或无操作")
        }
    }
}

struct ComputerActivityState: Equatable, Sendable {
    var isLocked = false
    var isSleeping = false
    var isSessionActive = true

    var isUnavailable: Bool { isLocked || isSleeping || !isSessionActive }
    var canCountAsRest: Bool { isLocked || isSleeping }
}

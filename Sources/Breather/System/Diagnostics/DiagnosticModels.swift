import Foundation

// Deliberately typed: arbitrary messages, paths and preference dictionaries never
// enter the diagnostic file. All strings below come from our own enums/code.
struct DiagnosticSchedulerSnapshot: Codable, Equatable, Sendable {
    let state: String
    let previousState: String
    let pauseReasons: [String]
    let remainingSeconds: Int
    let tickCount: UInt64
    let lastTickUptime: TimeInterval?
    let lastProgressUptime: TimeInterval?
    let countdownStartsAt: Date?
    let activity: ComputerActivityState

    func hasSameTransition(as other: Self) -> Bool {
        state == other.state && previousState == other.previousState
            && pauseReasons == other.pauseReasons && countdownStartsAt == other.countdownStartsAt
            && activity == other.activity
    }
}

struct DiagnosticOverlaySnapshot: Codable, Equatable, Sendable {
    let sessionID: UUID?
    let kind: String?
    let remainingSeconds: Int?
    let isDismissing: Bool
    let isAnimationPaused: Bool
    let windowCount: Int
}

struct DiagnosticSettingsSnapshot: Codable, Equatable, Sendable {
    let workSeconds: TimeInterval
    let shortBreakSeconds: TimeInterval
    let automaticRestMode: String
    let automaticRestThreshold: TimeInterval
    let pauseDuringMirroring: Bool
    let theme: String
    let fadeAnimation: Bool
    var effectiveAutomaticRestThreshold: TimeInterval? = nil
    var effectiveAutomaticRestMode: String? = nil
}

struct DiagnosticSystemEvent: Codable, Sendable {
    let name: String
    let before: ComputerActivityState
    let after: ComputerActivityState
    let observedLocked: Bool?
    let observedSessionActive: Bool?
}

struct DiagnosticEnvironment: Codable, Sendable {
    let appVersion: String
    let build: String
    let macOSVersion: String
    let architecture: String

    static var current: Self {
        #if arch(arm64)
        let architecture = "arm64"
        #else
        let architecture = "x86_64"
        #endif
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return Self(appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development",
                    build: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "development",
                    macOSVersion: "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)",
                    architecture: architecture)
    }
}

struct DiagnosticSnapshot: Codable, Sendable {
    let environment: DiagnosticEnvironment
    let scheduler: DiagnosticSchedulerSnapshot?
    let overlay: DiagnosticOverlaySnapshot?
    let settings: DiagnosticSettingsSnapshot?
}

struct DiagnosticEvent: Codable, Sendable {
    enum Kind: String, Codable, Sendable {
        case appStarted, appStopped, systemEvent, schedulerChanged, overlayChanged
        case settingsChanged, snapshot, recordingEnabled, dataLoss
    }
    let schemaVersion: Int
    let timestamp: Date
    let uptime: TimeInterval
    let launchID: UUID
    let sequence: UInt64
    let kind: Kind
    let reason: String?
    let snapshot: DiagnosticSnapshot?
    let system: DiagnosticSystemEvent?
    let droppedEvents: Int?
}

struct DiagnosticHealth: Sendable {
    var droppedEvents = 0
    var writeFailures = 0
    var lastError: String?
}

struct DiagnosticExport: Sendable {
    let directory: URL
    let archive: URL
    let bytes: Int
    let eventCount: Int
    let earliest: Date?
    let latest: Date?
    let malformedLines: Int
}

enum DiagnosticFailure: Error { case unavailable, oversizedEvent, archiveFailed }

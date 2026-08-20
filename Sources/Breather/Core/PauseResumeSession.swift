import Foundation

struct PauseResumeSession: Codable, Equatable {
    let startedAt: Date
    let resumesAt: Date

    func isExpired(at date: Date) -> Bool {
        resumesAt <= date
    }
}

final class PauseResumeSessionStore {
    private struct LegacyScreenSharingPauseSession: Codable {
        let startedAt: Date
        let expiresAt: Date?
    }

    private let userDefaults: UserDefaults
    private let key: String
    private let legacyKey: String

    init(
        userDefaults: UserDefaults = .standard,
        key: String = "breather.pauseResumeSession",
        legacyKey: String = "breather.screenSharingPauseSession"
    ) {
        self.userDefaults = userDefaults
        self.key = key
        self.legacyKey = legacyKey
    }

    func load() -> PauseResumeSession? {
        if let data = userDefaults.data(forKey: key),
           let session = try? JSONDecoder().decode(PauseResumeSession.self, from: data) {
            return session
        }

        guard let legacyData = userDefaults.data(forKey: legacyKey),
              let legacySession = try? JSONDecoder().decode(
                LegacyScreenSharingPauseSession.self,
                from: legacyData
              ),
              let expiresAt = legacySession.expiresAt else {
            userDefaults.removeObject(forKey: legacyKey)
            return nil
        }

        let migratedSession = PauseResumeSession(
            startedAt: legacySession.startedAt,
            resumesAt: expiresAt
        )
        save(migratedSession)
        return migratedSession
    }

    func save(_ session: PauseResumeSession) {
        guard let data = try? JSONEncoder().encode(session) else { return }
        userDefaults.set(data, forKey: key)
        userDefaults.removeObject(forKey: legacyKey)
    }

    func clear() {
        userDefaults.removeObject(forKey: key)
        userDefaults.removeObject(forKey: legacyKey)
    }
}

import Foundation
import Observation

struct InstalledReleaseNotes {
    let version: String
    let highlights: [String]

    static func bundled(for version: String) -> Self? {
        switch version {
        case "0.7.0":
            Self(version: version, highlights: [
                "查看近 30 天的休息记录",
                "提醒时可选「我刚休息过」",
                "修复雨滴和小恐龙动画提前停止的问题",
            ])
        case "0.6.0":
            Self(version: version, highlights: [
                "自动计为休息精确到秒",
                "按页恢复默认设置",
                "可导出运行日志",
            ])
        default:
            nil
        }
    }

    func localizedHighlights(language: AppLanguage = .effective) -> [String] {
        highlights.map { L.tr($0, language: language) }
    }
}

@MainActor
@Observable
final class InstalledReleaseNotice {
    private(set) var pendingNotes: InstalledReleaseNotes?

    private static let storageKey = "breather.installedReleaseNotice"
    private let userDefaults: UserDefaults

    init(
        userDefaults: UserDefaults = .standard,
        installedVersion: String = AppVersion.installedString,
        hasPreviousUse: Bool,
        notesForVersion: (String) -> InstalledReleaseNotes? = InstalledReleaseNotes.bundled(for:)
    ) {
        self.userDefaults = userDefaults
        guard UpdateChecker.isStableVersion(installedVersion), let current = AppVersion(installedVersion) else { return }

        var record = userDefaults.dictionary(forKey: Self.storageKey) as? [String: String] ?? [:]
        let previous = record["latestVersion"].flatMap(AppVersion.init)
        let notes = notesForVersion(installedVersion).flatMap { $0.highlights.isEmpty ? nil : $0 }

        if let previous, current <= previous {
            if current == previous, record["pendingVersion"] == installedVersion {
                pendingNotes = notes
            }
            return
        }

        // Record the running version even if the settings window is never opened.
        if previous != nil || hasPreviousUse {
            pendingNotes = notes
        }
        record["latestVersion"] = installedVersion
        record["pendingVersion"] = pendingNotes?.version
        userDefaults.set(record, forKey: Self.storageKey)
    }

    func dismiss() {
        guard let pendingNotes else { return }
        if var record = userDefaults.dictionary(forKey: Self.storageKey) as? [String: String],
           record["pendingVersion"] == pendingNotes.version {
            record.removeValue(forKey: "pendingVersion")
            userDefaults.set(record, forKey: Self.storageKey)
        }
        self.pendingNotes = nil
    }
}

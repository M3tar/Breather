import Foundation
import Combine

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case simplifiedChinese = "zh-Hans"
    case traditionalChinese = "zh-Hant"
    case english = "en"

    static let preferenceKey = "breather.language"
    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: L.tr("跟随系统", context: "language")
        case .simplifiedChinese: "简体中文"
        case .traditionalChinese: "繁體中文"
        case .english: "English"
        }
    }

    static var selected: AppLanguage {
        AppLanguage(rawValue: UserDefaults.standard.string(forKey: preferenceKey) ?? "system") ?? .system
    }

    static var effective: AppLanguage {
        if selected != .system { return selected }
        let preferred = UserDefaults.standard.stringArray(forKey: "AppleLanguages") ?? Locale.preferredLanguages
        return resolve(preferredLanguages: preferred)
    }

    static func resolve(preferredLanguages: [String]) -> AppLanguage {
        for language in preferredLanguages {
            let code = language.lowercased().replacingOccurrences(of: "_", with: "-")
            if code.hasPrefix("zh-hant") || code.hasPrefix("zh-tw")
                || code.hasPrefix("zh-hk") || code.hasPrefix("zh-mo") {
                return .traditionalChinese
            }
            if code.hasPrefix("zh") { return .simplifiedChinese }
            if code.hasPrefix("en") { return .english }
        }
        return .simplifiedChinese
    }
}

@MainActor
final class LocalizationRefresh: ObservableObject {
    static let shared = LocalizationRefresh()
    @Published private(set) var revision = 0

    private var lastLanguage = AppLanguage.effective
    private var lastSelection = AppLanguage.selected

    func refresh() {
        let language = AppLanguage.effective
        let selection = AppLanguage.selected
        guard language != lastLanguage || selection != lastSelection else { return }
        lastLanguage = language
        lastSelection = selection
        revision &+= 1
    }
}

enum L {
    private static var resources: Bundle {
        #if SWIFT_PACKAGE
        Bundle.module
        #else
        Bundle.main
        #endif
    }

    private static let localizedBundles: [String: Bundle] = {
        var bundles: [String: Bundle] = [:]
        for language in [AppLanguage.traditionalChinese.rawValue, AppLanguage.english.rawValue] {
            if let path = resources.path(forResource: language, ofType: "lproj"),
               let bundle = Bundle(path: path) {
                bundles[language] = bundle
            }
        }
        return bundles
    }()

    static func tr(_ source: String, context: String? = nil, language selectedLanguage: AppLanguage = .effective) -> String {
        let language = (selectedLanguage == .system ? AppLanguage.effective : selectedLanguage).rawValue
        guard let bundle = localizedBundles[language] else { return source }
        // A valid translation can equal the source (for example “通知” in zh-Hant).
        let missing = "\u{E000}Breather.missing.translation"
        if let context {
            let translated = bundle.localizedString(forKey: "\(source).\(context)", value: missing, table: nil)
            if translated != missing { return translated }
        }
        let translated = bundle.localizedString(forKey: source, value: missing, table: nil)
        if translated != missing { return translated }
        return dynamic(source, language: language) ?? source
    }

    private static func dynamic(_ source: String, language: String) -> String? {
        for entry in dynamicEntries {
            guard let match = entry.regex.firstMatch(in: source, range: NSRange(source.startIndex..., in: source)),
                  match.range.length == (source as NSString).length else { continue }
            let template = language == "en" ? entry.english : entry.traditional
            var result = template
            for index in 1..<match.numberOfRanges {
                if let range = Range(match.range(at: index), in: source) {
                    result = result.replacingOccurrences(of: "{\(index - 1)}", with: String(source[range]))
                }
            }
            return result
        }
        return nil
    }

    private struct DynamicEntry {
        let regex: NSRegularExpression
        let english: String
        let traditional: String

        init(pattern: String, english: String, traditional: String) {
            // These patterns are source constants; compile once, not on each lookup.
            regex = try! NSRegularExpression(pattern: pattern)
            self.english = english
            self.traditional = traditional
        }
    }

    // Dynamic strings are assembled outside SwiftUI; keep their word order here.
    private static let dynamicEntries: [DynamicEntry] = [
        .init(pattern: #"^工作结束后，休息 (\d+) 秒$"#, english: "After work, take a {0}-second break", traditional: "工作結束後，休息 {0} 秒"),
        .init(pattern: #"^(\d+) 分钟$"#, english: "{0} min", traditional: "{0} 分鐘"),
        .init(pattern: #"^(\d+) 秒$"#, english: "{0} sec", traditional: "{0} 秒"),
        .init(pattern: #"^(\d+) 小时$"#, english: "{0} hr", traditional: "{0} 小時"),
        .init(pattern: #"^(\d+) 分 (\d+) 秒$"#, english: "{0} min {1} sec", traditional: "{0} 分 {1} 秒"),
        .init(pattern: #"^完整 (\d+) 分钟工作周期$"#, english: "a full {0}-minute work session", traditional: "完整的 {0} 分鐘工作時段"),
        .init(pattern: #"^暂停 (\d+)m$"#, english: "Paused {0}m", traditional: "暫停 {0} 分鐘"),
        .init(pattern: #"^已暂停 · (.+)后重新开始$"#, english: "Paused · resumes in {0}", traditional: "已暫停 · {0} 後重新開始"),
        .init(pattern: #"^(.+)后重新开始完整工作周期$"#, english: "A full work session starts in {0}", traditional: "{0} 後重新開始完整工作時段"),
        .init(pattern: #"^(.+)后补休$"#, english: "Break in {0}", traditional: "{0} 後補休"),
        .init(pattern: #"^将在(.+)后重新开始$"#, english: "Resumes in {0}", traditional: "將在 {0} 後重新開始"),
        .init(pattern: #"^(.+)后重新开始$"#, english: "Resume after {0}", traditional: "{0} 後重新開始"),
        .init(pattern: #"^已设置在(.+)后自动恢复，可修改时间$"#, english: "Set to resume in {0}. Choose another time if needed.", traditional: "已設定在 {0} 後自動恢復，可修改時間"),
        .init(pattern: #"^自动恢复 (.+)$"#, english: "Resume in {0}", traditional: "{0} 後自動恢復"),
        .init(pattern: #"^延后 (.+)$"#, english: "Snooze for {0}", traditional: "延後 {0}"),
        .init(pattern: #"^发现新版本 v(.+)，前往 GitHub 下载$"#, english: "Version {0} is available. Download it from GitHub.", traditional: "發現新版本 v{0}，前往 GitHub 下載"),
        .init(pattern: #"^发现新版本 v(.+)，可前往 GitHub 手动下载。$"#, english: "Version {0} is available on GitHub for manual download.", traditional: "發現新版本 v{0}，可前往 GitHub 手動下載。"),
        .init(pattern: #"^(.+)（构建 (.+)）$"#, english: "{0} (build {1})", traditional: "{0}（建置 {1}）"),
        .init(pattern: #"^屏幕镜像中，休息提醒已暂停。当前工作计时停在 (.+)。结束镜像后自动重新开始(.+)$"#, english: "Screen mirroring is on. Break reminders are paused at {0}. {1} starts when mirroring ends.", traditional: "螢幕鏡像輸出中，休息提醒已暫停於 {0}。結束鏡像輸出後，將自動開始{1}。"),
    ]
}

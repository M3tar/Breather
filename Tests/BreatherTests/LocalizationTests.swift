import XCTest
@testable import Breather

@MainActor
final class LocalizationTests: XCTestCase {
    func testPauseStatusKeepsTranslationsAfterRemovingMiddleDot() {
        XCTAssertEqual(L.tr("已暂停，30 min后重新开始", language: .english), "Paused, resumes in 30 min")
        XCTAssertEqual(L.tr("已暂停，30 分鐘后重新开始", language: .traditionalChinese), "已暫停，30 分鐘 後重新開始")
        for language in [AppLanguage.simplifiedChinese, .traditionalChinese, .english] {
            for source in ["屏幕镜像中，休息提醒已暂停", "已暂停，直到手动继续", "已暂停，30 分钟后重新开始"] {
                XCTAssertFalse(L.tr(source, language: language).contains("·"))
            }
        }
    }

    func testFreshLanguagePreferenceFollowsSystemAndRemembersExplicitChoice() {
        let defaults = UserDefaults.standard
        let previous = defaults.string(forKey: AppLanguage.preferenceKey)
        defer {
            if let previous {
                defaults.set(previous, forKey: AppLanguage.preferenceKey)
            } else {
                defaults.removeObject(forKey: AppLanguage.preferenceKey)
            }
        }
        defaults.removeObject(forKey: AppLanguage.preferenceKey)
        XCTAssertEqual(AppLanguage.selected, .system)
        defaults.set(AppLanguage.english.rawValue, forKey: AppLanguage.preferenceKey)
        XCTAssertEqual(AppLanguage.selected, .english)
        defaults.set(AppLanguage.system.rawValue, forKey: AppLanguage.preferenceKey)
        XCTAssertEqual(AppLanguage.selected, .system)
    }

    func testSupportedSystemLanguagesAndFallback() {
        XCTAssertEqual(AppLanguage.resolve(preferredLanguages: ["zh-TW"]), .traditionalChinese)
        XCTAssertEqual(AppLanguage.resolve(preferredLanguages: ["zh-HK"]), .traditionalChinese)
        XCTAssertEqual(AppLanguage.resolve(preferredLanguages: ["en-US"]), .english)
        XCTAssertEqual(AppLanguage.resolve(preferredLanguages: ["fr-FR"]), .simplifiedChinese)
    }

    func testIdenticalTranslationsAndDynamicFallback() {
        XCTAssertEqual(L.tr("通知", language: .traditionalChinese), "通知")
        XCTAssertEqual(L.tr("37 分钟", language: .english), "37 min")
        XCTAssertEqual(L.tr("37 分 8 秒", language: .traditionalChinese), "37 分 8 秒")
        XCTAssertEqual(L.tr("未收录的文本", language: .english), "未收录的文本")
    }

    func testContextSeparatesLanguageAndAppearanceAndPreservesFallback() {
        XCTAssertEqual(L.tr("跟随系统", context: "language", language: .english), "System default")
        XCTAssertEqual(L.tr("跟随系统", context: "appearance", language: .english), "Match system")
        for context in ["language", "appearance"] {
            XCTAssertEqual(L.tr("跟随系统", context: context, language: .traditionalChinese), "跟隨系統")
            XCTAssertEqual(L.tr("跟随系统", context: context, language: .simplifiedChinese), "跟随系统")
        }
        XCTAssertEqual(L.tr("通知", context: "missing", language: .english), "Notifications")
        XCTAssertEqual(L.tr("未收录的文本", context: "missing", language: .english), "未收录的文本")
    }

    func testUnchangedLanguageDoesNotPublishAnotherRefresh() {
        let refresh = LocalizationRefresh()
        let revision = refresh.revision
        refresh.refresh()
        refresh.refresh()
        XCTAssertEqual(refresh.revision, revision)
    }

    func testRestCopyChangesLanguageWithoutRerollingPrompt() {
        let oldValue = UserDefaults.standard.string(forKey: AppLanguage.preferenceKey)
        defer {
            if let oldValue {
                UserDefaults.standard.set(oldValue, forKey: AppLanguage.preferenceKey)
            } else {
                UserDefaults.standard.removeObject(forKey: AppLanguage.preferenceKey)
            }
        }

        UserDefaults.standard.set(AppLanguage.simplifiedChinese.rawValue, forKey: AppLanguage.preferenceKey)
        var settings = AppSettings()
        settings.restOverlayPrompt = .random
        settings.restOverlaySubtitle = .none
        let copy = RestOverlayCopy(settings: settings)
        let selectedPrompt = try? XCTUnwrap(copy.prompt)
        XCTAssertTrue(RestOverlayPrompt.fixedCases.contains { $0.title == selectedPrompt })

        UserDefaults.standard.set(AppLanguage.english.rawValue, forKey: AppLanguage.preferenceKey)
        let englishPrompt = copy.prompt
        XCTAssertEqual(englishPrompt, L.tr(selectedPrompt ?? "", language: .english))
        XCTAssertNotEqual(englishPrompt, selectedPrompt)
    }
}

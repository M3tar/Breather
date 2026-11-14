import AppKit
import SwiftUI
import XCTest
@testable import Breather

@MainActor
final class SettingsPresentationTests: XCTestCase {
    func testAuthorizedNotificationPermissionOffersRefreshAndTest() {
        let presentation = NotificationPermissionPresentation(status: .authorized)

        XCTAssertEqual(presentation.statusText, "已授权")
        XCTAssertFalse(presentation.statusSymbol.isEmpty)
        XCTAssertEqual(presentation.actions, [.testNotification, .refresh])
    }

    func testDisabledNotificationAlertsOfferSettingsAndRefresh() {
        let presentation = NotificationPermissionPresentation(status: .alertsDisabled)

        XCTAssertEqual(presentation.statusText, "桌面提醒已关闭")
        XCTAssertFalse(presentation.statusSymbol.isEmpty)
        XCTAssertEqual(presentation.actions, [.openSettings, .refresh])
    }

    func testDeniedNotificationPermissionOffersSettingsAndRefresh() {
        let presentation = NotificationPermissionPresentation(status: .denied)

        XCTAssertEqual(presentation.statusText, "未授权")
        XCTAssertFalse(presentation.statusSymbol.isEmpty)
        XCTAssertEqual(presentation.actions, [.openSettings, .refresh])
    }

    func testUndeterminedNotificationPermissionMatchesDeniedPresentation() {
        let presentation = NotificationPermissionPresentation(status: .notDetermined)

        XCTAssertEqual(presentation.statusText, "未授权")
        XCTAssertFalse(presentation.statusSymbol.isEmpty)
        XCTAssertEqual(presentation, NotificationPermissionPresentation(status: .denied))
    }

    func testNotificationPermissionLoadingStateHasNoConflictingActions() {
        let presentation = NotificationPermissionPresentation(status: nil)

        XCTAssertEqual(presentation.statusText, "检测中…")
        XCTAssertFalse(presentation.statusSymbol.isEmpty)
        XCTAssertTrue(presentation.actions.isEmpty)
    }

    func testMenuBarCountdownSettingMapsAllValidStates() {
        var settings = AppSettings()

        MenuBarCountdownSetting.hidden.apply(to: &settings)
        XCTAssertEqual(MenuBarCountdownSetting(settings: settings), .hidden)

        MenuBarCountdownSetting.minutes.apply(to: &settings)
        XCTAssertEqual(MenuBarCountdownSetting(settings: settings), .minutes)

        MenuBarCountdownSetting.minutesAndSeconds.apply(to: &settings)
        XCTAssertEqual(MenuBarCountdownSetting(settings: settings), .minutesAndSeconds)
    }

    func testRestSkipSettingMapsAllValidStates() {
        var settings = AppSettings()

        for selection in RestSkipSetting.allCases {
            selection.apply(to: &settings)
            XCTAssertEqual(RestSkipSetting(settings: settings), selection)
        }
    }

    func testRestOverlayBackgroundSettingMapsAllValidStates() {
        var settings = AppSettings()

        for selection in RestOverlayBackgroundSetting.allCases {
            selection.apply(to: &settings)
            XCTAssertEqual(RestOverlayBackgroundSetting(settings: settings), selection)
        }
    }

    func testMenuBarIconSettingCombinesVisibilityAndStyle() {
        var settings = AppSettings()

        MenuBarIconSetting.hidden.apply(to: &settings)
        XCTAssertEqual(MenuBarIconSetting(settings: settings), .hidden)

        MenuBarIconSetting.icon(.breather04).apply(to: &settings)
        XCTAssertEqual(MenuBarIconSetting(settings: settings), .icon(.breather04))
    }

    func testLegacyCodexNotificationSoundIsNotSelectable() {
        XCTAssertFalse(RestSoundEffect.fixedCases.contains(.codexNotification))
        XCTAssertFalse(RestSoundEffect.selectableCases.contains(.codexNotification))
    }

    func testBundledNotificationSoundsUseSystemSupportedContainers() {
        let supportedExtensions = Set(["aiff", "wav", "caf"])

        for effect in RestSoundEffect.fixedCases {
            guard let fileName = effect.bundledNotificationSoundFileName else { continue }

            XCTAssertTrue(
                supportedExtensions.contains(URL(fileURLWithPath: fileName).pathExtension.lowercased()),
                "Unsupported notification sound resource: \(fileName)"
            )
        }
    }

    func testNotificationDeliveryVerifierRejectsAcceptedButUndeliveredRequest() async {
        let verifier = NotificationDeliveryVerifier(
            maximumAttempts: 3,
            retryInterval: .zero
        )

        let wasDelivered = await verifier.waitUntilDelivered(identifier: "preview") {
            []
        }

        XCTAssertFalse(wasDelivered)
    }

    func testNotificationDeliveryVerifierAcceptsOnlyMatchingDeliveredRequest() async {
        let verifier = NotificationDeliveryVerifier(
            maximumAttempts: 3,
            retryInterval: .zero
        )
        var attempt = 0

        let wasDelivered = await verifier.waitUntilDelivered(identifier: "preview") {
            attempt += 1
            return attempt < 2 ? ["another"] : ["preview"]
        }

        XCTAssertTrue(wasDelivered)
        XCTAssertEqual(attempt, 2)
    }
}

final class UpdateCheckerTests: XCTestCase {
    func testVersionComparisonHandlesPrereleasesAndNumericSegments() {
        XCTAssertLessThan(AppVersion("0.4.0-beta.2")!, AppVersion("0.4.0-beta.10")!)
        XCTAssertLessThan(AppVersion("0.4.0-rc.1")!, AppVersion("0.4.0")!)
        XCTAssertLessThan(AppVersion("0.9.0")!, AppVersion("0.10.0")!)
        XCTAssertNil(AppVersion("0.4.0-"))
    }

    func testReleaseSelectionExcludesPrereleasesDraftsAndMissingDMGs() throws {
        let releases: [[String: Any]] = [
            release("0.7.0", draft: true),
            release("0.6.0", prerelease: true),
            release("0.5.1-beta.1"),
            release("0.5.0", hasDMG: false),
            release("0.4.0")
        ]
        let data = try JSONSerialization.data(withJSONObject: releases)
        let result = try UpdateChecker.result(from: data, installedVersion: "0.3.0")
        guard case let .available(update) = result else { return XCTFail("Expected stable update") }
        XCTAssertEqual(update.version, "0.4.0")
        for installed in ["0.4.0", "0.5.0", "0.5.0-beta.1"] {
            guard case .upToDate = try UpdateChecker.result(from: data, installedVersion: installed) else {
                return XCTFail("Must not offer an older release")
            }
        }
    }

    private func release(_ version: String, draft: Bool = false, prerelease: Bool = false, hasDMG: Bool = true) -> [String: Any] {
        ["tag_name": "v\(version)", "html_url": "https://github.com/M3tar/Breather/releases/tag/v\(version)",
         "draft": draft, "prerelease": prerelease,
         "assets": hasDMG ? [["name": "Breather-\(version).dmg", "browser_download_url": "https://github.com/M3tar/Breather/releases/download/v\(version)/Breather-\(version).dmg"]] : []]
    }

}

@MainActor
final class UpdateMonitorTests: XCTestCase {
    func testAutomaticChecksAreAtMostOncePerDayAndManualChecksBypassTheLimit() async throws {
        let suiteName = "UpdateMonitorCadenceTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var currentDate = Date(timeIntervalSince1970: 1_700_000_000)
        var callCount = 0
        let monitor = UpdateMonitor(
            userDefaults: defaults,
            installedVersion: "0.3.0",
            now: { currentDate },
            checkRelease: { _ in
                callCount += 1
                return UpdateCheckResponse(.upToDate)
            }
        )

        await monitor.checkIfDue()
        await monitor.checkIfDue()
        currentDate.addTimeInterval(23 * 60 * 60)
        await monitor.checkIfDue()
        XCTAssertEqual(callCount, 1)

        currentDate.addTimeInterval(60 * 60)
        await monitor.checkIfDue()
        XCTAssertEqual(callCount, 2)

        await monitor.checkNow()
        XCTAssertEqual(callCount, 3)
    }

    func testAvailableUpdatePersistsAndNewerVersionReplacesIt() async throws {
        let suiteName = "UpdateMonitorDismissalTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let release = UpdateTestReleaseState(version: "0.4.0")
        let checkRelease: @MainActor (String) async throws -> UpdateCheckResponse = { _ in
            UpdateCheckResponse(.available(AvailableUpdate(
                version: release.version,
                releaseURL: URL(string: "https://github.com/M3tar/Breather/releases/tag/v\(release.version)")!
            )))
        }
        let monitor = UpdateMonitor(
            userDefaults: defaults,
            installedVersion: "0.3.0",
            checkRelease: checkRelease
        )

        await monitor.checkNow()
        XCTAssertEqual(monitor.availableUpdate?.version, "0.4.0")

        let reloaded = UpdateMonitor(
            userDefaults: defaults,
            installedVersion: "0.3.0",
            checkRelease: checkRelease
        )
        XCTAssertEqual(reloaded.availableUpdate?.version, "0.4.0")

        release.version = "0.5.0"
        await reloaded.checkNow()
        XCTAssertEqual(reloaded.availableUpdate?.version, "0.5.0")
    }

    func testAutomaticNetworkFailureKeepsTheLastKnownUpdate() async throws {
        let suiteName = "UpdateMonitorOfflineTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let release = UpdateTestReleaseState(version: "0.4.0")
        var currentDate = Date(timeIntervalSince1970: 1_700_000_000)
        let monitor = UpdateMonitor(
            userDefaults: defaults,
            installedVersion: "0.3.0",
            now: { currentDate },
            checkRelease: { _ in
                if release.shouldFail { throw URLError(.notConnectedToInternet) }
                return UpdateCheckResponse(.available(AvailableUpdate(
                    version: release.version,
                    releaseURL: URL(string: "https://github.com/M3tar/Breather/releases/tag/v0.4.0")!
                )))
            }
        )

        await monitor.checkNow()
        release.shouldFail = true
        currentDate.addTimeInterval(24 * 60 * 60)
        await monitor.checkIfDue()

        XCTAssertEqual(monitor.availableUpdate?.version, "0.4.0")
        guard case .available = monitor.status else {
            return XCTFail("Automatic failures should not replace the known update with an error")
        }
    }
}

@MainActor
private final class UpdateTestReleaseState {
    var version: String
    var shouldFail = false

    init(version: String) {
        self.version = version
    }
}

@MainActor
final class SettingsResetTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!
    private var store: SettingsStore!

    override func setUp() async throws {
        suite = "SettingsResetTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        store = SettingsStore(userDefaults: defaults)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
        store = nil
        defaults = nil
    }

    func testResetPreviewIsReadOnlyAndListsOnlyActualChanges() {
        store.rules.workDuration = 35 * 60
        store.rules.preBreakNotificationEnabled = false
        store.settings.appearancePreference = .dark
        store.settings.cloudTrainPlaybackSpeed = .normal
        let beforeSettings = store.settings
        let beforeRules = store.rules
        let persistedSettings = defaults.data(forKey: "breather.settings")
        let persistedRules = defaults.data(forKey: "breather.rules")
        let preview = SettingsResetPreview(scope: .schedule, settings: store.settings, rules: store.rules)
        XCTAssertEqual(preview.changes.map(\.id), ["workDuration", "preBreakNotificationEnabled"])
        XCTAssertEqual(store.settings, beforeSettings)
        XCTAssertEqual(store.rules, beforeRules)
        XCTAssertEqual(defaults.data(forKey: "breather.settings"), persistedSettings)
        XCTAssertEqual(defaults.data(forKey: "breather.rules"), persistedRules)
        store.restoreDefaults(for: .schedule)
        XCTAssertEqual(store.settings.cloudTrainPlaybackSpeed, .normal)
        XCTAssertTrue(SettingsResetPreview(scope: .schedule, settings: store.settings, rules: store.rules).changes.isEmpty)
    }

    func testResetPreviewDisclosesParametersForThemesThatAreNotSelected() {
        store.settings.cloudTrainPlaybackSpeed = .normal
        store.settings.cloudTrainForegroundSpeed = .half
        store.settings.curtainPalette = .warmLinen
        let preview = SettingsResetPreview(scope: .restOverlay, settings: store.settings, rules: store.rules)
        XCTAssertEqual(preview.changes.map(\.id),
                       ["cloudTrainPlaybackSpeed", "cloudTrainForegroundSpeed", "curtainPalette"])
        XCTAssertEqual(preview.changes.compactMap(\.group), [.theme(.cloudTrain), .theme(.cloudTrain), .theme(.curtain)])
        XCTAssertFalse(preview.changes.contains { $0.current == $0.restored })
        XCTAssertEqual(store.settings.restOverlayContentMode, .classic)

        store.settings.cloudTrainPlaybackSpeed = AppSettings().cloudTrainPlaybackSpeed
        store.settings.rainAmbienceEnabled = false
        let single = SettingsResetPreview(scope: .restOverlay, settings: store.settings, rules: store.rules)
        XCTAssertEqual(single.changes.compactMap(\.group), [.theme(.cloudTrain), .theme(.curtain), .theme(.rainy)])
        XCTAssertEqual(single.changes.first?.title, L.tr("前景云层速度"))
    }

    func testResetPreviewGroupsScheduleChangesWithoutRepeatingParentTitles() {
        store.rules.preBreakNotificationOffset = 45
        store.settings.automaticRestThreshold = 600
        let children = SettingsResetPreview(scope: .schedule, settings: store.settings, rules: store.rules)
        XCTAssertEqual(children.changes.compactMap(\.group), [.advanceReminder, .automaticRest])
        XCTAssertEqual(children.changes.compactMap(\.title), [L.tr("提前时间"), L.tr("至少持续")])
        XCTAssertEqual(children.changes[0].contextHeading(after: nil), .advanceReminder)
        XCTAssertEqual(children.changes[1].contextHeading(after: children.changes[0]), .automaticRest)

        store.rules.preBreakNotificationEnabled = false
        store.settings.automaticRestMode = .disabled
        let grouped = SettingsResetPreview(scope: .schedule, settings: store.settings, rules: store.rules)
        XCTAssertEqual(grouped.changes.compactMap(\.group),
                       [.advanceReminder, .advanceReminder, .automaticRest, .automaticRest])
        XCTAssertEqual(grouped.changes.map(\.title), [nil, L.tr("提前时间"), nil, L.tr("至少持续")])
        XCTAssertNil(grouped.changes[0].contextHeading(after: nil))
        XCTAssertNil(grouped.changes[1].contextHeading(after: grouped.changes[0]))
        XCTAssertNil(grouped.changes[3].contextHeading(after: grouped.changes[2]))
    }

    func testStandaloneThemeParameterKeepsItsContext() throws {
        store.settings.restOverlayBackground = .moon
        let preview = SettingsResetPreview(scope: .restOverlay, settings: store.settings, rules: store.rules)
        let change = try XCTUnwrap(preview.changes.first)
        XCTAssertEqual(preview.changes.count, 1)
        XCTAssertEqual(change.contextHeading(after: nil), .theme(.classic))
    }

    func testRestResetColumnsFallBackWhenLocalizedValuesDoNotFit() {
        let language = UserDefaults.standard.string(forKey: AppLanguage.preferenceKey)
        defer { UserDefaults.standard.set(language, forKey: AppLanguage.preferenceKey) }
        UserDefaults.standard.set(AppLanguage.english.rawValue, forKey: AppLanguage.preferenceKey)
        store.settings.restOverlayContentMode = .cloudTrain
        store.settings.cloudTrainForegroundSpeed = .normal
        let short = SettingsResetPreview(scope: .restOverlay, settings: store.settings, rules: store.rules)
        XCTAssertNotNil(SettingsResetColumns(changes: short.changes, width: 452).labelWidth)

        store.settings.restOverlaySubtitle = .leaveScreen
        let long = SettingsResetPreview(scope: .restOverlay, settings: store.settings, rules: store.rules)
        XCTAssertNil(SettingsResetColumns(changes: long.changes, width: 452).labelWidth)
        let columns = SettingsResetColumns(changes: long.changes, width: 408)
        XCTAssertEqual(SettingsResetColumns.indent + columns.currentValueWidth(leadingInset: SettingsResetColumns.indent),
                       columns.currentValueWidth(leadingInset: 0), accuracy: 0.001,
                       "Indenting a child must not move the restored value column")
    }

    func testResetPreviewUsesCombinedMenuBarOptions() {
        store.settings.showMenuBarIcon = false
        store.settings.menuBarIcon = .breather04
        store.settings.showCountdownInMenuBar = false
        store.settings.showSeconds = false
        let preview = SettingsResetPreview(scope: .menuBar, settings: store.settings, rules: store.rules)
        XCTAssertEqual(preview.changes.map(\.id), ["menuBarIcon", "showCountdownInMenuBar"])
        XCTAssertEqual(preview.changes.map(\.current), [L.tr("不显示"), L.tr("不显示")])
        XCTAssertEqual(preview.changes.map(\.restored), [AppSettings().menuBarIcon.title, L.tr("分钟和秒")])
        store.settings.showCountdownInMenuBar = true
        let minutes = SettingsResetPreview(scope: .menuBar, settings: store.settings, rules: store.rules)
        XCTAssertEqual(minutes.changes.last?.current, MenuBarCountdownSetting.minutes.title)
        for scope in SettingsResetScope.allCases {
            XCTAssertTrue(SettingsResetPreview(scope: scope, settings: AppSettings(), rules: BreakRules()).changes.isEmpty)
        }
    }

    func testResetPreviewUsesCombinedRestBackgroundAndSoundOptions() {
        store.settings.restOverlayBackground = .solid
        store.settings.restOverlayTranslucentBackground = true
        store.settings.playRestStartSound = false
        store.settings.restStartSoundEffect = .stardewAchievement
        store.settings.restEndSoundEffect = .codexNotification
        let preview = SettingsResetPreview(scope: .restOverlay, settings: store.settings, rules: store.rules)
        XCTAssertEqual(preview.changes.map(\.id), ["restOverlayBackground", "restStartSoundEffect", "restEndSoundEffect"])
        XCTAssertEqual(preview.changes.map(\.current), [L.tr("半透明纯色"), L.tr("无"), L.tr("无")])
        XCTAssertEqual(preview.changes.map(\.restored),
                       [L.tr("太阳"), AppSettings().restStartSoundEffect.title, AppSettings().restEndSoundEffect.title])
        XCTAssertNil(preview.effectNote(isResting: false))
        XCTAssertNotNil(preview.effectNote(isResting: true))

        store.settings.restOverlayTranslucentBackground = false
        store.settings.restOverlayBackground = .sun
        let soundOnly = SettingsResetPreview(scope: .restOverlay, settings: store.settings, rules: store.rules)
        XCTAssertNil(soundOnly.effectNote(isResting: true))
    }

    func testResetPreviewOnlyExplainsDeferredRulesWhenRelevant() {
        func note() -> String? {
            SettingsResetPreview(scope: .schedule, settings: store.settings, rules: store.rules)
                .effectNote(isResting: false)
        }

        store.settings.allowSkip = false
        XCTAssertNil(note())

        store.rules.preBreakNotificationEnabled = false
        XCTAssertTrue(store.currentCycleRules.preBreakNotificationEnabled)
        XCTAssertEqual(note(), L.tr("休息前通知将在下个周期生效。"))
        store.rules.preBreakNotificationEnabled = true

        store.rules.workDuration = 35 * 60
        XCTAssertEqual(note(), L.tr("时长将在下个周期生效。"))
        store.activateSavedRulesForCurrentCycle()
        XCTAssertEqual(note(), L.tr("时长将在下个周期生效。"))

        store.rules.preBreakNotificationEnabled = false
        XCTAssertEqual(note(), L.tr("时长和休息前通知将在下个周期生效。"))
        store.activateSavedRulesForCurrentCycle()
        XCTAssertEqual(note(), L.tr("时长和休息前通知将在下个周期生效。"))

        store.rules.workDuration = BreakRules().workDuration
        XCTAssertEqual(note(), L.tr("休息前通知将在下个周期生效。"))
        store.activateSavedRulesForCurrentCycle()
        XCTAssertEqual(note(), L.tr("休息前通知将在下个周期生效。"))

        store.rules.preBreakNotificationEnabled = true
        store.rules.preBreakNotificationOffset = 45
        XCTAssertEqual(note(), L.tr("休息前通知将在下个周期生效。"))
    }

    func testResetInkUsesTheSameStrokeGeometryAcrossAppearances() throws {
        let settingID = "restOverlayContentMode"
        let shortSize = CGSize(width: 20, height: 16)
        let wideSize = CGSize(width: 80, height: 16)
        let ink = LooseleafResetInk.shared
        XCTAssertEqual(ink.drawing(settingID: settingID, size: shortSize, colorScheme: .light).strokes.count, 1)

        let light = ink.drawing(settingID: settingID, size: wideSize, colorScheme: .light).strokes
        let dark = ink.drawing(settingID: settingID, size: wideSize, colorScheme: .dark).strokes
        XCTAssertEqual(light.count, 2)
        XCTAssertEqual(light.count, dark.count)
        XCTAssertEqual(light.map(\.timing), dark.map(\.timing))
        XCTAssertEqual(light.map(\.horizontalExtent), dark.map(\.horizontalExtent))
        for (a, b) in zip(light, dark) {
            let lightInk = try XCTUnwrap(a.image.dataProvider?.data) as Data
            let darkInk = try XCTUnwrap(b.image.dataProvider?.data) as Data
            XCTAssertNotEqual(lightInk, darkInk)
            let lightAlpha = stride(from: 3, to: lightInk.count, by: 4).map { lightInk[$0] }
            let darkAlpha = stride(from: 3, to: darkInk.count, by: 4).map { darkInk[$0] }
            XCTAssertEqual(lightAlpha, darkAlpha)
        }
    }

    func testReceiptCorrectionsOverlapPrintingAndStayBoundedForLongLists() {
        for index in 0..<100 {
            let start = SettingsResetPaperFeed.correctionStart + SettingsResetPaperFeed.correctionDelay(for: index)
            XCTAssertLessThan(start, SettingsResetPaperFeed.duration)
            XCTAssertLessThanOrEqual(start + SettingsResetPaperFeed.correctionDuration, 0.600)
        }
        XCTAssertEqual(SettingsResetPaperFeed.correctionDelay(for: 2),
                       SettingsResetPaperFeed.correctionDelay(for: 99))
    }

    func testResetPreviewLocalizesDurationFormatsInEachLanguage() {
        let previous = UserDefaults.standard.string(forKey: AppLanguage.preferenceKey)
        defer { UserDefaults.standard.set(previous, forKey: AppLanguage.preferenceKey) }

        store.rules.workDuration = 35 * 60
        store.rules.shortBreakDuration = 45
        store.rules.longBreakDuration = 5 * 60 + 8
        let examples: [(AppLanguage, [String], [String])] = [
            (.simplifiedChinese, ["35 分钟", "45 秒", "5 分 8 秒"], ["30 分钟", "30 秒", "5 分钟"]),
            (.traditionalChinese, ["35 分鐘", "45 秒", "5 分 8 秒"], ["30 分鐘", "30 秒", "5 分鐘"]),
            (.english, ["35 min", "45 sec", "5 min 8 sec"], ["30 min", "30 sec", "5 min"]),
        ]
        for (language, current, restored) in examples {
            UserDefaults.standard.set(language.rawValue, forKey: AppLanguage.preferenceKey)
            let preview = SettingsResetPreview(scope: .schedule, settings: store.settings, rules: store.rules)
            XCTAssertEqual(preview.changes.map(\.current), current)
            XCTAssertEqual(preview.changes.map(\.restored), restored)
        }
    }

    func testResetSheetRenderingAndAnimationDoesNotApplyChanges() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["BREATHER_WINDOW_TEST"] == "1")
        let language = UserDefaults.standard.string(forKey: AppLanguage.preferenceKey)
        defer {
            if let language { UserDefaults.standard.set(language, forKey: AppLanguage.preferenceKey) }
            else { UserDefaults.standard.removeObject(forKey: AppLanguage.preferenceKey) }
        }
        store.rules.workDuration = 32 * 60
        store.rules.shortBreakDuration = 33
        store.rules.preBreakNotificationEnabled = false
        store.rules.preBreakNotificationOffset = 23
        store.settings.automaticRestMode = .lockSleepOrIdle
        store.settings.automaticRestThreshold = 9 * 60
        store.settings.autoPauseDuringDisplayMirroring = false
        store.settings.showSeconds = false
        store.settings.menuBarPopoverThemeColor = .mistBlue
        store.settings.restOverlayContentMode = .cloudTrain
        store.settings.cloudTrainPlaybackSpeed = .normal
        store.settings.cloudTrainForegroundSpeed = .normal
        store.settings.curtainPalette = .warmLinen
        store.settings.restOverlayPrompt = .none
        store.settings.restOverlaySubtitle = .none
        store.settings.rainAmbienceEnabled = false
        let beforeSettings = store.settings
        let beforeRules = store.rules
        let directory = URL(fileURLWithPath: "/tmp/BreatherResetAnimation")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var restores = 0
        for lang in [AppLanguage.simplifiedChinese, .traditionalChinese, .english] {
            UserDefaults.standard.set(lang.rawValue, forKey: AppLanguage.preferenceKey)
            for (index, scope) in SettingsResetScope.allCases.enumerated() {
                var renderSettings = store.settings
                if lang == .english && scope == .restOverlay {
                    // Keep the long value visible in the snapshot of the stacked layout.
                    renderSettings = AppSettings()
                    renderSettings.restOverlayContentMode = .cloudTrain
                    renderSettings.cloudTrainForegroundSpeed = .normal
                    renderSettings.curtainPalette = .warmLinen
                    renderSettings.restOverlaySubtitle = .leaveScreen
                }
                let preview = SettingsResetPreview(scope: scope, settings: renderSettings, rules: store.rules)
                for appearance in [ColorScheme.light, .dark] {
                    let host = NSHostingView(rootView: SettingsResetSheet(preview: preview, onRestore: { restores += 1 })
                        .background(Color(nsColor: .windowBackgroundColor)).preferredColorScheme(appearance))
                    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 520),
                                          styleMask: [.titled], backing: .buffered, defer: false)
                    window.isReleasedWhenClosed = false
                    window.contentView = host
                    host.frame = NSRect(x: 0, y: 0, width: 500, height: 520)
                    host.layoutSubtreeIfNeeded()
                    window.orderFront(nil)
                    try await Task.sleep(for: .milliseconds(60))
                    var captures: [Data] = []
                    for frame in ["start", "feeding", "correcting", "complete"] {
                        if frame == "feeding" { try await Task.sleep(for: .milliseconds(120)) }
                        if frame == "correcting" { try await Task.sleep(for: .milliseconds(240)) }
                        if frame == "complete" { try await Task.sleep(for: .milliseconds(400)) }
                        host.layoutSubtreeIfNeeded()
                        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                        host.cacheDisplay(in: host.bounds, to: bitmap)
                        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                        captures.append(png)
                        try png.write(to: directory.appendingPathComponent("sheet-\(index)-\(lang.rawValue)-\(appearance)-\(frame).png"))
                    }
                    if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                        XCTAssertTrue(captures.allSatisfy { $0 == captures[0] }, "Reduced motion must display both values immediately")
                    } else {
                        XCTAssertNotEqual(captures[0], captures[1], "The paper must advance through an intermediate frame")
                        XCTAssertNotEqual(captures[1], captures[3], "The paper must not jump straight to the final frame")
                    }
                    window.contentView = nil
                    window.close()
                }
            }
        }
        XCTAssertEqual(restores, 0)
        XCTAssertEqual(store.settings, beforeSettings)
        XCTAssertEqual(store.rules, beforeRules)
    }

    func testDefaultDetectionIgnoresPreferencesFromOtherPages() {
        store.settings.appearancePreference = .dark
        store.settings.notificationSoundEnabled = false
        for scope in SettingsResetScope.allCases {
            XCTAssertTrue(store.isDefault(for: scope))
        }
        store.settings.cloudTrainPlaybackSpeed = .normal
        XCTAssertFalse(store.isDefault(for: .restOverlay))
        XCTAssertTrue(store.isDefault(for: .menuBar))
        XCTAssertTrue(store.isDefault(for: .schedule))
    }

    func testMenuBarResetRestoresDisplayAndStyleWithoutChangingOtherPages() {
        store.settings.appearancePreference = .dark
        store.settings.restOverlayContentMode = .cloudTrain
        store.settings.automaticRestThreshold = 600
        store.rules.workDuration = 1500
        let expected = store.settings
        let rules = store.rules
        store.settings.showMenuBarIcon = false
        store.settings.menuBarIcon = .breather04
        store.settings.showCountdownInMenuBar = false
        store.settings.showSeconds = false
        store.settings.menuBarPopoverAppearance = .dark
        store.settings.menuBarPopoverThemeColor = .mistBlue
        store.settings.menuBarPopoverProgressStyle = .radix
        store.settings.menuBarPopoverSquareStyle = .block
        store.settings.menuBarPopoverSquareColorMode = .neutral
        XCTAssertFalse(store.isDefault(for: .menuBar))
        store.restoreDefaults(for: .menuBar)
        XCTAssertEqual(store.settings, expected)
        XCTAssertEqual(store.rules, rules)
        XCTAssertEqual(SettingsStore(userDefaults: defaults).settings, expected)
        XCTAssertTrue(store.isDefault(for: .menuBar))
    }

    func testRestResetIncludesHiddenThemeParametersButKeepsAnActiveSession() {
        store.settings.showSeconds = false
        store.settings.notificationSoundEnabled = false
        let expected = store.settings
        store.settings.restOverlayContentMode = .cloudTrain
        store.settings.curtainPalette = .warmLinen
        store.settings.cloudTrainPlaybackSpeed = .normal
        store.settings.cloudTrainForegroundSpeed = .half
        store.settings.restOverlayPrompt = .none
        store.settings.restOverlaySubtitle = .none
        store.settings.restOverlayBackground = .linen
        store.settings.restOverlayFadeAnimation = false
        store.settings.restOverlayTranslucentBackground = true
        store.settings.rainAmbienceEnabled = false
        store.settings.playRestStartSound = false
        store.settings.playRestEndSound = false
        store.settings.restStartSoundEffect = .none
        store.settings.restEndSoundEffect = .none
        let session = RestOverlaySession(kind: .rest, settings: store.settings, totalSeconds: 30)
        store.restoreDefaults(for: .restOverlay)
        XCTAssertEqual(store.settings, expected)
        XCTAssertEqual(SettingsStore(userDefaults: defaults).settings, expected)
        XCTAssertTrue(store.isDefault(for: .restOverlay))
        XCTAssertEqual(session.contentMode, .cloudTrain)
        XCTAssertEqual(session.cloudTrainPlaybackSpeed, .normal)
        XCTAssertEqual(session.remainingSeconds, 30)
    }

    func testScheduleResetKeepsPausedCountdownAndDefersRulesUntilNextCycle() {
        store.settings.restOverlayContentMode = .cloudTrain
        store.settings.showSeconds = false
        let expected = store.settings
        store.rules.workDuration = 1500
        store.rules.shortBreakDuration = 90
        store.rules.preBreakNotificationEnabled = false
        store.activateSavedRulesForCurrentCycle()
        store.settings.ruleChangeEffect = .immediate
        store.settings.allowSkip = false
        store.settings.allowEscToSkip = false
        store.settings.strictMode = true
        store.settings.snoozeDuration = 600
        store.settings.recoveryNudgeThreshold = 5
        store.settings.automaticRestMode = .disabled
        store.settings.automaticRestThreshold = 600
        store.settings.autoPauseDuringDisplayMirroring = false
        let scheduler = BreakScheduler(settingsStore: store, notificationService: ResetTestNotifications(),
                                       idleMonitor: ResetTestIdle(),
                                       pauseResumeSessionStore: PauseResumeSessionStore(userDefaults: defaults))
        scheduler.tick()
        scheduler.togglePause()
        let remaining = scheduler.remainingSeconds
        let currentRules = store.currentCycleRules
        store.restoreDefaults(for: .schedule)
        XCTAssertEqual(store.settings, expected)
        XCTAssertEqual(store.rules, BreakRules())
        XCTAssertEqual(store.currentCycleRules, currentRules)
        XCTAssertTrue(store.hasPendingRuleChanges)
        XCTAssertEqual(scheduler.state, .paused)
        XCTAssertEqual(scheduler.remainingSeconds, remaining)
        let reloaded = SettingsStore(userDefaults: defaults)
        XCTAssertEqual(reloaded.settings, expected)
        XCTAssertEqual(reloaded.rules, BreakRules())
        XCTAssertTrue(store.isDefault(for: .schedule))
        scheduler.continueUserPause()
        scheduler.tick()
        XCTAssertEqual(scheduler.remainingSeconds, remaining - 1)
        scheduler.resetWorkCycle()
        XCTAssertEqual(store.currentCycleRules, BreakRules())
    }
}

@MainActor
private final class ResetTestNotifications: BreakNotificationSending {
    func sendPreBreakNotification(playSound: Bool, soundEffect: RestSoundEffect) {}
}
private final class ResetTestIdle: IdleTimeProviding { var idleSeconds: TimeInterval = 0 }

@MainActor
final class SettingsToastTests: XCTestCase {
    func testSuccessExpiresAndDoesNotReplayOnReturn() async throws {
        let feedback = SettingsToastPresenter(successDuration: .milliseconds(20))
        feedback.appear()
        feedback.show(SettingsToastMessage(text: UpdateStatus.upToDate.message))
        XCTAssertEqual(feedback.message?.text, UpdateStatus.upToDate.message)
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertNil(feedback.message)
        feedback.show(SettingsToastMessage(text: UpdateStatus.upToDate.message))
        feedback.disappear()
        feedback.receive(.failed("late response"))
        feedback.appear()
        XCTAssertNil(feedback.message)
        feedback.disappear()
    }

    func testFailureLastsLongerAndReplacementCancelsPreviousTimer() async throws {
        let feedback = SettingsToastPresenter(successDuration: .milliseconds(20), failureDuration: .milliseconds(200))
        feedback.appear()
        feedback.show(SettingsToastMessage(text: UpdateStatus.upToDate.message))
        feedback.show(SettingsToastMessage(text: "offline", isError: true))
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(feedback.message?.text, "offline")
        XCTAssertEqual(feedback.message?.isError, true)
        try await Task.sleep(for: .milliseconds(180))
        XCTAssertNil(feedback.message)
        feedback.show(SettingsToastMessage(text: "offline", isError: true))
        feedback.dismiss()
        XCTAssertNil(feedback.message)
        feedback.show(SettingsToastMessage(text: UpdateStatus.upToDate.message))
        feedback.receive(.checking)
        XCTAssertNil(feedback.message)
        feedback.show(SettingsToastMessage(text: "Logs cleared"))
        feedback.show(nil)
        XCTAssertNil(feedback.message)
        feedback.disappear()
    }

    func testHoverPausesAndResumesOnlyTheRemainingTime() async throws {
        var now = ContinuousClock().now
        let feedback = SettingsToastPresenter(successDuration: .seconds(3), now: { now })
        feedback.appear()
        feedback.show(SettingsToastMessage(text: UpdateStatus.upToDate.message))
        now = now.advanced(by: .milliseconds(2800))
        feedback.setHovered(true)
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertNotNil(feedback.message)
        feedback.setHovered(false)
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertNil(feedback.message, "Resuming should use the remaining 200 ms, not a fresh three seconds")
        feedback.disappear()
    }

    func testReplacementWhileHoveredAndLeavingPageCancelPendingTimers() async throws {
        let feedback = SettingsToastPresenter(successDuration: .milliseconds(20), failureDuration: .milliseconds(80))
        feedback.appear()
        feedback.show(SettingsToastMessage(text: UpdateStatus.upToDate.message))
        feedback.setHovered(true)
        feedback.show(SettingsToastMessage(text: "latest failure", isError: true))
        try await Task.sleep(for: .milliseconds(140))
        XCTAssertEqual(feedback.message?.text, "latest failure")
        feedback.setHovered(false)
        try await Task.sleep(for: .milliseconds(140))
        XCTAssertNil(feedback.message)
        feedback.show(SettingsToastMessage(text: "offline", isError: true))
        feedback.setHovered(true)
        feedback.disappear()
        feedback.appear()
        feedback.show(SettingsToastMessage(text: UpdateStatus.upToDate.message))
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertNil(feedback.message, "A previous page's hover state must not pause a new result")
        feedback.disappear()
    }

    func testLateUpdateResultDoesNotAppearAfterLeavingAndReturning() {
        let feedback = SettingsToastPresenter()
        feedback.appear()
        feedback.receive(.checking)
        feedback.disappear()
        feedback.appear()
        feedback.receive(.failed("previous visit"))
        XCTAssertNil(feedback.message)
        feedback.receive(.checking)
        feedback.receive(.upToDate)
        XCTAssertEqual(feedback.message?.text, UpdateStatus.upToDate.message)
        feedback.disappear()
        feedback.receive(.checking)
        feedback.appear()
        feedback.receive(.failed("started off page"))
        XCTAssertNil(feedback.message)
        feedback.disappear()
    }

    func testAvailableUpdateIsNotAnExpiringToast() {
        let feedback = SettingsToastPresenter()
        feedback.appear()
        let update = AvailableUpdate(version: "0.6.0", releaseURL: URL(string: "https://github.com/M3tar/Breather/releases/tag/v0.6.0")!)
        feedback.show(SettingsToastMessage(text: UpdateStatus.upToDate.message))
        feedback.receive(.checking)
        feedback.receive(.available(update))
        XCTAssertNil(feedback.message)
        feedback.disappear()
    }
}

import Foundation
import XCTest
@testable import Breather

@MainActor
final class BreakSchedulerPauseAndMirroringTests: XCTestCase {
    private var userDefaults: UserDefaults!
    private var suiteName: String!
    private var settingsStore: SettingsStore!
    private var sessionStore: PauseResumeSessionStore!
    private var notificationService: TestNotificationService!
    private var idleMonitor: TestIdleMonitor!
    private var clock: TestClock!

    override func setUp() async throws {
        suiteName = "BreakSchedulerPauseAndMirroringTests.\(UUID().uuidString)"
        userDefaults = UserDefaults(suiteName: suiteName)
        userDefaults.removePersistentDomain(forName: suiteName)
        settingsStore = SettingsStore(userDefaults: userDefaults)
        sessionStore = PauseResumeSessionStore(userDefaults: userDefaults)
        notificationService = TestNotificationService()
        idleMonitor = TestIdleMonitor()
        clock = TestClock(now: Date(timeIntervalSince1970: 1_800_000_000))

        settingsStore.rules.workDuration = 20 * 60
        settingsStore.rules.shortBreakDuration = 30
        settingsStore.rules.preBreakNotificationOffset = 20
        settingsStore.settings.autoPauseDuringDisplayMirroring = true
    }

    override func tearDown() async throws {
        userDefaults.removePersistentDomain(forName: suiteName)
        userDefaults = nil
        suiteName = nil
        settingsStore = nil
        sessionStore = nil
        notificationService = nil
        idleMonitor = nil
        clock = nil
    }

    func testNewStoreUsesConfiguredProductDefaults() {
        let defaultSuiteName = "DefaultSettings.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: defaultSuiteName)!
        defer { defaults.removePersistentDomain(forName: defaultSuiteName) }

        let store = SettingsStore(userDefaults: defaults)

        XCTAssertEqual(store.rules.workDuration, 30 * 60)
        XCTAssertTrue(store.settings.notificationSoundEnabled)
        XCTAssertEqual(store.settings.notificationSoundEffect, .stardewAchievement)
        XCTAssertEqual(store.settings.menuBarPopoverThemeColor, .jadeToken)
        XCTAssertEqual(store.settings.menuBarPopoverProgressStyle, .segments)
        XCTAssertEqual(MenuBarCountdownSetting(settings: store.settings), .minutesAndSeconds)
        XCTAssertTrue(store.settings.autoPauseDuringDisplayMirroring)
        XCTAssertEqual(store.settings.restOverlaySubtitle, .random)
        XCTAssertEqual(store.settings.restStartSoundEffect, .stardewNewRecord)
        XCTAssertEqual(store.settings.restEndSoundEffect, .stardewHorseFlute)
    }

    func testMissingStoredFieldsUseConfiguredProductDefaults() throws {
        let data = try XCTUnwrap("{}".data(using: .utf8))
        let settings = try JSONDecoder().decode(AppSettings.self, from: data)

        XCTAssertTrue(settings.notificationSoundEnabled)
        XCTAssertEqual(settings.notificationSoundEffect, .stardewAchievement)
        XCTAssertEqual(settings.menuBarPopoverThemeColor, .jadeToken)
        XCTAssertEqual(settings.menuBarPopoverProgressStyle, .segments)
        XCTAssertEqual(MenuBarCountdownSetting(settings: settings), .minutesAndSeconds)
        XCTAssertTrue(settings.autoPauseDuringDisplayMirroring)
        XCTAssertEqual(settings.restOverlaySubtitle, .random)
        XCTAssertEqual(settings.restStartSoundEffect, .stardewNewRecord)
        XCTAssertEqual(settings.restEndSoundEffect, .stardewHorseFlute)
    }

    func testLegacyMasterAndAutomaticSettingsMigrateToOneToggle() throws {
        let enabledData = try XCTUnwrap(
            "{\"screenSharingPauseEnabled\":true,\"autoPauseDuringDisplayMirroring\":true}"
                .data(using: .utf8)
        )
        let masterDisabledData = try XCTUnwrap(
            "{\"screenSharingPauseEnabled\":false,\"autoPauseDuringDisplayMirroring\":true}"
                .data(using: .utf8)
        )
        let legacyData = try XCTUnwrap(
            "{\"pauseDuringScreenSharing\":true}".data(using: .utf8)
        )

        XCTAssertTrue(try JSONDecoder().decode(AppSettings.self, from: enabledData).autoPauseDuringDisplayMirroring)
        XCTAssertFalse(try JSONDecoder().decode(AppSettings.self, from: masterDisabledData).autoPauseDuringDisplayMirroring)
        XCTAssertTrue(try JSONDecoder().decode(AppSettings.self, from: legacyData).autoPauseDuringDisplayMirroring)
    }

    func testOrdinaryPauseFreezesAndContinuesTheSameCountdown() {
        let scheduler = makeScheduler()
        scheduler.tick()
        let frozenSeconds = scheduler.remainingSeconds

        scheduler.togglePause()
        scheduler.tick()

        XCTAssertEqual(scheduler.state, .paused)
        XCTAssertEqual(scheduler.pauseReasons, [.user])
        XCTAssertEqual(scheduler.remainingSeconds, frozenSeconds)
        XCTAssertEqual(scheduler.pauseContextTitle, "Breather 已暂停")
        XCTAssertEqual(scheduler.pauseContextDetail, "不会提醒休息，直到你手动继续")

        scheduler.continueUserPause()

        XCTAssertEqual(scheduler.state, .working)
        XCTAssertEqual(scheduler.remainingSeconds, frozenSeconds)
        XCTAssertTrue(scheduler.pauseReasons.isEmpty)
    }

    func testQuickOrdinaryPauseIsNotRestoredAfterRestart() {
        var scheduler: BreakScheduler? = makeScheduler()
        scheduler?.togglePause()
        XCTAssertNil(sessionStore.load())
        scheduler = nil

        let recreatedScheduler = makeScheduler()
        recreatedScheduler.restorePauseResumeSessionIfNeeded()

        XCTAssertEqual(recreatedScheduler.state, .working)
        XCTAssertTrue(recreatedScheduler.pauseReasons.isEmpty)
    }

    func testTimedPauseFreezesCountdownAndPersistsAbsoluteResumeDate() throws {
        let scheduler = makeScheduler()
        scheduler.tick()
        let frozenSeconds = scheduler.remainingSeconds
        let resumesAt = clock.now.addingTimeInterval(30 * 60)

        scheduler.beginPauseAutoResume(until: resumesAt)
        scheduler.tick()

        XCTAssertEqual(scheduler.state, .paused)
        XCTAssertEqual(scheduler.pauseReasons, [.user])
        XCTAssertEqual(scheduler.remainingSeconds, frozenSeconds)
        XCTAssertEqual(scheduler.pauseResumeRemainingSeconds, 30 * 60)
        XCTAssertEqual(try XCTUnwrap(sessionStore.load()).resumesAt, resumesAt)
        XCTAssertEqual(scheduler.menuBarTitle, "暂停 30m")
        XCTAssertEqual(scheduler.pauseStatusText, "已暂停，30 分钟后重新开始")
    }

    func testTimedPauseExpiryStartsFreshWorkCycleBeforePausedGuard() {
        let scheduler = makeScheduler()
        scheduler.tick()
        scheduler.beginPauseAutoResume(until: clock.now.addingTimeInterval(30))

        clock.now = clock.now.addingTimeInterval(31)
        scheduler.tick()

        XCTAssertEqual(scheduler.state, .working)
        XCTAssertTrue(scheduler.pauseReasons.isEmpty)
        XCTAssertNil(scheduler.pauseResumeSession)
        XCTAssertNil(sessionStore.load())
        XCTAssertEqual(scheduler.remainingSeconds, Int(settingsStore.rules.workDuration))
    }

    func testWakeRefreshExpiresTimedPauseWithoutDecrementingFreshCycle() {
        let scheduler = makeScheduler()
        scheduler.beginPauseAutoResume(until: clock.now.addingTimeInterval(30))

        clock.now = clock.now.addingTimeInterval(31)
        scheduler.refreshPauseAfterWakeOrUnlock()

        XCTAssertEqual(scheduler.state, .working)
        XCTAssertTrue(scheduler.pauseReasons.isEmpty)
        XCTAssertNil(sessionStore.load())
        XCTAssertEqual(scheduler.remainingSeconds, Int(settingsStore.rules.workDuration))
    }

    func testTimedPauseRestoresAcrossSchedulerRecreation() throws {
        let resumesAt = clock.now.addingTimeInterval(60 * 60)
        sessionStore.save(PauseResumeSession(startedAt: clock.now, resumesAt: resumesAt))

        let restoredScheduler = makeScheduler()
        restoredScheduler.restorePauseResumeSessionIfNeeded()

        XCTAssertEqual(restoredScheduler.state, .paused)
        XCTAssertEqual(restoredScheduler.pauseReasons, [.user])
        XCTAssertEqual(try XCTUnwrap(restoredScheduler.pauseResumeSession).resumesAt, resumesAt)
        XCTAssertEqual(restoredScheduler.pauseResumeRemainingSeconds, 60 * 60)
    }

    func testChangingAutoResumeDurationRecalculatesFromCurrentTime() throws {
        let scheduler = makeScheduler()
        scheduler.beginPauseAutoResume(until: clock.now.addingTimeInterval(30 * 60))

        clock.now = clock.now.addingTimeInterval(10 * 60)
        let replacementResumeDate = clock.now.addingTimeInterval(60 * 60)
        scheduler.beginPauseAutoResume(until: replacementResumeDate)

        XCTAssertEqual(scheduler.pauseResumeSession?.startedAt, clock.now)
        XCTAssertEqual(scheduler.pauseResumeSession?.resumesAt, replacementResumeDate)
        XCTAssertEqual(try XCTUnwrap(sessionStore.load()).resumesAt, replacementResumeDate)
        XCTAssertEqual(scheduler.pauseResumeRemainingSeconds, 60 * 60)
    }

    func testCancelAutoResumeKeepsOrdinaryPauseActive() {
        let scheduler = makeScheduler()
        scheduler.beginPauseAutoResume(until: clock.now.addingTimeInterval(30 * 60))

        scheduler.cancelPauseAutoResume()

        XCTAssertEqual(scheduler.state, .paused)
        XCTAssertEqual(scheduler.pauseReasons, [.user])
        XCTAssertNil(scheduler.pauseResumeSession)
        XCTAssertNil(sessionStore.load())
        XCTAssertEqual(scheduler.menuBarTitle, "已暂停")
    }

    func testContinuingBeforeAutoResumeClearsSessionAndKeepsPreviousCountdown() {
        let scheduler = makeScheduler()
        scheduler.tick()
        let previousSeconds = scheduler.remainingSeconds
        scheduler.beginPauseAutoResume(until: clock.now.addingTimeInterval(30 * 60))

        scheduler.continueUserPause()

        XCTAssertEqual(scheduler.state, .working)
        XCTAssertEqual(scheduler.remainingSeconds, previousSeconds)
        XCTAssertNil(scheduler.pauseResumeSession)
        XCTAssertNil(sessionStore.load())
    }

    func testExpiredPersistedSessionIsDeletedInsteadOfRestored() {
        sessionStore.save(
            PauseResumeSession(
                startedAt: clock.now.addingTimeInterval(-120),
                resumesAt: clock.now.addingTimeInterval(-60)
            )
        )

        let scheduler = makeScheduler()
        scheduler.restorePauseResumeSessionIfNeeded()

        XCTAssertEqual(scheduler.state, .working)
        XCTAssertTrue(scheduler.pauseReasons.isEmpty)
        XCTAssertNil(sessionStore.load())
    }

    func testLegacyTimedScreenSharingSessionMigratesButIndefiniteSessionDoesNot() throws {
        struct LegacySession: Codable {
            let startedAt: Date
            let expiresAt: Date?
        }

        let legacyKey = "breather.screenSharingPauseSession"
        let expiry = clock.now.addingTimeInterval(30 * 60)
        userDefaults.set(
            try JSONEncoder().encode(LegacySession(startedAt: clock.now, expiresAt: expiry)),
            forKey: legacyKey
        )

        XCTAssertEqual(sessionStore.load()?.resumesAt, expiry)
        XCTAssertNil(userDefaults.data(forKey: legacyKey))

        sessionStore.clear()
        userDefaults.set(
            try JSONEncoder().encode(LegacySession(startedAt: clock.now, expiresAt: nil)),
            forKey: legacyKey
        )

        XCTAssertNil(sessionStore.load())
        XCTAssertNil(userDefaults.data(forKey: legacyKey))
    }

    func testMirrorAndUserPauseReasonsRemainIndependent() {
        let scheduler = makeScheduler()
        scheduler.tick()
        scheduler.beginPauseAutoResume(until: clock.now.addingTimeInterval(60))
        scheduler.setDisplayMirroringActive(true)

        XCTAssertEqual(scheduler.pauseReasons, [.user, .displayMirroring])
        XCTAssertEqual(scheduler.pauseContextTitle, "屏幕镜像中")

        scheduler.setDisplayMirroringActive(false)

        XCTAssertEqual(scheduler.state, .paused)
        XCTAssertEqual(scheduler.pauseReasons, [.user])
        XCTAssertEqual(scheduler.remainingSeconds, Int(settingsStore.rules.workDuration))

        scheduler.continueUserPause()
        XCTAssertEqual(scheduler.state, .working)
        XCTAssertEqual(scheduler.remainingSeconds, Int(settingsStore.rules.workDuration))
    }

    func testTimedPauseExpiryDoesNotBypassActiveMirrorPause() {
        let scheduler = makeScheduler()
        scheduler.setDisplayMirroringActive(true)
        scheduler.beginPauseAutoResume(until: clock.now.addingTimeInterval(60))

        clock.now = clock.now.addingTimeInterval(61)
        scheduler.tick()

        XCTAssertEqual(scheduler.state, .paused)
        XCTAssertEqual(scheduler.pauseReasons, [.displayMirroring])
        XCTAssertNil(scheduler.pauseResumeSession)
        XCTAssertEqual(scheduler.menuBarTitle, "镜像中")
    }

    func testAutomaticMirrorPauseIsNotRestoredAcrossRestart() {
        var scheduler: BreakScheduler? = makeScheduler()
        scheduler?.setDisplayMirroringActive(true)
        XCTAssertNil(sessionStore.load())
        scheduler = nil

        let recreatedScheduler = makeScheduler()
        recreatedScheduler.restorePauseResumeSessionIfNeeded()

        XCTAssertEqual(recreatedScheduler.state, .working)
        XCTAssertTrue(recreatedScheduler.pauseReasons.isEmpty)
    }

    func testMirrorPauseDuringRestHidesOverlayAndEndsWithFreshWorkCycle() {
        let scheduler = makeScheduler()
        var restStartedCount = 0
        var restEndedCount = 0
        scheduler.onRestStarted = { restStartedCount += 1 }
        scheduler.onRestEnded = { restEndedCount += 1 }

        scheduler.startRestNow()
        scheduler.setDisplayMirroringActive(true)

        XCTAssertEqual(restStartedCount, 1)
        XCTAssertEqual(restEndedCount, 1)
        XCTAssertEqual(scheduler.state, .paused)
        XCTAssertEqual(scheduler.consecutiveMissedBreaks, 0)

        scheduler.setDisplayMirroringActive(false)

        XCTAssertEqual(scheduler.state, .working)
        XCTAssertEqual(scheduler.remainingSeconds, Int(settingsStore.rules.workDuration))
        XCTAssertEqual(scheduler.consecutiveMissedBreaks, 0)
    }

    func testMirrorPauseDuringSnoozeDoesNotResumeSnooze() {
        let scheduler = makeScheduler()
        scheduler.startRestNow()
        scheduler.snoozeBreak()
        XCTAssertEqual(scheduler.state, .snoozing)

        scheduler.setDisplayMirroringActive(true)
        scheduler.setDisplayMirroringActive(false)

        XCTAssertEqual(scheduler.state, .working)
        XCTAssertEqual(scheduler.remainingSeconds, Int(settingsStore.rules.workDuration))
        XCTAssertEqual(scheduler.consecutiveMissedBreaks, 1)
    }

    func testMirrorPauseSuppressesRestNotificationAndIdleTransitions() {
        settingsStore.rules.workDuration = 21
        settingsStore.rules.preBreakNotificationOffset = 20
        settingsStore.settings.automaticRestMode = .lockSleepOrIdle
        idleMonitor.idleSeconds = settingsStore.settings.automaticRestThreshold + 60
        let scheduler = makeScheduler()
        scheduler.setDisplayMirroringActive(true)

        scheduler.tick()
        scheduler.startRestNow()

        XCTAssertEqual(scheduler.state, .paused)
        XCTAssertEqual(scheduler.remainingSeconds, 21)
        XCTAssertEqual(notificationService.sendCount, 0)
    }

    func testMirrorPauseRequiresSettingAndDisablingItEndsCurrentMirrorPause() {
        settingsStore.settings.autoPauseDuringDisplayMirroring = false
        let scheduler = makeScheduler()

        scheduler.setDisplayMirroringActive(true)
        XCTAssertFalse(scheduler.isDisplayMirroringPauseActive)

        settingsStore.settings.autoPauseDuringDisplayMirroring = true
        scheduler.setDisplayMirroringActive(true)
        XCTAssertTrue(scheduler.isDisplayMirroringPauseActive)

        scheduler.disableDisplayMirroringAutoPause()

        XCTAssertEqual(scheduler.state, .working)
        XCTAssertFalse(scheduler.isDisplayMirroringPauseActive)
        XCTAssertEqual(scheduler.remainingSeconds, Int(settingsStore.rules.workDuration))
    }

    func testStrictModeStillAllowsOrdinaryAndAutomaticMirrorPause() {
        settingsStore.settings.strictMode = true
        let scheduler = makeScheduler()

        scheduler.togglePause()
        XCTAssertEqual(scheduler.pauseReasons, [.user])

        scheduler.continueUserPause()
        scheduler.setDisplayMirroringActive(true)
        XCTAssertEqual(scheduler.pauseReasons, [.displayMirroring])
    }

    func testNextCycleRuleChangeKeepsCurrentBreakDurationUntilTheFollowingWorkCycle() {
        settingsStore.rules.workDuration = 2
        settingsStore.rules.shortBreakDuration = 30
        settingsStore.rules.preBreakNotificationOffset = 0
        settingsStore.settings.ruleChangeEffect = .nextCycle
        let scheduler = makeScheduler()

        settingsStore.rules.shortBreakDuration = 58
        XCTAssertTrue(settingsStore.hasPendingRuleChanges)
        XCTAssertEqual(settingsStore.currentCycleRules.shortBreakDuration, 30)
        scheduler.tick()

        XCTAssertEqual(scheduler.statusText, "工作结束后，休息 30 秒")

        scheduler.tick()

        XCTAssertEqual(scheduler.state, .resting)
        XCTAssertEqual(scheduler.remainingSeconds, 30)

        for _ in 0..<30 {
            scheduler.tick()
        }

        XCTAssertEqual(scheduler.state, .working)
        XCTAssertFalse(settingsStore.hasPendingRuleChanges)
        XCTAssertEqual(settingsStore.currentCycleRules.shortBreakDuration, 58)
        scheduler.startRestNow()
        XCTAssertEqual(scheduler.remainingSeconds, 58)
    }

    func testDisabledPreBreakNotificationStillStartsAndFinishesRest() {
        settingsStore.rules.workDuration = 3
        settingsStore.rules.shortBreakDuration = 2
        settingsStore.rules.preBreakNotificationEnabled = false
        let scheduler = makeScheduler()

        for _ in 0..<3 { scheduler.tick() }

        XCTAssertEqual(notificationService.sendCount, 0)
        XCTAssertEqual(scheduler.state, .resting)
        XCTAssertEqual(scheduler.remainingSeconds, 2)
        for _ in 0..<2 { scheduler.tick() }
        XCTAssertEqual(scheduler.state, .working)
        XCTAssertEqual(scheduler.remainingSeconds, 3)
    }

    func testPreBreakNotificationSendsOnceAtConfiguredTime() {
        settingsStore.rules.workDuration = 5
        settingsStore.preBreakNotificationSeconds = 2
        let scheduler = makeScheduler()

        for _ in 0..<2 { scheduler.tick() }
        XCTAssertEqual(notificationService.sendCount, 0)
        scheduler.tick()
        XCTAssertEqual(scheduler.state, .notifying)
        XCTAssertEqual(scheduler.remainingSeconds, 2)
        XCTAssertEqual(notificationService.sendCount, 1)
        for _ in 0..<2 { scheduler.tick() }
        XCTAssertEqual(scheduler.state, .resting)
        XCTAssertEqual(notificationService.sendCount, 1)
    }

    func testZeroOffsetDoesNotNotifyAtRestStart() {
        settingsStore.rules.workDuration = 1
        settingsStore.rules.preBreakNotificationOffset = 0
        let scheduler = makeScheduler()
        scheduler.tick()
        XCTAssertEqual(scheduler.state, .resting)
        XCTAssertEqual(notificationService.sendCount, 0)
    }

    func testNotificationChoiceFollowsRuleActivationBoundary() {
        settingsStore.rules.workDuration = 3
        settingsStore.preBreakNotificationSeconds = 1
        let scheduler = makeScheduler()
        settingsStore.rules.preBreakNotificationEnabled = false

        XCTAssertTrue(settingsStore.hasPendingRuleChanges)
        for _ in 0..<2 { scheduler.tick() }
        XCTAssertEqual(notificationService.sendCount, 1, "Saved changes do not alter the active cycle")
        scheduler.resetWorkCycle()
        for _ in 0..<3 { scheduler.tick() }
        XCTAssertEqual(scheduler.state, .resting)
        XCTAssertEqual(notificationService.sendCount, 1)
        XCTAssertFalse(settingsStore.hasPendingRuleChanges)
    }

    func testApplyingDisabledNotificationImmediatelySuppressesCurrentCycleNotification() {
        settingsStore.rules.workDuration = 3
        let scheduler = makeScheduler()
        settingsStore.rules.preBreakNotificationEnabled = false
        scheduler.applyCurrentRulesToCurrentCycle()

        for _ in 0..<3 { scheduler.tick() }
        XCTAssertEqual(scheduler.state, .resting)
        XCTAssertEqual(notificationService.sendCount, 0)
        XCTAssertFalse(settingsStore.hasPendingRuleChanges)
    }

    func testLegacyNotificationChoiceMigratesWithoutLosingOtherRules() throws {
        for offset in [0, 45] {
            let legacy = Data("""
            {"workDuration":2700,"shortBreakDuration":58,"longBreakEnabled":true,
             "longBreakEveryShortBreaks":3,"longBreakDuration":600,"preBreakNotificationOffset":\(offset)}
            """.utf8)
            userDefaults.set(legacy, forKey: "breather.rules")
            let store = SettingsStore(userDefaults: userDefaults)

            XCTAssertEqual(store.rules.workDuration, 2700)
            XCTAssertEqual(store.rules.shortBreakDuration, 58)
            XCTAssertTrue(store.rules.longBreakEnabled)
            XCTAssertEqual(store.rules.longBreakEveryShortBreaks, 3)
            XCTAssertEqual(store.rules.longBreakDuration, 600)
            XCTAssertEqual(store.rules.preBreakNotificationEnabled, offset > 0)
            XCTAssertEqual(store.preBreakNotificationSeconds, offset == 0 ? 20 : 45)
        }
    }

    func testNotificationChoiceAndLastDurationSurviveRelaunchAndReenabling() {
        settingsStore.preBreakNotificationSeconds = 45
        settingsStore.rules.preBreakNotificationEnabled = false
        let reloaded = SettingsStore(userDefaults: userDefaults)
        XCTAssertFalse(reloaded.rules.preBreakNotificationEnabled)
        XCTAssertEqual(reloaded.preBreakNotificationSeconds, 45)
        reloaded.rules.preBreakNotificationEnabled = true
        XCTAssertEqual(reloaded.preBreakNotificationSeconds, 45)
        XCTAssertTrue(SettingsStore(userDefaults: userDefaults).rules.preBreakNotificationEnabled)
    }

    func testExplicitNotificationChoiceTakesPrecedenceAndMissingRulesKeepDefaults() throws {
        let data = Data("{\"preBreakNotificationEnabled\":false,\"preBreakNotificationOffset\":45}".utf8)
        let rules = try JSONDecoder().decode(BreakRules.self, from: data)
        XCTAssertFalse(rules.preBreakNotificationEnabled)
        XCTAssertEqual(rules.preBreakNotificationOffset, 45)
        XCTAssertEqual(rules.workDuration, 30 * 60)
        let defaults = try JSONDecoder().decode(BreakRules.self, from: Data("{}".utf8))
        XCTAssertTrue(defaults.preBreakNotificationEnabled)
        XCTAssertEqual(defaults.preBreakNotificationOffset, 20)
    }

    func testNotificationDurationRejectsZeroAndOutOfRangeInput() {
        settingsStore.preBreakNotificationSeconds = 0
        XCTAssertEqual(settingsStore.preBreakNotificationSeconds, 1)
        settingsStore.preBreakNotificationSeconds = 121
        XCTAssertEqual(settingsStore.preBreakNotificationSeconds, 120)
    }

    func testApplyingSavedRulesImmediatelyUpdatesTheCurrentCycle() {
        let scheduler = makeScheduler()
        settingsStore.rules.workDuration = 10 * 60
        settingsStore.rules.shortBreakDuration = 58

        XCTAssertTrue(settingsStore.hasPendingRuleChanges)

        scheduler.applyCurrentRulesToCurrentCycle()

        XCTAssertFalse(settingsStore.hasPendingRuleChanges)
        XCTAssertEqual(scheduler.state, .working)
        XCTAssertEqual(scheduler.remainingSeconds, 10 * 60)
        XCTAssertEqual(scheduler.statusText, "工作结束后，休息 58 秒")
    }

    func testPauseTitlesOverrideHiddenCountdownAndExplainWhyActionsChanged() {
        settingsStore.settings.showCountdownInMenuBar = false
        let scheduler = makeScheduler()
        XCTAssertEqual(scheduler.menuBarTitle, "Breather")

        scheduler.togglePause()
        XCTAssertEqual(scheduler.menuBarTitle, "已暂停")
        XCTAssertNil(scheduler.pauseContextFootnote)

        scheduler.continueUserPause()
        scheduler.setDisplayMirroringActive(true)
        XCTAssertEqual(scheduler.menuBarTitle, "镜像中")
        XCTAssertEqual(scheduler.pauseContextDetail, "休息提醒已暂停")
        XCTAssertEqual(
            scheduler.pauseContextFootnote,
            "检测到 AirPlay 或有线屏幕镜像"
        )
    }

    private func makeScheduler() -> BreakScheduler {
        settingsStore.activateSavedRulesForCurrentCycle()
        return BreakScheduler(
            settingsStore: settingsStore,
            notificationService: notificationService,
            idleMonitor: idleMonitor,
            pauseResumeSessionStore: sessionStore,
            now: { [clock] in clock!.now }
        )
    }

}

@MainActor
private final class TestNotificationService: BreakNotificationSending {
    private(set) var sendCount = 0

    func sendPreBreakNotification(playSound: Bool, soundEffect: RestSoundEffect) {
        sendCount += 1
    }
}

private final class TestIdleMonitor: IdleTimeProviding {
    var idleSeconds: TimeInterval = 0
}

private final class TestClock {
    var now: Date

    init(now: Date) {
        self.now = now
    }
}

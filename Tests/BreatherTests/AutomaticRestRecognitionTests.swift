import AppKit
import XCTest
@testable import Breather

final class AutomaticRestSettingsTests: XCTestCase {
    func testFreshSettingsUseLockOrSleepAndFiveMinutes() throws {
        for settings in [AppSettings(), try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))] {
            XCTAssertEqual(settings.automaticRestMode, .lockOrSleep)
            XCTAssertEqual(settings.automaticRestThreshold, 5 * 60)
        }
    }

    func testExistingIdleSettingsKeepTheirBehaviorAndDuration() throws {
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data("{\"idleThreshold\":540}".utf8))
        XCTAssertEqual(settings.automaticRestMode, .lockSleepOrIdle)
        XCTAssertEqual(settings.automaticRestThreshold, 540)
        let encoded = try JSONEncoder().encode(settings)
        let fields = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertNil(fields["idleThreshold"])
        XCTAssertEqual(fields["automaticRestThreshold"] as? Double, 540)
        XCTAssertEqual(try JSONDecoder().decode(AppSettings.self, from: encoded), settings)
    }

    func testExplicitModeAndDurationOverrideLegacyValuesAndPersist() throws {
        for mode in AutomaticRestMode.allCases {
            let data = Data("{\"automaticRestMode\":\"\(mode.rawValue)\",\"automaticRestThreshold\":120,\"idleThreshold\":540}".utf8)
            let settings = try JSONDecoder().decode(AppSettings.self, from: data)
            XCTAssertEqual(settings.automaticRestMode, mode)
            XCTAssertEqual(settings.automaticRestThreshold, 120)
            XCTAssertEqual(try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings)), settings)
        }
    }
}

@MainActor
final class BreakSchedulerAutomaticRestTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!
    private var store: SettingsStore!
    private var clock: AutomaticRestTestClock!
    private var idle: AutomaticRestTestIdle!
    private var notifications: AutomaticRestTestNotifications!
    private var scheduler: BreakScheduler!

    override func setUp() async throws {
        suite = "AutomaticRestTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        store = SettingsStore(userDefaults: defaults)
        store.rules.workDuration = 1200
        store.settings.automaticRestThreshold = 300
        store.activateSavedRulesForCurrentCycle()
        clock = AutomaticRestTestClock()
        idle = AutomaticRestTestIdle()
        notifications = AutomaticRestTestNotifications()
        scheduler = BreakScheduler(settingsStore: store, notificationService: notifications, idleMonitor: idle,
                                   pauseResumeSessionStore: PauseResumeSessionStore(userDefaults: defaults),
                                   now: { [clock] in clock!.now })
    }

    override func tearDown() async throws {
        scheduler = nil
        defaults.removePersistentDomain(forName: suite)
        defaults = nil
        store = nil
        clock = nil
        idle = nil
        notifications = nil
    }

    func testReadingWithoutInputKeepsWorkTimerInDefaultAndDisabledModes() {
        idle.idleSeconds = 3600
        for mode in [AutomaticRestMode.lockOrSleep, .disabled] {
            store.settings.automaticRestMode = mode
            store.activateSavedRulesForCurrentCycle()
            let before = scheduler.remainingSeconds
            scheduler.tick()
            XCTAssertEqual(scheduler.state, .working)
            XCTAssertEqual(scheduler.remainingSeconds, before - 1)
        }
    }

    func testOptingIntoIdleCountsOneBreakAndWaitsForInputToStartWork() {
        store.settings.automaticRestMode = .lockSleepOrIdle
        store.activateSavedRulesForCurrentCycle()
        scheduler.startRestNow()
        scheduler.snoozeBreak()
        idle.idleSeconds = 300
        scheduler.tick()
        XCTAssertEqual(scheduler.state, .idleRested)
        XCTAssertEqual(scheduler.consecutiveMissedBreaks, 0)
        scheduler.tick()
        XCTAssertEqual(scheduler.state, .idleRested)
        XCTAssertEqual(scheduler.remainingSeconds, 1200)
        idle.idleSeconds = 0
        scheduler.tick()
        XCTAssertEqual(scheduler.state, .working)
        XCTAssertEqual(scheduler.remainingSeconds, 1200)
    }

    func testTurningOffIdleWhileWaitingReturnsToNormalWorkTimer() {
        store.settings.automaticRestMode = .lockSleepOrIdle
        store.activateSavedRulesForCurrentCycle()
        idle.idleSeconds = 300
        scheduler.tick()
        store.settings.automaticRestMode = .disabled
        scheduler.applyCurrentRulesToCurrentCycle()
        scheduler.tick()
        XCTAssertEqual(scheduler.state, .working)
        XCTAssertEqual(scheduler.remainingSeconds, 1199)
    }

    func testShortLockFreezesCountdownAndContinuesTheSameCycle() {
        scheduler.tick()
        let remaining = scheduler.remainingSeconds
        scheduler.setComputerActivity(ComputerActivityState(isLocked: true))
        clock.advance(299)
        scheduler.tick()
        XCTAssertEqual(scheduler.state, .paused)
        XCTAssertEqual(scheduler.remainingSeconds, remaining)
        XCTAssertEqual(notifications.sendCount, 0)
        scheduler.setComputerActivity(ComputerActivityState())
        XCTAssertEqual(scheduler.state, .working)
        XCTAssertEqual(scheduler.remainingSeconds, remaining)
    }

    func testExactThresholdCompletesMissedBreakAndAppliesSavedRules() {
        scheduler.startRestNow()
        scheduler.snoozeBreak()
        XCTAssertEqual(scheduler.consecutiveMissedBreaks, 1)
        store.rules.workDuration = 1800
        scheduler.setComputerActivity(ComputerActivityState(isLocked: true))
        clock.advance(300)
        scheduler.setComputerActivity(ComputerActivityState())
        XCTAssertEqual(scheduler.state, .working)
        XCTAssertEqual(scheduler.remainingSeconds, 1800)
        XCTAssertEqual(scheduler.consecutiveMissedBreaks, 0)
        XCTAssertFalse(store.hasPendingRuleChanges)
    }

    func testDisabledModeNeverCreditsLongSleep() {
        store.settings.automaticRestMode = .disabled
        store.activateSavedRulesForCurrentCycle()
        scheduler.tick()
        let remaining = scheduler.remainingSeconds
        scheduler.setComputerActivity(ComputerActivityState(isSleeping: true))
        clock.advance(3600)
        scheduler.setComputerActivity(ComputerActivityState())
        XCTAssertEqual(scheduler.state, .working)
        XCTAssertEqual(scheduler.remainingSeconds, remaining)
    }

    func testLockAndSleepFormOneContinuousIntervalAndWakeWaitsForUnlock() {
        scheduler.tick()
        scheduler.setComputerActivity(ComputerActivityState(isLocked: true))
        clock.advance(200)
        scheduler.setComputerActivity(ComputerActivityState(isLocked: true, isSleeping: true))
        clock.advance(50)
        scheduler.setComputerActivity(ComputerActivityState(isLocked: true))
        scheduler.tick()
        XCTAssertEqual(scheduler.state, .paused)
        XCTAssertEqual(scheduler.remainingSeconds, 1199)
        clock.advance(50)
        scheduler.setComputerActivity(ComputerActivityState())
        XCTAssertEqual(scheduler.state, .working)
        XCTAssertEqual(scheduler.remainingSeconds, 1200)
        scheduler.tick()
        XCTAssertEqual(scheduler.remainingSeconds, 1199)
    }

    func testDuplicateLockEventDoesNotRestartTheInterval() {
        scheduler.tick()
        scheduler.setComputerActivity(ComputerActivityState(isLocked: true))
        clock.advance(200)
        scheduler.setComputerActivity(ComputerActivityState(isLocked: true))
        clock.advance(100)
        scheduler.setComputerActivity(ComputerActivityState())
        XCTAssertEqual(scheduler.remainingSeconds, 1200)
        XCTAssertEqual(scheduler.state, .working)
    }

    func testSeparateShortLocksDoNotAccumulateIntoOneBreak() {
        scheduler.tick()
        for _ in 0..<2 {
            scheduler.setComputerActivity(ComputerActivityState(isLocked: true))
            clock.advance(200)
            scheduler.setComputerActivity(ComputerActivityState())
            XCTAssertEqual(scheduler.state, .working)
            XCTAssertEqual(scheduler.remainingSeconds, 1199)
            clock.advance(10)
        }
    }

    func testFastUserSwitchOnlyPausesWithoutCreditingRest() {
        scheduler.tick()
        scheduler.setComputerActivity(ComputerActivityState(isSessionActive: false))
        clock.advance(600)
        scheduler.setComputerActivity(ComputerActivityState())
        XCTAssertEqual(scheduler.remainingSeconds, 1199)
        XCTAssertEqual(scheduler.state, .working)
    }

    func testQualifyingRestPreservesManualPauseAndItsAutoResumeDate() {
        let resumesAt = clock.now.addingTimeInterval(3600)
        scheduler.beginPauseAutoResume(until: resumesAt)
        scheduler.setComputerActivity(ComputerActivityState(isLocked: true))
        clock.advance(300)
        scheduler.setComputerActivity(ComputerActivityState())
        XCTAssertEqual(scheduler.state, .paused)
        XCTAssertEqual(scheduler.pauseReasons, [.user])
        XCTAssertEqual(scheduler.pauseResumeSession?.resumesAt, resumesAt)
        XCTAssertEqual(scheduler.remainingSeconds, 1200)
    }

    func testTimedPauseExpiryWhileLockedDoesNotResumeUntilAvailable() {
        scheduler.beginPauseAutoResume(until: clock.now.addingTimeInterval(60))
        scheduler.setComputerActivity(ComputerActivityState(isLocked: true))
        clock.advance(100)
        scheduler.tick()
        XCTAssertEqual(scheduler.state, .paused)
        XCTAssertEqual(scheduler.pauseReasons, [.computerUnavailable])
        scheduler.setComputerActivity(ComputerActivityState())
        XCTAssertEqual(scheduler.state, .working)
        XCTAssertEqual(scheduler.remainingSeconds, 1200)
    }

    func testUnlockDoesNotClearMirroringOrManualPause() {
        scheduler.togglePause()
        scheduler.setDisplayMirroringActive(true)
        scheduler.setComputerActivity(ComputerActivityState(isLocked: true))
        clock.advance(300)
        scheduler.setComputerActivity(ComputerActivityState())
        XCTAssertEqual(scheduler.state, .paused)
        XCTAssertEqual(scheduler.pauseReasons, [.user, .displayMirroring])
        scheduler.setDisplayMirroringActive(false)
        XCTAssertEqual(scheduler.pauseReasons, [.user])
        scheduler.continueUserPause()
        XCTAssertEqual(scheduler.state, .working)
    }

    func testActionsCannotStartTimerOrRestWhileUnavailable() {
        var restStarts = 0
        scheduler.onRestStarted = { restStarts += 1 }
        scheduler.setComputerActivity(ComputerActivityState(isLocked: true))
        scheduler.togglePause()
        scheduler.startRestNow()
        scheduler.resetWorkCycle()
        XCTAssertEqual(scheduler.state, .paused)
        XCTAssertEqual(scheduler.pauseReasons, [.computerUnavailable])
        XCTAssertEqual(restStarts, 0)
    }

    func testShortLockDuringRestRestoresOverlayAndRemainingRest() {
        var restStarts = 0
        scheduler.onRestStarted = { restStarts += 1 }
        scheduler.startRestNow()
        scheduler.tick()
        let remaining = scheduler.remainingSeconds
        scheduler.setComputerActivity(ComputerActivityState(isLocked: true))
        clock.advance(10)
        scheduler.setComputerActivity(ComputerActivityState())
        XCTAssertEqual(scheduler.state, .resting)
        XCTAssertEqual(scheduler.remainingSeconds, remaining)
        XCTAssertEqual(restStarts, 2)
    }
}

@MainActor
final class ComputerActivityMonitorTests: XCTestCase {
    func testWakeRechecksLockWithoutPublishingAFalseAvailableState() {
        let workspace = NotificationCenter()
        let distributed = NotificationCenter()
        let monitor = ComputerActivityMonitor(workspaceCenter: workspace, distributedCenter: distributed,
                                              readSession: { (true, true) })
        var states: [ComputerActivityState] = []
        monitor.onStateChanged = { states.append($0) }
        monitor.start()
        workspace.post(name: NSWorkspace.willSleepNotification, object: nil)
        workspace.post(name: NSWorkspace.didWakeNotification, object: nil)
        XCTAssertTrue(states.allSatisfy(\.isUnavailable))
        XCTAssertTrue(monitor.state.isLocked)
        XCTAssertFalse(monitor.state.isSleeping)
        distributed.post(name: ComputerActivityMonitor.screenUnlockedNotification, object: nil)
        XCTAssertFalse(monitor.state.isUnavailable)
    }

    func testDuplicateEventsAndRepeatedStartPublishOnlyStateChanges() {
        let workspace = NotificationCenter()
        let distributed = NotificationCenter()
        let monitor = ComputerActivityMonitor(workspaceCenter: workspace, distributedCenter: distributed,
                                              readSession: { (false, true) })
        var count = 0
        monitor.onStateChanged = { _ in count += 1 }
        monitor.start()
        monitor.start()
        distributed.post(name: ComputerActivityMonitor.screenLockedNotification, object: nil)
        distributed.post(name: ComputerActivityMonitor.screenLockedNotification, object: nil)
        XCTAssertEqual(count, 1)
        monitor.stop()
        distributed.post(name: ComputerActivityMonitor.screenUnlockedNotification, object: nil)
        XCTAssertEqual(count, 1)
    }

    func testMissingSessionSnapshotPreservesObservedLockOnWake() {
        let workspace = NotificationCenter()
        let distributed = NotificationCenter()
        let monitor = ComputerActivityMonitor(workspaceCenter: workspace, distributedCenter: distributed,
                                              readSession: { (nil, nil) })
        monitor.start()
        distributed.post(name: ComputerActivityMonitor.screenLockedNotification, object: nil)
        workspace.post(name: NSWorkspace.willSleepNotification, object: nil)
        workspace.post(name: NSWorkspace.didWakeNotification, object: nil)
        XCTAssertTrue(monitor.state.isLocked)
        XCTAssertFalse(monitor.state.isSleeping)
    }

    func testRestartResamplesSessionAndClearsStaleSleepState() {
        let workspace = NotificationCenter()
        let monitor = ComputerActivityMonitor(workspaceCenter: workspace, distributedCenter: NotificationCenter(),
                                              readSession: { (false, true) })
        monitor.start()
        workspace.post(name: NSWorkspace.willSleepNotification, object: nil)
        monitor.stop()
        workspace.post(name: NSWorkspace.didWakeNotification, object: nil)
        XCTAssertTrue(monitor.state.isSleeping)
        monitor.start()
        XCTAssertEqual(monitor.state, ComputerActivityState())
    }
}

private final class AutomaticRestTestClock {
    var now = Date(timeIntervalSince1970: 1_800_000_000)
    func advance(_ seconds: TimeInterval) { now.addTimeInterval(seconds) }
}
private final class AutomaticRestTestIdle: IdleTimeProviding { var idleSeconds: TimeInterval = 0 }
@MainActor
private final class AutomaticRestTestNotifications: BreakNotificationSending {
    var sendCount = 0
    func sendPreBreakNotification(playSound: Bool, soundEffect: RestSoundEffect) { sendCount += 1 }
}

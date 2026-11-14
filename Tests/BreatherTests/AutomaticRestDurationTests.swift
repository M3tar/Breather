import Foundation
import Testing
@testable import Breather

@Suite(.serialized)
@MainActor
struct AutomaticRestDurationTests {
    @Test(arguments: [30, 60, 90])
    func modeMinimums(short: Int) {
        #expect(AutomaticRestDuration.minimum(mode: .lockOrSleep, shortBreak: Double(short)) == short)
        #expect(AutomaticRestDuration.minimum(mode: .lockSleepOrIdle, shortBreak: Double(short)) == max(60, short))
    }

    @Test(arguments: [30, 45, 90])
    func secondsSurviveReload(seconds: Int) throws {
        let f = try Fixture()
        defer { f.cleanUp() }
        f.store.automaticRestSeconds = seconds
        let reloaded = SettingsStore(userDefaults: f.defaults)
        #expect(reloaded.automaticRestSeconds == seconds)
        #expect(reloaded.settings.automaticRestThreshold == Double(seconds))
    }

    @Test func dependentChangesOnlyRaiseDuration() throws {
        let f = try Fixture()
        defer { f.cleanUp() }
        f.store.automaticRestSeconds = 45
        f.store.settings.automaticRestMode = .lockSleepOrIdle
        #expect(f.store.automaticRestSeconds == 60)
        f.store.shortBreakSeconds = 90
        #expect(f.store.automaticRestSeconds == 90)
        f.store.shortBreakSeconds = 30
        f.store.settings.automaticRestMode = .lockOrSleep
        #expect(f.store.automaticRestSeconds == 90)
        f.store.automaticRestSeconds = 45
        #expect(f.store.automaticRestSeconds == 45)
    }

    @Test func disabledPreservesValueUntilEnabled() throws {
        let f = try Fixture()
        defer { f.cleanUp() }
        f.store.automaticRestSeconds = 45
        f.store.settings.automaticRestMode = .disabled
        f.store.shortBreakSeconds = 90
        #expect(f.store.automaticRestSeconds == 45)
        let reloaded = SettingsStore(userDefaults: f.defaults)
        #expect(reloaded.automaticRestSeconds == 45)
        reloaded.settings.automaticRestMode = .lockOrSleep
        #expect(reloaded.automaticRestSeconds == 90)
    }

    @Test(arguments: [-1.0, 0, 29, 30, 44.5, 1801, Double.infinity, Double.nan])
    func invalidValuesNormalizeAndPersist(value: Double) throws {
        let f = try Fixture()
        defer { f.cleanUp() }
        f.store.settings.automaticRestThreshold = value
        let expected = value.isFinite ? min(1800, max(30, value.rounded(.up))) : 300
        #expect(f.store.settings.automaticRestThreshold == expected)
        #expect(SettingsStore(userDefaults: f.defaults).settings.automaticRestThreshold == expected)
    }

    @Test func loadLegacyAndCorrectIncompatibleSavedValues() throws {
        let f = try Fixture()
        defer { f.cleanUp() }
        f.defaults.set(Data(#"{"idleThreshold":45}"#.utf8), forKey: "breather.settings")
        let migrated = SettingsStore(userDefaults: f.defaults)
        #expect(migrated.settings.automaticRestMode == .lockSleepOrIdle)
        #expect(migrated.automaticRestSeconds == 60)
        #expect(SettingsStore(userDefaults: f.defaults).automaticRestSeconds == 60)
        f.store.rules.shortBreakDuration = 90
        f.defaults.set(Data(#"{"automaticRestMode":"lockOrSleep","automaticRestThreshold":60}"#.utf8), forKey: "breather.settings")
        #expect(SettingsStore(userDefaults: f.defaults).automaticRestSeconds == 90)
    }

    @Test func resetValidatesFinalPairWithoutIncreasingDefaultDuration() throws {
        let f = try Fixture()
        defer { f.cleanUp() }
        f.store.shortBreakSeconds = 600
        f.store.settings.automaticRestMode = .lockSleepOrIdle
        f.store.restoreDefaults(for: .schedule)
        #expect(f.store.shortBreakSeconds == 30)
        #expect(f.store.automaticRestSeconds == 300)
        #expect(f.store.isDefault(for: .schedule))
        #expect(SettingsStore(userDefaults: f.defaults).automaticRestSeconds == 300)
    }

    @Test(arguments: [44.0, 45, 46], [false, true])
    func lockAndSleepRespectExactSeconds(elapsed: Double, sleeping: Bool) throws {
        let f = try Fixture()
        defer { f.cleanUp() }
        f.store.automaticRestSeconds = 45
        f.store.activateSavedRulesForCurrentCycle()
        f.scheduler.startRestNow()
        for _ in 0..<10 { f.scheduler.tick() }
        #expect(f.scheduler.remainingSeconds == 20)
        f.scheduler.setComputerActivity(ComputerActivityState(isLocked: !sleeping, isSleeping: sleeping))
        f.clock.now.addTimeInterval(elapsed)
        f.scheduler.tick()
        #expect(f.scheduler.remainingSeconds == 20)
        f.scheduler.setComputerActivity(ComputerActivityState())
        #expect(f.scheduler.state == (elapsed >= 45 ? .working : .resting))
        #expect(f.scheduler.remainingSeconds == (elapsed >= 45 ? 1200 : 20))
    }

    @Test(arguments: [30, 90], [-1, 0, 1])
    func idleMinimumWaitsForUserReturn(short: Int, offset: Int) throws {
        let f = try Fixture()
        defer { f.cleanUp() }
        f.store.shortBreakSeconds = short
        f.store.activateSavedRulesForCurrentCycle()
        f.store.settings.automaticRestMode = .lockSleepOrIdle
        f.store.automaticRestSeconds = 30
        f.store.activateSavedRulesForCurrentCycle()
        #expect(f.store.automaticRestSeconds == max(60, short))
        f.idle.idleSeconds = Double(max(60, short) + offset)
        f.scheduler.tick()
        #expect(f.scheduler.state == (offset >= 0 ? .idleRested : .working))
        f.idle.idleSeconds = 0
        f.scheduler.tick()
        #expect(f.scheduler.state == .working)
        #expect(f.scheduler.remainingSeconds == (offset >= 0 ? 1200 : 1198))
    }

    @Test func idleModeAlsoUsesItsMinimumForLocking() throws {
        let f = try Fixture()
        defer { f.cleanUp() }
        f.store.settings.automaticRestMode = .lockSleepOrIdle
        f.store.automaticRestSeconds = 45
        f.store.activateSavedRulesForCurrentCycle()
        f.scheduler.startRestNow()
        f.scheduler.setComputerActivity(ComputerActivityState(isLocked: true))
        f.clock.now.addTimeInterval(45)
        f.scheduler.setComputerActivity(ComputerActivityState())
        #expect(f.scheduler.state == .resting)
        f.scheduler.setComputerActivity(ComputerActivityState(isLocked: true))
        f.clock.now.addTimeInterval(60)
        f.scheduler.setComputerActivity(ComputerActivityState())
        #expect(f.scheduler.state == .working)
    }

    @Test func translatedLabelsPreserveTimePlaceholders() {
        #expect(L.tr("锁屏或睡眠", language: .english) == "Locked or asleep")
        for language in [AppLanguage.simplifiedChinese, .traditionalChinese, .english] {
            for key in ["至少持续 %@，不能短于短休息时长。", "已调整为 %@", "当前周期至少 %@"] {
                let template = L.tr(key, language: language)
                #expect(template.contains("%@"))
                #expect(!template.contains("·"))
                if language == .english { #expect(template != key) }
            }
        }
    }

    @Test(arguments: [37, 60, 90])
    func minimumCopyUsesTheProvidedSeconds(seconds: Int) {
        let source = "至少持续 %@，不能短于短休息时长。"
        for language in [AppLanguage.simplifiedChinese, .traditionalChinese, .english] {
            let duration = String(format: L.tr("%lld 秒", language: language), seconds)
            let text = String(format: L.tr(source, language: language), duration)
            let expected = switch language {
            case .english: "At least \(seconds) sec, and no shorter than a short break."
            case .traditionalChinese: "至少持續 \(seconds) 秒，不能短於短暫休息時間。"
            default: "至少持续 \(seconds) 秒，不能短于短休息时长。"
            }
            #expect(text == expected)
        }
    }

    @Test func helpCopyIsLocalizedForEveryMode() {
        let messages = [
            "关闭时，锁屏或睡眠只暂停计时，不会自动完成休息。",
            "锁屏或睡眠达到设定时长，视为完成休息；返回后重新开始工作计时。",
            "锁屏、睡眠或无操作达到设定时长，视为完成休息；返回后重新开始工作计时。"
        ]
        for language in [AppLanguage.traditionalChinese, .english] {
            for source in messages {
                let translated = L.tr(source, language: language)
                #expect(translated != source)
                #expect(!translated.contains("·"))
                #expect(!translated.contains("%@"))
            }
        }
    }

    @Test func idleDoesNotSkipAnActiveShortBreak() throws {
        let f = try Fixture()
        defer { f.cleanUp() }
        f.store.settings.automaticRestMode = .lockSleepOrIdle
        f.store.automaticRestSeconds = 60
        f.store.activateSavedRulesForCurrentCycle()
        f.scheduler.startRestNow()
        f.idle.idleSeconds = 100
        f.scheduler.tick()
        #expect(f.scheduler.state == .resting)
        #expect(f.scheduler.remainingSeconds == 29)
    }

    @Test(arguments: [false, true])
    func nextCycleReductionCannotShortenCurrentRequirement(idle: Bool) throws {
        let f = try Fixture()
        defer { f.cleanUp() }
        f.store.settings.automaticRestMode = idle ? .lockSleepOrIdle : .lockOrSleep
        f.store.shortBreakSeconds = 90
        f.store.automaticRestSeconds = 90
        f.store.activateSavedRulesForCurrentCycle()
        f.store.shortBreakSeconds = 30
        f.store.automaticRestSeconds = 60
        #expect(f.store.automaticRestSeconds == 60)
        #expect(f.store.effectiveAutomaticRestThreshold == 90)
        if idle {
            f.idle.idleSeconds = 60
            f.scheduler.tick()
            #expect(f.scheduler.state == .working)
        } else {
            f.scheduler.startRestNow()
            f.scheduler.setComputerActivity(ComputerActivityState(isLocked: true))
            f.clock.now.addTimeInterval(60)
            f.scheduler.setComputerActivity(ComputerActivityState())
            #expect(f.scheduler.state == .resting)
            #expect(f.scheduler.remainingSeconds == 90)
        }
        f.scheduler.applyCurrentRulesToCurrentCycle()
        #expect(f.store.effectiveAutomaticRestThreshold == 60)
        #expect(f.store.currentCycleRules.shortBreakDuration == 30)
    }

    @Test func changingThresholdAfterCreditedIdleDoesNotCreditTwice() throws {
        let f = try Fixture()
        defer { f.cleanUp() }
        f.store.settings.automaticRestMode = .lockSleepOrIdle
        f.store.automaticRestSeconds = 60
        f.store.activateSavedRulesForCurrentCycle()
        f.idle.idleSeconds = 60
        f.scheduler.tick()
        f.store.automaticRestSeconds = 90
        f.scheduler.tick()
        #expect(f.scheduler.state == .idleRested)
        f.idle.idleSeconds = 0
        f.scheduler.tick()
        #expect(f.scheduler.remainingSeconds == 1200)
    }

    @Test(arguments: [false, true])
    func linkedIncreaseUsesOneCycleConfiguration(applyNow: Bool) throws {
        let f = try Fixture()
        defer { f.cleanUp() }
        f.store.shortBreakSeconds = 60
        f.store.automaticRestSeconds = 120
        f.store.activateSavedRulesForCurrentCycle()
        f.scheduler.startRestNow()
        f.scheduler.tick()
        f.store.shortBreakSeconds = 180
        #expect(f.store.automaticRestSeconds == 180)
        #expect(f.store.currentCycleRules.shortBreakDuration == 60)
        #expect(f.store.effectiveAutomaticRestThreshold == 120)
        #expect(f.scheduler.remainingSeconds == 59)
        #expect(f.store.hasPendingRuleChanges)
        if applyNow {
            f.scheduler.applyCurrentRulesToCurrentCycle()
            #expect(f.scheduler.remainingSeconds == 180)
            #expect(f.store.effectiveAutomaticRestThreshold == 180)
            #expect(!f.store.hasPendingRuleChanges)
        }
        f.scheduler.setComputerActivity(ComputerActivityState(isLocked: true))
        f.clock.now.addTimeInterval(120)
        f.scheduler.setComputerActivity(ComputerActivityState())
        #expect(f.scheduler.state == (applyNow ? .resting : .working))
        #expect(f.store.currentCycleRules.shortBreakDuration == 180)
        #expect(f.store.effectiveAutomaticRestThreshold == 180)
        #expect(!f.store.hasPendingRuleChanges)
    }

    @Test(arguments: [30, 180])
    func thresholdOnlyEditsWaitForNextCycle(seconds: Int) throws {
        let f = try Fixture()
        defer { f.cleanUp() }
        f.store.automaticRestSeconds = 120
        f.store.activateSavedRulesForCurrentCycle()
        f.scheduler.tick()
        f.store.automaticRestSeconds = seconds
        #expect(f.store.hasPendingRuleChanges)
        #expect(f.store.effectiveAutomaticRestThreshold == 120)
        #expect(f.scheduler.remainingSeconds == 1199)
        f.scheduler.setComputerActivity(ComputerActivityState(isSleeping: true))
        f.clock.now.addTimeInterval(119)
        f.scheduler.setComputerActivity(ComputerActivityState())
        #expect(f.scheduler.remainingSeconds == 1199)
        f.scheduler.setComputerActivity(ComputerActivityState(isSleeping: true))
        f.clock.now.addTimeInterval(120)
        f.scheduler.setComputerActivity(ComputerActivityState())
        #expect(f.scheduler.remainingSeconds == 1200)
        #expect(f.store.effectiveAutomaticRestThreshold == Double(seconds))
    }

    @Test(arguments: AutomaticRestMode.allCases, AutomaticRestMode.allCases)
    func modeAndThresholdSwitchTogether(old: AutomaticRestMode, new: AutomaticRestMode) throws {
        let f = try Fixture()
        defer { f.cleanUp() }
        f.store.settings.automaticRestMode = old
        f.store.automaticRestSeconds = 120
        f.store.activateSavedRulesForCurrentCycle()
        f.store.settings.automaticRestMode = new
        f.store.automaticRestSeconds = 45
        #expect(f.store.currentAutomaticRestMode == old)
        #expect(f.store.effectiveAutomaticRestThreshold == 120)
        f.idle.idleSeconds = 120
        f.scheduler.tick()
        #expect(f.scheduler.state == (old.includesIdle ? .idleRested : .working))
        if old.includesIdle {
            // Editing the mode must not prematurely restart a credited idle break.
            f.scheduler.tick()
            #expect(f.scheduler.state == .idleRested)
            f.idle.idleSeconds = 0
            f.scheduler.tick()
        } else {
            f.scheduler.resetWorkCycle()
        }
        #expect(f.store.currentAutomaticRestMode == new)
        #expect(f.store.effectiveAutomaticRestThreshold == (new.includesIdle ? 60 : 45))
        #expect(!f.store.hasPendingRuleChanges)
    }

    @Test(arguments: AutomaticRestMode.allCases, AutomaticRestMode.allCases)
    func lockReturnUsesActiveModeBeforeApplyingPendingMode(old: AutomaticRestMode, new: AutomaticRestMode) throws {
        let f = try Fixture()
        defer { f.cleanUp() }
        f.store.settings.automaticRestMode = old
        f.store.automaticRestSeconds = 120
        f.store.activateSavedRulesForCurrentCycle()
        f.scheduler.startRestNow()
        f.scheduler.tick()
        f.store.settings.automaticRestMode = new
        f.store.automaticRestSeconds = 180
        f.scheduler.setComputerActivity(ComputerActivityState(isLocked: true))
        f.clock.now.addTimeInterval(120)
        f.scheduler.setComputerActivity(ComputerActivityState())
        #expect(f.scheduler.state == (old.isEnabled ? .working : .resting))
        #expect(f.scheduler.remainingSeconds == (old.isEnabled ? 1200 : 29))
        if old.isEnabled {
            #expect(f.store.currentAutomaticRestMode == new)
            #expect(f.store.effectiveAutomaticRestThreshold == 180)
        } else {
            #expect(f.store.currentAutomaticRestMode == old)
            #expect(f.store.effectiveAutomaticRestThreshold == 120)
        }
    }

    @Test func repeatedEditsRestoreAndReloadKeepCompleteConfigurations() throws {
        let f = try Fixture()
        defer { f.cleanUp() }
        f.store.shortBreakSeconds = 60
        f.store.automaticRestSeconds = 120
        f.store.activateSavedRulesForCurrentCycle()
        let active = f.store.currentCycleConfiguration
        f.store.shortBreakSeconds = 180
        f.store.shortBreakSeconds = 30
        f.store.automaticRestSeconds = 45
        f.store.settings.automaticRestMode = .lockSleepOrIdle
        #expect(f.store.currentCycleConfiguration == active)
        #expect(f.store.automaticRestSeconds == 60)
        let reloaded = SettingsStore(userDefaults: f.defaults)
        #expect(reloaded.currentCycleConfiguration == f.store.savedCycleConfiguration)
        #expect(!reloaded.hasPendingRuleChanges)
        f.store.restoreDefaults(for: .schedule)
        #expect(f.store.currentCycleConfiguration == active)
        #expect(f.store.hasPendingRuleChanges)
        f.scheduler.resetWorkCycle()
        #expect(f.store.currentCycleConfiguration == f.store.savedCycleConfiguration)
        #expect(f.store.effectiveAutomaticRestThreshold == 300)
    }

    @Test func delayedImmediateApplyUsesLatestWholeConfigurationOnce() async throws {
        let f = try Fixture()
        defer { f.cleanUp() }
        let application = SettingsRuleApplication()
        defer { application.cancel() }
        var applications = 0
        let apply: @MainActor () -> Void = { applications += 1; f.scheduler.applyCurrentRulesToCurrentCycle() }
        f.scheduler.tick()
        f.store.settings.ruleChangeEffect = .immediate
        f.store.automaticRestSeconds = 120
        application.update(store: f.store, after: .milliseconds(20), apply: apply)
        f.store.shortBreakSeconds = 180
        application.update(store: f.store, after: .milliseconds(20), apply: apply)
        try await Task.sleep(for: .milliseconds(70))
        #expect(applications == 1)
        #expect(f.store.effectiveAutomaticRestThreshold == 180)
        #expect(f.store.currentCycleRules.shortBreakDuration == 180)
        #expect(f.scheduler.remainingSeconds == 1200)
        #expect(!application.isWaiting)
        #expect(!f.store.hasPendingRuleChanges)
    }

    @Test func scheduledApplyDoesNotRestartAnAlreadyAdvancedCycle() async throws {
        let f = try Fixture()
        defer { f.cleanUp() }
        let application = SettingsRuleApplication()
        defer { application.cancel() }
        var applications = 0
        f.store.settings.ruleChangeEffect = .immediate
        f.store.automaticRestSeconds = 90
        application.update(store: f.store, after: .milliseconds(20)) { applications += 1 }
        f.scheduler.resetWorkCycle()
        f.scheduler.tick()
        try await Task.sleep(for: .milliseconds(60))
        #expect(applications == 0)
        #expect(f.scheduler.remainingSeconds == 1199)
    }

    @Test func leavingSettingsFinishesImmediateEditsButKeepsDeferredEdits() async throws {
        let f = try Fixture()
        defer { f.cleanUp() }
        let application = SettingsRuleApplication()
        defer { application.cancel() }
        var applications = 0
        let apply: @MainActor () -> Void = { applications += 1; f.scheduler.applyCurrentRulesToCurrentCycle() }
        f.store.settings.ruleChangeEffect = .immediate
        f.store.automaticRestSeconds = 90
        application.update(store: f.store, after: .milliseconds(20), apply: apply)
        application.finishPending(store: f.store, apply: apply)
        try await Task.sleep(for: .milliseconds(60))
        #expect(applications == 1)
        #expect(f.store.effectiveAutomaticRestThreshold == 90)
        f.store.automaticRestSeconds = 120
        application.update(store: f.store, after: .milliseconds(20), apply: apply)
        f.store.settings.ruleChangeEffect = .nextCycle
        application.update(store: f.store, after: .milliseconds(20), apply: apply)
        application.finishPending(store: f.store, apply: apply)
        try await Task.sleep(for: .milliseconds(60))
        #expect(applications == 1)
        #expect(f.store.effectiveAutomaticRestThreshold == 90)
        #expect(f.store.hasPendingRuleChanges)
    }

    @Test func revertingSavedConfigurationRemovesPendingChanges() throws {
        let f = try Fixture()
        defer { f.cleanUp() }
        f.store.automaticRestSeconds = 90
        #expect(f.store.hasPendingRuleChanges)
        f.store.automaticRestSeconds = 300
        #expect(!f.store.hasPendingRuleChanges)
        f.store.settings.automaticRestMode = .disabled
        #expect(f.store.hasPendingRuleChanges)
        f.store.settings.automaticRestMode = .lockOrSleep
        #expect(!f.store.hasPendingRuleChanges)
    }

    @Test(arguments: [BreakState.working, .resting, .snoozing], [false, true])
    func individualEditsRespectCycleTimingInEveryPhase(phase: BreakState, paused: Bool) throws {
        for applyNow in [false, true] {
            for modeOnly in [false, true] {
                let f = try Fixture()
                defer { f.cleanUp() }
                f.store.shortBreakSeconds = 60
                f.store.automaticRestSeconds = 120
                f.store.activateSavedRulesForCurrentCycle()
                if phase != .working { f.scheduler.startRestNow() }
                if phase == .snoozing { f.scheduler.snoozeBreak() }
                f.scheduler.tick()
                let remaining = f.scheduler.remainingSeconds
                if paused { f.scheduler.togglePause() }
                if modeOnly {
                    f.store.settings.automaticRestMode = .lockSleepOrIdle
                } else {
                    f.store.automaticRestSeconds = 240
                }
                #expect(f.store.hasPendingRuleChanges)
                #expect(f.store.currentAutomaticRestMode == .lockOrSleep)
                #expect(f.store.effectiveAutomaticRestThreshold == 120)
                #expect(f.scheduler.remainingSeconds == remaining)
                if applyNow {
                    f.scheduler.applyCurrentRulesToCurrentCycle()
                    #expect(f.store.currentCycleConfiguration == f.store.savedCycleConfiguration)
                    let expected = phase == .working ? 1200 : phase == .resting ? 60 : 180
                    #expect(f.scheduler.remainingSeconds == expected)
                }
                #expect(f.scheduler.state == (paused ? .paused : phase))
                #expect(f.scheduler.pauseReasons == (paused ? [.user] : []))
                if paused { f.scheduler.continueUserPause() }
                if phase != .resting {
                    let remainingPhase = f.scheduler.remainingSeconds
                    for _ in 0..<remainingPhase { f.scheduler.tick() }
                    #expect(f.scheduler.state == .resting)
                    #expect(f.scheduler.remainingSeconds == 60)
                    #expect(f.store.hasPendingRuleChanges == !applyNow)
                }
                let remainingRest = f.scheduler.remainingSeconds
                for _ in 0..<remainingRest { f.scheduler.tick() }
                #expect(f.scheduler.state == .working)
                #expect(f.scheduler.remainingSeconds == 1200)
                #expect(f.store.currentCycleConfiguration == f.store.savedCycleConfiguration)
                #expect(f.store.currentAutomaticRestMode == (modeOnly ? .lockSleepOrIdle : .lockOrSleep))
                #expect(f.store.effectiveAutomaticRestThreshold == (modeOnly ? 120 : 240))
                #expect(!f.store.hasPendingRuleChanges)
            }
        }
    }

    @Test func revertingDuringImmediateDelayDoesNotResetTheTimer() async throws {
        let f = try Fixture()
        defer { f.cleanUp() }
        let application = SettingsRuleApplication()
        defer { application.cancel() }
        var applications = 0
        f.scheduler.tick()
        f.store.settings.ruleChangeEffect = .immediate
        f.store.automaticRestSeconds = 90
        application.update(store: f.store, after: .milliseconds(20)) { applications += 1 }
        f.store.automaticRestSeconds = 300
        application.update(store: f.store, after: .milliseconds(20)) { applications += 1 }
        try await Task.sleep(for: .milliseconds(60))
        #expect(applications == 0)
        #expect(f.scheduler.remainingSeconds == 1199)
        #expect(!application.isWaiting)
        #expect(!f.store.hasPendingRuleChanges)
    }

    @Test func restoringDefaultsCancelsImmediateAutomaticRestChanges() async throws {
        let f = try Fixture()
        defer { f.cleanUp() }
        f.store.shortBreakSeconds = 180
        f.store.automaticRestSeconds = 240
        f.store.activateSavedRulesForCurrentCycle()
        let active = f.store.currentCycleConfiguration
        f.store.settings.ruleChangeEffect = .immediate
        f.store.settings.automaticRestMode = .disabled
        let application = SettingsRuleApplication()
        defer { application.cancel() }
        var applications = 0
        application.update(store: f.store, after: .milliseconds(20)) { applications += 1 }
        f.store.restoreDefaults(for: .schedule)
        application.update(store: f.store, after: .milliseconds(20)) { applications += 1 }
        try await Task.sleep(for: .milliseconds(60))
        #expect(applications == 0)
        #expect(f.store.currentCycleConfiguration == active)
        #expect(f.store.settings.ruleChangeEffect == .nextCycle)
        f.scheduler.startRestNow()
        #expect(f.scheduler.remainingSeconds == 180)
        for _ in 0..<180 { f.scheduler.tick() }
        #expect(f.store.currentCycleRules.shortBreakDuration == 30)
        #expect(f.store.currentAutomaticRestMode == .lockOrSleep)
        #expect(f.store.effectiveAutomaticRestThreshold == 300)
    }

    @MainActor
    private struct Fixture {
        let suite = "AutomaticRestDuration.\(UUID().uuidString)"
        let defaults: UserDefaults
        let store: SettingsStore
        let scheduler: BreakScheduler
        let clock = Clock()
        let idle = Idle()

        init() throws {
            defaults = try #require(UserDefaults(suiteName: suite))
            store = SettingsStore(userDefaults: defaults)
            store.rules.workDuration = 1200
            store.activateSavedRulesForCurrentCycle()
            let clock = self.clock
            scheduler = BreakScheduler(settingsStore: store, notificationService: Notifications(), idleMonitor: idle,
                pauseResumeSessionStore: PauseResumeSessionStore(userDefaults: defaults), now: { clock.now })
        }

        func cleanUp() { defaults.removePersistentDomain(forName: suite) }
    }

    private final class Clock { var now = Date(timeIntervalSince1970: 1_800_000_000) }
    private final class Idle: IdleTimeProviding { var idleSeconds: TimeInterval = 0 }
    @MainActor private final class Notifications: BreakNotificationSending {
        func sendPreBreakNotification(playSound: Bool, soundEffect: RestSoundEffect) {}
    }
}

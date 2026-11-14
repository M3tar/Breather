import AppKit
import XCTest
@testable import Breather

private final class DiagnosticTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value = Date(timeIntervalSince1970: 1_800_000_000)
    var now: Date { lock.withLock { value } }
    func advance(_ seconds: TimeInterval) { lock.withLock { value.addTimeInterval(seconds) } }
}

final class DiagnosticStoreTests: XCTestCase {
    private var root: URL!
    private var clock: DiagnosticTestClock!
    private var directory: URL { root.appendingPathComponent("logs") }
    private var snapshot: DiagnosticSnapshot {
        DiagnosticSnapshot(environment: DiagnosticEnvironment(appVersion: "1.0.0", build: "1", macOSVersion: "15.0", architecture: "arm64"),
                           scheduler: nil, overlay: nil, settings: nil)
    }
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("Breather-Diagnostics-Test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        clock = DiagnosticTestClock()
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }
    private func store(limits: DiagnosticStore.Limits = .init(), enabled: Bool = true) -> DiagnosticStore {
        let clock = clock!
        return DiagnosticStore(directory: directory, enabled: enabled, limits: limits, clock: { clock.now })
    }
    private func files() throws -> [URL] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).sorted { $0.path < $1.path }
    }
    private func records() throws -> [DiagnosticEvent] {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        return try files().filter { $0.pathExtension == "jsonl" }.flatMap { file in
            try Data(contentsOf: file).split(separator: 10).map { try decoder.decode(DiagnosticEvent.self, from: Data($0)) }
        }
    }

    func testRecordsPersistAcrossRestartWithPrivatePermissionsAndOrderedSequences() async throws {
        let first = store()
        first.record(.appStarted, snapshot: snapshot)
        first.record(.snapshot, snapshot: snapshot)
        await first.flush()
        let prior = try records()
        XCTAssertEqual(prior.map(\.sequence), [1, 2])
        let second = store()
        second.record(.appStarted, snapshot: snapshot)
        await second.flush()
        let all = try records()
        XCTAssertEqual(all.count, 3)
        XCTAssertNotEqual(all[0].launchID, all[2].launchID)
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: directory.path)[.posixPermissions] as? Int, 0o700)
        for file in try files() {
            XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int, 0o600)
        }
    }

    func testRotationAndCapacityBoundDiskUsage() async throws {
        var limits = DiagnosticStore.Limits(); limits.fileBytes = 1000; limits.totalBytes = 2500
        let recorder = store(limits: limits)
        for _ in 0..<30 { recorder.record(.snapshot, snapshot: snapshot); await recorder.flush() }
        let sizes = try files().map { try $0.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0 }
        XCTAssertGreaterThan(sizes.count, 1)
        XCTAssertTrue(sizes.allSatisfy { $0 <= limits.fileBytes })
        XCTAssertLessThanOrEqual(sizes.reduce(0, +), limits.totalBytes)
        let sequences = try records().map(\.sequence)
        XCTAssertEqual(sequences, sequences.sorted())
        XCTAssertEqual(sequences.last, 30)
    }

    func testTerminationFlushWritesFinalBatchBeforeReturning() throws {
        let recorder = store()
        recorder.record(.appStarted)
        recorder.record(.snapshot, snapshot: snapshot)
        recorder.record(.appStopped)
        XCTAssertTrue(recorder.flushForTermination())
        XCTAssertEqual(try records().map(\.kind), [.appStarted, .snapshot, .appStopped])
        recorder.setEnabled(false)
        recorder.record(.appStopped)
        XCTAssertTrue(recorder.flushForTermination())
        XCTAssertEqual(try records().count, 3)
    }

    func testTerminationFlushHasBoundedWaitWhenIOQueueIsBusy() throws {
        let queue = DispatchQueue(label: "DiagnosticsTests.blocked-io")
        let entered = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0)
        queue.async { entered.signal(); release.wait() }
        XCTAssertEqual(entered.wait(timeout: .now() + 2), .success)
        let recorder = DiagnosticStore(directory: directory, queue: queue)
        recorder.record(.appStopped)
        let start = ProcessInfo.processInfo.systemUptime
        let completed = recorder.flushForTermination(timeout: 0.03)
        let elapsed = ProcessInfo.processInfo.systemUptime - start
        release.signal()
        XCTAssertFalse(completed)
        XCTAssertLessThan(elapsed, 1)
        XCTAssertTrue(recorder.flushForTermination())
        XCTAssertEqual(try records().map(\.kind), [.appStopped])
    }

    func testTerminationFlushReportsStorageFailure() throws {
        try Data("not a directory".utf8).write(to: directory)
        let recorder = store()
        recorder.record(.appStopped)
        XCTAssertFalse(recorder.flushForTermination())
        XCTAssertNotNil(recorder.health.lastError)
    }

    func testNextLaunchCleansAbandonedExportButKeepsActiveExportAndSavedZIP() async throws {
        var owner: DiagnosticStore? = store()
        weak let weakOwner = owner
        owner!.record(.appStarted)
        let exported = try await owner!.export(snapshot: snapshot)
        let saved = root.appendingPathComponent("user-saved.zip")
        try await owner!.saveExport(exported, to: saved)
        let savedBytes = try Data(contentsOf: saved)
        let other = store(enabled: false)
        await other.maintenance()
        XCTAssertTrue(FileManager.default.fileExists(atPath: exported.archive.path), "Another store must respect an active export's lease")
        XCTAssertNil(other.health.lastError)
        owner = nil
        for _ in 0..<100 where weakOwner != nil { await Task.yield() }
        XCTAssertNil(weakOwner)
        await other.maintenance()
        XCTAssertFalse(FileManager.default.fileExists(atPath: exported.directory.path))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: other.exportStagingDirectory.path), [])
        XCTAssertEqual(try Data(contentsOf: saved), savedBytes)
        XCTAssertEqual(try records().map(\.kind), [.appStarted])
    }

    func testStagingCleanupIgnoresUnrelatedFilesAndSymbolicLinks() async throws {
        let recorder = store()
        let exported = try await recorder.export(snapshot: snapshot)
        await recorder.removeExport(exported)
        let staging = recorder.exportStagingDirectory
        let unrelated = staging.appendingPathComponent("report.zip")
        try Data("saved report".utf8).write(to: unrelated)
        let outside = root.appendingPathComponent("outside.txt")
        try Data("keep".utf8).write(to: outside)
        let link = staging.appendingPathComponent("export-\(UUID()).lock")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        await recorder.maintenance()
        XCTAssertNil(recorder.health.lastError)
        XCTAssertEqual(try String(contentsOf: outside, encoding: .utf8), "keep")
        XCTAssertEqual(try Data(contentsOf: unrelated), Data("saved report".utf8))
        XCTAssertTrue(FileManager.default.fileExists(atPath: link.path))
    }

    func testMaintenanceCanRaceExportCreationAndRemoval() async throws {
        let recorder = store(), cleaner = store(enabled: false)
        let cleaning = Task { for _ in 0..<60 { await cleaner.maintenance() } }
        for _ in 0..<15 {
            let export = try await recorder.export(snapshot: snapshot)
            XCTAssertTrue(FileManager.default.fileExists(atPath: export.archive.path))
            await recorder.removeExport(export)
        }
        await cleaning.value
        XCTAssertNil(cleaner.health.lastError)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: recorder.exportStagingDirectory.path), [])
    }

    func testFailedExportReleasesItsStagingAndLease() async throws {
        let recorder = store()
        let invalid = DiagnosticSnapshot(environment: snapshot.environment, scheduler: nil, overlay: nil,
            settings: DiagnosticSettingsSnapshot(workSeconds: .nan, shortBreakSeconds: 30,
                automaticRestMode: "off", automaticRestThreshold: 60, pauseDuringMirroring: false,
                theme: "classic", fadeAnimation: false))
        do {
            _ = try await recorder.export(snapshot: invalid)
            XCTFail("Non-finite values must fail JSON encoding")
        } catch { }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: recorder.exportStagingDirectory.path), [])
        let successful = try await recorder.export(snapshot: snapshot)
        await recorder.removeExport(successful)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: recorder.exportStagingDirectory.path), [])
    }

    func testNoTimeExpiryAndDisabledRecordingPreservesOldLogs() async throws {
        let recorder = store()
        recorder.record(.appStarted); await recorder.flush()
        recorder.setEnabled(false)
        clock.advance(8 * 86400)
        await recorder.maintenance()
        XCTAssertEqual(try records().count, 1)
        recorder.record(.snapshot); await recorder.flush()
        XCTAssertEqual(try records().count, 1)
    }

    func testDisableAndClearDoNotResurrectQueuedRecords() async throws {
        let recorder = store()
        for _ in 0..<500 { recorder.record(.snapshot) }
        recorder.setEnabled(false)
        await recorder.flush()
        try await recorder.clear()
        recorder.record(.appStarted)
        await recorder.flush()
        XCTAssertTrue(try records().isEmpty)
        recorder.setEnabled(true)
        recorder.record(.recordingEnabled)
        await recorder.flush()
        XCTAssertEqual(try records().map(\.kind), [.recordingEnabled])
    }

    func testBoundedMailboxReportsLossWithoutBreakingSequenceOrder() async throws {
        var limits = DiagnosticStore.Limits(); limits.pendingEvents = 1
        let recorder = store(limits: limits)
        for _ in 0..<5000 { recorder.record(.snapshot) }
        await recorder.flush()
        recorder.record(.appStarted)
        await recorder.flush()
        XCTAssertGreaterThan(recorder.health.droppedEvents, 0)
        let records = try records()
        XCTAssertTrue(records.contains { $0.kind == .dataLoss })
        XCTAssertEqual(records.map(\.sequence), records.map(\.sequence).sorted())
        XCTAssertEqual(Set(records.map(\.sequence)).count, records.count)
    }

    func testWriteFailureBacksOffAndRecovers() async throws {
        try Data("not a directory".utf8).write(to: directory)
        let recorder = store()
        recorder.record(.appStarted); await recorder.flush()
        XCTAssertEqual(recorder.health.writeFailures, 1)
        recorder.record(.snapshot); await recorder.flush()
        XCTAssertEqual(recorder.health.writeFailures, 1)
        try FileManager.default.removeItem(at: directory)
        clock.advance(61)
        recorder.record(.snapshot); await recorder.flush()
        XCTAssertNil(recorder.health.lastError)
        XCTAssertFalse(try records().isEmpty)
    }

    func testZIPExportIncludesAllRetainedRecordsReportsCorruptionAndCleansTemporaryFiles() async throws {
        let recorder = store()
        recorder.record(.appStarted, snapshot: snapshot); await recorder.flush()
        clock.advance(2 * 86400)
        recorder.record(.snapshot, snapshot: snapshot); await recorder.flush()
        let file = try XCTUnwrap(try files().last)
        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd(); try handle.write(contentsOf: Data("incomplete record\n".utf8)); try handle.close()
        let export = try await recorder.export(snapshot: snapshot)
        XCTAssertEqual(export.eventCount, 2)
        XCTAssertEqual(export.malformedLines, 1)
        XCTAssertGreaterThan(export.bytes, 0)
        let summary = try String(contentsOf: export.directory.appendingPathComponent("Breather-Diagnostics/summary.txt"), encoding: .utf8)
        XCTAssertTrue(summary.contains("Unreadable lines skipped: 1"))
        let zip = try Data(contentsOf: export.archive)
        XCTAssertEqual(Array(zip.prefix(2)), [0x50, 0x4b])
        let destination = root.appendingPathComponent("saved.zip")
        try await recorder.saveExport(export, to: destination)
        await recorder.removeExport(export)
        XCTAssertFalse(FileManager.default.fileExists(atPath: export.directory.path))
        XCTAssertEqual(try Data(contentsOf: destination), zip)
        let all = try await recorder.export(snapshot: snapshot)
        XCTAssertEqual(all.eventCount, 2)
        await recorder.removeExport(all)
    }

    func testExportSnapshotIsStableWhileLaterEventsContinue() async throws {
        let recorder = store()
        recorder.record(.appStarted); await recorder.flush()
        let export = try await recorder.export(snapshot: snapshot)
        recorder.record(.snapshot); await recorder.flush()
        XCTAssertEqual(export.eventCount, 1)
        XCTAssertEqual(try records().count, 2)
        await recorder.removeExport(export)
    }

    func testExportIgnoresUnrelatedFilesAndSymlinks() async throws {
        let recorder = store()
        recorder.record(.appStarted); await recorder.flush()
        let secret = root.appendingPathComponent("private.txt")
        try Data("SECRET_SHOULD_NEVER_EXPORT".utf8).write(to: secret)
        try FileManager.default.createSymbolicLink(at: directory.appendingPathComponent("events-1800000000000-link.jsonl"), withDestinationURL: secret)
        try Data("SECRET_SHOULD_NEVER_EXPORT".utf8).write(to: directory.appendingPathComponent("unrelated.txt"))
        let export = try await recorder.export(snapshot: snapshot)
        let text = try String(contentsOf: export.directory.appendingPathComponent("Breather-Diagnostics/events.jsonl"), encoding: .utf8)
        XCTAssertFalse(text.contains("SECRET"))
        XCTAssertEqual(export.eventCount, 1)
        await recorder.removeExport(export)
        try await recorder.clear()
        XCTAssertTrue(FileManager.default.fileExists(atPath: secret.path))
    }
}

@MainActor
final class DiagnosticsIntegrationTests: XCTestCase {
    func testControllerTerminationFlushIsIdempotentAndRecordingOffStaysOff() throws {
        let suite = "DiagnosticsTerminationTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        defer { try? FileManager.default.removeItem(at: root) }
        let controller = DiagnosticsController(directory: root, userDefaults: defaults)
        controller.store.record(.appStarted)
        XCTAssertTrue(controller.prepareForTermination())
        controller.sample()
        XCTAssertTrue(controller.prepareForTermination())
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let events = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "jsonl" }.flatMap {
                try Data(contentsOf: $0).split(separator: 10).map { try decoder.decode(DiagnosticEvent.self, from: Data($0)) }
            }
        XCTAssertEqual(events.map(\.kind), [.appStarted, .appStopped])
        defaults.set(false, forKey: "breather.diagnostics.enabled")
        let disabledDirectory = root.appendingPathComponent("disabled")
        let disabled = DiagnosticsController(directory: disabledDirectory, userDefaults: defaults)
        XCTAssertTrue(disabled.prepareForTermination())
        XCTAssertFalse(FileManager.default.fileExists(atPath: disabledDirectory.path))
    }

    func testDismissalEventsKeepClosingSessionIdentityInExport() async throws {
        let suite = "DiagnosticsDismissalTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        defer { try? FileManager.default.removeItem(at: root) }
        let settings = SettingsStore(userDefaults: defaults)
        let scheduler = BreakScheduler(settingsStore: settings, notificationService: DiagnosticNotifications(), idleMonitor: DiagnosticIdle(),
            pauseResumeSessionStore: PauseResumeSessionStore(userDefaults: defaults))
        let activity = ComputerActivityMonitor(workspaceCenter: NotificationCenter(), distributedCenter: NotificationCenter(), readSession: { (false, true) })
        let overlay = RestOverlayWindowController(scheduler: scheduler, onSnooze: {}, onSkip: {}, presentsWindows: false)
        let controller = DiagnosticsController(directory: root, userDefaults: defaults)
        controller.start(scheduler: scheduler, activity: activity, overlay: overlay, settings: settings)
        scheduler.startRestNow()
        overlay.show()
        let firstID = try XCTUnwrap(overlay.session?.id)
        let remaining = overlay.session?.remainingSeconds
        overlay.hideRest()
        XCTAssertNil(overlay.session)
        overlay.show()
        let secondID = try XCTUnwrap(overlay.session?.id)
        XCTAssertNotEqual(firstID, secondID)
        let export = try await controller.store.export(snapshot: controller.snapshot)
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let events = try Data(contentsOf: export.directory.appendingPathComponent("Breather-Diagnostics/events.jsonl"))
            .split(separator: 10).map { try decoder.decode(DiagnosticEvent.self, from: Data($0)) }
        let closing = events.filter { $0.reason == "dismissalStarted" || $0.reason == "dismissalCompleted" }
        XCTAssertEqual(closing.map(\.reason), ["dismissalStarted", "dismissalCompleted"])
        for event in closing {
            XCTAssertEqual(event.snapshot?.overlay?.sessionID, firstID)
            XCTAssertEqual(event.snapshot?.overlay?.isDismissing, true)
            XCTAssertEqual(event.snapshot?.overlay?.remainingSeconds, remaining)
        }
        XCTAssertEqual(closing.last?.snapshot?.overlay?.windowCount, 0)
        XCTAssertEqual(controller.snapshot.overlay?.sessionID, secondID)
        await controller.store.removeExport(export)
        overlay.shutdown()
        XCTAssertTrue(controller.prepareForTermination())
        let finalEvents = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "jsonl" }.flatMap {
                try Data(contentsOf: $0).split(separator: 10).map { try decoder.decode(DiagnosticEvent.self, from: Data($0)) }
            }.sorted { $0.sequence < $1.sequence }
        XCTAssertEqual(finalEvents.suffix(3).map(\.reason), ["dismissalStarted", "dismissalCompleted", nil])
        XCTAssertEqual(finalEvents.last?.kind, .appStopped)
    }

    func testAnimatedDismissalCompletionDoesNotReportReplacementSession() async throws {
        let suite = "DiagnosticsAnimatedDismissalTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsStore(userDefaults: defaults)
        settings.settings.restOverlayContentMode = .classic
        settings.settings.restOverlayBackground = .sun
        settings.settings.restOverlayFadeAnimation = true
        let scheduler = BreakScheduler(settingsStore: settings, notificationService: DiagnosticNotifications(), idleMonitor: DiagnosticIdle(),
            pauseResumeSessionStore: PauseResumeSessionStore(userDefaults: defaults))
        // Empty screens exercise the delayed dismissal path without showing any windows.
        let overlay = RestOverlayWindowController(scheduler: scheduler, onSnooze: {}, onSkip: {},
            screens: { [] }, reduceMotion: { false }, presentsWindows: true)
        defer { overlay.shutdown() }
        scheduler.startRestNow()
        overlay.show()
        let firstID = try XCTUnwrap(overlay.session?.id)
        let completed = expectation(description: "Closing session finishes its animation")
        var closingEvents: [(String, DiagnosticOverlaySnapshot)] = []
        overlay.onDiagnosticChange = { reason, snapshot in
            guard snapshot.sessionID == firstID else { return }
            closingEvents.append((reason, snapshot))
            if reason == "dismissalCompleted" { completed.fulfill() }
        }
        overlay.hideRest()
        overlay.show()
        let secondID = try XCTUnwrap(overlay.session?.id)
        await fulfillment(of: [completed], timeout: 2)
        XCTAssertNotEqual(firstID, secondID)
        XCTAssertEqual(overlay.session?.id, secondID)
        XCTAssertEqual(closingEvents.map { $0.0 }, ["dismissalStarted", "dismissalCompleted"])
        XCTAssertTrue(closingEvents.allSatisfy { $0.1.sessionID == firstID && $0.1.isDismissing })
        XCTAssertEqual(closingEvents.last?.1.windowCount, 0)
    }

    func testDuplicateSystemEventsAreRecordedBeforeStateDeduplication() {
        let workspace = NotificationCenter(), distributed = NotificationCenter()
        let monitor = ComputerActivityMonitor(workspaceCenter: workspace, distributedCenter: distributed, readSession: { (nil, true) })
        var events: [DiagnosticSystemEvent] = []
        var changes = 0
        monitor.onEvent = { events.append($0) }
        monitor.onStateChanged = { _ in changes += 1 }
        monitor.start()
        XCTAssertEqual(events.first?.name, "initialSample")
        events.removeAll()
        distributed.post(name: ComputerActivityMonitor.screenLockedNotification, object: nil)
        distributed.post(name: ComputerActivityMonitor.screenLockedNotification, object: nil)
        distributed.post(name: ComputerActivityMonitor.screenUnlockedNotification, object: nil)
        XCTAssertEqual(events.map(\.name), ["lock", "lock", "unlock"])
        XCTAssertEqual(changes, 2)
        XCTAssertNil(events[0].observedLocked)
        XCTAssertFalse(events[0].before.isLocked)
        XCTAssertTrue(events[0].after.isLocked)
        monitor.stop()
    }

    func testSnapshotSeparatesPausedTimerAndStaleOverlayWithoutChangingBehavior() async throws {
        let suite = "DiagnosticsIntegrationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        defer { try? FileManager.default.removeItem(at: root) }
        let settings = SettingsStore(userDefaults: defaults)
        defaults.set("SECRET_USERNAME", forKey: "unrelated_private_preference")
        let scheduler = BreakScheduler(settingsStore: settings, notificationService: DiagnosticNotifications(), idleMonitor: DiagnosticIdle(),
                                       pauseResumeSessionStore: PauseResumeSessionStore(userDefaults: defaults))
        let activity = ComputerActivityMonitor(workspaceCenter: NotificationCenter(), distributedCenter: NotificationCenter(), readSession: { (false, true) })
        let overlay = RestOverlayWindowController(scheduler: scheduler, onSnooze: {}, onSkip: {}, presentsWindows: false)
        let controller = DiagnosticsController(directory: root, userDefaults: defaults)
        controller.start(scheduler: scheduler, activity: activity, overlay: overlay, settings: settings)
        scheduler.startRestNow()
        overlay.show()
        scheduler.tick()
        let running = scheduler.diagnosticSnapshot
        XCTAssertEqual(running.tickCount, 1)
        XCTAssertNotNil(running.lastProgressUptime)
        scheduler.setComputerActivity(ComputerActivityState(isLocked: true))
        let remaining = scheduler.remainingSeconds
        scheduler.tick()
        controller.sample()
        let paused = controller.snapshot
        XCTAssertEqual(paused.scheduler?.tickCount, 2)
        XCTAssertEqual(paused.scheduler?.state, "paused")
        XCTAssertEqual(paused.scheduler?.pauseReasons, ["computerUnavailable"])
        XCTAssertEqual(scheduler.remainingSeconds, remaining)
        XCTAssertEqual(paused.overlay?.remainingSeconds, remaining)
        let export = try await controller.store.export(snapshot: controller.snapshot)
        let json = try String(contentsOf: export.directory.appendingPathComponent("Breather-Diagnostics/snapshot.json"), encoding: .utf8)
        XCTAssertFalse(json.contains("SECRET_USERNAME"))
        XCTAssertFalse(json.contains(NSHomeDirectory()))
        await controller.store.removeExport(export)
        controller.setEnabled(false)
        XCTAssertFalse(defaults.bool(forKey: "breather.diagnostics.enabled"))
        controller.stop()
        await controller.store.flush()
        overlay.shutdown()
    }

    func testSimpleExportAndClearActions() async throws {
        let suite = "DiagnosticsActionsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let controller = DiagnosticsController(directory: root.appendingPathComponent("logs"), userDefaults: defaults)
        controller.store.record(.appStarted)
        let output = root.appendingPathComponent("report.zip")
        await controller.export(to: output)
        XCTAssertTrue(FileManager.default.fileExists(atPath: output.path))
        XCTAssertFalse(controller.isExporting)
        XCTAssertEqual(controller.message?.text, L.tr("日志已导出"))
        XCTAssertEqual(controller.message?.isError, false)
        let preserved = try Data(contentsOf: output)
        await controller.export(to: root.appendingPathComponent("missing/report.zip"))
        XCTAssertFalse(controller.isExporting)
        XCTAssertEqual(controller.message?.text, L.tr("无法导出日志，请重试。"))
        XCTAssertEqual(controller.message?.isError, true)
        controller.dismissMessage()
        XCTAssertNil(controller.message, "Leaving the page clears action errors")
        let cancelled = Task { @MainActor in await controller.export(to: root.appendingPathComponent("cancelled.zip")) }
        cancelled.cancel()
        await cancelled.value
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("cancelled.zip").path))
        controller.setEnabled(false)
        let stoppedRecordingOutput = root.appendingPathComponent("recording-off.zip")
        await controller.export(to: stoppedRecordingOutput)
        XCTAssertTrue(FileManager.default.fileExists(atPath: stoppedRecordingOutput.path))
        XCTAssertFalse(controller.isEnabled, "Exporting existing logs must not turn recording back on")
        await controller.clearLogs()
        XCTAssertEqual(controller.message?.text, L.tr("日志已清除"))
        XCTAssertEqual(controller.message?.isError, false)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: controller.store.directory.path), ["Exports"])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: controller.store.exportStagingDirectory.path), [])
        XCTAssertEqual(try Data(contentsOf: output), preserved)
        controller.stop()
        await controller.store.flush()
    }

    func testSamplingCadenceAndPrivacySettingPersist() {
        XCTAssertEqual(DiagnosticsController.samplingInterval(hasRestOverlay: true, recentlyUnlocked: false), 5)
        XCTAssertEqual(DiagnosticsController.samplingInterval(hasRestOverlay: false, recentlyUnlocked: true), 5)
        XCTAssertEqual(DiagnosticsController.samplingInterval(hasRestOverlay: false, recentlyUnlocked: false), 60)
        let suite = "DiagnosticsPrivacyTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        let controller = DiagnosticsController(directory: root, userDefaults: defaults)
        XCTAssertTrue(controller.isEnabled)
        controller.setEnabled(false)
        let reloaded = DiagnosticsController(directory: root, userDefaults: defaults)
        XCTAssertFalse(reloaded.isEnabled)
    }
}

private final class DiagnosticIdle: IdleTimeProviding { var idleSeconds: TimeInterval = 0 }
@MainActor private final class DiagnosticNotifications: BreakNotificationSending {
    func sendPreBreakNotification(playSound: Bool, soundEffect: RestSoundEffect) { }
}

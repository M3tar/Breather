import AppKit
import Combine
import UniformTypeIdentifiers

@MainActor
final class DiagnosticsController: ObservableObject {
    @Published private(set) var isEnabled: Bool
    @Published private(set) var isExporting = false
    @Published private(set) var message: SettingsToastMessage?
    @Published private(set) var storageHasError = false

    let store: DiagnosticStore
    private let defaults: UserDefaults
    private let enabledKey = "breather.diagnostics.enabled"
    private weak var scheduler: BreakScheduler?
    private weak var overlay: RestOverlayWindowController?
    private weak var settingsStore: SettingsStore?
    private weak var activityMonitor: ComputerActivityMonitor?
    private var messageGeneration = 0
    private var hasStopped = false
    private var subscriptions: Set<AnyCancellable> = []
    private var samplingTask: Task<Void, Never>?
    private var recentUnlockUntil = Date.distantPast
    private var lastScheduler: DiagnosticSchedulerSnapshot?
    private var lastSettings: DiagnosticSettingsSnapshot?

    init(directory: URL? = nil, userDefaults: UserDefaults = .standard) {
        defaults = userDefaults
        let enabled = userDefaults.object(forKey: enabledKey) as? Bool ?? true
        isEnabled = enabled
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        #if DEBUG
        let component = "Breather-Debug"
        #else
        let component = "Breather"
        #endif
        store = DiagnosticStore(directory: directory ?? support.appendingPathComponent(component).appendingPathComponent("Diagnostics"), enabled: enabled)
    }

    func start(scheduler: BreakScheduler, activity: ComputerActivityMonitor,
               overlay: RestOverlayWindowController, settings: SettingsStore) {
        self.scheduler = scheduler
        self.overlay = overlay
        settingsStore = settings
        activityMonitor = activity
        hasStopped = false
        scheduler.onDiagnosticChange = { [weak self] reason, state in
            guard let self, self.isEnabled else { return }
            if self.lastScheduler.map({ state.hasSameTransition(as: $0) }) != true {
                self.lastScheduler = state
                self.store.record(.schedulerChanged, reason: reason, snapshot: self.snapshot)
                self.restartSampling()
            }
        }
        activity.onEvent = { [weak self] event in
            guard let self, self.isEnabled else { return }
            self.store.record(.systemEvent, system: event)
            if ["unlock", "wake", "sessionActive"].contains(event.name) {
                self.recentUnlockUntil = Date().addingTimeInterval(120)
                self.restartSampling()
            }
        }
        overlay.onDiagnosticChange = { [weak self] reason, overlayState in
            guard let self, self.isEnabled else { return }
            let current = self.snapshot
            let eventSnapshot = DiagnosticSnapshot(environment: current.environment, scheduler: current.scheduler,
                                                   overlay: overlayState, settings: current.settings)
            self.store.record(.overlayChanged, reason: reason, snapshot: eventSnapshot)
            self.restartSampling()
        }
        settings.$settings.sink { [weak self] _ in
            // @Published emits before mutation; read the installed settings next turn.
            Task { @MainActor [weak self] in self?.recordSettingsIfChanged() }
        }.store(in: &subscriptions)
        settings.$currentCycleConfiguration.sink { [weak self] _ in
            Task { @MainActor [weak self] in self?.recordSettingsIfChanged() }
        }.store(in: &subscriptions)
        store.record(.appStarted, snapshot: snapshot)
        recordSettingsIfChanged()
        restartSampling()
        Task { await store.maintenance() }
    }

    var snapshot: DiagnosticSnapshot {
        DiagnosticSnapshot(environment: .current, scheduler: scheduler?.diagnosticSnapshot,
                           overlay: overlay?.diagnosticSnapshot, settings: settingsSnapshot)
    }

    private var settingsSnapshot: DiagnosticSettingsSnapshot? {
        guard let store = settingsStore else { return nil }
        let settings = store.settings
        return DiagnosticSettingsSnapshot(workSeconds: store.currentCycleRules.workDuration,
            shortBreakSeconds: store.currentCycleRules.shortBreakDuration,
            automaticRestMode: settings.automaticRestMode.rawValue, automaticRestThreshold: settings.automaticRestThreshold,
            pauseDuringMirroring: settings.autoPauseDuringDisplayMirroring, theme: settings.restOverlayContentMode.rawValue,
            fadeAnimation: settings.restOverlayFadeAnimation,
            effectiveAutomaticRestThreshold: store.effectiveAutomaticRestThreshold,
            effectiveAutomaticRestMode: store.currentAutomaticRestMode.rawValue)
    }

    private func recordSettingsIfChanged() {
        guard !hasStopped, isEnabled, let current = settingsSnapshot, current != lastSettings else { return }
        lastSettings = current
        store.record(.settingsChanged, snapshot: snapshot)
    }

    static func samplingInterval(hasRestOverlay: Bool, recentlyUnlocked: Bool) -> TimeInterval {
        hasRestOverlay || recentlyUnlocked ? 5 : 60
    }

    private func restartSampling() {
        samplingTask?.cancel()
        samplingTask = nil
        guard !hasStopped, isEnabled else { return }
        samplingTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let delay = Self.samplingInterval(hasRestOverlay: self.overlay?.session?.kind == .rest,
                                                  recentlyUnlocked: Date() < self.recentUnlockUntil)
                do { try await Task.sleep(for: .seconds(delay)) } catch { return }
                guard !Task.isCancelled, self.isEnabled else { return }
                self.sample()
            }
        }
    }

    // Independent of BreakScheduler.tick(): a stopped countdown can still be observed.
    func sample() {
        guard !hasStopped, isEnabled else { return }
        store.record(.snapshot, snapshot: snapshot)
        storageHasError = store.health.lastError != nil
    }

    func setEnabled(_ enabled: Bool) {
        guard isEnabled != enabled else { return }
        dismissMessage()
        isEnabled = enabled
        defaults.set(enabled, forKey: enabledKey)
        store.setEnabled(enabled)
        if enabled {
            lastScheduler = nil
            lastSettings = nil
            store.record(.recordingEnabled, snapshot: snapshot)
            recordSettingsIfChanged()
        }
        restartSampling()
        // Maintenance remains available when recording is off.
        Task { await store.maintenance() }
    }

    func stop() {
        guard !hasStopped else { return }
        hasStopped = true
        store.record(.appStopped, snapshot: snapshot)
        samplingTask?.cancel()
        samplingTask = nil
        subscriptions.removeAll()
        scheduler?.onDiagnosticChange = nil
        overlay?.onDiagnosticChange = nil
        activityMonitor?.onEvent = nil
    }

    @discardableResult
    func prepareForTermination(timeout: TimeInterval = 2) -> Bool {
        stop()
        return store.flushForTermination(timeout: timeout)
    }

    func exportLogs() async {
        guard !isExporting else { return }
        isExporting = true
        defer { isExporting = false }
        dismissMessage()
        let generation = messageGeneration
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.zip]
        panel.nameFieldStringValue = "Breather-Diagnostics.zip"
        guard await panel.begin() == .OK, let url = panel.url else { return }
        await writeExport(to: url, generation: generation)
    }

    // Separate from the save panel so the real export and cleanup path is testable.
    func export(to destination: URL) async {
        guard !isExporting else { return }
        isExporting = true
        defer { isExporting = false }
        dismissMessage()
        await writeExport(to: destination, generation: messageGeneration)
    }

    private func writeExport(to destination: URL, generation: Int) async {
        var prepared: DiagnosticExport?
        do {
            try Task.checkCancellation()
            let result = try await store.export(snapshot: snapshot)
            prepared = result
            try Task.checkCancellation()
            try await store.saveExport(result, to: destination)
            if generation == messageGeneration { message = SettingsToastMessage(text: L.tr("日志已导出")) }
        } catch {
            if !Task.isCancelled, generation == messageGeneration { message = SettingsToastMessage(text: L.tr("无法导出日志，请重试。"), isError: true) }
        }
        if let prepared { await store.removeExport(prepared) }
    }

    func dismissMessage() {
        messageGeneration += 1
        message = nil
    }

    func clearLogs() async {
        guard !isExporting else { return }
        dismissMessage()
        let generation = messageGeneration
        do {
            try await store.clear()
            storageHasError = false
            if generation == messageGeneration { message = SettingsToastMessage(text: L.tr("日志已清除")) }
        } catch {
            if generation == messageGeneration { message = SettingsToastMessage(text: L.tr("无法清除日志，请重试。"), isError: true) }
        }
    }
}

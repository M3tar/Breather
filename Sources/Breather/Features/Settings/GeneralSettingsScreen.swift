import AppKit
import SwiftUI

struct GeneralSettingsScreen: View {
    @ObservedObject var settingsStore: SettingsStore
    @State private var languageCode = AppLanguage.selected.rawValue
    let notificationService: any NotificationSettingsServicing
    let restSoundService: RestSoundService
    var focusNotifications = false

    private let launchAtLoginService = LaunchAtLoginService()

    @State private var launchAtLoginStatus: LaunchAtLoginStatus = .detecting
    @State private var launchAtLoginMessage: String?
    @State private var notificationPermissionStatus: NotificationPermissionStatus?
    @State private var notificationPreviewResult: NotificationPreviewResult?
    @State private var notificationFeedbackTask: Task<Void, Never>?
    @State private var notificationOperation: NotificationPermissionOperation?

    var body: some View {
        ScrollViewReader { proxy in
            SettingsScreenContainer {
                applicationGroup
                notificationGroup
                    .id("notifications")
            }
            .task {
                if focusNotifications {
                    await Task.yield()
                    proxy.scrollTo("notifications", anchor: .top)
                }
                refreshLaunchAtLoginStatus()
                await refreshNotificationPermissionStatus()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshLaunchAtLoginStatus()
            Task {
                await refreshNotificationPermissionStatus()
            }
        }
        .onDisappear {
            notificationFeedbackTask?.cancel()
        }
        .onReceive(LocalizationRefresh.shared.$revision) { _ in
            languageCode = AppLanguage.selected.rawValue
        }
    }

    private var applicationGroup: some View {
        SettingsGroup(L.tr("应用")) {
            SettingsRow(title: L.tr("界面语言")) {
                SettingsMenuPicker(L.tr("界面语言"), selection: Binding(
                    get: { languageCode },
                    set: { newValue in
                        languageCode = newValue
                        // Apply on the next run-loop turn, after native menu tracking ends.
                        DispatchQueue.main.async {
                            UserDefaults.standard.set(newValue, forKey: AppLanguage.preferenceKey)
                            LocalizationRefresh.shared.refresh()
                        }
                    }
                ), options: AppLanguage.allCases.map {
                    SettingsMenuOption(value: $0.rawValue, title: $0.title)
                })
                .fixedSize()
            }

            SettingsRow(title: L.tr("应用外观")) {
                SettingsMenuPicker(L.tr("应用外观"), selection: appearancePreferenceBinding,
                    options: AppearancePreference.allCases.map {
                        SettingsMenuOption(value: $0, title: $0.title)
                    })
                    .fixedSize()
            }

            SettingsRow(title: L.tr("登录时自动启动")) {
                LaunchAtLoginControl(
                    isOn: launchAtLoginBinding,
                    status: launchAtLoginStatus,
                    message: launchAtLoginMessage
                )
            }
        }
    }

    private var notificationGroup: some View {
        SettingsGroup(L.tr("通知")) {
            SettingsRow(title: L.tr("通知声音")) {
                SoundEffectControl(selection: notificationSoundEffectBinding) {
                    previewSound(settingsStore.settings.notificationSoundEffect)
                }
            }

            SettingsRow(title: L.tr("系统通知")) {
                NotificationPermissionControl(
                    status: notificationPermissionStatus,
                    operation: notificationOperation,
                    previewResult: notificationPreviewResult,
                    onRefresh: {
                        Task { await refreshNotificationPermissionStatus() }
                    },
                    onOpenSettings: {
                        Task { await openNotificationSettings() }
                    },
                    onTestNotification: {
                        Task { await testNotification() }
                    }
                )
            }
        }
    }

    private var appearancePreferenceBinding: Binding<AppearancePreference> {
        Binding(
            get: { settingsStore.settings.appearancePreference },
            set: { settingsStore.settings.appearancePreference = $0 }
        )
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { launchAtLoginStatus.isEnabled },
            set: { setLaunchAtLogin($0) }
        )
    }

    private var notificationSoundEffectBinding: Binding<RestSoundEffect> {
        Binding(
            get: {
                guard settingsStore.settings.notificationSoundEnabled else {
                    return .none
                }
                let effect = settingsStore.settings.notificationSoundEffect
                return RestSoundEffect.selectableCases.contains(effect) ? effect : .stardewAchievement
            },
            set: { effect in
                settingsStore.settings.notificationSoundEffect = effect
                settingsStore.settings.notificationSoundEnabled = effect != .none
            }
        )
    }

    private func refreshLaunchAtLoginStatus() {
        launchAtLoginStatus = launchAtLoginService.status()

        if launchAtLoginStatus != .requiresApproval {
            launchAtLoginMessage = nil
        }
    }

    private func setLaunchAtLogin(_ isEnabled: Bool) {
        launchAtLoginMessage = nil

        do {
            launchAtLoginStatus = try launchAtLoginService.setEnabled(isEnabled)

            if launchAtLoginStatus == .requiresApproval {
                launchAtLoginMessage = L.tr("需要在系统设置中批准")
            }
        } catch {
            launchAtLoginStatus = launchAtLoginService.status()
            launchAtLoginMessage = L.tr("设置失败")
        }
    }

    private func refreshNotificationPermissionStatus() async {
        guard notificationOperation == nil else { return }
        notificationOperation = .refreshing
        setNotificationPreviewResult(nil)
        defer { notificationOperation = nil }

        notificationPermissionStatus = await notificationService.authorizationStatus()
    }

    private func testNotification() async {
        guard notificationOperation == nil else { return }
        notificationOperation = .testing
        setNotificationPreviewResult(nil)
        defer { notificationOperation = nil }

        let status = await notificationService.authorizationStatus()
        notificationPermissionStatus = status
        guard status.canPresentNotifications else {
            setNotificationPreviewResult(.notDelivered)
            return
        }

        let result = await notificationService.sendPreviewNotification(
            playSound: settingsStore.settings.notificationSoundEnabled,
            soundEffect: settingsStore.settings.notificationSoundEffect
        )
        setNotificationPreviewResult(result)
    }

    private func setNotificationPreviewResult(_ result: NotificationPreviewResult?) {
        notificationFeedbackTask?.cancel()
        notificationPreviewResult = result

        guard result == .delivered else { return }
        notificationFeedbackTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            notificationPreviewResult = nil
        }
    }

    private func openNotificationSettings() async {
        guard notificationOperation == nil else { return }
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension"
        ) else {
            return
        }
        notificationOperation = .openingSettings
        setNotificationPreviewResult(nil)
        defer { notificationOperation = nil }
        notificationPermissionStatus = await notificationService.prepareToOpenSettings()
        NSWorkspace.shared.open(url)
    }

    private func previewSound(_ effect: RestSoundEffect) {
        restSoundService.stop()
        restSoundService.play(effect)
    }
}

struct LaunchAtLoginControl: View {
    @Binding var isOn: Bool
    let status: LaunchAtLoginStatus
    let message: String?

    var body: some View {
        HStack(spacing: 10) {
            if let message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(status == .requiresApproval ? .orange : .red)
            }

            SettingsSwitch(L.tr("登录时自动启动"), isOn: $isOn)
                .disabled(status == .detecting)
        }
    }
}

enum NotificationPermissionOperation: Equatable {
    case refreshing
    case openingSettings
    case testing
}

enum NotificationPermissionAction: String, Identifiable, Equatable {
    case refresh
    case openSettings
    case testNotification

    var id: String { rawValue }
}

struct NotificationPermissionPresentation: Equatable {
    let statusText: String
    let statusSymbol: String
    let actions: [NotificationPermissionAction]

    init(status: NotificationPermissionStatus?) {
        statusText = status?.title ?? L.tr("检测中…")
        switch status {
        case .authorized:
            statusSymbol = "checkmark.circle.fill"
            actions = [.testNotification, .refresh]
        case .provisional:
            statusSymbol = "checkmark.circle"
            actions = [.testNotification, .refresh]
        case .alertsDisabled:
            statusSymbol = "exclamationmark.circle.fill"
            actions = [.openSettings, .refresh]
        case .denied, .notDetermined:
            statusSymbol = "exclamationmark.circle.fill"
            actions = [.openSettings, .refresh]
        case .unavailable:
            statusSymbol = "xmark.circle"
            actions = [.refresh]
        case nil:
            statusSymbol = "ellipsis.circle"
            actions = []
        }
    }
}

struct NotificationPermissionControl: View {
    let status: NotificationPermissionStatus?
    let operation: NotificationPermissionOperation?
    let previewResult: NotificationPreviewResult?
    let onRefresh: () -> Void
    let onOpenSettings: () -> Void
    let onTestNotification: () -> Void

    private var presentation: NotificationPermissionPresentation {
        NotificationPermissionPresentation(status: status)
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    statusLabel
                    actionButtons
                }

                VStack(alignment: .trailing, spacing: 6) {
                    statusLabel
                    actionButtons
                }
            }

            if let previewResult {
                HStack(spacing: 6) {
                    Label(
                        previewMessage(for: previewResult),
                        systemImage: previewResult == .delivered
                            ? "checkmark.circle.fill"
                            : "exclamationmark.circle"
                    )

                    if previewResult == .notDelivered {
                        Button(L.tr("打开系统设置…"), action: onOpenSettings)
                            .buttonStyle(.link)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var statusLabel: some View {
        HStack(spacing: 5) {
            Image(systemName: presentation.statusSymbol)
                .foregroundStyle(statusSymbolColor)

            Text(presentation.statusText)
                .foregroundStyle(.secondary)
        }
        .font(.callout)
        .fixedSize()
    }

    private var actionButtons: some View {
        HStack(spacing: 8) {
            ForEach(presentation.actions) { action in
                Button(actionTitle(for: action)) {
                    perform(action)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .disabled(operation != nil)
            }
        }
        .fixedSize()
    }

    private var statusSymbolColor: Color {
        switch status {
        case .authorized, .provisional:
            .green
        case .alertsDisabled, .denied, .notDetermined, .unavailable:
            .orange
        case nil:
            .secondary
        }
    }

    private func actionTitle(for action: NotificationPermissionAction) -> String {
        switch action {
        case .refresh:
            operation == .refreshing ? L.tr("检测中…") : L.tr("重新检测")
        case .openSettings:
            L.tr("打开系统设置…")
        case .testNotification:
            operation == .testing ? L.tr("发送中…") : L.tr("发送测试通知")
        }
    }

    private func previewMessage(for result: NotificationPreviewResult) -> String {
        switch result {
        case .delivered:
            L.tr("系统已接收测试通知")
        case .notDelivered:
            L.tr("未检测到通知")
        case .failed:
            L.tr("发送失败")
        }
    }

    private func perform(_ action: NotificationPermissionAction) {
        switch action {
        case .refresh:
            onRefresh()
        case .openSettings:
            onOpenSettings()
        case .testNotification:
            onTestNotification()
        }
    }
}

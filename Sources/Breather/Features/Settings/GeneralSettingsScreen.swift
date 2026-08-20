import AppKit
import SwiftUI

@MainActor
protocol NotificationSettingsServicing: AnyObject {
    func authorizationStatus() async -> NotificationPermissionStatus
    func requestAuthorization() async -> NotificationPermissionStatus
    func sendPreviewNotification(
        playSound: Bool,
        soundEffect: RestSoundEffect
    ) async -> NotificationPreviewResult
}

extension NotificationService: NotificationSettingsServicing {}

enum MenuBarIconSetting: Hashable {
    case hidden
    case icon(MenuBarIcon)

    init(settings: AppSettings) {
        self = settings.showMenuBarIcon ? .icon(settings.menuBarIcon) : .hidden
    }

    func apply(to settings: inout AppSettings) {
        switch self {
        case .hidden:
            settings.showMenuBarIcon = false
        case let .icon(icon):
            settings.showMenuBarIcon = true
            settings.menuBarIcon = icon
        }
    }
}

enum MenuBarCountdownSetting: String, CaseIterable, Identifiable {
    case hidden
    case minutes
    case minutesAndSeconds

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hidden: "不显示"
        case .minutes: "分钟"
        case .minutesAndSeconds: "分钟和秒"
        }
    }

    init(settings: AppSettings) {
        if !settings.showCountdownInMenuBar {
            self = .hidden
        } else if settings.showSeconds {
            self = .minutesAndSeconds
        } else {
            self = .minutes
        }
    }

    func apply(to settings: inout AppSettings) {
        switch self {
        case .hidden:
            settings.showCountdownInMenuBar = false
            settings.showSeconds = false
        case .minutes:
            settings.showCountdownInMenuBar = true
            settings.showSeconds = false
        case .minutesAndSeconds:
            settings.showCountdownInMenuBar = true
            settings.showSeconds = true
        }
    }
}

struct GeneralSettingsScreen: View {
    @ObservedObject var settingsStore: SettingsStore
    let notificationService: any NotificationSettingsServicing
    let restSoundService: RestSoundService

    private let launchAtLoginService = LaunchAtLoginService()

    @State private var launchAtLoginStatus: LaunchAtLoginStatus = .detecting
    @State private var launchAtLoginMessage: String?
    @State private var notificationPermissionStatus: NotificationPermissionStatus?
    @State private var notificationPreviewResult: NotificationPreviewResult?
    @State private var notificationFeedbackTask: Task<Void, Never>?
    @State private var notificationOperation: NotificationPermissionOperation?

    var body: some View {
        SettingsScreenContainer {
            applicationGroup
            notificationGroup
            menuBarGroup
            menuBarPopoverGroup
        }
        .task {
            refreshLaunchAtLoginStatus()
            await refreshNotificationPermissionStatus()
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
    }

    private var applicationGroup: some View {
        SettingsGroup("应用") {
            SettingsRow(title: "应用外观") {
                Picker("应用外观", selection: appearancePreferenceBinding) {
                    ForEach(AppearancePreference.allCases) { preference in
                        Text(preference.title).tag(preference)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
            }

            SettingsRow(title: "登录时自动启动") {
                LaunchAtLoginControl(
                    isOn: launchAtLoginBinding,
                    status: launchAtLoginStatus,
                    message: launchAtLoginMessage
                )
            }
        }
    }

    private var notificationGroup: some View {
        SettingsGroup("通知") {
            SettingsRow(title: "通知声音") {
                SoundEffectControl(selection: notificationSoundEffectBinding) {
                    previewSound(settingsStore.settings.notificationSoundEffect)
                }
            }

            SettingsRow(title: "系统通知") {
                NotificationPermissionControl(
                    status: notificationPermissionStatus,
                    operation: notificationOperation,
                    previewResult: notificationPreviewResult,
                    onRefresh: {
                        Task { await refreshNotificationPermissionStatus() }
                    },
                    onRequestPermission: {
                        Task { await requestNotificationPermission() }
                    },
                    onOpenSettings: openNotificationSettings,
                    onTestNotification: {
                        Task { await testNotification() }
                    }
                )
            }
        }
    }

    private var menuBarGroup: some View {
        SettingsGroup("菜单栏") {
            SettingsRow(title: "菜单栏图标") {
                MenuBarIconControl(selection: menuBarIconSettingBinding)
            }

            SettingsRow(title: "倒计时显示") {
                menuPicker(
                    title: "倒计时显示",
                    selection: menuBarCountdownSettingBinding,
                    values: MenuBarCountdownSetting.allCases
                )
            }
        }
    }

    private var menuBarPopoverGroup: some View {
        SettingsGroup("菜单栏弹窗") {
            SettingsRow(title: "弹窗外观") {
                menuPicker(
                    title: "弹窗外观",
                    selection: menuBarPopoverAppearanceBinding,
                    values: MenuBarPopoverAppearance.allCases
                )
            }

            SettingsRow(title: "主题色") {
                menuPicker(
                    title: "主题色",
                    selection: menuBarPopoverThemeColorBinding,
                    values: MenuBarPopoverThemeColor.allCases
                )
            }

            SettingsRow(title: "进度条") {
                menuPicker(
                    title: "进度条",
                    selection: menuBarPopoverProgressStyleBinding,
                    values: MenuBarPopoverProgressStyle.allCases
                )
            }

            SettingsRow(title: "中心方块") {
                menuPicker(
                    title: "中心方块",
                    selection: menuBarPopoverSquareStyleBinding,
                    values: MenuBarPopoverSquareStyle.allCases
                )
            }

            SettingsRow(title: "方块颜色") {
                menuPicker(
                    title: "方块颜色",
                    selection: menuBarPopoverSquareColorModeBinding,
                    values: MenuBarPopoverSquareColorMode.allCases
                )
            }
        }
    }

    private func menuPicker<Value>(
        title: String,
        selection: Binding<Value>,
        values: [Value]
    ) -> some View where Value: Identifiable & Hashable, Value: SettingsTitledValue {
        Picker(title, selection: selection) {
            ForEach(values) { value in
                Text(value.title).tag(value)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .fixedSize()
    }

    private var appearancePreferenceBinding: Binding<AppearancePreference> {
        Binding(
            get: { settingsStore.settings.appearancePreference },
            set: { settingsStore.settings.appearancePreference = $0 }
        )
    }

    private var menuBarIconSettingBinding: Binding<MenuBarIconSetting> {
        Binding(
            get: { MenuBarIconSetting(settings: settingsStore.settings) },
            set: { selection in
                var settings = settingsStore.settings
                selection.apply(to: &settings)
                settingsStore.settings = settings
            }
        )
    }

    private var menuBarCountdownSettingBinding: Binding<MenuBarCountdownSetting> {
        Binding(
            get: { MenuBarCountdownSetting(settings: settingsStore.settings) },
            set: { selection in
                var settings = settingsStore.settings
                selection.apply(to: &settings)
                settingsStore.settings = settings
            }
        )
    }

    private var menuBarPopoverThemeColorBinding: Binding<MenuBarPopoverThemeColor> {
        Binding(
            get: { settingsStore.settings.menuBarPopoverThemeColor },
            set: { settingsStore.settings.menuBarPopoverThemeColor = $0 }
        )
    }

    private var menuBarPopoverAppearanceBinding: Binding<MenuBarPopoverAppearance> {
        Binding(
            get: { settingsStore.settings.menuBarPopoverAppearance },
            set: { settingsStore.settings.menuBarPopoverAppearance = $0 }
        )
    }

    private var menuBarPopoverProgressStyleBinding: Binding<MenuBarPopoverProgressStyle> {
        Binding(
            get: { settingsStore.settings.menuBarPopoverProgressStyle },
            set: { settingsStore.settings.menuBarPopoverProgressStyle = $0 }
        )
    }

    private var menuBarPopoverSquareStyleBinding: Binding<MenuBarPopoverSquareStyle> {
        Binding(
            get: { settingsStore.settings.menuBarPopoverSquareStyle },
            set: { settingsStore.settings.menuBarPopoverSquareStyle = $0 }
        )
    }

    private var menuBarPopoverSquareColorModeBinding: Binding<MenuBarPopoverSquareColorMode> {
        Binding(
            get: { settingsStore.settings.menuBarPopoverSquareColorMode },
            set: { settingsStore.settings.menuBarPopoverSquareColorMode = $0 }
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
                launchAtLoginMessage = "需要在系统设置中批准"
            }
        } catch {
            launchAtLoginStatus = launchAtLoginService.status()
            launchAtLoginMessage = "设置失败"
        }
    }

    private func refreshNotificationPermissionStatus() async {
        guard notificationOperation == nil else { return }
        notificationOperation = .refreshing
        setNotificationPreviewResult(nil)
        defer { notificationOperation = nil }

        notificationPermissionStatus = await notificationService.authorizationStatus()
    }

    private func requestNotificationPermission() async {
        guard notificationOperation == nil else { return }
        notificationOperation = .requesting
        setNotificationPreviewResult(nil)
        defer { notificationOperation = nil }

        notificationPermissionStatus = await notificationService.requestAuthorization()
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

    private func openNotificationSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension"
        ) else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    private func previewSound(_ effect: RestSoundEffect) {
        restSoundService.stop()
        restSoundService.play(effect)
    }
}

private protocol SettingsTitledValue {
    var title: String { get }
}

extension MenuBarPopoverAppearance: SettingsTitledValue {}
extension MenuBarPopoverThemeColor: SettingsTitledValue {}
extension MenuBarPopoverProgressStyle: SettingsTitledValue {}
extension MenuBarPopoverSquareStyle: SettingsTitledValue {}
extension MenuBarPopoverSquareColorMode: SettingsTitledValue {}
extension MenuBarCountdownSetting: SettingsTitledValue {}

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

            SettingsSwitch("登录时自动启动", isOn: $isOn)
                .disabled(status == .detecting)
        }
    }
}

struct MenuBarIconControl: View {
    @Binding var selection: MenuBarIconSetting

    var body: some View {
        Picker("菜单栏图标", selection: $selection) {
            Text("不显示").tag(MenuBarIconSetting.hidden)
            Divider()

            ForEach(MenuBarIcon.allCases) { icon in
                Label {
                    Text(icon.title)
                } icon: {
                    MenuBarIconPreview(icon: icon)
                }
                .tag(MenuBarIconSetting.icon(icon))
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .fixedSize()
    }
}

private struct MenuBarIconPreview: View {
    let icon: MenuBarIcon

    var body: some View {
        Image(icon.assetName)
            .resizable()
            .renderingMode(.template)
            .scaledToFit()
            .frame(width: 18, height: 18)
            .imageScale(.small)
            .foregroundStyle(.primary)
    }
}

enum NotificationPermissionOperation: Equatable {
    case refreshing
    case requesting
    case testing
}

enum NotificationPermissionAction: String, Identifiable, Equatable {
    case refresh
    case requestPermission
    case openSettings
    case testNotification

    var id: String { rawValue }
}

struct NotificationPermissionPresentation: Equatable {
    let statusText: String
    let statusSymbol: String
    let actions: [NotificationPermissionAction]

    init(status: NotificationPermissionStatus?) {
        switch status {
        case .authorized:
            statusText = "已授权"
            statusSymbol = "checkmark.circle.fill"
            actions = [.testNotification, .refresh]
        case .provisional:
            statusText = "临时授权"
            statusSymbol = "checkmark.circle"
            actions = [.testNotification, .refresh]
        case .alertsDisabled:
            statusText = "横幅已关闭"
            statusSymbol = "exclamationmark.circle.fill"
            actions = [.openSettings, .refresh]
        case .denied:
            statusText = "未授权"
            statusSymbol = "exclamationmark.circle.fill"
            actions = [.openSettings, .refresh]
        case .notDetermined:
            statusText = "未请求"
            statusSymbol = "questionmark.circle"
            actions = [.requestPermission, .refresh]
        case .unavailable:
            statusText = "不可用"
            statusSymbol = "xmark.circle"
            actions = [.refresh]
        case nil:
            statusText = "检测中…"
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
    let onRequestPermission: () -> Void
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
                        Button("打开系统设置…", action: onOpenSettings)
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
        case .alertsDisabled, .denied, .unavailable:
            .red
        case .notDetermined, nil:
            .secondary
        }
    }

    private func actionTitle(for action: NotificationPermissionAction) -> String {
        switch action {
        case .refresh:
            operation == .refreshing ? "检测中…" : "重新检测"
        case .requestPermission:
            operation == .requesting ? "请求中…" : "请求权限"
        case .openSettings:
            "打开系统设置…"
        case .testNotification:
            operation == .testing ? "发送中…" : "发送测试通知"
        }
    }

    private func previewMessage(for result: NotificationPreviewResult) -> String {
        switch result {
        case .delivered:
            "系统已接收测试通知"
        case .notDelivered:
            "未检测到通知"
        case .failed:
            "发送失败"
        }
    }

    private func perform(_ action: NotificationPermissionAction) {
        switch action {
        case .refresh:
            onRefresh()
        case .requestPermission:
            onRequestPermission()
        case .openSettings:
            onOpenSettings()
        case .testNotification:
            onTestNotification()
        }
    }
}

import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject var settingsStore: SettingsStore
    let notificationService: NotificationService
    let restSoundService: RestSoundService
    let onApplyRulesToCurrentCycle: () -> Void
    let onPreviewRestOverlay: () -> Void

    private let launchAtLoginService = LaunchAtLoginService()

    @State private var selectedSection: SettingsSectionID = .general
    @State private var lastSavedAt = Date()
    @State private var launchAtLoginStatus: LaunchAtLoginStatus = .detecting
    @State private var launchAtLoginMessage: String?
    @State private var notificationPermissionStatus: NotificationPermissionStatus?
    @State private var notificationPreviewMessage: String?
    @State private var notificationPreviewMessageTask: Task<Void, Never>?
    @State private var isSendingNotificationPreview = false
    @State private var hasPendingRuleChanges = false
    @State private var isWaitingToApplyRules = false
    @State private var ruleApplyTask: Task<Void, Never>?

    var body: some View {
        NavigationSplitView {
            SettingsSidebar(selectedSection: $selectedSection)
                .navigationSplitViewColumnWidth(min: 150, ideal: 170, max: 200)
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    selectedContent
                    saveStatus
                }
                .padding(.top, 8)
                .padding(.horizontal, 16)
                .padding(.bottom, 28)
                .frame(maxWidth: 620, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(minWidth: 760, minHeight: 560)
        .onChange(of: settingsStore.settings) { oldSettings, newSettings in
            lastSavedAt = Date()
            guard oldSettings.ruleChangeEffect != newSettings.ruleChangeEffect else {
                return
            }

            if newSettings.ruleChangeEffect == .immediate, hasPendingRuleChanges {
                scheduleCurrentCycleApply()
            } else {
                cancelScheduledRuleApply()
            }
        }
        .onChange(of: settingsStore.rules) { _, _ in
            lastSavedAt = Date()
            hasPendingRuleChanges = true
            if settingsStore.settings.ruleChangeEffect == .immediate {
                scheduleCurrentCycleApply()
            }
        }
        .onDisappear {
            ruleApplyTask?.cancel()
            notificationPreviewMessageTask?.cancel()
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
    }

    @ViewBuilder
    private var selectedContent: some View {
        switch selectedSection {
        case .general:
            generalContent
        case .schedule:
            scheduleContent
        case .restOverlay:
            restOverlayContent
        }
    }

    private var generalContent: some View {
        VStack(spacing: 16) {
            SettingsGroup("外观") {
                SettingsRow(title: "外观风格", description: "选择 Breather 使用浅色、深色，或跟随系统。") {
                    Picker("", selection: appearancePreferenceBinding) {
                        ForEach(AppearancePreference.allCases) { preference in
                            Text(preference.title).tag(preference)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 132, alignment: .trailing)
                }
            }

            SettingsGroup("启动") {
                SettingsRow(title: "开机自动启动", description: "登录 macOS 后自动启动 Breather。") {
                    LaunchAtLoginControl(
                        isOn: launchAtLoginBinding,
                        status: launchAtLoginStatus,
                        message: launchAtLoginMessage
                    )
                }
            }

            SettingsGroup("菜单栏") {
                SettingsRow(title: "显示图标", description: "在菜单栏倒计时旁显示 Breather 图标。") {
                    Toggle("", isOn: settingsBinding(\.showMenuBarIcon))
                        .labelsHidden()
                }

                SettingsRow(title: "菜单栏图标", description: "选择要在菜单栏中显示的自定义图标。") {
                    MenuBarIconControl(selection: menuBarIconBinding)
                        .disabled(!settingsStore.settings.showMenuBarIcon)
                }

                SettingsRow(title: "显示倒计时", description: "在菜单栏直接显示当前工作周期剩余时间。") {
                    Toggle("", isOn: settingsBinding(\.showCountdownInMenuBar))
                        .labelsHidden()
                }

                SettingsRow(title: "显示秒数", description: "打开后菜单栏会显示更精确的剩余时间。") {
                    Toggle("", isOn: settingsBinding(\.showSeconds))
                        .labelsHidden()
                }
            }

            SettingsGroup("菜单栏弹窗") {
                SettingsRow(title: "明暗模式", description: "单独控制菜单栏弹窗使用浅色、深色，或跟随系统。") {
                    Picker("", selection: menuBarPopoverAppearanceBinding) {
                        ForEach(MenuBarPopoverAppearance.allCases) { appearance in
                            Text(appearance.title).tag(appearance)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 132, alignment: .trailing)
                }

                SettingsRow(title: "主题色", description: "控制弹窗强调色、进度条和中心方块色调。") {
                    Picker("", selection: menuBarPopoverThemeColorBinding) {
                        ForEach(MenuBarPopoverThemeColor.allCases) { themeColor in
                            Text(themeColor.title).tag(themeColor)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 132, alignment: .trailing)
                }

                SettingsRow(title: "进度条", description: "选择倒计时进度的显示方式。") {
                    Picker("", selection: menuBarPopoverProgressStyleBinding) {
                        ForEach(MenuBarPopoverProgressStyle.allCases) { progressStyle in
                            Text(progressStyle.title).tag(progressStyle)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 132, alignment: .trailing)
                }

                SettingsRow(title: "中心方块", description: "选择按钮中方块的运动表现。") {
                    Picker("", selection: menuBarPopoverSquareStyleBinding) {
                        ForEach(MenuBarPopoverSquareStyle.allCases) { squareStyle in
                            Text(squareStyle.title).tag(squareStyle)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 132, alignment: .trailing)
                }

                SettingsRow(title: "方块颜色", description: "选择方块跟随主题色，或使用更克制的中性色。") {
                    Picker("", selection: menuBarPopoverSquareColorModeBinding) {
                        ForEach(MenuBarPopoverSquareColorMode.allCases) { colorMode in
                            Text(colorMode.title).tag(colorMode)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 132, alignment: .trailing)
                }
            }

            SettingsGroup("通知") {
                SettingsRow(title: "通知声音", description: "选择休息前通知播放的提示音。") {
                    HStack(spacing: 10) {
                        Toggle("", isOn: settingsBinding(\.notificationSoundEnabled))
                            .labelsHidden()

                        SoundEffectControl(selection: notificationSoundEffectBinding) {
                            restSoundService.play(settingsStore.settings.notificationSoundEffect)
                        }
                        .disabled(!settingsStore.settings.notificationSoundEnabled)
                    }
                }

                SettingsRow(title: "通知权限", description: "如果权限不可用，Breather 会降级为菜单栏和休息遮罩提醒。") {
                    NotificationPermissionControl(
                        status: notificationPermissionStatus,
                        previewMessage: notificationPreviewMessage,
                        isSendingPreview: isSendingNotificationPreview,
                        onPrimaryAction: handleNotificationPermissionPrimaryAction,
                        onPreview: previewNotification
                    )
                }
            }

            SettingsGroup("应用") {
                SettingsRow(title: "退出 Breather", description: "停止当前计时并退出菜单栏 App。") {
                    Button("退出") {
                        NSApp.terminate(nil)
                    }
                    .buttonStyle(.bordered)
                    .foregroundStyle(.red)
                }
            }
        }
    }

    private var scheduleContent: some View {
        VStack(spacing: 16) {
            SettingsGroup("计时规则") {
                SettingsRow(title: "工作时长", description: "每个工作周期的持续时间。") {
                    DurationStepper(value: workMinutesBinding, range: 1...180, unit: "分钟")
                }

                SettingsRow(title: "短休息时长", description: "到点后全屏休息遮罩显示的时间。") {
                    DurationStepper(value: shortBreakSecondsBinding, range: 10...600, unit: "秒")
                }

                SettingsRow(title: "休息前通知", description: "进入休息前提前多久提醒。") {
                    DurationStepper(value: preBreakNotificationSecondsBinding, range: 0...120, unit: "秒")
                }

                SettingsRow(title: "空闲阈值", description: "离开电脑超过这个时间，会视为已经休息过。") {
                    DurationStepper(value: idleMinutesBinding, range: 1...30, unit: "分钟")
                }

                SettingsRow(title: "默认生效方式", description: "设置计时规则修改后的默认处理方式。") {
                    Picker("", selection: ruleChangeEffectBinding) {
                        ForEach(RuleChangeEffect.allCases) { effect in
                            Text(effect.title).tag(effect)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 190)
                }

                RuleChangeStatusRow(
                    effect: settingsStore.settings.ruleChangeEffect,
                    hasPendingChanges: hasPendingRuleChanges,
                    isWaitingToApply: isWaitingToApplyRules,
                    onApplyNow: applyRulesToCurrentCycle
                )
            }

            SettingsGroup("跳过与延后") {
                SettingsRow(title: "允许跳过", description: "休息遮罩中显示跳过按钮。") {
                    Toggle("", isOn: settingsBinding(\.allowSkip))
                        .labelsHidden()
                }

                SettingsRow(title: "Esc 跳过", description: "按 Esc 可以跳过当前休息。") {
                    Toggle("", isOn: settingsBinding(\.allowEscToSkip))
                        .labelsHidden()
                }

                SettingsRow(title: "延后时长", description: "休息时点击延后后，多久再次提醒补休。") {
                    DurationStepper(value: snoozeMinutesBinding, range: 1...30, unit: "分钟")
                }

                SettingsRow(title: "连续未休息提醒", description: "连续延后或跳过达到这个次数后，下次休息时显示短休建议。") {
                    DurationStepper(value: recoveryNudgeThresholdBinding, range: 2...6, unit: "次")
                }
            }
        }
    }

    private var restOverlayContent: some View {
        VStack(spacing: 16) {
            SettingsGroup("外观") {
                SettingsRow(title: "覆盖所有屏幕", description: "在所有显示器显示遮罩。") {
                    ReadOnlyValue("已开启")
                }

                SettingsRow(title: "背景", description: "选择休息界面的背景样式。") {
                    Picker("", selection: restOverlayBackgroundBinding) {
                        ForEach(RestOverlayBackground.allCases) { background in
                            Text(background.title).tag(background)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 132, alignment: .trailing)
                }

                SettingsRow(title: "背景半透明", description: "纯色背景可轻微透出桌面。") {
                    Toggle("", isOn: settingsBinding(\.restOverlayTranslucentBackground))
                        .labelsHidden()
                        .disabled(settingsStore.settings.restOverlayBackground != .solid)
                }

                SettingsRow(title: "显示倒计时", description: "显示休息剩余时间。") {
                    ReadOnlyValue("已开启")
                }

                SettingsRow(title: "淡入淡出", description: "打开和关闭时过渡。") {
                    Toggle("", isOn: settingsBinding(\.restOverlayFadeAnimation))
                        .labelsHidden()
                }
            }

            SettingsGroup("文案") {
                SettingsRow(title: "主提示语", description: "休息界面的主提示。") {
                    Picker("", selection: restOverlayPromptBinding) {
                        ForEach(RestOverlayPrompt.fixedCases) { prompt in
                            Text(prompt.title).tag(prompt)
                        }
                        Divider()
                        Text(RestOverlayPrompt.random.title).tag(RestOverlayPrompt.random)
                        Text(RestOverlayPrompt.none.title).tag(RestOverlayPrompt.none)
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 132, alignment: .trailing)
                }

                SettingsRow(title: "辅助提示语", description: "主提示下方的补充。") {
                    Picker("", selection: restOverlaySubtitleBinding) {
                        ForEach(RestOverlaySubtitle.fixedCases) { subtitle in
                            Text(subtitle.title).tag(subtitle)
                        }
                        Divider()
                        Text(RestOverlaySubtitle.random.title).tag(RestOverlaySubtitle.random)
                        Text(RestOverlaySubtitle.none.title).tag(RestOverlaySubtitle.none)
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 184, alignment: .trailing)
                }
            }

            SettingsGroup("声音") {
                SettingsRow(title: "进入休息", description: "休息开始时播放。") {
                    SoundEffectControl(selection: restStartSoundEffectBinding) {
                        restSoundService.play(settingsStore.settings.restStartSoundEffect)
                    }
                }

                SettingsRow(title: "休息结束", description: "休息完成或跳过后播放。") {
                    SoundEffectControl(selection: restEndSoundEffectBinding) {
                        restSoundService.play(settingsStore.settings.restEndSoundEffect)
                    }
                }
            }

            SettingsGroup("预览") {
                SettingsRow(title: "预览休息界面", description: "后续会支持从设置中直接预览遮罩。") {
                    Button("预览") {
                        onPreviewRestOverlay()
                    }
                }
            }
        }
    }

    private var saveStatus: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)

            Text("已自动保存")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(lastSavedAt, style: .time)
                .font(.caption)
                .foregroundStyle(.tertiary)

            Spacer()

            Text(ruleEffectStatusText)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.top, 4)
    }

    private var ruleEffectStatusText: String {
        switch settingsStore.settings.ruleChangeEffect {
        case .nextCycle:
            hasPendingRuleChanges ? "计时规则将在下个周期生效" : "当前周期已使用最新规则"
        case .immediate:
            isWaitingToApplyRules ? "计时规则即将应用到当前周期" : "计时规则默认立即生效"
        }
    }

    private func settingsBinding(_ keyPath: WritableKeyPath<AppSettings, Bool>) -> Binding<Bool> {
        Binding(
            get: { settingsStore.settings[keyPath: keyPath] },
            set: { settingsStore.settings[keyPath: keyPath] = $0 }
        )
    }

    private var appearancePreferenceBinding: Binding<AppearancePreference> {
        Binding(
            get: { settingsStore.settings.appearancePreference },
            set: { settingsStore.settings.appearancePreference = $0 }
        )
    }

    private var menuBarIconBinding: Binding<MenuBarIcon> {
        Binding(
            get: { settingsStore.settings.menuBarIcon },
            set: { settingsStore.settings.menuBarIcon = $0 }
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
            get: { launchAtLoginStatus == .detecting ? settingsStore.settings.launchAtLogin : launchAtLoginStatus.isEnabled },
            set: { setLaunchAtLogin($0) }
        )
    }

    private var restOverlayPromptBinding: Binding<RestOverlayPrompt> {
        Binding(
            get: { settingsStore.settings.restOverlayPrompt },
            set: { settingsStore.settings.restOverlayPrompt = $0 }
        )
    }

    private var restOverlaySubtitleBinding: Binding<RestOverlaySubtitle> {
        Binding(
            get: { settingsStore.settings.restOverlaySubtitle },
            set: { settingsStore.settings.restOverlaySubtitle = $0 }
        )
    }

    private var restOverlayBackgroundBinding: Binding<RestOverlayBackground> {
        Binding(
            get: { settingsStore.settings.restOverlayBackground },
            set: { settingsStore.settings.restOverlayBackground = $0 }
        )
    }

    private var notificationSoundEffectBinding: Binding<RestSoundEffect> {
        Binding(
            get: {
                let effect = settingsStore.settings.notificationSoundEffect
                return RestSoundEffect.selectableCases.contains(effect) ? effect : .stardewAchievement
            },
            set: { effect in
                settingsStore.settings.notificationSoundEffect = effect
                settingsStore.settings.notificationSoundEnabled = effect != .none
            }
        )
    }

    private var restStartSoundEffectBinding: Binding<RestSoundEffect> {
        Binding(
            get: {
                let effect = settingsStore.settings.restStartSoundEffect
                return RestSoundEffect.selectableCases.contains(effect) ? effect : .none
            },
            set: { effect in
                settingsStore.settings.restStartSoundEffect = effect
                settingsStore.settings.playRestStartSound = effect != .none
            }
        )
    }

    private var restEndSoundEffectBinding: Binding<RestSoundEffect> {
        Binding(
            get: {
                let effect = settingsStore.settings.restEndSoundEffect
                return RestSoundEffect.selectableCases.contains(effect) ? effect : .none
            },
            set: { effect in
                settingsStore.settings.restEndSoundEffect = effect
                settingsStore.settings.playRestEndSound = effect != .none
            }
        )
    }

    private var ruleChangeEffectBinding: Binding<RuleChangeEffect> {
        Binding(
            get: { settingsStore.settings.ruleChangeEffect },
            set: { settingsStore.settings.ruleChangeEffect = $0 }
        )
    }

    private var workMinutesBinding: Binding<Int> {
        Binding(
            get: { settingsStore.workMinutes },
            set: { settingsStore.workMinutes = $0 }
        )
    }

    private var shortBreakSecondsBinding: Binding<Int> {
        Binding(
            get: { settingsStore.shortBreakSeconds },
            set: { settingsStore.shortBreakSeconds = $0 }
        )
    }

    private var preBreakNotificationSecondsBinding: Binding<Int> {
        Binding(
            get: { settingsStore.preBreakNotificationSeconds },
            set: { settingsStore.preBreakNotificationSeconds = $0 }
        )
    }

    private var idleMinutesBinding: Binding<Int> {
        Binding(
            get: { settingsStore.idleMinutes },
            set: { settingsStore.idleMinutes = $0 }
        )
    }

    private var snoozeMinutesBinding: Binding<Int> {
        Binding(
            get: { settingsStore.snoozeMinutes },
            set: { settingsStore.snoozeMinutes = $0 }
        )
    }

    private var recoveryNudgeThresholdBinding: Binding<Int> {
        Binding(
            get: { settingsStore.recoveryNudgeThreshold },
            set: { settingsStore.recoveryNudgeThreshold = $0 }
        )
    }

    private func scheduleCurrentCycleApply() {
        isWaitingToApplyRules = true
        ruleApplyTask?.cancel()
        ruleApplyTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(900))
            guard !Task.isCancelled else { return }
            applyRulesToCurrentCycle()
        }
    }

    private func applyRulesToCurrentCycle() {
        cancelScheduledRuleApply()
        onApplyRulesToCurrentCycle()
        hasPendingRuleChanges = false
    }

    private func cancelScheduledRuleApply() {
        ruleApplyTask?.cancel()
        ruleApplyTask = nil
        isWaitingToApplyRules = false
    }

    private func refreshLaunchAtLoginStatus() {
        launchAtLoginStatus = launchAtLoginService.status()
        settingsStore.settings.launchAtLogin = launchAtLoginStatus.isEnabled

        if launchAtLoginStatus != .requiresApproval {
            launchAtLoginMessage = nil
        }
    }

    private func setLaunchAtLogin(_ isEnabled: Bool) {
        launchAtLoginMessage = nil

        do {
            launchAtLoginStatus = try launchAtLoginService.setEnabled(isEnabled)
            settingsStore.settings.launchAtLogin = launchAtLoginStatus.isEnabled

            if launchAtLoginStatus == .requiresApproval {
                launchAtLoginMessage = "需要在系统设置中批准"
            }
        } catch {
            launchAtLoginStatus = launchAtLoginService.status()
            settingsStore.settings.launchAtLogin = launchAtLoginStatus.isEnabled
            launchAtLoginMessage = "设置失败"
        }
    }

    private func refreshNotificationPermissionStatus() async {
        notificationPreviewMessage = nil
        notificationPermissionStatus = await notificationService.authorizationStatus()
    }

    private func requestNotificationPermission() {
        Task {
            notificationPermissionStatus = await notificationService.requestAuthorization()
        }
    }

    private func handleNotificationPermissionPrimaryAction() {
        if notificationPermissionStatus == .denied {
            openNotificationSettings()
        } else {
            requestNotificationPermission()
        }
    }

    private func previewNotification() {
        Task {
            setNotificationPreviewMessage(nil)
            isSendingNotificationPreview = true
            defer { isSendingNotificationPreview = false }

            var status = await notificationService.authorizationStatus()
            if status == .notDetermined {
                status = await notificationService.requestAuthorization()
            }
            notificationPermissionStatus = status

            guard status.canSendNotifications else {
                setNotificationPreviewMessage("请先授权")
                return
            }

            let didSend = await notificationService.sendPreviewNotification(
                playSound: settingsStore.settings.notificationSoundEnabled,
                soundEffect: settingsStore.settings.notificationSoundEffect
            )
            setNotificationPreviewMessage(didSend ? "已发送" : "发送失败")
        }
    }

    private func setNotificationPreviewMessage(_ message: String?) {
        notificationPreviewMessageTask?.cancel()
        notificationPreviewMessage = message

        guard message != nil else {
            return
        }

        notificationPreviewMessageTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else {
                return
            }
            notificationPreviewMessage = nil
        }
    }

    private func openNotificationSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}

private struct SettingsSidebar: View {
    @Binding var selectedSection: SettingsSectionID

    var body: some View {
        List(selection: $selectedSection) {
            ForEach(SettingsSectionID.allCases) { section in
                Label(section.title, systemImage: section.systemImage)
                    .tag(section)
            }
        }
        .listStyle(.sidebar)
    }
}

private struct RuleChangeStatusRow: View {
    let effect: RuleChangeEffect
    let hasPendingChanges: Bool
    let isWaitingToApply: Bool
    let onApplyNow: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: statusIcon)
                .foregroundStyle(statusColor)

            Text(statusText)
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            if effect == .nextCycle {
                Button("立即应用到当前周期", action: onApplyNow)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(!hasPendingChanges)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var statusText: String {
        switch effect {
        case .nextCycle:
            hasPendingChanges ? "计时规则已保存，将在下个周期生效。" : "当前周期已使用最新计时规则。"
        case .immediate:
            isWaitingToApply ? "即将应用到当前周期..." : "计时规则会在修改后自动应用到当前周期。"
        }
    }

    private var statusIcon: String {
        switch effect {
        case .nextCycle:
            hasPendingChanges ? "clock" : "checkmark.circle.fill"
        case .immediate:
            isWaitingToApply ? "timer" : "bolt.circle.fill"
        }
    }

    private var statusColor: Color {
        switch effect {
        case .nextCycle:
            hasPendingChanges ? .orange : .green
        case .immediate:
            isWaitingToApply ? .orange : .blue
        }
    }
}

private struct NotificationPermissionControl: View {
    let status: NotificationPermissionStatus?
    let previewMessage: String?
    let isSendingPreview: Bool
    let onPrimaryAction: () -> Void
    let onPreview: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text(status?.title ?? "检测中")
                .font(.callout)
                .foregroundStyle(statusColor)
                .frame(minWidth: 52, alignment: .trailing)

            Button(primaryActionTitle, action: onPrimaryAction)
                .buttonStyle(.bordered)
                .controlSize(.small)

            Button("预览", action: onPreview)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(isSendingPreview || !canPreview)

            if let previewMessage {
                Text(previewMessage)
                    .font(.callout)
                    .foregroundStyle(previewMessage == "已发送" ? .green : .secondary)
            }
        }
    }

    private var canPreview: Bool {
        switch status {
        case .authorized, .provisional, .notDetermined:
            true
        case .denied, .unavailable, nil:
            false
        }
    }

    private var statusColor: Color {
        switch status {
        case .authorized, .provisional:
            .green
        case .denied, .unavailable:
            .red
        case .notDetermined, nil:
            .secondary
        }
    }

    private var primaryActionTitle: String {
        switch status {
        case .denied:
            "打开设置"
        case .notDetermined:
            "请求权限"
        default:
            "刷新"
        }
    }
}

private struct LaunchAtLoginControl: View {
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

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .disabled(status == .detecting)
        }
    }
}

private struct MenuBarIconControl: View {
    @Binding var selection: MenuBarIcon

    var body: some View {
        Picker("", selection: $selection) {
            ForEach(MenuBarIcon.allCases) { icon in
                Label {
                    Text(icon.title)
                } icon: {
                    MenuBarIconPreview(icon: icon)
                }
                .tag(icon)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(width: 168, alignment: .trailing)
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

private struct SoundEffectControl: View {
    @Binding var selection: RestSoundEffect
    let onPreview: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Picker("", selection: $selection) {
                ForEach(RestSoundEffect.fixedCases) { effect in
                    Text(effect.title).tag(effect)
                }
                Divider()
                Text(RestSoundEffect.random.title).tag(RestSoundEffect.random)
                Text(RestSoundEffect.none.title).tag(RestSoundEffect.none)
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 92, alignment: .trailing)

            Button(action: onPreview) {
                Image(systemName: "play.circle")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .disabled(selection == .none)
            .help("播放提示音")
        }
        .frame(width: 124, alignment: .trailing)
    }
}

private enum SettingsSectionID: String, CaseIterable, Identifiable, Hashable {
    case general
    case schedule
    case restOverlay

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "通用"
        case .schedule: "计划"
        case .restOverlay: "休息界面"
        }
    }

    var subtitle: String {
        switch self {
        case .general: "管理菜单栏、通知和应用行为。"
        case .schedule: "设置工作和休息节奏。"
        case .restOverlay: "调整全屏休息遮罩的基础体验。"
        }
    }

    var systemImage: String {
        switch self {
        case .general: "gearshape"
        case .schedule: "timer"
        case .restOverlay: "rectangle.inset.filled"
        }
    }
}

private struct SettingsGroup<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        GroupBox {
            VStack(spacing: 0) {
                content
            }
            .padding(.vertical, 2)
        } label: {
            Text(title)
                .font(.headline)
        }
        .groupBoxStyle(.automatic)
    }
}

private struct SettingsRow<Control: View>: View {
    let title: String
    let description: String
    @ViewBuilder let control: Control

    var body: some View {
        HStack(alignment: .center, spacing: 22) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body)

                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 24)

            control
                .frame(minWidth: 120, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }
}

private struct DurationStepper: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    let unit: String

    var body: some View {
        HStack(spacing: 6) {
            NumericTextField(value: $value, range: range)
                .frame(width: 48, height: 22)

            Text(unit)
                .foregroundStyle(.secondary)
                .frame(width: 30, alignment: .leading)

            NativeStepper(value: $value, range: range)
        }
        .frame(width: 146, alignment: .trailing)
    }
}

private struct NativeStepper: NSViewRepresentable {
    @Binding var value: Int
    let range: ClosedRange<Int>

    func makeNSView(context: Context) -> EditingAwareStepper {
        let stepper = EditingAwareStepper()
        stepper.minValue = Double(range.lowerBound)
        stepper.maxValue = Double(range.upperBound)
        stepper.increment = 1
        stepper.intValue = Int32(value)
        stepper.controlSize = .small
        stepper.target = context.coordinator
        stepper.action = #selector(Coordinator.valueChanged(_:))
        return stepper
    }

    func updateNSView(_ stepper: EditingAwareStepper, context: Context) {
        context.coordinator.parent = self
        stepper.minValue = Double(range.lowerBound)
        stepper.maxValue = Double(range.upperBound)
        stepper.intValue = Int32(value)
        stepper.isEnabled = range.lowerBound < range.upperBound
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    @MainActor
    final class Coordinator: NSObject {
        var parent: NativeStepper

        init(parent: NativeStepper) {
            self.parent = parent
        }

        @objc func valueChanged(_ sender: NSStepper) {
            parent.value = Int(sender.intValue)
        }
    }

    final class EditingAwareStepper: NSStepper {
        override func mouseDown(with event: NSEvent) {
            window?.makeFirstResponder(nil)
            super.mouseDown(with: event)
        }
    }
}

private struct NumericTextField: NSViewRepresentable {
    @Binding var value: Int
    let range: ClosedRange<Int>

    func makeNSView(context: Context) -> NSTextField {
        let textField = NSTextField()
        textField.delegate = context.coordinator
        textField.alignment = .right
        textField.bezelStyle = .roundedBezel
        textField.controlSize = .small
        textField.font = .monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        textField.stringValue = "\(value)"
        return textField
    }

    func updateNSView(_ textField: NSTextField, context: Context) {
        context.coordinator.parent = self
        guard textField.currentEditor() == nil else {
            return
        }
        textField.stringValue = "\(value)"
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: NumericTextField

        init(parent: NumericTextField) {
            self.parent = parent
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let textField = notification.object as? NSTextField else {
                return
            }

            let digitsOnly = textField.stringValue.filter(\.isNumber)
            if digitsOnly != textField.stringValue {
                textField.stringValue = digitsOnly
            }

            guard let parsedValue = Int(digitsOnly) else {
                return
            }

            parent.value = clamped(parsedValue)
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            guard let textField = notification.object as? NSTextField else {
                return
            }

            commit(textField)
        }

        func control(
            _ control: NSControl,
            textView: NSTextView,
            doCommandBy commandSelector: Selector
        ) -> Bool {
            guard commandSelector == #selector(NSResponder.insertNewline(_:)),
                  let textField = control as? NSTextField else {
                return false
            }

            commit(textField)
            textField.window?.makeFirstResponder(nil)
            return true
        }

        private func commit(_ textField: NSTextField) {
            guard let parsedValue = Int(textField.stringValue) else {
                textField.stringValue = "\(parent.value)"
                return
            }

            let committedValue = clamped(parsedValue)
            parent.value = committedValue
            textField.stringValue = "\(committedValue)"
        }

        private func clamped(_ input: Int) -> Int {
            min(max(input, parent.range.lowerBound), parent.range.upperBound)
        }
    }
}

private struct ReadOnlyValue: View {
    let value: String

    init(_ value: String) {
        self.value = value
    }

    var body: some View {
        Text(value)
            .foregroundStyle(.secondary)
            .frame(minWidth: 120, alignment: .trailing)
    }
}

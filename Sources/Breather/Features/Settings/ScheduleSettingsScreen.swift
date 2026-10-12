import AppKit
import SwiftUI

enum RestSkipSetting: String, CaseIterable, Identifiable {
    case disallowed
    case buttonOnly
    case buttonAndEscape

    var id: String { rawValue }

    var title: String {
        switch self {
        case .disallowed: L.tr("不允许")
        case .buttonOnly: L.tr("仅使用按钮")
        case .buttonAndEscape: L.tr("按钮或 Esc 键")
        }
    }

    init(settings: AppSettings) {
        if !settings.allowSkip {
            self = .disallowed
        } else if settings.allowEscToSkip {
            self = .buttonAndEscape
        } else {
            self = .buttonOnly
        }
    }

    func apply(to settings: inout AppSettings) {
        switch self {
        case .disallowed:
            settings.allowSkip = false
            settings.allowEscToSkip = false
        case .buttonOnly:
            settings.allowSkip = true
            settings.allowEscToSkip = false
        case .buttonAndEscape:
            settings.allowSkip = true
            settings.allowEscToSkip = true
        }
    }
}

struct ScheduleSettingsScreen: View {
    @ObservedObject var settingsStore: SettingsStore
    let isWaitingToApplyRules: Bool
    let onApplyRulesToCurrentCycle: () -> Void
    let notificationService: any NotificationSettingsServicing
    let onOpenNotificationSettings: () -> Void

    @State private var notificationPermissionStatus: NotificationPermissionStatus?

    var body: some View {
        SettingsScreenContainer {
            workAndRestGroup
            timingBehaviorGroup
            restActionsGroup
        }
        .task(id: settingsStore.rules.preBreakNotificationEnabled) {
            await refreshNotificationPermissionStatus()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await refreshNotificationPermissionStatus() }
        }
    }

    private var workAndRestGroup: some View {
        SettingsGroup(L.tr("工作与休息")) {
            SettingsRow(title: L.tr("工作时长")) {
                DurationStepper(value: workMinutesBinding, range: 1...180, unit: L.tr("分钟"))
            }

            SettingsRow(title: L.tr("短休息时长")) {
                DurationStepper(value: shortBreakSecondsBinding, range: 10...600, unit: L.tr("秒"))
            }

            preBreakNotificationRows

            SettingsDivider()

            SettingsRow(title: L.tr("规则生效时间")) {
                Picker(L.tr("规则生效时间"), selection: ruleChangeEffectBinding) {
                    Text(L.tr("下个周期")).tag(RuleChangeEffect.nextCycle)
                    Text(L.tr("立即应用")).tag(RuleChangeEffect.immediate)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .fixedSize()
            }

            if shouldShowRuleStatus {
                RuleChangeStatusRow(
                    effect: settingsStore.settings.ruleChangeEffect,
                    hasPendingChanges: settingsStore.hasPendingRuleChanges,
                    isWaitingToApply: isWaitingToApplyRules,
                    onApplyNow: onApplyRulesToCurrentCycle
                )
            }
        }
    }

    @ViewBuilder
    private var preBreakNotificationRows: some View {
        SettingsRow(title: L.tr("休息前通知")) {
            Picker(L.tr("休息前通知"), selection: preBreakNotificationEnabledBinding) {
                Text(L.tr("不通知")).tag(false)
                Text(L.tr("提前通知")).tag(true)
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .fixedSize()
        }

        if settingsStore.rules.preBreakNotificationEnabled {
            SettingsRow(title: L.tr("提前时间"), role: .dependent, accessory: {
                NotificationPermissionSettingsLink(status: notificationPermissionStatus, action: onOpenNotificationSettings)
            }) {
                DurationStepper(value: preBreakNotificationSecondsBinding, range: 1...120, unit: L.tr("秒"))
            }
        }
    }

    private func refreshNotificationPermissionStatus() async {
        guard settingsStore.rules.preBreakNotificationEnabled else {
            notificationPermissionStatus = nil
            return
        }
        let status = await notificationService.authorizationStatus()
        guard !Task.isCancelled, settingsStore.rules.preBreakNotificationEnabled else { return }
        notificationPermissionStatus = status
    }

    private var timingBehaviorGroup: some View {
        SettingsGroup(L.tr("计时行为")) {
            SettingsRow(
                title: L.tr("自动计为休息"),
                description: settingsStore.settings.automaticRestMode.includesIdle
                    ? L.tr("长时间阅读或看视频，也可能算作休息。") : nil
            ) {
                SettingsMenuPicker(L.tr("自动计为休息"), selection: automaticRestModeBinding,
                    options: AutomaticRestMode.allCases.map { SettingsMenuOption(value: $0, title: $0.title) })
            }

            if settingsStore.settings.automaticRestMode.isEnabled {
                SettingsRow(
                    title: L.tr("至少持续"),
                    description: L.tr("休息时间达到设定时长，返回后开始新的工作计时。"),
                    role: .dependent
                ) {
                    DurationStepper(value: automaticRestMinutesBinding, range: 1...30, unit: L.tr("分钟"))
                }
            }

            SettingsDivider()

            SettingsRow(
                title: L.tr("屏幕镜像时暂停计时"),
                description: L.tr("支持 AirPlay 或有线连接的同画面镜像；扩展桌面和软件共享时除外。")
            ) {
                SettingsSwitch(
                    L.tr("屏幕镜像时暂停计时"),
                    isOn: settingsBinding(\.autoPauseDuringDisplayMirroring)
                )
            }
        }
    }

    private var restActionsGroup: some View {
        SettingsGroup(L.tr("休息操作")) {
            SettingsRow(title: L.tr("跳过休息")) {
                SettingsMenuPicker(L.tr("跳过休息"), selection: restSkipSettingBinding,
                    options: RestSkipSetting.allCases.map { SettingsMenuOption(value: $0, title: $0.title) })
                    .fixedSize()
            }

            SettingsDivider()

            SettingsRow(title: L.tr("延后时长")) {
                DurationStepper(value: snoozeMinutesBinding, range: 1...30, unit: L.tr("分钟"))
            }

            SettingsRow(
                title: L.tr("连续未休息次数"),
                description: L.tr("连续延后或跳过达到此次数后，下次休息时显示短休建议。")
            ) {
                DurationStepper(value: recoveryNudgeThresholdBinding, range: 2...6, unit: L.tr("次"))
            }
        }
    }

    private var shouldShowRuleStatus: Bool {
        settingsStore.hasPendingRuleChanges || isWaitingToApplyRules
    }

    private func settingsBinding(_ keyPath: WritableKeyPath<AppSettings, Bool>) -> Binding<Bool> {
        Binding(
            get: { settingsStore.settings[keyPath: keyPath] },
            set: { settingsStore.settings[keyPath: keyPath] = $0 }
        )
    }

    private var ruleChangeEffectBinding: Binding<RuleChangeEffect> {
        Binding(
            get: { settingsStore.settings.ruleChangeEffect },
            set: { settingsStore.settings.ruleChangeEffect = $0 }
        )
    }

    private var restSkipSettingBinding: Binding<RestSkipSetting> {
        Binding(
            get: { RestSkipSetting(settings: settingsStore.settings) },
            set: { selection in
                var settings = settingsStore.settings
                selection.apply(to: &settings)
                settingsStore.settings = settings
            }
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

    private var preBreakNotificationEnabledBinding: Binding<Bool> {
        Binding(
            get: { settingsStore.rules.preBreakNotificationEnabled },
            set: { enabled in
                // Finish native segmented-control tracking before inserting or removing its dependent rows.
                DispatchQueue.main.async {
                    guard settingsStore.rules.preBreakNotificationEnabled != enabled else { return }
                    settingsStore.rules.preBreakNotificationEnabled = enabled
                }
            }
        )
    }

    private var automaticRestModeBinding: Binding<AutomaticRestMode> {
        Binding(
            get: { settingsStore.settings.automaticRestMode },
            set: { settingsStore.settings.automaticRestMode = $0 }
        )
    }

    private var automaticRestMinutesBinding: Binding<Int> {
        Binding(
            get: { settingsStore.automaticRestMinutes },
            set: { settingsStore.automaticRestMinutes = $0 }
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
}

private struct NotificationPermissionSettingsLink: View {
    let status: NotificationPermissionStatus?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: statusIcon)
                    .foregroundStyle(statusColor)
                HStack(spacing: 2) {
                    Text(statusText)
                        .foregroundStyle(.tint)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .regular))
                        .foregroundStyle(.tint)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.link)
        .font(.caption)
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(statusText)
        .accessibilityHint(L.tr("打开通知设置"))
    }

    private var statusText: String {
        status?.settingsLinkTitle ?? L.tr("检测中…")
    }

    private var statusIcon: String {
        guard let status else { return "ellipsis.circle" }
        return status.canPresentNotifications ? "checkmark.circle" : "bell.slash"
    }

    private var statusColor: Color {
        guard let status else { return .secondary }
        return status.canPresentNotifications ? .green : .orange
    }
}

private struct RuleChangeStatusRow: View {
    let effect: RuleChangeEffect
    let hasPendingChanges: Bool
    let isWaitingToApply: Bool
    let onApplyNow: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                statusLabel
                Spacer(minLength: 12)
                applyButton
            }

            VStack(alignment: .leading, spacing: 8) {
                statusLabel
                applyButton
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var statusLabel: some View {
        Label(statusText, systemImage: statusIcon)
            .font(.caption)
            .foregroundStyle(statusColor)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var applyButton: some View {
        if effect == .nextCycle, hasPendingChanges {
            Button(L.tr("应用到当前周期"), action: onApplyNow)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .fixedSize()
        }
    }

    private var statusText: String {
        switch effect {
        case .nextCycle:
            L.tr("更改将在下个工作周期生效")
        case .immediate:
            isWaitingToApply ? L.tr("正在应用到当前周期…") : L.tr("已应用到当前周期")
        }
    }

    private var statusIcon: String {
        switch effect {
        case .nextCycle: "clock"
        case .immediate: isWaitingToApply ? "timer" : "checkmark.circle"
        }
    }

    private var statusColor: Color {
        switch effect {
        case .nextCycle: .orange
        case .immediate: isWaitingToApply ? .orange : .green
        }
    }
}

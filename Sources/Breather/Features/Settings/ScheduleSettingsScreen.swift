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

    var body: some View {
        SettingsScreenContainer {
            workAndRestGroup
            timingBehaviorGroup
            restActionsGroup
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

            SettingsRow(title: L.tr("休息前通知")) {
                DurationStepper(
                    value: preBreakNotificationSecondsBinding,
                    range: 0...120,
                    unit: L.tr("秒前")
                )
            }

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

    private var timingBehaviorGroup: some View {
        SettingsGroup(L.tr("计时行为")) {
            SettingsRow(
                title: L.tr("空闲后视为已休息"),
                description: L.tr("离开电脑达到这个时长后，不再补发本轮休息。")
            ) {
                DurationStepper(value: idleMinutesBinding, range: 1...30, unit: L.tr("分钟"))
            }

            SettingsRow(
                title: L.tr("屏幕镜像时暂停计时"),
                description: L.tr("仅识别 AirPlay 或有线镜像；扩展桌面和软件共享不触发。")
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
            Button(L.tr("本次应用到当前周期"), action: onApplyNow)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .fixedSize()
        }
    }

    private var statusText: String {
        switch effect {
        case .nextCycle:
            L.tr("将在下一完整工作周期生效")
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

import AppKit
import SwiftUI

enum SettingsResetGroup: Equatable {
    case advanceReminder
    case automaticRest
    case theme(RestOverlayContentMode)

    var title: String {
        switch self {
        case .advanceReminder: L.tr("休息前通知")
        case .automaticRest: L.tr("自动计为休息")
        case let .theme(theme): theme.title
        }
    }
}

struct SettingsResetChange: Identifiable, Equatable {
    let id: String
    // A changed parent setting uses its group name as the row title.
    let title: String?
    let current: String
    let restored: String
    let group: SettingsResetGroup?

    var displayTitle: String { title ?? group?.title ?? "" }
    var isGroupedChild: Bool { group != nil && title != nil }

    func contextHeading(after previous: SettingsResetChange?) -> SettingsResetGroup? {
        guard isGroupedChild, group != previous?.group else { return nil }
        return group
    }
}

/// A read-only snapshot: opening or cancelling the sheet never writes preferences.
struct SettingsResetPreview: Identifiable {
    let id = UUID()
    let scope: SettingsResetScope
    let changes: [SettingsResetChange]
    private let deferredRulesNoteKey: String?

    init(scope: SettingsResetScope, settings: AppSettings, rules: BreakRules) {
        self.scope = scope
        let defaults = scope.restoringDefaults(in: settings)
        let defaultRules = BreakRules()

        var changes: [SettingsResetChange] = []
        var deferredRulesNoteKey: String?
        func add<Value: Equatable>(_ id: String, _ title: String?, _ current: Value, _ restored: Value,
                                   group: SettingsResetGroup? = nil,
                                   _ display: (Value) -> String) {
            guard current != restored else { return }
            changes.append(SettingsResetChange(id: id, title: title.map { L.tr($0) },
                                               current: display(current), restored: display(restored), group: group))
        }
        func setting<Value: Equatable>(_ id: String, _ title: String?, _ key: KeyPath<AppSettings, Value>,
                                       group: SettingsResetGroup? = nil,
                                       _ display: (Value) -> String) {
            add(id, title, settings[keyPath: key], defaults[keyPath: key], group: group, display)
        }
        func rule<Value: Equatable>(_ id: String, _ title: String?, _ key: KeyPath<BreakRules, Value>,
                                   group: SettingsResetGroup? = nil,
                                   _ display: (Value) -> String) {
            add(id, title, rules[keyPath: key], defaultRules[keyPath: key], group: group, display)
        }
        let onOff: (Bool) -> String = { L.tr($0 ? "开启" : "关闭") }
        let duration: (TimeInterval) -> String = { value in
            let seconds = max(0, Int(value))
            if seconds >= 60 && seconds % 60 == 0 {
                return String(format: L.tr("%lld 分钟"), seconds / 60)
            }
            if seconds >= 60 {
                return String(format: L.tr("%lld 分 %lld 秒"), seconds / 60, seconds % 60)
            }
            return String(format: L.tr("%lld 秒"), seconds)
        }
        let count: (Int) -> String = { String(format: L.tr("%d 次"), $0) }
        switch scope {
        case .schedule:
            let defersDurations = rules.workDuration != defaultRules.workDuration
                || rules.shortBreakDuration != defaultRules.shortBreakDuration
            let defersReminder = rules.preBreakNotificationEnabled != defaultRules.preBreakNotificationEnabled
                || rules.preBreakNotificationOffset != defaultRules.preBreakNotificationOffset
            deferredRulesNoteKey = switch (defersDurations, defersReminder) {
            case (true, true): "时长和休息前通知将在下个周期生效。"
            case (true, false): "时长将在下个周期生效。"
            case (false, true): "休息前通知将在下个周期生效。"
            case (false, false): nil
            }

            rule("workDuration", "工作时长", \.workDuration, duration)
            rule("shortBreakDuration", "短休息时长", \.shortBreakDuration, duration)
            rule("preBreakNotificationEnabled", nil, \.preBreakNotificationEnabled, group: .advanceReminder) {
                L.tr($0 ? "提前通知" : "不通知")
            }
            rule("preBreakNotificationOffset", "提前时间", \.preBreakNotificationOffset, group: .advanceReminder, duration)
            rule("longBreakEnabled", "长休息", \.longBreakEnabled, onOff)
            rule("longBreakEveryShortBreaks", "长休息间隔", \.longBreakEveryShortBreaks, count)
            rule("longBreakDuration", "长休息时长", \.longBreakDuration, duration)
            setting("ruleChangeEffect", "修改生效时间", \.ruleChangeEffect, { $0.title })
            setting("automaticRestMode", nil, \.automaticRestMode, group: .automaticRest, { $0.title })
            setting("automaticRestThreshold", "至少持续", \.automaticRestThreshold, group: .automaticRest, duration)
            setting("autoPauseDuringDisplayMirroring", "屏幕镜像时暂停计时", \.autoPauseDuringDisplayMirroring, onOff)
            setting("allowSkip", "允许跳过休息", \.allowSkip, onOff)
            setting("allowEscToSkip", "Esc 跳过休息", \.allowEscToSkip, onOff)
            setting("strictMode", "严格模式", \.strictMode, onOff)
            setting("snoozeDuration", "延后时长", \.snoozeDuration, duration)
            setting("recoveryNudgeThreshold", "连续未休息次数", \.recoveryNudgeThreshold, count)
        case .menuBar:
            add("menuBarIcon", "菜单栏图标", MenuBarIconSetting(settings: settings),
                MenuBarIconSetting(settings: defaults), { $0.title })
            add("showCountdownInMenuBar", "倒计时显示", MenuBarCountdownSetting(settings: settings),
                MenuBarCountdownSetting(settings: defaults), { $0.title })
            setting("menuBarPopoverAppearance", "弹窗外观", \.menuBarPopoverAppearance, { $0.title })
            setting("menuBarPopoverThemeColor", "主题色", \.menuBarPopoverThemeColor, { $0.title })
            setting("menuBarPopoverProgressStyle", "进度条", \.menuBarPopoverProgressStyle, { $0.title })
            setting("menuBarPopoverSquareStyle", "中心方块", \.menuBarPopoverSquareStyle, { $0.title })
            setting("menuBarPopoverSquareColorMode", "方块颜色", \.menuBarPopoverSquareColorMode, { $0.title })
        case .restOverlay:
            setting("restOverlayContentMode", "休息主题", \.restOverlayContentMode, { $0.title })
            add("restOverlayBackground", "背景样式", RestOverlayBackgroundSetting(settings: settings),
                RestOverlayBackgroundSetting(settings: defaults), group: .theme(.classic), { $0.title })
            setting("cloudTrainPlaybackSpeed", "整体动画速度", \.cloudTrainPlaybackSpeed,
                    group: .theme(.cloudTrain), { $0.title })
            setting("cloudTrainForegroundSpeed", "前景云层速度", \.cloudTrainForegroundSpeed,
                    group: .theme(.cloudTrain), { $0.title })
            setting("curtainPalette", "帷幕配色", \.curtainPalette, group: .theme(.curtain), { $0.title })
            setting("rainAmbienceEnabled", "持续雨声", \.rainAmbienceEnabled, group: .theme(.rainy), onOff)
            setting("restOverlayFadeAnimation", "休息界面过渡动画", \.restOverlayFadeAnimation, onOff)
            setting("restOverlayPrompt", "主提示语", \.restOverlayPrompt, { $0.title })
            setting("restOverlaySubtitle", "辅助提示语", \.restOverlaySubtitle, { $0.title })
            add("restStartSoundEffect", "进入休息提示音",
                settings.restStartSoundEffect.selection(isEnabled: settings.playRestStartSound),
                defaults.restStartSoundEffect.selection(isEnabled: defaults.playRestStartSound), { $0.title })
            add("restEndSoundEffect", "结束休息提示音",
                settings.restEndSoundEffect.selection(isEnabled: settings.playRestEndSound),
                defaults.restEndSoundEffect.selection(isEnabled: defaults.playRestEndSound), { $0.title })
        }
        self.changes = changes
        self.deferredRulesNoteKey = deferredRulesNoteKey
    }

    func effectNote(isResting: Bool) -> String? {
        if let deferredRulesNoteKey {
            return L.tr(deferredRulesNoteKey)
        }
        if scope == .restOverlay && isResting && changes.contains(where: {
            $0.id != "restStartSoundEffect" && $0.id != "restEndSoundEffect"
        }) {
            return L.tr("休息画面的改动从下次休息生效。")
        }
        return nil
    }
}

struct SettingsResetButton: View {
    @ObservedObject var settingsStore: SettingsStore
    let scope: SettingsResetScope
    var isResting = false
    var onRestore: (() -> Void)? = nil
    @State private var preview: SettingsResetPreview?
    @Environment(\.settingsResetTransition) private var transition

    var body: some View {
        Button(scope.resetButtonTitle) {
            transition?.prepareForConfirmation()
            preview = SettingsResetPreview(scope: scope, settings: settingsStore.settings, rules: settingsStore.rules)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(settingsStore.isDefault(for: scope))
        .frame(maxWidth: .infinity, alignment: .trailing)
        .sheet(item: $preview, onDismiss: { transition?.confirmationDismissed() }) { snapshot in
            SettingsResetSheet(preview: snapshot, isResting: isResting) {
                let commit = {
                    if let onRestore { onRestore() }
                    else { settingsStore.restoreDefaults(for: scope) }
                }
                if let transition { transition.restore(commit) }
                else { commit() }
            }
        }
    }
}

struct SettingsResetSheet: View {
    let preview: SettingsResetPreview
    var isResting = false
    let onRestore: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @FocusState private var cancelFocused: Bool
    private let sheetWidth: CGFloat = 500
    private let horizontalInset: CGFloat = 24

    var body: some View {
        let effectNote = preview.effectNote(isResting: isResting)
        let listLimit: CGFloat = effectNote == nil ? 372 : 342
        VStack(alignment: .leading, spacing: 0) {
            Text(preview.scope.confirmationTitle)
                .font(.title3.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .padding(.horizontal, horizontalInset)
                .padding(.top, 24)
                .padding(.bottom, 12)

            SettingsResetReceipt(preview: preview, width: sheetWidth - horizontalInset * 2,
                                 maximumHeight: listLimit)
                .padding(.horizontal, horizontalInset)

            if let note = effectNote {
                Text(note).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, horizontalInset)
                    .padding(.top, 10)
            }
            Divider().padding(.top, 12)
            HStack(spacing: 12) {
                Spacer()
                Button(L.tr("取消")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .focused($cancelFocused)
                Button(L.tr("还原"), role: .destructive) { onRestore(); dismiss() }
                    .buttonStyle(.borderedProminent)
                    .disabled(preview.changes.isEmpty)
            }
            .controlSize(.regular)
            .padding(.horizontal, horizontalInset)
            .padding(.vertical, 16)
        }
        .defaultFocus($cancelFocused, true)
        .frame(width: sheetWidth)
        .background(reduceTransparency
                    ? AnyShapeStyle(Color(nsColor: .windowBackgroundColor))
                    : AnyShapeStyle(.regularMaterial))
    }
}

struct SettingsResetColumns {
    static let gap: CGFloat = 18
    static let indent: CGFloat = 12
    let labelWidth: CGFloat?
    let oldWidth: CGFloat

    func currentValueWidth(leadingInset: CGFloat) -> CGFloat {
        // Keep the restored column fixed while a stacked child block is inset.
        max(0, oldWidth - (labelWidth == nil ? leadingInset : 0))
    }

    init(changes: [SettingsResetChange], width: CGFloat) {
        let font = NSFont.preferredFont(forTextStyle: .body, options: [:])
        let medium = NSFont.systemFont(ofSize: font.pointSize, weight: .medium)
        let semibold = NSFont.systemFont(ofSize: font.pointSize, weight: .semibold)
        func measure(_ value: String, font: NSFont) -> CGFloat {
            ceil((value as NSString).size(withAttributes: [.font: font]).width)
        }

        let label = max(137, changes.map {
            measure($0.displayTitle, font: $0.title == nil ? semibold : font)
                + ($0.isGroupedChild ? Self.indent : 0)
        }.max() ?? 0)
        let old = max(108, changes.map { measure($0.current, font: font) + 8 }.max() ?? 0)
        let restored = changes.map { measure($0.restored, font: medium) }.max() ?? 0
        // Pick one layout for the whole list so every value shares the same column start.
        if label + old + restored + Self.gap * 2 <= width {
            labelWidth = label
            oldWidth = old
        } else {
            labelWidth = nil
            oldWidth = (width - Self.gap) / 2
        }
    }
}

struct SettingsResetChangeRow: View {
    let change: SettingsResetChange
    let index: Int
    let bottomInset: CGFloat
    let columns: SettingsResetColumns?
    var showCorrections = true
    var ink: Color = .primary
    var secondaryInk: Color = .secondary
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var editProgress: CGFloat = 0

    var body: some View {
        rowContent
            .font(.body)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 8)
            .padding(.bottom, bottomInset)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityTitle)
            .accessibilityValue(String(format: L.tr("当前 %@，还原后 %@"), change.current, change.restored))
            .task(id: showCorrections && !reduceMotion) {
                if reduceMotion || !showCorrections {
                    var transaction = Transaction(animation: nil)
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        editProgress = reduceMotion ? 1 : 0
                    }
                    return
                }
                guard editProgress < 1 else { return }
                do {
                    try await Task.sleep(for: .seconds(SettingsResetPaperFeed.correctionDelay(for: index)))
                    withAnimation(.timingCurve(0.23, 1, 0.32, 1, duration: SettingsResetPaperFeed.correctionDuration)) {
                        editProgress = 1
                    }
                } catch { return }
            }
    }

    @ViewBuilder private var rowContent: some View {
        let indent = change.isGroupedChild ? SettingsResetColumns.indent : 0
        let label = Text(change.displayTitle)
            .fontWeight(change.title == nil ? .semibold : .regular)
            .foregroundStyle(ink)
        if let labelWidth = columns?.labelWidth {
            HStack(alignment: .firstTextBaseline, spacing: SettingsResetColumns.gap) {
                label.padding(.leading, indent).frame(width: labelWidth, alignment: .leading)
                values(leadingInset: 0)
            }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                label
                values(leadingInset: indent)
            }
            .padding(.leading, indent)
        }
    }

    private func values(leadingInset: CGFloat) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: SettingsResetColumns.gap) {
            Text(change.current).foregroundStyle(secondaryInk)
                .textRenderer(LooseleafResetRenderer(progress: reduceMotion ? 1 : editProgress,
                                                    settingID: change.id, colorScheme: colorScheme))
                .frame(width: columns?.currentValueWidth(leadingInset: leadingInset), alignment: .leading)
            Text(change.restored).fontWeight(.medium)
                .foregroundStyle(ink)
                .frame(maxWidth: .infinity, alignment: columns?.labelWidth == nil ? .leading : .trailing)
        }
    }

    private var accessibilityTitle: String {
        if let group = change.group, let title = change.title {
            return String(format: L.tr("%@，%@"), group.title, title)
        }
        return change.displayTitle
    }
}

private extension SettingsResetScope {
    var resetButtonTitle: String {
        switch self {
        case .schedule: L.tr("还原计划设置…")
        case .menuBar: L.tr("还原菜单栏设置…")
        case .restOverlay: L.tr("还原休息界面设置…")
        }
    }

    var confirmationTitle: String {
        switch self {
        case .schedule: L.tr("还原计划设置")
        case .menuBar: L.tr("还原菜单栏设置")
        case .restOverlay: L.tr("还原休息界面设置")
        }
    }
}

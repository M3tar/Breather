import SwiftUI

enum RestOverlayBackgroundSetting: String, CaseIterable, Identifiable {
    case solid
    case translucentSolid
    case linen
    case moon
    case sun

    var id: String { rawValue }

    var title: String {
        switch self {
        case .solid: "纯色"
        case .translucentSolid: "半透明纯色"
        case .linen: "亚麻米色"
        case .moon: "月亮"
        case .sun: "太阳"
        }
    }

    init(settings: AppSettings) {
        switch settings.restOverlayBackground {
        case .solid:
            self = settings.restOverlayTranslucentBackground ? .translucentSolid : .solid
        case .linen:
            self = .linen
        case .moon:
            self = .moon
        case .sun:
            self = .sun
        }
    }

    func apply(to settings: inout AppSettings) {
        switch self {
        case .solid:
            settings.restOverlayBackground = .solid
            settings.restOverlayTranslucentBackground = false
        case .translucentSolid:
            settings.restOverlayBackground = .solid
            settings.restOverlayTranslucentBackground = true
        case .linen:
            settings.restOverlayBackground = .linen
            settings.restOverlayTranslucentBackground = false
        case .moon:
            settings.restOverlayBackground = .moon
            settings.restOverlayTranslucentBackground = false
        case .sun:
            settings.restOverlayBackground = .sun
            settings.restOverlayTranslucentBackground = false
        }
    }
}

private struct RestBackgroundStylePicker: View {
    @Binding var selection: RestOverlayBackgroundSetting

    var body: some View {
        VisualChoicePicker(
            options: RestOverlayBackgroundSetting.allCases,
            selection: $selection,
            title: \.title
        ) { setting in
            RestBackgroundStyleSwatch(setting: setting)
        }
    }
}

struct CurtainPalettePicker: View {
    @Binding var selection: CurtainPalette

    var body: some View {
        VisualChoicePicker(
            options: CurtainPalette.allCases,
            selection: $selection,
            title: \.title
        ) { palette in
            let colors = CurtainColors(palette: palette)
            LinearGradient(
                colors: [colors.deep, colors.highlight, colors.base, colors.deep],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
    }
}

private struct VisualChoicePicker<Option, Preview>: View
where Option: Hashable & Identifiable, Preview: View {
    let options: [Option]
    @Binding var selection: Option
    let title: (Option) -> String
    @ViewBuilder let preview: (Option) -> Preview

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                ForEach(options) { option in choice(option) }
            }

            Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                ForEach(0..<((options.count + 2) / 3), id: \.self) { row in
                    GridRow {
                        ForEach(0..<3, id: \.self) { column in
                            let index = row * 3 + column
                            if index < options.count {
                                choice(options[index])
                            } else {
                                Color.clear.frame(width: 62, height: 54)
                            }
                        }
                    }
                }
            }
        }
    }

    private func choice(_ option: Option) -> some View {
        let selected = selection == option
        return Button {
            selection = option
        } label: {
            VStack(spacing: 5) {
                preview(option)
                    .frame(width: 62, height: 34)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(selected ? Color.accentColor : Color.secondary.opacity(0.28),
                                          lineWidth: selected ? 2 : 1)
                    }
                    .overlay(alignment: .topTrailing) {
                        if selected {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 12))
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, Color.accentColor)
                                .padding(3)
                        }
                    }

                Text(title(option))
                    .font(.caption2)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title(option))
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

private struct RestBackgroundStyleSwatch: View {
    @Environment(\.colorScheme) private var colorScheme
    let setting: RestOverlayBackgroundSetting

    var body: some View {
        ZStack {
            if setting == .translucentSolid {
                CheckerboardSwatch()
            }
            RestOverlayBackgroundView(
                background: setting.background,
                style: RestOverlayStyle(background: setting.background, colorScheme: colorScheme),
                translucent: setting == .translucentSolid
            )
        }
    }
}

private struct CheckerboardSwatch: View {
    var body: some View {
        Canvas { context, size in
            let cell = size.height / 2
            for row in 0..<2 {
                for column in 0..<4 where (row + column).isMultiple(of: 2) {
                    context.fill(
                        Path(CGRect(x: CGFloat(column) * cell, y: CGFloat(row) * cell,
                                    width: cell, height: cell)),
                        with: .color(Color.secondary.opacity(0.14))
                    )
                }
            }
        }
        .background(Color.primary.opacity(0.04))
    }
}

private extension RestOverlayBackgroundSetting {
    var background: RestOverlayBackground {
        switch self {
        case .solid, .translucentSolid: .solid
        case .linen: .linen
        case .moon: .moon
        case .sun: .sun
        }
    }
}

struct RestOverlaySettingsScreen: View {
    @ObservedObject var settingsStore: SettingsStore
    let restSoundService: RestSoundService
    @ObservedObject var availability = RestOverlayAvailability()
    let onPreviewRestOverlay: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            SettingsScreenContainer {
                RestThemePicker(settings: $settingsStore.settings,
                                duration: settingsStore.shortBreakSeconds,
                                isResting: availability.isResting)
                appearanceGroup
                copyGroup
                soundGroup
            }

            previewActionBar
        }
    }

    private var appearanceGroup: some View {
        SettingsGroup("外观") {
            if settingsStore.settings.restOverlayContentMode == .classic {
                SettingsRow(title: "背景样式") {
                    RestBackgroundStylePicker(selection: restOverlayBackgroundSettingBinding)
                }
            }

            if settingsStore.settings.restOverlayContentMode == .curtain {
                SettingsRow(title: "帷幕配色") {
                    CurtainPalettePicker(selection: curtainPaletteBinding)
                }
            }

            SettingsRow(title: "休息界面过渡动画") {
                SettingsSwitch(
                    "休息界面过渡动画",
                    isOn: settingsBinding(\.restOverlayFadeAnimation)
                )
            }
        }
    }

    private var copyGroup: some View {
        SettingsGroup("文字") {
            SettingsRow(title: "主提示语") {
                Picker("主提示语", selection: restOverlayPromptBinding) {
                    ForEach(RestOverlayPrompt.fixedCases) { prompt in
                        Text(prompt.title).tag(prompt)
                    }
                    Divider()
                    Text(RestOverlayPrompt.random.title).tag(RestOverlayPrompt.random)
                    Text(RestOverlayPrompt.none.title).tag(RestOverlayPrompt.none)
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
            }

            SettingsRow(title: "辅助提示语") {
                Picker("辅助提示语", selection: restOverlaySubtitleBinding) {
                    ForEach(RestOverlaySubtitle.fixedCases) { subtitle in
                        Text(subtitle.title).tag(subtitle)
                    }
                    Divider()
                    Text(RestOverlaySubtitle.random.title).tag(RestOverlaySubtitle.random)
                    Text(RestOverlaySubtitle.none.title).tag(RestOverlaySubtitle.none)
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
            }
        }
    }

    private var soundGroup: some View {
        SettingsGroup("声音") {
            if settingsStore.settings.restOverlayContentMode == .rainy {
                SettingsRow(title: "持续雨声") {
                    SettingsSwitch(
                        "持续雨声",
                        isOn: settingsBinding(\.rainAmbienceEnabled)
                    )
                }
            }

            SettingsRow(title: "进入休息") {
                SoundEffectControl(selection: restStartSoundEffectBinding) {
                    previewSound(settingsStore.settings.restStartSoundEffect)
                }
            }

            SettingsRow(title: "结束休息") {
                SoundEffectControl(selection: restEndSoundEffectBinding) {
                    previewSound(settingsStore.settings.restEndSoundEffect)
                }
            }
        }
    }

    private var previewActionBar: some View {
        HStack(spacing: 8) {
            Text("当前主题")
                .font(.callout)
                .foregroundStyle(.secondary)

            Text(settingsStore.settings.restOverlayContentMode.title)
                .font(.body.weight(.medium))

            Spacer()

            if availability.isResting {
                Text("休息结束后可预览")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button(action: onPreviewRestOverlay) {
                Label("全屏预览", systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .disabled(availability.isResting)
            .help("预览当前休息界面设置")
        }
        .padding(.horizontal, 20)
        .frame(height: SettingsFooterMetrics.height)
        .background(.bar)
        .overlay(alignment: .top) {
            Divider()
        }
    }

    private func settingsBinding(_ keyPath: WritableKeyPath<AppSettings, Bool>) -> Binding<Bool> {
        Binding(
            get: { settingsStore.settings[keyPath: keyPath] },
            set: { settingsStore.settings[keyPath: keyPath] = $0 }
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

    private var restOverlayBackgroundSettingBinding: Binding<RestOverlayBackgroundSetting> {
        Binding(
            get: { RestOverlayBackgroundSetting(settings: settingsStore.settings) },
            set: { selection in
                var settings = settingsStore.settings
                selection.apply(to: &settings)
                settingsStore.settings = settings
            }
        )
    }

    private var curtainPaletteBinding: Binding<CurtainPalette> {
        Binding(
            get: { settingsStore.settings.curtainPalette },
            set: { settingsStore.settings.curtainPalette = $0 }
        )
    }

    private var restStartSoundEffectBinding: Binding<RestSoundEffect> {
        Binding(
            get: {
                guard settingsStore.settings.playRestStartSound else {
                    return .none
                }
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
                guard settingsStore.settings.playRestEndSound else {
                    return .none
                }
                let effect = settingsStore.settings.restEndSoundEffect
                return RestSoundEffect.selectableCases.contains(effect) ? effect : .none
            },
            set: { effect in
                settingsStore.settings.restEndSoundEffect = effect
                settingsStore.settings.playRestEndSound = effect != .none
            }
        )
    }

    private func previewSound(_ effect: RestSoundEffect) {
        restSoundService.stop()
        restSoundService.play(effect)
    }
}

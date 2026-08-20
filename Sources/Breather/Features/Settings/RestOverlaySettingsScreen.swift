import SwiftUI

enum RestOverlayBackgroundSetting: String, CaseIterable, Identifiable {
    case solid
    case translucentSolid
    case moon
    case sun

    var id: String { rawValue }

    var title: String {
        switch self {
        case .solid: "纯色"
        case .translucentSolid: "半透明纯色"
        case .moon: "月亮"
        case .sun: "太阳"
        }
    }

    init(settings: AppSettings) {
        switch settings.restOverlayBackground {
        case .solid:
            self = settings.restOverlayTranslucentBackground ? .translucentSolid : .solid
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
        case .moon:
            settings.restOverlayBackground = .moon
            settings.restOverlayTranslucentBackground = false
        case .sun:
            settings.restOverlayBackground = .sun
            settings.restOverlayTranslucentBackground = false
        }
    }
}

struct RestOverlaySettingsScreen: View {
    @ObservedObject var settingsStore: SettingsStore
    let restSoundService: RestSoundService
    let onPreviewRestOverlay: () -> Void

    var body: some View {
        SettingsScreenContainer {
            appearanceGroup
            copyGroup

            VStack(alignment: .leading, spacing: 15) {
                soundGroup
                previewAction
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var appearanceGroup: some View {
        SettingsGroup("外观") {
            SettingsRow(title: "背景样式") {
                Picker("背景样式", selection: restOverlayBackgroundSettingBinding) {
                    ForEach(RestOverlayBackgroundSetting.allCases) { setting in
                        Text(setting.title).tag(setting)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
            }

            SettingsRow(title: "转场动画") {
                SettingsSwitch(
                    "转场动画",
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

    private var previewAction: some View {
        Button(action: onPreviewRestOverlay) {
            Label("预览界面", systemImage: "play.fill")
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
        .help("预览当前休息界面设置")
        .frame(maxWidth: .infinity, alignment: .trailing)
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

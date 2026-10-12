import SwiftUI

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
        case .hidden: L.tr("不显示")
        case .minutes: L.tr("分钟")
        case .minutesAndSeconds: L.tr("分钟和秒")
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

struct MenuBarSettingsScreen: View {
    @ObservedObject var settingsStore: SettingsStore

    var body: some View {
        SettingsScreenContainer {
            menuBarGroup
            menuBarPopoverGroup
        }
    }

    private var menuBarGroup: some View {
        SettingsGroup(L.tr("菜单栏显示")) {
            SettingsRow(title: L.tr("菜单栏图标")) {
                MenuBarIconControl(selection: menuBarIconSettingBinding)
            }

            SettingsRow(title: L.tr("倒计时显示")) {
                menuPicker(
                    title: L.tr("倒计时显示"),
                    selection: menuBarCountdownSettingBinding,
                    values: MenuBarCountdownSetting.allCases
                )
            }
        }
    }

    private var menuBarPopoverGroup: some View {
        SettingsGroup(L.tr("菜单栏弹窗")) {
            SettingsRow(title: L.tr("弹窗外观")) {
                menuPicker(
                    title: L.tr("弹窗外观"),
                    selection: menuBarPopoverAppearanceBinding,
                    values: MenuBarPopoverAppearance.allCases
                )
            }

            SettingsRow(title: L.tr("主题色")) {
                menuPicker(
                    title: L.tr("主题色"),
                    selection: menuBarPopoverThemeColorBinding,
                    values: MenuBarPopoverThemeColor.allCases
                )
            }

            SettingsRow(title: L.tr("进度条")) {
                menuPicker(
                    title: L.tr("进度条"),
                    selection: menuBarPopoverProgressStyleBinding,
                    values: MenuBarPopoverProgressStyle.allCases
                )
            }

            SettingsRow(title: L.tr("中心方块")) {
                menuPicker(
                    title: L.tr("中心方块"),
                    selection: menuBarPopoverSquareStyleBinding,
                    values: MenuBarPopoverSquareStyle.allCases
                )
            }

            SettingsRow(title: L.tr("方块颜色")) {
                menuPicker(
                    title: L.tr("方块颜色"),
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
        SettingsMenuPicker(title, selection: selection, options: values.map {
            SettingsMenuOption(value: $0, title: $0.title)
        })
        .fixedSize()
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

struct MenuBarIconControl: View {
    @Binding var selection: MenuBarIconSetting

    var body: some View {
        SettingsMenuPicker(L.tr("菜单栏图标"), selection: $selection, options:
            [SettingsMenuOption(value: MenuBarIconSetting.hidden, title: L.tr("不显示"))]
            + MenuBarIcon.allCases.enumerated().map { index, icon in
                SettingsMenuOption(value: .icon(icon), title: icon.title,
                    imageName: icon.assetName, separatorBefore: index == 0)
            }
        )
        .fixedSize()
    }
}

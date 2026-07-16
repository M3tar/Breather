import Foundation

enum RuleChangeEffect: String, Codable, CaseIterable, Identifiable {
    case nextCycle
    case immediate

    var id: String { rawValue }

    var title: String {
        switch self {
        case .nextCycle: "下个周期生效"
        case .immediate: "立即生效"
        }
    }
}

enum AppearancePreference: String, Codable, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "跟随系统"
        case .light: "浅色"
        case .dark: "深色"
        }
    }
}

enum MenuBarPopoverThemeColor: String, Codable, CaseIterable, Identifiable {
    case jadeCore
    case jadeToken
    case tealGlass
    case mintAir
    case mistBlue
    case skyBreath
    case lilacCalm
    case irisDrift
    case amberRest
    case warmClay
    case neutralCore

    var id: String { rawValue }

    var title: String {
        switch self {
        case .jadeCore: "Jade Core"
        case .jadeToken: "Jade Token"
        case .neutralCore: "Neutral Core"
        case .tealGlass: "Teal Glass"
        case .mintAir: "Mint Air"
        case .mistBlue: "Mist Blue"
        case .skyBreath: "Sky Breath"
        case .lilacCalm: "Lilac Calm"
        case .irisDrift: "Iris Drift"
        case .warmClay: "Warm Clay"
        case .amberRest: "Amber Rest"
        }
    }
}

enum MenuBarPopoverProgressStyle: String, Codable, CaseIterable, Identifiable {
    case radix
    case segments

    var id: String { rawValue }

    var title: String {
        switch self {
        case .radix: "Radix 滑动"
        case .segments: "Segments 分段"
        }
    }
}

enum MenuBarPopoverSquareStyle: String, Codable, CaseIterable, Identifiable {
    case breathing
    case block

    var id: String { rawValue }

    var title: String {
        switch self {
        case .breathing: "Breathing"
        case .block: "Block"
        }
    }
}

enum MenuBarPopoverSquareColorMode: String, Codable, CaseIterable, Identifiable {
    case followTheme
    case neutral

    var id: String { rawValue }

    var title: String {
        switch self {
        case .followTheme: "跟随主题色"
        case .neutral: "中性色"
        }
    }
}

enum MenuBarPopoverAppearance: String, Codable, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "跟随系统"
        case .light: "浅色"
        case .dark: "深色"
        }
    }
}

enum MenuBarIcon: String, Codable, CaseIterable, Identifiable {
    case breather01
    case breather02
    case breather03
    case breather04
    case breather05
    case breather06
    case breather07
    case breather08
    case breather09

    var id: String { rawValue }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        if let icon = MenuBarIcon(rawValue: rawValue) {
            self = icon
            return
        }

        switch rawValue {
        case "breather10":
            self = .breather05
        case "breather11":
            self = .breather06
        case "breather13":
            self = .breather07
        case "breather15":
            self = .breather08
        case "breather16":
            self = .breather09
        default:
            self = .breather01
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    var title: String {
        switch self {
        case .breather01: "Breather 01"
        case .breather02: "Breather 02"
        case .breather03: "Breather 03"
        case .breather04: "Breather 04"
        case .breather05: "Breather 05"
        case .breather06: "Breather 06"
        case .breather07: "Breather 07"
        case .breather08: "Breather 08"
        case .breather09: "Breather 09"
        }
    }

    var assetName: String {
        switch self {
        case .breather01: "breather-menubar-01"
        case .breather02: "breather-menubar-02"
        case .breather03: "breather-menubar-03"
        case .breather04: "breather-menubar-04"
        case .breather05: "breather-menubar-05"
        case .breather06: "breather-menubar-06"
        case .breather07: "breather-menubar-07"
        case .breather08: "breather-menubar-08"
        case .breather09: "breather-menubar-09"
        }
    }
}

enum RestOverlayPrompt: String, Codable, CaseIterable, Identifiable {
    case lookFar
    case breathe
    case blink
    case stretch
    case standUp
    case random
    case none

    var id: String { rawValue }

    static var fixedCases: [RestOverlayPrompt] {
        [.lookFar, .breathe, .blink, .stretch, .standUp]
    }

    var title: String {
        switch self {
        case .lookFar: "请眺望远方"
        case .breathe: "慢慢呼吸"
        case .blink: "放松眼睛"
        case .stretch: "伸展一下"
        case .standUp: "站起来走走"
        case .random: "随机"
        case .none: "无"
        }
    }

    var resolvedTitle: String? {
        switch self {
        case .random:
            RestOverlayPrompt.fixedCases.randomElement()?.title
        case .none:
            nil
        default:
            title
        }
    }
}

enum RestOverlaySubtitle: String, Codable, CaseIterable, Identifiable {
    case takeBreath
    case softenShoulders
    case restEyes
    case leaveScreen
    case shortPause
    case random
    case none

    var id: String { rawValue }

    static var fixedCases: [RestOverlaySubtitle] {
        [.takeBreath, .softenShoulders, .restEyes, .leaveScreen, .shortPause]
    }

    var title: String {
        switch self {
        case .takeBreath: "到点了，喘口气。"
        case .softenShoulders: "放松肩颈，慢一点。"
        case .restEyes: "让眼睛离开屏幕一会儿。"
        case .leaveScreen: "离开屏幕，给自己一点空白。"
        case .shortPause: "暂停一下，再继续。"
        case .random: "随机"
        case .none: "无"
        }
    }

    var resolvedTitle: String? {
        switch self {
        case .random:
            RestOverlaySubtitle.fixedCases.randomElement()?.title
        case .none:
            nil
        default:
            title
        }
    }
}

enum RestOverlayBackground: String, Codable, CaseIterable, Identifiable {
    case solid
    case moon
    case sun

    var id: String { rawValue }

    var title: String {
        switch self {
        case .solid: "纯色"
        case .moon: "月亮"
        case .sun: "太阳"
        }
    }

    var imageName: String? {
        switch self {
        case .solid: nil
        case .moon: "rest-background-moon"
        case .sun: "rest-background-sun"
        }
    }
}

enum RestSoundEffect: String, Codable, CaseIterable, Identifiable {
    case stardewFishHook = "stardew-fish-hook"
    case stardewAchievement = "stardew-achievement"
    case stardewSpecialItem = "stardew-special-item"
    case stardewGiveGift = "stardew-give-gift"
    case stardewHorseFlute = "stardew-horse-flute"
    case stardewMineral = "stardew-mineral"
    case stardewNewRecord = "stardew-new-record"
    case stardewReward = "stardew-reward"
    case boop
    case breeze
    case bubble
    case codexNotification = "codex-notification"
    case crystal
    case funky
    case heroine
    case jump
    case mezzo
    case pebble
    case pluck
    case pong
    case sonar
    case sonumi
    case submerge
    case glass
    case ping
    case pop
    case tink
    case hero
    case purr
    case basso
    case blow
    case bottle
    case frog
    case funk
    case morse
    case sosumi
    case submarine
    case random
    case none

    var id: String { rawValue }

    static var fixedCases: [RestSoundEffect] {
        [
            .stardewFishHook,
            .stardewAchievement,
            .stardewSpecialItem,
            .stardewGiveGift,
            .stardewHorseFlute,
            .stardewMineral,
            .stardewNewRecord,
            .stardewReward,
            .codexNotification,
            .glass,
            .ping,
            .pop,
            .tink,
            .hero,
            .purr,
            .basso,
            .blow,
            .bottle,
            .frog,
            .funk,
            .morse,
            .sosumi,
            .submarine
        ]
    }

    static var selectableCases: [RestSoundEffect] {
        fixedCases + [.random, .none]
    }

    var title: String {
        switch self {
        case .stardewFishHook: "鱼上钩"
        case .stardewAchievement: "成就"
        case .stardewSpecialItem: "特殊物品"
        case .stardewGiveGift: "给礼物"
        case .stardewHorseFlute: "马笛"
        case .stardewMineral: "发现矿物"
        case .stardewNewRecord: "新纪录"
        case .stardewReward: "奖励"
        case .boop: "Boop"
        case .breeze: "Breeze"
        case .bubble: "Bubble"
        case .codexNotification: "codex-notification"
        case .crystal: "Crystal"
        case .funky: "Funky"
        case .heroine: "Heroine"
        case .jump: "Jump"
        case .mezzo: "Mezzo"
        case .pebble: "Pebble"
        case .pluck: "Pluck"
        case .pong: "Pong"
        case .sonar: "Sonar"
        case .sonumi: "Sonumi"
        case .submerge: "Submerge"
        case .glass: "放松"
        case .ping: "清脆"
        case .pop: "弹出"
        case .tink: "轻响"
        case .hero: "明亮"
        case .purr: "柔和"
        case .basso: "低沉"
        case .blow: "轻吹"
        case .bottle: "瓶音"
        case .frog: "短促"
        case .funk: "活泼"
        case .morse: "电报码"
        case .sosumi: "经典"
        case .submarine: "下潜"
        case .random: "随机"
        case .none: "无"
        }
    }

    var systemSoundName: String? {
        switch self {
        case .stardewFishHook,
             .stardewAchievement,
             .stardewSpecialItem,
             .stardewGiveGift,
             .stardewHorseFlute,
             .stardewMineral,
             .stardewNewRecord,
             .stardewReward:
            nil
        case .boop: "Boop"
        case .breeze: "Breeze"
        case .bubble: "Bubble"
        case .codexNotification: "codex-notification"
        case .crystal: "Crystal"
        case .funky: "Funky"
        case .heroine: "Heroine"
        case .jump: "Jump"
        case .mezzo: "Mezzo"
        case .pebble: "Pebble"
        case .pluck: "Pluck"
        case .pong: "Pong"
        case .sonar: "Sonar"
        case .sonumi: "Sonumi"
        case .submerge: "Submerge"
        case .glass: "Glass"
        case .ping: "Ping"
        case .pop: "Pop"
        case .tink: "Tink"
        case .hero: "Hero"
        case .purr: "Purr"
        case .basso: "Basso"
        case .blow: "Blow"
        case .bottle: "Bottle"
        case .frog: "Frog"
        case .funk: "Funk"
        case .morse: "Morse"
        case .sosumi: "Sosumi"
        case .submarine: "Submarine"
        case .random: RestSoundEffect.fixedCases.randomElement()?.systemSoundName
        case .none: nil
        }
    }

    var bundledSoundFileName: String? {
        switch self {
        case .stardewFishHook,
             .stardewAchievement,
             .stardewSpecialItem,
             .stardewGiveGift,
             .stardewHorseFlute,
             .stardewMineral,
             .stardewNewRecord,
             .stardewReward:
            "\(rawValue).mp3"
        case .random:
            RestSoundEffect.fixedCases.randomElement()?.bundledSoundFileName
        default:
            nil
        }
    }
}

struct AppSettings: Codable, Equatable {
    var launchAtLogin: Bool = false
    var appearancePreference: AppearancePreference = .system
    var showMenuBarIcon: Bool = true
    var menuBarIcon: MenuBarIcon = .breather01
    var menuBarPopoverThemeColor: MenuBarPopoverThemeColor = .jadeCore
    var menuBarPopoverProgressStyle: MenuBarPopoverProgressStyle = .radix
    var menuBarPopoverSquareStyle: MenuBarPopoverSquareStyle = .breathing
    var menuBarPopoverSquareColorMode: MenuBarPopoverSquareColorMode = .followTheme
    var menuBarPopoverAppearance: MenuBarPopoverAppearance = .system
    var showCountdownInMenuBar: Bool = true
    var showSeconds: Bool = false
    var ruleChangeEffect: RuleChangeEffect = .nextCycle
    var playSound: Bool = true
    var notificationSoundEnabled: Bool = true
    var notificationSoundEffect: RestSoundEffect = .stardewAchievement
    var allowSkip: Bool = true
    var allowEscToSkip: Bool = true
    var snoozeDuration: TimeInterval = 3 * 60
    var recoveryNudgeThreshold: Int = 2
    var strictMode: Bool = false
    var pauseDuringScreenSharing: Bool = false
    var resetAfterWakeOrUnlock: Bool = false
    var restOverlayPrompt: RestOverlayPrompt = .lookFar
    var restOverlaySubtitle: RestOverlaySubtitle = .takeBreath
    var restOverlayBackground: RestOverlayBackground = .solid
    var restOverlayFadeAnimation: Bool = true
    var restOverlayTranslucentBackground: Bool = false
    var playRestStartSound: Bool = true
    var playRestEndSound: Bool = true
    var restStartSoundEffect: RestSoundEffect = .stardewNewRecord
    var restEndSoundEffect: RestSoundEffect = .stardewHorseFlute
    var idleThreshold: TimeInterval = 5 * 60

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        launchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false
        appearancePreference = try container.decodeIfPresent(AppearancePreference.self, forKey: .appearancePreference) ?? .system
        showMenuBarIcon = try container.decodeIfPresent(Bool.self, forKey: .showMenuBarIcon) ?? true
        menuBarIcon = try container.decodeIfPresent(MenuBarIcon.self, forKey: .menuBarIcon) ?? .breather01
        menuBarPopoverThemeColor = try container.decodeIfPresent(MenuBarPopoverThemeColor.self, forKey: .menuBarPopoverThemeColor) ?? .jadeCore
        menuBarPopoverProgressStyle = try container.decodeIfPresent(MenuBarPopoverProgressStyle.self, forKey: .menuBarPopoverProgressStyle) ?? .radix
        menuBarPopoverSquareStyle = try container.decodeIfPresent(MenuBarPopoverSquareStyle.self, forKey: .menuBarPopoverSquareStyle) ?? .breathing
        menuBarPopoverSquareColorMode = try container.decodeIfPresent(MenuBarPopoverSquareColorMode.self, forKey: .menuBarPopoverSquareColorMode) ?? .followTheme
        menuBarPopoverAppearance = try container.decodeIfPresent(MenuBarPopoverAppearance.self, forKey: .menuBarPopoverAppearance) ?? .system
        showCountdownInMenuBar = try container.decodeIfPresent(Bool.self, forKey: .showCountdownInMenuBar) ?? true
        showSeconds = try container.decodeIfPresent(Bool.self, forKey: .showSeconds) ?? false
        ruleChangeEffect = try container.decodeIfPresent(RuleChangeEffect.self, forKey: .ruleChangeEffect) ?? .nextCycle
        playSound = try container.decodeIfPresent(Bool.self, forKey: .playSound) ?? true
        notificationSoundEnabled = try container.decodeIfPresent(Bool.self, forKey: .notificationSoundEnabled) ?? playSound
        notificationSoundEffect = try container.decodeIfPresent(RestSoundEffect.self, forKey: .notificationSoundEffect) ?? .stardewAchievement
        allowSkip = try container.decodeIfPresent(Bool.self, forKey: .allowSkip) ?? true
        allowEscToSkip = try container.decodeIfPresent(Bool.self, forKey: .allowEscToSkip) ?? true
        snoozeDuration = try container.decodeIfPresent(TimeInterval.self, forKey: .snoozeDuration) ?? 3 * 60
        recoveryNudgeThreshold = try container.decodeIfPresent(Int.self, forKey: .recoveryNudgeThreshold) ?? 2
        strictMode = try container.decodeIfPresent(Bool.self, forKey: .strictMode) ?? false
        pauseDuringScreenSharing = try container.decodeIfPresent(Bool.self, forKey: .pauseDuringScreenSharing) ?? false
        resetAfterWakeOrUnlock = try container.decodeIfPresent(Bool.self, forKey: .resetAfterWakeOrUnlock) ?? false
        restOverlayPrompt = try container.decodeIfPresent(RestOverlayPrompt.self, forKey: .restOverlayPrompt) ?? .lookFar
        restOverlaySubtitle = try container.decodeIfPresent(RestOverlaySubtitle.self, forKey: .restOverlaySubtitle) ?? .takeBreath
        restOverlayBackground = try container.decodeIfPresent(RestOverlayBackground.self, forKey: .restOverlayBackground) ?? .solid
        restOverlayFadeAnimation = try container.decodeIfPresent(Bool.self, forKey: .restOverlayFadeAnimation) ?? true
        restOverlayTranslucentBackground = try container.decodeIfPresent(Bool.self, forKey: .restOverlayTranslucentBackground) ?? false
        playRestStartSound = try container.decodeIfPresent(Bool.self, forKey: .playRestStartSound) ?? true
        playRestEndSound = try container.decodeIfPresent(Bool.self, forKey: .playRestEndSound) ?? true
        restStartSoundEffect = try container.decodeIfPresent(RestSoundEffect.self, forKey: .restStartSoundEffect) ?? (playRestStartSound ? .stardewNewRecord : .none)
        restEndSoundEffect = try container.decodeIfPresent(RestSoundEffect.self, forKey: .restEndSoundEffect) ?? (playRestEndSound ? .stardewHorseFlute : .none)
        idleThreshold = try container.decodeIfPresent(TimeInterval.self, forKey: .idleThreshold) ?? 5 * 60
    }
}

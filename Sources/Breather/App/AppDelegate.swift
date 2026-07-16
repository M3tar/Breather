import AppKit
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var scheduler: BreakScheduler!
    private var menuBarController: MenuBarController!
    private var restOverlayController: RestOverlayWindowController!
    private var cancellables: Set<AnyCancellable> = []

    let settingsStore = SettingsStore()
    let notificationService = NotificationService()
    let restSoundService = RestSoundService()
    var openSettingsHandler: (() -> Void)?
    private var isSettingsWindowOpenRequested = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMainMenu()
        installApplicationIcon()

        let idleMonitor = IdleMonitor()
        applyAppearance(settingsStore.settings.appearancePreference)

        scheduler = BreakScheduler(
            settingsStore: settingsStore,
            notificationService: notificationService,
            idleMonitor: idleMonitor
        )

        restOverlayController = RestOverlayWindowController(
            scheduler: scheduler,
            onSnooze: { [weak scheduler] in
                scheduler?.snoozeBreak()
            },
            onSkip: { [weak scheduler] in
                scheduler?.skipBreak()
            }
        )

        menuBarController = MenuBarController(
            scheduler: scheduler,
            onOpenSettings: { [weak self] in
                self?.openSettingsHandler?()
            },
            onQuit: {
                NSApp.terminate(nil)
            }
        )

        scheduler.onRestStarted = { [weak restOverlayController] in
            restOverlayController?.show()
        }
        scheduler.onRestEnded = { [weak restOverlayController] in
            restOverlayController?.hide()
        }
        scheduler.onRestBegan = { [weak self] in
            guard let settings = self?.settingsStore.settings,
                  settings.playRestStartSound else { return }
            self?.restSoundService.play(settings.restStartSoundEffect)
        }
        scheduler.onRestFinished = { [weak self] in
            guard let settings = self?.settingsStore.settings,
                  settings.playRestEndSound else { return }
            self?.restSoundService.play(settings.restEndSoundEffect)
        }

        settingsStore.$settings
            .map(\.appearancePreference)
            .removeDuplicates()
            .sink { [weak self] appearancePreference in
                self?.applyAppearance(appearancePreference)
            }
            .store(in: &cancellables)

        Task {
            _ = await notificationService.requestAuthorization()
        }
        scheduler.start()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applyCurrentRulesToCurrentCycle() {
        scheduler?.applyCurrentRulesToCurrentCycle()
    }

    func previewRestOverlay() {
        restOverlayController?.preview()
    }

    func requestSettingsWindowOpen() {
        isSettingsWindowOpenRequested = true
    }

    func settingsWindowDidAppear() {
        guard isSettingsWindowOpenRequested else {
            Task { @MainActor in
                NSApp.windows.first { $0.title == "Breather" }?.close()
            }
            return
        }

        isSettingsWindowOpenRequested = false
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func settingsWindowDidDisappear() {
        isSettingsWindowOpenRequested = false
        NSApp.setActivationPolicy(.accessory)
    }

    private func installApplicationIcon() {
        if let appIcon = NSImage(named: "AppIcon") {
            NSApp.applicationIconImage = appIcon
            return
        }

        guard let appIconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
              let appIcon = NSImage(contentsOf: appIconURL) else {
            return
        }

        NSApp.applicationIconImage = appIcon
    }

    private func applyAppearance(_ preference: AppearancePreference) {
        switch preference {
        case .system:
            NSApp.appearance = nil
        case .light:
            NSApp.appearance = NSAppearance(named: .aqua)
        case .dark:
            NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }

    private func installMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(
            withTitle: "退出 Breather",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "编辑")
        editMenu.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "重做", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        NSApp.mainMenu = mainMenu
    }
}

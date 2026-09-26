import SwiftUI

@main
struct BreatherApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        let _ = configureOpenSettingsHandler()

        settingsWindow
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("设置…") {
                    appDelegate.requestSettingsWindowOpen()
                    openWindow(id: "settings")
                }
                .keyboardShortcut(",", modifiers: .command)
            }
            CommandGroup(replacing: .newItem) { }
        }
    }

    private var settingsWindow: some Scene {
        Window("Breather", id: "settings") {
            SettingsView(
                settingsStore: appDelegate.settingsStore,
                updateMonitor: appDelegate.updateMonitor,
                notificationService: appDelegate.notificationService,
                restSoundService: appDelegate.restSoundService,
                restOverlayAvailability: appDelegate.restOverlayAvailability,
                onApplyRulesToCurrentCycle: {
                    appDelegate.applyCurrentRulesToCurrentCycle()
                },
                onPreviewRestOverlay: {
                    appDelegate.previewRestOverlay()
                }
            )
            .onAppear {
                appDelegate.settingsWindowDidAppear()
            }
            .onDisappear {
                appDelegate.settingsWindowDidDisappear()
            }
        }
        .windowResizability(.contentMinSize)
        .defaultPosition(.center)
        .defaultSize(width: 960, height: 680)
        .defaultLaunchBehavior(.suppressed)
    }

    private func configureOpenSettingsHandler() {
        appDelegate.openSettingsHandler = {
            appDelegate.requestSettingsWindowOpen()
            openWindow(id: "settings")
        }
    }
}

import AppKit
import Combine
import SwiftUI

@MainActor
final class MenuBarController: NSObject {
    private let statusItem: NSStatusItem
    private let scheduler: BreakScheduler
    private let onOpenSettings: () -> Void
    private let onQuit: () -> Void
    private var cancellables: Set<AnyCancellable> = []
    private var panel: NSPanel?
    private var eventMonitor: Any?
    private var localEventMonitor: Any?
    private let panelSize = NSSize(width: 320, height: 430)

    init(
        scheduler: BreakScheduler,
        onOpenSettings: @escaping () -> Void,
        onQuit: @escaping () -> Void
    ) {
        self.scheduler = scheduler
        self.onOpenSettings = onOpenSettings
        self.onQuit = onQuit
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        super.init()

        statusItem.autosaveName = "BreatherStatusItem.v2"

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(togglePopover)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.imagePosition = .imageLeading
            button.imageScaling = .scaleProportionallyDown
            updateStatusItem()
        }

        scheduler.$remainingSeconds
            .combineLatest(scheduler.$state)
            .sink { [weak self] _ in
                self?.updateStatusItem()
            }
            .store(in: &cancellables)

        scheduler.settingsStore.$settings
            .sink { [weak self] _ in
                self?.updateStatusItem()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)
            .sink { [weak self] _ in
                guard self?.panel?.isVisible != true else { return }
                self?.closePopover()
            }
            .store(in: &cancellables)
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }

        if panel?.isVisible == true {
            closePopover()
        } else {
            NSApp.activate(ignoringOtherApps: true)
            showPopover(relativeTo: button)
            installEventMonitor()
        }
    }

    private func updateStatusItem() {
        guard let button = statusItem.button else { return }

        button.title = scheduler.menuBarTitle
        button.image = menuBarImage()
        button.imagePosition = scheduler.menuBarTitle.isEmpty ? .imageOnly : .imageLeading
    }

    private func showPopover(relativeTo button: NSStatusBarButton) {
        let panel = panel ?? makePanel()
        self.panel = panel
        panel.contentViewController = NSHostingController(
            rootView: MenuBarPanelView(
                scheduler: scheduler,
                onOpenSettings: { [weak self] in
                    self?.openSettings()
                },
                onQuit: { [weak self] in
                    self?.quit()
                }
            )
        )

        position(panel, relativeTo: button)
        panel.orderFrontRegardless()
    }

    private func makePanel() -> NSPanel {
        let panel = MenuBarPopoverPanel(
            contentRect: NSRect(origin: .zero, size: panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        return panel
    }

    private func position(_ panel: NSPanel, relativeTo button: NSStatusBarButton) {
        guard
            let window = button.window,
            let screen = window.screen
        else { return }

        let buttonRect = window.convertToScreen(button.convert(button.bounds, to: nil))
        let visibleFrame = screen.visibleFrame
        let x = min(
            max(buttonRect.midX - panelSize.width / 2, visibleFrame.minX + 8),
            visibleFrame.maxX - panelSize.width - 8
        )
        let y = buttonRect.minY - panelSize.height - 4

        panel.setFrame(
            NSRect(
                x: x,
                y: max(y, visibleFrame.minY + 8),
                width: panelSize.width,
                height: panelSize.height
            ),
            display: true
        )
    }

    private func menuBarImage() -> NSImage? {
        let settings = scheduler.settingsStore.settings
        guard settings.showMenuBarIcon else { return nil }
        guard let image = NSImage(named: settings.menuBarIcon.assetName) else { return nil }

        let statusImage = image.copy() as? NSImage ?? image
        statusImage.size = NSSize(width: 17, height: 17)
        statusImage.isTemplate = true
        return statusImage
    }

    private func openSettings() {
        closePopover()
        onOpenSettings()
    }

    private func quit() {
        closePopover()
        onQuit()
    }

    private func closePopover() {
        panel?.orderOut(nil)
        eventMonitor.map(NSEvent.removeMonitor)
        eventMonitor = nil
        localEventMonitor.map(NSEvent.removeMonitor)
        localEventMonitor = nil
    }

    private func installEventMonitor() {
        eventMonitor.map(NSEvent.removeMonitor)
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in
                self?.closePopover()
            }
        }

        localEventMonitor.map(NSEvent.removeMonitor)
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            if let panel = self?.panel, event.window !== panel {
                Task { @MainActor in
                    self?.closePopover()
                }
            }
            return event
        }
    }
}

private final class MenuBarPopoverPanel: NSPanel {
    override var canBecomeKey: Bool {
        false
    }
}

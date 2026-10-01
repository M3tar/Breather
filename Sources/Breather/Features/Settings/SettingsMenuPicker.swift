import AppKit
import SwiftUI

struct SettingsMenuOption<Value: Hashable> {
    let value: Value
    let title: String
    var imageName: String? = nil
    var separatorBefore = false
}

struct SettingsMenuPicker<Value: Hashable>: View {
    let title: String
    @Binding var selection: Value
    let options: [SettingsMenuOption<Value>]

    init(_ title: String, selection: Binding<Value>, options: [SettingsMenuOption<Value>]) {
        self.title = title
        _selection = selection
        self.options = options
    }

    var body: some View {
        let selected = options.first { $0.value == selection }
        let sizing = SettingsMenuSizing(option: selected)
        NativeSettingsMenuPicker(title, selection: $selection, options: options, selectedWidth: sizing.width)
            .frame(width: sizing.width)
            .transaction { transaction in
                transaction.animation = nil
                transaction.disablesAnimations = true
            }
    }
}

/// Keep the native popup and its selection alive when only translated titles change.
/// SwiftUI owns the value; AppKit owns menu tracking and keyboard/accessibility behavior.
private struct NativeSettingsMenuPicker<Value: Hashable>: NSViewRepresentable {
    let title: String
    @Binding var selection: Value
    let options: [SettingsMenuOption<Value>]
    let selectedWidth: CGFloat
    @Environment(\.isEnabled) private var isEnabled
    @ObservedObject private var localizationRefresh = LocalizationRefresh.shared

    init(_ title: String, selection: Binding<Value>, options: [SettingsMenuOption<Value>], selectedWidth: CGFloat) {
        self.title = title
        _selection = selection
        self.options = options
        self.selectedWidth = selectedWidth
    }

    func makeNSView(context: Context) -> NSPopUpButton {
        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        popup.bezelStyle = .rounded
        popup.controlSize = .regular
        popup.font = .systemFont(ofSize: NSFont.systemFontSize)
        popup.cell?.lineBreakMode = .byTruncatingTail
        popup.target = context.coordinator
        popup.action = #selector(Coordinator.valueChanged(_:))
        update(popup, coordinator: context.coordinator)
        return popup
    }

    func updateNSView(_ popup: NSPopUpButton, context: Context) {
        let _ = localizationRefresh.revision
        update(popup, coordinator: context.coordinator)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSPopUpButton, context: Context) -> CGSize? {
        NSSize(width: selectedWidth, height: nsView.intrinsicContentSize.height)
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    private func update(_ popup: NSPopUpButton, coordinator: Coordinator) {
        coordinator.parent = self
        let cell = popup.cell as? NSPopUpButtonCell
        cell?.usesItemFromMenu = false
        let values = options.map(\.value)
        let separators = options.map(\.separatorBefore)
        if coordinator.values != values || coordinator.separators != separators {
            popup.removeAllItems()
            coordinator.imageNames.removeAll()
            coordinator.items = options.map { option in
                if option.separatorBefore { popup.menu?.addItem(.separator()) }
                let item = NSMenuItem(title: option.title, action: nil, keyEquivalent: "")
                popup.menu?.addItem(item)
                return item
            }
            coordinator.values = values
            coordinator.separators = separators
        }
        for (index, option) in options.enumerated() {
            let item = coordinator.items[index]
            if item.title != option.title { item.title = option.title }
            if coordinator.imageNames[index] != option.imageName {
                item.image = settingsMenuImage(named: option.imageName)
                coordinator.imageNames[index] = option.imageName
            }
        }
        if let index = values.firstIndex(of: selection) { popup.select(coordinator.items[index]) }
        popup.synchronizeTitleAndSelectedItem()
        if let selected = options.first(where: { $0.value == selection }) {
            // A separate display item keeps native menu tracking from inserting a
            // full sentence into the old frame before SwiftUI updates its width.
            coordinator.displayItem.title = selected.title
            coordinator.displayItem.image = popup.selectedItem?.image
            cell?.menuItem = coordinator.displayItem
        }
        popup.isEnabled = isEnabled
        popup.setAccessibilityLabel(title)
        // AppKit owns hover help for the native control. Keep its registration
        // stable across unrelated SwiftUI updates while the selected text is unchanged.
        let fullTitle = popup.titleOfSelectedItem
        if popup.toolTip != fullTitle { popup.toolTip = fullTitle }
        popup.setAccessibilityHelp(fullTitle)
        popup.setAccessibilityValue(popup.titleOfSelectedItem)
        popup.invalidateIntrinsicContentSize()
    }

    @MainActor
    final class Coordinator: NSObject {
        var parent: NativeSettingsMenuPicker
        var values: [Value] = []
        var separators: [Bool] = []
        var items: [NSMenuItem] = []
        var imageNames: [Int: String] = [:]
        let displayItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")

        init(parent: NativeSettingsMenuPicker) { self.parent = parent }

        @objc func valueChanged(_ sender: NSPopUpButton) {
            guard let selected = sender.selectedItem,
                  let index = items.firstIndex(where: { $0 === selected }) else { return }
            parent.selection = values[index]
        }
    }
}

/// Measure the closed label with the same native metrics as the visible popup.
@MainActor
private struct SettingsMenuSizing {
    let width: CGFloat

    init<Value>(option: SettingsMenuOption<Value>?) {
        let sizingCell = NSPopUpButtonCell(textCell: "", pullsDown: false)
        sizingCell.addItem(withTitle: option?.title ?? "")
        sizingCell.font = .systemFont(ofSize: NSFont.systemFontSize)
        sizingCell.controlSize = .regular
        sizingCell.bezelStyle = .rounded
        sizingCell.item(at: 0)?.image = settingsMenuImage(named: option?.imageName)
        sizingCell.selectItem(at: 0)
        sizingCell.synchronizeTitleAndSelectedItem()
        let naturalWidth = ceil(sizingCell.cellSize.width)
        width = min(360, max(96, naturalWidth))
    }
}

@MainActor
private func settingsMenuImage(named name: String?) -> NSImage? {
    guard let name, let image = NSImage(named: name)?.copy() as? NSImage else { return nil }
    image.size = NSSize(width: 18, height: 18)
    image.isTemplate = true
    return image
}

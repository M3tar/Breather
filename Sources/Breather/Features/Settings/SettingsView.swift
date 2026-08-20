import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settingsStore: SettingsStore
    let notificationService: any NotificationSettingsServicing
    let restSoundService: RestSoundService
    let onApplyRulesToCurrentCycle: () -> Void
    let onPreviewRestOverlay: () -> Void

    @State private var selectedSection: SettingsSectionID = .general
    @State private var isWaitingToApplyRules = false
    @State private var ruleApplyTask: Task<Void, Never>?

    var body: some View {
        NavigationSplitView {
            SettingsSidebar(
                selectedSection: $selectedSection,
                onQuit: { NSApp.terminate(nil) }
            )
            .navigationSplitViewColumnWidth(min: 150, ideal: 170, max: 200)
        } detail: {
            selectedScreen
        }
        .frame(
            minWidth: 760,
            idealWidth: 960,
            minHeight: 560,
            idealHeight: 680
        )
        .onChange(of: settingsStore.settings) { oldSettings, newSettings in
            guard oldSettings.ruleChangeEffect != newSettings.ruleChangeEffect else {
                return
            }

            if newSettings.ruleChangeEffect == .immediate,
               settingsStore.hasPendingRuleChanges {
                scheduleCurrentCycleApply()
            } else {
                cancelScheduledRuleApply()
            }
        }
        .onChange(of: settingsStore.rules) { _, _ in
            if settingsStore.settings.ruleChangeEffect == .immediate {
                scheduleCurrentCycleApply()
            }
        }
        .onDisappear {
            cancelScheduledRuleApply()
        }
    }

    @ViewBuilder
    private var selectedScreen: some View {
        switch selectedSection {
        case .general:
            GeneralSettingsScreen(
                settingsStore: settingsStore,
                notificationService: notificationService,
                restSoundService: restSoundService
            )
        case .schedule:
            ScheduleSettingsScreen(
                settingsStore: settingsStore,
                isWaitingToApplyRules: isWaitingToApplyRules,
                onApplyRulesToCurrentCycle: applyRulesToCurrentCycle
            )
        case .restOverlay:
            RestOverlaySettingsScreen(
                settingsStore: settingsStore,
                restSoundService: restSoundService,
                onPreviewRestOverlay: onPreviewRestOverlay
            )
        }
    }

    private func scheduleCurrentCycleApply() {
        isWaitingToApplyRules = true
        ruleApplyTask?.cancel()
        ruleApplyTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(900))
            guard !Task.isCancelled else { return }
            applyRulesToCurrentCycle()
        }
    }

    private func applyRulesToCurrentCycle() {
        cancelScheduledRuleApply()
        onApplyRulesToCurrentCycle()
    }

    private func cancelScheduledRuleApply() {
        ruleApplyTask?.cancel()
        ruleApplyTask = nil
        isWaitingToApplyRules = false
    }

}

struct SettingsSidebar: View {
    @Binding var selectedSection: SettingsSectionID
    let onQuit: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $selectedSection) {
                ForEach(SettingsSectionID.allCases) { section in
                    Label(section.title, systemImage: section.systemImage)
                        .tag(section)
                }
            }
            .listStyle(.sidebar)
            .accessibilityLabel("设置分类")

            Divider()

            HStack {
                Button(action: onQuit) {
                    Image(systemName: "power")
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .frame(width: 28, height: 28)
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
                .help("退出")
                .accessibilityLabel("退出")

                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
    }
}

enum SettingsSectionID: String, CaseIterable, Identifiable, Hashable {
    case general
    case schedule
    case restOverlay

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "通用"
        case .schedule: "计划"
        case .restOverlay: "休息界面"
        }
    }

    var systemImage: String {
        switch self {
        case .general: "gearshape"
        case .schedule: "timer"
        case .restOverlay: "rectangle.inset.filled"
        }
    }
}

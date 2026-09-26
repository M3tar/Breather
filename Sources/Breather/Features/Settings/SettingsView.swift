import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settingsStore: SettingsStore
    @ObservedObject var updateMonitor: UpdateMonitor
    let notificationService: any NotificationSettingsServicing
    let restSoundService: RestSoundService
    var restOverlayAvailability = RestOverlayAvailability()
    let onApplyRulesToCurrentCycle: () -> Void
    let onPreviewRestOverlay: () -> Void

    @State private var selectedSection: SettingsSectionID = .general
    @State private var isWaitingToApplyRules = false
    @State private var ruleApplyTask: Task<Void, Never>?

    var body: some View {
        NavigationSplitView {
            SettingsSidebar(
                selectedSection: $selectedSection,
                hasAvailableUpdate: updateMonitor.availableUpdate != nil,
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
                availability: restOverlayAvailability,
                onPreviewRestOverlay: onPreviewRestOverlay
            )
        case .about:
            AboutSettingsScreen(updateMonitor: updateMonitor)
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
    let hasAvailableUpdate: Bool
    let onQuit: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $selectedSection) {
                ForEach(SettingsSectionID.allCases) { section in
                    HStack(spacing: 8) {
                        Label(section.title, systemImage: section.systemImage)
                        if section == .about && hasAvailableUpdate {
                            Spacer(minLength: 2)
                            Text("更新")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(selectedSection == .about ? .white : .blue)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    selectedSection == .about ? Color.white.opacity(0.18) : Color.blue.opacity(0.1),
                                    in: Capsule()
                                )
                                .accessibilityHidden(true)
                        }
                    }
                    .accessibilityLabel(section == .about && hasAvailableUpdate ? "关于，有新版本可用" : section.title)
                    .tag(section)
                }
            }
            .listStyle(.sidebar)
            .accessibilityLabel("设置分类")

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
            .frame(height: SettingsFooterMetrics.height)
        }
    }
}

enum SettingsSectionID: String, CaseIterable, Identifiable, Hashable {
    case general
    case schedule
    case restOverlay
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "通用"
        case .schedule: "计划"
        case .restOverlay: "休息界面"
        case .about: "关于"
        }
    }

    var systemImage: String {
        switch self {
        case .general: "gearshape"
        case .schedule: "timer"
        case .restOverlay: "rectangle.inset.filled"
        case .about: "info.circle"
        }
    }
}

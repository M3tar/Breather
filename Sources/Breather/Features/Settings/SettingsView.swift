import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settingsStore: SettingsStore
    @ObservedObject private var localizationRefresh = LocalizationRefresh.shared
    @ObservedObject var updateMonitor: UpdateMonitor
    var diagnostics: DiagnosticsController? = nil
    var installedReleaseNotice: InstalledReleaseNotice? = nil
    let notificationService: any NotificationSettingsServicing
    let restSoundService: RestSoundService
    var restOverlayAvailability = RestOverlayAvailability()
    let onApplyRulesToCurrentCycle: () -> Void
    let onPreviewRestOverlay: () -> Void

    @State private var selectedSection: SettingsSectionID = .schedule
    @StateObject private var ruleApplication = SettingsRuleApplication()
    @StateObject private var resetTransition = SettingsResetTransition()
    @State private var focusGeneralNotifications = false

    var body: some View {
        let _ = localizationRefresh.revision
        NavigationSplitView {
            SettingsSidebar(
                selectedSection: $selectedSection,
                hasAvailableUpdate: updateMonitor.availableUpdate != nil,
                installedReleaseNotice: installedReleaseNotice,
                onQuit: { NSApp.terminate(nil) }
            )
            .navigationSplitViewColumnWidth(min: 150, ideal: 170, max: 200)
        } detail: {
            switch selectedSection {
            case .schedule, .menuBar, .restOverlay:
                SettingsResetTransitionContent(transition: resetTransition, store: settingsStore) {
                    selectedScreen
                }
            case .general, .about, .history:
                selectedScreen
            }
        }
        .frame(
            minWidth: SettingsWindowMetrics.minimumSize.width,
            idealWidth: SettingsWindowMetrics.defaultSize.width,
            minHeight: SettingsWindowMetrics.minimumSize.height,
            idealHeight: SettingsWindowMetrics.defaultSize.height
        )
        .background {
            SettingsWindowInitialFocus()
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
            SettingsFeedbackWindowObserver(onLeave: {
                ruleApplication.finishPending(store: settingsStore, apply: { onApplyRulesToCurrentCycle() })
            }, onReturn: scheduleCurrentCycleApply)
                .frame(width: 0, height: 0)
        }
        .onChange(of: settingsStore.settings.ruleChangeEffect) { _, _ in
            scheduleCurrentCycleApply()
        }
        .onChange(of: settingsStore.savedCycleConfiguration) { _, _ in
            scheduleCurrentCycleApply()
        }
        .onChange(of: settingsStore.currentCycleConfiguration) { _, _ in
            if !settingsStore.hasPendingRuleChanges { cancelScheduledRuleApply() }
        }
        .onAppear { scheduleCurrentCycleApply() }
        .onDisappear {
            ruleApplication.finishPending(store: settingsStore, apply: { onApplyRulesToCurrentCycle() })
            resetTransition.cancel("page-disappeared")
        }
        .onChange(of: selectedSection) { _, section in
            resetTransition.cancel("section-changed")
            if section != .general {
                focusGeneralNotifications = false
            }
        }
    }

    @ViewBuilder
    private var selectedScreen: some View {
        switch selectedSection {
        case .general:
            GeneralSettingsScreen(
                settingsStore: settingsStore,
                notificationService: notificationService,
                restSoundService: restSoundService,
                focusNotifications: focusGeneralNotifications
            )
        case .schedule:
            ScheduleSettingsScreen(
                settingsStore: settingsStore,
                isWaitingToApplyRules: ruleApplication.isWaiting,
                onApplyRulesToCurrentCycle: applyRulesToCurrentCycle,
                notificationService: notificationService,
                onOpenNotificationSettings: {
                    focusGeneralNotifications = true
                    selectedSection = .general
                },
                onRestoreDefaults: {
                    cancelScheduledRuleApply()
                    settingsStore.restoreDefaults(for: .schedule)
                }
            )
        case .menuBar:
            MenuBarSettingsScreen(settingsStore: settingsStore)
        case .restOverlay:
            RestOverlaySettingsScreen(
                settingsStore: settingsStore,
                restSoundService: restSoundService,
                availability: restOverlayAvailability,
                onPreviewRestOverlay: onPreviewRestOverlay
            )
        case .history:
            RestHistoryScreen()
        case .about:
            AboutSettingsScreen(updateMonitor: updateMonitor, diagnostics: diagnostics)
        }
    }

    private func scheduleCurrentCycleApply() {
        ruleApplication.update(store: settingsStore, apply: { onApplyRulesToCurrentCycle() })
    }

    private func applyRulesToCurrentCycle() {
        cancelScheduledRuleApply()
        onApplyRulesToCurrentCycle()
    }

    private func cancelScheduledRuleApply() {
        ruleApplication.cancel()
    }

}

struct SettingsSidebar: View {
    @Binding var selectedSection: SettingsSectionID
    @ObservedObject private var localizationRefresh = LocalizationRefresh.shared
    let hasAvailableUpdate: Bool
    var installedReleaseNotice: InstalledReleaseNotice? = nil
    let onQuit: () -> Void

    var body: some View {
        let _ = localizationRefresh.revision
        VStack(spacing: 0) {
            List(selection: $selectedSection) {
                ForEach(SettingsSectionID.allCases) { section in
                    HStack(spacing: 8) {
                        Label(section.title, systemImage: section.systemImage)
                        if section == .about && hasAvailableUpdate {
                            Spacer(minLength: 2)
                            Text(L.tr("更新"))
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
                    .accessibilityLabel(section == .about && hasAvailableUpdate ? L.tr("关于，有新版本可用") : section.title)
                    .tag(section)
                }
            }
            .listStyle(.sidebar)
            .accessibilityLabel(L.tr("设置分类"))

            if let installedReleaseNotice, let notes = installedReleaseNotice.pendingNotes {
                SettingsReleaseNotesCard(notes: notes, onDismiss: installedReleaseNotice.dismiss)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 4)
            }

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
                .help(L.tr("退出"))
                .accessibilityLabel(L.tr("退出"))

                Spacer()
            }
            .padding(.horizontal, 8)
            .frame(height: SettingsFooterMetrics.height)
        }
    }
}

enum SettingsSectionID: String, CaseIterable, Identifiable, Hashable {
    case schedule
    case menuBar
    case restOverlay
    case history
    case general
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: L.tr("通用")
        case .schedule: L.tr("计划")
        case .menuBar: L.tr("菜单栏")
        case .restOverlay: L.tr("休息界面")
        case .history: L.tr("休息记录")
        case .about: L.tr("关于")
        }
    }

    var systemImage: String {
        switch self {
        case .general: "gearshape"
        case .schedule: "timer"
        case .menuBar: "menubar.rectangle"
        case .restOverlay: "rectangle.inset.filled"
        case .history: "calendar"
        case .about: "info.circle"
        }
    }
}

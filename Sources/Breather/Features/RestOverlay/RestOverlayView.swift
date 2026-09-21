import SwiftUI

struct RestOverlayView: View {
    @ObservedObject var settingsStore: SettingsStore
    @ObservedObject var session: RestOverlaySession
    let onSnooze: () -> Void
    let onSkip: () -> Void

    var body: some View {
        let settings = settingsStore.settings
        RestOverlayShell(
            session: session,
            actions: .rest(snoozeDuration: settings.snoozeDuration,
                           canSnooze: !settings.strictMode,
                           canSkip: settings.allowSkip && !settings.strictMode,
                           onSnooze: onSnooze, onSkip: onSkip)
        )
    }
}

struct RestOverlayPreviewView: View {
    @ObservedObject var session: RestOverlaySession
    let onClose: () -> Void

    var body: some View {
        RestOverlayShell(session: session,
                         actions: .preview(onClose: onClose))
    }
}

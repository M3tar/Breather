import SwiftUI

struct RestThemePicker: View {
    @Binding var settings: AppSettings
    let duration: Int
    let isResting: Bool
    @State private var changedDuringRest = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("休息主题").font(.headline)
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 12) { options }
                VStack(spacing: 12) { options }
            }
            if isResting && changedDuringRest {
                Text("主题将在下次休息时使用")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onChange(of: settings.restOverlayContentMode) { _, _ in
            changedDuringRest = isResting
        }
        .onChange(of: isResting) { _, _ in changedDuringRest = false }
    }

    private var options: some View {
        ForEach(RestOverlayContentMode.allCases) { mode in
            RestContentOption(mode: mode,
                              isSelected: settings.restOverlayContentMode == mode,
                              thumbnail: RestThemeThumbnailConfiguration(mode: mode, settings: settings,
                                                                        duration: duration)) {
                settings.restOverlayContentMode = mode
            }
            .frame(minWidth: 220)
        }
    }
}

/// A value-only thumbnail: no session, random sampling, timer or scheduler writes.
struct RestThemeThumbnailConfiguration: Equatable {
    let mode: RestOverlayContentMode
    let background: RestOverlayBackground
    let translucent: Bool
    let formattedTime: String
    let prompt: String?

    init(mode: RestOverlayContentMode, settings: AppSettings, duration: Int) {
        self.mode = mode
        background = mode == .classic ? settings.restOverlayBackground : .solid
        translucent = mode == .classic && settings.restOverlayTranslucentBackground
        let seconds = max(0, duration)
        formattedTime = String(format: "%02d:%02d", seconds / 60, seconds % 60)
        switch settings.restOverlayPrompt {
        case .random: prompt = RestOverlayPrompt.lookFar.title
        case .none: prompt = nil
        default: prompt = settings.restOverlayPrompt.title
        }
    }
}

struct RestContentOption: View {
    let mode: RestOverlayContentMode
    let isSelected: Bool
    let thumbnail: RestThemeThumbnailConfiguration
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 10) {
                RestThemeThumbnail(configuration: thumbnail)
                HStack {
                    Text(mode.title).font(.body.weight(.medium))
                    Spacer(minLength: 4)
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                }
                Text(mode.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(RestThemeOptionButtonStyle(isSelected: isSelected))
        .accessibilityLabel(mode.title)
        .accessibilityHint(mode.summary)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

struct RestThemeThumbnail: View {
    @Environment(\.colorScheme) private var colorScheme
    let configuration: RestThemeThumbnailConfiguration
    private static let scene = DinosaurSceneModel(seed: 0).frame(elapsed: 0, animated: false)

    var body: some View {
        let style = RestOverlayStyle(background: configuration.background, colorScheme: colorScheme)
        ZStack {
            if configuration.mode == .dinosaur {
                DinosaurPalette(dark: colorScheme == .dark).background
                DinosaurLane(frame: Self.scene, palette: DinosaurPalette(dark: colorScheme == .dark))
                    .frame(height: 44)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 4)
                    .frame(maxHeight: .infinity, alignment: .bottom)
            } else {
                RestOverlayBackgroundView(background: configuration.background, style: style,
                                          translucent: configuration.translucent)
            }
            VStack(spacing: 4) {
                Text(configuration.formattedTime)
                    .font(.system(size: 26, weight: .regular, design: .rounded))
                    .monospacedDigit()
                if let prompt = configuration.prompt {
                    Text(prompt).font(.system(size: 10, weight: .medium))
                }
            }
            .foregroundStyle(style.primaryText)
            .shadow(color: style.textShadow, radius: 2, y: 1)
            .offset(y: configuration.mode == .dinosaur ? -18 : 0)
        }
        // Shared thumbnail viewport, not a fixed card height; descriptions can wrap.
        .frame(height: 112)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .accessibilityHidden(true)
    }
}

private struct RestThemeOptionButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        RestThemeOptionButtonBody(configuration: configuration, isSelected: isSelected)
    }
}

private struct RestThemeOptionButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let isSelected: Bool
    @State private var hovering = false

    var body: some View {
        configuration.label
            .padding(10)
            .background(Color.primary.opacity(configuration.isPressed ? 0.08 : hovering ? 0.04 : 0))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(isSelected ? Color.accentColor : Color.secondary.opacity(0.2),
                                  lineWidth: isSelected ? 1.5 : 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 10))
            .onHover { hovering = $0 }
    }
}

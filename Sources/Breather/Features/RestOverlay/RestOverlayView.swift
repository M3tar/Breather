import AppKit
import SwiftUI

@MainActor
final class RestOverlayDismissalState: ObservableObject {
    @Published var isDismissing = false
    @Published var frozenTime: String?
}

struct RestOverlayView: View {
    @ObservedObject var scheduler: BreakScheduler
    @ObservedObject var dismissalState: RestOverlayDismissalState
    let copy: RestOverlayCopy
    let onSnooze: () -> Void
    let onSkip: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let settings = scheduler.settingsStore.settings
        let style = RestOverlayStyle(background: settings.restOverlayBackground, colorScheme: colorScheme)

        ZStack {
            RestOverlayBackgroundView(
                background: settings.restOverlayBackground,
                style: style,
                translucent: settings.restOverlayTranslucentBackground
            )
            .sunDismissalEffect(
                isActive: settings.restOverlayBackground == .sun && dismissalState.isDismissing
            )

            VStack(spacing: 24) {
                Text(dismissalState.frozenTime ?? scheduler.formattedTime)
                    .font(.system(size: 96, weight: .regular, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(style.primaryText)
                    .shadow(color: style.textShadow, radius: 8, y: 2)

                if let prompt = copy.prompt {
                    Text(prompt)
                        .font(.system(size: 34, weight: .medium))
                        .foregroundStyle(style.primaryText.opacity(0.94))
                        .shadow(color: style.textShadow, radius: 6, y: 2)
                }

                if let subtitle = copy.subtitle {
                    Text(subtitle)
                        .font(.system(size: 18, weight: .regular))
                        .foregroundStyle(style.primaryText.opacity(0.72))
                        .shadow(color: style.textShadow, radius: 5, y: 1)
                }

                if !settings.strictMode {
                    HStack(spacing: 24) {
                        Button("延后 \(Self.formattedDuration(settings.snoozeDuration))") {
                            onSnooze()
                        }
                        .buttonStyle(RestOverlayActionButtonStyle(style: style))

                        if settings.allowSkip {
                            Button("跳过") {
                                onSkip()
                            }
                            .buttonStyle(RestOverlayActionButtonStyle(style: style))
                        }
                    }
                    .padding(.top, 10)
                }
            }
            .padding(48)
            .opacity(settings.restOverlayBackground == .sun && dismissalState.isDismissing ? 0 : 1)
            .animation(.easeOut(duration: 0.08), value: dismissalState.isDismissing)
        }
    }

    private static func formattedDuration(_ duration: TimeInterval) -> String {
        if duration >= 60 {
            return "\(max(1, Int(duration / 60))) 分钟"
        }
        return "\(max(1, Int(duration))) 秒"
    }
}

struct RestOverlayPreviewView: View {
    @ObservedObject var dismissalState: RestOverlayDismissalState
    let copy: RestOverlayCopy
    let background: RestOverlayBackground
    let translucentBackground: Bool
    let onClose: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let style = RestOverlayStyle(background: background, colorScheme: colorScheme)

        ZStack {
            RestOverlayBackgroundView(
                background: background,
                style: style,
                translucent: translucentBackground
            )
            .sunDismissalEffect(isActive: background == .sun && dismissalState.isDismissing)

            VStack(spacing: 24) {
                Text("00:30")
                    .font(.system(size: 96, weight: .regular, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(style.primaryText)
                    .shadow(color: style.textShadow, radius: 8, y: 2)

                if let prompt = copy.prompt {
                    Text(prompt)
                        .font(.system(size: 34, weight: .medium))
                        .foregroundStyle(style.primaryText.opacity(0.94))
                        .shadow(color: style.textShadow, radius: 6, y: 2)
                }

                if let subtitle = copy.subtitle {
                    Text(subtitle)
                        .font(.system(size: 18, weight: .regular))
                        .foregroundStyle(style.primaryText.opacity(0.72))
                        .shadow(color: style.textShadow, radius: 5, y: 1)
                }

                Button("关闭预览") {
                    onClose()
                }
                .buttonStyle(RestOverlayActionButtonStyle(style: style))
                .padding(.top, 10)
            }
            .padding(48)
            .opacity(background == .sun && dismissalState.isDismissing ? 0 : 1)
            .animation(.easeOut(duration: 0.08), value: dismissalState.isDismissing)
        }
    }

}

struct RestOverlayCopy {
    let prompt: String?
    let subtitle: String?

    init(settings: AppSettings) {
        prompt = settings.restOverlayPrompt.resolvedTitle
        subtitle = settings.restOverlaySubtitle.resolvedTitle
    }

    init(settings: AppSettings, showsRecoveryNudge: Bool) {
        prompt = settings.restOverlayPrompt.resolvedTitle
        subtitle = showsRecoveryNudge
            ? "最近几次休息都被延后或跳过了，这次先把短休完成吧。"
            : settings.restOverlaySubtitle.resolvedTitle
    }
}

private struct RestOverlayBackgroundView: View {
    let background: RestOverlayBackground
    let style: RestOverlayStyle
    let translucent: Bool

    var body: some View {
        Group {
            if let imageName = background.imageName,
               let image = NSImage(named: imageName) ?? bundledImage(named: imageName) {
                GeometryReader { proxy in
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                        .overlay(style.imageOverlay)
                }
            } else {
                style.solidBackground(translucent: translucent)
            }
        }
        .ignoresSafeArea()
    }

    private func bundledImage(named name: String) -> NSImage? {
        let bundle: Bundle
        #if SWIFT_PACKAGE
        bundle = Bundle.module
        #else
        bundle = Bundle.main
        #endif

        guard let url = bundle.url(
            forResource: name,
            withExtension: "png",
            subdirectory: "Backgrounds"
        ) ?? bundle.url(forResource: name, withExtension: "png") else {
            return nil
        }

        return NSImage(contentsOf: url)
    }
}

private extension View {
    func sunDismissalEffect(isActive: Bool) -> some View {
        self
            .opacity(isActive ? 0.34 : 1)
            .animation(.easeInOut(duration: 0.22), value: isActive)
    }
}

private struct RestOverlayActionButtonStyle: ButtonStyle {
    let style: RestOverlayStyle

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(style.buttonText)
            .lineLimit(1)
            .padding(.horizontal, 16)
            .frame(height: 32)
            .background(
                Capsule()
                    .fill(configuration.isPressed ? style.buttonPressedBackground : style.buttonBackground)
                    .shadow(color: style.buttonShadow, radius: 8, y: 2)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct RestOverlayStyle {
    let background: RestOverlayBackground
    let colorScheme: ColorScheme

    func solidBackground(translucent: Bool) -> Color {
        let base = colorScheme == .dark
            ? Color(red: 0.075, green: 0.082, blue: 0.09)
            : Color(red: 0.88, green: 0.89, blue: 0.90)

        return translucent ? base.opacity(colorScheme == .dark ? 0.88 : 0.90) : base
    }

    var primaryText: Color {
        switch background {
        case .solid:
            colorScheme == .dark ? .white : Color(red: 0.15, green: 0.16, blue: 0.17)
        case .moon:
            .white
        case .sun:
            Color(red: 0.18, green: 0.17, blue: 0.15)
        }
    }

    var buttonBackground: Color {
        switch background {
        case .solid:
            colorScheme == .dark
                ? Color.white.opacity(0.18)
                : Color.white.opacity(0.72)
        case .moon:
            Color.white.opacity(0.24)
        case .sun:
            Color(red: 0.96, green: 0.96, blue: 0.93).opacity(0.94)
        }
    }

    var buttonPressedBackground: Color {
        switch background {
        case .solid:
            colorScheme == .dark
                ? Color.white.opacity(0.24)
                : Color.white.opacity(0.86)
        case .moon:
            Color.white.opacity(0.32)
        case .sun:
            Color(red: 0.90, green: 0.90, blue: 0.87).opacity(0.96)
        }
    }

    var buttonText: Color {
        switch background {
        case .solid:
            colorScheme == .dark ? .white.opacity(0.94) : Color(red: 0.16, green: 0.17, blue: 0.18)
        case .moon:
            Color.white.opacity(0.94)
        case .sun:
            Color(red: 0.18, green: 0.17, blue: 0.15)
        }
    }

    var buttonShadow: Color {
        switch background {
        case .solid:
            colorScheme == .dark ? Color.black.opacity(0.18) : Color.black.opacity(0.10)
        case .moon:
            Color.black.opacity(0.34)
        case .sun:
            Color.black.opacity(0.08)
        }
    }

    var imageOverlay: Color {
        switch background {
        case .solid:
            .clear
        case .moon:
            Color.black.opacity(0.18)
        case .sun:
            Color.white.opacity(0.08)
        }
    }

    var textShadow: Color {
        switch background {
        case .solid:
            .clear
        case .moon:
            Color.black.opacity(0.52)
        case .sun:
            Color.white.opacity(0.34)
        }
    }
}

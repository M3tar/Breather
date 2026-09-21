import SwiftUI

enum RestOverlayActions {
    case rest(snoozeDuration: TimeInterval, canSnooze: Bool, canSkip: Bool,
              onSnooze: () -> Void, onSkip: () -> Void)
    case preview(onClose: () -> Void)
}

/// Shared presentation only. Scheduling, sound, persistence and windows stay outside.
struct RestOverlayShell: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var session: RestOverlaySession
    let actions: RestOverlayActions
    @State private var informationHeight: CGFloat = 340

    private var style: RestOverlayStyle {
        RestOverlayStyle(background: session.background, colorScheme: colorScheme)
    }

    private var sunDismissal: Bool {
        session.background == .sun && session.isDismissing && !reduceMotion
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                background
                    .opacity(sunDismissal ? 0.34 : 1)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: session.isDismissing)

                if session.contentMode == .dinosaur {
                    let available = max(0, (proxy.size.height - informationHeight) / 2 - 32)
                    if available >= 36 {
                        DinosaurRestContentView(
                            session: session,
                            compact: available < 130
                        )
                        .frame(height: min(200, available))
                        .padding(.horizontal, 32)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                        .padding(.bottom, 16)
                        .opacity(session.isDismissing ? 0 : 1)
                    }
                }

                information
                    .padding(.horizontal, min(48, proxy.size.width * 0.06))
                    .background {
                        GeometryReader { informationProxy in
                            Color.clear.preference(key: RestInformationHeightKey.self,
                                                   value: informationProxy.size.height)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .opacity(sunDismissal ? 0 : 1)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.08), value: session.isDismissing)
            }
        }
        .onPreferenceChange(RestInformationHeightKey.self) { informationHeight = $0 }
    }

    @ViewBuilder private var background: some View {
        if session.contentMode == .dinosaur {
            DinosaurPalette(dark: colorScheme == .dark).background.ignoresSafeArea()
        } else {
            RestOverlayBackgroundView(background: session.background, style: style,
                                      translucent: session.translucent)
        }
    }

    private var information: some View {
        VStack(spacing: 24) {
            Text(session.formattedTime)
                .font(.system(size: 96, weight: .regular, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(style.primaryText)
                .shadow(color: style.textShadow, radius: 8, y: 2)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .accessibilityLabel("剩余时间")
                .accessibilityValue(session.formattedTime)

            if let prompt = session.copy.prompt {
                Text(prompt)
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(style.primaryText.opacity(0.94))
                    .shadow(color: style.textShadow, radius: 6, y: 2)
            }
            if let subtitle = session.copy.subtitle {
                Text(subtitle)
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(style.primaryText.opacity(0.72))
                    .shadow(color: style.textShadow, radius: 5, y: 1)
            }
            actionButtons
        }
        .multilineTextAlignment(.center)
    }

    @ViewBuilder private var actionButtons: some View {
        switch actions {
        case let .preview(onClose):
            Button("关闭预览", action: onClose)
                .buttonStyle(RestOverlayActionButtonStyle(style: style))
                .padding(.top, 10)
        case let .rest(duration, canSnooze, canSkip, onSnooze, onSkip):
            if canSnooze || canSkip {
                HStack(spacing: 24) {
                    if canSnooze {
                        Button("延后 \(Self.formattedDuration(duration))", action: onSnooze)
                    }
                    if canSkip {
                        Button("跳过", action: onSkip)
                    }
                }
                .buttonStyle(RestOverlayActionButtonStyle(style: style))
                .padding(.top, 10)
            }
        }
    }

    private static func formattedDuration(_ duration: TimeInterval) -> String {
        duration >= 60 ? "\(max(1, Int(duration / 60))) 分钟" : "\(max(1, Int(duration))) 秒"
    }
}

private struct RestInformationHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 340
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

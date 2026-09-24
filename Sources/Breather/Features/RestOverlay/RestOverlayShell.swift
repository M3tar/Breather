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
    @State private var curtainPhase: CurtainPhase = .open
    @State private var curtainContentVisible = false

    private var atmosphere: RestAtmosphere? {
        RestAtmosphere(contentMode: session.contentMode)
    }

    private var style: RestOverlayStyle {
        RestOverlayStyle(
            background: atmosphere?.styleBackground ?? session.background,
            colorScheme: session.contentMode == .curtain ? .dark
                : atmosphere == .moonlight || atmosphere == .rainy || atmosphere == .snowy ? .dark
                : atmosphere == .windowLeaves || atmosphere == .sunny || atmosphere == .cloudTrain ? .light
                : colorScheme
        )
    }

    private var atmosphericDismissal: Bool {
        (atmosphere != nil || session.background == .sun)
            && session.isDismissing && !reduceMotion
    }

    private var animatesCurtain: Bool {
        session.fadeAnimation && !reduceMotion
    }

    private var curtainColors: CurtainColors {
        CurtainColors(palette: session.curtainPalette)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                background
                    .opacity(atmosphericDismissal ? 0.34 : 1)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: session.isDismissing)

                if session.contentMode == .curtain {
                    CurtainBackdrop(
                        palette: session.curtainPalette,
                        phase: curtainPhase,
                        animated: animatesCurtain
                            && (!session.isAnimationPaused || session.isDismissing)
                    )
                }

                if let atmosphere {
                    AtmosphericRestBackdrop(
                        atmosphere: atmosphere,
                        animated: session.fadeAnimation && !reduceMotion && !session.isAnimationPaused
                    )
                }

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
                    .opacity(informationOpacity)
                    .scaleEffect(session.contentMode == .curtain && !curtainContentVisible ? 0.985 : 1)
                    .animation(informationAnimation, value: curtainContentVisible)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.08), value: session.isDismissing)
            }
        }
        .onPreferenceChange(RestInformationHeightKey.self) { informationHeight = $0 }
        .onAppear(perform: closeCurtain)
        .onChange(of: session.isDismissing) { _, dismissing in
            guard session.contentMode == .curtain, dismissing else { return }
            if animatesCurtain {
                withAnimation(.easeOut(duration: 0.14)) { curtainContentVisible = false }
                curtainPhase = .opening
            } else {
                curtainContentVisible = false
                curtainPhase = .open
            }
        }
    }

    private var informationOpacity: Double {
        if atmosphericDismissal { return 0 }
        guard session.contentMode == .curtain else { return 1 }
        return curtainContentVisible && !session.isDismissing ? 1 : 0
    }

    private var informationAnimation: Animation? {
        guard animatesCurtain else { return nil }
        return curtainContentVisible
            ? .easeOut(duration: 0.38)
            : .easeOut(duration: 0.14)
    }

    private func closeCurtain() {
        guard session.contentMode == .curtain else { return }
        guard animatesCurtain else {
            curtainPhase = .closed
            curtainContentVisible = true
            return
        }
        Task { @MainActor in
            await Task.yield()
            guard !session.isDismissing else { return }
            curtainPhase = .closing
            try? await Task.sleep(for: CurtainTiming.contentRevealDelay)
            guard curtainPhase == .closing, !session.isDismissing else { return }
            withAnimation(.easeOut(duration: 0.38)) { curtainContentVisible = true }
        }
    }

    @ViewBuilder private var background: some View {
        if session.contentMode == .curtain {
            Color.clear.ignoresSafeArea()
        } else if atmosphere != nil {
            Color.clear.ignoresSafeArea()
        } else if session.contentMode == .dinosaur {
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
                .foregroundStyle(informationText)
                .shadow(color: informationShadow, radius: 8, y: 2)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .accessibilityLabel("剩余时间")
                .accessibilityValue(session.formattedTime)

            if let prompt = session.copy.prompt {
                Text(prompt)
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(informationText.opacity(0.94))
                    .shadow(color: informationShadow, radius: 6, y: 2)
            }
            if let subtitle = session.copy.subtitle {
                Text(subtitle)
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(informationText.opacity(0.72))
                    .shadow(color: informationShadow, radius: 5, y: 1)
            }
            actionButtons
        }
        .multilineTextAlignment(.center)
    }

    private var informationText: Color {
        if session.contentMode == .curtain { return curtainColors.text }
        return atmosphere?.text ?? style.primaryText
    }

    private var informationShadow: Color {
        if session.contentMode == .curtain { return curtainColors.shadow.opacity(0.58) }
        return atmosphere?.textShadow ?? style.textShadow
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

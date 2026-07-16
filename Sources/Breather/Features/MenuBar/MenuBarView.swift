import SwiftUI
import AppKit

struct MenuBarPanelView: View {
    @ObservedObject var scheduler: BreakScheduler
    let onOpenSettings: () -> Void
    let onQuit: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var settings: AppSettings {
        scheduler.settingsStore.settings
    }

    private var theme: RotorTheme {
        RotorTheme(
            colorScheme: effectiveColorScheme,
            themeColor: settings.menuBarPopoverThemeColor,
            squareColorMode: settings.menuBarPopoverSquareColorMode
        )
    }

    private var effectiveColorScheme: ColorScheme {
        switch settings.menuBarPopoverAppearance {
        case .system:
            colorScheme
        case .light:
            .light
        case .dark:
            .dark
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: -1) {
                PopoverArrow()
                    .fill(theme.chromeFill)
                    .frame(width: 38, height: 11)
                    .overlay {
                        PopoverArrowStroke()
                            .stroke(
                                theme.border,
                                style: StrokeStyle(lineWidth: 0.8, lineCap: .round, lineJoin: .round)
                            )
                    }
                    .shadow(color: Color.black.opacity(0.05), radius: 1, x: 0, y: 0.4)
                    .zIndex(1)

                MenuBarView(
                    scheduler: scheduler,
                    onOpenSettings: onOpenSettings,
                    onQuit: onQuit
                )
            }

            Rectangle()
                .fill(theme.chromeFill)
                .frame(width: 58, height: 2)
                .offset(y: 10)
                .allowsHitTesting(false)
        }
        .frame(width: 320, height: 430, alignment: .top)
        .background(Color.clear)
    }
}

struct MenuBarView: View {
    @ObservedObject var scheduler: BreakScheduler
    let onOpenSettings: () -> Void
    let onQuit: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHoveringRotor = false
    @State private var frozenRotationDegrees = 18.0
    @State private var rotationAnchorDate = Date()

    private var settings: AppSettings {
        scheduler.settingsStore.settings
    }

    private var theme: RotorTheme {
        RotorTheme(
            colorScheme: effectiveColorScheme,
            themeColor: settings.menuBarPopoverThemeColor,
            squareColorMode: settings.menuBarPopoverSquareColorMode
        )
    }

    private var effectiveColorScheme: ColorScheme {
        switch settings.menuBarPopoverAppearance {
        case .system:
            colorScheme
        case .light:
            .light
        case .dark:
            .dark
        }
    }

    private var progress: Double {
        let total = max(1, totalSeconds)
        return min(1, max(0, 1 - Double(scheduler.remainingSeconds) / Double(total)))
    }

    private var totalSeconds: Int {
        switch scheduler.state {
        case .resting:
            Int(scheduler.settingsStore.rules.shortBreakDuration)
        case .snoozing:
            Int(scheduler.settingsStore.settings.snoozeDuration)
        case .paused:
            max(Int(scheduler.settingsStore.rules.workDuration), scheduler.remainingSeconds)
        case .working, .notifying, .idleRested:
            Int(scheduler.settingsStore.rules.workDuration)
        }
    }

    private var phaseTitle: String {
        switch scheduler.state {
        case .working, .notifying: "Process"
        case .resting: "Rest"
        case .snoozing: "Snooze"
        case .paused: "Pause"
        case .idleRested: "Ready"
        }
    }

    private var percentText: String {
        "\(Int((progress * 100).rounded()))%"
    }

    private var shouldRotateSquare: Bool {
        !scheduler.isPaused && !reduceMotion
    }

    private var squareAppearance: RotorSquareAppearance {
        theme.squareAppearance(for: settings.menuBarPopoverSquareStyle)
    }

    private var squareRotationSpeed: Double {
        360 / squareAppearance.rotationDuration
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            VStack(spacing: 14) {
                Spacer(minLength: 20)

                rotorButton

                Text(scheduler.formattedTime)
                    .font(.system(size: 42, weight: .medium, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(theme.text)
                    .padding(.top, 2)

                progressBlock

                Spacer(minLength: 52)
            }
            .padding(.horizontal, 26)

            actions
                .padding(.horizontal, 26)
                .padding(.bottom, 22)
        }
        .frame(width: 320, height: 420)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(theme.surfaceGradient)

                Circle()
                    .fill(theme.backgroundGlow)
                    .frame(width: 230, height: 230)
                    .blur(radius: 34)
                    .offset(y: -34)

                Circle()
                    .fill(theme.lowerBackgroundGlow)
                    .frame(width: 280, height: 220)
                    .blur(radius: 42)
                    .offset(y: 128)

                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(theme.border, lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .onAppear(perform: startSquareRotationIfNeeded)
        .onChange(of: scheduler.isPaused) { _, isPaused in
            if isPaused {
                freezeSquareRotation()
            } else {
                startSquareRotationIfNeeded()
            }
        }
        .onChange(of: reduceMotion) { _, isReduced in
            if isReduced {
                freezeSquareRotation()
            } else {
                startSquareRotationIfNeeded()
            }
        }
    }

    private var header: some View {
        HStack {
            IconButton(systemName: "power", color: theme.muted, help: "退出 Breather", action: onQuit)

            Spacer()

            IconButton(systemName: "gearshape", color: theme.muted, help: "设置", action: onOpenSettings)
        }
        .padding(.horizontal, 26)
        .padding(.top, 24)
    }

    private var rotorButton: some View {
        Button(action: scheduler.togglePause) {
            ZStack {
                TimelineView(.animation) { timeline in
                    square
                        .rotationEffect(.degrees(rotationDegrees(at: timeline.date)))
                }

                Image(systemName: scheduler.isPaused ? "play.fill" : "pause.fill")
                    .font(.system(size: scheduler.isPaused ? 15 : 14, weight: .bold))
                    .foregroundStyle(squareAppearance.glyph)
                    .symbolRenderingMode(.monochrome)
                    .opacity(scheduler.isPaused || isHoveringRotor ? 1 : 0)
            }
            .frame(width: 52, height: 52)
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(scheduler.isPaused ? "继续" : "暂停")
        .help(scheduler.isPaused ? "继续" : "暂停")
        .onHover { isHoveringRotor = $0 }
    }

    private var square: some View {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(squareAppearance.fill)
            .frame(width: 34, height: 34)
            .modifier(SquareShadowModifier(appearance: squareAppearance))
            .opacity(scheduler.isPaused ? squareAppearance.pausedOpacity : 1)
    }

    @ViewBuilder
    private var progressBlock: some View {
        VStack(spacing: 8) {
            HStack {
                Text(phaseTitle)
                    .foregroundStyle(theme.accent)

                Spacer()

                Text(percentText)
                    .foregroundStyle(theme.text)
            }
            .font(.system(size: 12, weight: .bold))
            .monospacedDigit()

            switch settings.menuBarPopoverProgressStyle {
            case .radix:
                RadixProgressBar(progress: progress, theme: theme)
            case .segments:
                SegmentedProgressBar(progress: progress, theme: theme)
            }
        }
        .frame(width: 216)
        .animation(.easeOut(duration: 0.35), value: progress)
    }

    private var actions: some View {
        HStack(spacing: 12) {
            Button(action: scheduler.resetWorkCycle) {
                Text("重置")
            }
            .buttonStyle(RotorActionButtonStyle(theme: theme, isPrimary: false))

            Button(action: scheduler.startRestNow) {
                Text("休息")
            }
            .buttonStyle(RotorActionButtonStyle(theme: theme, isPrimary: true))
        }
    }

    private func startSquareRotationIfNeeded() {
        if shouldRotateSquare {
            rotationAnchorDate = Date().addingTimeInterval(-rotationOffsetSeconds(for: frozenRotationDegrees))
        }
    }

    private func freezeSquareRotation() {
        frozenRotationDegrees = activeRotationDegrees(at: Date())
    }

    private func rotationDegrees(at date: Date) -> Double {
        shouldRotateSquare ? activeRotationDegrees(at: date) : frozenRotationDegrees
    }

    private func activeRotationDegrees(at date: Date) -> Double {
        normalizedDegrees(18 + date.timeIntervalSince(rotationAnchorDate) * squareRotationSpeed)
    }

    private func rotationOffsetSeconds(for degrees: Double) -> TimeInterval {
        normalizedDegrees(degrees - 18) / squareRotationSpeed
    }

    private func normalizedDegrees(_ degrees: Double) -> Double {
        let value = degrees.truncatingRemainder(dividingBy: 360)
        return value >= 0 ? value : value + 360
    }
}

private struct SquareShadowModifier: ViewModifier {
    let appearance: RotorSquareAppearance

    func body(content: Content) -> some View {
        content
            .shadow(color: appearance.strongGlow, radius: appearance.strongGlowRadius, x: 0, y: 0)
            .shadow(color: appearance.softGlow, radius: appearance.softGlowRadius, x: 0, y: 0)
            .shadow(color: appearance.dropShadow, radius: appearance.dropShadowRadius, x: 0, y: appearance.dropShadowYOffset)
    }
}

private struct RotorSquareAppearance {
    let fill: LinearGradient
    let glyph: Color
    let strongGlow: Color
    let strongGlowRadius: CGFloat
    let softGlow: Color
    let softGlowRadius: CGFloat
    let dropShadow: Color
    let dropShadowRadius: CGFloat
    let dropShadowYOffset: CGFloat
    let pausedOpacity: Double
    let rotationDuration: TimeInterval
}

private struct RadixProgressBar: View {
    let progress: Double
    let theme: RotorTheme

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Capsule()
                    .fill(theme.progressTrack)

                Capsule()
                    .fill(theme.progressFill)
                    .frame(width: proxy.size.width)
                    .offset(x: -proxy.size.width + proxy.size.width * progress)
            }
            .clipShape(Capsule())
        }
        .frame(height: 8)
    }
}

private struct SegmentedProgressBar: View {
    let progress: Double
    let theme: RotorTheme

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                SegmentedStripe(color: theme.progressTrack)

                Rectangle()
                    .fill(theme.progressCompletedGap)
                    .frame(width: proxy.size.width * progress)

                SegmentedStripe(color: theme.accent)
                    .frame(width: proxy.size.width * progress)
            }
            .clipShape(Capsule())
        }
        .frame(height: 10)
    }
}

private struct SegmentedStripe: View {
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 6) {
                ForEach(0..<segmentCount(for: proxy.size.width), id: \.self) { _ in
                    Rectangle()
                        .fill(color)
                        .frame(width: 4)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }

    private func segmentCount(for width: CGFloat) -> Int {
        max(1, Int((width / 10).rounded(.up)) + 1)
    }
}

private struct IconButton: View {
    let systemName: String
    let color: Color
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .semibold))
                .symbolRenderingMode(.monochrome)
                .frame(width: 32, height: 32)
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .foregroundStyle(color)
        .help(help)
        .accessibilityLabel(help)
    }
}

private struct PopoverArrow: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let baseY = rect.maxY
        let tipY = rect.minY
        let midX = rect.midX
        let leftX = rect.minX
        let rightX = rect.maxX

        path.move(to: CGPoint(x: leftX, y: baseY))
        path.addCurve(
            to: CGPoint(x: midX, y: tipY),
            control1: CGPoint(x: leftX + rect.width * 0.30, y: baseY),
            control2: CGPoint(x: midX - rect.width * 0.16, y: tipY + 0.6)
        )
        path.addCurve(
            to: CGPoint(x: rightX, y: baseY),
            control1: CGPoint(x: midX + rect.width * 0.16, y: tipY + 0.6),
            control2: CGPoint(x: rightX - rect.width * 0.30, y: baseY)
        )
        path.closeSubpath()
        return path
    }
}

private struct PopoverArrowStroke: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let baseY = rect.maxY
        let tipY = rect.minY
        let midX = rect.midX
        let leftX = rect.minX
        let rightX = rect.maxX

        path.move(to: CGPoint(x: leftX, y: baseY))
        path.addCurve(
            to: CGPoint(x: midX, y: tipY),
            control1: CGPoint(x: leftX + rect.width * 0.30, y: baseY),
            control2: CGPoint(x: midX - rect.width * 0.16, y: tipY + 0.6)
        )
        path.addCurve(
            to: CGPoint(x: rightX, y: baseY),
            control1: CGPoint(x: midX + rect.width * 0.16, y: tipY + 0.6),
            control2: CGPoint(x: rightX - rect.width * 0.30, y: baseY)
        )
        return path
    }
}

private struct RotorActionButtonStyle: ButtonStyle {
    let theme: RotorTheme
    let isPrimary: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .frame(maxWidth: .infinity)
            .frame(height: 42)
            .foregroundStyle(isPrimary ? theme.primaryButtonText.opacity(0.94) : theme.text.opacity(0.82))
            .background(isPrimary ? theme.accent : theme.buttonBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isPrimary ? Color.clear : theme.buttonBorder, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .opacity(configuration.isPressed ? 0.72 : 1)
    }
}

private struct RotorTheme {
    let surfaceGradient: LinearGradient
    let chromeFill: Color
    let backgroundGlow: Color
    let lowerBackgroundGlow: Color
    let text: Color
    let muted: Color
    let border: Color
    let accent: Color
    let progressTrack: Color
    let progressCompletedGap: Color
    let progressFill: LinearGradient
    let breathingSquare: RotorSquareAppearance
    let blockSquare: RotorSquareAppearance
    let primaryButtonText: Color
    let buttonBackground: Color
    let buttonBorder: Color

    func squareAppearance(for style: MenuBarPopoverSquareStyle) -> RotorSquareAppearance {
        switch style {
        case .breathing:
            breathingSquare
        case .block:
            blockSquare
        }
    }

    init(
        colorScheme: ColorScheme,
        themeColor: MenuBarPopoverThemeColor,
        squareColorMode: MenuBarPopoverSquareColorMode
    ) {
        let isDark = colorScheme == .dark
        let palette = RotorPalette(themeColor: themeColor, isDark: isDark)
        let squarePalette = squareColorMode == .followTheme
            ? palette
            : RotorPalette(themeColor: .neutralCore, isDark: isDark)

        surfaceGradient = LinearGradient(
            colors: isDark
                ? [Color(hex: 0x171918), Color(hex: 0x101211)]
                : [Color.white, palette.surface],
            startPoint: .top,
            endPoint: .bottom
        )
        let chromeBase = isDark ? Color(hex: 0x171918) : Color(hex: 0xFEFFFE)
        chromeFill = chromeBase.mix(with: palette.accent, amount: isDark ? 0.018 : 0.008)
        backgroundGlow = palette.glow
        lowerBackgroundGlow = palette.glow.opacity(isDark ? 0.22 : 0.34)
        accent = palette.accent
        text = isDark ? Color(hex: 0xECEEED) : Color(hex: 0x1D2421)
        muted = isDark ? Color(hex: 0x717D79) : Color(hex: 0x65716B)
        border = isDark ? Color.white.opacity(0.12) : Color(hex: 0x8B9992).opacity(0.38)
        progressTrack = palette.line
        progressCompletedGap = palette.line
        progressFill = LinearGradient(
            colors: [palette.accent.mix(with: .white, amount: 0.28), palette.accent],
            startPoint: .leading,
            endPoint: .trailing
        )
        breathingSquare = RotorSquareAppearance.breathing(
            palette: palette,
            squarePalette: squarePalette,
            isNeutral: squareColorMode == .neutral,
            isDark: isDark
        )
        blockSquare = RotorSquareAppearance.block(
            squarePalette: squarePalette,
            isDark: isDark
        )
        primaryButtonText = palette.primaryButtonText
        buttonBackground = isDark ? Color(hex: 0x1A211E).opacity(0.86) : Color.white.opacity(0.72)
        buttonBorder = isDark ? Color(hex: 0x373B39) : Color(hex: 0x1D2421).opacity(0.14)
    }
}

private struct RotorPalette {
    let themeColor: MenuBarPopoverThemeColor
    let accent: Color
    let line: Color
    let surface: Color
    let glow: Color
    let squareColors: [Color]
    let pauseGlyph: Color
    let primaryButtonText: Color

    init(themeColor: MenuBarPopoverThemeColor, isDark: Bool) {
        self.themeColor = themeColor

        switch (themeColor, isDark) {
        case (.jadeCore, false):
            accent = Color(hex: 0x29A383)
            line = accent.opacity(0.20)
            surface = Color(hex: 0xF1FAF6)
            glow = accent.opacity(0.16)
            squareColors = [Color(hex: 0x37D9AE), Color(hex: 0x128A6D)]
            pauseGlyph = .white
            primaryButtonText = .white
        case (.jadeCore, true):
            accent = Color(hex: 0x1FD8A4)
            line = accent.opacity(0.24)
            surface = Color(hex: 0x101211)
            glow = accent.opacity(0.20)
            squareColors = [Color(hex: 0x27B08B), Color(hex: 0x0B3B2C)]
            pauseGlyph = Color(hex: 0x101211)
            primaryButtonText = Color(hex: 0x050807)
        case (.jadeToken, false):
            accent = Color(hex: 0x29A383)
            line = accent.opacity(0.20)
            surface = Color(hex: 0xF1FAF6)
            glow = accent.opacity(0.16)
            squareColors = [Color(hex: 0x37D9AE), Color(hex: 0x128A6D)]
            pauseGlyph = .white
            primaryButtonText = .white
        case (.jadeToken, true):
            accent = Color(hex: 0x29A383)
            line = Color(hex: 0x1FD8A4).opacity(0.24)
            surface = Color(hex: 0x101211)
            glow = Color(hex: 0x1FD8A4).opacity(0.20)
            squareColors = [Color(hex: 0x27B08B), Color(hex: 0x0B3B2C)]
            pauseGlyph = Color(hex: 0x101211)
            primaryButtonText = .white
        case (.neutralCore, false):
            accent = Color(hex: 0x1D2421)
            line = accent.opacity(0.14)
            surface = Color(hex: 0xF4F8F6)
            glow = Color(hex: 0x29A383).opacity(0.08)
            squareColors = [Color(hex: 0x323A37), Color(hex: 0x141917)]
            pauseGlyph = .white
            primaryButtonText = .white
        case (.neutralCore, true):
            accent = Color(hex: 0xF8FAF9)
            line = accent.opacity(0.18)
            surface = Color(hex: 0x101211)
            glow = Color.white.opacity(0.10)
            squareColors = [Color(hex: 0xF8FAF9), Color(hex: 0x8C9994)]
            pauseGlyph = Color(hex: 0x101211)
            primaryButtonText = Color(hex: 0x101211)
        case (.tealGlass, false):
            accent = Color(hex: 0x12A594)
            line = accent.opacity(0.20)
            surface = Color(hex: 0xEFFAF7)
            glow = accent.opacity(0.15)
            squareColors = [Color(hex: 0x21C7B4), Color(hex: 0x008573)]
            pauseGlyph = .white
            primaryButtonText = .white
        case (.tealGlass, true):
            accent = Color(hex: 0x0BD8B6)
            line = accent.opacity(0.22)
            surface = Color(hex: 0x101211)
            glow = accent.opacity(0.20)
            squareColors = [Color(hex: 0x0EB39E), Color(hex: 0x023B37)]
            pauseGlyph = Color(hex: 0x101211)
            primaryButtonText = Color(hex: 0x050807)
        case (.mintAir, false):
            accent = Color(hex: 0x027864)
            line = accent.opacity(0.18)
            surface = Color(hex: 0xEFFBF8)
            glow = Color(hex: 0x86EAD4).opacity(0.18)
            squareColors = [Color(hex: 0x86EAD4), Color(hex: 0x027864)]
            pauseGlyph = .white
            primaryButtonText = .white
        case (.mintAir, true):
            accent = Color(hex: 0x58D5BA)
            line = accent.opacity(0.24)
            surface = Color(hex: 0x101211)
            glow = Color(hex: 0x86EAD4).opacity(0.20)
            squareColors = [Color(hex: 0xA8F5E5), Color(hex: 0x003A38)]
            pauseGlyph = Color(hex: 0x101211)
            primaryButtonText = Color(hex: 0x050807)
        case (.mistBlue, false):
            accent = Color(hex: 0x4D93C8)
            line = accent.opacity(0.20)
            surface = Color(hex: 0xF2F8FB)
            glow = accent.opacity(0.15)
            squareColors = [Color(hex: 0x7FC8E7), Color(hex: 0x3F7FAC)]
            pauseGlyph = .white
            primaryButtonText = .white
        case (.mistBlue, true):
            accent = Color(hex: 0x75C7F0)
            line = accent.opacity(0.22)
            surface = Color(hex: 0x101211)
            glow = accent.opacity(0.18)
            squareColors = [Color(hex: 0xA8EEFF), Color(hex: 0x113555)]
            pauseGlyph = Color(hex: 0x101211)
            primaryButtonText = Color(hex: 0x050807)
        case (.skyBreath, false):
            accent = Color(hex: 0x4D93C8)
            line = accent.opacity(0.20)
            surface = Color(hex: 0xF2F8FB)
            glow = accent.opacity(0.15)
            squareColors = [Color(hex: 0x7CE2FE), Color(hex: 0x3F7FAC)]
            pauseGlyph = .white
            primaryButtonText = .white
        case (.skyBreath, true):
            accent = Color(hex: 0x75C7F0)
            line = accent.opacity(0.22)
            surface = Color(hex: 0x101211)
            glow = accent.opacity(0.18)
            squareColors = [Color(hex: 0xA8EEFF), Color(hex: 0x113555)]
            pauseGlyph = Color(hex: 0x101211)
            primaryButtonText = Color(hex: 0x050807)
        case (.lilacCalm, false):
            accent = Color(hex: 0x8B79C8)
            line = accent.opacity(0.20)
            surface = Color(hex: 0xF6F4FB)
            glow = accent.opacity(0.14)
            squareColors = [Color(hex: 0xB7A9E8), Color(hex: 0x7461B4)]
            pauseGlyph = .white
            primaryButtonText = .white
        case (.lilacCalm, true):
            accent = Color(hex: 0xB1A9FF)
            line = accent.opacity(0.22)
            surface = Color(hex: 0x101211)
            glow = accent.opacity(0.18)
            squareColors = [Color(hex: 0x6E6ADE), Color(hex: 0x262A65)]
            pauseGlyph = Color(hex: 0x101211)
            primaryButtonText = Color(hex: 0x050807)
        case (.irisDrift, false):
            accent = Color(hex: 0x5B5BD6)
            line = accent.opacity(0.18)
            surface = Color(hex: 0xF6F4FB)
            glow = accent.opacity(0.13)
            squareColors = [Color(hex: 0xB7A9E8), Color(hex: 0x7461B4)]
            pauseGlyph = .white
            primaryButtonText = .white
        case (.irisDrift, true):
            accent = Color(hex: 0xB1A9FF)
            line = accent.opacity(0.22)
            surface = Color(hex: 0x101211)
            glow = accent.opacity(0.18)
            squareColors = [Color(hex: 0x6E6ADE), Color(hex: 0x262A65)]
            pauseGlyph = Color(hex: 0x101211)
            primaryButtonText = Color(hex: 0x050807)
        case (.warmClay, false):
            accent = Color(hex: 0xC7784D)
            line = accent.opacity(0.20)
            surface = Color(hex: 0xF9F3EF)
            glow = accent.opacity(0.14)
            squareColors = [Color(hex: 0xE1A071), Color(hex: 0xB85F3D)]
            pauseGlyph = .white
            primaryButtonText = .white
        case (.warmClay, true):
            accent = Color(hex: 0xC7784D)
            line = accent.opacity(0.22)
            surface = Color(hex: 0x101211)
            glow = accent.opacity(0.16)
            squareColors = [Color(hex: 0xE1A071), Color(hex: 0x4A1D0E)]
            pauseGlyph = Color(hex: 0x101211)
            primaryButtonText = Color(hex: 0x050807)
        case (.amberRest, false):
            accent = Color(hex: 0xAB6400)
            line = accent.opacity(0.18)
            surface = Color(hex: 0xFFF7EE)
            glow = Color(hex: 0xFFC53D).opacity(0.14)
            squareColors = [Color(hex: 0xFFC53D), Color(hex: 0xB85F3D)]
            pauseGlyph = Color(hex: 0x1D2421)
            primaryButtonText = .white
        case (.amberRest, true):
            accent = Color(hex: 0xFFCA16)
            line = accent.opacity(0.20)
            surface = Color(hex: 0x101211)
            glow = accent.opacity(0.16)
            squareColors = [Color(hex: 0xFFD60A), Color(hex: 0x3F2700)]
            pauseGlyph = Color(hex: 0x101211)
            primaryButtonText = Color(hex: 0x101211)
        }
    }
}

private extension RotorSquareAppearance {
    static func breathing(
        palette: RotorPalette,
        squarePalette: RotorPalette,
        isNeutral: Bool,
        isDark: Bool
    ) -> RotorSquareAppearance {
        let fillColors: [Color]
        if isNeutral {
            fillColors = squarePalette.squareColors
        } else if isDark && squarePalette.themeColor == .warmClay {
            fillColors = [Color(hex: 0xD28455), Color(hex: 0x8A432A)]
        } else {
            fillColors = isDark
                ? [
                    squarePalette.accent.mix(with: .white, amount: 0.08),
                    squarePalette.accent.mix(with: .black, amount: 0.66)
                ]
                : [
                    squarePalette.accent.mix(with: .white, amount: 0.34),
                    squarePalette.accent.mix(with: .black, amount: 0.16)
                ]
        }

        let glowSource = isNeutral ? palette.accent : squarePalette.accent

        return RotorSquareAppearance(
            fill: LinearGradient(colors: fillColors, startPoint: .topLeading, endPoint: .bottomTrailing),
            glyph: squarePalette.pauseGlyph,
            strongGlow: glowSource.opacity(isDark ? 0.34 : 0.42),
            strongGlowRadius: 30,
            softGlow: glowSource.opacity(isDark ? 0.18 : 0.22),
            softGlowRadius: 72,
            dropShadow: Color.black.opacity(isDark ? 0.30 : 0.18),
            dropShadowRadius: 26,
            dropShadowYOffset: 12,
            pausedOpacity: 0.22,
            rotationDuration: 5.2
        )
    }

    static func block(
        squarePalette: RotorPalette,
        isDark: Bool
    ) -> RotorSquareAppearance {
        let fillColors: [Color]
        if isDark && squarePalette.themeColor == .warmClay {
            fillColors = [Color(hex: 0xD28455), Color(hex: 0xC87349)]
        } else {
            fillColors = isDark
                ? [
                    squarePalette.accent.mix(with: .white, amount: 0.22),
                    squarePalette.accent.mix(with: .black, amount: 0.34)
                ]
                : squarePalette.squareColors
        }

        return RotorSquareAppearance(
            fill: LinearGradient(colors: fillColors, startPoint: .topLeading, endPoint: .bottomTrailing),
            glyph: squarePalette.pauseGlyph,
            strongGlow: squarePalette.accent.opacity(isDark ? 0.12 : 0.10),
            strongGlowRadius: 14,
            softGlow: squarePalette.accent.opacity(isDark ? 0.06 : 0.06),
            softGlowRadius: 22,
            dropShadow: Color.black.opacity(isDark ? 0.18 : 0.12),
            dropShadowRadius: 16,
            dropShadowYOffset: 10,
            pausedOpacity: 0.28,
            rotationDuration: 5.2
        )
    }
}

private extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xff) / 255,
            green: Double((hex >> 8) & 0xff) / 255,
            blue: Double(hex & 0xff) / 255
        )
    }

    func mix(with other: Color, amount: Double) -> Color {
        Color(
            red: resolvedRed * (1 - amount) + other.resolvedRed * amount,
            green: resolvedGreen * (1 - amount) + other.resolvedGreen * amount,
            blue: resolvedBlue * (1 - amount) + other.resolvedBlue * amount
        )
    }

    private var resolvedRed: Double {
        #if os(macOS)
        Double(NSColor(self).usingColorSpace(.sRGB)?.redComponent ?? 0)
        #else
        0
        #endif
    }

    private var resolvedGreen: Double {
        #if os(macOS)
        Double(NSColor(self).usingColorSpace(.sRGB)?.greenComponent ?? 0)
        #else
        0
        #endif
    }

    private var resolvedBlue: Double {
        #if os(macOS)
        Double(NSColor(self).usingColorSpace(.sRGB)?.blueComponent ?? 0)
        #else
        0
        #endif
    }
}

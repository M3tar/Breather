import SwiftUI

struct RestThemePicker: View {
    static let displayModes: [RestOverlayContentMode] = [
        .classic,
        .moonlight,
        .dinosaur,
        .curtain,
        .windowLeaves,
        .sunny,
        .rainy,
        .snowy,
        .cloudTrain
    ]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.controlActiveState) private var controlActiveState
    @Binding var settings: AppSettings
    let duration: Int
    let isResting: Bool
    @State private var changedDuringRest = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("休息主题").font(.headline)
            ViewThatFits(in: .horizontal) {
                threeColumnOptions
                twoColumnOptions
                singleColumnOptions
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

    private var singleColumnOptions: some View {
        VStack(spacing: 12) {
            options
        }
    }

    private var options: some View {
        ForEach(Self.displayModes) { mode in
            option(for: mode)
        }
    }

    private var threeColumnOptions: some View {
        let modes = Self.displayModes
        let fullRowCount = modes.count / 3
        let remainder = modes.count % 3
        return Grid(alignment: .topLeading, horizontalSpacing: 12, verticalSpacing: 12) {
            ForEach(0..<fullRowCount, id: \.self) { row in
                GridRow {
                    ForEach(0..<3, id: \.self) { column in
                        option(for: modes[row * 3 + column])
                            .gridCellColumns(2)
                    }
                }
            }
            if remainder == 2 {
                GridRow {
                    Color.clear.gridCellUnsizedAxes(.vertical)
                    option(for: modes[fullRowCount * 3])
                        .gridCellColumns(2)
                    option(for: modes[fullRowCount * 3 + 1])
                        .gridCellColumns(2)
                    Color.clear.gridCellUnsizedAxes(.vertical)
                }
            } else if remainder == 1 {
                GridRow {
                    Color.clear.gridCellColumns(2).gridCellUnsizedAxes(.vertical)
                    option(for: modes[fullRowCount * 3])
                        .gridCellColumns(2)
                    Color.clear.gridCellColumns(2).gridCellUnsizedAxes(.vertical)
                }
            }
        }
        .frame(minWidth: 672)
    }

    private var twoColumnOptions: some View {
        let modes = Self.displayModes
        return Grid(alignment: .topLeading, horizontalSpacing: 12, verticalSpacing: 12) {
            ForEach(0..<((modes.count + 1) / 2), id: \.self) { row in
                GridRow {
                    ForEach(0..<2, id: \.self) { column in
                        let index = row * 2 + column
                        if index < modes.count {
                            option(for: modes[index])
                        } else {
                            Color.clear.frame(minWidth: 220)
                        }
                    }
                }
            }
        }
        .frame(minWidth: 440)
    }

    private func option(for mode: RestOverlayContentMode) -> some View {
        let isSelected = settings.restOverlayContentMode == mode
        return RestContentOption(mode: mode,
                                 isSelected: isSelected,
                                 thumbnail: RestThemeThumbnailConfiguration(mode: mode, settings: settings,
                                                                           duration: duration),
                                 animatesThumbnail: Self.shouldAnimateThumbnail(
                                     mode: mode,
                                     isSelected: isSelected,
                                     allowsAnimation: allowsThumbnailAnimation
                                 )) {
            settings.restOverlayContentMode = mode
        }
        .frame(maxWidth: .infinity)
    }

    static func shouldAnimateThumbnail(
        mode: RestOverlayContentMode,
        isSelected: Bool,
        allowsAnimation: Bool
    ) -> Bool {
        mode != .moonlight && isSelected && allowsAnimation
    }

    private var allowsThumbnailAnimation: Bool {
        !reduceMotion && controlActiveState != .inactive
    }
}

/// A value-only thumbnail: no session, random sampling, timer or scheduler writes.
struct RestThemeThumbnailConfiguration: Equatable {
    let mode: RestOverlayContentMode
    let background: RestOverlayBackground
    let translucent: Bool
    let curtainPalette: CurtainPalette
    let formattedTime: String

    init(mode: RestOverlayContentMode, settings: AppSettings, duration: Int) {
        self.mode = mode
        background = mode == .classic ? settings.restOverlayBackground : .solid
        translucent = mode == .classic && settings.restOverlayTranslucentBackground
        curtainPalette = settings.curtainPalette
        let seconds = max(0, duration)
        formattedTime = String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}

struct RestContentOption: View {
    let mode: RestOverlayContentMode
    let isSelected: Bool
    let thumbnail: RestThemeThumbnailConfiguration
    let animatesThumbnail: Bool
    let onSelect: () -> Void

    init(
        mode: RestOverlayContentMode,
        isSelected: Bool,
        thumbnail: RestThemeThumbnailConfiguration,
        animatesThumbnail: Bool = false,
        onSelect: @escaping () -> Void
    ) {
        self.mode = mode
        self.isSelected = isSelected
        self.thumbnail = thumbnail
        self.animatesThumbnail = animatesThumbnail
        self.onSelect = onSelect
    }

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 10) {
                RestThemeThumbnail(configuration: thumbnail, animated: animatesThumbnail)
                    .overlay(alignment: .topLeading) {
                        if let motionBadge {
                            RestThemeMotionBadge(title: motionBadge)
                                .padding(6)
                        }
                    }
                    .overlay(alignment: .topTrailing) {
                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, Color.accentColor)
                                .font(.system(size: 16, weight: .semibold))
                                .padding(6)
                        }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(mode.title).font(.body.weight(.medium))
                    Text(mode.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(RestThemeOptionButtonStyle(isSelected: isSelected))
        .accessibilityLabel(motionBadge.map { "\(mode.title)，\($0)" } ?? mode.title)
        .accessibilityHint(mode.summary)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var motionBadge: String? {
        switch mode {
        case .dinosaur, .windowLeaves, .sunny, .rainy, .snowy, .cloudTrain:
            "动态"
        case .curtain:
            "转场"
        case .classic, .moonlight:
            nil
        }
    }
}

private struct RestThemeMotionBadge: View {
    let title: String

    var body: some View {
        if #available(macOS 26.0, *) {
            label
                .glassEffect(.regular, in: Capsule())
        } else {
            label
                .background(.ultraThinMaterial, in: Capsule())
        }
    }

    private var label: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
    }
}

struct RestThemeThumbnail: View {
    @Environment(\.colorScheme) private var colorScheme
    let configuration: RestThemeThumbnailConfiguration
    let animated: Bool
    private static let scene = DinosaurSceneModel(seed: 0).frame(elapsed: 0, animated: false)

    init(configuration: RestThemeThumbnailConfiguration, animated: Bool = false) {
        self.configuration = configuration
        self.animated = animated
    }

    static func countdownDelay(
        mode: RestOverlayContentMode,
        animated: Bool
    ) -> Duration? {
        mode == .curtain && animated ? CurtainTiming.thumbnailContentRevealDelay : nil
    }

    var body: some View {
        let atmosphere = RestAtmosphere(contentMode: configuration.mode)
        let style = RestOverlayStyle(
            background: atmosphere?.styleBackground ?? configuration.background,
            colorScheme: configuration.mode == .curtain ? .dark
                : atmosphere == .moonlight || atmosphere == .rainy ? .dark
                : atmosphere == .windowLeaves || atmosphere == .sunny || atmosphere == .snowy || atmosphere == .cloudTrain ? .light
                : colorScheme
        )
        ZStack {
            if configuration.mode == .curtain {
                CurtainBackdrop(
                    palette: configuration.curtainPalette,
                    phase: animated ? .closing : .closed,
                    animated: animated
                )
            } else if let atmosphere {
                AtmosphericRestBackdrop(atmosphere: atmosphere, animated: animated)
            } else if configuration.mode == .dinosaur {
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
            let countdownColor = thumbnailText(style: style)
            let countdownOffset = configuration.mode == .dinosaur ? -12.0 : 0
            if let delay = Self.countdownDelay(mode: configuration.mode, animated: animated) {
                DelayedRestThemeCountdownLabel(
                    text: configuration.formattedTime,
                    foreground: countdownColor,
                    shadow: style.textShadow,
                    verticalOffset: countdownOffset,
                    delay: delay
                )
            } else {
                RestThemeCountdownLabel(
                    text: configuration.formattedTime,
                    foreground: countdownColor,
                    shadow: style.textShadow,
                    verticalOffset: countdownOffset
                )
            }
        }
        // Shared thumbnail viewport, not a fixed card height; descriptions can wrap.
        .frame(maxWidth: .infinity)
        .frame(height: 96)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .accessibilityHidden(true)
    }

    private func thumbnailText(style: RestOverlayStyle) -> Color {
        if configuration.mode == .curtain {
            return CurtainColors(palette: configuration.curtainPalette).text
        }
        return RestAtmosphere(contentMode: configuration.mode)?.text ?? style.primaryText
    }
}

private struct RestThemeCountdownLabel: View {
    let text: String
    let foreground: Color
    let shadow: Color
    let verticalOffset: CGFloat

    var body: some View {
        Text(text)
            .font(.system(size: 26, weight: .regular, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(foreground)
            .shadow(color: shadow, radius: 2, y: 1)
            .offset(y: verticalOffset)
    }
}

private struct DelayedRestThemeCountdownLabel: View {
    let text: String
    let foreground: Color
    let shadow: Color
    let verticalOffset: CGFloat
    let delay: Duration
    @State private var isVisible = false

    var body: some View {
        RestThemeCountdownLabel(
            text: text,
            foreground: foreground,
            shadow: shadow,
            verticalOffset: verticalOffset
        )
        .opacity(isVisible ? 1 : 0)
        .task {
            do {
                try await Task.sleep(for: delay)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.24)) {
                isVisible = true
            }
        }
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

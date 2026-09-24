import AppKit
import SwiftUI

enum RestAtmosphere: CaseIterable {
    case moonlight
    case windowLeaves
    case sunny
    case rainy
    case snowy
    case cloudTrain

    init?(contentMode: RestOverlayContentMode) {
        switch contentMode {
        case .moonlight: self = .moonlight
        case .windowLeaves: self = .windowLeaves
        case .sunny: self = .sunny
        case .rainy: self = .rainy
        case .snowy: self = .snowy
        case .cloudTrain: self = .cloudTrain
        default: return nil
        }
    }

    var styleBackground: RestOverlayBackground {
        switch self {
        case .moonlight, .rainy, .snowy: .moon
        case .windowLeaves, .sunny, .cloudTrain: .sun
        }
    }

    var text: Color {
        switch self {
        case .moonlight: Color(red: 0.91, green: 0.92, blue: 0.91)
        case .windowLeaves: Color(red: 0.12, green: 0.12, blue: 0.105)
        case .sunny: Color(red: 0.12, green: 0.12, blue: 0.105)
        case .rainy: Color(red: 0.91, green: 0.94, blue: 0.96)
        case .snowy: Color(red: 0.96, green: 0.97, blue: 0.99)
        case .cloudTrain: Color(red: 0.19, green: 0.12, blue: 0.16)
        }
    }

    var textShadow: Color {
        switch self {
        case .moonlight: .black.opacity(0.72)
        case .windowLeaves: .white.opacity(0.46)
        case .sunny: .white.opacity(0.46)
        case .rainy: .black.opacity(0.32)
        case .snowy: .black.opacity(0.66)
        case .cloudTrain: .white.opacity(0.72)
        }
    }
}

struct AtmosphericRestBackdrop: View {
    let atmosphere: RestAtmosphere
    let animated: Bool

    @ViewBuilder
    var body: some View {
        if atmosphere == .windowLeaves || atmosphere == .sunny
            || atmosphere == .rainy || atmosphere == .snowy || atmosphere == .cloudTrain {
            AtmosphericRestFrame(
                atmosphere: atmosphere,
                time: 0,
                animated: animated
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)
        } else {
            TimelineView(.animation(minimumInterval: atmosphere == .rainy ? RainMotion.frameInterval : 1.0 / 30,
                                    paused: !animated)) { timeline in
                AtmosphericRestFrame(
                    atmosphere: atmosphere,
                    time: animated ? timeline.date.timeIntervalSinceReferenceDate : 0,
                    animated: animated
                )
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
        }
    }
}

enum SnowyRestBackground {
    static let url: URL? = {
        let bundle: Bundle
        #if SWIFT_PACKAGE
        bundle = .module
        #else
        bundle = .main
        #endif
        return bundle.url(forResource: "rest-background-snow-desert", withExtension: "jpg",
                          subdirectory: "Backgrounds")
            ?? bundle.url(forResource: "rest-background-snow-desert", withExtension: "jpg")
    }()

    static let image: NSImage? = url.flatMap(NSImage.init(contentsOf:))
}

private struct AtmosphericRestFrame: View {
    let atmosphere: RestAtmosphere
    let time: TimeInterval
    let animated: Bool

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                background
                switch atmosphere {
                case .moonlight:
                    MoonlightAtmosphere(time: time)
                case .windowLeaves:
                    SunnyLeafVideoBackdrop(kind: .windowShadows, animated: animated, fallbackTime: time)
                case .sunny:
                    SunnyLeafVideoBackdrop(kind: .fallingLeaves, animated: animated, fallbackTime: time)
                case .rainy:
                    RainGlassMetalBackdrop(animated: animated) {
                        RainyAtmosphere(time: time)
                    }
                case .snowy:
                    SnowfallMetalBackdrop(animated: animated) {
                        SnowyAtmosphere(time: time)
                    }
                case .cloudTrain:
                    CloudTrainMetalBackdrop(animated: animated)
                }
                focusField(size: proxy.size)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
    }

    @ViewBuilder private var background: some View {
        switch atmosphere {
        case .moonlight:
            LinearGradient(colors: [Color(hex: 0x08090A), Color(hex: 0x11151A), Color(hex: 0x08090A)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        case .windowLeaves:
            Color(hex: 0xF5F4F0)
        case .sunny:
            Color(hex: 0xF2EFE9)
        case .rainy:
            LinearGradient(
                colors: [Color(hex: 0x3F4955), Color(hex: 0x59636D), Color(hex: 0x434C57)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .snowy:
            GeometryReader { proxy in
                Group {
                    if let image = SnowyRestBackground.image {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: proxy.size.width, height: proxy.size.height)
                            .clipped()
                    } else {
                        LinearGradient(colors: [Color(hex: 0x40546A), Color(hex: 0x4B5361), Color(hex: 0x59545A)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
                .overlay {
                    LinearGradient(
                        colors: [Color(hex: 0x182638).opacity(0.38),
                                 Color.black.opacity(0.22), Color.black.opacity(0.31)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
                .overlay {
                    RadialGradient(
                        colors: [Color.black.opacity(0.34), .clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: max(360, proxy.size.width * 0.42)
                    )
                }
            }
        case .cloudTrain:
            Color(hex: 0xEAA987)
        }
    }

    @ViewBuilder private func focusField(size: CGSize) -> some View {
        switch atmosphere {
        case .moonlight:
            RadialGradient(colors: [Color.black.opacity(0.18), .clear], center: .center,
                           startRadius: 0, endRadius: max(240, size.width * 0.35))
        case .windowLeaves, .sunny:
            Color.clear
        case .rainy:
            Color.clear
        case .snowy:
            Color.clear
        case .cloudTrain:
            Color.clear
        }
    }
}

private struct MoonlightAtmosphere: View {
    let time: TimeInterval

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Canvas { context, size in
                    for index in 0..<92 {
                        let x = unit(index * 47 + 5) * size.width
                        let y = unit(index * 83 + 19) * size.height
                        let pulse = 0.42 + 0.58 * (0.5 + 0.5 * sin(time * (0.7 + unit(index) * 1.2) + Double(index)))
                        let radius = 0.55 + unit(index * 31) * 1.45
                        context.fill(Path(ellipseIn: CGRect(x: x - radius, y: y - radius,
                                                            width: radius * 2, height: radius * 2)),
                                     with: .color(Color.white.opacity(0.18 + pulse * 0.58)))
                    }
                }

                Circle()
                    .fill(Color(hex: 0xE5E1D5))
                    .overlay {
                        ZStack {
                            Circle().fill(Color.black.opacity(0.055)).frame(width: 19, height: 15).offset(x: -18, y: -12)
                            Circle().fill(Color.black.opacity(0.04)).frame(width: 12, height: 10).offset(x: 17, y: 19)
                            Circle().fill(Color.white.opacity(0.12)).frame(width: 22, height: 18).offset(x: 12, y: -22)
                        }
                    }
                    .frame(width: min(132, proxy.size.width * 0.13))
                    .shadow(color: Color(hex: 0xDDE4FF).opacity(0.40), radius: 34)
                    .position(x: proxy.size.width * 0.74, y: proxy.size.height * 0.16)
            }
        }
    }
}

struct SunnyAtmosphereFallback: View {
    let time: TimeInterval

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)),
                         with: .color(Color(hex: 0xF4F2EC)))

            drawLeafLayer(
                in: &context,
                size: size,
                leaves: Self.distantLeaves,
                branches: Self.distantBranches,
                color: Color(hex: 0x77796F).opacity(0.16),
                blur: max(16, size.width / 82),
                offset: CGSize(width: sin(time * 0.045) * 7, height: cos(time * 0.038) * 4),
                angle: sin(time * 0.032) * 0.65
            )

            drawLeafLayer(
                in: &context,
                size: size,
                leaves: Self.nearLeaves,
                branches: Self.nearBranches,
                color: Color(hex: 0x686B62).opacity(0.17),
                blur: max(11, size.width / 112),
                offset: CGSize(width: sin(time * 0.062 + 1.2) * 5,
                               height: cos(time * 0.051 + 0.8) * 3),
                angle: sin(time * 0.041 + 0.7) * 0.48
            )

            context.fill(
                Path(ellipseIn: CGRect(x: size.width * -0.12, y: size.height * 0.20,
                                       width: size.width * 0.86, height: size.height * 0.92)),
                with: .radialGradient(
                    Gradient(colors: [Color.white.opacity(0.07), .clear]),
                    center: CGPoint(x: size.width * 0.30, y: size.height * 0.53),
                    startRadius: 0,
                    endRadius: max(size.width, size.height) * 0.62
                )
            )
        }
    }

    private func drawLeafLayer(
        in context: inout GraphicsContext,
        size: CGSize,
        leaves: [LeafSpec],
        branches: [BranchSpec],
        color: Color,
        blur: CGFloat,
        offset: CGSize,
        angle: Double
    ) {
        var layer = context
        layer.translateBy(x: size.width * 0.72 + offset.width, y: size.height * 0.10 + offset.height)
        layer.rotate(by: .degrees(angle))
        layer.translateBy(x: -size.width * 0.72, y: -size.height * 0.10)
        layer.addFilter(.blur(radius: blur))

        for branch in branches {
            var path = Path()
            path.move(to: point(branch.start, in: size))
            path.addCurve(to: point(branch.end, in: size),
                          control1: point(branch.control1, in: size),
                          control2: point(branch.control2, in: size))
            layer.stroke(path, with: .color(color),
                         style: StrokeStyle(lineWidth: max(3, branch.width * size.width), lineCap: .round))
        }

        for leaf in leaves {
            var leafContext = layer
            let center = point(leaf.center, in: size)
            leafContext.translateBy(x: center.x, y: center.y)
            leafContext.rotate(by: .degrees(leaf.rotation))
            let rect = CGRect(x: -leaf.size.width * size.width / 2,
                              y: -leaf.size.height * size.height / 2,
                              width: leaf.size.width * size.width,
                              height: leaf.size.height * size.height)
            leafContext.fill(Path(ellipseIn: rect), with: .color(color))
        }
    }

    private func point(_ point: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(x: point.x * size.width, y: point.y * size.height)
    }

    private struct LeafSpec {
        let center: CGPoint
        let size: CGSize
        let rotation: Double
    }

    private struct BranchSpec {
        let start: CGPoint
        let control1: CGPoint
        let control2: CGPoint
        let end: CGPoint
        let width: CGFloat
    }

    private static let distantBranches = [
        BranchSpec(start: CGPoint(x: 0.28, y: -0.09), control1: CGPoint(x: 0.34, y: 0.13),
                   control2: CGPoint(x: 0.45, y: 0.34), end: CGPoint(x: 0.64, y: 0.62), width: 0.008),
        BranchSpec(start: CGPoint(x: 0.43, y: -0.08), control1: CGPoint(x: 0.50, y: 0.08),
                   control2: CGPoint(x: 0.57, y: 0.28), end: CGPoint(x: 0.78, y: 0.48), width: 0.010),
        BranchSpec(start: CGPoint(x: 0.58, y: 0.24), control1: CGPoint(x: 0.70, y: 0.18),
                   control2: CGPoint(x: 0.80, y: 0.08), end: CGPoint(x: 0.88, y: -0.04), width: 0.007),
        BranchSpec(start: CGPoint(x: 0.69, y: 0.38), control1: CGPoint(x: 0.80, y: 0.46),
                   control2: CGPoint(x: 0.88, y: 0.61), end: CGPoint(x: 0.96, y: 0.78), width: 0.008)
    ]

    private static let distantLeaves = [
        LeafSpec(center: CGPoint(x: 0.31, y: 0.04), size: CGSize(width: 0.12, height: 0.21), rotation: 32),
        LeafSpec(center: CGPoint(x: 0.38, y: 0.18), size: CGSize(width: 0.14, height: 0.23), rotation: -34),
        LeafSpec(center: CGPoint(x: 0.47, y: 0.31), size: CGSize(width: 0.13, height: 0.22), rotation: 38),
        LeafSpec(center: CGPoint(x: 0.56, y: 0.45), size: CGSize(width: 0.15, height: 0.24), rotation: -31),
        LeafSpec(center: CGPoint(x: 0.64, y: 0.58), size: CGSize(width: 0.14, height: 0.23), rotation: 34),
        LeafSpec(center: CGPoint(x: 0.43, y: 0.03), size: CGSize(width: 0.12, height: 0.20), rotation: -31),
        LeafSpec(center: CGPoint(x: 0.53, y: 0.10), size: CGSize(width: 0.10, height: 0.19), rotation: 30),
        LeafSpec(center: CGPoint(x: 0.60, y: 0.19), size: CGSize(width: 0.13, height: 0.22), rotation: -36),
        LeafSpec(center: CGPoint(x: 0.67, y: 0.27), size: CGSize(width: 0.12, height: 0.21), rotation: 42),
        LeafSpec(center: CGPoint(x: 0.75, y: 0.34), size: CGSize(width: 0.15, height: 0.23), rotation: -38),
        LeafSpec(center: CGPoint(x: 0.83, y: 0.18), size: CGSize(width: 0.16, height: 0.25), rotation: 33),
        LeafSpec(center: CGPoint(x: 0.92, y: 0.05), size: CGSize(width: 0.15, height: 0.24), rotation: -18),
        LeafSpec(center: CGPoint(x: 0.84, y: 0.48), size: CGSize(width: 0.15, height: 0.25), rotation: 38),
        LeafSpec(center: CGPoint(x: 0.91, y: 0.59), size: CGSize(width: 0.18, height: 0.27), rotation: -28),
        LeafSpec(center: CGPoint(x: 1.01, y: 0.72), size: CGSize(width: 0.18, height: 0.30), rotation: 28)
    ]

    private static let nearBranches = [
        BranchSpec(start: CGPoint(x: 0.95, y: -0.05), control1: CGPoint(x: 0.91, y: 0.18),
                   control2: CGPoint(x: 0.83, y: 0.42), end: CGPoint(x: 0.72, y: 0.70), width: 0.006),
        BranchSpec(start: CGPoint(x: 0.80, y: 0.47), control1: CGPoint(x: 0.86, y: 0.58),
                   control2: CGPoint(x: 0.93, y: 0.74), end: CGPoint(x: 0.98, y: 0.94), width: 0.005)
    ]

    private static let nearLeaves = [
        LeafSpec(center: CGPoint(x: 0.95, y: 0.10), size: CGSize(width: 0.11, height: 0.18), rotation: 31),
        LeafSpec(center: CGPoint(x: 0.88, y: 0.24), size: CGSize(width: 0.10, height: 0.18), rotation: -37),
        LeafSpec(center: CGPoint(x: 0.83, y: 0.39), size: CGSize(width: 0.12, height: 0.19), rotation: 29),
        LeafSpec(center: CGPoint(x: 0.77, y: 0.53), size: CGSize(width: 0.11, height: 0.19), rotation: -32),
        LeafSpec(center: CGPoint(x: 0.73, y: 0.68), size: CGSize(width: 0.13, height: 0.21), rotation: 38),
        LeafSpec(center: CGPoint(x: 0.87, y: 0.61), size: CGSize(width: 0.11, height: 0.19), rotation: -31),
        LeafSpec(center: CGPoint(x: 0.93, y: 0.76), size: CGSize(width: 0.13, height: 0.22), rotation: 34),
        LeafSpec(center: CGPoint(x: 0.99, y: 0.91), size: CGSize(width: 0.14, height: 0.23), rotation: -27)
    ]
}

enum RainMotion {
    static let framesPerSecond = 30.0
    static let frameInterval = 1.0 / framesPerSecond
    static let nearDropCount = 28
    static let middleDropCount = 64
    static let distantDropCount = 80
    static let totalDropCount = nearDropCount + middleDropCount + distantDropCount
    static let timeScale = 6.0
}

private struct RainyAtmosphere: View {
    let time: TimeInterval

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                RainFog(time: time, size: proxy.size)
                Canvas { context, size in
                    drawRain(in: &context, size: size)
                }
            }
        }
    }

    private func drawRain(in context: inout GraphicsContext, size: CGSize) {
        let layers = [
            RainLayer(count: RainMotion.nearDropCount, length: 18...30, speed: 18, width: 1.05,
                      color: Color(red: 200 / 255, green: 210 / 255, blue: 225 / 255),
                      alpha: 0.22...0.40, splashChance: 0.16),
            RainLayer(count: RainMotion.middleDropCount, length: 10...19, speed: 13, width: 0.72,
                      color: Color(red: 185 / 255, green: 195 / 255, blue: 212 / 255),
                      alpha: 0.12...0.24, splashChance: 0.04),
            RainLayer(count: RainMotion.distantDropCount, length: 5...11, speed: 9, width: 0.42,
                      color: Color(red: 170 / 255, green: 180 / 255, blue: 200 / 255),
                      alpha: 0.05...0.13, splashChance: 0)
        ]

        var globalIndex = 0
        for (layerIndex, layer) in layers.enumerated() {
            for _ in 0..<layer.count {
                let seed = globalIndex + layerIndex * 1_003
                let length = interpolate(layer.length, unit(seed * 23 + 5))
                let speed = layer.speed * (1 + unit(seed * 17 + 9) * 0.4)
                let drift = 1.2 + unit(seed * 31 + 13) * 1.2
                let cycle = size.height + length + 80
                let distance = unit(seed * 41 + 3) * cycle + CGFloat(time * RainMotion.timeScale) * speed
                let phase = positiveRemainder(distance, cycle)
                let y = phase - length - 40
                let initialX = unit(seed * 67 + 11) * (size.width + 60) - 30
                let framesIntoCycle = phase / speed
                let x = positiveRemainder(initialX + drift * framesIntoCycle + 30,
                                          size.width + 60) - 30
                let alpha = interpolate(layer.alpha, unit(seed * 29 + 7))
                var drop = Path()
                drop.move(to: CGPoint(x: x, y: y))
                drop.addLine(to: CGPoint(x: x + drift * (length / speed), y: y + length))
                context.stroke(drop, with: .color(layer.color.opacity(alpha)),
                               style: StrokeStyle(lineWidth: layer.width + unit(seed * 37) * 0.15,
                                                  lineCap: .round))

                if unit(seed * 53 + 17) < layer.splashChance {
                    drawSplash(
                        in: &context,
                        size: size,
                        seed: seed,
                        distanceAfterImpact: y + length - size.height,
                        x: x
                    )
                }
                globalIndex += 1
            }
        }
    }

    private func drawSplash(
        in context: inout GraphicsContext,
        size: CGSize,
        seed: Int,
        distanceAfterImpact: CGFloat,
        x: CGFloat
    ) {
        let travel = 18 + unit(seed * 71 + 19) * 12
        guard distanceAfterImpact >= 0, distanceAfterImpact < travel else { return }
        let progress = distanceAfterImpact / travel
        let maxRadius = 2 + unit(seed * 79 + 23) * 3
        let radius = maxRadius * progress
        let opacity = (0.2 + unit(seed * 83 + 29) * 0.15) * (1 - progress)
        let rect = CGRect(x: x - radius * 1.5, y: size.height - 2 - radius * 0.5,
                          width: radius * 3, height: radius)
        context.stroke(Path(ellipseIn: rect),
                       with: .color(Color(red: 180 / 255, green: 190 / 255, blue: 205 / 255)
                        .opacity(opacity)), lineWidth: 0.5)
    }

    private func interpolate(_ range: ClosedRange<CGFloat>, _ progress: CGFloat) -> CGFloat {
        range.lowerBound + (range.upperBound - range.lowerBound) * progress
    }

    private func positiveRemainder(_ value: CGFloat, _ divisor: CGFloat) -> CGFloat {
        let remainder = value.truncatingRemainder(dividingBy: divisor)
        return remainder >= 0 ? remainder : remainder + divisor
    }
}

private struct RainLayer {
    let count: Int
    let length: ClosedRange<CGFloat>
    let speed: CGFloat
    let width: CGFloat
    let color: Color
    let alpha: ClosedRange<CGFloat>
    let splashChance: CGFloat
}

private struct RainFog: View {
    let time: TimeInterval
    let size: CGSize

    private var progress: CGFloat {
        CGFloat(0.5 - cos(time * .pi / 40) * 0.5)
    }

    var body: some View {
        ZStack {
            fogSpot(color: Color(red: 70 / 255, green: 80 / 255, blue: 95 / 255).opacity(0.15),
                    width: 1.0, height: 0.90, x: 0.50, y: 1.0)
            fogSpot(color: Color(red: 60 / 255, green: 70 / 255, blue: 85 / 255).opacity(0.08),
                    width: 0.70, height: 0.56, x: 0.20, y: 0.85)
            fogSpot(color: Color(red: 55 / 255, green: 65 / 255, blue: 80 / 255).opacity(0.06),
                    width: 0.60, height: 0.48, x: 0.80, y: 0.90)
        }
        .offset(x: size.width * (-0.008 + progress * 0.016))
        .opacity(0.74 + progress * 0.18)
    }

    private func fogSpot(color: Color, width: CGFloat, height: CGFloat,
                         x: CGFloat, y: CGFloat) -> some View {
        RadialGradient(colors: [color, .clear], center: .center,
                       startRadius: 0, endRadius: max(size.width, size.height) * 0.5)
            .frame(width: size.width * width, height: size.height * height)
            .position(x: size.width * x, y: size.height * y)
    }
}

private struct SnowyAtmosphere: View {
    let time: TimeInterval

    var body: some View {
        Canvas { context, size in
            for index in 0..<88 {
                let depth = 0.35 + unit(index * 31) * 0.9
                let speed = 0.018 + depth * 0.035
                let travel = (unit(index * 59 + 7) + time * speed).truncatingRemainder(dividingBy: 1.10)
                let drift = sin(time * (0.32 + depth * 0.18) + Double(index)) * (10 + depth * 18)
                let x = unit(index * 73 + 17) * size.width + drift
                let y = CGFloat(travel) * (size.height + 80) - 40
                let radius = 1.1 + depth * 2.9
                let opacity = 0.32 + depth * 0.46
                context.fill(Path(ellipseIn: CGRect(x: x - radius, y: y - radius,
                                                    width: radius * 2, height: radius * 2)),
                             with: .color(Color.white.opacity(opacity)))
                if index.isMultiple(of: 11) {
                    var flakeContext = context
                    flakeContext.translateBy(x: x, y: y)
                    for angle in [0.0, Double.pi / 3, Double.pi * 2 / 3] {
                        var arm = Path()
                        arm.move(to: CGPoint(x: -radius * 2.2 * cos(angle), y: -radius * 2.2 * sin(angle)))
                        arm.addLine(to: CGPoint(x: radius * 2.2 * cos(angle), y: radius * 2.2 * sin(angle)))
                        flakeContext.stroke(arm, with: .color(Color.white.opacity(opacity * 0.9)), lineWidth: 0.8)
                    }
                }
            }
        }
    }
}

private func unit(_ seed: Int) -> CGFloat {
    let value = sin(Double(seed) * 12.9898) * 43_758.5453
    return CGFloat(value - floor(value))
}

private extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

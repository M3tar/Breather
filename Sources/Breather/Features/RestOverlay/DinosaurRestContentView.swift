import SwiftUI

struct DinosaurPalette {
    let dark: Bool
    var background: Color { color(0xF2F5EF, 0x17251F) }
    var body: Color { color(0x4B7664, 0x9BCBB2) }
    var belly: Color { color(0xA9DEC1, 0xCEF0D9) }
    var cactus: Color { color(0x3D6650, 0x72A98B) }
    var ground: Color { color(0x75877B, 0x708F7B) }
    var cloud: Color { color(0x6EAA89, 0x83B89B).opacity(0.36) }

    private func color(_ light: UInt32, _ darkValue: UInt32) -> Color {
        let value = dark ? darkValue : light
        return Color(red: Double((value >> 16) & 255) / 255,
                     green: Double((value >> 8) & 255) / 255,
                     blue: Double(value & 255) / 255)
    }
}

struct DinosaurRestContentView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var session: RestOverlaySession
    var compact = false

    private var animated: Bool {
        !reduceMotion && !compact
            && !session.isAnimationPaused && !session.isDismissing
    }

    var body: some View {
        Group {
            if animated && !session.hasSceneStopped {
                TimelineView(.animation(minimumInterval: 1.0 / 30)) { _ in
                    lane(animated: true)
                }
            } else {
                lane(animated: animated)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func lane(animated: Bool) -> some View {
        let frame = session.scene.frame(
            elapsed: session.animationElapsed,
            stopAt: session.sceneStopTime, animated: animated
        )
        return DinosaurLane(frame: frame, palette: DinosaurPalette(dark: colorScheme == .dark), compact: compact)
    }
}

/// Shared code-native pixel artwork: the settings thumbnail and every rest/preview
/// screen use exactly these paths. No per-frame resource loading or raster filtering.
struct DinosaurLane: View {
    let frame: DinosaurSceneModel.Frame
    let palette: DinosaurPalette
    var compact = false
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Canvas { context, size in
            let availableScale = min(size.width / (compact ? 50 : 420), size.height / (compact ? 36 : 90))
            // Integral physical pixels where possible; small thumbnails may use
            // sub-point units but must always fit the entire logical lane.
            let scale = availableScale >= 1 / displayScale
                ? floor(availableScale * displayScale) / displayScale : availableScale
            let width = compact ? 50.0 : DinosaurSceneModel.laneWidth
            let origin = CGPoint(x: ((size.width - width * scale) / 2 * displayScale).rounded() / displayScale,
                                 y: ((size.height - (compact ? 8 : 14) * scale) * displayScale).rounded() / displayScale)
            context.translateBy(x: origin.x, y: origin.y)
            context.scaleBy(x: scale, y: scale)
            let dinosaurX = compact ? 12.0 : DinosaurSceneModel.dinosaurX
            if !compact {
                fill(&context, CGRect(x: 0, y: 0, width: width, height: 0.6), palette.ground)
                for index in 0..<7 {
                    let x = (Double(index) * 64 - frame.groundOffset + 448).truncatingRemainder(dividingBy: 448)
                    fill(&context, CGRect(x: x.rounded(), y: 5 + Double(index % 2) * 3, width: Double(2 + index % 4), height: 1), palette.ground.opacity(0.55))
                }
                cloud(&context, x: 156, y: -55)
                cloud(&context, x: 330, y: -70)
                for obstacle in frame.obstacles {
                    cactus(&context, obstacle: obstacle)
                }
                for x in [35.0, 210, 395] {
                    fill(&context, CGRect(x: x, y: -3, width: 1, height: 3), palette.cactus.opacity(0.6))
                    fill(&context, CGRect(x: x + 2, y: -2, width: 1, height: 2), palette.cactus.opacity(0.6))
                }
            }
            DinosaurPixelArt.draw(in: &context,
                                  origin: CGPoint(x: dinosaurX, y: -28 - frame.jumpHeight.rounded()),
                                  pose: frame.pose, palette: palette)
        }
        .clipped()
    }

    private func fill(_ context: inout GraphicsContext, _ rect: CGRect, _ color: Color) {
        context.fill(Path(rect), with: .color(color))
    }

    private func cactus(_ context: inout GraphicsContext, obstacle: DinosaurSceneModel.Obstacle) {
        let x = obstacle.x.rounded()
        let h = obstacle.height
        for rect in [CGRect(x: x + 4, y: -h, width: 3, height: h),
                     CGRect(x: x, y: -h + 7, width: 2, height: 8),
                     CGRect(x: x + 1, y: -h + 13, width: 4, height: 2),
                     CGRect(x: x + 8, y: -h + 4, width: 2, height: 8),
                     CGRect(x: x + 6, y: -h + 10, width: 3, height: 2)] {
            fill(&context, rect, palette.cactus)
        }
    }

    private func cloud(_ context: inout GraphicsContext, x: Double, y: Double) {
        var path = Path()
        path.move(to: CGPoint(x: x, y: y))
        for point in [(0.0, -2.0), (5, -2), (5, -5), (10, -5), (10, -8), (17, -8),
                      (17, -5), (22, -5), (22, -2), (28, -2), (28, 0), (0, 0)] {
            path.addLine(to: CGPoint(x: x + point.0, y: y + point.1))
        }
        context.stroke(path, with: .color(palette.cloud), lineWidth: 0.6)
    }
}

enum DinosaurPixelArt {
    // A stepped, side-on silhouette, drawn on a 26 × 28 logical-pixel grid.
    private static let silhouette: Path = {
        var path = Path()
        let points: [(Double, Double)] = [
            (14, 0), (24, 0), (24, 2), (26, 2), (26, 10),
            (19, 10), (19, 12), (24, 12), (24, 13), (17, 13),
            (17, 15), (21, 15), (21, 18), (19, 18), (19, 16), (17, 16),
            (17, 20), (15, 20), (15, 22), (12, 22), (12, 24),
            (7, 24), (7, 22), (5, 22), (5, 20), (3, 20), (3, 18),
            (1, 18), (1, 15), (0, 15), (0, 9), (2, 9), (2, 13),
            (4, 13), (4, 15), (7, 15), (7, 13), (10, 13),
            (10, 11), (12, 11), (12, 3), (14, 3)
        ]
        path.move(to: CGPoint(x: points[0].0, y: points[0].1))
        for point in points.dropFirst() { path.addLine(to: CGPoint(x: point.0, y: point.1)) }
        path.closeSubpath()
        return path
    }()

    static func draw(in context: inout GraphicsContext, origin: CGPoint,
                     pose: DinosaurSceneModel.Pose, palette: DinosaurPalette) {
        var ctx = context
        ctx.translateBy(x: origin.x, y: origin.y)
        ctx.fill(silhouette, with: .color(palette.body))
        ctx.fill(Path(CGRect(x: 16, y: 3, width: 2, height: 2)), with: .color(palette.background))
        var belly = Path(CGRect(x: 13, y: 16, width: 2, height: 5))
        belly.addRect(CGRect(x: 11, y: 19, width: 2, height: 3))
        ctx.fill(belly, with: .color(palette.belly))
        let leftLift = pose == .walkA ? 3.0 : 0
        let rightLift = pose == .walkB ? 3.0 : 0
        for (x, lift) in [(7.0, leftLift), (13.0, rightLift)] {
            ctx.fill(Path(CGRect(x: x, y: 22, width: 2, height: 6 - lift)), with: .color(palette.body))
            ctx.fill(Path(CGRect(x: x, y: 26 - lift, width: 4, height: 2)), with: .color(palette.body))
        }
    }
}

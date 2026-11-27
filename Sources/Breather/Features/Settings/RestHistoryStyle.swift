import SwiftUI

/// Resolved colors of the approved week and month prototypes.
struct RestHistoryPalette {
    let scheme: ColorScheme
    var month = false

    fileprivate func color(_ light: UInt32, _ dark: UInt32) -> Color {
        let rgb = scheme == .dark ? dark : light
        return Color(.sRGB, red: Double(rgb >> 16) / 255, green: Double(rgb >> 8 & 255) / 255,
                     blue: Double(rgb & 255) / 255, opacity: 1)
    }

    var weekSelection: Color { color(0xe6f4fe, 0x343638) }
    var paper: Color { color(0xffffff, 0x202226) }
    var panel: Color { color(0xf6f6f7, 0x292c30) }
    var ink: Color { color(0x222427, 0xeff1f3) }
    var muted: Color { color(0x626670, 0xb4bbc4) }
    var line: Color { color(0xdedfe2, 0x40454a) }
    var slate: Color { color(0xf0f0f3, 0x25292d) }
    var completeBar: Color { color(0x12a594, 0x58bdad) }
    var skipBar: Color { color(0xf76b15, 0xe6a06c) }
    var completeText: Color { color(0x0d3d38, 0xbbecdf) }
    var skipText: Color { color(0xcc4e00, 0xffb481) }
    var seal: Color { color(0x83b9b1, 0x73ab9c) }
    var glint: Color { color(0x83bcaf, 0xa5dfd4) }
    var rangeSelection: Color { color(0x006ad8, month ? 0x79b5ff : 0x65adff) }
    var rangeSelectionText: Color { color(0xffffff, 0x202226) }
    var selectionBorder: Color { scheme == .dark ? color(0, 0x79b5ff) : color(0x006ad8, 0) }
    var weekUnderline: Color { color(0x0d74ce, 0xc2bbb1) }
    var weekHover: Color { scheme == .dark ? .white.opacity(8/255) : color(0xf4faff, 0) }
    var awardTitle: Color { color(0x0d3d38, 0xd2f4e9) }
    var awardBody: Color { color(0x0d3d38, 0xc7d1d0) }
    var recordInk: Color { color(0x222427, 0xd1d5da) }
    var pearl: Gradient {
        let dark = scheme == .dark
        return Gradient(stops: [
            .init(color: color(0xebaad9, 0xdf9bb8).opacity(dark ? 1 : 133/255), location: dark ? 0.02 : 0),
            .init(color: color(0xb1c9ff, 0x94b1df).opacity(dark ? 1 : 153/255), location: dark ? 0.29 : 0.28),
            .init(color: color(0x8fefd3, 0x8bc8b8).opacity(dark ? 1 : 135/255), location: dark ? 0.54 : 0.51),
            .init(color: color(0xffe6a1, 0xe9ce95).opacity(dark ? 1 : 136/255), location: dark ? 0.78 : 0.70),
            .init(color: color(0xefb7ed, 0xdca1bd).opacity(dark ? 1 : 153/255), location: 1)
        ])
    }

    func wash(for day: RestDay, card: Bool) -> Color {
        if scheme == .dark {
            if day.events.isEmpty { return color(0, 0x303237) }
            if day.clean { return color(0, 0x285046) }
            return color(0, day.completed == 0 ? 0x553d30 : 0x344558)
        }
        if day.events.isEmpty { return card ? slate : panel }
        if day.clean { return color(0xe0f8f3, 0x25483f) }
        if day.completed == 0 { return card ? color(0xfff1de, 0x302315) : color(0xffefd6, 0x302a27) }
        return card ? color(0xdfeaf4, 0x30404d) : color(0xe7eef5, 0x272a2d)
    }
}

enum RestHistoryMark: View {
    case completed, skipped, seal, glints

    var body: some View {
        Canvas { context, size in
            let base: CGSize
            switch self {
            case .completed, .skipped: base = CGSize(width: 18, height: 18)
            case .seal: base = CGSize(width: 120, height: 120)
            case .glints: base = CGSize(width: 90, height: 58)
            }
            context.scaleBy(x: size.width / base.width, y: size.height / base.height)
            switch self {
            case .completed:
                var path = Path()
                path.move(to: CGPoint(x: 7.3, y: 3.2))
                path.quad(8.2, 9, 13.1, 10.3)
                path.quad(8.2, 11.5, 7.3, 17)
                path.quad(6.4, 11.5, 1.6, 10.3)
                path.quad(6.4, 9, 7.3, 3.2)
                path.closeSubpath()
                path.move(to: CGPoint(x: 14, y: 0.8))
                path.quad(14.6, 3.7, 17.3, 4.6)
                path.quad(14.6, 5.4, 14, 8.5)
                path.quad(13.4, 5.4, 10.6, 4.6)
                path.quad(13.4, 3.7, 14, 0.8)
                context.fill(path, with: .foreground)
            case .skipped:
                var arrow = Path()
                arrow.move(to: CGPoint(x: 1.8, y: 10.2))
                arrow.addCurve(to: CGPoint(x: 15.7, y: 6.8), control1: CGPoint(x: 3.8, y: 3.2), control2: CGPoint(x: 10.5, y: 2.1))
                arrow.move(to: CGPoint(x: 11.9, y: 7.2))
                arrow.addLine(to: CGPoint(x: 16, y: 7.3))
                arrow.addLine(to: CGPoint(x: 15.8, y: 3.2))
                context.stroke(arrow, with: .foreground, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                for x in [6.1, 10.0] {
                    context.fill(Path(roundedRect: CGRect(x: x, y: 9.1, width: 2.2, height: 6.1), cornerRadius: 0.65), with: .foreground)
                }
            case .seal:
                context.stroke(Path(ellipseIn: CGRect(x: 4, y: 4, width: 112, height: 112)), with: .foreground, lineWidth: 3.6)
                var rotated = context
                rotated.translateBy(x: 60, y: 60)
                rotated.rotate(by: .degrees(-31))
                rotated.translateBy(x: -60, y: -60)
                rotated.stroke(Path(ellipseIn: CGRect(x: 13, y: 13, width: 94, height: 94)), with: .foreground,
                               style: StrokeStyle(lineWidth: 1.3, dash: [41, 13, 54, 18, 43, 19, 68, 40]))
                var motif = Path()
                motif.move(to: CGPoint(x: 56, y: 43))
                motif.quad(58, 56, 70, 59)
                motif.quad(58, 61, 56, 75)
                motif.quad(53, 62, 41, 59)
                motif.quad(53, 56, 56, 43)
                motif.move(to: CGPoint(x: 76, y: 48))
                motif.quad(77, 54, 83, 55)
                motif.quad(77, 57, 76, 63)
                motif.quad(75, 57, 69, 55)
                motif.quad(75, 54, 76, 48)
                rotated.fill(motif, with: .foreground)
                context.translateBy(x: 83.25, y: 96.25)
                context.rotate(by: .degrees(14))
                context.fill(Path(CGRect(x: -3.25, y: -3.25, width: 6.5, height: 6.5)), with: .foreground)
            case .glints:
                for (x,y,w,h,alpha) in [(14.0,16.0,6.5,8.0,1.0),(36,9,4,5,0.72),(69,42,4.5,6,0.82)] {
                    var star = Path()
                    star.move(to: CGPoint(x: x, y: y-h))
                    star.quad(x+w*0.18,y-h*0.16,x+w,y)
                    star.quad(x+w*0.18,y+h*0.16,x,y+h)
                    star.quad(x-w*0.18,y+h*0.16,x-w,y)
                    star.quad(x-w*0.18,y-h*0.16,x,y-h)
                    var layer = context
                    layer.opacity = alpha
                    layer.fill(star, with: .foreground)
                }
            }
        }.accessibilityHidden(true)
    }
}

private extension Path {
    mutating func quad(_ cx: CGFloat, _ cy: CGFloat, _ x: CGFloat, _ y: CGFloat) {
        addQuadCurve(to: CGPoint(x: x, y: y), control: CGPoint(x: cx, y: cy))
    }
}

struct RestHistorySurface: View {
    let day: RestDay
    let palette: RestHistoryPalette
    var card = false
    var selected = false
    var highlight: UnitPoint? = nil
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        let tint = palette.wash(for: day, card: card)
        ZStack {
            if reduceTransparency { tint }
            else {
                Canvas { context, size in
                    let angle = (card ? 145.0 : 165.0) * .pi / 180
                    let dx = sin(angle), dy = -cos(angle)
                    let half = (size.width * dx + size.height * dy) / 2
                    let base: Gradient
                    if !card {
                        base = Gradient(colors: [palette.paper, tint.mix(with: palette.panel, by: 0.55, in: .device)])
                    } else if palette.scheme == .dark {
                        base = Gradient(colors: [palette.paper, palette.panel])
                    } else {
                        base = Gradient(stops: [.init(color: palette.paper, location: 0.10),
                                                .init(color: palette.panel, location: 0.62),
                                                .init(color: day.completed == 0 && day.skipped > 0 ? palette.panel : palette.slate, location: 1)])
                    }
                    context.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(base,
                        startPoint: CGPoint(x: size.width/2 - half*dx, y: size.height/2 - half*dy),
                        endPoint: CGPoint(x: size.width/2 + half*dx, y: size.height/2 + half*dy)))
                }
                // CSS radial-gradient(ellipse at top right) uses the farthest corner.
                Canvas { context, size in
                    context.scaleBy(x: size.width, y: size.height)
                    let corner = CGFloat(2).squareRoot()
                    let gradient = Gradient(colors: [tint, tint.opacity(0)])
                    context.fill(Path(CGRect(x: 0, y: 0, width: 1, height: 1)),
                                 with: .radialGradient(gradient, center: CGPoint(x: 1, y: 0),
                                    startRadius: card ? 0 : 0.08 * corner, endRadius: (card ? (palette.scheme == .dark ? 0.64 : 0.58) : 0.86) * corner))
                }
                if card {
                    if palette.scheme == .dark {
                        Canvas { context, size in
                            context.scaleBy(x: size.width, y: size.height)
                            context.fill(Path(CGRect(x: 0, y: 0, width: 1, height: 1)), with: .radialGradient(
                                Gradient(colors: [palette.color(0, 0xeefaff).opacity(18/255), .clear]),
                                center: CGPoint(x: 0.90, y: -0.20), startRadius: 0, endRadius: 0.81))
                        }
                    }
                    RestSurfaceFinish(day: day, palette: palette, pointer: highlight)
                        .id(day.id)
                        .padding(1)
                } else if selected {
                    MonthCellFinish(day: day, palette: palette, pointer: highlight).padding(1)
                    RestGlassEdge(palette: palette, card: false)
                } else {
                    Rectangle().fill(.white.opacity(palette.scheme == .dark ? 18/255 : 166/255))
                        .frame(height: 1).frame(maxHeight: .infinity, alignment: .top)
                }
            }
        }
    }
}

/// CSS gradient angles are measured clockwise from the top of the card.
private struct RestSurfaceFinish: View {
    let day: RestDay
    let palette: RestHistoryPalette
    let pointer: UnitPoint?
    @State private var lastPointer: UnitPoint?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let clean = day.clean
        let dark = palette.scheme == .dark
        let light = pointer ?? (clean ? lastPointer : nil) ?? UnitPoint(x: 0.34, y: 0.22)
        let lustre = Color(red: 1, green: 1, blue: 252/255).opacity(0.96)
        let softBand = dark || clean
        Canvas { context, size in
            let rect = Path(CGRect(origin: .zero, size: size))
            let angle = 115.0 * Double.pi / 180
            let width = size.width * (softBand ? 1.80 : 2.05)
            let height = size.height
            let dx = sin(angle), dy = -cos(angle)
            let extent = (width * dx + height * dy) / 2
            // Centre the 48% colour stop under the pointer on a completed card.
            let cx = clean ? light.x * size.width + 0.04 * extent * dx : width / 2 + (size.width - width) * light.x
            let cy = clean ? light.y * size.height + 0.04 * extent * dy : size.height / 2
            let bandColor = clean ? Color(red: 116/255, green: 202/255, blue: 178/255) : Color(red: 232/255, green: 239/255, blue: 251/255)
            let stops: [Gradient.Stop] = softBand
                ? [.init(color: .clear, location: 0.34), .init(color: bandColor.opacity(40/255), location: 0.48), .init(color: .clear, location: 0.63)]
                : [.init(color: .clear, location: 0.38), .init(color: lustre, location: 0.48),
                   .init(color: .clear, location: 0.56)]
            context.fill(rect, with: .linearGradient(Gradient(stops: stops),
                startPoint: CGPoint(x: cx - extent * dx, y: cy - extent * dy),
                endPoint: CGPoint(x: cx + extent * dx, y: cy + extent * dy)))
            if !softBand {
                // CSS ellipse, sized to the corner farthest from the pointer.
                let rx = max(light.x, 1 - light.x) * size.width
                let ry = max(light.y, 1 - light.y) * size.height
                context.translateBy(x: light.x * size.width, y: light.y * size.height)
                context.scaleBy(x: rx, y: ry)
                context.fill(Path(CGRect(x: -2, y: -2, width: 4, height: 4)),
                             with: .radialGradient(Gradient(colors: [lustre, .clear]), center: .zero,
                                                   startRadius: 0, endRadius: sqrt(2) * 0.60))
            }
        }
        .mask {
            Canvas { context, size in
                context.scaleBy(x: size.width, y: size.height)
                let radius = sqrt(0.5)
                let mask = Gradient(colors: [.black.opacity(0.42), .black])
                context.fill(Path(CGRect(x: 0, y: 0, width: 1, height: 1)),
                             with: .radialGradient(mask, center: CGPoint(x: 0.5, y: 0.5),
                                                   startRadius: radius * 0.20, endRadius: radius * 0.85))
            }
        }
        .animation(clean && !reduceMotion ? .easeOut(duration: pointer == nil ? 0.27 : 0.10) : nil) {
            $0.opacity(opacity)
        }
        .onChange(of: pointer, initial: true) {
            if clean, let pointer { lastPointer = pointer }
        }
        .allowsHitTesting(false)
    }
    private var opacity: Double {
        if day.clean {
            return pointer == nil ? 0 : 0.60
        }
        if palette.scheme == .dark { return pointer == nil ? 0.38 : 0.60 }
        if day.completed > 0 && day.skipped > 0 { return pointer == nil ? 0.32 : 0.54 }
        return pointer == nil ? 0.72 : 0.96
    }

}

struct CompletedCardStarLight: View {
    let pointer: UnitPoint?
    @State private var lastPointer = UnitPoint.center
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Color(red: 239/255, green: 242/255, blue: 242/255)
            .overlay {
                Canvas { context, size in
                    let point = pointer ?? lastPointer
                    let angle = 115.0 * Double.pi / 180
                    let x = point.x * size.width, y = point.y * size.height
                    let dx = 45 * sin(angle), dy = -45 * cos(angle)
                    let mint = Color(red: 88/255, green: 177/255, blue: 151/255)
                    context.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(
                        Gradient(colors: [mint.opacity(0), mint, mint.opacity(0)]),
                        startPoint: CGPoint(x: x - dx, y: y - dy), endPoint: CGPoint(x: x + dx, y: y + dy)))
                }
                .animation(reduceMotion ? nil : .easeOut(duration: 0.26)) {
                    $0.opacity(pointer == nil ? 0 : 1)
                }
            }
            .onChange(of: pointer, initial: true) {
                if let pointer { lastPointer = pointer }
            }
    }
}

struct MonthCellStarLight: View {
    let pointer: UnitPoint
    let palette: RestHistoryPalette

    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            context.fill(Path(rect), with: .color(palette.glint))
            context.translateBy(x: pointer.x * size.width, y: pointer.y * size.height)
            context.scaleBy(x: max(pointer.x, 1 - pointer.x) * size.width,
                            y: max(pointer.y, 1 - pointer.y) * size.height)
            let light = palette.color(0x549c91, 0xeffffb)
            context.fill(Path(CGRect(x: -2, y: -2, width: 4, height: 4)),
                         with: .radialGradient(Gradient(colors: [light, light.opacity(0)]), center: .zero,
                                               startRadius: 0, endRadius: sqrt(2) * 0.75))
        }
        .allowsHitTesting(false)
    }
}

/// Match the card's CSS perspective(1050px) rotateX(...) rotateY(...).
struct RestCardTilt: GeometryEffect {
    var animatableData: AnimatablePair<Double, Double>

    let perspective: CGFloat

    init(pointer: UnitPoint?, degrees: Double = 10, perspective: CGFloat = 1050) {
        self.perspective = perspective
        animatableData = AnimatablePair((0.5 - (pointer?.y ?? 0.5)) * degrees * .pi / 180,
                                        ((pointer?.x ?? 0.5) - 0.5) * degrees * .pi / 180)
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        return ProjectionTransform(transform(around: CGPoint(x: size.width / 2, y: size.height / 2)))
    }

    func transform(around center: CGPoint) -> CATransform3D {
        if animatableData == .zero { return CATransform3DIdentity }
        var camera = CATransform3DIdentity
        camera.m34 = -1 / perspective
        var transform = CATransform3DRotate(camera, animatableData.first, 1, 0, 0)
        transform = CATransform3DRotate(transform, animatableData.second, 0, 1, 0)
        transform = CATransform3DTranslate(transform, -center.x, -center.y, 0)
        let origin = CATransform3DMakeTranslation(center.x, center.y, 0)
        return CATransform3DConcat(transform, origin)
    }
}

// Transform the live AppKit view hierarchy so the embedded scroll view continues
// receiving wheel events while its text and the rest of the card tilt together.
struct TiltedRestDetailCard<Card: View>: NSViewControllerRepresentable {
    let content: Card
    let pointer: UnitPoint?
    let animated: Bool

    func makeNSViewController(context: Context) -> NSHostingController<Card> {
        let controller = NSHostingController(rootView: content)
        controller.view.wantsLayer = true
        return controller
    }

    func updateNSViewController(_ controller: NSHostingController<Card>, context: Context) {
        controller.rootView = content
        guard let layer = controller.view.layer else { return }
        // An AppKit backing layer's anchor may be at its origin.
        let bounds = layer.bounds
        let dx = bounds.width * (0.5 - layer.anchorPoint.x)
        let dy = bounds.height * (0.5 - layer.anchorPoint.y)
        let centered = RestCardTilt(pointer: pointer).transform(around: CGPoint(x: dx, y: dy))
        guard !CATransform3DEqualToTransform(layer.transform, centered) else { return }
        if animated {
            let animation = CABasicAnimation(keyPath: "transform")
            animation.fromValue = NSValue(caTransform3D: layer.presentation()?.transform ?? layer.transform)
            animation.toValue = NSValue(caTransform3D: centered)
            animation.duration = 0.18
            animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
            layer.add(animation, forKey: "restCardTilt")
        } else {
            layer.removeAnimation(forKey: "restCardTilt")
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.transform = centered
        CATransaction.commit()
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsViewController: NSHostingController<Card>,
                      context: Context) -> CGSize? {
        nsViewController.sizeThatFits(in: proposal.replacingUnspecifiedDimensions(by: CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)))
    }
}

/// Keep the tracking rectangle stationary while the surface underneath tilts.
/// The transparent overlay passes clicks, wheel events and accessibility to the card.
struct RestHistoryPointerArea: NSViewRepresentable {
    let changed: (UnitPoint?) -> Void

    func makeNSView(context: Context) -> RestHistoryTrackingView {
        let view = RestHistoryTrackingView()
        view.setAccessibilityElement(false)
        view.changed = changed
        return view
    }

    func updateNSView(_ view: RestHistoryTrackingView, context: Context) {
        view.changed = changed
    }
}

final class RestHistoryTrackingView: NSView {
    var changed: ((UnitPoint?) -> Void)?
    private var area: NSTrackingArea?
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area { removeTrackingArea(area) }
        let next = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(next)
        area = next
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard bounds.contains(point), bounds.width > 0, bounds.height > 0 else {
            changed?(nil)
            return
        }
        changed?(UnitPoint(x: point.x / bounds.width, y: point.y / bounds.height))
    }
    override func mouseExited(with event: NSEvent) { changed?(nil) }
}

struct RestGlassEdge: View {
    let palette: RestHistoryPalette
    let card: Bool

    var body: some View {
        let dark = palette.scheme == .dark
        let shape = RoundedRectangle(cornerRadius: card ? 12 : 5)
        ZStack {
            if card { shape.strokeBorder(palette.completeText.opacity(0.14), lineWidth: 1) }
            shape.stroke(palette.color(0xffffff, 0xeffaff).opacity(dark ? (card ? 0.22 : 0.26) : 0.87),
                         lineWidth: 3).offset(y: 1.5).blur(radius: 0.5)
                .mask(alignment: .top) { Rectangle().frame(height: 2.5) }
            if dark {
                shape.stroke(.black.opacity(0.40), lineWidth: 3).offset(y: -1).blur(radius: 1)
                    .mask(alignment: .bottom) { Rectangle().frame(height: 3) }
            }
        }.clipShape(shape).allowsHitTesting(false)
    }
}

private struct MonthCellFinish: View {
    let day: RestDay
    let palette: RestHistoryPalette
    let pointer: UnitPoint?
    @State private var lastX: CGFloat = 0.5

    var body: some View {
        let dark = palette.scheme == .dark
        ZStack {
            if !day.clean {
                band(palette.pearl, angle: 116)
                    .mask {
                        Canvas { ctx, size in
                            ctx.scaleBy(x: size.width, y: size.height)
                            ctx.fill(Path(CGRect(x: 0, y: 0, width: 1, height: 1)), with: .radialGradient(
                                Gradient(colors: [.black.opacity(dark ? 1/3 : 0.16), .black]),
                                center: CGPoint(x: 0.5, y: dark ? 0.46 : 0.5),
                                startRadius: dark ? 0 : 0.141, endRadius: dark ? 0.70 : 0.601))
                        }
                    }.opacity(dark ? 0.27 : 0.63)
            }
            let x = pointer?.x ?? lastX
            band(reflection, angle: day.clean ? 113 : 112, width: day.clean ? 1.90 : 1.80,
                 position: day.clean && dark ? x : 1 - x)
                .opacity(pointer == nil ? 0 : (day.clean ? (dark ? 0.34 : 0.54) : (dark ? 0.23 : 0.52)))
                .animation(.easeInOut(duration: 0.14), value: pointer == nil)
        }
        .onChange(of: pointer) { _, point in if let point { lastX = point.x } }
        .allowsHitTesting(false)
    }

    private var reflection: Gradient {
        let dark = palette.scheme == .dark
        let tint = palette.wash(for: day, card: false)
        if dark && day.clean {
            return Gradient(stops: [.init(color: .clear, location: 0.26),
                .init(color: tint.mix(with: .white, by: 0.2, in: .device), location: 0.46),
                .init(color: .white.opacity(34/255), location: 0.51), .init(color: .clear, location: 0.69)])
        }
        if dark {
            let light = tint.mix(with: palette.color(0, 0xede9df), by: 0.38, in: .device)
            return Gradient(stops: [.init(color: .clear, location: 0.30), .init(color: light.opacity(0.28), location: 0.42),
                .init(color: light, location: 0.50), .init(color: light.opacity(0.28), location: 0.58),
                .init(color: .clear, location: 0.70)])
        }
        var stops: [Gradient.Stop] = [.init(color: .clear, location: day.clean ? 0.25 : 0.27),
            .init(color: .white.opacity(48/255), location: 0.40), .init(color: .white.opacity(224/255), location: 0.48),
            .init(color: .white, location: 0.50), .init(color: .white, location: 0.53)]
        if !day.clean { stops.append(.init(color: .white.opacity(85/255), location: 0.60)) }
        stops.append(.init(color: .clear, location: day.clean ? 0.70 : 0.73))
        return Gradient(stops: stops)
    }

    private func band(_ gradient: Gradient, angle: Double, width: CGFloat = 1, position: CGFloat = 0.5) -> some View {
        Canvas { ctx, size in
            let radians = angle * .pi / 180
            let dx = sin(radians), dy = -cos(radians)
            let w = width * size.width
            let half = (w * dx + size.height * dy) / 2
            let x = w / 2 + (size.width - w) * position
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(gradient,
                startPoint: CGPoint(x: x - half * dx, y: size.height / 2 - half * dy),
                endPoint: CGPoint(x: x + half * dx, y: size.height / 2 + half * dy)))
        }
    }
}

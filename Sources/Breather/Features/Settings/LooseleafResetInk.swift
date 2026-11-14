import AppKit
import JavaScriptCore
import SwiftUI

/// Runs the bundled, original Looseleaf engine at the actual text size.
/// Access to JavaScriptCore and its drawing cache is serialized for text rendering.
final class LooseleafResetInk: @unchecked Sendable {
    static let shared = LooseleafResetInk()
    private let lock = NSLock()
    private let engine: JSContext
    private let dryGrain: CGImage
    private let cache = NSCache<NSString, Drawing>()

    final class Drawing: NSObject {
        let strokes: [InkStroke]
        init(strokes: [InkStroke]) { self.strokes = strokes }
    }

    struct InkStroke {
        let image: CGImage
        let timing: ClosedRange<CGFloat>
        let horizontalExtent: ClosedRange<CGFloat>

        func revealRect(in canvas: CGRect, through amount: CGFloat) -> CGRect {
            CGRect(x: canvas.minX + horizontalExtent.lowerBound, y: canvas.minY,
                   width: (horizontalExtent.upperBound - horizontalExtent.lowerBound) * amount,
                   height: canvas.height)
        }
    }

    private struct StrokeData: Decodable {
        let timing: [CGFloat]
        let layers: [Layer]

        struct Layer: Decodable {
            let opacity: CGFloat
            let commands: [[CGFloat]]

            var path: CGPath {
                let path = CGMutablePath()
                for command in commands {
                    switch command[0] {
                    case 0: path.move(to: CGPoint(x: command[1], y: command[2]))
                    case 1: path.addLine(to: CGPoint(x: command[1], y: command[2]))
                    case 2:
                        path.addQuadCurve(to: CGPoint(x: command[3], y: command[4]),
                                          control: CGPoint(x: command[1], y: command[2]))
                    case 3: path.closeSubpath()
                    default: preconditionFailure("Unsupported Looseleaf path command")
                    }
                }
                return path
            }
        }
    }

    private init() {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle.main
        #endif
        guard let sourceURL = bundle.url(forResource: "reset-ink", withExtension: "js", subdirectory: "Looseleaf")
                ?? bundle.url(forResource: "reset-ink", withExtension: "js"),
              let source = try? String(contentsOf: sourceURL, encoding: .utf8),
              let engine = JSContext(),
              let grainURL = bundle.url(forResource: "waxy", withExtension: "png", subdirectory: "Looseleaf")
                ?? bundle.url(forResource: "waxy", withExtension: "png"),
              let image = NSImage(contentsOf: grainURL)?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { preconditionFailure("Missing bundled Looseleaf pen resources") }
        engine.evaluateScript(source)
        precondition(engine.exception == nil, "Unable to load Looseleaf pen engine")
        self.engine = engine
        dryGrain = Self.dryGrainMask(image)
        cache.totalCostLimit = 12 * 1024 * 1024
        cache.countLimit = 128
    }

    func drawing(settingID: String, size: CGSize, colorScheme: ColorScheme) -> Drawing {
        lock.withLock {
            let key = "\(settingID)|\(size.width)|\(size.height)|\(colorScheme)" as NSString
            if let drawing = cache.object(forKey: key) { return drawing }
            let output = engine.objectForKeyedSubscript("breatherResetInk")?
                .call(withArguments: [settingID, size.width, size.height])?.toString()
            guard engine.exception == nil, let output,
                  let data = output.data(using: .utf8),
                  let strokes = try? JSONDecoder().decode([StrokeData].self, from: data)
            else { preconditionFailure("Unable to draw Looseleaf reset annotation") }
            let canvasSize = CGSize(width: size.width + 8, height: size.height + 6)
            let seed = settingID.utf8.reduce(UInt32(2_166_136_261)) { ($0 ^ UInt32($1)) &* 16_777_619 }
            let phase = Int((seed &* 0x9e37_79b1) >> 7) % 6
            let images = strokes.map {
                render($0, size: canvasSize, grainPhase: phase, colorScheme: colorScheme)
            }
            let drawing = Drawing(strokes: images)
            cache.setObject(drawing, forKey: key, cost: images.reduce(0) { $0 + $1.image.bytesPerRow * $1.image.height })
            return drawing
        }
    }

    private func render(_ stroke: StrokeData, size: CGSize, grainPhase: Int, colorScheme: ColorScheme) -> InkStroke {
        let scale: CGFloat = 3
        let context = CGContext(data: nil, width: Int(ceil(size.width * scale)), height: Int(ceil(size.height * scale)),
                                bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.translateBy(x: 0, y: CGFloat(context.height))
        context.scaleBy(x: CGFloat(context.width) / size.width, y: -CGFloat(context.height) / size.height)
        let pigment: (red: CGFloat, green: CGFloat, blue: CGFloat) = colorScheme == .dark
            ? (238, 119, 95)
            : (194, 65, 45)
        var bounds = CGRect.null
        for layer in stroke.layers {
            let path = layer.path
            bounds = bounds.union(path.boundingBoxOfPath)
            context.setFillColor(CGColor(srgbRed: pigment.red / 255, green: pigment.green / 255,
                                         blue: pigment.blue / 255, alpha: layer.opacity))
            context.addPath(path)
            context.fillPath()
        }
        context.setBlendMode(.destinationIn)
        let tile: CGFloat = 112 * 1.4
        let xOffset = CGFloat((Double(grainPhase) * 0.618034).truncatingRemainder(dividingBy: 1)) * tile
        let yOffset = CGFloat((Double(grainPhase) * 0.381966 + 0.17).truncatingRemainder(dividingBy: 1)) * tile
        for x in stride(from: xOffset - tile, to: size.width, by: tile) {
            for y in stride(from: yOffset - tile, to: size.height, by: tile) {
                context.draw(dryGrain, in: CGRect(x: x, y: y, width: tile, height: tile))
            }
        }
        let extent = bounds.isNull ? 0...0 : (bounds.minX - 0.5)...(bounds.maxX + 0.5)
        return InkStroke(image: context.makeImage()!, timing: stroke.timing[0]...stroke.timing[1], horizontalExtent: extent)
    }

    private static func dryGrainMask(_ image: CGImage) -> CGImage {
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        pixels.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress, width: image.width, height: image.height,
                                    bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        // Increase the ink lost at lighter spots while leaving solid ink at full opacity.
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let opacity = UInt8(max(0, 255 - (255 - Double(pixels[index])) * 3.2).rounded())
            pixels[index] = opacity
            pixels[index + 1] = opacity
            pixels[index + 2] = opacity
            pixels[index + 3] = opacity
        }
        return CGImage(width: image.width, height: image.height, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: CGDataProvider(data: Data(pixels) as CFData)!, decode: nil,
                       shouldInterpolate: true, intent: .defaultIntent)!
    }
}

struct LooseleafResetRenderer: TextRenderer {
    var progress: CGFloat
    let settingID: String
    let colorScheme: ColorScheme

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    var displayPadding: EdgeInsets { EdgeInsets(top: 3, leading: 4, bottom: 3, trailing: 4) }

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        for line in layout {
            context.draw(line)
            let bounds = line.typographicBounds.rect
            guard bounds.width > 0, progress > 0 else { continue }
            let drawing = LooseleafResetInk.shared.drawing(settingID: settingID, size: bounds.size,
                                                          colorScheme: colorScheme)
            let rect = bounds.insetBy(dx: -4, dy: -3)
            let elapsed = progress * (drawing.strokes.last?.timing.upperBound ?? 1)
            for stroke in drawing.strokes where elapsed > stroke.timing.lowerBound {
                let amount = min(1, (elapsed - stroke.timing.lowerBound) / (stroke.timing.upperBound - stroke.timing.lowerBound))
                var ink = context
                ink.clip(to: Path(stroke.revealRect(in: rect, through: amount)))
                ink.draw(Image(decorative: stroke.image, scale: 3), in: rect)
            }
        }
    }
}

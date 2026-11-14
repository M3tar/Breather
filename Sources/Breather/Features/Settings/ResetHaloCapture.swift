import AppKit
import AVFoundation
import Metal

@MainActor enum ResetHaloCapture {
    /// Core Animation's software render still visits offscreen drawing leaves.
    /// Cull only bounded subtrees / unfiltered bitmap leaves, and restore every
    /// property before returning to the run loop. No altered tree is presented.
    private static func render(_ root: CALayer, in context: CGContext, strip: CGRect, liveRegions: [CGRect], metalImages: [ObjectIdentifier: CGImage]) {
        var hidden: [CALayer] = []
        var stills: [CALayer] = []
        func cull(_ layer: CALayer) {
            guard !layer.isHidden, layer.opacity > 0 else { return }
            if layer is CAMetalLayer || layer is AVPlayerLayer {
                if layer.convert(layer.bounds, to: root).intersects(strip),
                   let image = metalImages[ObjectIdentifier(layer)], let parent = layer.superlayer {
                    let still = CALayer()
                    still.bounds = layer.bounds; still.position = layer.position; still.anchorPoint = layer.anchorPoint
                    still.transform = layer.transform; still.zPosition = layer.zPosition
                    still.contents = image; still.contentsScale = layer.contentsScale; still.contentsGravity = .resize
                    still.opacity = layer.opacity; still.cornerRadius = layer.cornerRadius; still.masksToBounds = layer.masksToBounds
                    still.isGeometryFlipped = layer.isGeometryFlipped
                    parent.insertSublayer(still, below: layer); stills.append(still)
                }
                layer.isHidden = true; hidden.append(layer); return
            }
            let leaves = layer.sublayers ?? []
            let boundedLeaf = leaves.isEmpty && layer.contents != nil && layer.shadowOpacity == 0
                && (layer.filters?.isEmpty ?? true) && (layer.backgroundFilters?.isEmpty ?? true)
                && layer.compositingFilter == nil
            if layer !== root, !layer.bounds.isEmpty, layer.masksToBounds || boundedLeaf {
                let rect = layer.convert(layer.bounds, to: root)
                if !rect.insetBy(dx: -2, dy: -2).intersects(strip) || liveRegions.contains(where: { $0.contains(rect) }) {
                    layer.isHidden = true; hidden.append(layer); return
                }
            }
            leaves.forEach(cull)
        }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        cull(root)
        root.render(in: context)
        hidden.forEach { $0.isHidden = false }
        stills.forEach { $0.removeFromSuperlayer() }
        CATransaction.commit()
    }
    static func signature(_ root: NSView) -> [String] {
        var result: [String] = []
        func walk(_ view: NSView) {
            if let control = view as? NSControl,
               control is NSTextField || control is NSStepper || control is NSPopUpButton || control is NSSegmentedControl || control is NSSwitch {
                let rect = root.convert(view.bounds, from: view)
                let value: String
                if let field = control as? NSTextField { value = field.stringValue }
                else if let popup = control as? NSPopUpButton { value = popup.titleOfSelectedItem ?? "" }
                else if let segment = control as? NSSegmentedControl { value = String(segment.selectedSegment) }
                else if let toggle = control as? NSSwitch { value = String(toggle.state.rawValue) }
                else { value = String(control.doubleValue) }
                result.append("\(type(of: control))|\(value)|\(control.isEnabled)|\([rect.minX, rect.minY, rect.width, rect.height].map { Int(($0 * 16).rounded()) })")
            }
            view.subviews.forEach(walk)
        }
        walk(root); return result.sorted()
    }
    static func capture(host: NSView, gpu: ResetHaloGPU, revision: Int, scale: CGFloat,
                        valid: () -> Bool, didCaptureSlice: (Int) -> Void = { _ in },
                        samples: ResetHaloSamples? = nil, requiresOpaqueContent: Bool = false) async throws -> (ResetHaloFrame, [Double]) {
        let begin = CACurrentMediaTime(), size = host.bounds.size
        // Bound allocation and reject detached/degenerate views before conversion
        // to integer dimensions. Oversized displays simply omit visual feedback.
        guard valid(), size.width.isFinite, size.height.isFinite, scale.isFinite,
              size.width > 0, size.height > 0, scale > 0,
              size.width * scale <= 8192, size.height * scale <= 8192,
              size.width * size.height * scale * scale <= 16_777_216 else { throw CancellationError() }
        host.layoutSubtreeIfNeeded(); host.displayIfNeeded()
        let signature = ResetHaloCapture.signature(host)
        let width = Int(size.width * scale), height = Int(size.height * scale)
        let alignment = gpu.device.minimumLinearTextureAlignment(for: .bgra8Unorm)
        let row = ((width * 4 + alignment - 1) / alignment) * alignment
        guard let storage = gpu.device.makeBuffer(length: row * height, options: .storageModeShared),
              let context = CGContext(data: storage.contents(), width: width, height: height, bitsPerComponent: 8, bytesPerRow: row,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue),
              let layer = host.layer else { throw ResetHaloError.failed("Incremental bitmap unavailable") }
        context.translateBy(x: 0, y: CGFloat(height)); context.scaleBy(x: scale, y: -scale)
        let layout = (CACurrentMediaTime() - begin) * 1000
        samples?.append("captureLayoutMS", layout)
        samples?.append("captureWidth", size.width); samples?.append("captureHeight", size.height)
        var slices: [Double] = []
        // Metal/video surfaces cannot be faithfully read through CALayer's CPU
        // renderer. Leave those areas live underneath the transparent overlay;
        // the shader still sweeps light across them, without freezing playback.
        var liveRegions: [CGRect] = []
        var liveLayers: [CALayer] = []
        func findLiveRegions(_ candidate: CALayer) {
            guard !candidate.isHidden, candidate.opacity > 0 else { return }
            if candidate is CAMetalLayer || candidate is AVPlayerLayer {
                var rect = candidate.convert(candidate.bounds, to: layer).intersection(CGRect(origin: .zero, size: size))
                var ancestor = candidate.superlayer
                while let parent = ancestor {
                    if parent.masksToBounds { rect = rect.intersection(parent.convert(parent.bounds, to: layer)) }
                    if parent.isHidden || parent.opacity == 0 { return }
                    if parent === layer { break }
                    ancestor = parent.superlayer
                }
                if !rect.isNull, !rect.isEmpty { liveRegions.append(rect); liveLayers.append(candidate) }
                return
            }
            candidate.sublayers?.forEach(findLiveRegions)
        }
        findLiveRegions(layer)
        var metalMaximumMS = 0.0
        var metalImages: [ObjectIdentifier: CGImage] = [:]
        // Read only visible native Metal surfaces, once per A/B capture. Render
        // their existing shader into a small offscreen texture; no display-loop
        // readback or screenshot permission is required.
        if requiresOpaqueContent {
            var providers: [ObjectIdentifier: any MetalViewSnapshotProviding] = [:]
            func findProviders(_ view: NSView) {
                if let provider = view as? any MetalViewSnapshotProviding, let layer = view.layer {
                    providers[ObjectIdentifier(layer)] = provider
                }
                view.subviews.forEach(findProviders)
            }
            findProviders(host)
            for live in liveLayers {
                guard valid(), let provider = providers[ObjectIdentifier(live)] else {
                    throw ResetHaloError.failed("Visible live surface cannot be covered faithfully")
                }
                let frame = try await provider.captureMetalImage()
                metalImages[ObjectIdentifier(live)] = frame.image
                metalMaximumMS = max(metalMaximumMS, frame.maximumWorkMS)
                samples?.append("metalSnapshotWorkMS", frame.maximumWorkMS)
                try Task.checkCancellation()
                guard valid() else { throw CancellationError() }
            }
            liveRegions = []
            host.effectiveAppearance.performAsCurrentDrawingAppearance {
                context.setFillColor(NSColor.windowBackgroundColor.cgColor)
                context.fill(CGRect(origin: .zero, size: size))
            }
        }
        // Keep approximately the validated 840 pt / 2x pixel area per turn on
        // wider or denser displays. The final image retains full backing scale.
        let pixelBudget: CGFloat = requiresOpaqueContent ? 322_560 : 537_600
        let stripHeight = max(8, min(160, pixelBudget / (size.width * scale * scale)))
        // Clip edges must land on whole backing pixels. Fractional edges blend
        // adjacent passes with the background and leave horizontal seams through
        // controls, even when both strips contain the same unchanged pixels.
        let stripPixelHeight = max(1, Int((stripHeight * scale).rounded(.down)))
        // The first strip is separated from layout so one event-loop turn cannot
        // accidentally combine both costs. No partial frame is ever presented.
        try await Task.sleep(for: .milliseconds(1))
        for pixelY in stride(from: 0, to: height, by: stripPixelHeight) {
            try Task.checkCancellation()
            guard valid(), host.bounds.size == size else { throw CancellationError() }
            let start = CACurrentMediaTime()
            let strip = CGRect(x: 0, y: CGFloat(pixelY) / scale, width: size.width,
                               height: CGFloat(min(stripPixelHeight, height - pixelY)) / scale)
            context.saveGState(); context.clip(to: strip)
            render(layer, in: context, strip: strip, liveRegions: liveRegions, metalImages: metalImages); context.restoreGState()
            slices.append((CACurrentMediaTime() - start) * 1000)
            samples?.append("captureSliceMS", slices.last!)
            didCaptureSlice(slices.count)
            try await Task.sleep(for: .milliseconds(1))
        }
        try Task.checkCancellation()
        guard valid(), signature == ResetHaloCapture.signature(host) else { throw CancellationError() }
        liveRegions.forEach { context.clear($0) }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        descriptor.storageMode = .shared; descriptor.usage = .shaderRead
        guard let texture = storage.makeTexture(descriptor: descriptor, offset: 0, bytesPerRow: row) else { throw ResetHaloError.failed("Incremental texture unavailable") }
        return (ResetHaloFrame(texture: texture, storage: storage, context: context, size: size, scale: scale, revision: revision,
            timings: ["captureMS": slices.reduce(0,+), "maximumSliceMS": max(layout, metalMaximumMS, slices.max() ?? 0), "metalMaximumMS": metalMaximumMS, "layoutMS": layout,
                "wallMS": (CACurrentMediaTime() - begin) * 1000]), slices)
    }
}

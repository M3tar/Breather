import AppKit
@preconcurrency import MetalKit

// Shared by the production transition and the standalone performance probe.
private struct ResetHaloUniforms { var size: SIMD2<Float>; var progress: Float; var amplitude: Float }

final class ResetHaloSamples: @unchecked Sendable {
    let enabled: Bool
    init(enabled: Bool = true) { self.enabled = enabled }
    private let lock = NSLock()
    private var data: [String: [Double]] = [:]
    func append(_ key: String, _ value: Double) { guard enabled else { return }; lock.lock(); defer { lock.unlock() }; data[key, default: []].append(value) }
    func values(_ key: String) -> [Double] { lock.lock(); defer { lock.unlock() }; return data[key, default: []] }
}

final class ResetHaloGPU: @unchecked Sendable {
    let device: MTLDevice
    let queue: MTLCommandQueue
    let pipeline: MTLRenderPipelineState
    let placeholder: MTLTexture
    init() throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { throw ResetHaloError.failed("Metal unavailable") }
        self.device = device; self.queue = queue
        let source = Self.shaderSource
        let library = try device.makeLibrary(source: source, options: nil)
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "haloVertex")
        descriptor.fragmentFunction = library.makeFunction(name: "haloFragment")
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        let tiny = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: 1, height: 1, mipmapped: false)
        tiny.storageMode = .shared; tiny.usage = .shaderRead
        guard let placeholder = device.makeTexture(descriptor: tiny) else { throw ResetHaloError.failed("Placeholder unavailable") }
        var zero: UInt32 = 0
        placeholder.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0, withBytes: &zero, bytesPerRow: 4)
        self.placeholder = placeholder
    }
    func upload(_ image: CGImage) throws -> MTLTexture {
        try MTKTextureLoader(device: device).newTexture(cgImage: image, options: [.SRGB: false, .origin: MTKTextureLoader.Origin.topLeft])
    }
    func encode(source: MTLTexture, replacement: MTLTexture? = nil, target: MTLTexture, size: CGSize, progress: Float, amplitude: Float) throws -> MTLCommandBuffer {
        guard let buffer = queue.makeCommandBuffer() else { throw ResetHaloError.failed("Command buffer unavailable") }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .dontCare
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = buffer.makeRenderCommandEncoder(descriptor: pass) else { throw ResetHaloError.failed("Encoder unavailable") }
        var uniforms = ResetHaloUniforms(size: SIMD2(Float(size.width), Float(size.height)), progress: progress, amplitude: amplitude)
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(source, index: 0)
        encoder.setFragmentTexture(replacement ?? source, index: 1)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<ResetHaloUniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        return buffer
    }
    func renderImage(source: MTLTexture, replacement: MTLTexture? = nil, size: CGSize, progress: Float) throws -> CGImage {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: source.width, height: source.height, mipmapped: false)
        descriptor.usage = .renderTarget; descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor) else { throw ResetHaloError.failed("Output texture unavailable") }
        let buffer = try encode(source: source, replacement: replacement, target: texture, size: size, progress: progress, amplitude: 7)
        buffer.commit(); buffer.waitUntilCompleted()
        guard buffer.status == .completed else { throw buffer.error ?? ResetHaloError.failed("ResetHaloGPU failure") }
        var bytes = [UInt8](repeating: 0, count: texture.width * texture.height * 4)
        texture.getBytes(&bytes, bytesPerRow: texture.width * 4, from: MTLRegionMake2D(0, 0, texture.width, texture.height), mipmapLevel: 0)
        return CGImage(width: texture.width, height: texture.height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: texture.width * 4,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: [.byteOrder32Little, CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue)],
                       provider: CGDataProvider(data: Data(bytes) as CFData)!, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    }
    func warm() throws {
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: 8, height: 8, mipmapped: false)
        d.usage = [.shaderRead, .renderTarget]; d.storageMode = .shared
        guard let source = device.makeTexture(descriptor: d), let target = device.makeTexture(descriptor: d) else { throw ResetHaloError.failed("Warmup texture unavailable") }
        let buffer = try encode(source: source, target: target, size: CGSize(width: 8, height: 8), progress: 0, amplitude: 0)
        buffer.commit(); buffer.waitUntilCompleted()
        guard buffer.status == .completed else { throw buffer.error ?? ResetHaloError.failed("Warmup failed") }
    }
}

enum ResetHaloError: Error { case failed(String) }

/// One immutable snapshot per content revision. CPU and Metal share the same bytes;
/// a live/in-flight snapshot is never overwritten by the next capture.
@MainActor final class ResetHaloFrame {
    // Image materialization is only needed for evidence export, never for a click.
    private var capturedImage: CGImage?
    var image: CGImage {
        if let capturedImage { return capturedImage }
        let result = bitmapContext!.makeImage()!
        capturedImage = result
        return result
    }
    private let bitmapContext: CGContext?
    let texture: MTLTexture
    let revision: Int
    let size: CGSize
    let scale: CGFloat
    let timings: [String: Double]
    // Keep the bitmap owner alive for the buffer-backed texture.
    let storage: MTLBuffer?

    init(texture: MTLTexture, storage: MTLBuffer, context: CGContext, size: CGSize, scale: CGFloat, revision: Int, timings: [String: Double]) {
        self.texture = texture; self.storage = storage; bitmapContext = context
        self.size = size; self.scale = scale; self.revision = revision; self.timings = timings
    }

    init(host: NSView, gpu: ResetHaloGPU, revision: Int, method: String, scale: CGFloat) throws {
        self.revision = revision; size = host.bounds.size; self.scale = scale
        var times: [String: Double] = [:]
        var start = CACurrentMediaTime()
        host.layoutSubtreeIfNeeded(); host.displayIfNeeded()
        times["layoutMS"] = (CACurrentMediaTime() - start) * 1000
        start = CACurrentMediaTime()
        if method == "shared" {
            let width = Int(size.width * scale), height = Int(size.height * scale)
            let alignment = gpu.device.minimumLinearTextureAlignment(for: .bgra8Unorm)
            let row = ((width * 4 + alignment - 1) / alignment) * alignment
            guard let buffer = gpu.device.makeBuffer(length: row * height, options: .storageModeShared),
                  let context = CGContext(data: buffer.contents(), width: width, height: height, bitsPerComponent: 8, bytesPerRow: row,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue),
                  let layer = host.layer else { throw ResetHaloError.failed("Shared bitmap allocation failed") }
            times["allocationMS"] = (CACurrentMediaTime() - start) * 1000
            start = CACurrentMediaTime()
            context.translateBy(x: 0, y: CGFloat(height)); context.scaleBy(x: scale, y: -scale)
            layer.render(in: context)
            times["rasterMS"] = (CACurrentMediaTime() - start) * 1000
            bitmapContext = context; storage = buffer
            times["imageMS"] = 0
            start = CACurrentMediaTime()
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
            descriptor.storageMode = .shared; descriptor.usage = .shaderRead
            guard let texture = buffer.makeTexture(descriptor: descriptor, offset: 0, bytesPerRow: row) else { throw ResetHaloError.failed("Shared texture failed") }
            self.texture = texture
            times["uploadMS"] = (CACurrentMediaTime() - start) * 1000
        } else {
            guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw ResetHaloError.failed("Snapshot allocation failed") }
            times["allocationMS"] = (CACurrentMediaTime() - start) * 1000
            start = CACurrentMediaTime()
            host.cacheDisplay(in: host.bounds, to: rep)
            times["rasterMS"] = (CACurrentMediaTime() - start) * 1000
            start = CACurrentMediaTime()
            guard let image = rep.cgImage else { throw ResetHaloError.failed("Snapshot image failed") }
            bitmapContext = nil; storage = nil; capturedImage = image
            times["imageMS"] = (CACurrentMediaTime() - start) * 1000
            start = CACurrentMediaTime(); texture = try gpu.upload(image)
            times["uploadMS"] = (CACurrentMediaTime() - start) * 1000
        }
        times["captureMS"] = (times["allocationMS"] ?? 0) + (times["rasterMS"] ?? 0) + (times["imageMS"] ?? 0)
        timings = times
    }
}

@MainActor final class ResetHaloSurface: MTKView, MTKViewDelegate {
    let gpu: ResetHaloGPU
    var source: MTLTexture?
    private(set) var replacement: MTLTexture?
    var samples = ResetHaloSamples()
    var start = 0.0
    var frozen: Float?
    var finished: ((String) -> Void)?
    var drawCount = 0
    var callbackCount = 0
    var failure: String?
    var isValid: (() -> Bool)?
    private(set) var running = false
    private var deadline: Task<Void, Never>?
    private var primeDraw: (() -> Void)?
    private var primeID = UUID()
    private var primeCompletion: ((Result<Void, Error>) -> Void)?
    private var primeTimeout: Task<Void, Never>?

    init(frame: CGRect, gpu: ResetHaloGPU) {
        self.gpu = gpu
        super.init(frame: frame, device: gpu.device)
        colorPixelFormat = .bgra8Unorm; framebufferOnly = true; preferredFramesPerSecond = 60
        isPaused = true; enableSetNeedsDisplay = false; delegate = self; alphaValue = 0
        (layer as? CAMetalLayer)?.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
        (layer as? CAMetalLayer)?.isOpaque = false
        (layer as? CAMetalLayer)?.allowsNextDrawableTimeout = true
    }
    required init(coder: NSCoder) { fatalError("init(coder:) is not used") }
    override var isOpaque: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    /// Allocate actual-size drawable resources before the click, while transparent.
    /// No persistent frame loop is started by preparation.
    func prime(_ texture: MTLTexture) async throws {
        finishPrime(primeID, .failure(CancellationError()))
        let id = UUID(); primeID = id
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            primeCompletion = { continuation.resume(with: $0) }
            primeTimeout = Task { @MainActor [weak self] in
                do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
                self?.finishPrime(id, .failure(CancellationError()))
            }
            primeDraw = { [weak self] in
                do {
                    guard let self, let drawable = self.currentDrawable else { throw ResetHaloError.failed("Priming drawable unavailable") }
                    let buffer = try self.gpu.encode(source: texture, target: drawable.texture, size: self.bounds.size, progress: 0, amplitude: 0)
                    buffer.addCompletedHandler { [weak self] command in
                        let succeeded = command.status == .completed
                        Task { @MainActor [weak self] in
                            self?.finishPrime(id, succeeded ? .success(()) : .failure(ResetHaloError.failed("Priming GPU error")))
                        }
                    }
                    buffer.present(drawable); buffer.commit()
                } catch { self?.finishPrime(id, .failure(error)) }
            }
            // Let MTKView finish its draw cycle and retire currentDrawable, rather
            // than presenting a drawable obtained outside the delegate callback.
            draw()
        }
    }
    private func finishPrime(_ id: UUID, _ result: Result<Void, Error>) {
        guard id == primeID else { return }
        primeTimeout?.cancel(); primeTimeout = nil; primeDraw = nil
        let completion = primeCompletion; primeCompletion = nil
        completion?(result)
    }
    /// The primed old frame covers the real page before its settings change.
    /// Holding a frame does not start a display loop.
    func hold(_ texture: MTLTexture) {
        source = texture; alphaValue = 1
        CATransaction.flush()
    }
    func begin(_ texture: MTLTexture, replacement: MTLTexture? = nil, samples: ResetHaloSamples, frozen: Float? = nil) {
        source = texture; self.replacement = replacement; self.samples = samples; self.frozen = frozen
        start = CACurrentMediaTime(); drawCount = 0; callbackCount = 0; failure = nil; running = true
        alphaValue = 1
        // This deadline is independent of draw callbacks, visibility and drawable availability.
        // Even a frozen inspection has a bound, so it cannot retain resources indefinitely.
        deadline = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .milliseconds(frozen == nil ? 900 : 15_000)) } catch { return }
            self?.stop("deadline")
        }
        isPaused = true
        draw()
        CATransaction.flush()
        isPaused = frozen != nil
    }
    func stop(_ reason: String) {
        guard running else { return }
        running = false; deadline?.cancel(); deadline = nil
        isPaused = true; alphaValue = 0; source = nil; replacement = nil; frozen = nil
        let completion = finished; finished = nil
        completion?(reason)
    }
    func dispose() {
        finishPrime(primeID, .failure(CancellationError()))
        stop("disposed"); isPaused = true; delegate = nil
        source = nil; replacement = nil; releaseDrawables(); removeFromSuperview()
    }
    func draw(in view: MTKView) {
        if let primeDraw { self.primeDraw = nil; primeDraw(); return }
        callbackCount += 1
        guard running, let source else { return }
        if isValid?() == false { stop("invalidated"); return }
        let now = CACurrentMediaTime()
        let progress = frozen ?? Float((now - start) / 0.9)
        if progress >= 1 { stop("completed"); return }
        guard let window, window.isVisible, !window.isMiniaturized, window.occlusionState.contains(.visible), !NSApp.isHidden else {
            stop("not-visible"); return
        }
        samples.append("drawCallback", now)
        guard let drawable = currentDrawable else { samples.append("missingDrawable", now); return }
        do {
            let buffer = try gpu.encode(source: source, replacement: replacement, target: drawable.texture, size: bounds.size, progress: progress, amplitude: 7)
            let samples = self.samples
            drawable.addPresentedHandler { samples.append("presented", $0.presentedTime) }
            buffer.addCompletedHandler { [weak self] command in
                samples.append("gpuMS", (command.gpuEndTime - command.gpuStartTime) * 1000)
                if command.status != .completed {
                    samples.append("gpuErrors", 1)
                    Task { @MainActor [weak self] in self?.stop("gpu-error") }
                }
            }
            buffer.present(drawable); buffer.commit(); drawCount += 1
            samples.append("encodeMS", (CACurrentMediaTime() - now) * 1000)
        } catch { failure = String(describing: error); stop("gpu-error") }
    }
}


extension ResetHaloGPU {
    private static let shaderSource = #"""
#include <metal_stdlib>
using namespace metal;

struct Vertex { float4 position [[position]]; float2 uv; };
struct Uniforms { float2 size; float progress; float amplitude; };

vertex Vertex haloVertex(uint i [[vertex_id]]) {
    float2 p = float2((i << 1) & 2, i & 2);
    return { float4(p * float2(2, -2) + float2(-1, 1), 0, 1), p };
}

fragment float4 haloFragment(Vertex v [[stage_in]], texture2d<float> source [[texture(0)]],
                             texture2d<float> replacement [[texture(1)]], constant Uniforms &u [[buffer(0)]]) {
    constexpr sampler s(coord::normalized, address::clamp_to_edge, filter::linear);
    float2 p = v.uv * u.size;
    float t = clamp(u.progress, 0.0f, 1.0f);
    if (t <= 0) return source.sample(s, v.uv);
    if (t >= 1) return replacement.sample(s, v.uv);
    float strength = min(1.0f, t / .03f) * (1.0f - pow(t, 2.2f));
    float2 center = u.size * float2(.94, .95);
    float2 delta = p - center;
    float distance = length(delta);
    float radius = -90 + (length(center) + 180) * (1 - exp2(-6 * t)) / (1 - exp2(-6.0f));
    float width = 90;
    float x = (distance - radius) / width;
    float z = x * .75;
    float edge = min(min(p.x, u.size.x - p.x), min(p.y, u.size.y - p.y));
    float2 offset = delta / max(distance, 1.0f) * u.amplitude * 2.33 * z * exp(-z*z)
                    * strength * smoothstep(0.0f, 56.0f, edge);
    float2 uv = (p - offset) / u.size;
    // The narrow reveal edge travels at the crest of the same broad light arc.
    // Ahead of it every pixel is still A; behind it every pixel is B.
    float reveal = smoothstep(-8.0f, 8.0f, radius - distance);
    float4 original = mix(source.sample(s, v.uv), replacement.sample(s, v.uv), reveal);
    float glow = strength * exp(-1.1 * x*x) * .14;
    if (original.a < .01) return float4(float3(.24, .78, .70) * glow, glow);
    float4 color = mix(source.sample(s, uv), replacement.sample(s, uv), reveal);
    if (color.a < .99) color = original;
    float4 red = mix(source.sample(s, (p - offset * 1.08) / u.size),
                     replacement.sample(s, (p - offset * 1.08) / u.size), reveal);
    float4 blue = mix(source.sample(s, (p - offset * .92) / u.size),
                      replacement.sample(s, (p - offset * .92) / u.size), reveal);
    color.r = red.a > .99 ? red.r : original.r;
    color.b = blue.a > .99 ? blue.b : original.b;
    color.rgb = mix(color.rgb, float3(.24, .78, .70), glow);
    return color;
}

"""#
}

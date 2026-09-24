import MetalKit
import SwiftUI

enum RainGlassRendering {
    static let framesPerSecond = 30
    static let stillFrameTime: Float = 12.0

    #if DEBUG
    static func renderedPixels(width: Int, height: Int, time: Float,
                               fragmentName: String = "rainGlassFragment") -> [UInt8]? {
        guard let device = MTLCreateSystemDefaultDevice(),
              let library = try? device.makeLibrary(source: RainGlassRenderer.shaderSource, options: nil),
              let vertex = library.makeFunction(name: "rainGlassVertex"),
              let fragment = library.makeFunction(name: fragmentName),
              let queue = device.makeCommandQueue(),
              let background = RainGlassBackground.makeTexture(device: device, queue: queue)
        else { return nil }

        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertex
        pipelineDescriptor.fragmentFunction = fragment
        pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        guard let pipeline = try? device.makeRenderPipelineState(descriptor: pipelineDescriptor) else {
            return nil
        }

        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false
        )
        textureDescriptor.usage = .renderTarget
        textureDescriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: textureDescriptor),
              let buffer = queue.makeCommandBuffer() else { return nil }

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = buffer.makeRenderCommandEncoder(descriptor: pass) else { return nil }
        var uniforms = SIMD4<Float>(Float(width), Float(height), time, 1)
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<SIMD4<Float>>.stride, index: 0)
        encoder.setFragmentTexture(background, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        buffer.commit()
        buffer.waitUntilCompleted()
        guard buffer.status == .completed else { return nil }

        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        texture.getBytes(&pixels, bytesPerRow: width * 4,
                         from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        return pixels
    }

    static func motionMask(width: Int, height: Int, time: Float) -> [UInt8]? {
        renderedPixels(width: width, height: height, time: time,
                       fragmentName: "rainGlassMotionMask")
    }
    #endif
}

private enum RainGlassBackground {
    private static let cacheLock = NSLock()
    nonisolated(unsafe) private static var cachedTextures: [ObjectIdentifier: MTLTexture] = [:]

    static func makeTexture(device: MTLDevice, queue: MTLCommandQueue) -> MTLTexture? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        let key = ObjectIdentifier(device)
        if let cached = cachedTextures[key] { return cached }

        let side = 512
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm, width: side, height: side, mipmapped: true
        )
        descriptor.usage = [.shaderRead, .pixelFormatView]
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }

        // A compact, generated version of the existing rainy blue-gray base.
        // No image or video is added to the application bundle.
        let top = SIMD3<Float>(0x3F, 0x49, 0x55) / 255
        let middle = SIMD3<Float>(0x59, 0x63, 0x6D) / 255
        let bottom = SIMD3<Float>(0x43, 0x4C, 0x57) / 255
        let lights: [(Float, Float, Float, SIMD3<Float>)] = [
            (0.18, 0.26, 0.035, SIMD3(0.38, 0.27, 0.17)),
            (0.30, 0.44, 0.055, SIMD3(0.19, 0.25, 0.31)),
            (0.42, 0.20, 0.030, SIMD3(0.35, 0.25, 0.15)),
            (0.62, 0.58, 0.045, SIMD3(0.20, 0.26, 0.32)),
            (0.77, 0.32, 0.050, SIMD3(0.38, 0.29, 0.20)),
            (0.87, 0.70, 0.038, SIMD3(0.20, 0.26, 0.32))
        ]
        var pixels = [UInt8](repeating: 255, count: side * side * 4)
        for y in 0..<side {
            let v = Float(y) / Float(side - 1)
            for x in 0..<side {
                let u = Float(x) / Float(side - 1)
                let base = v < 0.5
                    ? simd_mix(top, middle, SIMD3<Float>(repeating: v * 2))
                    : simd_mix(middle, bottom, SIMD3<Float>(repeating: (v - 0.5) * 2))
                var color = base
                for (cx, cy, radius, tint) in lights {
                    let dx = (u - cx) / radius
                    let dy = (v - cy) / radius
                    color += tint * exp(-(dx * dx + dy * dy) * 0.45)
                }
                let pixel = (y * side + x) * 4
                pixels[pixel] = UInt8(clamping: Int(min(color.x, 1) * 255))
                pixels[pixel + 1] = UInt8(clamping: Int(min(color.y, 1) * 255))
                pixels[pixel + 2] = UInt8(clamping: Int(min(color.z, 1) * 255))
            }
        }
        texture.replace(region: MTLRegionMake2D(0, 0, side, side), mipmapLevel: 0,
                        withBytes: pixels, bytesPerRow: side * 4)
        guard let commandBuffer = queue.makeCommandBuffer(),
              let encoder = commandBuffer.makeBlitCommandEncoder() else { return nil }
        encoder.generateMipmaps(for: texture)
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        guard commandBuffer.status == .completed else { return nil }
        cachedTextures[key] = texture
        return texture
    }
}

struct RainGlassMetalBackdrop<Fallback: View>: View {
    let animated: Bool
    @ViewBuilder let fallback: () -> Fallback

    var body: some View {
        ZStack {
            fallback()
            if MTLCreateSystemDefaultDevice() != nil {
                RainGlassMetalSurface(animated: animated)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

private struct RainGlassMetalSurface: NSViewRepresentable {
    let animated: Bool

    func makeNSView(context: Context) -> RainGlassMetalView {
        RainGlassMetalView(animated: animated)
    }

    func updateNSView(_ view: RainGlassMetalView, context: Context) {
        view.setAnimated(animated)
    }
}

final class RainGlassMetalView: MTKView {
    private var rainRenderer: RainGlassRenderer?
    var isRendererReady: Bool { rainRenderer != nil }

    init(animated: Bool) {
        let device = MTLCreateSystemDefaultDevice()
        super.init(frame: .zero, device: device)

        colorPixelFormat = .bgra8Unorm_srgb
        clearColor = MTLClearColorMake(0, 0, 0, 0)
        preferredFramesPerSecond = RainGlassRendering.framesPerSecond
        framebufferOnly = true
        autoResizeDrawable = true
        wantsLayer = true
        layer?.isOpaque = false

        if let device, let renderer = RainGlassRenderer(device: device, pixelFormat: colorPixelFormat) {
            rainRenderer = renderer
            delegate = renderer
        }
        setAnimated(animated)
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setAnimated(_ animated: Bool) {
        isPaused = !animated
        enableSetNeedsDisplay = !animated
        rainRenderer?.isAnimated = animated
        if !animated {
            setNeedsDisplay(bounds)
        }
    }
}

private final class RainGlassRenderer: NSObject, MTKViewDelegate {
    private struct Uniforms {
        var resolution: SIMD2<Float>
        var time: Float
        var intensity: Float
    }

    private let commandQueue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private let background: MTLTexture
    private let startedAt = CACurrentMediaTime()
    var isAnimated = true

    init?(device: MTLDevice, pixelFormat: MTLPixelFormat) {
        guard let commandQueue = device.makeCommandQueue(),
              let background = RainGlassBackground.makeTexture(device: device, queue: commandQueue),
              let library = try? device.makeLibrary(source: Self.shaderSource, options: nil),
              let vertex = library.makeFunction(name: "rainGlassVertex"),
              let fragment = library.makeFunction(name: "rainGlassFragment") else {
            return nil
        }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertex
        descriptor.fragmentFunction = fragment
        descriptor.colorAttachments[0].pixelFormat = pixelFormat

        guard let pipeline = try? device.makeRenderPipelineState(descriptor: descriptor) else {
            return nil
        }
        self.commandQueue = commandQueue
        self.pipeline = pipeline
        self.background = background
        super.init()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard view.drawableSize.width > 0,
              view.drawableSize.height > 0,
              let pass = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else {
            return
        }

        let time = isAnimated
            ? Float(CACurrentMediaTime() - startedAt)
            : RainGlassRendering.stillFrameTime
        var uniforms = Uniforms(
            resolution: SIMD2(Float(view.drawableSize.width), Float(view.drawableSize.height)),
            time: time,
            intensity: 1
        )

        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
        encoder.setFragmentTexture(background, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    fileprivate static let shaderSource = #"""
    #include <metal_stdlib>
    using namespace metal;

    struct RasterData {
        float4 position [[position]];
        float2 uv;
    };

    struct Uniforms {
        float2 resolution;
        float time;
        float intensity;
    };

    vertex RasterData rainGlassVertex(uint vertexID [[vertex_id]]) {
        const float2 positions[3] = {
            float2(-1.0, -1.0), float2(3.0, -1.0), float2(-1.0, 3.0)
        };
        RasterData out;
        out.position = float4(positions[vertexID], 0.0, 1.0);
        out.uv = positions[vertexID] * 0.5 + 0.5;
        return out;
    }

    // Heartfelt rain geometry by Martijn Steinrucken / BigWings (2017),
    // ported from the GLSL supplied by the user. CC BY-NC-SA 3.0.
    // https://www.shadertoy.com/view/ltffzl
    // The original iChannel0 image was not supplied; the generated blue-gray
    // mipmapped texture replaces only that input. Keep the equations aligned.
    float S(float a, float b, float value) {
        return a < b ? smoothstep(a, b, value)
                     : 1.0 - smoothstep(b, a, value);
    }

    float3 N13(float value) {
        float3 p = fract(float3(value) * float3(0.1031, 0.11369, 0.13787));
        p += dot(p, p.yzx + 19.19);
        return fract(float3((p.x + p.y) * p.z,
                            (p.x + p.z) * p.y,
                            (p.y + p.z) * p.x));
    }

    float N(float value) {
        return fract(sin(value * 12345.564) * 7658.76);
    }

    float Saw(float b, float value) {
        return S(0.0, b, value) * S(1.0, b, value);
    }

    float2 DropLayer2(float2 uv, float time) {
        float2 originalUV = uv;
        // Shadertoy/Metal fragment UV is bottom-left: this positive offset
        // makes the visible droplet move down as time advances.
        uv.y += time * 0.75;
        float2 axis = float2(6.0, 1.0);
        float2 grid = axis * 2.0;
        float2 id = floor(uv * grid);
        uv.y += N(id.x);
        id = floor(uv * grid);
        float3 noise = N13(id.x * 35.2 + id.y * 2376.1);
        float2 cell = fract(uv * grid) - float2(0.5, 0.0);

        float x = noise.x - 0.5;
        float y = originalUV.y * 20.0;
        float wiggle = sin(y + sin(y));
        x += wiggle * (0.5 - abs(x)) * (noise.z - 0.5);
        x *= 0.7;
        float phase = fract(time + noise.z);
        y = (Saw(0.85, phase) - 0.5) * 0.9 + 0.5;
        float distance = length((cell - float2(x, y)) * axis.yx);
        float mainDrop = S(0.4, 0.0, distance);

        float radius = sqrt(S(1.0, y, cell.y));
        float columnDistance = abs(cell.x - x);
        float trail = S(0.23 * radius, 0.15 * radius * radius, columnDistance);
        float trailFront = S(-0.02, 0.02, cell.y - y);
        trail *= trailFront * radius * radius;

        y = fract(originalUV.y * 10.0) + (cell.y - 0.5);
        float beadDistance = length(cell - float2(x, y));
        float droplets = S(0.3, 0.0, beadDistance);
        float mask = mainDrop + droplets * radius * trailFront;
        return float2(mask, trail);
    }

    float StaticDrops(float2 uv, float time) {
        uv *= 40.0;
        float2 id = floor(uv);
        uv = fract(uv) - 0.5;
        float3 noise = N13(id.x * 107.45 + id.y * 3543.654);
        float2 center = (noise.xy - 0.5) * 0.7;
        float distance = length(uv - center);
        float fade = Saw(0.025, fract(time + noise.z));
        return S(0.3, 0.0, distance) * fract(noise.z * 10.0) * fade;
    }

    float2 Drops(float2 uv, float time, float layer0, float layer1, float layer2) {
        float still = StaticDrops(uv, time) * layer0;
        float2 large = DropLayer2(uv, time) * layer1;
        float2 small = DropLayer2(uv * 1.85, time) * layer2;
        float mask = S(0.3, 1.0, still + large.x + small.x);
        return float2(mask, max(large.y * layer0, small.y * layer1));
    }

    fragment float4 rainGlassMotionMask(RasterData in [[stage_in]],
                                        constant Uniforms &uniforms [[buffer(0)]]) {
        float aspect = uniforms.resolution.x / max(uniforms.resolution.y, 1.0);
        float2 pane = (in.uv - 0.5) * float2(aspect, 1.0);
        float body = DropLayer2(pane, uniforms.time * 0.2).x;
        return float4(body, body, body, 1.0);
    }

    fragment float4 rainGlassFragment(RasterData in [[stage_in]],
                                      constant Uniforms &uniforms [[buffer(0)]],
                                      texture2d<float> background [[texture(0)]]) {
        // The full-screen triangle supplies Shadertoy's bottom-left UV.
        float2 uv = in.uv;
        float aspect = uniforms.resolution.x / max(uniforms.resolution.y, 1.0);
        float2 pane = (uv - 0.5) * float2(aspect, 1.0);
        float T = fmod(uniforms.time, 102.0);
        float clock = T * 0.2;
        float amount = sin(T * 0.05) * 0.30 + 0.70;
        float maxBlur = mix(3.0, 6.0, amount);
        float minBlur = 2.0;

        // HAS_HEART in the supplied original is enabled. Preserve its 102 s
        // timeline, rain slowdown, zoom and heart-shaped rain distribution.
        float story = S(0.0, 70.0, T);
        float progress = min(1.0, T / 70.0);
        progress = 1.0 - progress;
        clock = (1.0 - progress * progress) * 70.0;
        float zoom = mix(0.3, 1.2, story);
        pane *= zoom;
        minBlur = 4.0 + S(0.5, 1.0, story) * 3.0;
        maxBlur = 6.0 + S(0.5, 1.0, story) * 1.5;
        float2 heartUV = pane - float2(0.0, -0.1);
        heartUV.x *= 0.5;
        float heartScale = S(110.0, 70.0, T);
        heartUV.y -= sqrt(abs(heartUV.x)) * 0.5 * heartScale;
        float heart = length(heartUV);
        heart = S(0.4 * heartScale, 0.2 * heartScale, heart) * heartScale;
        amount = heart;
        maxBlur -= heart;
        pane *= 1.5;
        clock *= 0.25;
        uv = (uv - 0.5) * (0.9 + zoom * 0.1) + 0.5;

        float staticLayer = S(-0.5, 1.0, amount) * 2.0;
        float largeLayer = S(0.25, 0.75, amount);
        float smallLayer = S(0.0, 0.5, amount);
        float2 drops = Drops(pane, clock, staticLayer, largeLayer, smallLayer);
        float epsilon = 0.001;
        float right = Drops(pane + float2(epsilon, 0.0), clock,
                            staticLayer, largeLayer, smallLayer).x;
        float above = Drops(pane + float2(0.0, epsilon), clock,
                            staticLayer, largeLayer, smallLayer).x;
        float2 normal = float2(right - drops.x, above - drops.x);
        normal *= 1.0 - S(60.0, 85.0, T);
        drops.y *= 1.0 - S(80.0, 100.0, T) * 0.8;

        float focus = mix(maxBlur - drops.y, minBlur, S(0.1, 0.2, drops.x));
        float2 refractedUV = clamp(uv + normal * uniforms.intensity, 0.0, 1.0);
        constexpr sampler glassSampler(filter::linear, mip_filter::linear,
                                       address::clamp_to_edge);
        float3 color = background.sample(glassSampler, refractedUV,
                                         level(focus)).rgb;
        float shiftTime = (T + 3.0) * 0.5;
        float coolShift = sin(shiftTime * 0.2) * 0.5 + 0.5 + story;
        color *= mix(float3(1.0), float3(0.8, 0.9, 1.3), coolShift);
        // A rest screen is shown on demand, so the source video's full-frame
        // fade would present an opaque black first frame. Only the lightning
        // keeps its gentle introduction; the rainy glass is visible at once.
        float lightningIntro = S(0.0, 10.0, T);
        float lightning = sin(shiftTime * sin(shiftTime * 10.0));
        lightning *= pow(max(0.0, sin(shiftTime + sin(shiftTime))), 10.0);
        color *= 1.0 + lightning * lightningIntro * mix(1.0, 0.1, story * story);
        float vignette = 1.0 - dot(uv - 0.5, uv - 0.5);
        color *= vignette;
        color = mix(pow(color, float3(1.2)), color, heart);
        return float4(saturate(color), 1.0);
    }
    """#
}

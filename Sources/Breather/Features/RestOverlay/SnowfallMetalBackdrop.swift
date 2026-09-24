import MetalKit
import SwiftUI

enum SnowfallRendering {
    static let layerCount = 50
    static let depth: Float = 0.5
    static let width: Float = 0.3
    static let speed: Float = 0.6
    static let framesPerSecond = 24
    static let stillFrameTime: Float = 8

    #if DEBUG
    static func renderedPixels(width: Int, height: Int, time: Float,
                               fragmentName: String = "snowfallPreviewFragment") -> [UInt8]? {
        guard let device = MTLCreateSystemDefaultDevice(),
              let library = try? device.makeLibrary(source: SnowfallRenderer.shaderSource, options: nil),
              let vertex = library.makeFunction(name: "snowfallVertex"),
              let fragment = library.makeFunction(name: fragmentName),
              let queue = device.makeCommandQueue() else { return nil }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertex
        descriptor.fragmentFunction = fragment
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        guard let pipeline = try? device.makeRenderPipelineState(descriptor: descriptor) else { return nil }

        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false
        )
        textureDescriptor.usage = .renderTarget
        textureDescriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: textureDescriptor),
              let commandBuffer = queue.makeCommandBuffer() else { return nil }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return nil }
        var uniforms = SIMD4<Float>(Float(width), Float(height), time, 0)
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<SIMD4<Float>>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        guard commandBuffer.status == .completed else { return nil }
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        texture.getBytes(&pixels, bytesPerRow: width * 4,
                         from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        return pixels
    }
    #endif
}

struct SnowfallMetalBackdrop<Fallback: View>: View {
    let animated: Bool
    @ViewBuilder let fallback: () -> Fallback

    var body: some View {
        Group {
            if MTLCreateSystemDefaultDevice() != nil {
                SnowfallMetalSurface(animated: animated)
            } else {
                fallback()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

private struct SnowfallMetalSurface: NSViewRepresentable {
    let animated: Bool

    func makeNSView(context: Context) -> SnowfallMetalView {
        SnowfallMetalView(animated: animated)
    }

    func updateNSView(_ view: SnowfallMetalView, context: Context) {
        view.setAnimated(animated)
    }
}

final class SnowfallMetalView: MTKView {
    private var snowfallRenderer: SnowfallRenderer?
    var isRendererReady: Bool { snowfallRenderer != nil }

    init(animated: Bool) {
        let device = MTLCreateSystemDefaultDevice()
        super.init(frame: .zero, device: device)
        colorPixelFormat = .bgra8Unorm
        clearColor = MTLClearColorMake(0, 0, 0, 0)
        preferredFramesPerSecond = SnowfallRendering.framesPerSecond
        framebufferOnly = true
        autoResizeDrawable = false
        wantsLayer = true
        layer?.isOpaque = false
        if let device, let renderer = SnowfallRenderer(device: device, pixelFormat: colorPixelFormat) {
            snowfallRenderer = renderer
            delegate = renderer
        }
        setAnimated(animated)
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        let backingScale = window?.backingScaleFactor ?? 1
        let size = CGSize(width: bounds.width * backingScale, height: bounds.height * backingScale)
        guard size.width > 0, size.height > 0 else { return }
        let scale = min(1, 1440 / max(size.width, size.height))
        let next = CGSize(width: max(1, (size.width * scale).rounded()),
                          height: max(1, (size.height * scale).rounded()))
        if drawableSize != next { drawableSize = next }
    }

    func setAnimated(_ animated: Bool) {
        isPaused = !animated
        enableSetNeedsDisplay = !animated
        snowfallRenderer?.setAnimated(animated)
        if !animated { setNeedsDisplay(bounds) }
    }
}

private final class SnowfallRenderer: NSObject, MTKViewDelegate {
    private struct Uniforms {
        var resolution: SIMD2<Float>
        var time: Float
        var unused: Float = 0
    }

    private let commandQueue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private var startedAt = CACurrentMediaTime()
    private var frozenTime = SnowfallRendering.stillFrameTime
    private var hasStarted = false
    private var isAnimated = false

    init?(device: MTLDevice, pixelFormat: MTLPixelFormat) {
        guard let queue = device.makeCommandQueue(),
              let library = try? device.makeLibrary(source: Self.shaderSource, options: nil),
              let vertex = library.makeFunction(name: "snowfallVertex"),
              let fragment = library.makeFunction(name: "snowfallFragment") else { return nil }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertex
        descriptor.fragmentFunction = fragment
        descriptor.colorAttachments[0].pixelFormat = pixelFormat
        guard let pipeline = try? device.makeRenderPipelineState(descriptor: descriptor) else { return nil }
        self.commandQueue = queue
        self.pipeline = pipeline
        super.init()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func setAnimated(_ animated: Bool) {
        guard isAnimated != animated else { return }
        let now = CACurrentMediaTime()
        if animated {
            startedAt = now - Double(hasStarted ? frozenTime : 0)
            hasStarted = true
        } else if hasStarted {
            frozenTime = Float(now - startedAt)
        }
        isAnimated = animated
    }

    func draw(in view: MTKView) {
        guard view.drawableSize.width > 0, view.drawableSize.height > 0,
              let pass = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        var uniforms = Uniforms(
            resolution: SIMD2(Float(view.drawableSize.width), Float(view.drawableSize.height)),
            time: isAnimated ? Float(CACurrentMediaTime() - startedAt) : frozenTime
        )
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    // Metal port of "Just snow" by Andrew Baldwin / baldand (2013).
    // Original: https://www.shadertoy.com/view/ldsGDn
    // License: CC BY-NC-SA 3.0. LIGHT_SNOW remains the original 50-layer mode;
    // the unsupported mouse input uses its zero-offset default.
    fileprivate static let shaderSource = #"""
    #include <metal_stdlib>
    using namespace metal;

    struct SnowRasterData {
        float4 position [[position]];
        float2 uv;
    };

    struct SnowUniforms {
        float2 resolution;
        float time;
        float unused;
    };

    vertex SnowRasterData snowfallVertex(uint vertexID [[vertex_id]]) {
        const float2 positions[3] = {
            float2(-1.0, -1.0), float2(3.0, -1.0), float2(-1.0, 3.0)
        };
        SnowRasterData output;
        output.position = float4(positions[vertexID], 0.0, 1.0);
        output.uv = positions[vertexID] * 0.5 + 0.5;
        return output;
    }

    float snowAccumulation(float2 uv, float time, int layerCount) {
        const float3x3 pattern = float3x3(
            float3(13.323122, 23.5112, 21.71123),
            float3(21.1212, 28.7312, 11.9312),
            float3(21.8112, 14.7212, 61.3934)
        );
        const float depth = \#(SnowfallRendering.depth);
        const float width = \#(SnowfallRendering.width);
        const float speed = \#(SnowfallRendering.speed);
        float acc = 0.0;
        float dof = 5.0 * sin(time * 0.1);
        for (int i = 0; i < \#(SnowfallRendering.layerCount); i++) {
            if (i >= layerCount) { break; }
            float fi = float(i);
            float2 q = uv * (1.0 + fi * depth);
            q += float2(q.y * (width * fract(fi * 7.238917) - width * 0.5),
                        speed * time / (1.0 + fi * depth * 0.03));
            float3 n = float3(floor(q), 31.189 + fi);
            float3 m = floor(n) * 0.00001 + fract(n);
            float3 mp = (31415.9 + m) / fract(pattern * m);
            float3 r = fract(mp);
            float2 s = abs(fract(q) - 0.5 + 0.9 * r.xy - 0.45);
            s += 0.01 * abs(2.0 * fract(10.0 * q.yx) - 1.0);
            float d = 0.6 * max(s.x - s.y, s.x + s.y) + max(s.x, s.y) - 0.01;
            float edge = 0.005 + 0.05 * min(0.5 * abs(fi - 5.0 - dof), 1.0);
            acc += (1.0 - smoothstep(-edge, edge, d))
                 * (r.x / (1.0 + 0.02 * fi * depth));
        }
        return acc;
    }

    fragment float4 snowfallFragment(SnowRasterData input [[stage_in]],
                                     constant SnowUniforms &uniforms [[buffer(0)]]) {
        float2 uv = float2(1.0, uniforms.resolution.y / uniforms.resolution.x) * input.uv;
        float snow = saturate(snowAccumulation(uv, uniforms.time, \#(SnowfallRendering.layerCount)));
        // CAMetalLayer composites premultiplied color over the SwiftUI base.
        return float4(snow, snow, snow, snow);
    }

    fragment float4 snowfallPreviewFragment(SnowRasterData input [[stage_in]],
                                            constant SnowUniforms &uniforms [[buffer(0)]]) {
        float2 uv = float2(1.0, uniforms.resolution.y / uniforms.resolution.x) * input.uv;
        float snow = snowAccumulation(uv, uniforms.time, \#(SnowfallRendering.layerCount));
        float3 top = float3(0.843, 0.871, 0.906);
        float3 middle = float3(0.788, 0.827, 0.875);
        float3 bottom = float3(0.894, 0.910, 0.929);
        float3 base = input.uv.y < 0.5 ? mix(bottom, middle, input.uv.y * 2.0)
                                       : mix(middle, top, (input.uv.y - 0.5) * 2.0);
        return float4(mix(base, float3(1.0), saturate(snow)), 1.0);
    }

    fragment float4 snowfallNearLayersMask(SnowRasterData input [[stage_in]],
                                          constant SnowUniforms &uniforms [[buffer(0)]]) {
        float2 uv = float2(1.0, uniforms.resolution.y / uniforms.resolution.x) * input.uv;
        float mask = saturate(snowAccumulation(uv, uniforms.time, 8));
        return float4(mask, mask, mask, 1.0);
    }
    """#
}

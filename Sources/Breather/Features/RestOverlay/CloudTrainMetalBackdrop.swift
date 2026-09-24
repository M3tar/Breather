import MetalKit
import SwiftUI

struct CloudTrainMetalBackdrop: View {
    let animated: Bool

    var body: some View {
        CloudTrainMetalSurface(animated: animated)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea()
            .allowsHitTesting(false)
    }
}

private struct CloudTrainMetalSurface: NSViewRepresentable {
    let animated: Bool

    func makeNSView(context: Context) -> CloudTrainMetalView {
        CloudTrainMetalView(animated: animated)
    }

    func updateNSView(_ view: CloudTrainMetalView, context: Context) {
        view.setAnimated(animated)
    }
}

final class CloudTrainMetalView: MTKView {
    private var trainRenderer: CloudTrainRenderer?
    var isRendererReady: Bool { trainRenderer != nil }

    init(animated: Bool) {
        let device = MTLCreateSystemDefaultDevice()
        super.init(frame: .zero, device: device)

        colorPixelFormat = .bgra8Unorm
        clearColor = MTLClearColorMake(0.58, 0.7, 1, 1)
        preferredFramesPerSecond = 60 // Fast bridge parallax flickers at lower frame rates.
        framebufferOnly = true
        autoResizeDrawable = false

        if let device, let renderer = CloudTrainRenderer(device: device, pixelFormat: colorPixelFormat) {
            trainRenderer = renderer
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
        let scale = min(1, 1400 / max(size.width, size.height))
        let next = CGSize(width: max(1, (size.width * scale).rounded()),
                          height: max(1, (size.height * scale).rounded()))
        if drawableSize != next { drawableSize = next }
    }

    func setAnimated(_ animated: Bool) {
        isPaused = !animated
        enableSetNeedsDisplay = !animated
        trainRenderer?.setAnimated(animated)
        if !animated { setNeedsDisplay(bounds) }
    }
}

private final class CloudTrainRenderer: NSObject, MTKViewDelegate {
    private struct Uniforms {
        var resolution: SIMD2<Float>
        var time: Float
    }

    private let commandQueue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private let blueNoise: MTLTexture
    private var startedAt = CACurrentMediaTime()
    private var frozenTime: Float = 7.25
    private var hasStarted = false
    private var isAnimated = false

    init?(device: MTLDevice, pixelFormat: MTLPixelFormat) {
        #if SWIFT_PACKAGE
        let resourceBundle = Bundle.module
        #else
        let resourceBundle = Bundle.main
        #endif
        guard let noiseURL = resourceBundle.url(
            forResource: "cloud-train-blue-noise", withExtension: "png", subdirectory: "Textures"
        ) ?? resourceBundle.url(forResource: "cloud-train-blue-noise", withExtension: "png"),
              let blueNoise = try? MTKTextureLoader(device: device).newTexture(
                URL: noiseURL,
                options: [.SRGB: false, .origin: MTKTextureLoader.Origin.topLeft]
              ),
              blueNoise.width == 1024, blueNoise.height == 1024 else { return nil }
        guard let commandQueue = device.makeCommandQueue(),
              let library = try? device.makeLibrary(source: Self.shaderSource, options: nil),
              let vertex = library.makeFunction(name: "cloudTrainVertex"),
              let fragment = library.makeFunction(name: "cloudTrainFragment") else {
            return nil
        }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertex
        descriptor.fragmentFunction = fragment
        descriptor.colorAttachments[0].pixelFormat = pixelFormat
        guard let pipeline = try? device.makeRenderPipelineState(descriptor: descriptor) else { return nil }
        self.commandQueue = commandQueue
        self.pipeline = pipeline
        self.blueNoise = blueNoise
        super.init()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func setAnimated(_ animated: Bool) {
        guard isAnimated != animated else { return }
        let now = CACurrentMediaTime()
        if animated {
            startedAt = now - Double(hasStarted ? frozenTime : 0)
            hasStarted = true
        } else {
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
        encoder.setFragmentTexture(blueNoise, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    // Adapted from "Up in the Cloud Sea" by mdb:
    // https://www.shadertoy.com/view/Ndc3zl
    // The scene's 1024px blue-noise input is from the attributed public adaptation:
    // https://github.com/HoytXU/cloudglen_express
    // The source's iChannel1 overlay texture was not included with the pasted GLSL.
    private static let shaderSource = #"""
        #include <metal_stdlib>
    using namespace metal;

    struct CloudTrainRasterData {
        float4 position [[position]];
        float2 uv;
    };

    struct CloudTrainUniforms {
        float2 resolution;
        float time;
    };

    vertex CloudTrainRasterData cloudTrainVertex(uint vertexID [[vertex_id]]) {
        const float2 positions[3] = {
            float2(-1.0, -1.0), float2(3.0, -1.0), float2(-1.0, 3.0)
        };
        CloudTrainRasterData out;
        out.position = float4(positions[vertexID], 0.0, 1.0);
        out.uv = positions[vertexID] * 0.5 + 0.5;
        return out;
    }

    // The lattice address jumps at cell boundaries; implicit mip selection makes
    // cloud contours shimmer as those boundaries move through the image.
    constexpr sampler noiseSampler(address::repeat, filter::linear);

    float noise(float2 x, texture2d<float> blueNoise){
        float2 f = fract(x);
        float2 u = f*f*f*(f*(f*6.0-15.0)+10.0);


        float2 p = floor(x);
        float a = blueNoise.sample(noiseSampler, (p+float2(0.0, 0.0))/1024.0, level(0)).r;
        float b = blueNoise.sample(noiseSampler, (p+float2(1.0,0.0))/1024.0, level(0)).r;
        float c = blueNoise.sample(noiseSampler, (p+float2(0.0,1.0))/1024.0, level(0)).r;
        float d = blueNoise.sample(noiseSampler, (p+float2(1.0,1.0))/1024.0, level(0)).r;


        return a+(b-a)*u.x+(c-a)*u.y+(a-b-c+d)*u.x*u.y;
    }

    float fbm(float2 x, int detail, texture2d<float> blueNoise){
        float a = 0.0;
        float b = 1.0;
        float t = 0.0;
        for(int i = 0; i < detail; i++){
            float n = noise(x, blueNoise);
            a += b*n;
            t += b;
            b *= 0.7;
            x *= 2.0;

        }
        return a/t;
    }

    float fbm2(float2 x, int detail, texture2d<float> blueNoise){
        float a = 0.0;
        float b = 1.0;
        float t = 0.0;
        for(int i = 0; i < detail; i++){
            float n = noise(x, blueNoise);
            a += b*n;
            t += b;
            b *= 0.9;
            x *= 2.0;

        }
        return a/t;
    }

    float box(float2 uv, float x1, float x2, float y1, float y2){
        return (uv.x > x1 && uv.x < x2 && uv.y > y1 && uv.y < y2)?1.0:0.0;
    }

    #define dot2(v) dot(v, v)
    #define layer(dh, v)  if (uv.y < h + midlevel - (dh) ) return float4(v, 1.);

    float4 foreground(float2 uv, float t, texture2d<float> blueNoise){
        float midlevel;
        float h;
        float disp;
        float dist;
        float2 uv2;

        uv.y -= 0.2;
        // clouds foreground //////////////////////////////////////////////////////////////

        // c14
        midlevel = -0.1;
        disp = 1.7;
        dist = 1.0;
        uv2 = uv + float2(t/dist + 40.0, 0.0);
        h = (fbm(uv2, 8, blueNoise) - 0.5)*disp;
        layer(0.12, float3(0.43, 0.32, 0.31));
        layer(0.08, float3(0.55, 0.42, 0.41));
        layer(0.04, float3(0.66, 0.42, 0.40));
        layer(0., float3(0.77, 0.48, 0.46));

        // c13

        midlevel = 0.05;
        disp = 1.7;
        dist = 2.0;
        uv2 = uv + float2(t/dist + 38.0, 0.0);
        h = (fbm(uv2, 8, blueNoise) - 0.5)*disp;
        layer(0.1, float3(0.95, 0.66, 0.48));
        layer(0.04, float3(0.98, 0.76, 0.64));
        layer(0., float3(0.95, 0.80, 0.77));

        return float4(0.95, 0.80, 0.77, 0.);
    }

    float4 background(float2 uv, float t, texture2d<float> blueNoise){
        float midlevel;
        float h;
        float disp;
        float dist;
        float2 uv2;

        // clouds ///////////////////////////////////////////////////////

        // c12
        midlevel = 0.3;
        disp = 0.9;
        dist = 10.0;
        uv2 = uv + float2(t/dist + 32.5, 0.0);
        h = (fbm(uv2, 8, blueNoise) - 0.5)*disp;
        layer(0.14, float3(0.48, 0.19, 0.20));
        layer(0.1, float3(0.68, 0.28, 0.19));
        layer(0.07, float3(0.88, 0.38, 0.24));
        layer(0., float3(0.95, 0.45, 0.30));

        // c11
        midlevel = 0.35;
        disp = 1.0;
        dist = 15.0;
        uv2 = uv + float2(t/dist + 30.0, 0.0);
        h = (fbm(uv2, 8, blueNoise) - 0.5)*disp;
        layer(0.04, float3(0.98, 0.76, 0.64));
        layer(0., float3(0.95, 0.80, 0.77));

        // c10
        midlevel = 0.35;
        disp = 3.5;
        dist = 20.0;
        uv2 = uv + float2(t/dist + 27.5, 0.0);
        h = (fbm(uv2, 8, blueNoise) - 0.5)*disp;
        layer(0.12, float3(0.43, 0.32, 0.31));
        layer(0.08, float3(0.55, 0.42, 0.41));
        layer(0.04, float3(0.66, 0.42, 0.40));
        layer(0., float3(0.77, 0.48, 0.46));

        // c9
        midlevel = 0.45;
        disp = 2.0;
        dist = 25.0;
        uv2 = uv + float2(t/dist + 23.0, 0.0);
        h = (fbm(uv2, 8, blueNoise) - 0.5)*disp;
        layer(0.04, float3(0.98, 0.57, 0.36));
        layer(0., float3(1.0, 0.62, 0.44));

        // c8
        midlevel = 0.5;
        disp = 2.3;
        dist = 30.0;
        uv2 = uv + float2(t/dist + 20.5, 0.0);
        h = (fbm(uv2, 8, blueNoise) - 0.5)*disp;
        layer(0.12, float3(0.41, 0.27, 0.27));
        layer(0.08, float3(0.53, 0.35, 0.32));
        layer(0.04, float3(0.80, 0.24, 0.17));
        layer(0., float3(0.99, 0.29, 0.20));

        // c7
        midlevel = 0.5;
        disp = 2.5;
        dist = 35.0;
        uv2 = uv + float2(t/dist + 18.0, 0.0);
        h = (fbm(uv2, 8, blueNoise) - 0.5)*disp;
        layer(0.1, float3(0.88, 0.38, 0.24));
        layer(0.05, float3(0.98, 0.42, 0.28));
        layer(0., float3(1.0, 0.48, 0.35));

        // c6
        midlevel = 0.6;
        disp = 2.0;
        dist = 40.0;
        uv2 = uv + float2(t/dist + 18.0, 0.0);
        h = (fbm(uv2, 8, blueNoise) - 0.5)*disp;
        layer(0.1, float3(0.95, 0.66, 0.48));
        layer(0., float3(1.0, 0.76, 0.60));

        // c5
        midlevel = 0.75;
        disp = 3.5;
        dist = 45.0;
        uv2 = uv + float2(t/dist + 15.5, 0.0);
        h = (fbm(uv2, 8, blueNoise) - 0.5)*disp;
        layer(0.2, float3(1.0, 0.55, 0.33));
        layer(0.15, float3(0.98, 0.50, 0.24));
        layer(0.1, float3(0.90, 0.55, 0.40));
        layer(0., float3(1.0, 0.62, 0.44));

        // c4
        midlevel = 0.7;
        disp = 2.7;
        dist = 50.0;
        uv2 = uv + float2(t/dist + 12.0, 0.0);
        h = (fbm(uv2, 8, blueNoise) - 0.5)*disp;
        layer(0.04, float3(0.73, 0.36, 0.30));
        layer(0., float3(0.80, 0.40, 0.34));

        // c3
        midlevel = 0.8;
        disp = 2.7;
        dist = 60.0;
        uv2 = uv + float2(t/dist + 9.5, 0.0);
        h = (fbm(uv2, 8, blueNoise) - 0.5)*disp;
        layer(0.1, float3(0.93, 0.58, 0.35));
        layer(0., float3(1.0, 0.76, 0.60));

        // c2
        midlevel = 0.9;
        disp = 3.0;
        dist = 70.0;
        uv2 = uv + float2(t/dist + 7.0, 0.0);
        h = (fbm(uv2, 8, blueNoise) - 0.5)*disp;
        layer(0.1, float3(0.56, 0.25, 0.22));
        layer(0.05, float3(0.60, 0.30, 0.27));
        layer(0., float3(0.74, 0.35, 0.30));

        // c1
        midlevel = 1.0;
        disp = 5.0;
        dist = 100.0;
        uv2 = uv + float2(t/dist + 3.5, 0.0);
        h = (fbm(uv2, 8, blueNoise) - 0.5)*disp;
        layer(0.1, float3(0.92, 0.85, 0.82));
        layer(0., float3(1.0, 0.94, 0.91));

        return float4(0.58, 0.7, 1.0, 1.);
    }

    float4 trainScene(float2 fragCoord, float2 iResolution, float iTime, texture2d<float> blueNoise)
    {
        float2 uv = fragCoord/iResolution.y;
        //uv.x += iTime;
        float t = iTime*4.0;
        float4 bg = background(uv, t, blueNoise);

        float4 fg = float4(0.);
        int n = 5;
        if (uv.y < 0.5)
        for (int i = 0; i < n; i++){
            fg += foreground(uv, t+4.*float(i)/float(n)/60., blueNoise) / (float(n));
        }

        float3 col = bg.rgb;
        // train /////////////////////////////////////////////////////////////////////
        float k;
        float midlevel;
        float h;
        float disp;
        float dist;
        float2 uv2;
        uv.y -= 0.2;
        // choo choo
        k = 1.0;
        uv2 = fract(uv*9.0);
        float wagon = 1.0;
        wagon *= 1.0 - step(0.45, uv.x);
        wagon *= 1.0 - step(0.115, uv.y);
        wagon *= step(0.103, uv.y);
        wagon *= step(0.05, 1.0 - abs(uv2.x*2.0 - 1.0));

        float join = 1.0;
        join *= 1.0 - step(0.45, uv.x);
        join *= 1.0 - step(0.11, uv.y);
        join *= step(0.107, uv.y);


        float roof = 1.0;
        roof *= 1.0 - step(0.45, uv.x);
        roof *= 1.0 - step(0.117, uv.y);
        roof *= step(0.11, uv.y);
        roof *= step(0.15, 1.0 - abs(uv2.x*2.0 - 1.0));

        float loco = box(uv, 0.45, 0.5, 0.103, 0.112);
        float chem1 = box(uv, 0.49, 0.495, 0.103, 0.12);
        float chem2 = box(uv, 0.488, 0.496, 0.12, 0.123);
        float locoRoof = box(uv, 0.443, 0.47, 0.11, 0.117);

        float wheel = 1.0 - step(0.00004, dot2(uv - float2(0.457, 0.106)));
        wheel += 1.0 - step(0.00002, dot2(uv - float2(0.487, 0.105)));
        wheel += 1.0 - step(0.00002, dot2(uv - float2(0.497, 0.105)));

        if (uv.x < 0.45 && uv.y > 0.025 && uv.y < 0.2){
            wheel += 1.0 - step(0.002, dot2(uv2 - float2(0.2, 0.95)));
            wheel += 1.0 - step(0.002, dot2(uv2 - float2(0.8, 0.95)));
        }
        col = mix(col, float3(0.18, 0.12, 0.15), join);
        col =  mix(col, float3(0.48, 0.19, 0.20), wagon);
        col = mix(col, float3(0.18, 0.12, 0.15), roof);

        col = mix(col, float3(0.38, 0.19, 0.20), loco);
        col = mix(col, float3(0.38, 0.19, 0.20), chem1);
        col = mix(col, float3(0.18, 0.12, 0.15), locoRoof);
        col = mix(col, float3(0.18, 0.12, 0.15), chem2 + wheel);
        // loco smoke //////

        dist = 5.0;
        uv2 = uv + float2(t/dist + 3.5, 0.0);
        uv2.x -= t/dist*0.2;
        h = fbm2(uv2, 8, blueNoise) - 0.55;

        if(uv.x < 0.49){
            float x = -uv.x + 0.49;
            float y = abs(uv.y + h*0.4 - 0.16*sqrt(x) - 0.12) - 0.8*x*exp(-x*10.0);
            if(y < 0.0) col = float3(1.0, 0.94, 0.91);
            if(y < - 0.02) col = float3(0.92, 0.85, 0.82);
        }

        //bridge ///////
        dist = 5.0;
        uv2 = uv + float2(t/dist + 32.5, 0.0);
        uv2.x = fract(uv2.x*3.0);
        k = 1.0;
        k *= smoothstep(0.001, 0.003, abs(uv2.y - pow(uv2.x - 0.5, 2.0)*0.15 - 0.12));
        k *= min(step(0.05, 1.0 - abs(uv2.x*2.0 - 1.0))
             +   step(0.17, uv2.y), 1.0);
        k *= min(smoothstep(0.02, 0.05, 1.0 - abs(uv2.x*2.0 - 1.0))
             +   step(0.177, uv2.y), 1.0);

        k *= min(step(0.1, uv2.y)
               + smoothstep(-0.09, -0.085, -uv2.y - 0.001/(1.0 - abs(uv2.x*2.0 - 1.0))), 1.0);

        k *= min(smoothstep(0.05, 0.2, 1.0 - abs(fract(uv2.x*16.0)*2.0 - 1.0))
             +   step(0.12, uv2.y - pow(uv2.x - 0.5, 2.0)*0.15)
             +   step(-0.1, -uv2.y), 1.0);
        col = mix(float3(0.29, 0.09, 0.08)*smoothstep(-0.08, 0.08, uv.y), col, k);



        col = mix(col, fg.rgb, fg.a);

        // Output to screen
        uv = fragCoord/iResolution.xy;
        return float4(col,1.0);
    }
    fragment float4 cloudTrainFragment(CloudTrainRasterData in [[stage_in]],
                                        constant CloudTrainUniforms &uniforms [[buffer(0)]],
                                        texture2d<float> blueNoise [[texture(0)]]) {
        float2 fragCoord = in.uv * uniforms.resolution;
        float3 col = trainScene(fragCoord, uniforms.resolution, uniforms.time, blueNoise).rgb;
        float2 uv = fragCoord / uniforms.resolution;
        float vignette = 0.5 + 0.5 * pow(max(0.0, 16.0 * uv.x * uv.y
                                                 * (1.0 - uv.x) * (1.0 - uv.y)), 0.2);
        return float4(col * vignette, 1.0);
    }
    """#
}

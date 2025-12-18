import Foundation
import Metal
import MetalKit
import simd
import UIKit

// Couldn't build .metal in separate file
private enum LiquidGlassShaderSource {
    static let metal: String = """
    #include <metal_stdlib>
    using namespace metal;

    struct VOut {
        float4 position [[position]];
        float2 uv;
    };

    struct Uniforms {
        float2 size;
        float2 center;
        float  refraction;
        float  chroma;

        float  shadowOffset;
        float  shadowBlur;
        float  shadowStrength;

        float  rimThickness;
        float  rimStrength;
        float2 lightDir;

        float  alpha;

        uint   shapeType;
        float  cornerRadiusPx;
        float3 _pad;
    };

    vertex VOut lg_vertex(const device float *v [[buffer(0)]], uint vid [[vertex_id]]) {
        VOut o;
        float2 pos = float2(v[vid * 4 + 0], v[vid * 4 + 1]);
        float2 uv  = float2(v[vid * 4 + 2], v[vid * 4 + 3]);
        o.position = float4(pos, 0.0, 1.0);
        o.uv = uv;
        return o;
    }

    static inline float sdRoundedRect(float2 p, float2 halfSize, float r) {
        float2 q = abs(p) - halfSize + r;
        return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
    }

    fragment half4 lg_fragment(
        VOut in [[stage_in]],
        constant Uniforms& u [[buffer(0)]],
        texture2d<half, access::sample> bg [[texture(0)]],
        sampler s [[sampler(0)]]
    ) {
        float2 p = in.uv * u.size;
        float2 c = u.center * u.size;
        float2 toCenterPx = (p - c);

        // --- Shape SDF (circle / rounded rect) ---
        float dist;
        if (u.shapeType == 0) {
            float radius = min(u.size.x, u.size.y) * 0.5;
            dist = length(toCenterPx) - radius;
        } else {
            float2 halfSize = (u.size * 0.5) - float2(1.0);
            dist = sdRoundedRect(toCenterPx, halfSize, u.cornerRadiusPx);
        }

        // Anti-aliased inside mask (rounded corners clipping)
        float aa = 1.0;
        float inside = smoothstep(0.0, -aa, dist);

        // ============================================================
        // EDGE-BASED REFRACTION + EDGE-ONLY CHROMA  (target look)
        // ============================================================

        float radiusForFalloff = min(u.size.x, u.size.y) * 0.5;
        float normalizedDist = clamp(length(toCenterPx) / max(radiusForFalloff, 1.0), 0.0, 1.0);

        float2 dir = normalize(toCenterPx + float2(1e-5));

        // 0 in the center, rising sharply towards the edges
        const float edgeStart = 0.45;
        const float edgeExp   = 6.0;
        float edgeMask = smoothstep(edgeStart, 1.0, normalizedDist);
        float edgeSharp = pow(edgeMask, edgeExp);

        // Offset in pixels (scaled by radius)
        float2 refractedOffsetPx = dir * (edgeSharp * u.refraction * radiusForFalloff);

        // Chrome only on the edges
        float chromaK = edgeSharp * u.chroma;
        float2 offR = refractedOffsetPx * (1.0 + chromaK);
        float2 offB = refractedOffsetPx * (1.0 - chromaK);

        float2 uvG = (p + refractedOffsetPx) / u.size;
        float2 uvR = (p + offR) / u.size;
        float2 uvB = (p + offB) / u.size;

        half4 colG = bg.sample(s, uvG);
        half4 colR = bg.sample(s, uvR);
        half4 colB = bg.sample(s, uvB);

        half4 outCol = colG;
        outCol.r = colR.r;
        outCol.b = colB.b;

        // Slight milkiness/lightening INSIDE the lens
        const float lift = 0.04; // 0.02..0.06 подбирай
        outCol.rgb = mix(outCol.rgb, half3(1.0h), half(lift * inside));

        // Important: the basic "snapshot" is shown only inside the form
        outCol.rgb *= half(inside);

        // Basic alpha is strictly based on the shape mask (clipping rounded corners)
        outCol.a = half(inside * u.alpha);

        // ============================================================
        // Shadow ring (as you had it), but scaled to u.alpha
        // ============================================================

        float2 shadowCenter = c + float2(u.shadowOffset, u.shadowOffset);
        float shadowDist = length(p - shadowCenter);

        float radiusApprox = radiusForFalloff;
        float shadowRadius = radiusApprox + u.shadowBlur;
        bool inShadowRing = (shadowDist < shadowRadius) && (dist > 0.0);

        if (inShadowRing) {
            float t = (shadowDist - radiusApprox) / max(u.shadowBlur, 1.0);
            float strength = smoothstep(1.0, 0.0, t) * u.shadowStrength * u.alpha;

            // black "haze" around
            outCol.rgb = mix(outCol.rgb, half3(0.0h), half(strength));
            outCol.a = max(outCol.a, half(strength));
        }

        // ============================================================
        // Symmetrical rim + border (without unilateral rimBias)
        // ============================================================

        float edgeAbs = abs(dist);

        // soft rim inside
        float rim = smoothstep(u.rimThickness, 0.0, edgeAbs) * u.rimStrength;
        outCol.rgb += half3(1.05h, 1.05h, 1.10h) * half(rim) * half(inside);

        // thin edge border (360°)
        const float borderW = 1.0;
        const float borderAlpha = 0.10;
        half3 borderColor = half3(0.92h, 0.96h, 1.00h);

        float border = smoothstep(borderW, 0.0, edgeAbs);
        outCol.rgb = mix(outCol.rgb, borderColor, half(borderAlpha * border * u.alpha));
        outCol.a = max(outCol.a, half(borderAlpha * border * u.alpha));

        if (outCol.a <= 0.001h) {
            return half4(0.0h);
        }

        return outCol;
    }

    """
}

final class LiquidGlassRenderer: NSObject, MTKViewDelegate {

    // MARK: Public
    var configuration: LiquidGlassConfiguration = .init()
    var shape: LiquidGlassShape = .circle

    // MARK: Private
    private unowned let mtkView: MTKView
    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private let library: MTLLibrary

    private let pipeline: MTLRenderPipelineState
    private let sampler: MTLSamplerState
    private let vertexBuffer: MTLBuffer

    private var backgroundTexture: MTLTexture?
    private let textureLoader: MTKTextureLoader

    init(mtkView: MTKView) {
        guard let dev = mtkView.device ?? MTLCreateSystemDefaultDevice() else {
            fatalError("Metal device is not available")
        }
        self.mtkView = mtkView
        self.device = dev

        guard let q = dev.makeCommandQueue() else { fatalError("No command queue") }
        self.queue = q

        let options = MTLCompileOptions()
        // options.languageVersion = .version2_4

        do {
            self.library = try dev.makeLibrary(source: LiquidGlassShaderSource.metal, options: options)
        } catch {
            fatalError("Failed to compile LiquidGlass shader: \(error)")
        }

        self.textureLoader = MTKTextureLoader(device: dev)

        // Fullscreen quad (pos.xy, uv.xy)
        let quad: [Float] = [
            -1, -1,  0, 1,
             1, -1,  1, 1,
            -1,  1,  0, 0,
             1,  1,  1, 0
        ]
        self.vertexBuffer = dev.makeBuffer(bytes: quad, length: quad.count * MemoryLayout<Float>.size, options: [])!

        let samplerDesc = MTLSamplerDescriptor()
        samplerDesc.minFilter = .linear
        samplerDesc.magFilter = .linear
        samplerDesc.sAddressMode = .clampToEdge
        samplerDesc.tAddressMode = .clampToEdge
        self.sampler = dev.makeSamplerState(descriptor: samplerDesc)!

        let pipelineDesc = MTLRenderPipelineDescriptor()
        pipelineDesc.vertexFunction = library.makeFunction(name: "lg_vertex")
        pipelineDesc.fragmentFunction = library.makeFunction(name: "lg_fragment")
        pipelineDesc.colorAttachments[0].pixelFormat = mtkView.colorPixelFormat

        let att = pipelineDesc.colorAttachments[0]!
        att.isBlendingEnabled = true
        att.rgbBlendOperation = .add
        att.alphaBlendOperation = .add
        att.sourceRGBBlendFactor = .sourceAlpha
        att.destinationRGBBlendFactor = .oneMinusSourceAlpha
        att.sourceAlphaBlendFactor = .one
        att.destinationAlphaBlendFactor = .oneMinusSourceAlpha

        self.pipeline = try! dev.makeRenderPipelineState(descriptor: pipelineDesc)
        
        super.init()
        mtkView.delegate = self
    }

    func updateBackground(cgImage: CGImage) {
        let options: [MTKTextureLoader.Option: Any] = [
            .SRGB: false,
            .origin: MTKTextureLoader.Origin.topLeft
        ]
        self.backgroundTexture = try? textureLoader.newTexture(cgImage: cgImage, options: options)
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
    
    func draw(in view: MTKView) {
        guard let drawable = mtkView.currentDrawable,
              let rpd = mtkView.currentRenderPassDescriptor,
              let bg = backgroundTexture
        else { return }

        // uniforms
        var u = Uniforms()
        u.size = SIMD2<Float>(Float(bg.width), Float(bg.height))
        u.center = SIMD2<Float>(0.5, 0.5)
        u.refraction = configuration.refraction
        u.chroma = configuration.chroma
        u.shadowOffset = configuration.shadowOffset
        u.shadowBlur = configuration.shadowBlur
        u.shadowStrength = configuration.shadowStrength
        u.rimThickness = configuration.rimThickness
        u.rimStrength = configuration.rimStrength
//        u.lightDir = simd_normalize(configuration.lightDir)
        u.alpha = configuration.alpha

        switch shape {
        case .circle:
            u.shapeType = 0
            u.cornerRadiusPx = 0
        case .roundedRect(let r):
            u.shapeType = 1
            // конвертим cornerRadius из points в пиксели текстуры (примерно)
            let scale = max(Float(bg.width) / Float(mtkView.drawableSize.width), 1.0)
            u.cornerRadiusPx = Float(r) * scale
        }

        guard let cmd = queue.makeCommandBuffer(),
              let enc = cmd.makeRenderCommandEncoder(descriptor: rpd) else { return }

        enc.setRenderPipelineState(pipeline)
        enc.setVertexBuffer(vertexBuffer, offset: 0, index: 0)

        enc.setFragmentTexture(bg, index: 0)
        enc.setFragmentSamplerState(sampler, index: 0)
        enc.setFragmentBytes(&u, length: MemoryLayout<Uniforms>.stride, index: 0)

        enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        enc.endEncoding()

        cmd.present(drawable)
        cmd.commit()
    }
}

// MARK: - Metal uniforms (must match .metal)

struct Uniforms {
    var size: SIMD2<Float> = .zero          // texture size in px
    var center: SIMD2<Float> = .init(0.5, 0.5)

    var refraction: Float = 0
    var chroma: Float = 0

    var shadowOffset: Float = 0
    var shadowBlur: Float = 0
    var shadowStrength: Float = 0

    var rimThickness: Float = 0
    var rimStrength: Float = 0
    var lightDir: SIMD2<Float> = .init(-0.5, -0.8)

    var alpha: Float = 1

    // 0 circle, 1 roundedRect
    var shapeType: UInt32 = 0
    var cornerRadiusPx: Float = 0

    // padding for alignment
    var _pad: SIMD3<Float> = .zero
}

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

        float  brightnessBoost;   // NEW 0..0.2
        float  edgeBlurWidthPx;     // ширина ободка (в пикселях), = 10pt * scale
        float  edgeBlurRadiusPx;    // “сила” размытия на самой границе (в пикселях)
        float  edgeNoiseStrength;   // шум в ободке (0..~0.06)
        float  edgeBlurMix;         // сколько подмешивать blur (0..1)

        uint   shapeType;
        float  cornerRadiusPx;
        float2 _pad;
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
    
    static inline float hash21(float2 p) {
        // быстрый псевдорандом 0..1
        float h = dot(p, float2(127.1, 311.7));
        return fract(sin(h) * 43758.5453123);
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
        float extraLift = clamp(u.brightnessBoost, 0.0, 0.10);
        float lift = 0.04 + extraLift; // базовый + динамический
        lift = clamp(lift, 0.0, 0.14); // не выходим за 14%
    
        // ---- lens blur (UIVisualEffect-ish) ----
        // Blur should be here
        
        // Important: the basic "snapshot" is shown only inside the form
        outCol.rgb *= inside;

        // Basic alpha is strictly based on the shape mask (clipping rounded corners)
        outCol.a = half(inside * u.alpha);        

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
//float nd = normalizedDist;                 // 0..1
//float edge = edgeSharp;                    // уже есть
//float blurK = inside * (0.20 + 0.80 * edge); // blur больше у края, но есть и в центре
//
//// радиус blur в пикселях: 1..~8 (тюнится)
//float blurPx = mix(1.2, 8.0, blurK);
//float2 texel = (blurPx / u.size);
//
//// 9 taps (крест + диагонали)
//half3 s0 = bg.sample(s, uvG).rgb;
//half3 s1 = bg.sample(s, uvG + texel * float2( 1, 0)).rgb;
//half3 s2 = bg.sample(s, uvG + texel * float2(-1, 0)).rgb;
//half3 s3 = bg.sample(s, uvG + texel * float2( 0, 1)).rgb;
//half3 s4 = bg.sample(s, uvG + texel * float2( 0,-1)).rgb;
//half3 s5 = bg.sample(s, uvG + texel * float2( 1, 1)).rgb;
//half3 s6 = bg.sample(s, uvG + texel * float2(-1, 1)).rgb;
//half3 s7 = bg.sample(s, uvG + texel * float2( 1,-1)).rgb;
//half3 s8 = bg.sample(s, uvG + texel * float2(-1,-1)).rgb;
//
//half3 blurred = (s0*2.0h + s1+s2+s3+s4 + s5+s6+s7+s8) / half(10.0);
//
//// подмешиваем blur к текущему outCol
//outCol.rgb = mix(outCol.rgb, blurred, half(blurK * 0.85));

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
        u.brightnessBoost = configuration.brightnessBoost
        
        let pxPerPt = max(Float(bg.width) / Float(mtkView.drawableSize.width), 1.0)

        u.edgeBlurWidthPx   = 10.0 * pxPerPt
        u.edgeBlurRadiusPx  = 8.0 * pxPerPt
        u.edgeNoiseStrength = 0.035
        u.edgeBlurMix       = 1.0

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
    var size: SIMD2<Float> = .zero
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

    /// 0..0.2 — extra lift к «молочности»
    var brightnessBoost: Float = 0      // NEW
    
    var edgeBlurWidthPx: Float = 0
    var edgeBlurRadiusPx: Float = 0
    var edgeNoiseStrength: Float = 0
    var edgeBlurMix: Float = 0

    // 0 circle, 1 roundedRect
    var shapeType: UInt32 = 0
    var cornerRadiusPx: Float = 0

    // padding для выравнивания с metal Uniforms
    var _pad: SIMD2<Float> = .zero
}


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

        float dist;
        if (u.shapeType == 0) {
            float radius = min(u.size.x, u.size.y) * 0.5;
            dist = length(toCenterPx) - radius;
        } else {
            float2 halfSize = (u.size * 0.5) - float2(1.0);
            dist = sdRoundedRect(toCenterPx, halfSize, u.cornerRadiusPx);
        }

        float aa = 1.0;
        float inside = smoothstep(0.0, -aa, dist);

        float radiusForFalloff = min(u.size.x, u.size.y) * 0.5;
        float normalizedDist = clamp(length(toCenterPx) / max(radiusForFalloff, 1.0), 0.0, 1.0);
        float falloff = 1.0 - (normalizedDist * normalizedDist);

        float2 refractedOffsetPx = toCenterPx * falloff * u.refraction;

        float chromaK = normalizedDist * u.chroma;
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

        float2 shadowCenter = c + float2(u.shadowOffset, u.shadowOffset);
        float shadowDist = length(p - shadowCenter);

        float radiusApprox = radiusForFalloff;
        float shadowRadius = radiusApprox + u.shadowBlur;
        bool inShadowRing = (shadowDist < shadowRadius) && (dist > 0.0);

        if (inShadowRing) {
            float t = (shadowDist - radiusApprox) / max(u.shadowBlur, 1.0);
            float strength = smoothstep(1.0, 0.0, t) * u.shadowStrength;
            outCol.rgb = mix(outCol.rgb, half3(0.0), half(strength));
            outCol.a = max(outCol.a, half(strength));
        }

        float edge = abs(dist);
        float rim = smoothstep(u.rimThickness, 0.0, edge) * u.rimStrength;

        float2 dir = normalize(toCenterPx);
        float rimBias = clamp(dot(dir, u.lightDir), 0.0, 1.0);

        outCol.rgb += half3(1.1h, 1.1h, 1.2h) * half(rim * rimBias);

        float alpha = max(inside, (float)outCol.a);
        outCol.a = half(alpha * u.alpha);

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

        // alpha blending (чтобы снаружи формы было прозрачно)
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
        u.lightDir = simd_normalize(configuration.lightDir)
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

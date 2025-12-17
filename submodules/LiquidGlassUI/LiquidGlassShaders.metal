#include <metal_stdlib>
using namespace metal;

struct VOut {
    float4 position [[position]];
    float2 uv;
};

struct Uniforms {
    float2 size;        // px
    float2 center;      // 0..1
    float  refraction;
    float  chroma;

    float  shadowOffset;    // px
    float  shadowBlur;      // px
    float  shadowStrength;

    float  rimThickness;    // px
    float  rimStrength;
    float2 lightDir;

    float  alpha;

    uint   shapeType;       // 0 circle, 1 roundedRect
    float  cornerRadiusPx;  // px
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

// Signed distance to rounded rect (Inigo Quilez style)
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
    // pixel space inside the captured texture
    float2 p = in.uv * u.size;              // px in [0..size]
    float2 c = u.center * u.size;           // px center
    float2 toCenterPx = (p - c);

    // Shape mask via SDF
    float dist; // signed distance: <0 inside
    if (u.shapeType == 0) {
        float radius = min(u.size.x, u.size.y) * 0.5;
        dist = length(toCenterPx) - radius;
    } else {
        float2 halfSize = (u.size * 0.5) - float2(1.0);
        dist = sdRoundedRect(toCenterPx, halfSize, u.cornerRadiusPx);
    }

    // Anti-aliasing in px
    float aa = 1.0;
    float inside = smoothstep(0.0, -aa, dist);   // 1 inside, 0 outside
    if (inside <= 0.001) {
        // still allow shadow ring outside
        inside = 0.0;
    }

    // Refraction falloff based on normalized distance to center (radial)
    float radiusForFalloff = min(u.size.x, u.size.y) * 0.5;
    float normalizedDist = clamp(length(toCenterPx) / max(radiusForFalloff, 1.0), 0.0, 1.0);
    float falloff = 1.0 - (normalizedDist * normalizedDist); // parabolic (1 - r^2) :contentReference[oaicite:2]{index=2}

    float2 refractedOffsetPx = toCenterPx * falloff * u.refraction;

    // Chromatic aberration stronger at the edge :contentReference[oaicite:3]{index=3}
    float chromaK = normalizedDist * u.chroma;
    float2 offR = refractedOffsetPx * (1.0 + chromaK);
    float2 offB = refractedOffsetPx * (1.0 - chromaK);

    float2 uvG = (p + refractedOffsetPx) / u.size;
    float2 uvR = (p + offR) / u.size;
    float2 uvB = (p + offB) / u.size;

    half4 colG = bg.sample(s, uvG);
    half4 colR = bg.sample(s, uvR);
    half4 colB = bg.sample(s, uvB);

    half4 refracted = colG;
    refracted.r = colR.r;
    refracted.b = colB.b;

    half4 outCol = refracted;

    // Shadow/occlusion halo outside shape (offset down-right) :contentReference[oaicite:4]{index=4}
    // We'll approximate using radial distance anyway
    float2 shadowCenter = c + float2(u.shadowOffset, u.shadowOffset);
    float shadowDist = length(p - shadowCenter);

    float radiusApprox = radiusForFalloff;
    float shadowRadius = radiusApprox + u.shadowBlur;
    bool inShadowRing = (shadowDist < shadowRadius) && (dist > 0.0);

    if (inShadowRing) {
        float t = (shadowDist - radiusApprox) / max(u.shadowBlur, 1.0);
        float strength = smoothstep(1.0, 0.0, t) * u.shadowStrength;
        // darken a bit
        outCol.rgb = mix(outCol.rgb, half3(0.0), half(strength));
        outCol.a = max(outCol.a, half(strength));
    }

    // Rim highlight at the edge, directional (upper-left) :contentReference[oaicite:5]{index=5}
    float edge = abs(dist);
    float rim = smoothstep(u.rimThickness, 0.0, edge) * u.rimStrength;

    float2 dir = normalize(toCenterPx);
    float rimBias = clamp(dot(dir, u.lightDir), 0.0, 1.0);

    half3 highlight = half3(1.1h, 1.1h, 1.2h) * half(rim * rimBias);
    outCol.rgb += highlight;

    // final alpha: inside shape => visible, outside => only shadow/rim if present
    float alpha = max(inside, (float)outCol.a);
    outCol.a = half(alpha * u.alpha);

    // If completely outside and no halo, keep it transparent
    if (outCol.a <= 0.001h) {
        return half4(0.0h);
    }

    return outCol;
}


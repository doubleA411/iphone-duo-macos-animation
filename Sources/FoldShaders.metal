#include <metal_stdlib>
using namespace metal;

constant float MAX_TILT = 1.50098316; // 86 degrees: a pronounced near-flat fold
constant float3 DARK = float3(0.003, 0.004, 0.005);

struct Uniforms {
    float2 imageSize;
    float2 cover;
    float aspect;
    float turn;
    float blurStrength;
    float reflectionIntensity;
};

struct VertexOut {
    float4 position [[position]];
    float2 uv;
};

vertex VertexOut foldVertex(uint vid [[vertex_id]]) {
    const float2 positions[6] = {
        float2(-1.0, -1.0),
        float2( 1.0, -1.0),
        float2(-1.0,  1.0),
        float2(-1.0,  1.0),
        float2( 1.0, -1.0),
        float2( 1.0,  1.0)
    };
    
    VertexOut out;
    float2 pos = positions[vid];
    out.position = float4(pos, 0.0, 1.0);
    // UV origin: (0,0) at top-left, (1,1) at bottom-right
    out.uv = float2(pos.x * 0.5 + 0.5, 0.5 - pos.y * 0.5);
    return out;
}

inline float3 sampleSmoothMatteBlur(texture2d<float> tex,
                                    sampler s,
                                    float2 uv,
                                    float radius,
                                    float2 cover,
                                    float2 uiPixel,
                                    float2 screenCoord) {
    float2 tuv = (uv - 0.5) * cover + 0.5;
    
    // When radius is near zero, return razor-sharp native Retina sample at level 0
    if (radius <= 0.15) {
        return tex.sample(s, tuv, level(0.0)).rgb;
    }
    
    // Low-pass before broad sampling to keep the frost smooth during motion.
    float baseLod = clamp(log2(max(1.0, radius * 0.3)), 0.0, 4.5);
    float cosRot = 1.0;
    float sinRot = 0.0;

    float3 accum = float3(0.0);
    float totalWeight = 0.0;
    
    // 32-sample Vogel Disc (Golden Angle Fermat Spiral)
    constexpr int NUM_SAMPLES = 32;
    constexpr float GOLDEN_ANGLE = 2.39996323; // pi * (3.0 - sqrt(5.0))
    
    for (int i = 0; i < NUM_SAMPLES; i++) {
        float fi = float(i);
        float theta = fi * GOLDEN_ANGLE;
        // Square root progression provides uniform area density across the disc
        float r = sqrt((fi + 0.5) / float(NUM_SAMPLES));
        
        // Direction rotated by micro-jitter
        float uX = cos(theta);
        float uY = sin(theta);
        float dirX = uX * cosRot - uY * sinRot;
        float dirY = uX * sinRot + uY * cosRot;
        
        float2 offset = float2(dirX, dirY) * (r * radius * uiPixel);
        float2 sampleUV = clamp(tuv + offset, 0.0, 1.0);
        
        // Gaussian optical falloff from center of blur disc
        float weight = exp(-2.3 * r * r);
        
        // Center samples draw fine details; perimeter samples blend into smooth mip
        float sampleLod = baseLod;
        
        accum += tex.sample(s, sampleUV, level(sampleLod)).rgb * weight;
        totalWeight += weight;
    }
    
    float3 blurred = accum / totalWeight;
    
    // Soft matte ambient scatter (frosted glass diffusion characteristic)
    float matteScatter = 0.015 * smoothstep(0.0, 20.0, radius);
    blurred = blurred + float3(matteScatter);
    
    // Smooth transition from sharp to matte blur as fold begins
    float3 sharp = tex.sample(s, tuv, level(0.0)).rgb;
    return mix(sharp, blurred, smoothstep(0.0, 2.0, radius));
}

// Mac reference: bottom content stays anchored while upper content stretches
// off the top edge, narrowing in perspective and progressively frosting.
fragment float4 foldFragment(VertexOut in [[stage_in]],
                             texture2d<float> tex [[texture(0)]],
                             sampler s [[sampler(0)]],
                             constant Uniforms &u [[buffer(0)]]) {
    float turn = clamp(u.turn, 0.0, 1.0);
    float2 uiPixel = 2.0 / max(float2(1.0), u.imageSize);
    if (turn <= 0.00001) {
        return float4(sampleSmoothMatteBlur(tex, s, in.uv, 0.0, u.cover, uiPixel, in.position.xy), 1.0);
    }
    float progress = turn * smoothstep(0.0, 0.08, turn);
    float fromBottom = 1.0 - in.uv.y;
    // At 50% closure the top samples the middle of the original image. The
    // bottom always samples y=1, giving the upward stretch visible in the clip.
    float compression = max(0.025, pow(1.0 - progress, 1.12));
    float taper = 0.55 * smoothstep(0.0, 0.92, progress);
    float perspective = 1.0 / (1.0 - taper * fromBottom);
    float2 source = float2(0.5 + (in.uv.x - 0.5) * perspective,
                          1.0 - fromBottom * compression);

    // Soft side boundaries; never create a free-floating card or a top border.
    float halfWidth = 0.5 / perspective;
    float sideDistance = abs(in.uv.x - 0.5) - halfWidth;
    float feather = max(fwidth(in.uv.x), 0.024 * progress * pow(fromBottom, 1.25));
    float silhouette = 1.0 - smoothstep(-feather, feather, sideDistance);
    if (silhouette <= 0.0001) { return float4(DARK, 1.0); }

    // Focus falls off toward the top, not as a moving horizontal blur curtain.
    float defocus = pow(fromBottom, 1.65) * smoothstep(0.0, 0.72, progress);
    float radius = 105.0 * defocus * max(0.0, u.blurStrength);
    float3 color = sampleSmoothMatteBlur(tex, s, clamp(source, 0.0, 1.0), radius,
                                         u.cover, uiPixel, in.position.xy);
    // Neutral dark glass near the upper margins, no colored wave or bright rim.
    float edgeShadow = smoothstep(halfWidth * 0.68, halfWidth, abs(in.uv.x - 0.5));
    color *= 1.0 - 0.12 * progress * fromBottom - 0.10 * edgeShadow * progress;
    float closeFade = 1.0 - smoothstep(0.88, 1.0, turn);
    return float4(mix(DARK, color, silhouette * closeFade), 1.0);
}

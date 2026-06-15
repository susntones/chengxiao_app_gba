#include <metal_stdlib>
using namespace metal;

// MARK: - Vertex Shader

struct VertexIn {
    float2 position [[attribute(0)]];
    float2 texCoord [[attribute(1)]];
};

struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
};

struct VertexData {
    float2 position;
    float2 texCoord;
};

vertex VertexOut vertexShader(
    uint vertexID [[vertex_id]],
    const device VertexData* vertices [[buffer(0)]],
    constant float2& viewportSize [[buffer(1)]],
    constant int& scalingMode [[buffer(2)]]
) {
    VertexOut out;

    float2 pos = vertices[vertexID].position;

    // Apply aspect ratio correction based on scaling mode
    if (scalingMode == 0) {
        // Fit: maintain 3:2 aspect ratio with letterboxing
        float gbaAspect = 240.0 / 160.0; // 3:2
        float viewAspect = viewportSize.x / viewportSize.y;

        if (viewAspect > gbaAspect) {
            // Wider than GBA - letterbox horizontally
            pos.x *= gbaAspect / viewAspect;
        } else {
            // Taller than GBA - letterbox vertically
            pos.y *= viewAspect / gbaAspect;
        }
    } else if (scalingMode == 2) {
        // Integer: scale by whole multiples
        float scaleX = floor(viewportSize.x / 240.0);
        float scaleY = floor(viewportSize.y / 160.0);
        float scale = min(scaleX, scaleY);
        if (scale < 1.0) scale = 1.0;

        float finalWidth = 240.0 * scale / viewportSize.x;
        float finalHeight = 160.0 * scale / viewportSize.y;

        pos.x *= finalWidth;
        pos.y *= finalHeight;
    }
    // scalingMode == 1 (Fill): no adjustment, stretch to fill

    out.position = float4(pos, 0.0, 1.0);
    out.texCoord = vertices[vertexID].texCoord;

    return out;
}

// MARK: - Fragment Shader

fragment float4 fragmentShader(
    VertexOut in [[stage_in]],
    texture2d<float> gameTexture [[texture(0)]],
    sampler texSampler [[sampler(0)]]
) {
    float4 color = gameTexture.sample(texSampler, in.texCoord);

    // Swap R and B channels (mGBA outputs RGBA, Metal expects BGRA)
    // Actually keep as-is since we're using rgba8Unorm texture format
    return color;
}

// MARK: - CRT Effect Shader (optional, for future use)

fragment float4 crtFragmentShader(
    VertexOut in [[stage_in]],
    texture2d<float> gameTexture [[texture(0)]],
    sampler texSampler [[sampler(0)]]
) {
    float4 color = gameTexture.sample(texSampler, in.texCoord);

    // Simple scanline effect
    float scanline = sin(in.texCoord.y * 160.0 * 3.14159) * 0.5 + 0.5;
    scanline = mix(0.85, 1.0, scanline);

    color.rgb *= scanline;

    // Slight vignette
    float2 uv = in.texCoord * 2.0 - 1.0;
    float vignette = 1.0 - dot(uv * 0.5, uv * 0.5);
    color.rgb *= vignette;

    return color;
}

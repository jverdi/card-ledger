#include <metal_stdlib>
using namespace metal;
// This affects presentation only. Original and cropped card assets are never modified.
[[ stitchable ]] half4 cardFoil(float2 position, half4 color, float2 size, float time) {
    float2 uv = position / max(size, float2(1.0));
    float sweep = sin(time * 0.8) * 1.4;
    float band = exp(-pow((uv.x + uv.y * 0.48 - 0.75 - sweep) * 4.0, 2.0));
    float3 rainbow = 0.5 + 0.5 * cos(6.28318 * (uv.x * 0.8 + uv.y * 0.55 + time * 0.07 + float3(0.0,0.33,0.67)));
    float glint = pow(max(0.0, sin((uv.x - uv.y + time * 0.13) * 21.0)), 24.0) * band;
    half3 shine = half3(rainbow * band * 0.22 + glint * 0.12) * color.a;
    return half4(min(color.rgb + shine, half3(color.a)), color.a);
}

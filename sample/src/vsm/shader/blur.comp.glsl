#version 460 core

layout(set = 0, binding = 0) uniform sampler2D source;
layout(set = 0, binding = 1, rg32f) writeonly uniform image2D dest;

const float kernel[] = float[9](
    0.0276306,
    0.0662822,
    0.123832,
    0.180174,
    0.204164,
    0.180174,
    0.123832,
    0.0662822,
    0.0276306);

void main() {
    const vec2 gid = gl_GlobalInvocationID.xy;
    const vec2 uv = gid / imageSize(dest);
    const float d = 1.0 / textureSize(source, 0).x;
    const int off = -kernel.length() / 2;

    vec4 sum = vec4(0.0);
    for (int i = 0; i < kernel.length(); i++)
        sum += textureLod(source, vec2(uv.s + d * (off + i), uv.t), 0.0) * kernel[i];

    imageStore(dest, ivec2(gid), sum);
}

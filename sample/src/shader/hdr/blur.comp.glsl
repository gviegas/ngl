#version 460 core

layout(set = 0, binding = 1, rgba16f) readonly uniform image2D source;
layout(set = 0, binding = 2, rgba16f) writeonly uniform image2D dest;

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
    const ivec2 gid = ivec2(gl_GlobalInvocationID.xy);
    const ivec2 bounds = imageSize(source);
    const int off = -kernel.length() / 2;

    vec4 sum = vec4(0.0);

    if (gid.y < -off || gid.y - off >= bounds.y)
        for (int i = 0; i < kernel.length(); i++) {
            const int y = clamp(gid.y + off + i, 0, bounds.y - 1);
            sum += imageLoad(source, ivec2(gid.x, y)) * kernel[i];
        }
    else
        for (int i = 0; i < kernel.length(); i++)
            sum += imageLoad(source, ivec2(gid.x, gid.y + off + i)) * kernel[i];

    imageStore(dest, gid, sum);
}

#version 460 core

layout(constant_id = 0) const uint source_width = 0;
layout(constant_id = 1) const uint source_height = 0;

layout(set = 0, binding = 4, r32f) readonly uniform image2D source;
layout(set = 0, binding = 5, r32f) writeonly uniform image2D dest;

void main() {
    const uvec2 gid = gl_GlobalInvocationID.xy;
    const ivec2 coord = ivec2(gid) * 2;
    float lum = imageLoad(source, coord).r;

    if (coord.x + 1 < source_width && coord.y + 1 < source_height) {
        lum += imageLoad(source, coord + ivec2(1, 0)).r;
        lum += imageLoad(source, coord + ivec2(0, 1)).r;
        lum += imageLoad(source, coord + ivec2(1, 1)).r;
        lum *= 0.25;
    }

    imageStore(dest, ivec2(gid), vec4(lum));
}

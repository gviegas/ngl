#version 460 core

layout(constant_id = 0) const float inv_width = 0.0;
layout(constant_id = 1) const float inv_height = 0.0;
layout(constant_id = 2) const float threshold = 1.0;

layout(set = 0, binding = 0) uniform sampler2D hdr_map;
layout(set = 0, binding = 1, rgba16f) writeonly uniform image2D bloom_map;

float luminance(vec3 color) {
    return dot(color, vec3(0.2126, 0.7152, 0.0722));
}

void main() {
    const uvec2 gid = gl_GlobalInvocationID.xy;
    const vec2 tc = vec2(inv_width, inv_height) * vec2(gid);

    const vec4 col = texture(hdr_map, tc);

    if (luminance(col.rgb) > threshold)
        imageStore(bloom_map, ivec2(gid), col);
    else
        imageStore(bloom_map, ivec2(gid), vec4(0.0));
}

#version 460 core

layout(constant_id = 0) const float inv_width = 0.0;
layout(constant_id = 1) const float inv_height = 0.0;

layout(set = 0, binding = 0) uniform sampler2D hdr_map;
layout(set = 0, binding = 4, r32f) writeonly uniform image2D tone_map;

float luminance(vec3 color) {
    return dot(color, vec3(0.2126, 0.7152, 0.0722));
}

void main() {
    const uvec2 gid = gl_GlobalInvocationID.xy;
    const vec2 tc = vec2(inv_width, inv_height) * vec2(gid);

    vec4 col = texture(hdr_map, tc);
    col += texture(hdr_map, tc + vec2(inv_width, 0.0));
    col += texture(hdr_map, tc + vec2(0.0, inv_height));
    col += texture(hdr_map, tc + vec2(inv_width, inv_height));

    imageStore(tone_map, ivec2(gid), vec4(luminance(col.rgb) * 0.25));
}

#version 460 core

#if defined(FIRST_ITERATION)
const uint comb_bind = 0;
const uint stor_bind = 7;
#elif defined(EVEN_ITERATION)
const uint comb_bind = 5;
const uint stor_bind = 7;
#elif defined(ODD_ITERATION)
const uint comb_bind = 6;
const uint stor_bind = 8;
#else
#error Missing define
#endif

layout(constant_id = 0) const float inv_u_scale = 0.0;
layout(constant_id = 1) const float inv_v_scale = 0.0;

layout(set = 0, binding = comb_bind) uniform sampler2D source;
// TODO: Should be `r16f` (note that such format might not
// support image stores).
layout(set = 0, binding = stor_bind, rgba16f) writeonly uniform image2D dest;

float luminance(vec3 color) {
    return dot(color, vec3(0.2126, 0.7152, 0.0722));
}

void main() {
    const uvec2 gid = gl_GlobalInvocationID.xy;
    const vec2 uv = (gid + 0.5) * vec2(inv_u_scale, inv_v_scale);

    vec4 col = textureLod(source, uv, 0.0);
#ifdef FIRST_ITERATION
    col = vec4(
        1.0 / (1.2 * exp2(log2(luminance(col.rgb) * 100.0 / 12.5))),
        0.0,
        0.0,
        1.0);
#endif

    imageStore(dest, ivec2(gid), col);
}

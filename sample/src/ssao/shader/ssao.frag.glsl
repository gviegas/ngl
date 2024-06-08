#version 460 core

layout(constant_id = 0) const float ao_scale = 1.0;
layout(constant_id = 1) const float ao_bias = 0.0;
layout(constant_id = 2) const float ao_intensity = 1.0;
layout(constant_id = 3) const int ao_sample_count = 1;

layout(set = 0, binding = 0) uniform sampler2D color;
layout(set = 0, binding = 1) uniform sampler2D normal;
layout(set = 0, binding = 2) uniform sampler2DMS depth;
layout(set = 0, binding = 3) uniform sampler2D random_sampling;

layout(set = 0, binding = 4) uniform Camera {
    mat4 inv_p;
} camera;

layout(location = 0) in vec2 uv;

layout(location = 0) out vec4 color_0;

const vec2 locations[] = vec2[8](
    vec2(0.0883883),
    vec2(-0.176777, 0.176777),
    vec2(-0.265165),
    vec2(0.353554, -0.353553),
    vec2(0.0, 0.625),
    vec2(-0.75, 0.0),
    vec2(0.0, -0.875),
    vec2(1.0, 0.0));

float getDepth(ivec2 iuv) {
    const int spl_cnt = textureSamples(depth);
    float dep = 0.0;
    for (int spl = 0; spl < spl_cnt; spl++)
        dep += texelFetch(depth, iuv, spl).r;
    return dep * (1.0 / spl_cnt);
}

float aoAmount(vec3 pos_2, vec3 pos, vec3 dir) {
    const vec3 v = pos_2 - pos - 1e-5;
    return
        max(0.1, dot(dir, normalize(v)) - ao_bias) *
        (1.0 / (1.0 + length(v) * ao_scale)) *
        ao_intensity;
}

void main() {
    const ivec2 iuv = ivec2(uv * textureSize(depth));
    const float dep = getDepth(iuv);

    color_0 = texture(color, uv);

    if (dep >= 1.0)
        return;

    vec4 pos = camera.inv_p * vec4(uv, dep, 1.0);
    pos.xyz /= pos.w;

    const vec3 n = normalize(texture(normal, uv).xyz * 2.0 - 1.0);

    const vec2 ruv = gl_FragCoord.xy / textureSize(random_sampling, 0);
    const vec2 rnd = normalize(texture(random_sampling, ruv).rg * 2.0 - 1.0);

    const int deps_len = 4;
    const vec2 size = textureSize(color, 0);

    float ao = 0.0;
    for (int i = 0; i < locations.length(); i++) {
        const ivec2 off = ivec2(locations[i] * rnd * size);

        const float deps[] = float[deps_len](
            getDepth(iuv + off),
            getDepth(iuv + ivec2(-off.x, off.y)),
            getDepth(iuv - ivec2(-off.x, off.y)),
            getDepth(iuv - off));

        for (int j = 0; j < deps.length(); j++) {
            vec4 pos_2 = camera.inv_p * vec4(uv, deps[j], 1.0);
            pos_2.xyz /= pos_2.w;
            ao += aoAmount(pos_2.xyz, pos.xyz, n);
        }
    }
    ao *= 1.0 / locations.length() / deps_len;

    color_0 = vec4(vec3(0.0), ao) + color_0 * vec4(1.0 - ao);
}

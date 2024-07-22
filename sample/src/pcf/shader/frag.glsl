#version 460 core

const float pi = 3.141592653589793;

layout(constant_id = 0) const int shadow_sample_count = 1;

layout(set = 0, binding = 0) uniform sampler2DShadow shadow_map;
layout(set = 0, binding = 1) uniform sampler3D random_sampling;

layout(set = 0, binding = 2) uniform Light {
    vec3 position;
    vec3 color;
    float intensity;
} light;

layout(set = 1, binding = 0) uniform Material {
    vec4 color;
    float metallic;
    float smoothness;
    float reflectance;
} material;

layout(location = 0) in Vertex {
    vec3 position;
    vec3 normal;
    vec4 shadow;
} vertex;

layout(location = 0) out vec4 color_0;

float dGgx(float n_dot_h, float m) {
    const float m_2 = m * m;
    const float f = (n_dot_h * m_2 - n_dot_h) * n_dot_h + 1.0;
    return m_2 / (f * f) * (1.0 / pi);
}

float vSmithGgxCorrelated(float n_dot_v, float n_dot_l, float roughness) {
    return 0.5 / mix(2.0 * n_dot_v * n_dot_l, n_dot_v + n_dot_l, roughness);
}

vec3 fSchlick(vec3 f0, float u) {
    const float f90 = 1.0;
    return f0 + (f90 - f0) * pow(1.0 - u, 5.0);
}

vec3 fdLambert(vec3 diffuse_color) {
    return diffuse_color * (1.0 / pi);
}

float shadowFactor() {
    if (vertex.shadow.w <= 1.0)
        return 1.0;

    const vec2 uv = gl_FragCoord.xy / textureSize(random_sampling, 0).xy;
    const float d = 1.0 / shadow_sample_count;
    float shdw_fac = 0.0;

    for (int i = 0; i < shadow_sample_count; i++) {
        const vec3 uvw = vec3(uv, d * i);
        const vec2 rnd = normalize(texture(random_sampling, uvw).rg * 2.0 - 1.0);
        const vec4 off = vec4(0.075 * rnd, 0.0, 0.0);
        shdw_fac += textureProj(shadow_map, vertex.shadow + off);
    }

    shdw_fac *= 1.0 / shadow_sample_count;
    return shdw_fac;
}

vec3 lightFactor(float n_dot_l) {
    const float dist = length(light.position - vertex.position);
    const float atten = 1.0 / max(dist * dist, 1e-4);
    return light.color * light.intensity * atten * n_dot_l;
}

void main() {
    color_0.rgb = vec3(0.0);
    color_0.a = material.color.a;

    const vec3 n = normalize(vertex.normal);
    const vec3 l = normalize(light.position - vertex.position);
    const float n_dot_l = clamp(dot(n, l), 0.0, 1.0);

    if (n_dot_l <= 1e-5)
        return;

    const vec3 v = normalize(-vertex.position);
    const vec3 h = normalize(v + l);
    const float n_dot_v = abs(dot(n, v)) + 1e-5;
    const float n_dot_h = clamp(dot(n, h), 0.0, 1.0);
    const float v_dot_h = clamp(dot(v, h), 0.0, 1.0);

    const float metal = material.metallic;
    const float nonmetal = 1.0 - metal;
    const float rough = 1.0 - material.smoothness;
    const vec3 diff_col = material.color.rgb * nonmetal;
    const vec3 f0 = material.color.rgb * metal + material.reflectance * nonmetal;

    const float fr_d = dGgx(n_dot_h, rough);
    const float fr_v = vSmithGgxCorrelated(n_dot_v, n_dot_l, rough);
    const vec3 fr_f = fSchlick(f0, v_dot_h);
    const vec3 fr = fr_d * fr_v * fr_f;

    const vec3 fd = (1.0 - fr_f) * fdLambert(diff_col);

    const vec3 brdf = fr + fd;
    const float shdw_fac = shadowFactor();
    const vec3 light_fac = lightFactor(n_dot_l);

    color_0.rgb = mix(brdf, brdf * shdw_fac, 0.7) * light_fac;
}

#version 460 core

const float pi = 3.14159265359;

layout(set = 0, binding = 0) uniform sampler2DShadow shadow_map;

layout(set = 0, binding = 1) uniform Light {
    vec3 position;
    vec3 color;
    float intensity;
} light;

layout(set = 1, binding = 1) uniform Material {
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

vec3 fSchlick(vec3 f0, float f90, float u) {
    return f0 + (f90 - f0) * pow(1.0 - u, 5.0);
}

float vSmithGgxCorrelated(float n_dot_v, float n_dot_l, float roughness) {
    return 0.5 / mix(2.0 * n_dot_v * n_dot_l, n_dot_v + n_dot_l, roughness);
}

float dGgx(float n_dot_h, float m) {
    const float m_2 = m * m;
    const float f = (n_dot_h * m_2 - n_dot_h) * n_dot_h + 1.0;
    return m_2 / (f * f) * (1.0 / pi);
}

float fdLambert() {
    return 1.0 / pi;
}

void main() {
    color_0.rgb = vec3(0.0);
    color_0.a = 1.0;

    const vec3 n = normalize(vertex.normal);
    const vec3 l = normalize(light.position - vertex.position);
    const float n_dot_l = clamp(dot(n, l), 0.0, 1.0);

    if (n_dot_l <= 1e-5)
        return;

    const vec3 v = normalize(-vertex.position);
    const vec3 h = normalize(v + l);
    const float n_dot_v = abs(dot(n, v)) + 1e-5;
    const float n_dot_h = clamp(dot(n, h), 0.0, 1.0);
    const float l_dot_h = clamp(dot(l, h), 0.0, 1.0);

    // TODO: Random samples.
    float shdw_fac;
    if (vertex.shadow.w > 1.0) {
        shdw_fac = textureProj(shadow_map, vertex.shadow);
        shdw_fac += textureProjOffset(shadow_map, vertex.shadow, ivec2(-1, -1));
        shdw_fac += textureProjOffset(shadow_map, vertex.shadow, ivec2(0, -1));
        shdw_fac += textureProjOffset(shadow_map, vertex.shadow, ivec2(1, -1));
        shdw_fac += textureProjOffset(shadow_map, vertex.shadow, ivec2(1, 0));
        shdw_fac += textureProjOffset(shadow_map, vertex.shadow, ivec2(1, 1));
        shdw_fac += textureProjOffset(shadow_map, vertex.shadow, ivec2(0, 1));
        shdw_fac += textureProjOffset(shadow_map, vertex.shadow, ivec2(-1, 1));
        shdw_fac += textureProjOffset(shadow_map, vertex.shadow, ivec2(-1, 0));
        shdw_fac *= 1.0 / 9.0;
    } else {
        shdw_fac = 1.0;
    }

    const float dist = length(light.position - vertex.position);
    const float atten = 1.0 / max(dist * dist, 1e-4);
    const vec3 light_fac = light.color * light.intensity * atten * n_dot_l;

    const vec4 color = material.color;
    const float metallic = material.metallic;
    const float smoothness = material.smoothness;
    const float reflectance = material.reflectance;

    const vec3 diff_col = color.rgb * (1.0 - metallic);
    const vec3 f0 = color.rgb * metallic + (reflectance * (1.0 - metallic));
    const float f90 = clamp(dot(f0, vec3(50.0 * (1.0 / 3.0))), 0.0, 1.0);

    const vec3 fr_f = fSchlick(f0, f90, l_dot_h);
    const float fr_v = vSmithGgxCorrelated(n_dot_v, n_dot_l, 1.0 - smoothness);
    const float fr_d = dGgx(n_dot_h, 1.0 - smoothness);
    const vec3 fr = fr_f * fr_v * fr_d;

    const float fd = fdLambert();

    const vec3 brdf = fr + fd * diff_col;
    color_0.rgb = mix(brdf, brdf * shdw_fac, 0.75) * light_fac;
}

#version 460 core

const float pi = 3.141592653589793;

layout(constant_id = 0) const uint light_n = 1;

layout(set = 0, binding = 2) uniform samplerCube ld;
layout(set = 0, binding = 3) uniform sampler2D dfg;
layout(set = 0, binding = 4) uniform samplerCube irradiance;

layout(set = 0, binding = 9) uniform Camera {
    mat4 vp;
    mat4 v;
    mat4 p;
    vec3 position;
    float scale;
} camera;

struct LightData {
    vec3 position;
    vec3 color;
    float intensity;
};

layout(set = 0, binding = 10) uniform Light {
    LightData lights[light_n];
} light;

layout(set = 1, binding = 0) uniform Material {
    vec4 color;
    float metallic;
    float smoothness;
    float reflectance;
} material;

layout(location = 0) in vec3 ws_position;
layout(location = 1) in vec3 ws_normal;
layout(location = 2) in vec3 reflection;

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

vec3 fSchlickRoughness(vec3 f0, float u, float roughness) {
    const vec3 smoothness = vec3(1.0 - roughness);
    return f0 + (max(smoothness, f0) - f0) * pow(1.0 - u, 5.0);
}

vec3 fdLambert(vec3 diffuse_color) {
    return diffuse_color * (1.0 / pi);
}

vec3 evaluateIbl(vec3 n, float n_dot_v, float roughness, vec3 diffuse_color, vec3 f0) {
    const float level = sqrt(roughness * roughness) * textureQueryLevels(ld);
    const vec3 spec_light = textureLod(ld, reflection, level).rgb;
    const vec2 spec_brdf = textureLod(dfg, vec2(n_dot_v, roughness), 0.0).rg;
    const vec3 spec = spec_light * (f0 * spec_brdf.x + spec_brdf.y);

    const vec3 diff_light = textureLod(irradiance, n, 0.0).rgb;
    const vec3 f_rough = fSchlickRoughness(f0, n_dot_v, roughness);
    const vec3 diff = diff_light * diffuse_color * (1.0 - f_rough);

    return spec + diff;
}

vec3 evaluateLights(vec3 n, vec3 v, float n_dot_v, float roughness, vec3 diffuse_color, vec3 f0) {
    vec3 sum = vec3(0.0);

    for (uint i = 0; i < light_n; i++) {
        const LightData lig = light.lights[i];

        const vec3 l = normalize(lig.position - ws_position);
        const float n_dot_l = clamp(dot(n, l), 0.0, 1.0);

        if (n_dot_l <= 1e-5)
            continue;

        const vec3 h = normalize(v + l);
        const float n_dot_h = clamp(dot(n, h), 0.0, 1.0);
        const float v_dot_h = clamp(dot(v, h), 0.0, 1.0);

        const float fr_d = dGgx(n_dot_h, roughness);
        const float fr_v = vSmithGgxCorrelated(n_dot_v, n_dot_l, roughness);
        const vec3 fr_f = fSchlick(f0, v_dot_h);
        const vec3 fr = fr_d * fr_v * fr_f;

        const vec3 fd = fdLambert(diffuse_color) * (1.0 - fr_f);

        const float dist = length(lig.position - ws_position);
        const float atten = 1.0 / max(dist * dist, 1e-4);

        sum += (fr + fd) * lig.color * lig.intensity * atten * n_dot_l;
    }

    return sum;
}

void main() {
    const vec3 n = normalize(ws_normal);
    const vec3 v = normalize(camera.position - ws_position);
    const float n_dot_v = abs(dot(n, v)) + 1e-5;

    const float metal = material.metallic;
    const float nonmetal = 1.0 - metal;
    const float rough = 1.0 - material.smoothness;
    const vec3 diff_col = material.color.rgb * nonmetal;
    const vec3 f0 = material.color.rgb * metal + material.reflectance * nonmetal;

    const vec3 ibl = evaluateIbl(n, n_dot_v, rough, diff_col, f0);
    const vec3 al = evaluateLights(n, v, n_dot_v, rough, diff_col, f0);

    color_0 = vec4(ibl + al, material.color.a);
}

#version 460 core

const float pi = 3.14159265359;

layout(set = 0, binding = 0) uniform Global {
    mat4 vp;
    mat4 m;
    mat3 n;
    vec3 eye;
} global;

struct LightData {
    vec3 position;
    vec4 color;
};
layout(set = 0, binding = 1) uniform Light {
    LightData lights[1];
} light;

layout(set = 1, binding = 0) uniform sampler2D base_color;

layout(set = 1, binding = 1) uniform Material {
    float metallic;
    float roughness;
    float reflectance;
} material;

layout(location = 0) in Vertex {
    vec3 position;
    vec3 normal;
    vec2 tex_coord;
} vertex;

layout(location = 0) out vec4 color_0;

vec3 fSchlick(vec3 f0, float f90, float u) {
    return f0 + (f90 - f0) * pow(1.0 - u, 5.0);
}
float fSchlick(float f0, float f90, float u) {
    return f0 + (f90 - f0) * pow(1.0 - u, 5.0);
}

float vSmithGgxCorrelated(float n_dot_v, float n_dot_l, float roughness) {
    const float rough_2 = roughness * roughness;
    const float lambda_v = n_dot_l * sqrt((n_dot_v - n_dot_v * rough_2) * n_dot_v + rough_2);
    const float lambda_l = n_dot_v * sqrt((n_dot_l - n_dot_l * rough_2) * n_dot_l + rough_2);
    return 0.5 / (lambda_v + lambda_l);
}

float dGgx(float n_dot_h, float m) {
    const float m_2 = m * m;
    const float f = (n_dot_h * m_2 - n_dot_h) * n_dot_h + 1.0;
    return m_2 / (f * f) * (1.0 / pi);
}

float fdDisneyDiffuse(float n_dot_v, float n_dot_l, float l_dot_h, float roughness) {
    const float f0 = 1.0;
    const float f90 = 0.5 + 2.0 * l_dot_h * l_dot_h * roughness;
    const float light_scatter = fSchlick(f0, f90, n_dot_l);
    const float view_scatter = fSchlick(f0, f90, n_dot_v);
    return light_scatter * view_scatter * (1.0 / pi);
}

void main() {
    const vec3 n = normalize(vertex.normal);
    const vec3 v = normalize(global.eye - vertex.position);
    const float n_dot_v = abs(dot(n, v)) + 1e-5;

    const float metallic = material.metallic;
    const float roughness = material.roughness;
    const float reflectance = material.reflectance;
    const vec4 base_col = texture(base_color, vertex.tex_coord);
    const vec3 diff_col = base_col.rgb * (1.0 - metallic);
    const vec3 f0 = base_col.rgb * metallic + (reflectance * (1.0 - metallic));
    const float f90 = clamp(dot(f0, vec3(50.0 * 0.33)), 0.0, 1.0);

    color_0.rgb = vec3(0.0);
    color_0.a = 1.0;

    for (uint i = 0; i < light.lights.length(); i++) {
        const vec3 l = normalize(light.lights[i].position - vertex.position);
        const vec3 h = normalize(v + l);
        const float n_dot_l = clamp(dot(n, l), 0.0, 1.0);
        const float n_dot_h = clamp(dot(n, h), 0.0, 1.0);
        const float l_dot_h = clamp(dot(l, h), 0.0, 1.0);

        const vec3 fr_f = fSchlick(f0, f90, l_dot_h);
        const float fr_v = vSmithGgxCorrelated(n_dot_v, n_dot_l, roughness);
        const float fr_d = dGgx(n_dot_h, roughness);
        const vec3 fr = fr_f * fr_v * fr_d;

        const float fd = fdDisneyDiffuse(n_dot_v, n_dot_l, l_dot_h, roughness);

        const float light_dist = length(light.lights[i].position - vertex.position);
        const float light_atten = 1.0 / max(light_dist * light_dist, 0.01 * 0.01);
        const vec3 light_col = light.lights[i].color.rgb;
        const float light_inten = light.lights[i].color.w;
        const vec3 light_fac = light_col * light_inten * light_atten * n_dot_l;

        color_0.rgb += (fr + fd * diff_col) * light_fac;
    }
}

#version 460 core

struct LightData {
    vec3 position;
    vec3 color;
    float intensity;
};

layout(set = 0, binding = 7) uniform Light {
    LightData lights[3];
} light;

layout(set = 1, binding = 1) uniform Material {
    vec3 base_color;
    float metallic;
    float roughness;
    float reflectance;
} material;

layout(location = 0) in Vertex {
    vec3 position;
    vec3 normal;
} vertex;

layout(location = 0) out vec4 color_0;

const float pi = 3.14159265359;

vec3 fSchlick(vec3 f0, float f90, float u) {
    return f0 + (f90 - f0) * pow(1.0 - u, 5.0);
}

float vSmithGgxCorrelated(float n_dot_v, float n_dot_l, float roughness) {
    const float a_sq = roughness * roughness;
    const float lambda_v = n_dot_l * sqrt((n_dot_v - n_dot_v * a_sq) * n_dot_v + a_sq);
    const float lambda_l = n_dot_v * sqrt((n_dot_l - n_dot_l * a_sq) * n_dot_l + a_sq);
    return 0.5 / (lambda_v + lambda_l);
}

float dGgx(float n_dot_h, float m) {
    const float m_sq = m * m;
    const float f = (n_dot_h * m_sq - n_dot_h) * n_dot_h + 1.0;
    return m_sq / (f * f) * (1.0 / pi);
}

float fdDisneyDiffuse(float n_dot_v, float n_dot_l, float l_dot_h, float roughness) {
    const float f0 = 1.0;
    const float f90 = 0.5 + 2.0 * l_dot_h * l_dot_h * roughness;
    const float light_scatter = fSchlick(vec3(f0), f90, n_dot_l).r;
    const float view_scatter = fSchlick(vec3(f0), f90, n_dot_v).r;
    return light_scatter * view_scatter * (1.0 / pi);
}

vec3 lightFactor(uint index, float n_dot_l) {
    const float dist = length(light.lights[index].position - vertex.position);
    const float atten = 1.0 / max(dist * dist, 0.01 * 0.01);
    return light.lights[index].color * light.lights[index].intensity * atten * n_dot_l;
}

void main() {
    const vec3 n = normalize(vertex.normal);
    const vec3 v = normalize(-vertex.position);
    const float n_dot_v = abs(dot(n, v)) + 1e-5;

    const vec3 diff_col = material.base_color * (1.0 - material.metallic);
    const vec3 f0 = material.base_color * material.metallic +
        (material.reflectance * (1.0 - material.metallic));
    const float f90 = clamp(dot(f0, vec3(16.6667)), 0.0, 1.0);

    color_0.rgb = vec3(0.0);
    color_0.a = 1.0;

    for (uint i = 0; i < light.lights.length(); i++) {
        const vec3 l = normalize(light.lights[i].position - vertex.position);
        const vec3 h = normalize(v + l);
        const float n_dot_l = clamp(dot(n, l), 0.0, 1.0);
        const float n_dot_h = clamp(dot(n, h), 0.0, 1.0);
        const float l_dot_h = clamp(dot(l, h), 0.0, 1.0);

        if (n_dot_l < 1e-5) continue;

        const vec3 fr = fSchlick(f0, f90, l_dot_h) *
            vSmithGgxCorrelated(n_dot_v, n_dot_l, material.roughness) *
            dGgx(n_dot_h, material.roughness);

        const float fd = fdDisneyDiffuse(n_dot_v, n_dot_l, l_dot_h, material.roughness);

        color_0.rgb += (fr + fd * diff_col) * lightFactor(i, n_dot_l);
    }
}

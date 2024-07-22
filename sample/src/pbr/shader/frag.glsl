#version 460 core

const float pi = 3.141592653589793;

layout(set = 0, binding = 0) uniform Global {
    mat4 vp;
    mat4 m;
    mat3 n;
    vec3 eye;
} global;

struct LightData {
    vec3 position;
    vec3 color;
    float intensity;
};

layout(constant_id = 0) const int light_n = 1;

layout(set = 0, binding = 1) uniform Light {
    LightData lights[light_n];
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

void main() {
    const vec3 n = normalize(vertex.normal);
    const vec3 v = normalize(global.eye - vertex.position);
    const float n_dot_v = abs(dot(n, v)) + 1e-5;

    const float metal = material.metallic;
    const float nonmetal = 1.0 - material.metallic;
    const float rough = 1.0 - material.smoothness;
    const vec3 diff_col = material.color.rgb * nonmetal;
    const vec3 f0 = material.color.rgb * metal + material.reflectance * nonmetal;

    color_0.rgb = vec3(0.0);
    color_0.a = material.color.a;

    for (uint i = 0; i < light_n; i++) {
        const LightData lig = light.lights[i];

        const vec3 l = normalize(lig.position - vertex.position);
        const float n_dot_l = clamp(dot(n, l), 0.0, 1.0);

        if (n_dot_l <= 1e-5)
            continue;

        const vec3 h = normalize(v + l);
        const float n_dot_h = clamp(dot(n, h), 0.0, 1.0);
        const float v_dot_h = clamp(dot(v, h), 0.0, 1.0);

        const float fr_d = dGgx(n_dot_h, rough);
        const float fr_v = vSmithGgxCorrelated(n_dot_v, n_dot_l, rough);
        const vec3 fr_f = fSchlick(f0, v_dot_h);
        const vec3 fr = fr_d * fr_v * fr_f;

        const vec3 fd = (1.0 - fr_f) * fdLambert(diff_col);

        const float dist = length(lig.position - vertex.position);
        const float atten = 1.0 / max(dist * dist, 1e-4);
        const vec3 fac = lig.color * lig.intensity * atten * n_dot_l;

        color_0.rgb += (fr + fd) * fac;
    }
}

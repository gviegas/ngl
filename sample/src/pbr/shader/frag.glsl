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

vec3 fSchlick(vec3 f0, float f90, float u) {
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

float fdDisney(float n_dot_v, float n_dot_l, float l_dot_h, float roughness) {
    const vec3 f0 = vec3(1.0);
    const float f90 = 0.5 + 2.0 * l_dot_h * l_dot_h * roughness;
    const float view_scatter = float(fSchlick(f0, f90, n_dot_v));
    const float light_scatter = float(fSchlick(f0, f90, n_dot_l));
    return view_scatter * light_scatter * (1.0 / pi);
}

void main() {
    const vec3 n = normalize(vertex.normal);
    const vec3 v = normalize(global.eye - vertex.position);
    const float n_dot_v = abs(dot(n, v)) + 1e-5;

    const vec4 color = material.color;
    const float metallic = material.metallic;
    const float smoothness = material.smoothness;
    const float reflectance = material.reflectance;

    const vec3 diff_col = color.rgb * (1.0 - metallic);
    const vec3 f0 = color.rgb * metallic + (reflectance * (1.0 - metallic));
    const float f90 = clamp(dot(f0, vec3(50.0 * (1.0 / 3.0))), 0.0, 1.0);

    color_0.rgb = vec3(0.0);
    color_0.a = 1.0;

    for (uint i = 0; i < light_n; i++) {
        const LightData lig = light.lights[i];

        const vec3 l = normalize(lig.position - vertex.position);
        const float n_dot_l = clamp(dot(n, l), 0.0, 1.0);

        if (n_dot_l <= 1e-5)
            continue;

        const vec3 h = normalize(v + l);
        const float n_dot_h = clamp(dot(n, h), 0.0, 1.0);
        const float l_dot_h = clamp(dot(l, h), 0.0, 1.0);

        const vec3 fr_f = fSchlick(f0, f90, l_dot_h);
        const float fr_v = vSmithGgxCorrelated(n_dot_v, n_dot_l, 1.0 - smoothness);
        const float fr_d = dGgx(n_dot_h, 1.0 - smoothness);
        const vec3 fr = fr_f * fr_v * fr_d;

        const float fd = fdDisney(n_dot_v, n_dot_l, l_dot_h, 1.0 - smoothness);

        const float dist = length(lig.position - vertex.position);
        const float atten = 1.0 / max(dist * dist, 1e-4);
        const vec3 fac = lig.color * lig.intensity * atten * n_dot_l;

        color_0.rgb += (fr + fd * diff_col) * fac;
    }
}

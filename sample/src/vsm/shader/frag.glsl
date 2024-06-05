#version 460 core

const float pi = 3.141592653589793;

layout(set = 0, binding = 0) uniform sampler2D shadow_map;

layout(set = 0, binding = 4) uniform Light {
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

float shadowFactor() {
    if (vertex.shadow.w <= 1.0)
        return 1.0;

    const vec3 coord = vertex.shadow.xyz / vertex.shadow.w;
    const vec2 moments = texture(shadow_map, coord.st).rg;
    const float depth = coord.z;

    const float variance = max(2e-5, moments.y - moments.x * moments.x);
    const float d = depth - moments.x;
    const float max_prob = variance / (variance + d * d);

    return max(max_prob, depth <= moments.x ? 1.0 : 0.3);
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
    const float l_dot_h = clamp(dot(l, h), 0.0, 1.0);

    const float metal = material.metallic;
    const float nonmetal = 1.0 - metal;
    const float rough = 1.0 - material.smoothness;
    const vec3 diff_col = material.color.rgb * nonmetal;
    const vec3 f0 = material.color.rgb * metal + material.reflectance * nonmetal;
    const float f90 = 1.0;

    const vec3 fr_f = fSchlick(f0, f90, l_dot_h);
    const float fr_v = vSmithGgxCorrelated(n_dot_v, n_dot_l, rough);
    const float fr_d = dGgx(n_dot_h, rough);
    const vec3 fr = fr_f * fr_v * fr_d;

    const float fd = fdLambert();

    color_0.rgb = (fr + fd * diff_col) * shadowFactor() * lightFactor(n_dot_l);
}

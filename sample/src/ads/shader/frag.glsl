#version 460 core

layout(constant_id = 0) const float gamma = 1e-5;

layout(set = 0, binding = 1) uniform Light {
    vec3 position;
    float intensity;
} light;

layout(set = 1, binding = 0) uniform Material {
    vec3 ka;
    vec3 kd;
    vec3 ks;
    float sp;
} material;

layout(location = 0) in Vertex {
    vec3 position;
    vec3 normal;
} vertex;

layout(location = 0) out vec4 color_0;

void main() {
    const vec3 n = normalize(vertex.normal);
    const vec3 l = normalize(light.position - vertex.position);
    const vec3 v = normalize(-vertex.position);
    const vec3 h = normalize(v + l);
    color_0 = vec4(0.0, 0.0, 0.0, 1.0);
    color_0.rgb += material.ka;
    color_0.rgb += material.kd * max(dot(n, l), 0.0);
    color_0.rgb += material.ks * pow(max(dot(n, h), 0.0), material.sp);
    color_0.rgb *= light.intensity;
    color_0.rgb = pow(color_0.rgb, vec3(1.0 / gamma));
}

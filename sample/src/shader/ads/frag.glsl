#version 460 core

layout(set = 0, binding = 1) uniform Light {
    vec3 position;
    vec3 intensity;
} light;

layout(set = 1, binding = 0) uniform Material {
    vec3 ka;
    vec3 kd;
    vec3 ks;
    float sp;
} material;

layout(set = 1, binding = 1) uniform sampler2D base_color;

layout(location = 0) in Vertex {
    vec3 position;
    vec3 normal;
    vec2 tex_coord;
} vertex;

layout(location = 0) out vec4 color_0;

void main() {
    const vec3 n = normalize(vertex.normal);
    const vec3 l = normalize(light.position - vertex.position);
    const vec3 v = normalize(-vertex.position);
    const vec3 h = normalize(v + l);
    const vec4 c = texture(base_color, vertex.tex_coord);
    color_0.a = c.a;
    color_0.rgb = c.rgb * (material.ka + material.kd * max(dot(n, l), 0.0));
    color_0.rgb += material.ks * pow(max(dot(n, h), 0.0), material.sp);
    color_0.rgb *= light.intensity;
}

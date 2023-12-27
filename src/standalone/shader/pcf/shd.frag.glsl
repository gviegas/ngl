#version 460 core

layout(set = 0, binding = 0) uniform sampler2DShadow shadow;

layout(set = 0, binding = 1) uniform Light {
    vec3 position;
    vec3 intensity;
} light;

layout(set = 1, binding = 0) uniform sampler2D base_color;

layout(set = 1, binding = 1) uniform Material {
    vec3 ka;
    vec3 kd;
    vec3 ks;
    float sp;
} material;

layout(location = 0) in Vertex {
    vec3 position;
    vec3 normal;
    vec2 tex_coord;
    vec4 shdw_coord;
} vertex;

layout(location = 0) out vec4 color_0;

void main() {
    const vec3 n = normalize(vertex.normal);
    const vec3 l = normalize(light.position - vertex.position);
    const vec3 v = normalize(-vertex.position);
    const vec3 h = normalize(v + l);
    const vec4 c = texture(base_color, vertex.tex_coord);
    const float s = 0.25 *
        (textureProjOffset(shadow, vertex.shdw_coord, ivec2(-1, -1)) +
         textureProjOffset(shadow, vertex.shdw_coord, ivec2(1, -1)) +
         textureProjOffset(shadow, vertex.shdw_coord, ivec2(1, 1)) +
         textureProjOffset(shadow, vertex.shdw_coord, ivec2(-1, 1)));
    color_0.a = 1.0;
    color_0.rgb = material.ka * c.rgb;
    color_0.rgb += s *
        (material.kd * max(dot(n, l), 0.0) * c.rgb +
         material.ks * pow(max(dot(n, h), 0.0), material.sp));
    color_0.rgb *= light.intensity;
}

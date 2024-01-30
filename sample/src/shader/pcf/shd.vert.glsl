#version 460 core

layout(set = 2, binding = 0) uniform Global {
    mat4 s;
    mat4 mvp;
    mat4 mv;
    mat3 n;
} global;

layout(location = 0) in vec3 position;
layout(location = 1) in vec3 normal;
layout(location = 2) in vec2 tex_coord;

layout(location = 0) out Vertex {
    vec3 position;
    vec3 normal;
    vec2 tex_coord;
    vec4 shdw_coord;
} vertex;

void main() {
    vertex.position = vec3(global.mv * vec4(position, 1.0));
    vertex.normal = normalize(global.n * normal);
    vertex.tex_coord = tex_coord;
    vertex.shdw_coord = global.s * vec4(position, 1.0);
    gl_Position = global.mvp * vec4(position, 1.0);
}

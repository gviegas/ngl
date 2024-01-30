#version 460 core

layout(set = 0, binding = 0) uniform Global {
    mat4 vp;
    mat4 m;
    mat3 n;
    vec3 eye;
} global;

layout(location = 0) in vec3 position;
layout(location = 1) in vec3 normal;
layout(location = 2) in vec2 tex_coord;

layout(location = 0) out Vertex {
    vec3 position;
    vec3 normal;
    vec2 tex_coord;
} vertex;

void main() {
    const vec4 pos = global.m * vec4(position, 1.0);
    const vec3 norm = global.n * normal;
    vertex.position = position.xyz;
    vertex.normal = norm;
    vertex.tex_coord = tex_coord;
    gl_Position = global.vp * pos;
}

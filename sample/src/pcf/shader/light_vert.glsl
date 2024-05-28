#version 460 core

layout(set = 1, binding = 0) uniform Global {
    mat4 shdw_mvp;
    mat4 s;
    mat4 mvp;
    mat4 mv;
    mat3 n;
} global;

layout(location = 0) in vec3 position;
layout(location = 1) in vec3 normal;

layout(location = 0) out Vertex {
    vec3 position;
    vec3 normal;
    vec4 shadow;
} vertex;

void main() {
    vertex.position = (global.mv * vec4(position, 1.0)).xyz;
    vertex.normal = global.n * normal;
    vertex.shadow = global.s * vec4(position, 1.0);
    gl_Position = global.mvp * vec4(position, 1.0);
}

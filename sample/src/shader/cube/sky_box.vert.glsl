#version 460 core

layout(set = 0, binding = 1) uniform Global {
    mat4 p;
    mat4 v;
    mat4 m;
    mat3 n;
    vec3 eye;
} global;

layout(location = 0) in vec3 position;

layout(location = 0) out vec3 tex_coord;

void main() {
    tex_coord = position;
    gl_Position = global.p * vec4(mat3(global.v) * position, 1.0);
}

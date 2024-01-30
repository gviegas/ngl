#version 460 core

layout(set = 1, binding = 0) uniform Global {
    mat4 mvp;
    mat3 n;
} global;

layout(location = 0) in vec3 position;
layout(location = 1) in vec3 normal;

layout(location = 0) out vec3 out_normal;

void main() {
    out_normal = global.n * normal;
    gl_Position = global.mvp * vec4(position, 1.0);
}

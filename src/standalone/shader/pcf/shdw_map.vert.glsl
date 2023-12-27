#version 460 core

layout(push_constant) uniform Global {
    mat4 mvp;
} global;

layout(location = 0) in vec3 position;

void main() {
    gl_Position = global.mvp * vec4(position, 1.0);
}

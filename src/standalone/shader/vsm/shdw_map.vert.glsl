#version 460 core

layout(set = 2, binding = 0) uniform Global {
    mat4 mvp;
} global;

layout(location = 0) in vec3 position;

layout(location = 0) out vec4 clip_pos;

void main() {
    clip_pos = global.mvp * vec4(position, 1.0);
    gl_Position = clip_pos;
}

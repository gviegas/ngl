#version 460 core

layout(set = 2, binding = 0) uniform Model {
    mat4 shdw_mvp;
    mat4 s;
    mat4 mvp;
    mat4 mv;
    mat3 n;
} model;

layout(location = 0) in vec3 position;

layout(location = 0) out vec4 clip_position;

void main() {
    clip_position = model.shdw_mvp * vec4(position, 1.0);
    gl_Position = clip_position;
}

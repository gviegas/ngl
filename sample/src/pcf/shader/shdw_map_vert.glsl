#version 460 core

layout(set = 1, binding = 0) uniform Global {
    mat4 shdw_mvp;
    mat4 s;
    mat4 mvp;
    mat4 mv;
    mat3 n;
} global;

layout(location = 0) in vec3 position;

void main() {
    gl_Position = global.shdw_mvp * vec4(position, 1.0);
}

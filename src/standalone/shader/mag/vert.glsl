#version 460 core

layout(set = 1, binding = 1) uniform Global {
    mat4 mvp;
} global;

layout(location = 0) in vec3 position;
layout(location = 1) in vec2 tex_coord;

layout(location = 0) out vec2 out_tex_coord;

void main() {
    out_tex_coord = tex_coord;
    gl_Position = global.mvp * vec4(position, 1.0);
}

#version 460 core

layout(push_constant) uniform Global {
    vec2 scale;
};

layout(location = 0) in vec3 position;
layout(location = 1) in vec2 tex_coord;

layout(location = 0) out vec2 out_tex_coord;

void main() {
    out_tex_coord = tex_coord;
    gl_Position = vec4(scale * position.xy, position.z, 1.0);
}

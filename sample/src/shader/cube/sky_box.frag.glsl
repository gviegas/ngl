#version 460 core

layout(set = 0, binding = 0) uniform samplerCube cube_map;

layout(location = 0) in vec3 tex_coord;

layout(location = 0) out vec4 color_0;

void main() {
    color_0 = texture(cube_map, tex_coord);
}

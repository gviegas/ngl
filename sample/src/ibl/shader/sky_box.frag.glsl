#version 460 core

layout(set = 0, binding = 1) uniform samplerCube cube_map;

layout(location = 0) in vec3 uvw;

layout(location = 0) out vec4 color_0;

void main() {
    color_0 = texture(cube_map, uvw);
}

#version 460 core

layout(set = 0, binding = 0) uniform samplerCube cube_map;

layout(location = 0) in vec3 tex_coord;
layout(location = 1) in vec3 tex_coord_2;

layout(location = 0) out vec4 color_0;

void main() {
    const vec3 refl = texture(cube_map, tex_coord).rgb;
    const vec3 refr = texture(cube_map, tex_coord_2).rgb;
    const vec3 col = vec3(0.9804, 0.9765, 0.9608);
    color_0.rgb = mix(mix(refl, refr, 0.3667), col, 0.5);
    color_0.a = 1.0;
}

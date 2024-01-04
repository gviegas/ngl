#version 460 core

layout(set = 1, binding = 0) uniform sampler2D alpha_map;

layout(location = 0) in vec2 tex_coord;

layout(location = 0) out vec4 color_0;

void main() {
    color_0 = texture(alpha_map, tex_coord);
#ifndef DEBUG
    const float sd = fwidth(color_0.a);
    color_0.rgb = vec3(smoothstep(0.5 - sd, 0.5 + sd, color_0.a));
    color_0.a = 1.0;
#else
    color_0 = color_0.aaaa;
#endif
}

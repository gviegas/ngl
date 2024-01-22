#version 460 core

layout(location = 0) in vec3 normal;

layout(location = 0) out vec4 color_0;
layout(location = 1) out vec4 color_1;

void main() {
    color_0 = vec4(normalize(normal) * 0.5 + 0.5, 1.0);
    color_1 = vec4(1.0);
}

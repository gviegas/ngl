#version 460 core

layout(set = 0, binding = 1) uniform Global {
    mat4 p;
    mat4 v;
    mat4 m;
    mat3 n;
    vec3 eye;
} global;

layout(location = 0) in vec3 position;
layout(location = 1) in vec3 normal;

layout(location = 0) out vec3 tex_coord;
layout(location = 1) out vec3 tex_coord_2;

void main() {
    const vec4 pos = global.m * vec4(position, 1.0);
    const vec3 norm = global.n * normal;
    const vec3 view = normalize(global.eye - pos.xyz);
    tex_coord = reflect(-view, norm);
    tex_coord_2 = refract(-view, norm, 0.625);
    gl_Position = global.p * global.v * pos;
}

#version 460 core

layout(set = 0, binding = 9) uniform Camera {
    mat4 vp;
    mat4 v;
    mat4 p;
    vec3 position;
    float scale;
} camera;

layout(set = 2, binding = 0) uniform Model {
    mat4 m;
    mat3 n;
} model;

layout(location = 0) in vec3 position;
layout(location = 1) in vec3 normal;

layout(location = 0) out vec3 ws_position;
layout(location = 1) out vec3 ws_normal;
layout(location = 2) out vec3 reflection;

void main() {
    ws_position = (model.m * vec4(position, 1.0)).xyz;
    ws_normal = model.n * normal;
    reflection = reflect(normalize(ws_position - camera.position), ws_normal);
    gl_Position = camera.vp * vec4(ws_position, 1.0);
}

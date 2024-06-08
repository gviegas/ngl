#version 460 core

layout(set = 2, binding = 0) uniform Model {
    mat4 mvp;
    mat4 mv;
    mat3 n;
} model;

layout(location = 0) in vec3 position;
layout(location = 1) in vec3 normal;

layout(location = 0) out vec3 es_position;
layout(location = 1) out vec3 es_normal;

void main() {
    es_position = (model.mv * vec4(position, 1.0)).xyz;
    es_normal = model.n * normal;
    gl_Position = model.mvp * vec4(position, 1.0);
}

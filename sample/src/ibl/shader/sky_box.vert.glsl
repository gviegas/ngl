#version 460 core

layout(set = 0, binding = 9) uniform Camera {
    mat4 vp;
    mat4 v;
    mat4 p;
    vec3 position;
    float scale;
} camera;

layout(location = 0) in vec3 position;

layout(location = 0) out vec3 uvw;

void main() {
    uvw = position;
    gl_Position = camera.p * vec4(mat3(camera.v) * position * camera.scale, 1.0);
}

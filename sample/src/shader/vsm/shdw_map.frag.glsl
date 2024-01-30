#version 460 core

layout(location = 0) in vec4 clip_pos;

layout(location = 0) out vec4 color_0;

// TODO
const float depth_bias = 1e-3;

void main() {
    const float depth = depth_bias + clip_pos.z / clip_pos.w;
    const float dx = dFdx(depth);
    const float dy = dFdy(depth);
    const vec2 moments = vec2(depth, depth * depth + (dx * dx + dy * dy) * 0.25);
    color_0 = vec4(moments, 0.0, 0.0);
}

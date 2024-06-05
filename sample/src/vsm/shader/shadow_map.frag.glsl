#version 460 core

layout(location = 0) in vec4 clip_position;

layout(location = 0) out vec4 color_0;

void main() {
    const float depth = clip_position.z / clip_position.w;
    const float dx = dFdx(depth);
    const float dy = dFdy(depth);

    const float moment = depth;
    const float moment_2 = depth * depth + 0.25 * (dx * dx + dy * dy);

    color_0 = vec4(moment, moment_2, 0.0, 0.0);
}

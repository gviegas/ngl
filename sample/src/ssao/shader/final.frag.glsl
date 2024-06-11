#version 460 core

layout(set = 0, binding = 0) uniform sampler2D color;
layout(set = 0, binding = 4) uniform sampler2D ao;

layout(location = 0) in vec2 uv;

layout(location = 0) out vec4 color_0;

void main() {
#if defined(COLOR_OUTPUT)
    color_0 = texture(color, uv);

#elif defined(AO_OUTPUT)
    color_0.rgb = texture(ao, uv).rrr;
    color_0.a = 1.0;

#else
    color_0 = texture(color, uv);
    color_0.rgb *= texture(ao, uv).r;
#endif
}

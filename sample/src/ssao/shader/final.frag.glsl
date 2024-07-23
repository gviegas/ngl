#version 460 core

layout(constant_id = 0) const float gamma = 1e-5;

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

    color_0.rgb = pow(color_0.rgb, vec3(1.0 / gamma));
}

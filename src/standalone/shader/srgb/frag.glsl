#version 460 core

layout(set = 0, binding = 0) uniform sampler2D color_map;

layout(location = 0) in vec2 tex_coord;

layout(location = 0) out vec4 color_0;

layout(constant_id = 0) const bool convert_input = false;
layout(constant_id = 1) const bool convert_output = false;
layout(constant_id = 2) const bool accurate = false;

vec3 srgbToLinear(vec3 color) {
    const vec3 conv[2] = {
        color / 12.92,
        pow((color + 0.055) / 1.055, vec3(2.4)),
    };
    const uvec3 idx = uvec3(greaterThan(color, vec3(0.04045)));
    return vec3(conv[idx.r].r, conv[idx.g].g, conv[idx.b].b);
}

vec3 linearToSrgb(vec3 color) {
    const vec3 conv[2] = {
        color * 12.92,
        1.055 * pow(color, vec3(1.0 / 2.4)) - 0.055,
    };
    const uvec3 idx = uvec3(greaterThan(color, vec3(0.0031308)));
    return vec3(conv[idx.r].r, conv[idx.g].g, conv[idx.b].b);
}

vec3 srgbToLinearFast(vec3 color) {
    return pow(color, vec3(2.2));
}

vec3 linearToSrgbFast(vec3 color) {
    return pow(color, vec3(1.0 / 2.2));
}

void main() {
    vec4 c = texture(color_map, tex_coord);

    if (convert_input) {
        if (accurate)
            c.rgb = srgbToLinear(c.rgb);
        else
            c.rgb = srgbToLinearFast(c.rgb);
    }

    if (convert_output) {
        if (accurate)
            color_0 = vec4(linearToSrgb(c.rgb), c.a);
        else
            color_0 = vec4(linearToSrgbFast(c.rgb), c.a);
    } else
        color_0 = c;
}

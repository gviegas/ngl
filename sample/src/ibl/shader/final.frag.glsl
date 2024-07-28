#version 460 core

layout(constant_id = 0) const bool use_luminance_1 = true;
layout(constant_id = 1) const float gamma = 1e-5;
layout(constant_id = 2) const float white_scale = 11.2;
layout(constant_id = 3) const float exposure_bias = 1.0;

layout(set = 0, binding = 0) uniform sampler2D color;
layout(set = 0, binding = 5) uniform sampler2D luminance_1;
layout(set = 0, binding = 6) uniform sampler2D luminance_2;

layout(location = 0) in vec2 uv;

layout(location = 0) out vec4 color_0;

vec3 tmoUc2(vec3 color) {
    const float a = 0.22;
    const float b = 0.3;
    const float c = 0.1;
    const float d = 0.2;
    const float e = 0.01;
    const float f = 0.3;

    return ((color * (a * color + c * b) + d * e) / (color * (a * color + b) + d * f)) - (e / f);
}

vec3 tonemap(vec3 color) {
    return 1.0 / tmoUc2(vec3(white_scale)) * tmoUc2(color * exposure_bias);
}

vec3 xyzFromRgb(vec3 rgb) {
    const mat3 m = mat3(
        0.49, 0.17697, 0.0,
        0.31, 0.81240, 0.01,
        0.2, 0.01063, 0.99);

    return m * rgb;
}

vec3 xyyFromXyz(vec3 xyz) {
    const float sum = max(xyz.x + xyz.y + xyz.z, 1e-5);
    const float x = xyz.x / sum;
    const float y = xyz.y / sum;

    return vec3(x, y, xyz.y);
}

vec3 xyzFromXyy(vec3 xyy) {
    const float yr = xyy.z / max(xyy.y, 1e-5);
    const float x = yr * xyy.x;
    const float z = yr * (1.0 - xyy.x - xyy.y);

    return vec3(x, xyy.z, z);
}

vec3 rgbFromXyz(vec3 xyz) {
    const mat3 m = mat3(
        2.36461, -0.51517, 0.0052,
        -0.89654, 1.4264, -0.01441,
        -0.46807, 0.08876, 1.0092);

    return m * xyz;
}

void main() {
    const vec4 col = texture(color, uv);

    float lum;
    if (use_luminance_1)
        lum = texelFetch(luminance_1, ivec2(0), 0).r;
    else
        lum = texelFetch(luminance_2, ivec2(0), 0).r;

    vec3 rgb = col.rgb;
    vec3 xyz = xyzFromRgb(rgb);
    vec3 xyy = xyyFromXyz(xyz);

    xyy.z = xyz.y * lum;
    xyz = xyzFromXyy(xyy);
    rgb = rgbFromXyz(xyz);

    color_0 = vec4(pow(tonemap(rgb), vec3(1.0 / gamma)), col.a);
}

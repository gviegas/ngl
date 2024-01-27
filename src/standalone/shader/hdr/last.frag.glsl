#version 460 core

layout(set = 0, binding = 0) uniform sampler2D hdr_map;
layout(set = 0, binding = 3) uniform sampler2D bloom_map;
layout(set = 0, binding = 6) uniform sampler2D tone_map;

layout(location = 0) in vec2 tex_coord;

layout(location = 0) out vec4 color_0;

float luminance(vec3 color) {
    return dot(color, vec3(0.2126, 0.7152, 0.0722));
}

vec3 tmoRh(vec3 color) {
    return color / (luminance(color) + 1.0);
}

vec3 tmoUc2(vec3 color) {
    const float a = 0.22;
    const float b = 0.3;
    const float c = 0.1;
    const float d = 0.2;
    const float e = 0.01;
    const float f = 0.3;
    return ((color * (a * color + c * b) + d * e) / (color * (a * color + b) + d * f)) - (e / f);
}

vec3 tmo(vec3 color) {
    //return tmoRh(color);
    return tmoUc2(color * 0.85) * (1.0 / tmoUc2(vec3(3.0)).r);
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

void shade(vec4 bloom) {
    const vec4 hdr = texture(hdr_map, tex_coord);
    const float tm = texture(tone_map, vec2(0.0)).r;

    vec3 rgb = hdr.rgb + bloom.rgb;
    vec3 xyz = xyzFromRgb(rgb);
    vec3 xyy = xyyFromXyz(xyz);

    const float lum = xyz.y * tm;

    xyy.z = lum;
    xyz = xyzFromXyy(xyy);
    rgb = rgbFromXyz(xyz);

    color_0 = vec4(tmo(rgb), hdr.a + bloom.a);
}

void debugHdr() {
    color_0 = texture(hdr_map, tex_coord);
}

void debugBloom() {
    color_0 = texture(bloom_map, tex_coord);
}

void debugTm() {
    color_0 = texture(tone_map, tex_coord);
}

void debugTmo() {
    shade(vec4(0.0));
}

void main() {
#if defined(DEBUG_HDR)
    debugHdr();
#elif defined(DEBUG_BLOOM)
    debugBloom();
#elif defined(DEBUG_TM)
    debugTm();
#elif defined(DEBUG_TMO)
    debugTmo();
#else
    shade(texture(bloom_map, tex_coord));
#endif
}

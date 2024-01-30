#version 460 core

layout(set = 0, binding = 0) uniform sampler2DMS normal_map;
layout(set = 0, binding = 1) uniform sampler2DMS depth_map;
layout(set = 0, binding = 2, input_attachment_index = 0) uniform subpassInputMS color_map;

layout(set = 0, binding = 3) uniform Global {
    mat4 inv_p;
    mat4 v;
    float ao_scale;
    float ao_bias;
    float ao_intensity;
} global;

layout(location = 0) in vec2 tex_coord;

layout(location = 0) out vec4 color_0;

const vec2 locations[] = vec2[8](
    vec2(0.0883883),
    vec2(-0.176777, 0.176777),
    vec2(-0.265165),
    vec2(0.353554, -0.353553),
    vec2(0.0, 0.625),
    vec2(-0.75, 0.0),
    vec2(0.0, -0.875),
    vec2(1.0, 0.0));

const float radius = 1.0;

vec2 rand2(vec2 v) {
    const float xyd = dot(v.xy, vec2(12.9898, 78.233));
    const float yxd = dot(v.yx, vec2(12.9898, 78.233));
    return vec2(fract(sin(xyd) * 43758.5453), fract(sin(yxd) * 43758.5453));
}

vec3 getNormal(ivec2 coord, vec3 ss_pos) {
    const int spl_count = textureSamples(normal_map);
    vec2 normal = vec2(0.0);
    for (int i = 0; i < spl_count; i++)
        normal += texelFetch(normal_map, coord, i).rg;
    normal *= 1.0 / float(spl_count);
    normal = normal * 2.0 - 1.0;
    const float z = sqrt(1.0 - normal.x * normal.x - normal.y * normal.y);
    const vec4 v_pos = global.v * vec4(ss_pos, 1.0);
    if (dot(normalize(-v_pos.xyz), vec3(normal, z)) < 0.0)
        return vec3(normal, -z);
    return vec3(normal, z);
}

float getDepth(ivec2 coord) {
    const int spl_count = textureSamples(depth_map);
    float depth = 0.0;
    for (int i = 0; i < spl_count; i++)
        depth += texelFetch(depth_map, coord, i).r;
    depth *= 1.0 / float(spl_count);
    return depth;
}

float computeAo(vec3 position, vec3 position_2, vec3 normal) {
    const vec3 difference = position_2 - position - 1e-5;
    const vec3 diff_norm = normalize(difference);
    const float d = length(difference) * global.ao_scale;
    return max(0.1, dot(normal, diff_norm) - global.ao_bias) *
        (1.0 / (1.0 + d)) *
        global.ao_intensity;
}

void main() {
    const int spl_count = textureSamples(depth_map);
    color_0 = vec4(0.0);
    for (int i = 0; i < spl_count; i++)
        color_0 += subpassLoad(color_map, i);
    color_0 *= 1.0 / float(spl_count);

    const vec2 size = vec2(textureSize(depth_map));
    const ivec2 coord = ivec2(round(tex_coord * size));
    const float depth = getDepth(coord);

    if (depth >= 1.0)
        return;

    vec4 position = global.inv_p * vec4(tex_coord, depth, 1.0);
    position.xyz /= position.w;
    const vec3 normal = getNormal(coord, position.xyz);
    const vec2 rand = normalize(rand2(coord) * 2.0 - 1.0);
    float ao = 0.0;

    for (uint i = 0; i < locations.length(); i++) {
        const float off_x = locations[i].x * rand.x * radius;
        const float off_y = locations[i].y * rand.y * radius;

        vec2 tc = tex_coord + vec2(off_x, off_y);
        float d = getDepth(ivec2(round(tc * size)));
        vec4 p = global.inv_p * vec4(tex_coord, d, 1.0);
        p.xyz /= p.w;
        ao += computeAo(p.xyz, position.xyz, normal);

        tc = tex_coord + vec2(-off_x, off_y);
        d = getDepth(ivec2(round(tc * size)));
        p = global.inv_p * vec4(tex_coord, d, 1.0);
        p.xyz /= p.w;
        ao += computeAo(p.xyz, position.xyz, normal);

        tc = tex_coord + vec2(-off_x, -off_y);
        d = getDepth(ivec2(round(tc * size)));
        p = global.inv_p * vec4(tex_coord, d, 1.0);
        p.xyz /= p.w;
        ao += computeAo(p.xyz, position.xyz, normal);

        tc = tex_coord + vec2(off_x, -off_y);
        d = getDepth(ivec2(round(tc * size)));
        p = global.inv_p * vec4(tex_coord, d, 1.0);
        p.xyz /= p.w;
        ao += computeAo(p.xyz, position.xyz, normal);

        tc = tex_coord + vec2(off_x, 0.0);
        d = getDepth(ivec2(round(tc * size)));
        p = global.inv_p * vec4(tex_coord, d, 1.0);
        p.xyz /= p.w;
        ao += computeAo(p.xyz, position.xyz, normal);

        tc = tex_coord + vec2(-off_x, 0.0);
        d = getDepth(ivec2(round(tc * size)));
        p = global.inv_p * vec4(tex_coord, d, 1.0);
        p.xyz /= p.w;
        ao += computeAo(p.xyz, position.xyz, normal);

        tc = tex_coord + vec2(0.0, -off_y);
        d = getDepth(ivec2(round(tc * size)));
        p = global.inv_p * vec4(tex_coord, d, 1.0);
        p.xyz /= p.w;
        ao += computeAo(p.xyz, position.xyz, normal);

        tc = tex_coord + vec2(0.0, off_y);
        d = getDepth(ivec2(round(tc * size)));
        p = global.inv_p * vec4(tex_coord, d, 1.0);
        p.xyz /= p.w;
        ao += computeAo(p.xyz, position.xyz, normal);
    }

    ao *= 1.0 / float(locations.length()) * 0.125;
    color_0.rgb *= ao;
}

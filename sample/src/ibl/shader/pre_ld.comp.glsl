#version 460 core

const float pi = 3.141592653589793;

layout(constant_id = 0) const uint layer = 0;
layout(constant_id = 1) const float inv_group_size = 0.0;
layout(constant_id = 2) const float roughness = 0.0;
layout(constant_id = 3) const uint sample_n = 1;

layout(set = 0, binding = 0) readonly buffer Distribution {
    vec2 xi[];
} distribution;

layout(set = 1, binding = 0) uniform samplerCube source;
layout(set = 1, binding = 1, rgba16f) writeonly uniform imageCube dest;

vec3 sampleGgx(vec2 xi, vec3 n) {
    const float a = roughness * roughness;
    const float phi = 2.0 * pi * xi.x;
    const float cos_theta = sqrt((1.0 - xi.y) / ((a * a - 1.0) * xi.y + 1.0));
    const float sin_theta = sqrt(1.0 - cos_theta * cos_theta);

    const vec3 h = vec3(
        sin_theta * cos(phi),
        sin_theta * sin(phi),
        cos_theta);

    const vec3 up = (abs(n.z) < 0.999) ? vec3(0.0, 0.0, 1.0) : vec3(1.0, 0.0, 0.0);
    const vec3 tangent_x = normalize(cross(up, n));
    const vec3 tangent_y = cross(n, tangent_x);

    return normalize(tangent_x * h.x + tangent_y * h.y + n * h.z);
}

vec3 prefilter(vec3 r) {
    vec3 sum = vec3(0.0);
    float weight = 1e-5;
    for (uint i = 0; i < sample_n; i++) {
        const vec2 xi = distribution.xi[i];
        const vec3 h = sampleGgx(xi, r);
        const vec3 l = reflect(-r, h);
        const float n_dot_l = clamp(dot(r, l), 0.0, 1.0);

        if (n_dot_l <= 1e-5)
            continue;

        sum += textureLod(source, l, 0.0).rgb * n_dot_l;
        weight += n_dot_l;
    }

    return sum / weight;
}

void main() {
    const uvec2 gid = gl_GlobalInvocationID.xy;
    const vec2 uv = (gid + 0.5) * vec2(inv_group_size);

    const float x = uv.s * 2.0 - 1.0;
    const float y = uv.t * 2.0 - 1.0;
    const float z = 1.0 + 1e-5;

    vec3 r;
    switch (layer) {
    case 0:
        r = vec3(z, -y, -x);
        break;
    case 1:
        r = vec3(-z, -y, x);
        break;
    case 2:
        r = vec3(x, z, y);
        break;
    case 3:
        r = vec3(x, -z, -y);
        break;
    case 4:
        r = vec3(x, -y, z);
        break;
    case 5:
        r = vec3(-x, -y, -z);
        break;
    }

    const vec3 light = prefilter(normalize(r));

    imageStore(dest, ivec3(gid, layer), vec4(light, 1.0));
}

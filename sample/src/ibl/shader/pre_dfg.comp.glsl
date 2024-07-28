#version 460 core

const float pi = 3.141592653589793;

layout(constant_id = 0) const float inv_group_size = 0.0;
layout(constant_id = 1) const uint sample_n = 1;

layout(set = 0, binding = 0) readonly buffer Distribution {
    vec2 xi[];
} distribution;

layout(set = 0, binding = 1, rgba16f) writeonly uniform image2D dest;

vec3 sampleGgx(vec2 xi, vec3 n, float roughness) {
    const float a = roughness * roughness;
    const float phi = 2.0 * pi * xi.x;
    const float cos_theta = sqrt((1.0 - xi.y) / ((a * a - 1.0) * xi.y + 1.0));
    const float sin_theta = sqrt(1.0 - cos_theta * cos_theta);

    const vec3 h = vec3(
        sin_theta * cos(phi),
        sin_theta * sin(phi),
        cos_theta);

    const vec3 up = vec3(1.0, 0.0, 0.0);
    const vec3 tangent_x = normalize(cross(up, n));
    const vec3 tangent_y = cross(n, tangent_x);

    return normalize(tangent_x * h.x + tangent_y * h.y + n * h.z);
}

float gSmithGgxCorrelated(float n_dot_v, float n_dot_l, float roughness) {
    const float a = roughness * roughness;
    const float n_dot_v_2 = n_dot_v * n_dot_v;
    const float n_dot_l_2 = n_dot_l * n_dot_l;
    const float lambda_v = ((sqrt(a + (1.0 - a) * n_dot_v_2)) / n_dot_v - 1.0) * 0.5;
    const float lambda_l = ((sqrt(a + (1.0 - a) * n_dot_l_2)) / n_dot_l - 1.0) * 0.5;
    return 1.0 / (1.0 + lambda_v + lambda_l);
}

vec2 integrate(vec3 n, float n_dot_v, float roughness) {
    const vec3 v = vec3(
        sqrt(1.0 - n_dot_v * n_dot_v),
        0.0,
        n_dot_v);

    vec2 sum = vec2(0.0);
    for (uint i = 0; i < sample_n; i++) {
        const vec2 xi = distribution.xi[i];
        const vec3 h = sampleGgx(xi, n, roughness);
        const vec3 l = reflect(-v, h);
        const float n_dot_l = clamp(l.z, 0.0, 1.0);
        const float n_dot_h = clamp(h.z, 0.0, 1.0);
        const float v_dot_h = clamp(dot(v, h), 0.0, 1.0);

        if (n_dot_l <= 1e-5)
            continue;

        const float g = gSmithGgxCorrelated(n_dot_v, n_dot_l, roughness);
        const float vis = g * v_dot_h / (n_dot_h * n_dot_v);
        const float fc = pow(1.0 - v_dot_h, 5.0);

        sum += vec2(
            (1.0 - fc) * vis,
            fc * vis);
    }

    return sum * (1.0 / sample_n);
}

void main() {
    const uvec2 gid = gl_GlobalInvocationID.xy;
    const vec2 uv = (gid + 0.5) * vec2(inv_group_size);

    const vec3 n = vec3(0.0, 0.0, 1.0);
    const float n_dot_v = uv.s;
    const float rough = uv.t;

    const vec2 brdf = integrate(n, n_dot_v, rough);

    imageStore(dest, ivec2(gid), vec4(brdf, 0.0, 1.0));
}

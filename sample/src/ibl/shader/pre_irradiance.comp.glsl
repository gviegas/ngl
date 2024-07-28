#version 460 core

const float pi = 3.141592653589793;

layout(constant_id = 0) const uint layer = 0;
layout(constant_id = 1) const float inv_group_size = 0.0;
layout(constant_id = 2) const float phi_delta = 0.0;
layout(constant_id = 3) const float theta_delta = 0.0;

layout(set = 0, binding = 2) uniform samplerCube source;
layout(set = 0, binding = 3, rgba16f) writeonly uniform imageCube dest;

vec3 convolve(vec3 r) {
    const vec3 up = (abs(r.z) < 0.999) ? vec3(0.0, 0.0, 1.0) : vec3(1.0, 0.0, 0.0);
    const vec3 tangent_x = normalize(cross(up, r));
    const vec3 tangent_y = cross(r, tangent_x);

    vec3 sum = vec3(0.0);
    float weight = 1e-5;

    for (float phi = 0.0; phi < 2.0 * pi; phi += phi_delta) {
        for (float theta = 0.0; theta < 0.5 * pi; theta += theta_delta) {

            const float cos_theta = cos(theta);
            const float sin_theta = sqrt(1.0 - cos_theta * cos_theta);

            const vec3 c = vec3(
                sin_theta * cos(phi),
                sin_theta * sin(phi),
                cos_theta);

            const vec3 w = normalize(tangent_x * c.x + tangent_y * c.y + r * c.z);

            sum += textureLod(source, w, 0.0).rgb * cos_theta * sin_theta;
            weight += 1.0;
        }
    }

    return pi * sum / weight;
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

    const vec3 irrad = convolve(normalize(r));

    imageStore(dest, ivec3(gid, layer), vec4(irrad, 1.0));
}

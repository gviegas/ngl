#version 460 core

// TODO
layout(local_size_x = 1, local_size_y = 1) in;

layout(set = 0, binding = 1, rgba32f) readonly uniform image2D source;
layout(set = 0, binding = 0, rgba32f) writeonly uniform image2D dest;

const float kernel[] = float[25](
    0.0024499299678342,
    0.0043538453346397,
    0.0073599963704157,
    0.0118349786570722,
    0.0181026699707781,
    0.0263392293891488,
    0.0364543006660986,
    0.0479932050577658,
    0.0601029809166942,
    0.0715974486241365,
    0.0811305381519717,
    0.0874493212267511,
    0.0896631113333857,
    0.0874493212267511,
    0.0811305381519717,
    0.0715974486241365,
    0.0601029809166942,
    0.0479932050577658,
    0.0364543006660986,
    0.0263392293891488,
    0.0181026699707781,
    0.0118349786570722,
    0.0073599963704157,
    0.0043538453346397,
    0.0024499299678342);

void main() {
    const ivec2 gid = ivec2(gl_GlobalInvocationID.xy);

    const ivec2 bounds = imageSize(source);
    if (gid.x < kernel.length() / 2 || gid.x + kernel.length() / 2 >= bounds.x) {
        imageStore(dest, gid, imageLoad(source, gid));
        return;
    }

    uint k = 0;
    vec2 sum = vec2(0.0);
    for (int i = -kernel.length() / 2; i <= kernel.length() / 2; i++)
        sum += imageLoad(source, ivec2(gid.x + i, gid.y)).rg * kernel[k++];

    imageStore(dest, gid, vec4(sum, 0.0, 0.0));
}

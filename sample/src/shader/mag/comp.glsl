#version 460 core

layout(local_size_x_id = 0, local_size_y_id = 1) in;

layout(set = 0, binding = 0) uniform sampler2D source;
layout(set = 0, binding = 1, rgba8) uniform image2D dest;

void main() {
    const ivec2 gid = ivec2(gl_GlobalInvocationID);
    const ivec2 source_size = textureSize(source, 0);
    const ivec2 dest_size = imageSize(dest);
    const ivec2 size = source_size / dest_size;
    const ivec2 corner = gid * size;

    float c = 0.0;
    for (uint y = 0; y < size.y; y++)
        for (uint x = 0; x < size.x; x++)
            c += texelFetch(source, corner + ivec2(x, y), 0).r;
    c /= float(size.x * size.y);

    imageStore(dest, gid, vec4(vec3(1.0), c));
}

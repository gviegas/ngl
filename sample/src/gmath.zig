const std = @import("std");
const assert = std.debug.assert;

pub fn addV(comptime n: comptime_int, lh: [n]f32, rh: [n]f32) [n]f32 {
    const a: @Vector(n, f32) = lh;
    const b: @Vector(n, f32) = rh;
    return a + b;
}

pub fn negV(comptime n: comptime_int, vector: [n]f32) [n]f32 {
    const v: @Vector(n, f32) = vector;
    return -v;
}

pub fn subV(comptime n: comptime_int, lh: [n]f32, rh: [n]f32) [n]f32 {
    return addV(n, lh, negV(n, rh));
}

pub fn scaleV(comptime n: comptime_int, vector: [n]f32, scalar: f32) [n]f32 {
    const v: @Vector(n, f32) = vector;
    const s: @Vector(n, f32) = @splat(scalar);
    return v * s;
}

pub fn dot(comptime n: comptime_int, lh: [n]f32, rh: [n]f32) f32 {
    const a: @Vector(n, f32) = lh;
    const b: @Vector(n, f32) = rh;
    return @reduce(.Add, a * b);
}

pub fn length(comptime n: comptime_int, vector: [n]f32) f32 {
    return @sqrt(dot(n, vector, vector));
}

pub fn normalize(comptime n: comptime_int, vector: [n]f32) [n]f32 {
    const len = length(n, vector);
    assert(!std.math.approxEqAbs(f32, len, 0, std.math.floatEps(f32)));
    return scaleV(n, vector, 1 / len);
}

pub fn cross(lh: [3]f32, rh: [3]f32) [3]f32 {
    const a: @Vector(3, f32) = lh;
    const b: @Vector(3, f32) = rh;
    const mask = .{
        @Vector(3, i32){ 1, 2, 0 },
        @Vector(3, i32){ 2, 0, 1 },
    };
    const v = .{
        @shuffle(f32, a, undefined, mask[0]) * @shuffle(f32, b, undefined, mask[1]),
        @shuffle(f32, b, undefined, mask[0]) * @shuffle(f32, a, undefined, mask[1]),
    };
    return v[0] - v[1];
}

pub fn iQ() [4]f32 {
    return .{ 0, 0, 0, 1 };
}

pub fn mulQ(lh: [4]f32, rh: [4]f32) [4]f32 {
    const q: @Vector(4, f32) = lh;
    const p: @Vector(4, f32) = rh;
    const q_imag = @shuffle(f32, q, undefined, @Vector(3, i32){ 0, 1, 2 });
    const p_imag = @shuffle(f32, p, undefined, @Vector(3, i32){ 0, 1, 2 });
    const q_real: @Vector(3, f32) = @splat(q[3]);
    const p_real: @Vector(3, f32) = @splat(p[3]);
    const imag = q_imag * p_real + p_imag * q_real + cross(q_imag, p_imag);
    const real = q_real * p_real - @as(@Vector(3, f32), @splat(dot(3, q_imag, p_imag)));
    return @shuffle(f32, imag, real, @Vector(4, i32){ 0, 1, 2, ~@as(i32, 0) });
}

pub fn rotateQ(axis: [3]f32, angle: f32) [4]f32 {
    const half_angle = angle * 0.5;
    const sin: @Vector(3, f32) = @splat(@sin(half_angle));
    const cos: @Vector(3, f32) = @splat(@cos(half_angle));
    return @shuffle(f32, sin * normalize(3, axis), cos, @Vector(4, i32){ 0, 1, 2, ~@as(i32, 0) });
}

pub fn iM(comptime n: comptime_int) [n * n]f32 {
    var m: @Vector(n * n, f32) = @splat(0);
    for (0..n) |i|
        m[i * n + i] = 1;
    return m;
}

pub fn mulM(comptime n: comptime_int, lh: [n * n]f32, rh: [n * n]f32) [n * n]f32 {
    const row_mask = comptime blk: {
        var m: [n]@Vector(n, i32) = undefined;
        for (0..n) |i|
            for (0..n) |j| {
                m[i][j] = i + n * j;
            };
        break :blk m;
    };
    const col_mask = comptime blk: {
        var m: [n]@Vector(n, i32) = undefined;
        for (0..n) |i|
            for (0..n) |j| {
                m[i][j] = i * n + j;
            };
        break :blk m;
    };
    var m: @Vector(n * n, f32) = undefined;
    inline for (0..n) |i|
        inline for (0..n) |j| {
            const row = @shuffle(f32, lh, undefined, row_mask[j]);
            const col = @shuffle(f32, rh, undefined, col_mask[i]);
            m[i * n + j] = @reduce(.Add, row * col);
        };
    return m;
}

pub fn mulMV(comptime n: comptime_int, matrix: [n * n]f32, vector: [n]f32) [n]f32 {
    const row_mask = comptime blk: {
        var m: [n]@Vector(n, i32) = undefined;
        for (0..n) |i|
            for (0..n) |j| {
                m[i][j] = i + n * j;
            };
        break :blk m;
    };
    const m: @Vector(n * n, f32) = matrix;
    const v: @Vector(n, f32) = vector;
    var res: [n]f32 = undefined;
    inline for (0..n) |i|
        res[i] = @reduce(.Add, @shuffle(f32, m, undefined, row_mask[i]) * v);
    return res;
}

pub fn translate(x: f32, y: f32, z: f32) [4 * 4]f32 {
    return .{
        1, 0, 0, 0,
        0, 1, 0, 0,
        0, 0, 1, 0,
        x, y, z, 1,
    };
}

pub fn rotateM(comptime n: comptime_int, axis: [3]f32, angle: f32) [n * n]f32 {
    const x_y_z: @Vector(3, f32) = normalize(3, axis);
    const y_z_x = @shuffle(f32, x_y_z, undefined, @Vector(3, i32){ 1, 2, 0 });
    const z_x_y = @shuffle(f32, x_y_z, undefined, @Vector(3, i32){ 2, 0, 1 });
    const xx_yy_zz = x_y_z * x_y_z;
    const xy_yz_zx = x_y_z * y_z_x;
    const one: @Vector(3, f32) = @splat(1);
    const cos: @Vector(3, f32) = @splat(@cos(angle));
    const dcos = one - cos;
    const sin: @Vector(3, f32) = @splat(@sin(angle));
    const dcosxx_dcosyy_dcoszz = dcos * xx_yy_zz;
    const dcosxy_dcosyz_dcoszx = dcos * xy_yz_zx;
    const sinz_sinx_siny = sin * z_x_y;
    const m00_m11_m22 = cos + dcosxx_dcosyy_dcoszz;
    const m01_m12_m20 = dcosxy_dcosyz_dcoszx + sinz_sinx_siny;
    const m10_m21_m02 = dcosxy_dcosyz_dcoszx - sinz_sinx_siny;
    return switch (n) {
        3 => .{
            m00_m11_m22[0],
            m01_m12_m20[0],
            m10_m21_m02[2],

            m10_m21_m02[0],
            m00_m11_m22[1],
            m01_m12_m20[1],

            m01_m12_m20[2],
            m10_m21_m02[1],
            m00_m11_m22[2],
        },
        4 => .{
            m00_m11_m22[0],
            m01_m12_m20[0],
            m10_m21_m02[2],
            0,

            m10_m21_m02[0],
            m00_m11_m22[1],
            m01_m12_m20[1],
            0,

            m01_m12_m20[2],
            m10_m21_m02[1],
            m00_m11_m22[2],
            0,

            0,
            0,
            0,
            1,
        },
        else => @compileError("Only for 3x3 and 4x4 matrices"),
    };
}

pub fn rotateMQ(comptime n: comptime_int, quaternion: [4]f32) [n * n]f32 {
    const q: @Vector(4, f32) = normalize(4, quaternion);
    const two: @Vector(4, f32) = @splat(2);
    const xx2_yy2_zz2_na = q * q * two;
    const xy2_yz2_zx2_na = q * @shuffle(f32, q, undefined, @Vector(4, i32){ 1, 2, 0, 3 }) * two;
    const zw2_xw2_yw2_na = @shuffle(
        f32,
        q * @as(@Vector(4, f32), @splat(q[3])) * two,
        undefined,
        @Vector(4, i32){ 2, 0, 1, 3 },
    );
    const m00_m11_m22 =
        @as(@Vector(3, f32), @splat(1)) -
        @shuffle(f32, xx2_yy2_zz2_na, undefined, @Vector(3, i32){ 1, 0, 0 }) -
        @shuffle(f32, xx2_yy2_zz2_na, undefined, @Vector(3, i32){ 2, 2, 1 });
    const m01_m12_m20_na = xy2_yz2_zx2_na + zw2_xw2_yw2_na;
    const m10_m21_m02_na = xy2_yz2_zx2_na - zw2_xw2_yw2_na;
    return switch (n) {
        3 => .{
            m00_m11_m22[0],
            m01_m12_m20_na[0],
            m10_m21_m02_na[2],

            m10_m21_m02_na[0],
            m00_m11_m22[1],
            m01_m12_m20_na[1],

            m01_m12_m20_na[2],
            m10_m21_m02_na[1],
            m00_m11_m22[2],
        },
        4 => .{
            m00_m11_m22[0],
            m01_m12_m20_na[0],
            m10_m21_m02_na[2],
            0,

            m10_m21_m02_na[0],
            m00_m11_m22[1],
            m01_m12_m20_na[1],
            0,

            m01_m12_m20_na[2],
            m10_m21_m02_na[1],
            m00_m11_m22[2],
            0,

            0,
            0,
            0,
            1,
        },
        else => @compileError("Only for 3x3 and 4x4 matrices"),
    };
}

pub fn scale3(x: f32, y: f32, z: f32) [3 * 3]f32 {
    return .{
        x, 0, 0,
        0, y, 0,
        0, 0, z,
    };
}

pub fn scale4(x: f32, y: f32, z: f32) [4 * 4]f32 {
    return .{
        x, 0, 0, 0,
        0, y, 0, 0,
        0, 0, z, 0,
        0, 0, 0, 1,
    };
}

pub fn lookAt(eye: [3]f32, center: [3]f32, up: [3]f32) [4 * 4]f32 {
    const f = normalize(3, subV(3, center, eye));
    const s = normalize(3, cross(f, up));
    const u = cross(f, s);
    return .{
        s[0],
        u[0],
        f[0],
        0,
        s[1],
        u[1],
        f[1],
        0,
        s[2],
        u[2],
        f[2],
        0,
        -dot(3, s, eye),
        -dot(3, u, eye),
        -dot(3, f, eye),
        1,
    };
}

pub fn frustum(left: f32, right: f32, top: f32, bottom: f32, znear: f32, zfar: f32) [4 * 4]f32 {
    var m = [_]f32{0} ** 16;
    m[0] = (2 * znear) / (right - left);
    m[5] = (2 * znear) / (bottom - top);
    m[8] = -(right + left) / (right - left);
    m[9] = -(bottom + top) / (bottom - top);
    m[10] = zfar / (zfar - znear);
    m[11] = 1;
    m[14] = -(zfar * znear) / (zfar - znear);
    return m;
}

pub fn perspective(yfov: f32, aspect_ratio: f32, znear: f32, zfar: f32) [4 * 4]f32 {
    var m = [_]f32{0} ** 16;
    const ct = 1 / @tan(yfov * 0.5);
    m[0] = ct / aspect_ratio;
    m[5] = ct;
    m[10] = zfar / (zfar - znear);
    m[11] = 1;
    m[14] = -(zfar * znear) / (zfar - znear);
    return m;
}

pub fn det3(matrix: [3 * 3]f32) f32 {
    const m00 = matrix[0];
    const m01 = matrix[1];
    const m02 = matrix[2];
    const m10 = matrix[3];
    const m11 = matrix[4];
    const m12 = matrix[5];
    const m20 = matrix[6];
    const m21 = matrix[7];
    const m22 = matrix[8];
    return m00 * (m11 * m22 - m12 * m21) -
        m01 * (m10 * m22 - m12 * m20) +
        m02 * (m10 * m21 - m11 * m20);
}

pub fn invert3(matrix: [3 * 3]f32) [3 * 3]f32 {
    const m00 = matrix[0];
    const m01 = matrix[1];
    const m02 = matrix[2];
    const m10 = matrix[3];
    const m11 = matrix[4];
    const m12 = matrix[5];
    const m20 = matrix[6];
    const m21 = matrix[7];
    const m22 = matrix[8];
    const s0 = m11 * m22 - m12 * m21;
    const s1 = m10 * m22 - m12 * m20;
    const s2 = m10 * m21 - m11 * m20;
    const det = m00 * s0 - m01 * s1 + m02 * s2;
    assert(!std.math.approxEqAbs(f32, det, 0, std.math.floatEps(f32)));
    return @as(@Vector(3 * 3, f32), @splat(1 / det)) * @Vector(3 * 3, f32){
        s0,
        -(m01 * m22 - m02 * m21),
        m01 * m12 - m02 * m11,

        -s1,
        m00 * m22 - m02 * m20,
        -(m00 * m12 - m02 * m10),

        s2,
        -(m00 * m21 - m01 * m20),
        m00 * m11 - m01 * m10,
    };
}

pub fn det4(matrix: [4 * 4]f32) f32 {
    const m00 = matrix[0];
    const m01 = matrix[1];
    const m02 = matrix[2];
    const m03 = matrix[3];
    const m10 = matrix[4];
    const m11 = matrix[5];
    const m12 = matrix[6];
    const m13 = matrix[7];
    const m20 = matrix[8];
    const m21 = matrix[9];
    const m22 = matrix[10];
    const m23 = matrix[11];
    const m30 = matrix[12];
    const m31 = matrix[13];
    const m32 = matrix[14];
    const m33 = matrix[15];
    return (m00 * m11 - m01 * m10) * (m22 * m33 - m23 * m32) -
        (m00 * m12 - m02 * m10) * (m21 * m33 - m23 * m31) +
        (m00 * m13 - m03 * m10) * (m21 * m32 - m22 * m31) +
        (m01 * m12 - m02 * m11) * (m20 * m33 - m23 * m30) -
        (m01 * m13 - m03 * m11) * (m20 * m32 - m22 * m30) +
        (m02 * m13 - m03 * m12) * (m20 * m31 - m21 * m30);
}

pub fn invert4(matrix: [4 * 4]f32) [4 * 4]f32 {
    const m00 = matrix[0];
    const m01 = matrix[1];
    const m02 = matrix[2];
    const m03 = matrix[3];
    const m10 = matrix[4];
    const m11 = matrix[5];
    const m12 = matrix[6];
    const m13 = matrix[7];
    const m20 = matrix[8];
    const m21 = matrix[9];
    const m22 = matrix[10];
    const m23 = matrix[11];
    const m30 = matrix[12];
    const m31 = matrix[13];
    const m32 = matrix[14];
    const m33 = matrix[15];
    const s0 = m00 * m11 - m01 * m10;
    const s1 = m00 * m12 - m02 * m10;
    const s2 = m00 * m13 - m03 * m10;
    const s3 = m01 * m12 - m02 * m11;
    const s4 = m01 * m13 - m03 * m11;
    const s5 = m02 * m13 - m03 * m12;
    const c0 = m20 * m31 - m21 * m30;
    const c1 = m20 * m32 - m22 * m30;
    const c2 = m20 * m33 - m23 * m30;
    const c3 = m21 * m32 - m22 * m31;
    const c4 = m21 * m33 - m23 * m31;
    const c5 = m22 * m33 - m23 * m32;
    const det = s0 * c5 - s1 * c4 + s2 * c3 + s3 * c2 - s4 * c1 + s5 * c0;
    assert(!std.math.approxEqAbs(f32, det, 0, std.math.floatEps(f32)));
    return @as(@Vector(4 * 4, f32), @splat(1 / det)) * @Vector(4 * 4, f32){
        c5 * m11 - c4 * m12 + c3 * m13,
        -c5 * m01 + c4 * m02 - c3 * m03,
        s5 * m31 - s4 * m32 + s3 * m33,
        -s5 * m21 + s4 * m22 - s3 * m23,

        -c5 * m10 + c2 * m12 - c1 * m13,
        c5 * m00 - c2 * m02 + c1 * m03,
        -s5 * m30 + s2 * m32 - s1 * m33,
        s5 * m20 - s2 * m22 + s1 * m23,

        c4 * m10 - c2 * m11 + c0 * m13,
        -c4 * m00 + c2 * m01 - c0 * m03,
        s4 * m30 - s2 * m31 + s0 * m33,
        -s4 * m20 + s2 * m21 - s0 * m23,

        -c3 * m10 + c1 * m11 - c0 * m12,
        c3 * m00 - c1 * m01 + c0 * m02,
        -s3 * m30 + s1 * m31 - s0 * m32,
        s3 * m20 - s1 * m21 + s0 * m22,
    };
}

pub fn transpose(comptime n: comptime_int, matrix: [n * n]f32) [n * n]f32 {
    const mask = comptime blk: {
        var m: @Vector(n * n, f32) = undefined;
        for (0..n) |i|
            for (0..n) |j| {
                m[i * n + j] = i + n * j;
            };
        break :blk m;
    };
    const m: @Vector(n * n, f32) = matrix;
    return @shuffle(f32, m, undefined, mask);
}

pub fn upperLeft(comptime n: comptime_int, matrix: [n * n]f32) [(n - 1) * (n - 1)]f32 {
    var m: [(n - 1) * (n - 1)]f32 = undefined;
    for (0..n - 1) |i|
        @memcpy(
            m[i * (n - 1) .. i * (n - 1) + n - 1],
            matrix[i * n .. i * n + n - 1],
        );
    return m;
}

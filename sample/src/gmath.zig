const std = @import("std");
const assert = std.debug.assert;

pub const v3f = vScope(3, f32);
pub const v4f = vScope(4, f32);

fn vScope(comptime n: comptime_int, comptime T: type) type {
    return struct {
        pub const V = [n]T;

        pub fn add(lh: V, rh: V) V {
            return addV(n, T, lh, rh);
        }

        pub fn neg(vector: V) V {
            return negV(n, T, vector);
        }

        pub fn sub(lh: V, rh: V) V {
            return subV(n, T, lh, rh);
        }

        pub fn scale(vector: V, scalar: T) V {
            return scaleV(n, T, vector, scalar);
        }

        pub fn dot(lh: V, rh: V) T {
            return dotV(n, T, lh, rh);
        }

        pub fn length(vector: V) T {
            return lengthV(n, T, vector);
        }

        pub fn normalize(vector: V) V {
            return normalizeV(n, T, vector);
        }

        pub fn cross(lh: V, rh: V) V {
            comptime assert(n == 3);
            return crossV(T, lh, rh);
        }
    };
}

fn addV(comptime n: comptime_int, comptime T: type, lh: [n]T, rh: [n]T) [n]T {
    const a: @Vector(n, T) = lh;
    const b: @Vector(n, T) = rh;
    return a + b;
}

fn negV(comptime n: comptime_int, comptime T: type, vector: [n]T) [n]T {
    const v: @Vector(n, T) = vector;
    return -v;
}

fn subV(comptime n: comptime_int, comptime T: type, lh: [n]T, rh: [n]T) [n]T {
    return addV(n, T, lh, negV(n, T, rh));
}

fn scaleV(comptime n: comptime_int, comptime T: type, vector: [n]T, scalar: T) [n]T {
    const v: @Vector(n, T) = vector;
    const s: @Vector(n, T) = @splat(scalar);
    return v * s;
}

fn dotV(comptime n: comptime_int, comptime T: type, lh: [n]T, rh: [n]T) T {
    const a: @Vector(n, T) = lh;
    const b: @Vector(n, T) = rh;
    return @reduce(.Add, a * b);
}

fn lengthV(comptime n: comptime_int, comptime T: type, vector: [n]T) T {
    return @sqrt(dotV(n, T, vector, vector));
}

fn normalizeV(comptime n: comptime_int, comptime T: type, vector: [n]T) [n]T {
    const len = lengthV(n, T, vector);
    assert(!std.math.approxEqAbs(T, len, 0, std.math.floatEps(T)));
    return scaleV(n, T, vector, 1 / len);
}

fn crossV(comptime T: type, lh: [3]T, rh: [3]T) [3]T {
    const a: @Vector(3, T) = lh;
    const b: @Vector(3, T) = rh;
    const mask = .{
        @Vector(3, i32){ 1, 2, 0 },
        @Vector(3, i32){ 2, 0, 1 },
    };
    const v = .{
        @shuffle(T, a, undefined, mask[0]) * @shuffle(T, b, undefined, mask[1]),
        @shuffle(T, b, undefined, mask[0]) * @shuffle(T, a, undefined, mask[1]),
    };
    return v[0] - v[1];
}

pub const qf = qScope(f32);

fn qScope(comptime T: type) type {
    return struct {
        pub const Q = [4]T;

        pub const id = Q{ 0, 0, 0, 1 };

        pub fn mul(lh: Q, rh: Q) Q {
            return mulQ(T, lh, rh);
        }

        pub fn rotate(axis: [3]T, angle: T) Q {
            return rotateQ(T, axis, angle);
        }
    };
}

fn mulQ(comptime T: type, lh: [4]T, rh: [4]T) [4]T {
    const q: @Vector(4, T) = lh;
    const p: @Vector(4, T) = rh;
    const q_imag = @shuffle(T, q, undefined, @Vector(3, i32){ 0, 1, 2 });
    const p_imag = @shuffle(T, p, undefined, @Vector(3, i32){ 0, 1, 2 });
    const q_real: @Vector(3, T) = @splat(q[3]);
    const p_real: @Vector(3, T) = @splat(p[3]);
    const imag = q_imag * p_real + p_imag * q_real + crossV(T, q_imag, p_imag);
    const real = q_real * p_real - @as(@Vector(3, T), @splat(dotV(3, T, q_imag, p_imag)));
    return @shuffle(T, imag, real, @Vector(4, i32){ 0, 1, 2, ~@as(i32, 0) });
}

fn rotateQ(comptime T: type, axis: [3]T, angle: T) [4]T {
    const half_angle = angle * 0.5;
    const sin: @Vector(3, T) = @splat(@sin(half_angle));
    const cos: @Vector(3, T) = @splat(@cos(half_angle));
    return @shuffle(T, sin * normalizeV(3, T, axis), cos, @Vector(4, i32){ 0, 1, 2, ~@as(i32, 0) });
}

pub const m3f = mScope(3, f32);
pub const m4f = mScope(4, f32);

fn mScope(comptime n: comptime_int, comptime T: type) type {
    return struct {
        pub const M = [n * n]T;

        pub const id: M = blk: {
            var m: @Vector(n * n, T) = @splat(0);
            for (0..n) |i|
                m[i * n + i] = 1;
            break :blk m;
        };

        pub fn mul(lh: M, rh: anytype) switch (rh.len) {
            n * n => M,
            n => [n]T,
            else => unreachable,
        } {
            return switch (@TypeOf(rh)) {
                M => mulM(n, T, lh, rh),
                [n]T => mulMV(n, T, lh, rh),
                else => |U| blk: {
                    const S = @typeInfo(U).Struct;
                    comptime assert(S.is_tuple);
                    break :blk switch (S.fields.len) {
                        n * n => mulM(n, T, lh, rh),
                        n => mulMV(n, T, lh, rh),
                        else => comptime unreachable,
                    };
                },
            };
        }

        pub fn t(x: T, y: T, z: T) M {
            comptime assert(n == 4);
            return tM(T, x, y, z);
        }

        pub fn r(quaternion: [4]T) M {
            comptime assert(n > 2 and n < 5);
            return rM(n, T, quaternion);
        }

        pub fn rEuler(axis: [3]T, angle: T) M {
            comptime assert(n > 2 and n < 5);
            return rMEuler(n, T, axis, angle);
        }

        pub fn s(x: T, y: T, z: T) M {
            comptime assert(n > 2 and n < 5);
            return sM(n, T, x, y, z);
        }

        pub fn lookAt(eye: [3]T, center: [3]T, up: [3]T) M {
            comptime assert(n == 4);
            return lookAtM(T, eye, center, up);
        }

        pub fn frustum(left: T, right: T, top: T, bottom: T, znear: T, zfar: T) M {
            comptime assert(n == 4);
            return frustumM(T, left, right, top, bottom, znear, zfar);
        }

        pub fn perspective(yfov: T, aspect_ratio: T, znear: T, zfar: T) M {
            comptime assert(n == 4);
            return perspectiveM(T, yfov, aspect_ratio, znear, zfar);
        }

        pub fn det(matrix: M) T {
            comptime assert(n > 2 and n < 5);
            return detM(n, T, matrix);
        }

        pub fn invert(matrix: M) M {
            comptime assert(n > 2 and n < 5);
            return invertM(n, T, matrix);
        }

        pub fn transpose(matrix: M) M {
            return transposeM(n, T, matrix);
        }

        pub fn upperLeft(matrix: M) [(n - 1) * (n - 1)]T {
            return upperLeftM(n, T, matrix);
        }

        pub fn to3x4(matrix: M, fill: T) [3 * 4]T {
            comptime assert(n > 2 and n < 5);
            return toM3x4(n, T, matrix, fill);
        }
    };
}

fn mulM(comptime n: comptime_int, comptime T: type, lh: [n * n]T, rh: [n * n]T) [n * n]T {
    const row_mask = comptime blk: {
        var mask: [n]@Vector(n, i32) = undefined;
        for (0..n) |i|
            for (0..n) |j| {
                mask[i][j] = i + n * j;
            };
        break :blk mask;
    };
    const col_mask = comptime blk: {
        var mask: [n]@Vector(n, i32) = undefined;
        for (0..n) |i|
            for (0..n) |j| {
                mask[i][j] = i * n + j;
            };
        break :blk mask;
    };
    var m: @Vector(n * n, T) = undefined;
    inline for (0..n) |i|
        inline for (0..n) |j| {
            const row = @shuffle(T, lh, undefined, row_mask[j]);
            const col = @shuffle(T, rh, undefined, col_mask[i]);
            m[i * n + j] = @reduce(.Add, row * col);
        };
    return m;
}

fn mulMV(comptime n: comptime_int, comptime T: type, matrix: [n * n]T, vector: [n]T) [n]T {
    const row_mask = comptime blk: {
        var mask: [n]@Vector(n, i32) = undefined;
        for (0..n) |i|
            for (0..n) |j| {
                mask[i][j] = i + n * j;
            };
        break :blk mask;
    };
    const m: @Vector(n * n, T) = matrix;
    const v: @Vector(n, T) = vector;
    var res: [n]T = undefined;
    inline for (0..n) |i|
        res[i] = @reduce(.Add, @shuffle(T, m, undefined, row_mask[i]) * v);
    return res;
}

fn tM(comptime T: type, x: T, y: T, z: T) [4 * 4]T {
    return .{
        1, 0, 0, 0,
        0, 1, 0, 0,
        0, 0, 1, 0,
        x, y, z, 1,
    };
}

fn rM(comptime n: comptime_int, comptime T: type, quaternion: [4]T) [n * n]T {
    const q: @Vector(4, T) = normalizeV(4, T, quaternion);
    const two: @Vector(4, T) = @splat(2);
    const xx2_yy2_zz2_na = q * q * two;
    const xy2_yz2_zx2_na = q * @shuffle(T, q, undefined, @Vector(4, i32){ 1, 2, 0, 3 }) * two;
    const zw2_xw2_yw2_na = @shuffle(
        T,
        q * @as(@Vector(4, T), @splat(q[3])) * two,
        undefined,
        @Vector(4, i32){ 2, 0, 1, 3 },
    );
    const m00_m11_m22 =
        @as(@Vector(3, T), @splat(1)) -
        @shuffle(T, xx2_yy2_zz2_na, undefined, @Vector(3, i32){ 1, 0, 0 }) -
        @shuffle(T, xx2_yy2_zz2_na, undefined, @Vector(3, i32){ 2, 2, 1 });
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
        else => unreachable,
    };
}

fn rMEuler(comptime n: comptime_int, comptime T: type, axis: [3]T, angle: T) [n * n]T {
    const x_y_z: @Vector(3, T) = normalizeV(3, T, axis);
    const y_z_x = @shuffle(T, x_y_z, undefined, @Vector(3, i32){ 1, 2, 0 });
    const z_x_y = @shuffle(T, x_y_z, undefined, @Vector(3, i32){ 2, 0, 1 });
    const xx_yy_zz = x_y_z * x_y_z;
    const xy_yz_zx = x_y_z * y_z_x;
    const one: @Vector(3, T) = @splat(1);
    const cos: @Vector(3, T) = @splat(@cos(angle));
    const dcos = one - cos;
    const sin: @Vector(3, T) = @splat(@sin(angle));
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
        else => unreachable,
    };
}

fn sM(comptime n: comptime_int, comptime T: type, x: T, y: T, z: T) [n * n]T {
    return switch (n) {
        3 => .{
            x, 0, 0,
            0, y, 0,
            0, 0, z,
        },
        4 => .{
            x, 0, 0, 0,
            0, y, 0, 0,
            0, 0, z, 0,
            0, 0, 0, 1,
        },
        else => unreachable,
    };
}

fn lookAtM(comptime T: type, eye: [3]T, center: [3]T, up: [3]T) [4 * 4]T {
    const f = normalizeV(3, T, subV(3, T, center, eye));
    const s = normalizeV(3, T, crossV(T, f, up));
    const u = crossV(T, f, s);
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
        -dotV(3, T, s, eye),
        -dotV(3, T, u, eye),
        -dotV(3, T, f, eye),
        1,
    };
}

fn frustumM(comptime T: type, left: T, right: T, top: T, bottom: T, znear: T, zfar: T) [4 * 4]T {
    var m = [_]T{0} ** 16;
    m[0] = (2 * znear) / (right - left);
    m[5] = (2 * znear) / (bottom - top);
    m[8] = -(right + left) / (right - left);
    m[9] = -(bottom + top) / (bottom - top);
    m[10] = zfar / (zfar - znear);
    m[11] = 1;
    m[14] = -(zfar * znear) / (zfar - znear);
    return m;
}

fn perspectiveM(comptime T: type, yfov: T, aspect_ratio: T, znear: T, zfar: T) [4 * 4]T {
    var m = [_]T{0} ** 16;
    const ct = 1 / @tan(yfov * 0.5);
    m[0] = ct / aspect_ratio;
    m[5] = ct;
    m[10] = zfar / (zfar - znear);
    m[11] = 1;
    m[14] = -(zfar * znear) / (zfar - znear);
    return m;
}

fn detM(comptime n: comptime_int, comptime T: type, matrix: [n * n]T) T {
    switch (n) {
        3 => {
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
        },
        4 => {
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
        },
        else => unreachable,
    }
}

fn invertM(comptime n: comptime_int, comptime T: type, matrix: [n * n]T) [n * n]T {
    switch (n) {
        3 => {
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
            assert(!std.math.approxEqAbs(T, det, 0, std.math.floatEps(T)));
            return @as(@Vector(3 * 3, T), @splat(1 / det)) * @Vector(3 * 3, T){
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
        },
        4 => {
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
            assert(!std.math.approxEqAbs(T, det, 0, std.math.floatEps(T)));
            return @as(@Vector(4 * 4, T), @splat(1 / det)) * @Vector(4 * 4, T){
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
        },
        else => unreachable,
    }
}

fn transposeM(comptime n: comptime_int, comptime T: type, matrix: [n * n]T) [n * n]T {
    const mask = comptime blk: {
        var mask: @Vector(n * n, i32) = undefined;
        for (0..n) |i|
            for (0..n) |j| {
                mask[i * n + j] = i + n * j;
            };
        break :blk mask;
    };
    const m: @Vector(n * n, T) = matrix;
    return @shuffle(T, m, undefined, mask);
}

fn upperLeftM(comptime n: comptime_int, comptime T: type, matrix: [n * n]T) [(n - 1) * (n - 1)]T {
    var m: [(n - 1) * (n - 1)]T = undefined;
    for (0..n - 1) |i|
        @memcpy(
            m[i * (n - 1) .. i * (n - 1) + n - 1],
            matrix[i * n .. i * n + n - 1],
        );
    return m;
}

fn toM3x4(comptime n: comptime_int, comptime T: type, matrix: [n * n]T, fill: T) [3 * 4]T {
    const m: @Vector(n * n, T) = matrix;
    return switch (n) {
        3 => .{
            m[0], m[1], m[2], fill,
            m[3], m[4], m[5], fill,
            m[6], m[7], m[8], fill,
        },
        4 => @shuffle(T, m, undefined, @Vector(3 * 4, i32){
            0, 1, 2,  3,
            4, 5, 6,  7,
            8, 9, 10, 11,
        }),
        else => unreachable,
    };
}

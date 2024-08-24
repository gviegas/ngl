const std = @import("std");
const assert = std.debug.assert;

pub const v3f = vScope(3, f32);
pub const v4f = vScope(4, f32);

fn vScope(comptime n: comptime_int, comptime T: type) type {
    return struct {
        pub const V = [n]T;

        pub fn add(lh: V, rh: V) V {
            const v: @Vector(n, T) = lh;
            const u: @Vector(n, T) = rh;
            return v + u;
        }

        pub fn neg(vector: V) V {
            const v: @Vector(n, T) = vector;
            return -v;
        }

        pub fn sub(lh: V, rh: V) V {
            return add(lh, neg(rh));
        }

        pub fn scale(vector: V, scalar: T) V {
            const v: @Vector(n, T) = vector;
            const s: @Vector(n, T) = @splat(scalar);
            return v * s;
        }

        pub fn dot(lh: V, rh: V) T {
            const v: @Vector(n, T) = lh;
            const u: @Vector(n, T) = rh;
            return @reduce(.Add, v * u);
        }

        pub fn length(vector: V) T {
            return @sqrt(dot(vector, vector));
        }

        pub fn normalize(vector: V) V {
            const len = length(vector);
            assert(!std.math.approxEqAbs(T, len, 0, std.math.floatEps(T)));
            return scale(vector, 1 / len);
        }

        pub fn cross(lh: V, rh: V) V {
            const v: @Vector(3, T) = lh;
            const u: @Vector(3, T) = rh;
            const masks = .{
                @Vector(3, i32){ 1, 2, 0 },
                @Vector(3, i32){ 2, 0, 1 },
            };
            const vs = .{
                @shuffle(T, v, undefined, masks[0]) * @shuffle(T, u, undefined, masks[1]),
                @shuffle(T, u, undefined, masks[0]) * @shuffle(T, v, undefined, masks[1]),
            };
            return vs[0] - vs[1];
        }
    };
}

pub const qf = qScope(f32);

fn qScope(comptime T: type) type {
    return struct {
        pub const Q = [4]T;

        pub const id = Q{ 0, 0, 0, 1 };

        const v3 = vScope(3, T);

        pub fn mul(lh: Q, rh: Q) Q {
            const q: @Vector(4, T) = lh;
            const p: @Vector(4, T) = rh;
            const q_imag = @shuffle(T, q, undefined, @Vector(3, i32){ 0, 1, 2 });
            const p_imag = @shuffle(T, p, undefined, @Vector(3, i32){ 0, 1, 2 });
            const q_real: @Vector(3, T) = @splat(q[3]);
            const p_real: @Vector(3, T) = @splat(p[3]);
            const q_cross_p: @Vector(3, T) = v3.cross(q_imag, p_imag);
            const q_dot_p: @Vector(3, T) = @splat(v3.dot(q_imag, p_imag));
            const imag = q_imag * p_real + p_imag * q_real + q_cross_p;
            const real = q_real * p_real - q_dot_p;
            return @shuffle(T, imag, real, @Vector(4, i32){ 0, 1, 2, ~@as(i32, 0) });
        }

        pub fn rotate(axis: [3]T, angle: T) Q {
            const v: @Vector(3, T) = v3.normalize(axis);
            const a = angle * 0.5;
            const sin: @Vector(3, T) = @splat(@sin(a));
            const cos: @Vector(3, T) = @splat(@cos(a));
            return @shuffle(T, sin * v, cos, @Vector(4, i32){ 0, 1, 2, ~@as(i32, 0) });
        }
    };
}

pub const m3f = mScope(3, f32);
pub const m4f = mScope(4, f32);

fn mScope(comptime n: comptime_int, comptime T: type) type {
    return struct {
        pub const M = [n * n]T;
        pub const V = [n]T;

        pub const id: M = blk: {
            var m: @Vector(n * n, T) = @splat(0);
            for (0..n) |i|
                m[i * n + i] = 1;
            break :blk m;
        };

        const v3 = vScope(3, T);
        const v4 = vScope(4, T);

        fn mulM(lh: M, rh: M) M {
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

        fn mulV(matrix: M, vector: V) V {
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
            var res: V = undefined;
            inline for (0..n) |i|
                res[i] = @reduce(.Add, @shuffle(T, m, undefined, row_mask[i]) * v);
            return res;
        }

        pub fn mul(lh: M, rh: anytype) switch (rh.len) {
            n * n => M,
            n => V,
            else => unreachable,
        } {
            return switch (@TypeOf(rh)) {
                M => mulM(lh, rh),
                V => mulV(lh, rh),
                else => |U| blk: {
                    const S = @typeInfo(U).Struct;
                    comptime assert(S.is_tuple);
                    break :blk switch (S.fields.len) {
                        n * n => mulM(lh, rh),
                        n => mulV(lh, rh),
                        else => comptime unreachable,
                    };
                },
            };
        }

        pub fn t(x: T, y: T, z: T) M {
            return .{
                1, 0, 0, 0,
                0, 1, 0, 0,
                0, 0, 1, 0,
                x, y, z, 1,
            };
        }

        pub fn r(quaternion: [4]T) M {
            const nq: @Vector(4, T) = v4.normalize(quaternion);
            const x_y_z: @Vector(3, T) = @shuffle(T, nq, undefined, @Vector(3, i32){ 0, 1, 2 });
            const w: @Vector(3, T) = @shuffle(T, nq, undefined, @Vector(3, i32){ 3, 3, 3 });
            const one: @Vector(3, T) = @splat(1);
            const two: @Vector(3, T) = @splat(2);
            const x2_y2_z2 = x_y_z * two;
            const xx2_yy2_zz2 = x_y_z * x2_y2_z2;
            const yy2_xx2_xx2 = @shuffle(T, xx2_yy2_zz2, undefined, @Vector(3, i32){ 1, 0, 0 });
            const zz2_zz2_yy2 = @shuffle(T, xx2_yy2_zz2, undefined, @Vector(3, i32){ 2, 2, 1 });
            const y_z_x: @Vector(3, T) = @shuffle(T, x_y_z, undefined, @Vector(3, i32){ 1, 2, 0 });
            const xy2_yz2_zx2 = y_z_x * x2_y2_z2;
            const zw2_xw2_yw2 = @shuffle(T, x2_y2_z2 * w, undefined, @Vector(3, i32){ 2, 0, 1 });
            const m00_m11_m22 = one - yy2_xx2_xx2 - zz2_zz2_yy2;
            const m01_m12_m20 = xy2_yz2_zx2 + zw2_xw2_yw2;
            const m10_m21_m02 = xy2_yz2_zx2 - zw2_xw2_yw2;
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
                else => comptime unreachable,
            };
        }

        pub fn rEuler(axis: [3]T, angle: T) M {
            const x_y_z: @Vector(3, T) = v3.normalize(axis);
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
                else => comptime unreachable,
            };
        }

        pub fn s(x: T, y: T, z: T) M {
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
                else => comptime unreachable,
            };
        }

        pub fn lookAt(eye: [3]T, center: [3]T, up: [3]T) M {
            const f = v3.normalize(v3.sub(center, eye));
            const l = v3.normalize(v3.cross(f, up));
            const u = v3.cross(f, l);
            return .{
                l[0],
                u[0],
                f[0],
                0,
                l[1],
                u[1],
                f[1],
                0,
                l[2],
                u[2],
                f[2],
                0,
                -v3.dot(l, eye),
                -v3.dot(u, eye),
                -v3.dot(f, eye),
                1,
            };
        }

        pub fn perspective(yfov: T, aspect_ratio: T, znear: T, zfar: T) M {
            var m = [_]T{0} ** 16;
            const ct = 1 / @tan(yfov * 0.5);
            m[0] = ct / aspect_ratio;
            m[5] = ct;
            m[10] = zfar / (zfar - znear);
            m[11] = 1;
            m[14] = -(zfar * znear) / (zfar - znear);
            return m;
        }

        pub fn frustum(left: T, right: T, top: T, bottom: T, znear: T, zfar: T) M {
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

        pub fn ortho(left: T, right: T, top: T, bottom: T, znear: T, zfar: T) M {
            var m = [_]T{0} ** 16;
            m[0] = 2 / (right - left);
            m[5] = 2 / (bottom - top);
            m[10] = 1 / (zfar - znear);
            m[12] = -(right + left) / (right - left);
            m[13] = -(bottom + top) / (bottom - top);
            m[14] = -znear / (zfar - znear);
            m[15] = 1;
            return m;
        }

        pub fn det(matrix: M) T {
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
                else => comptime unreachable,
            }
        }

        pub fn invert(matrix: M) M {
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
                    const detm = m00 * s0 - m01 * s1 + m02 * s2;
                    assert(!std.math.approxEqAbs(T, detm, 0, std.math.floatEps(T)));
                    return @as(@Vector(3 * 3, T), @splat(1 / detm)) * @Vector(3 * 3, T){
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
                    const detm = s0 * c5 - s1 * c4 + s2 * c3 + s3 * c2 - s4 * c1 + s5 * c0;
                    assert(!std.math.approxEqAbs(T, detm, 0, std.math.floatEps(T)));
                    return @as(@Vector(4 * 4, T), @splat(1 / detm)) * @Vector(4 * 4, T){
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
                else => comptime unreachable,
            }
        }

        pub fn transpose(matrix: M) M {
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

        pub fn upperLeft(matrix: M) [(n - 1) * (n - 1)]T {
            var m: [(n - 1) * (n - 1)]T = undefined;
            for (0..n - 1) |i|
                @memcpy(
                    m[i * (n - 1) .. i * (n - 1) + n - 1],
                    matrix[i * n .. i * n + n - 1],
                );
            return m;
        }

        pub fn to3x4(matrix: M, fill: T) [3 * 4]T {
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
                else => comptime unreachable,
            };
        }
    };
}

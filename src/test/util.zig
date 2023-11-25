pub fn addV(comptime n: comptime_int, lh: [n]f32, rh: [n]f32) [n]f32 {
    const a: @Vector(n, f32) = lh;
    const b: @Vector(n, f32) = rh;
    return a + b;
}

pub fn subV(comptime n: comptime_int, lh: [n]f32, rh: [n]f32) [n]f32 {
    const a: @Vector(n, f32) = lh;
    const b: @Vector(n, f32) = rh;
    return a - b;
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

pub fn len(comptime n: comptime_int, vector: [n]f32) f32 {
    return @sqrt(dot(n, vector, vector));
}

pub fn norm(comptime n: comptime_int, vector: [n]f32) [n]f32 {
    return scaleV(n, vector, 1 / len(n, vector));
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

pub fn identity(comptime n: comptime_int) [n * n]f32 {
    var m: @Vector(n * n, f32) = @splat(0);
    for (0..n) |i| m[i * n + i] = 1;
    return m;
}

pub fn mulM(comptime n: comptime_int, lh: [n * n]f32, rh: [n * n]f32) [n * n]f32 {
    const row_mask = comptime blk: {
        var m: [n]@Vector(n, i32) = undefined;
        for (0..n) |i| {
            for (0..n) |j| {
                m[i][j] = i + n * j;
            }
        }
        break :blk m;
    };
    const col_mask = comptime blk: {
        var m: [n]@Vector(n, i32) = undefined;
        for (0..n) |i| {
            for (0..n) |j| {
                m[i][j] = i * n + j;
            }
        }
        break :blk m;
    };
    var m: @Vector(n * n, f32) = undefined;
    inline for (0..n) |i| {
        inline for (0..n) |j| {
            const row = @shuffle(f32, lh, undefined, row_mask[j]);
            const col = @shuffle(f32, rh, undefined, col_mask[i]);
            m[i * n + j] = @reduce(.Add, row * col);
        }
    }
    return m;
}

pub fn mulMV(comptime n: comptime_int, matrix: [n * n]f32, vector: [n]f32) [n]f32 {
    const row_mask = comptime blk: {
        var m: [n]@Vector(n, i32) = undefined;
        for (0..n) |i| {
            for (0..n) |j| {
                m[i][j] = i + n * j;
            }
        }
        break :blk m;
    };
    const m: @Vector(n * n, f32) = matrix;
    const v: @Vector(n, f32) = vector;
    var res: [n]f32 = undefined;
    inline for (0..n) |i|
        res[i] = @reduce(.Add, @shuffle(f32, m, undefined, row_mask[i]) * v);
    return res;
}

pub fn lookAt(center: [3]f32, eye: [3]f32, up: [3]f32) [16]f32 {
    const f = norm(3, subV(3, center, eye));
    const s = norm(3, cross(f, up));
    const u = cross(f, s);
    return .{
        s[0],
        u[0],
        -f[0],
        0,
        s[1],
        u[1],
        -f[1],
        0,
        s[2],
        u[2],
        -f[2],
        0,
        -dot(3, s, eye),
        -dot(3, u, eye),
        dot(3, f, eye),
        1,
    };
}

pub fn infPerspective(yfov: f32, aspect_ratio: f32, znear: f32) [16]f32 {
    var m = [_]f32{0} ** 16;
    const ct = 1 / @tan(yfov * 0.5);
    m[0] = ct / aspect_ratio;
    m[5] = ct;
    m[10] = -1;
    m[11] = -1;
    m[14] = -2 * znear;
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
    const inv_det = 1 / (m00 * s0 - m01 * s1 + m02 * s2);
    return @as(@Vector(3 * 3, f32), @splat(inv_det)) * @Vector(3 * 3, f32){
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

pub fn transpose(comptime n: comptime_int, matrix: [n * n]f32) [n * n]f32 {
    const mask = comptime blk: {
        var m: @Vector(n * n, f32) = undefined;
        for (0..n) |i| {
            for (0..n) |j| {
                m[i * n + j] = i + n * j;
            }
        }
        break :blk m;
    };
    const m: @Vector(n * n, f32) = matrix;
    return @shuffle(f32, m, undefined, mask);
}

pub fn upperLeft(comptime n: comptime_int, matrix: [n * n]f32) [(n - 1) * (n - 1)]f32 {
    var m: [(n - 1) * (n - 1)]f32 = undefined;
    for (0..n - 1) |i| @memcpy(
        m[i * (n - 1) .. i * (n - 1) + n - 1],
        matrix[i * n .. i * n + n - 1],
    );
    return m;
}

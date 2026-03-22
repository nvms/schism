const std = @import("std");

pub const Vec3 = struct {
    x: f64,
    y: f64,
    z: f64,

    pub const zero = Vec3{ .x = 0, .y = 0, .z = 0 };
    pub const one = Vec3{ .x = 1, .y = 1, .z = 1 };
    pub const up = Vec3{ .x = 0, .y = 1, .z = 0 };
    pub const forward = Vec3{ .x = 0, .y = 0, .z = -1 };
    pub const right = Vec3{ .x = 1, .y = 0, .z = 0 };

    pub fn init(x: f64, y: f64, z: f64) Vec3 {
        return .{ .x = x, .y = y, .z = z };
    }

    pub fn splat(v: f64) Vec3 {
        return .{ .x = v, .y = v, .z = v };
    }

    pub fn add(a: Vec3, b: Vec3) Vec3 {
        return .{ .x = a.x + b.x, .y = a.y + b.y, .z = a.z + b.z };
    }

    pub fn sub(a: Vec3, b: Vec3) Vec3 {
        return .{ .x = a.x - b.x, .y = a.y - b.y, .z = a.z - b.z };
    }

    pub fn mul(a: Vec3, b: Vec3) Vec3 {
        return .{ .x = a.x * b.x, .y = a.y * b.y, .z = a.z * b.z };
    }

    pub fn scale(v: Vec3, s: f64) Vec3 {
        return .{ .x = v.x * s, .y = v.y * s, .z = v.z * s };
    }

    pub fn dot(a: Vec3, b: Vec3) f64 {
        return a.x * b.x + a.y * b.y + a.z * b.z;
    }

    pub fn cross(a: Vec3, b: Vec3) Vec3 {
        return .{
            .x = a.y * b.z - a.z * b.y,
            .y = a.z * b.x - a.x * b.z,
            .z = a.x * b.y - a.y * b.x,
        };
    }

    pub fn length(v: Vec3) f64 {
        return @sqrt(v.dot(v));
    }

    pub fn lengthSq(v: Vec3) f64 {
        return v.dot(v);
    }

    pub fn normalize(v: Vec3) Vec3 {
        const len = v.length();
        if (len == 0) return Vec3.zero;
        return v.scale(1.0 / len);
    }

    pub fn negate(v: Vec3) Vec3 {
        return .{ .x = -v.x, .y = -v.y, .z = -v.z };
    }

    pub fn lerp(a: Vec3, b: Vec3, t: f64) Vec3 {
        return a.add(b.sub(a).scale(t));
    }

    pub fn reflect(v: Vec3, n: Vec3) Vec3 {
        return v.sub(n.scale(2.0 * v.dot(n)));
    }

    pub fn refract(v: Vec3, n: Vec3, eta: f64) ?Vec3 {
        const cos_i = v.negate().dot(n);
        const sin2_t = eta * eta * (1.0 - cos_i * cos_i);
        if (sin2_t > 1.0) return null;
        const cos_t = @sqrt(1.0 - sin2_t);
        return v.scale(eta).add(n.scale(eta * cos_i - cos_t));
    }

    pub fn abs(v: Vec3) Vec3 {
        return .{ .x = @abs(v.x), .y = @abs(v.y), .z = @abs(v.z) };
    }

    pub fn max(a: Vec3, b: Vec3) Vec3 {
        return .{
            .x = @max(a.x, b.x),
            .y = @max(a.y, b.y),
            .z = @max(a.z, b.z),
        };
    }

    pub fn min(a: Vec3, b: Vec3) Vec3 {
        return .{
            .x = @min(a.x, b.x),
            .y = @min(a.y, b.y),
            .z = @min(a.z, b.z),
        };
    }

    pub fn maxComponent(v: Vec3) f64 {
        return @max(v.x, @max(v.y, v.z));
    }

    pub fn minComponent(v: Vec3) f64 {
        return @min(v.x, @min(v.y, v.z));
    }
};

pub const Ray = struct {
    origin: Vec3,
    dir: Vec3,

    pub fn init(origin: Vec3, dir: Vec3) Ray {
        return .{ .origin = origin, .dir = dir.normalize() };
    }

    pub fn at(r: Ray, t: f64) Vec3 {
        return r.origin.add(r.dir.scale(t));
    }
};

pub fn clamp(val: f64, lo: f64, hi: f64) f64 {
    return @max(lo, @min(hi, val));
}

test "vec3 basic ops" {
    const a = Vec3.init(1, 2, 3);
    const b = Vec3.init(4, 5, 6);

    const sum = a.add(b);
    try std.testing.expectApproxEqAbs(sum.x, 5.0, 1e-10);
    try std.testing.expectApproxEqAbs(sum.y, 7.0, 1e-10);
    try std.testing.expectApproxEqAbs(sum.z, 9.0, 1e-10);

    const d = a.dot(b);
    try std.testing.expectApproxEqAbs(d, 32.0, 1e-10);
}

test "vec3 cross product" {
    const x = Vec3.right;
    const y = Vec3.up;
    const z = x.cross(y);
    try std.testing.expectApproxEqAbs(z.x, 0.0, 1e-10);
    try std.testing.expectApproxEqAbs(z.y, 0.0, 1e-10);
    try std.testing.expectApproxEqAbs(z.z, 1.0, 1e-10);
}

test "vec3 normalize" {
    const v = Vec3.init(3, 0, 0);
    const n = v.normalize();
    try std.testing.expectApproxEqAbs(n.x, 1.0, 1e-10);
    try std.testing.expectApproxEqAbs(n.length(), 1.0, 1e-10);

    const z = Vec3.zero.normalize();
    try std.testing.expectApproxEqAbs(z.length(), 0.0, 1e-10);
}

test "vec3 reflect" {
    const v = Vec3.init(1, -1, 0).normalize();
    const n = Vec3.up;
    const r = v.reflect(n);
    try std.testing.expectApproxEqAbs(r.x, v.x, 1e-10);
    try std.testing.expectApproxEqAbs(r.y, -v.y, 1e-10);
}

test "vec3 refract" {
    const v = Vec3.init(0, -1, 0);
    const n = Vec3.up;
    const r = v.refract(n, 1.0).?;
    try std.testing.expectApproxEqAbs(r.x, 0.0, 1e-10);
    try std.testing.expectApproxEqAbs(r.y, -1.0, 1e-10);

    const tir = Vec3.init(0.9, -0.1, 0).normalize().refract(n, 2.5);
    try std.testing.expect(tir == null);
}

test "ray at" {
    const r = Ray.init(Vec3.zero, Vec3.init(1, 0, 0));
    const p = r.at(5.0);
    try std.testing.expectApproxEqAbs(p.x, 5.0, 1e-10);
    try std.testing.expectApproxEqAbs(p.y, 0.0, 1e-10);
}

test "clamp" {
    try std.testing.expectApproxEqAbs(clamp(1.5, 0.0, 1.0), 1.0, 1e-10);
    try std.testing.expectApproxEqAbs(clamp(-0.5, 0.0, 1.0), 0.0, 1e-10);
    try std.testing.expectApproxEqAbs(clamp(0.5, 0.0, 1.0), 0.5, 1e-10);
}

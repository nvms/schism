const std = @import("std");
const math = @import("math.zig");
const Vec3 = math.Vec3;

pub const FractalType = enum {
    mandelbulb,
    menger,
    sierpinski,
    julia,
    kleinian,
    ifs,
};

pub const FractalParams = struct {
    fractal_type: FractalType,
    power: f64 = 8.0,
    max_iterations: u32 = 50,
    bailout: f64 = 4.0,
    julia_c: Vec3 = Vec3.init(-0.2, 0.6, -0.2),
    scale: f64 = 2.0,
    offset: Vec3 = Vec3.init(1.0, 1.0, 1.0),
};

pub const SDFResult = struct {
    distance: f64,
    // orbit trap values for coloring
    trap: Vec3,
    // minimum orbit distance (for AO-like effects)
    min_orbit: f64,
    iterations: u32,
};

pub fn sdf(p: Vec3, params: FractalParams) SDFResult {
    return switch (params.fractal_type) {
        .mandelbulb => mandelbulb(p, params),
        .menger => menger(p, params),
        .sierpinski => sierpinski(p, params),
        .julia => julia(p, params),
        .kleinian => kleinian(p, params),
        .ifs => ifsFractal(p, params),
    };
}

pub fn sdfDistance(p: Vec3, params: FractalParams) f64 {
    return sdf(p, params).distance;
}

fn mandelbulb(p: Vec3, params: FractalParams) SDFResult {
    var z = p;
    var dr: f64 = 1.0;
    var r: f64 = 0.0;
    const power = params.power;
    var min_orbit: f64 = 1e10;
    var trap = Vec3.splat(1e10);
    var i: u32 = 0;

    while (i < params.max_iterations) : (i += 1) {
        r = z.length();
        if (r > params.bailout) break;

        // orbit trap: track closest approach to coordinate planes
        const orbit = z.abs();
        trap = trap.min(orbit);
        min_orbit = @min(min_orbit, r);

        var theta = std.math.acos(math.clamp(z.z / r, -1.0, 1.0));
        var phi = std.math.atan2(z.y, z.x);
        dr = std.math.pow(f64, r, power - 1.0) * power * dr + 1.0;

        const zr = std.math.pow(f64, r, power);
        theta *= power;
        phi *= power;

        z = Vec3.init(
            @sin(theta) * @cos(phi),
            @sin(phi) * @sin(theta),
            @cos(theta),
        ).scale(zr).add(p);
    }
    return .{
        .distance = 0.5 * @log(r) * r / dr,
        .trap = trap,
        .min_orbit = min_orbit,
        .iterations = i,
    };
}

fn menger(p: Vec3, params: FractalParams) SDFResult {
    var z = p;
    const iterations: u32 = @min(params.max_iterations, 20);
    var min_orbit: f64 = 1e10;
    var trap = Vec3.splat(1e10);
    var i: u32 = 0;

    while (i < iterations) : (i += 1) {
        z = z.abs();
        if (z.x < z.y) z = Vec3.init(z.y, z.x, z.z);
        if (z.x < z.z) z = Vec3.init(z.z, z.y, z.x);
        if (z.y < z.z) z = Vec3.init(z.x, z.z, z.y);

        trap = trap.min(z.abs());
        min_orbit = @min(min_orbit, z.length());

        z = z.scale(params.scale);
        z = z.sub(params.offset.scale(params.scale - 1.0));

        if (z.z < -0.5 * params.offset.z * (params.scale - 1.0)) {
            z.z += params.offset.z * (params.scale - 1.0);
        }
    }
    const s = std.math.pow(f64, params.scale, -@as(f64, @floatFromInt(iterations)));
    return .{
        .distance = z.length() * s,
        .trap = trap,
        .min_orbit = min_orbit,
        .iterations = i,
    };
}

fn sierpinski(p: Vec3, params: FractalParams) SDFResult {
    var z = p;
    const iterations: u32 = @min(params.max_iterations, 20);
    var min_orbit: f64 = 1e10;
    var trap = Vec3.splat(1e10);
    var i: u32 = 0;

    while (i < iterations) : (i += 1) {
        if (z.x + z.y < 0) z = Vec3.init(-z.y, -z.x, z.z);
        if (z.x + z.z < 0) z = Vec3.init(-z.z, z.y, -z.x);
        if (z.y + z.z < 0) z = Vec3.init(z.x, -z.z, -z.y);

        trap = trap.min(z.abs());
        min_orbit = @min(min_orbit, z.length());

        z = z.scale(params.scale).sub(params.offset.scale(params.scale - 1.0));
    }
    const s = std.math.pow(f64, params.scale, -@as(f64, @floatFromInt(iterations)));
    return .{
        .distance = (z.length() - 1.5) * s,
        .trap = trap,
        .min_orbit = min_orbit,
        .iterations = i,
    };
}

fn julia(p: Vec3, params: FractalParams) SDFResult {
    var z = p;
    var r: f64 = 0.0;
    var dr: f64 = 1.0;
    const c = params.julia_c;
    var min_orbit: f64 = 1e10;
    var trap = Vec3.splat(1e10);
    var i: u32 = 0;

    while (i < params.max_iterations) : (i += 1) {
        r = z.length();
        if (r > params.bailout) break;

        trap = trap.min(z.abs());
        min_orbit = @min(min_orbit, r);

        const x2 = z.x * z.x;
        const y2 = z.y * z.y;
        const z2 = z.z * z.z;
        const new_x = x2 - y2 - z2;
        const new_y = 2.0 * z.x * z.y;
        const new_z = 2.0 * z.x * z.z;

        dr = 2.0 * r * dr + 1.0;
        z = Vec3.init(new_x, new_y, new_z).add(c);
    }
    return .{
        .distance = 0.5 * @log(r) * r / dr,
        .trap = trap,
        .min_orbit = min_orbit,
        .iterations = i,
    };
}

fn kleinian(p: Vec3, params: FractalParams) SDFResult {
    var z = p;
    var de: f64 = 1.0;
    const box_size = params.offset;
    var min_orbit: f64 = 1e10;
    var trap = Vec3.splat(1e10);
    var i: u32 = 0;

    while (i < params.max_iterations) : (i += 1) {
        z.x = z.x - box_size.x * @round(z.x / box_size.x);
        z.z = z.z - box_size.z * @round(z.z / box_size.z);

        trap = trap.min(z.abs());
        min_orbit = @min(min_orbit, z.length());

        const r2 = z.lengthSq();
        if (r2 < 0.001) break;

        const k = @max(1.0 / r2, 1.0);
        z = z.scale(k);
        de *= k;
    }
    const r = z.length();
    return .{
        .distance = r / de,
        .trap = trap,
        .min_orbit = min_orbit,
        .iterations = i,
    };
}

fn ifsFractal(p: Vec3, params: FractalParams) SDFResult {
    var z = p;
    const s = params.scale;
    const iterations: u32 = @min(params.max_iterations, 20);
    var min_orbit: f64 = 1e10;
    var trap = Vec3.splat(1e10);
    var i: u32 = 0;

    while (i < iterations) : (i += 1) {
        z = z.abs();
        if (z.x - z.y < 0) z = Vec3.init(z.y, z.x, z.z);
        if (z.x - z.z < 0) z = Vec3.init(z.z, z.y, z.x);
        if (z.y - z.z < 0) z = Vec3.init(z.x, z.z, z.y);

        trap = trap.min(z.abs());
        min_orbit = @min(min_orbit, z.length());

        z = z.scale(s).sub(params.offset.scale(s - 1.0));
    }
    const si = std.math.pow(f64, s, -@as(f64, @floatFromInt(iterations)));
    return .{
        .distance = z.length() * si,
        .trap = trap,
        .min_orbit = min_orbit,
        .iterations = i,
    };
}

pub fn estimateNormal(p: Vec3, params: FractalParams) Vec3 {
    const eps = 0.0001;
    const dx = sdfDistance(p.add(Vec3.init(eps, 0, 0)), params) - sdfDistance(p.sub(Vec3.init(eps, 0, 0)), params);
    const dy = sdfDistance(p.add(Vec3.init(0, eps, 0)), params) - sdfDistance(p.sub(Vec3.init(0, eps, 0)), params);
    const dz = sdfDistance(p.add(Vec3.init(0, 0, eps)), params) - sdfDistance(p.sub(Vec3.init(0, 0, eps)), params);
    return Vec3.init(dx, dy, dz).normalize();
}

// soft shadow via sphere tracing toward light
pub fn softShadow(origin: Vec3, dir: Vec3, params: FractalParams, k: f64) f64 {
    var result: f64 = 1.0;
    var t: f64 = 0.01;
    var i: u32 = 0;
    while (i < 64) : (i += 1) {
        const p = origin.add(dir.scale(t));
        const d = sdfDistance(p, params);
        if (d < 0.0001) return 0.0;
        result = @min(result, k * d / t);
        t += math.clamp(d, 0.001, 0.5);
        if (t > 20.0) break;
    }
    return math.clamp(result, 0.0, 1.0);
}

// SDF-based ambient occlusion
pub fn ambientOcclusion(p: Vec3, n: Vec3, params: FractalParams) f64 {
    var ao: f64 = 0.0;
    var scale: f64 = 1.0;
    for (1..6) |i| {
        const fi = @as(f64, @floatFromInt(i));
        const step = 0.02 * fi;
        const d = sdfDistance(p.add(n.scale(step)), params);
        ao += (step - d) * scale;
        scale *= 0.5;
    }
    return math.clamp(1.0 - 3.0 * ao, 0.0, 1.0);
}

test "mandelbulb sdf positive far from origin" {
    const params = FractalParams{ .fractal_type = .mandelbulb };
    const r = mandelbulb(Vec3.init(10, 10, 10), params);
    try std.testing.expect(r.distance > 0);
}

test "mandelbulb sdf decreases toward surface" {
    const params = FractalParams{ .fractal_type = .mandelbulb };
    const d_far = mandelbulb(Vec3.init(3, 0, 0), params).distance;
    const d_near = mandelbulb(Vec3.init(1.5, 0, 0), params).distance;
    try std.testing.expect(d_far > d_near);
}

test "mandelbulb orbit trap tracks values" {
    const params = FractalParams{ .fractal_type = .mandelbulb };
    const r = mandelbulb(Vec3.init(1.0, 0.5, 0.3), params);
    try std.testing.expect(r.trap.x < 1e10);
    try std.testing.expect(r.min_orbit < 1e10);
}

test "menger sdf symmetry" {
    const params = FractalParams{ .fractal_type = .menger, .scale = 3.0, .max_iterations = 5 };
    const a = menger(Vec3.init(0.5, 0.3, 0.1), params).distance;
    const b = menger(Vec3.init(0.5, 0.1, 0.3), params).distance;
    try std.testing.expectApproxEqAbs(a, b, 1e-10);
}

test "sierpinski sdf positive far from origin" {
    const params = FractalParams{ .fractal_type = .sierpinski };
    const d = sierpinski(Vec3.init(5, 5, 5), params).distance;
    try std.testing.expect(d > 0);
}

test "julia sdf positive far from origin" {
    const params = FractalParams{ .fractal_type = .julia };
    const d = julia(Vec3.init(10, 10, 10), params).distance;
    try std.testing.expect(d > 0);
}

test "estimate normal points outward for sphere-like region" {
    const params = FractalParams{ .fractal_type = .mandelbulb };
    const n = estimateNormal(Vec3.init(2, 0, 0), params);
    try std.testing.expect(n.x > 0.5);
}

test "sdf dispatch matches direct call" {
    const params = FractalParams{ .fractal_type = .menger, .scale = 3.0, .max_iterations = 5 };
    const p = Vec3.init(0.7, 0.3, 0.1);
    const dispatched = sdf(p, params).distance;
    const direct = menger(p, params).distance;
    try std.testing.expectApproxEqAbs(dispatched, direct, 1e-15);
}

test "soft shadow returns 1.0 in open space" {
    const params = FractalParams{ .fractal_type = .mandelbulb };
    const s = softShadow(Vec3.init(5, 5, 5), Vec3.init(0, 1, 0), params, 8.0);
    try std.testing.expect(s > 0.9);
}

test "ambient occlusion near surface" {
    const params = FractalParams{ .fractal_type = .mandelbulb };
    const ao = ambientOcclusion(Vec3.init(2, 0, 0), Vec3.init(1, 0, 0), params);
    try std.testing.expect(ao > 0.0);
    try std.testing.expect(ao <= 1.0);
}

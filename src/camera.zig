const std = @import("std");
const m = @import("math.zig");
const Vec3 = m.Vec3;
const Ray = m.Ray;

pub const Camera = struct {
    position: Vec3,
    forward: Vec3,
    right: Vec3,
    up: Vec3,
    fov: f64,
    aspect: f64,
    aperture: f64,
    focus_dist: f64,

    pub fn init(opts: struct {
        position: Vec3 = Vec3.init(0, 0, 3),
        look_at: Vec3 = Vec3.zero,
        up: Vec3 = Vec3.up,
        fov_degrees: f64 = 60.0,
        aspect: f64 = 16.0 / 9.0,
        aperture: f64 = 0.0,
        focus_dist: f64 = 0.0,
    }) Camera {
        const fwd = opts.look_at.sub(opts.position).normalize();
        const r = fwd.cross(opts.up).normalize();
        const u = r.cross(fwd);
        const fd = if (opts.focus_dist == 0.0) opts.look_at.sub(opts.position).length() else opts.focus_dist;

        return .{
            .position = opts.position,
            .forward = fwd,
            .right = r,
            .up = u,
            .fov = opts.fov_degrees * std.math.pi / 180.0,
            .aspect = opts.aspect,
            .aperture = opts.aperture,
            .focus_dist = fd,
        };
    }

    pub fn ray(self: Camera, u: f64, v: f64) Ray {
        const half_h = @tan(self.fov / 2.0);
        const half_w = half_h * self.aspect;

        const x = (2.0 * u - 1.0) * half_w;
        const y = (2.0 * v - 1.0) * half_h;

        const dir = self.forward
            .add(self.right.scale(x))
            .add(self.up.scale(y))
            .normalize();

        return Ray.init(self.position, dir);
    }

    pub fn rayDOF(self: Camera, u: f64, v: f64, lens_u: f64, lens_v: f64) Ray {
        if (self.aperture == 0.0) return self.ray(u, v);

        const half_h = @tan(self.fov / 2.0);
        const half_w = half_h * self.aspect;

        const x = (2.0 * u - 1.0) * half_w;
        const y = (2.0 * v - 1.0) * half_h;

        const focus_point = self.position.add(
            self.forward
                .add(self.right.scale(x))
                .add(self.up.scale(y))
                .normalize()
                .scale(self.focus_dist),
        );

        // uniform disk sampling
        const r = self.aperture * @sqrt(lens_u);
        const theta = 2.0 * std.math.pi * lens_v;
        const offset = self.right.scale(r * @cos(theta)).add(self.up.scale(r * @sin(theta)));

        const origin = self.position.add(offset);
        return Ray.init(origin, focus_point.sub(origin));
    }
};

test "camera ray center points forward" {
    const cam = Camera.init(.{
        .position = Vec3.init(0, 0, 3),
        .look_at = Vec3.zero,
    });
    const r = cam.ray(0.5, 0.5);
    try std.testing.expect(r.dir.z < 0);
    try std.testing.expectApproxEqAbs(r.dir.x, 0.0, 1e-10);
    try std.testing.expectApproxEqAbs(r.dir.y, 0.0, 1e-10);
}

test "camera ray corners diverge" {
    const cam = Camera.init(.{});
    const tl = cam.ray(0.0, 1.0);
    const br = cam.ray(1.0, 0.0);
    try std.testing.expect(tl.dir.x < 0);
    try std.testing.expect(tl.dir.y > 0);
    try std.testing.expect(br.dir.x > 0);
    try std.testing.expect(br.dir.y < 0);
}

test "camera no dof matches regular ray" {
    const cam = Camera.init(.{ .aperture = 0.0 });
    const r1 = cam.ray(0.3, 0.7);
    const r2 = cam.rayDOF(0.3, 0.7, 0.5, 0.5);
    try std.testing.expectApproxEqAbs(r1.dir.x, r2.dir.x, 1e-10);
    try std.testing.expectApproxEqAbs(r1.dir.y, r2.dir.y, 1e-10);
    try std.testing.expectApproxEqAbs(r1.dir.z, r2.dir.z, 1e-10);
}

test "camera dof shifts origin" {
    const cam = Camera.init(.{ .aperture = 0.1, .focus_dist = 3.0 });
    const r1 = cam.rayDOF(0.5, 0.5, 0.0, 0.0);
    const r2 = cam.rayDOF(0.5, 0.5, 1.0, 0.5);
    const diff = r1.origin.sub(r2.origin).length();
    try std.testing.expect(diff > 0.001);
}

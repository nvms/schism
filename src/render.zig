const std = @import("std");
const m = @import("math.zig");
const Vec3 = m.Vec3;
const Ray = m.Ray;
const spectrum = @import("spectrum.zig");
const fractals = @import("fractals.zig");
const Camera = @import("camera.zig").Camera;

pub const max_march_steps = 512;
pub const max_distance = 50.0;
pub const surface_epsilon = 0.00005;
pub const max_bounces = 6;

pub const HitResult = struct {
    distance: f64,
    position: Vec3,
    normal: Vec3,
    steps: u32,
    trap: Vec3,
    min_orbit: f64,
    iterations: u32,
};

pub fn raymarch(ray: Ray, params: fractals.FractalParams) ?HitResult {
    var t: f64 = 0.001;
    var steps: u32 = 0;
    var last_result: fractals.SDFResult = undefined;

    while (steps < max_march_steps) : (steps += 1) {
        const p = ray.at(t);
        last_result = fractals.sdf(p, params);
        const d = last_result.distance;

        if (d < surface_epsilon * t) {
            return .{
                .distance = t,
                .position = p,
                .normal = fractals.estimateNormal(p, params),
                .steps = steps,
                .trap = last_result.trap,
                .min_orbit = last_result.min_orbit,
                .iterations = last_result.iterations,
            };
        }

        t += d * 0.8;
        if (t > max_distance) break;
    }
    return null;
}

pub const Material = struct {
    roughness: f64 = 0.4,
    metallic: f64 = 0.0,
    ior: f64 = 1.5,
    emission: f64 = 0.0,
};

pub const RenderConfig = struct {
    width: u32 = 1920,
    height: u32 = 1080,
    samples_per_pixel: u32 = 64,
    fractal: fractals.FractalParams = .{ .fractal_type = .mandelbulb },
    material: Material = .{},
    camera: Camera = Camera.init(.{}),
    fog_density: f64 = 0.03,
    fog_color: Vec3 = Vec3.init(0.0, 0.0, 0.0),
    exposure: f64 = 1.5,
    color_phase1: f64 = 0.0,
    color_phase2: f64 = 0.0,
};

pub fn tracePixel(
    px: u32,
    py: u32,
    config: RenderConfig,
    rng: *std.Random.Pcg,
) Vec3 {
    var accum = Vec3.zero;
    const r = rng.random();

    for (0..config.samples_per_pixel) |_| {
        const jx = r.float(f64);
        const jy = r.float(f64);
        const u = (@as(f64, @floatFromInt(px)) + jx) / @as(f64, @floatFromInt(config.width));
        const v = 1.0 - (@as(f64, @floatFromInt(py)) + jy) / @as(f64, @floatFromInt(config.height));

        const lens_u = r.float(f64);
        const lens_v = r.float(f64);
        const rgb = tracePath(u, v, lens_u, lens_v, config, r);
        accum = accum.add(rgb);
    }

    const n = @as(f64, @floatFromInt(config.samples_per_pixel));
    var color = accum.scale(1.0 / n);
    color = color.scale(config.exposure);
    color = acesTonemap(color);
    return gammaCorrect(color);
}

fn tracePath(
    u: f64,
    v: f64,
    lens_u: f64,
    lens_v: f64,
    config: RenderConfig,
    r: std.Random,
) Vec3 {
    var current_ray = config.camera.rayDOF(u, v, lens_u, lens_v);
    var throughput = Vec3.one;
    var result = Vec3.zero;

    for (0..max_bounces) |bounce| {
        const hit = raymarch(current_ray, config.fractal) orelse {
            // environment: dark with subtle gradient
            const env = envColor(current_ray.dir);
            result = result.add(throughput.mul(env));
            break;
        };

        // surface color from orbit trap
        const surface_color = orbitTrapColor(hit.trap, hit.min_orbit, hit.iterations, config);

        // ambient occlusion
        const ao = fractals.ambientOcclusion(hit.position, hit.normal, config.fractal);

        // lighting
        const light1_dir = Vec3.init(0.6, 0.8, -0.3).normalize();
        const light2_dir = Vec3.init(-0.5, 0.3, 0.7).normalize();
        const light1_color = Vec3.init(1.2, 1.0, 0.8);
        const light2_color = Vec3.init(0.3, 0.4, 0.6);

        // soft shadows
        const shadow_origin = hit.position.add(hit.normal.scale(0.002));
        const shadow1 = fractals.softShadow(shadow_origin, light1_dir, config.fractal, 12.0);
        const shadow2 = fractals.softShadow(shadow_origin, light2_dir, config.fractal, 12.0);

        // BRDF evaluation
        const view_dir = current_ray.dir.negate();
        const brdf1 = evaluateBRDF(hit.normal, light1_dir, view_dir, surface_color, config.material);
        const brdf2 = evaluateBRDF(hit.normal, light2_dir, view_dir, surface_color, config.material);

        var direct = brdf1.mul(light1_color).scale(shadow1)
            .add(brdf2.mul(light2_color).scale(shadow2));

        // ambient term
        const ambient = surface_color.scale(0.04 * ao);
        direct = direct.add(ambient);

        // emission
        if (config.material.emission > 0) {
            const emit_strength = config.material.emission * ao;
            direct = direct.add(surface_color.scale(emit_strength));
        }

        // fog
        const fog_factor = @exp(-config.fog_density * hit.distance);
        direct = direct.scale(fog_factor).add(config.fog_color.scale(1.0 - fog_factor));

        result = result.add(throughput.mul(direct));

        if (bounce >= max_bounces - 1) break;

        // russian roulette after first few bounces
        if (bounce > 2) {
            const p_continue = @min(throughput.maxComponent(), 0.95);
            if (r.float(f64) > p_continue) break;
            throughput = throughput.scale(1.0 / p_continue);
        }

        // bounce: importance sample based on roughness
        const bounce_dir = if (config.material.roughness < 0.3)
            importanceSampleGGX(hit.normal, view_dir, config.material.roughness, r)
        else
            randomHemisphere(hit.normal, r);

        current_ray = Ray.init(shadow_origin, bounce_dir);
        throughput = throughput.mul(surface_color).scale(0.5);
    }

    return result;
}

fn orbitTrapColor(trap: Vec3, min_orbit: f64, iterations: u32, config: RenderConfig) Vec3 {
    const t = m.clamp(trap.x * 2.0, 0.0, 1.0);
    const s = m.clamp(trap.y * 2.0, 0.0, 1.0);
    const q = m.clamp(trap.z * 2.0, 0.0, 1.0);
    const orbit_norm = m.clamp(min_orbit / 2.0, 0.0, 1.0);
    const iter_norm = m.clamp(@as(f64, @floatFromInt(iterations)) / 50.0, 0.0, 1.0);

    const p1 = config.color_phase1;
    const p2 = config.color_phase2;

    const r = m.clamp(0.5 + 0.5 * @sin(t * 5.0 + orbit_norm * 3.0 + p1), 0.0, 1.0);
    const g = m.clamp(0.5 + 0.5 * @sin(s * 4.0 + iter_norm * 2.5 + p2), 0.0, 1.0);
    const b = m.clamp(0.5 + 0.5 * @sin(q * 3.0 + orbit_norm * 4.0 + p1 + p2), 0.0, 1.0);

    return Vec3.init(r * 0.9, g * 0.8, b * 0.85);
}

fn evaluateBRDF(normal: Vec3, light_dir: Vec3, view_dir: Vec3, albedo: Vec3, mat: Material) Vec3 {
    const ndotl = @max(normal.dot(light_dir), 0.0);
    if (ndotl <= 0.0) return Vec3.zero;

    const half_vec = light_dir.add(view_dir).normalize();
    const ndoth = @max(normal.dot(half_vec), 0.0);
    const ndotv = @max(normal.dot(view_dir), 0.001);

    // Fresnel-Schlick
    const f0_dielectric = 0.04;
    const f0 = Vec3.lerp(Vec3.splat(f0_dielectric), albedo, mat.metallic);
    const vdoth = @max(view_dir.dot(half_vec), 0.0);
    const fresnel_factor = std.math.pow(f64, 1.0 - vdoth, 5.0);
    const fresnel = f0.add(Vec3.one.sub(f0).scale(fresnel_factor));

    // GGX distribution
    const a = mat.roughness * mat.roughness;
    const a2 = a * a;
    const denom_d = ndoth * ndoth * (a2 - 1.0) + 1.0;
    const D = a2 / (std.math.pi * denom_d * denom_d + 0.0001);

    // Smith geometry
    const k = (mat.roughness + 1.0) * (mat.roughness + 1.0) / 8.0;
    const g1 = ndotv / (ndotv * (1.0 - k) + k);
    const g2 = ndotl / (ndotl * (1.0 - k) + k);
    const G = g1 * g2;

    // specular
    const spec = fresnel.scale(D * G / (4.0 * ndotv * ndotl + 0.001));

    // diffuse (energy conserving)
    const ks = fresnel;
    const kd = Vec3.one.sub(ks).scale(1.0 - mat.metallic);
    const diffuse = kd.mul(albedo).scale(1.0 / std.math.pi);

    return diffuse.add(spec).scale(ndotl);
}

fn envColor(dir: Vec3) Vec3 {
    // very dark environment with subtle gradient
    const t = @max(dir.y * 0.5 + 0.5, 0.0);
    return Vec3.init(0.001, 0.001, 0.002).scale(t);
}

fn importanceSampleGGX(normal: Vec3, _: Vec3, roughness: f64, r: std.Random) Vec3 {
    const a = roughness * roughness;
    const xi1 = r.float(f64);
    const xi2 = r.float(f64);

    const cos_theta = @sqrt((1.0 - xi1) / (1.0 + (a * a - 1.0) * xi1));
    const sin_theta = @sqrt(1.0 - cos_theta * cos_theta);
    const phi = 2.0 * std.math.pi * xi2;

    const local = Vec3.init(sin_theta * @cos(phi), sin_theta * @sin(phi), cos_theta);

    const helper = if (@abs(normal.x) < 0.9) Vec3.right else Vec3.up;
    const tangent = normal.cross(helper).normalize();
    const bitangent = normal.cross(tangent);

    return tangent.scale(local.x).add(bitangent.scale(local.y)).add(normal.scale(local.z)).normalize();
}

fn randomHemisphere(normal: Vec3, r: std.Random) Vec3 {
    const z = r.float(f64);
    const phi = 2.0 * std.math.pi * r.float(f64);
    const sin_theta = @sqrt(1.0 - z * z);

    const local = Vec3.init(sin_theta * @cos(phi), sin_theta * @sin(phi), z);

    const helper = if (@abs(normal.x) < 0.9) Vec3.right else Vec3.up;
    const tangent = normal.cross(helper).normalize();
    const bitangent = normal.cross(tangent);

    return tangent.scale(local.x).add(bitangent.scale(local.y)).add(normal.scale(local.z)).normalize();
}

// ACES filmic tonemapping (Narkowicz 2015)
fn acesTonemap(color: Vec3) Vec3 {
    const a = 2.51;
    const b = 0.03;
    const c = 2.43;
    const d = 0.59;
    const e = 0.14;
    return Vec3.init(
        acesChannel(color.x, a, b, c, d, e),
        acesChannel(color.y, a, b, c, d, e),
        acesChannel(color.z, a, b, c, d, e),
    );
}

fn acesChannel(x: f64, a: f64, b: f64, c: f64, d: f64, e: f64) f64 {
    const numerator = x * (a * x + b);
    const denominator = x * (c * x + d) + e;
    return m.clamp(numerator / denominator, 0.0, 1.0);
}

fn gammaCorrect(color: Vec3) Vec3 {
    const g = 1.0 / 2.2;
    return Vec3.init(
        std.math.pow(f64, @max(color.x, 0.0), g),
        std.math.pow(f64, @max(color.y, 0.0), g),
        std.math.pow(f64, @max(color.z, 0.0), g),
    );
}

// post-process bloom (applied to final image buffer)
pub fn applyBloom(pixels: []Vec3, width: u32, height: u32, intensity: f64, threshold: f64) void {
    const w = @as(usize, width);
    const h = @as(usize, height);
    const radius: usize = 5;

    var temp = std.heap.page_allocator.alloc(Vec3, w * h) catch return;
    defer std.heap.page_allocator.free(temp);

    // extract bright pixels
    for (0..w * h) |i| {
        const lum = pixels[i].x * 0.2126 + pixels[i].y * 0.7152 + pixels[i].z * 0.0722;
        if (lum > threshold) {
            temp[i] = pixels[i].scale(lum - threshold);
        } else {
            temp[i] = Vec3.zero;
        }
    }

    // horizontal blur
    var temp2 = std.heap.page_allocator.alloc(Vec3, w * h) catch return;
    defer std.heap.page_allocator.free(temp2);

    for (0..h) |y| {
        for (0..w) |x| {
            var sum = Vec3.zero;
            var weight: f64 = 0;
            const start = if (x >= radius) x - radius else 0;
            const end = @min(x + radius + 1, w);
            for (start..end) |kx| {
                const dx = @as(f64, @floatFromInt(if (kx > x) kx - x else x - kx));
                const g = @exp(-dx * dx / (@as(f64, @floatFromInt(radius)) * 0.5));
                sum = sum.add(temp[y * w + kx].scale(g));
                weight += g;
            }
            temp2[y * w + x] = sum.scale(1.0 / weight);
        }
    }

    // vertical blur
    for (0..h) |y| {
        for (0..w) |x| {
            var sum = Vec3.zero;
            var weight: f64 = 0;
            const start = if (y >= radius) y - radius else 0;
            const end = @min(y + radius + 1, h);
            for (start..end) |ky| {
                const dy = @as(f64, @floatFromInt(if (ky > y) ky - y else y - ky));
                const g = @exp(-dy * dy / (@as(f64, @floatFromInt(radius)) * 0.5));
                sum = sum.add(temp2[ky * w + x].scale(g));
                weight += g;
            }
            pixels[y * w + x] = pixels[y * w + x].add(sum.scale(intensity / weight));
        }
    }
}

const std = @import("std");
const Vec3 = @import("math.zig").Vec3;
const Camera = @import("camera.zig").Camera;
const fractals = @import("fractals.zig");
const render = @import("render.zig");
const png = @import("png.zig");
const Seed = @import("seed.zig").Seed;

const build_options = @import("build_options");
const has_gpu = build_options.has_vulkan;
const VulkanCompute = if (has_gpu) @import("vulkan_compute.zig").VulkanCompute else void;

const Args = struct {
    fractal_type: fractals.FractalType = .mandelbulb,
    width: u32 = 1920,
    height: u32 = 1080,
    samples: u32 = 64,
    seed: ?Seed = null,
    output: []const u8 = "output.png",
    help: bool = false,
    force_cpu: bool = false,
};

pub fn main() !void {
    var stdout_buf: [4096]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buf);
    const stdout = &stdout_writer.interface;

    const args = parseArgs() catch |err| {
        try stdout.print("error: {s}\n", .{@errorName(err)});
        try stdout.flush();
        std.process.exit(1);
    };

    if (args.help) {
        try stdout.print(
            \\schism - spectral fractal path tracer
            \\
            \\usage: schism [options]
            \\
            \\options:
            \\  --fractal <type>   mandelbulb, menger, sierpinski, julia, kleinian, ifs
            \\  --seed <hex>       deterministic seed (random if omitted)
            \\  --width <n>        image width (default: 1920)
            \\  --height <n>       image height (default: 1080)
            \\  --samples <n>      samples per pixel (default: 64)
            \\  -o <path>          output file (default: output.png)
            \\  -h, --help         show this help
            \\
        , .{});
        try stdout.flush();
        return;
    }

    const seed = args.seed orelse Seed.random();

    var hex_buf: [16]u8 = undefined;
    const hex = seed.toShortHex(&hex_buf);
    try stdout.print("seed: {s}\n", .{hex});
    try stdout.print("fractal: {s}\n", .{@tagName(args.fractal_type)});
    try stdout.print("resolution: {d}x{d}\n", .{ args.width, args.height });
    try stdout.print("samples: {d}\n", .{args.samples});
    try stdout.flush();

    const cam_config = cameraForFractal(args.fractal_type, args.width, args.height);
    const frac_params = fractalParams(args.fractal_type);

    const config = render.RenderConfig{
        .width = args.width,
        .height = args.height,
        .samples_per_pixel = args.samples,
        .fractal = frac_params,
        .material = materialForFractal(args.fractal_type),
        .camera = cam_config,
        .fog_density = 0.02,
        .fog_color = Vec3.init(0.0, 0.0, 0.0),
        .exposure = 1.8,
    };

    const pixels = if (has_gpu and !args.force_cpu) blk: {
        break :blk renderGPU(args, config, seed, stdout) catch |err| {
            try stdout.print("gpu failed ({s}), falling back to cpu\n", .{@errorName(err)});
            try stdout.flush();
            break :blk try renderCPU(args, config, seed, stdout);
        };
    } else try renderCPU(args, config, seed, stdout);
    defer std.heap.page_allocator.free(pixels);

    render.applyBloom(pixels, args.width, args.height, 0.15, 0.8);

    try png.write(pixels, args.width, args.height, args.output);
    try stdout.print("wrote {s}\n", .{args.output});
    try stdout.flush();
}

fn cameraForFractal(fractal_type: fractals.FractalType, width: u32, height: u32) Camera {
    const aspect = @as(f64, @floatFromInt(width)) / @as(f64, @floatFromInt(height));
    return switch (fractal_type) {
        .mandelbulb => Camera.init(.{
            .position = Vec3.init(1.2, 0.8, 1.8),
            .look_at = Vec3.init(0.0, -0.1, 0.0),
            .fov_degrees = 45.0,
            .aspect = aspect,
            .aperture = 0.01,
            .focus_dist = 2.2,
        }),
        .menger => Camera.init(.{
            .position = Vec3.init(1.5, 1.0, 2.0),
            .look_at = Vec3.init(0.0, 0.0, 0.0),
            .fov_degrees = 50.0,
            .aspect = aspect,
            .aperture = 0.008,
            .focus_dist = 2.5,
        }),
        .sierpinski => Camera.init(.{
            .position = Vec3.init(1.0, 1.2, 1.8),
            .look_at = Vec3.init(0.0, 0.0, 0.0),
            .fov_degrees = 50.0,
            .aspect = aspect,
            .aperture = 0.01,
        }),
        .julia => Camera.init(.{
            .position = Vec3.init(0.8, 0.6, 1.5),
            .look_at = Vec3.init(0.0, 0.0, 0.0),
            .fov_degrees = 50.0,
            .aspect = aspect,
            .aperture = 0.01,
        }),
        .kleinian => Camera.init(.{
            .position = Vec3.init(0.3, 0.2, 0.8),
            .look_at = Vec3.init(0.0, 0.0, 0.0),
            .fov_degrees = 60.0,
            .aspect = aspect,
            .aperture = 0.005,
        }),
        .ifs => Camera.init(.{
            .position = Vec3.init(1.2, 0.9, 1.6),
            .look_at = Vec3.init(0.0, 0.0, 0.0),
            .fov_degrees = 50.0,
            .aspect = aspect,
            .aperture = 0.01,
        }),
    };
}

fn fractalParams(fractal_type: fractals.FractalType) fractals.FractalParams {
    return switch (fractal_type) {
        .mandelbulb => .{
            .fractal_type = .mandelbulb,
            .power = 8.0,
            .max_iterations = 50,
            .bailout = 4.0,
        },
        .menger => .{
            .fractal_type = .menger,
            .scale = 3.0,
            .max_iterations = 12,
            .offset = Vec3.init(1.0, 1.0, 1.0),
        },
        .sierpinski => .{
            .fractal_type = .sierpinski,
            .scale = 2.0,
            .max_iterations = 15,
            .offset = Vec3.init(1.0, 1.0, 1.0),
        },
        .julia => .{
            .fractal_type = .julia,
            .max_iterations = 40,
            .bailout = 4.0,
            .julia_c = Vec3.init(-0.2, 0.6, -0.2),
        },
        .kleinian => .{
            .fractal_type = .kleinian,
            .max_iterations = 40,
            .offset = Vec3.init(2.0, 0.5, 2.0),
        },
        .ifs => .{
            .fractal_type = .ifs,
            .scale = 2.0,
            .max_iterations = 15,
            .offset = Vec3.init(1.0, 1.0, 1.0),
        },
    };
}

fn materialForFractal(fractal_type: fractals.FractalType) render.Material {
    return switch (fractal_type) {
        .mandelbulb => .{ .roughness = 0.35, .metallic = 0.0, .ior = 1.5 },
        .menger => .{ .roughness = 0.25, .metallic = 0.1, .ior = 1.6 },
        .sierpinski => .{ .roughness = 0.3, .metallic = 0.0, .ior = 1.5 },
        .julia => .{ .roughness = 0.4, .metallic = 0.0, .ior = 1.45 },
        .kleinian => .{ .roughness = 0.2, .metallic = 0.0, .ior = 1.6, .emission = 0.5 },
        .ifs => .{ .roughness = 0.3, .metallic = 0.05, .ior = 1.5 },
    };
}

fn renderGPU(args: Args, config: render.RenderConfig, seed: Seed, stdout: *std.Io.Writer) ![]Vec3 {
    if (!has_gpu) return error.VulkanNotAvailable;

    try stdout.print("backend: gpu (vulkan)\n", .{});
    try stdout.flush();

    var gpu = try VulkanCompute.init(args.width, args.height);
    defer gpu.deinit();

    try gpu.dispatch(config, @truncate(seed.value));
    return try gpu.readPixels(args.width, args.height);
}

fn renderCPU(args: Args, config: render.RenderConfig, seed: Seed, stdout: *std.Io.Writer) ![]Vec3 {
    const num_threads = std.Thread.getCpuCount() catch 4;
    try stdout.print("backend: cpu ({d} threads)\n", .{num_threads});
    try stdout.flush();

    const pixels = try std.heap.page_allocator.alloc(Vec3, @as(usize, args.width) * args.height);

    var rows_done = std.atomic.Value(u32).init(0);
    const threads = try std.heap.page_allocator.alloc(std.Thread, num_threads);
    defer std.heap.page_allocator.free(threads);

    for (0..num_threads) |tid| {
        threads[tid] = try std.Thread.spawn(.{}, renderWorker, .{
            pixels,
            config,
            seed.value,
            @as(u32, @intCast(tid)),
            @as(u32, @intCast(num_threads)),
            &rows_done,
        });
    }

    while (true) {
        const done = rows_done.load(.acquire);
        const pct = @as(f64, @floatFromInt(done)) / @as(f64, @floatFromInt(args.height)) * 100.0;
        try stdout.print("\r{d:.0}%", .{pct});
        try stdout.flush();
        if (done >= args.height) break;
        std.Thread.sleep(100 * std.time.ns_per_ms);
    }

    for (threads) |t| t.join();
    try stdout.print("\r100%\n", .{});
    try stdout.flush();

    return pixels;
}

fn renderWorker(
    pixels: []Vec3,
    config: render.RenderConfig,
    base_seed: u64,
    tid: u32,
    num_threads: u32,
    rows_done: *std.atomic.Value(u32),
) void {
    var y = tid;
    while (y < config.height) : (y += num_threads) {
        // per-row RNG seeded from base seed + row index for determinism
        var rng = std.Random.Pcg.init(base_seed +% @as(u64, y) * 2654435761);
        for (0..config.width) |x| {
            pixels[y * config.width + x] = render.tracePixel(
                @intCast(x),
                @intCast(y),
                config,
                &rng,
            );
        }
        _ = rows_done.fetchAdd(1, .release);
    }
}

fn parseArgs() !Args {
    var args = Args{};
    var iter = std.process.args();
    _ = iter.next();

    while (iter.next()) |arg| {
        if (std.mem.eql(u8, arg, "--fractal")) {
            const val = iter.next() orelse return error.MissingArgument;
            args.fractal_type = std.meta.stringToEnum(fractals.FractalType, val) orelse return error.UnknownFractal;
        } else if (std.mem.eql(u8, arg, "--seed")) {
            const val = iter.next() orelse return error.MissingArgument;
            args.seed = try Seed.fromHex(val);
        } else if (std.mem.eql(u8, arg, "--width")) {
            const val = iter.next() orelse return error.MissingArgument;
            args.width = try std.fmt.parseInt(u32, val, 10);
        } else if (std.mem.eql(u8, arg, "--height")) {
            const val = iter.next() orelse return error.MissingArgument;
            args.height = try std.fmt.parseInt(u32, val, 10);
        } else if (std.mem.eql(u8, arg, "--samples") or std.mem.eql(u8, arg, "-s")) {
            const val = iter.next() orelse return error.MissingArgument;
            args.samples = try std.fmt.parseInt(u32, val, 10);
        } else if (std.mem.eql(u8, arg, "-o") or std.mem.eql(u8, arg, "--output")) {
            args.output = iter.next() orelse return error.MissingArgument;
        } else if (std.mem.eql(u8, arg, "--cpu")) {
            args.force_cpu = true;
        } else if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            args.help = true;
        }
    }
    return args;
}

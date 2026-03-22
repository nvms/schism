const std = @import("std");
const math = @import("math.zig");

pub const wavelength_min: f64 = 380.0;
pub const wavelength_max: f64 = 780.0;
pub const wavelength_range: f64 = wavelength_max - wavelength_min;

pub const num_hero_wavelengths = 4;

pub const SpectralSample = struct {
    wavelengths: [num_hero_wavelengths]f64,
    values: [num_hero_wavelengths]f64,

    pub fn zero() SpectralSample {
        return .{
            .wavelengths = [_]f64{0} ** num_hero_wavelengths,
            .values = [_]f64{0} ** num_hero_wavelengths,
        };
    }

    pub fn uniform(hero: f64, val: f64) SpectralSample {
        var s: SpectralSample = undefined;
        const step = wavelength_range / @as(f64, num_hero_wavelengths);
        for (0..num_hero_wavelengths) |i| {
            var wl = hero + @as(f64, @floatFromInt(i)) * step;
            if (wl > wavelength_max) wl -= wavelength_range;
            s.wavelengths[i] = wl;
            s.values[i] = val;
        }
        return s;
    }

    pub fn scale(self: SpectralSample, s: f64) SpectralSample {
        var result = self;
        for (0..num_hero_wavelengths) |i| {
            result.values[i] *= s;
        }
        return result;
    }

    pub fn multiply(a: SpectralSample, b: SpectralSample) SpectralSample {
        var result = a;
        for (0..num_hero_wavelengths) |i| {
            result.values[i] *= b.values[i];
        }
        return result;
    }

    pub fn add(a: SpectralSample, b: SpectralSample) SpectralSample {
        var result = a;
        for (0..num_hero_wavelengths) |i| {
            result.values[i] += b.values[i];
        }
        return result;
    }

    pub fn toXYZ(self: SpectralSample) [3]f64 {
        var xyz = [3]f64{ 0, 0, 0 };
        for (0..num_hero_wavelengths) |i| {
            const cmf = cieXYZ(self.wavelengths[i]);
            xyz[0] += self.values[i] * cmf[0];
            xyz[1] += self.values[i] * cmf[1];
            xyz[2] += self.values[i] * cmf[2];
        }
        const norm = wavelength_range / @as(f64, num_hero_wavelengths);
        xyz[0] *= norm;
        xyz[1] *= norm;
        xyz[2] *= norm;
        return xyz;
    }
};

// CIE 1931 2-degree observer, piecewise gaussian approximation (Wyman et al. 2013)
pub fn cieXYZ(wavelength: f64) [3]f64 {
    const wl = wavelength;
    return .{
        cieX(wl),
        cieY(wl),
        cieZ(wl),
    };
}

fn gaussian(x: f64, mu: f64, sigma1: f64, sigma2: f64) f64 {
    const t = (x - mu) / (if (x < mu) sigma1 else sigma2);
    return @exp(-0.5 * t * t);
}

fn cieX(wl: f64) f64 {
    return 1.056 * gaussian(wl, 599.8, 37.9, 31.0) +
        0.362 * gaussian(wl, 442.0, 16.0, 26.7) -
        0.065 * gaussian(wl, 501.1, 20.4, 26.2);
}

fn cieY(wl: f64) f64 {
    return 0.821 * gaussian(wl, 568.8, 46.9, 40.5) +
        0.286 * gaussian(wl, 530.9, 16.3, 31.1);
}

fn cieZ(wl: f64) f64 {
    return 1.217 * gaussian(wl, 437.0, 11.8, 36.0) +
        0.681 * gaussian(wl, 459.0, 26.0, 13.8);
}

// sRGB D65 matrix
pub fn xyzToSRGB(xyz: [3]f64) math.Vec3 {
    return .{
        .x = 3.2406 * xyz[0] - 1.5372 * xyz[1] - 0.4986 * xyz[2],
        .y = -0.9689 * xyz[0] + 1.8758 * xyz[1] + 0.0415 * xyz[2],
        .z = 0.0557 * xyz[0] - 0.2040 * xyz[1] + 1.0570 * xyz[2],
    };
}

pub fn srgbGamma(c: f64) f64 {
    if (c <= 0.0031308) return 12.92 * c;
    return 1.055 * std.math.pow(f64, c, 1.0 / 2.4) - 0.055;
}

pub fn spectralToRGB(sample: SpectralSample) math.Vec3 {
    const xyz = sample.toXYZ();
    const linear = xyzToSRGB(xyz);
    return .{
        .x = math.clamp(srgbGamma(linear.x), 0, 1),
        .y = math.clamp(srgbGamma(linear.y), 0, 1),
        .z = math.clamp(srgbGamma(linear.z), 0, 1),
    };
}

// Cauchy dispersion model: n(lambda) = B + C/lambda^2
pub fn cauchyIOR(wavelength_nm: f64, b: f64, c: f64) f64 {
    const wl_um = wavelength_nm / 1000.0;
    return b + c / (wl_um * wl_um);
}

// Sellmeier dispersion (common form with 3 terms)
pub fn sellmeierIOR(wavelength_nm: f64, b: [3]f64, c: [3]f64) f64 {
    const wl_um = wavelength_nm / 1000.0;
    const l2 = wl_um * wl_um;
    var n2: f64 = 1.0;
    for (0..3) |i| {
        n2 += (b[i] * l2) / (l2 - c[i]);
    }
    return @sqrt(@max(n2, 1.0));
}

test "cie xyz gives non-negative Y for visible range" {
    var wl: f64 = wavelength_min;
    while (wl <= wavelength_max) : (wl += 5.0) {
        const xyz = cieXYZ(wl);
        try std.testing.expect(xyz[1] >= -0.01);
    }
}

test "cie xyz peaks around expected wavelengths" {
    const green_y = cieY(555.0);
    const red_y = cieY(700.0);
    try std.testing.expect(green_y > red_y);
}

test "spectral sample hero wavelength spacing" {
    const s = SpectralSample.uniform(500.0, 1.0);
    try std.testing.expectApproxEqAbs(s.wavelengths[0], 500.0, 1e-10);
    const step = wavelength_range / @as(f64, num_hero_wavelengths);
    try std.testing.expectApproxEqAbs(s.wavelengths[1], 500.0 + step, 1e-10);
}

test "spectral sample wraps around visible range" {
    const s = SpectralSample.uniform(750.0, 1.0);
    for (s.wavelengths) |wl| {
        try std.testing.expect(wl >= wavelength_min);
        try std.testing.expect(wl <= wavelength_max);
    }
}

test "cauchy dispersion increases toward blue" {
    const n_blue = cauchyIOR(450.0, 1.5, 0.004);
    const n_red = cauchyIOR(650.0, 1.5, 0.004);
    try std.testing.expect(n_blue > n_red);
}

test "sellmeier bk7 glass" {
    const bk7_b = [3]f64{ 1.03961212, 0.231792344, 1.01046945 };
    const bk7_c = [3]f64{ 0.00600069867, 0.0200179144, 103.560653 };
    const n = sellmeierIOR(589.3, bk7_b, bk7_c);
    try std.testing.expectApproxEqAbs(n, 1.5168, 0.001);
}

test "spectral to rgb produces visible color for D65-ish" {
    const s = SpectralSample.uniform(550.0, 0.01);
    const rgb = spectralToRGB(s);
    try std.testing.expect(rgb.x >= 0 and rgb.x <= 1);
    try std.testing.expect(rgb.y >= 0 and rgb.y <= 1);
    try std.testing.expect(rgb.z >= 0 and rgb.z <= 1);
}

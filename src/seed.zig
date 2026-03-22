const std = @import("std");

pub const Seed = struct {
    value: u64,

    pub fn fromHex(hex: []const u8) !Seed {
        if (hex.len == 0 or hex.len > 16) return error.InvalidSeed;
        var value: u64 = 0;
        for (hex) |c| {
            const digit: u64 = switch (c) {
                '0'...'9' => c - '0',
                'a'...'f' => c - 'a' + 10,
                'A'...'F' => c - 'A' + 10,
                else => return error.InvalidSeed,
            };
            value = (value << 4) | digit;
        }
        return .{ .value = value };
    }

    pub fn random() Seed {
        var buf: [8]u8 = undefined;
        std.crypto.random.bytes(&buf);
        return .{ .value = std.mem.readInt(u64, &buf, .little) };
    }

    pub fn toHex(self: Seed) [16]u8 {
        var buf: [16]u8 = undefined;
        _ = std.fmt.bufPrint(&buf, "{x:0>16}", .{self.value}) catch unreachable;
        return buf;
    }

    // trimmed hex with no leading zeros
    pub fn toShortHex(self: Seed, buf: []u8) []const u8 {
        return std.fmt.bufPrint(buf, "{x}", .{self.value}) catch buf[0..0];
    }

    pub fn rng(self: Seed) std.Random.Pcg {
        return std.Random.Pcg.init(self.value);
    }
};

test "seed from hex roundtrip" {
    const s = try Seed.fromHex("a4f29c");
    try std.testing.expectEqual(s.value, 0xa4f29c);
}

test "seed from hex uppercase" {
    const s = try Seed.fromHex("A4F29C");
    try std.testing.expectEqual(s.value, 0xa4f29c);
}

test "seed invalid hex" {
    try std.testing.expectError(error.InvalidSeed, Seed.fromHex("xyz"));
    try std.testing.expectError(error.InvalidSeed, Seed.fromHex(""));
    try std.testing.expectError(error.InvalidSeed, Seed.fromHex("12345678901234567"));
}

test "seed rng is deterministic" {
    const s = Seed{ .value = 42 };
    var r1 = s.rng();
    var r2 = s.rng();
    const a = r1.random().int(u64);
    const b = r2.random().int(u64);
    try std.testing.expectEqual(a, b);
}

test "seed to short hex" {
    const s = Seed{ .value = 0xa4f29c };
    var buf: [16]u8 = undefined;
    const hex = s.toShortHex(&buf);
    try std.testing.expectEqualStrings("a4f29c", hex);
}

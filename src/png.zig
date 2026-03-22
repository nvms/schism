const std = @import("std");
const m = @import("math.zig");
const Vec3 = m.Vec3;

pub fn write(
    pixels: []const Vec3,
    width: u32,
    height: u32,
    path: []const u8,
) !void {
    const file = try std.fs.cwd().createFile(path, .{});
    defer file.close();
    var buf: [8192]u8 = undefined;
    var writer = file.writer(&buf);
    try writePNG(pixels, width, height, &writer.interface);
    try writer.interface.flush();
}

fn writePNG(
    pixels: []const Vec3,
    width: u32,
    height: u32,
    writer: *std.Io.Writer,
) !void {
    try writer.writeAll(&[_]u8{ 0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A });

    var ihdr: [13]u8 = undefined;
    std.mem.writeInt(u32, ihdr[0..4], width, .big);
    std.mem.writeInt(u32, ihdr[4..8], height, .big);
    ihdr[8] = 8;
    ihdr[9] = 2;
    ihdr[10] = 0;
    ihdr[11] = 0;
    ihdr[12] = 0;
    try writeChunk(writer, "IHDR", &ihdr);

    // build raw scanlines (filter byte + RGB per row)
    const row_bytes = width * 3 + 1;
    const raw_len = row_bytes * height;
    var raw = try std.heap.page_allocator.alloc(u8, raw_len);
    defer std.heap.page_allocator.free(raw);

    for (0..height) |y| {
        raw[y * row_bytes] = 0;
        for (0..width) |x| {
            const px = pixels[y * width + x];
            const offset = y * row_bytes + 1 + x * 3;
            raw[offset + 0] = floatToByte(px.x);
            raw[offset + 1] = floatToByte(px.y);
            raw[offset + 2] = floatToByte(px.z);
        }
    }

    // zlib stored (uncompressed) wrapping
    const idat = try zlibStore(raw);
    defer std.heap.page_allocator.free(idat);
    try writeChunk(writer, "IDAT", idat);

    try writeChunk(writer, "IEND", &[_]u8{});
}

fn zlibStore(data: []const u8) ![]u8 {
    // zlib header (2 bytes) + deflate stored blocks + adler32 (4 bytes)
    // each stored block: 5 byte header + up to 65535 bytes
    const max_block = 65535;
    const num_blocks = (data.len + max_block - 1) / max_block;
    const total = 2 + (num_blocks * 5) + data.len + 4;

    var out = try std.heap.page_allocator.alloc(u8, total);
    var pos: usize = 0;

    // zlib header: CMF=0x78 (deflate, 32k window), FLG=0x01 (check bits)
    out[pos] = 0x78;
    pos += 1;
    out[pos] = 0x01;
    pos += 1;

    var remaining = data.len;
    var offset: usize = 0;
    while (remaining > 0) {
        const block_size = @min(remaining, max_block);
        const is_last: u8 = if (remaining <= max_block) 1 else 0;

        out[pos] = is_last;
        pos += 1;
        const len16: u16 = @intCast(block_size);
        std.mem.writeInt(u16, out[pos..][0..2], len16, .little);
        pos += 2;
        std.mem.writeInt(u16, out[pos..][0..2], ~len16, .little);
        pos += 2;

        @memcpy(out[pos .. pos + block_size], data[offset .. offset + block_size]);
        pos += block_size;
        offset += block_size;
        remaining -= block_size;
    }

    // adler32
    const adler = adler32(data);
    std.mem.writeInt(u32, out[pos..][0..4], adler, .big);
    pos += 4;

    return out[0..pos];
}

fn adler32(data: []const u8) u32 {
    var a: u32 = 1;
    var b: u32 = 0;
    for (data) |byte| {
        a = (a + byte) % 65521;
        b = (b + a) % 65521;
    }
    return (b << 16) | a;
}

fn writeChunk(writer: *std.Io.Writer, chunk_type: *const [4]u8, data: []const u8) !void {
    const len: u32 = @intCast(data.len);
    var len_buf: [4]u8 = undefined;
    std.mem.writeInt(u32, &len_buf, len, .big);
    try writer.writeAll(&len_buf);
    try writer.writeAll(chunk_type);
    try writer.writeAll(data);

    var crc = std.hash.Crc32.init();
    crc.update(chunk_type);
    crc.update(data);
    var crc_buf: [4]u8 = undefined;
    std.mem.writeInt(u32, &crc_buf, crc.final(), .big);
    try writer.writeAll(&crc_buf);
}

fn floatToByte(v: f64) u8 {
    const clamped = m.clamp(v, 0.0, 1.0);
    return @intFromFloat(clamped * 255.0 + 0.5);
}

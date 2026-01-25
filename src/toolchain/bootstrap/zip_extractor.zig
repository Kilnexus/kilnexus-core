const std = @import("std");

pub fn extractZipFile(
    allocator: std.mem.Allocator,
    zip_path: []const u8,
    dest_dir: []const u8,
    strip_components: usize,
) !void {
    var archive = try std.fs.cwd().openFile(zip_path, .{});
    defer archive.close();

    const file_size = try archive.getEndPos();
    const tail_size: u64 = @min(file_size, 0xFFFF + 22);

    var tail = try allocator.alloc(u8, @intCast(tail_size));
    defer allocator.free(tail);

    _ = try archive.preadAll(tail, file_size - tail_size);

    const eocd_offset = findEocd(tail) orelse return error.ZipCorrupt;
    const eocd = tail[eocd_offset..];

    const total_entries = readU16(eocd, 10);
    const central_dir_size = readU32(eocd, 12);
    const central_dir_offset = readU32(eocd, 16);

    var central_dir = try allocator.alloc(u8, @intCast(central_dir_size));
    defer allocator.free(central_dir);
    _ = try archive.preadAll(central_dir, central_dir_offset);

    var out_dir = try std.fs.cwd().openDir(dest_dir, .{});
    defer out_dir.close();

    var idx: usize = 0;
    var entries_read: u16 = 0;
    while (idx + 46 <= central_dir.len and entries_read < total_entries) : (entries_read += 1) {
        const sig = readU32(central_dir, idx);
        if (sig != 0x02014b50) return error.ZipCorrupt;

        const compression_method = readU16(central_dir, idx + 10);
        const compressed_size = readU32(central_dir, idx + 20);
        const uncompressed_size = readU32(central_dir, idx + 24);
        const name_len = readU16(central_dir, idx + 28);
        const extra_len = readU16(central_dir, idx + 30);
        const comment_len = readU16(central_dir, idx + 32);
        const local_header_offset = readU32(central_dir, idx + 42);

        const name_start = idx + 46;
        const name_end = name_start + name_len;
        if (name_end > central_dir.len) return error.ZipCorrupt;
        const name = central_dir[name_start..name_end];

        idx = name_end + extra_len + comment_len;

        const stripped = stripLeadingComponents(name, strip_components) orelse continue;
        if (stripped.len == 0) continue;
        if (!isSafePath(stripped)) return error.ZipUnsafePath;

        if (stripped[stripped.len - 1] == '/') {
            const normalized_dir = try normalizePathAlloc(allocator, stripped);
            defer allocator.free(normalized_dir);
            try out_dir.makePath(normalized_dir);
            continue;
        }

        const local_header = try readLocalHeader(archive, local_header_offset);
        const data_offset = local_header_offset + 30 + local_header.name_len + local_header.extra_len;

        try extractZipEntry(
            allocator,
            archive,
            out_dir,
            stripped,
            data_offset,
            compressed_size,
            uncompressed_size,
            compression_method,
        );
    }
}

fn extractZipEntry(
    allocator: std.mem.Allocator,
    archive: std.fs.File,
    out_dir: std.fs.Dir,
    rel_path: []const u8,
    data_offset: u64,
    compressed_size: u32,
    uncompressed_size: u32,
    compression_method: u16,
) !void {
    const normalized = try normalizePathAlloc(allocator, rel_path);
    defer allocator.free(normalized);

    if (std.fs.path.dirname(normalized)) |dir_name| {
        try out_dir.makePath(dir_name);
    }

    var out_file = try out_dir.createFile(normalized, .{ .truncate = true });
    defer out_file.close();

    var file_buffer: [32 * 1024]u8 = undefined;
    var writer = out_file.writer(&file_buffer);

    const compressed = try allocator.alloc(u8, @intCast(compressed_size));
    defer allocator.free(compressed);
    _ = try archive.preadAll(compressed, data_offset);

    switch (compression_method) {
        0 => {
            _ = uncompressed_size;
            try writer.interface.writeAll(compressed);
        },
        8 => {
            var in_reader: std.Io.Reader = .fixed(compressed);
            var window: [std.compress.flate.max_window_len]u8 = undefined;
            var decomp = std.compress.flate.Decompress.init(&in_reader, .raw, &window);
            _ = try decomp.reader.streamRemaining(&writer.interface);
        },
        else => return error.ZipUnsupportedCompression,
    }

    try writer.interface.flush();
}

const LocalHeader = struct {
    name_len: u16,
    extra_len: u16,
};

fn readLocalHeader(file: std.fs.File, offset: u64) !LocalHeader {
    var buffer: [30]u8 = undefined;
    _ = try file.preadAll(&buffer, offset);

    if (readU32(&buffer, 0) != 0x04034b50) return error.ZipCorrupt;

    return .{
        .name_len = readU16(&buffer, 26),
        .extra_len = readU16(&buffer, 28),
    };
}

fn findEocd(buf: []const u8) ?usize {
    if (buf.len < 22) return null;
    var i: usize = buf.len - 22;
    while (true) : (i -= 1) {
        if (readU32(buf, i) == 0x06054b50) return i;
        if (i == 0) break;
    }
    return null;
}

fn stripLeadingComponents(path: []const u8, count: usize) ?[]const u8 {
    if (count == 0) return path;
    var remaining = path;
    var left: usize = count;
    while (left > 0) : (left -= 1) {
        const first_slash = std.mem.indexOfScalar(u8, remaining, '/');
        const first_backslash = std.mem.indexOfScalar(u8, remaining, '\\');
        const cut = if (first_slash) |s| blk: {
            if (first_backslash) |b| break :blk @min(s, b);
            break :blk s;
        } else first_backslash orelse return null;
        if (cut + 1 >= remaining.len) return "";
        remaining = remaining[cut + 1 ..];
    }
    return remaining;
}

fn isSafePath(path: []const u8) bool {
    if (std.fs.path.isAbsolute(path)) return false;

    var it = std.mem.splitAny(u8, path, "/\\\\");
    while (it.next()) |part| {
        if (std.mem.eql(u8, part, "..")) return false;
    }
    return true;
}

fn normalizePathAlloc(allocator: std.mem.Allocator, path: []const u8) ![]const u8 {
    const out = try allocator.dupe(u8, path);
    if (std.fs.path.sep != '/') {
        std.mem.replaceScalar(u8, out, '/', std.fs.path.sep);
    }
    return out;
}

fn readU16(buf: []const u8, offset: usize) u16 {
    const ptr: *const [2]u8 = @ptrCast(buf[offset..].ptr);
    return std.mem.readInt(u16, ptr, .little);
}

fn readU32(buf: []const u8, offset: usize) u32 {
    const ptr: *const [4]u8 = @ptrCast(buf[offset..].ptr);
    return std.mem.readInt(u32, ptr, .little);
}

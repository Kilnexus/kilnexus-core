const std = @import("std");
const manager = @import("manager.zig");
const minisign = @import("minisign.zig");

pub fn bootstrapZig(allocator: std.mem.Allocator, cwd: std.fs.Dir, version: []const u8) !void {
    const zig_path = manager.zigRelPathForVersion(allocator, version) catch null;
    if (zig_path) |path| {
        defer allocator.free(path);
        if (existsRel(cwd, path)) return;
    }

    try manager.ensureToolchainDirFor(cwd, .Zig);
    const install_dir = try manager.zigInstallDirRelForVersion(allocator, version);
    defer allocator.free(install_dir);
    try cwd.makePath(install_dir);

    const archive_name = try manager.zigArchiveNameForVersion(allocator, version);
    defer allocator.free(archive_name);
    const archive_path = try std.fs.path.join(allocator, &[_][]const u8{ install_dir, archive_name });
    defer allocator.free(archive_path);

    const archive_url = try manager.zigDownloadUrlForVersion(allocator, version);
    defer allocator.free(archive_url);

    const sig_name = try manager.zigSignatureNameForVersion(allocator, version);
    defer allocator.free(sig_name);
    const sig_path = try std.fs.path.join(allocator, &[_][]const u8{ install_dir, sig_name });
    defer allocator.free(sig_path);

    const sig_url = try manager.zigSignatureUrlForVersion(allocator, version);
    defer allocator.free(sig_url);

    try downloadFile(allocator, archive_url, archive_path);
    try downloadFile(allocator, sig_url, sig_path);
    try minisign.verifyFileSignature(allocator, archive_path, sig_path);
    try extractArchive(allocator, archive_path, install_dir, 1);
}

pub fn bootstrapRust(allocator: std.mem.Allocator, cwd: std.fs.Dir, version: []const u8) !void {
    const rustc_path = manager.rustcRelPathForVersion(allocator, version) catch null;
    if (rustc_path) |path| {
        defer allocator.free(path);
        if (existsRel(cwd, path)) return;
    }

    try manager.ensureToolchainDirFor(cwd, .Rust);
    const install_dir = try manager.rustInstallDirRelForVersion(allocator, version);
    defer allocator.free(install_dir);
    try cwd.makePath(install_dir);

    const archive_name = try manager.rustArchiveNameForVersion(allocator, version);
    defer allocator.free(archive_name);
    const archive_path = try std.fs.path.join(allocator, &[_][]const u8{ install_dir, archive_name });
    defer allocator.free(archive_path);

    const archive_url = try manager.rustDownloadUrlForVersion(allocator, version);
    defer allocator.free(archive_url);

    try downloadFile(allocator, archive_url, archive_path);
    try extractArchive(allocator, archive_path, install_dir, 1);
}

pub fn bootstrapGo(allocator: std.mem.Allocator, cwd: std.fs.Dir, version: []const u8) !void {
    const go_path = manager.goRelPathForVersion(allocator, version) catch null;
    if (go_path) |path| {
        defer allocator.free(path);
        if (existsRel(cwd, path)) return;
    }

    try manager.ensureToolchainDirFor(cwd, .Go);
    const install_dir = try manager.goInstallDirRelForVersion(allocator, version);
    defer allocator.free(install_dir);
    try cwd.makePath(install_dir);

    const archive_name = try manager.goArchiveNameForVersion(allocator, version);
    defer allocator.free(archive_name);
    const archive_path = try std.fs.path.join(allocator, &[_][]const u8{ install_dir, archive_name });
    defer allocator.free(archive_path);

    const archive_url = try manager.goDownloadUrlForVersion(allocator, version);
    defer allocator.free(archive_url);

    try downloadFile(allocator, archive_url, archive_path);
    try extractArchive(allocator, archive_path, install_dir, 0);
}

fn downloadFile(allocator: std.mem.Allocator, url: []const u8, output_path: []const u8) !void {
    var client = std.http.Client{ .allocator = allocator };
    defer client.deinit();

    var file = try std.fs.cwd().createFile(output_path, .{ .truncate = true });
    defer file.close();

    var writer_buffer: [32 * 1024]u8 = undefined;
    var writer = file.writer(&writer_buffer);

    const result = try client.fetch(.{
        .location = .{ .url = url },
        .response_writer = &writer.interface,
    });

    try writer.interface.flush();
    if (result.status.class() != .success) return error.HttpFailed;
}

fn extractArchive(allocator: std.mem.Allocator, archive_path: []const u8, install_dir: []const u8, strip_components: u8) !void {
    if (std.mem.endsWith(u8, archive_path, ".zip")) {
        try extractZip(allocator, archive_path, install_dir, strip_components);
        return;
    }
    if (std.mem.endsWith(u8, archive_path, ".tar.xz")) {
        try extractTarXz(allocator, archive_path, install_dir, strip_components);
        return;
    }
    if (std.mem.endsWith(u8, archive_path, ".tar.gz")) {
        try extractTarGz(allocator, archive_path, install_dir, strip_components);
        return;
    }

    return error.UnsupportedArchive;
}

fn extractTarXz(allocator: std.mem.Allocator, archive_path: []const u8, install_dir: []const u8, strip_components: u8) !void {
    var archive = try std.fs.cwd().openFile(archive_path, .{});
    defer archive.close();

    var reader_buffer: [32 * 1024]u8 = undefined;
    var file_reader = archive.reader(&reader_buffer);
    const old_reader = file_reader.interface.adaptToOldInterface();

    var xz = try std.compress.xz.decompress(allocator, old_reader);
    defer xz.deinit();

    var xz_reader = xz.reader();
    var adapter_buffer: [32 * 1024]u8 = undefined;
    const adapter = xz_reader.adaptToNewApi(&adapter_buffer);
    var tar_reader = adapter.new_interface;

    var out_dir = try std.fs.cwd().openDir(install_dir, .{});
    defer out_dir.close();

    try std.tar.pipeToFileSystem(out_dir, &tar_reader, .{
        .strip_components = strip_components,
    });
}

fn extractTarGz(allocator: std.mem.Allocator, archive_path: []const u8, install_dir: []const u8, strip_components: u8) !void {
    _ = allocator;
    var archive = try std.fs.cwd().openFile(archive_path, .{});
    defer archive.close();

    var reader_buffer: [32 * 1024]u8 = undefined;
    const file_reader = archive.reader(&reader_buffer);
    var in_reader = file_reader.interface;
    var window: [std.compress.flate.max_window_len]u8 = undefined;
    const decomp = std.compress.flate.Decompress.init(&in_reader, .gzip, &window);
    var tar_reader = decomp.reader;

    var out_dir = try std.fs.cwd().openDir(install_dir, .{});
    defer out_dir.close();

    try std.tar.pipeToFileSystem(out_dir, &tar_reader, .{
        .strip_components = strip_components,
    });
}

fn extractZip(allocator: std.mem.Allocator, archive_path: []const u8, install_dir: []const u8, strip_components: u8) !void {
    var archive = try std.fs.cwd().openFile(archive_path, .{});
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

    var out_dir = try std.fs.cwd().openDir(install_dir, .{});
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

        try extractZipFile(
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

fn extractZipFile(
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

fn stripLeadingComponents(path: []const u8, count: u8) ?[]const u8 {
    if (count == 0) return path;
    var remaining = path;
    var left: u8 = count;
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

fn existsRel(cwd: std.fs.Dir, path: []const u8) bool {
    cwd.access(path, .{}) catch return false;
    return true;
}

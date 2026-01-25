const std = @import("std");

pub fn verifyNoSharedDeps(binary_path: []const u8) !void {
    var file = try std.fs.cwd().openFile(binary_path, .{});
    defer file.close();

    var header: [64]u8 = undefined;
    const read_len = file.preadAll(&header, 0) catch |err| switch (err) {
        error.EndOfStream => return error.UnsupportedBinary,
        else => return err,
    };
    if (read_len < 16) return error.UnsupportedBinary;

    if (!std.mem.eql(u8, header[0..4], "\x7fELF")) return error.UnsupportedBinary;

    const ei_class = header[4];
    const ei_data = header[5];
    if (ei_data != std.elf.ELFDATA2LSB) return error.UnsupportedEndianness;

    switch (ei_class) {
        std.elf.ELFCLASS32 => try verifyElf32(file, header),
        std.elf.ELFCLASS64 => try verifyElf64(file, header),
        else => return error.UnsupportedBinary,
    }
}

pub fn extractStaticLibs(dep_dir: []const u8) ![]const []const u8 {
    const allocator = std.heap.page_allocator;
    var out = std.ArrayList([]const u8).empty;
    errdefer {
        for (out.items) |item| allocator.free(item);
        out.deinit(allocator);
    }

    var dir = try std.fs.cwd().openDir(dep_dir, .{ .iterate = true });
    defer dir.close();
    var walker = try dir.walk(allocator);
    defer walker.deinit();
    while (try walker.next()) |entry| {
        if (entry.kind != .file) continue;
        if (!std.mem.endsWith(u8, entry.path, ".a")) continue;
        const full = try std.fs.path.join(allocator, &[_][]const u8{ dep_dir, entry.path });
        try out.append(allocator, full);
    }

    return try out.toOwnedSlice(allocator);
}

fn verifyElf64(file: std.fs.File, header: [64]u8) !void {
    const e_phoff = readInt(u64, header[32..40]);
    const e_phentsize = readInt(u16, header[54..56]);
    const e_phnum = readInt(u16, header[56..58]);
    if (e_phentsize == 0 or e_phnum == 0) return;

    var ph_buf: [256]u8 = undefined;
    if (e_phentsize > ph_buf.len) return error.UnsupportedBinary;

    var i: u16 = 0;
    while (i < e_phnum) : (i += 1) {
        const offset = e_phoff + @as(u64, e_phentsize) * i;
        _ = try file.preadAll(ph_buf[0..e_phentsize], offset);
        const p_type = readInt(u32, ph_buf[0..4]);
        if (p_type != std.elf.PT_DYNAMIC) continue;
        const p_offset = readInt(u64, ph_buf[8..16]);
        const p_filesz = readInt(u64, ph_buf[32..40]);
        try scanDynamic64(file, p_offset, p_filesz);
    }
}

fn scanDynamic64(file: std.fs.File, offset: u64, size: u64) !void {
    if (size == 0) return;
    if (size > 16 * 1024 * 1024) return error.DynamicSectionTooLarge;
    const allocator = std.heap.page_allocator;
    const buf = try allocator.alloc(u8, @intCast(size));
    defer allocator.free(buf);
    _ = try file.preadAll(buf, offset);

    var i: usize = 0;
    while (i + 16 <= buf.len) : (i += 16) {
        const tag = readInt(u64, buf[i .. i + 8]);
        if (tag == std.elf.DT_NULL) break;
        if (tag == std.elf.DT_NEEDED) return error.SharedDependenciesFound;
    }
}

fn verifyElf32(file: std.fs.File, header: [64]u8) !void {
    const e_phoff = readInt(u32, header[28..32]);
    const e_phentsize = readInt(u16, header[42..44]);
    const e_phnum = readInt(u16, header[44..46]);
    if (e_phentsize == 0 or e_phnum == 0) return;

    var ph_buf: [128]u8 = undefined;
    if (e_phentsize > ph_buf.len) return error.UnsupportedBinary;

    var i: u16 = 0;
    while (i < e_phnum) : (i += 1) {
        const offset = @as(u64, e_phoff) + @as(u64, e_phentsize) * i;
        _ = try file.preadAll(ph_buf[0..e_phentsize], offset);
        const p_type = readInt(u32, ph_buf[0..4]);
        if (p_type != std.elf.PT_DYNAMIC) continue;
        const p_offset = readInt(u32, ph_buf[4..8]);
        const p_filesz = readInt(u32, ph_buf[16..20]);
        try scanDynamic32(file, p_offset, p_filesz);
    }
}

fn scanDynamic32(file: std.fs.File, offset: u32, size: u32) !void {
    if (size == 0) return;
    if (size > 16 * 1024 * 1024) return error.DynamicSectionTooLarge;
    const allocator = std.heap.page_allocator;
    const buf = try allocator.alloc(u8, size);
    defer allocator.free(buf);
    _ = try file.preadAll(buf, offset);

    var i: usize = 0;
    while (i + 8 <= buf.len) : (i += 8) {
        const tag = readInt(u32, buf[i .. i + 4]);
        if (tag == std.elf.DT_NULL) break;
        if (tag == std.elf.DT_NEEDED) return error.SharedDependenciesFound;
    }
}

fn readInt(comptime T: type, bytes: []const u8) T {
    const ptr: *const [@sizeOf(T)]u8 = @ptrCast(bytes.ptr);
    return std.mem.readInt(T, ptr, .little);
}

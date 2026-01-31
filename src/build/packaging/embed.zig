const std = @import("std");
const core = @import("../../root.zig");
const paths_config = @import("../../paths/config.zig");

pub const RustEmbed = struct {
    alias: []const u8,
    rs_path: []const u8,
    rlib_path: []const u8,
};

pub const EmbedResult = struct {
    c_path: ?[]const u8 = null,
    include_dir: ?[]const u8 = null,
    rust_embed: ?RustEmbed = null,
};

pub fn generateCEmbed(
    allocator: std.mem.Allocator,
    cwd: std.fs.Dir,
    embed_dir: []const u8,
    alias: []const u8,
    owned: *std.ArrayList([]const u8),
) !EmbedResult {
    const gen_dir = try paths_config.projectPath(allocator, &[_][]const u8{"gen"});
    try owned.append(allocator, gen_dir);
    const safe_alias = try sanitizeIdentifier(allocator, alias);
    defer allocator.free(safe_alias);
    const c_name = try std.fmt.allocPrint(allocator, "{s}_embed.c", .{safe_alias});
    try owned.append(allocator, c_name);
    const h_name = try std.fmt.allocPrint(allocator, "{s}_embed.h", .{safe_alias});
    try owned.append(allocator, h_name);

    const c_path = try std.fs.path.join(allocator, &[_][]const u8{ gen_dir, c_name });
    try owned.append(allocator, c_path);
    const h_path = try std.fs.path.join(allocator, &[_][]const u8{ gen_dir, h_name });
    try owned.append(allocator, h_path);

    var h_file = try cwd.createFile(h_path, .{ .truncate = true });
    defer h_file.close();
    var h_buf: [32 * 1024]u8 = undefined;
    var h_writer = h_file.writer(&h_buf);
    try h_writer.interface.writeAll("#pragma once\n#include <stddef.h>\n");

    var c_file = try cwd.createFile(c_path, .{ .truncate = true });
    defer c_file.close();
    var c_buf: [32 * 1024]u8 = undefined;
    var c_writer = c_file.writer(&c_buf);
    try c_writer.interface.print("#include \"{s}\"\n", .{h_name});

    var rust_embed: ?RustEmbed = null;
    const rust_name = try std.fmt.allocPrint(allocator, "{s}_embed.rs", .{safe_alias});
    try owned.append(allocator, rust_name);
    const rust_path = try std.fs.path.join(allocator, &[_][]const u8{ gen_dir, rust_name });
    try owned.append(allocator, rust_path);
    var rust_file = try cwd.createFile(rust_path, .{ .truncate = true });
    defer rust_file.close();
    var rust_buf: [32 * 1024]u8 = undefined;
    var rust_writer = rust_file.writer(&rust_buf);

    const zig_name = try std.fmt.allocPrint(allocator, "{s}.zig", .{safe_alias});
    try owned.append(allocator, zig_name);
    const zig_path = try std.fs.path.join(allocator, &[_][]const u8{ gen_dir, zig_name });
    try owned.append(allocator, zig_path);
    var zig_file = try cwd.createFile(zig_path, .{ .truncate = true });
    defer zig_file.close();
    var zig_buf: [32 * 1024]u8 = undefined;
    var zig_writer = zig_file.writer(&zig_buf);

    var dir = try cwd.openDir(embed_dir, .{ .iterate = true });
    defer dir.close();
    var walker = try dir.walk(allocator);
    defer walker.deinit();
    while (try walker.next()) |entry| {
        if (entry.kind != .file) continue;
        const sym = try buildSymbol(allocator, safe_alias, entry.path);
        defer allocator.free(sym);
        const file_path = try std.fs.path.join(allocator, &[_][]const u8{ embed_dir, entry.path });
        defer allocator.free(file_path);
        var file = try cwd.openFile(file_path, .{});
        defer file.close();
        const data = try file.readToEndAlloc(allocator, 16 * 1024 * 1024);
        defer allocator.free(data);

        try h_writer.interface.print("extern const unsigned char {s}[];\n", .{sym});
        try h_writer.interface.print("extern const size_t {s}_len;\n", .{sym});
        try c_writer.interface.print("const unsigned char {s}[] = {{", .{sym});
        for (data, 0..) |byte, i| {
            if (i % 12 == 0) try c_writer.interface.writeAll("\n  ");
            try c_writer.interface.print("0x{X:0>2}, ", .{byte});
        }
        try c_writer.interface.writeAll("\n};\n");
        try c_writer.interface.print("const size_t {s}_len = {d};\n", .{ sym, data.len });

        const abs_path = try cwd.realpathAlloc(allocator, file_path);
        defer allocator.free(abs_path);
        try rust_writer.interface.print("pub static {s}: &[u8] = include_bytes!(r#\"{s}\"#);\n", .{ sym, abs_path });
        try zig_writer.interface.print("pub const {s} = @embedFile(\"{s}\");\n", .{ sym, abs_path });
    }

    try h_writer.interface.flush();
    try c_writer.interface.flush();
    try rust_writer.interface.flush();
    try zig_writer.interface.flush();

    const rust_alias = try allocator.dupe(u8, safe_alias);
    try owned.append(allocator, rust_alias);
    rust_embed = .{
        .alias = rust_alias,
        .rs_path = rust_path,
        .rlib_path = blk: {
            const rlib_name = try std.fmt.allocPrint(allocator, "{s}_embed.rlib", .{safe_alias});
            try owned.append(allocator, rlib_name);
            break :blk try std.fs.path.join(allocator, &[_][]const u8{ gen_dir, rlib_name });
        },
    };
    try owned.append(allocator, rust_embed.?.rlib_path);

    return .{
        .c_path = c_path,
        .include_dir = gen_dir,
        .rust_embed = rust_embed,
    };
}

pub fn prepareRustEmbeds(
    allocator: std.mem.Allocator,
    cwd: std.fs.Dir,
    rustc_path: []const u8,
    embeds: []const RustEmbed,
    rustc_extra_args: *std.ArrayList([]const u8),
    rustflags_extra: *std.ArrayList([]const u8),
    owned: *std.ArrayList([]const u8),
) !void {
    for (embeds) |embed| {
        const args = &[_][]const u8{
            rustc_path,
            "--crate-type",
            "rlib",
            "--crate-name",
            embed.alias,
            embed.rs_path,
            "-o",
            embed.rlib_path,
        };
        try core.toolchain_executor.runProcess(allocator, cwd, args);
        const extern_arg = try std.fmt.allocPrint(allocator, "{s}={s}", .{ embed.alias, embed.rlib_path });
        try owned.append(allocator, extern_arg);
        try rustc_extra_args.appendSlice(allocator, &[_][]const u8{ "--extern", extern_arg });
        try rustflags_extra.appendSlice(allocator, &[_][]const u8{ "--extern", extern_arg });
    }
}

pub fn buildSymbol(allocator: std.mem.Allocator, prefix: []const u8, rel_path: []const u8) ![]const u8 {
    var buf = std.ArrayList(u8).empty;
    defer buf.deinit(allocator);
    try appendSanitized(&buf, allocator, prefix);
    try buf.append(allocator, '_');
    try appendSanitized(&buf, allocator, rel_path);
    return try buf.toOwnedSlice(allocator);
}

pub fn sanitizeIdentifier(allocator: std.mem.Allocator, text: []const u8) ![]const u8 {
    var buf = std.ArrayList(u8).empty;
    defer buf.deinit(allocator);
    try appendSanitized(&buf, allocator, text);
    return try buf.toOwnedSlice(allocator);
}

fn appendSanitized(buf: *std.ArrayList(u8), allocator: std.mem.Allocator, text: []const u8) !void {
    for (text) |ch| {
        if ((ch >= 'a' and ch <= 'z') or (ch >= 'A' and ch <= 'Z') or (ch >= '0' and ch <= '9')) {
            try buf.append(allocator, ch);
        } else {
            try buf.append(allocator, '_');
        }
    }
}

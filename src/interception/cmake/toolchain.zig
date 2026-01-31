const std = @import("std");
const core = @import("../../root.zig");
const paths_config = @import("../../paths/config.zig");

pub const ToolchainOptions = struct {
    target: core.toolchain_cross.target.CrossTarget,
    zig_path: []const u8,
    sysroot: ?[]const u8 = null,
};

pub fn writeToolchainFile(
    allocator: std.mem.Allocator,
    cwd: std.fs.Dir,
    options: ToolchainOptions,
) ![]const u8 {
    const dir = try paths_config.projectPath(allocator, &[_][]const u8{ "interception", "cmake" });
    try cwd.makePath(dir);
    defer allocator.free(dir);

    const out_path = try std.fs.path.join(allocator, &[_][]const u8{ dir, "toolchain.cmake" });
    errdefer allocator.free(out_path);

    var file = try cwd.createFile(out_path, .{ .truncate = true });
    defer file.close();
    var buf: [32 * 1024]u8 = undefined;
    var writer = file.writer(&buf);

    const zig_target = options.target.toZigTarget();
    const system_name = cmakeSystemName(options.target.os);
    const system_processor = cmakeSystemProcessor(options.target.arch);

    const zig_path = try normalizePathAlloc(allocator, options.zig_path);
    defer allocator.free(zig_path);
    const sysroot_path = if (options.sysroot) |root| try normalizePathAlloc(allocator, root) else null;
    defer if (sysroot_path) |root| allocator.free(root);

    try writer.interface.print("set(CMAKE_SYSTEM_NAME {s})\n", .{system_name});
    try writer.interface.print("set(CMAKE_SYSTEM_PROCESSOR {s})\n", .{system_processor});
    try writer.interface.print("set(CMAKE_C_COMPILER \"{s}\")\n", .{zig_path});
    try writer.interface.writeAll("set(CMAKE_C_COMPILER_ARG1 \"cc\")\n");
    try writer.interface.print("set(CMAKE_CXX_COMPILER \"{s}\")\n", .{zig_path});
    try writer.interface.writeAll("set(CMAKE_CXX_COMPILER_ARG1 \"c++\")\n");
    try writer.interface.writeAll("set(CMAKE_TRY_COMPILE_TARGET_TYPE STATIC_LIBRARY)\n");

    const c_flags = try buildCmakeFlags(allocator, zig_target, sysroot_path);
    defer allocator.free(c_flags);
    try writer.interface.print("set(CMAKE_C_FLAGS_INIT \"{s}\")\n", .{c_flags});
    try writer.interface.print("set(CMAKE_CXX_FLAGS_INIT \"{s}\")\n", .{c_flags});
    try writer.interface.print("set(CMAKE_EXE_LINKER_FLAGS_INIT \"{s}\")\n", .{c_flags});

    if (sysroot_path) |root| {
        try writer.interface.print("set(CMAKE_SYSROOT \"{s}\")\n", .{root});
    }

    try writer.interface.flush();
    return out_path;
}

fn buildCmakeFlags(allocator: std.mem.Allocator, zig_target: []const u8, sysroot: ?[]const u8) ![]const u8 {
    if (sysroot) |root| {
        return std.fmt.allocPrint(allocator, "-target {s} --sysroot {s}", .{ zig_target, root });
    }
    return std.fmt.allocPrint(allocator, "-target {s}", .{zig_target});
}

fn cmakeSystemName(os: core.toolchain_cross.target.Os) []const u8 {
    return switch (os) {
        .linux => "Linux",
        .windows => "Windows",
        .macos => "Darwin",
        .freestanding => "Generic",
    };
}

fn cmakeSystemProcessor(arch: core.toolchain_cross.target.Arch) []const u8 {
    return switch (arch) {
        .x86_64 => "x86_64",
        .aarch64 => "aarch64",
        .riscv64 => "riscv64",
        .wasm32 => "wasm32",
    };
}

fn normalizePathAlloc(allocator: std.mem.Allocator, path: []const u8) ![]const u8 {
    const out = try allocator.dupe(u8, path);
    std.mem.replaceScalar(u8, out, '\\', '/');
    return out;
}

const std = @import("std");

pub const SourceTool = enum {
    Zig,
    Rust,
    Musl,
};

pub const EnvValue = struct {
    value: []const u8,
    owned: bool,
};

pub const OwnedStr = struct {
    value: []const u8,
    owned: bool,
};

pub fn toolName(tool: SourceTool) []const u8 {
    return switch (tool) {
        .Zig => "zig",
        .Rust => "rust",
        .Musl => "musl",
    };
}

pub fn sourceRootFor(tool: SourceTool, version: []const u8) ![]const u8 {
    const env_key = switch (tool) {
        .Zig => "KILNEXUS_ZIG_SOURCE_DIR",
        .Rust => "KILNEXUS_RUST_SOURCE_DIR",
        .Musl => "KILNEXUS_MUSL_SOURCE_DIR",
    };
    if (std.process.getEnvVarOwned(std.heap.page_allocator, env_key)) |value| {
        return value;
    } else |_| {}
    return std.fs.path.join(std.heap.page_allocator, &[_][]const u8{
        ".knx",
        "sources",
        toolName(tool),
        version,
    });
}

pub fn buildDirFor(tool: SourceTool, source_root: []const u8, fallback: []const u8) ![]const u8 {
    const env_key = switch (tool) {
        .Zig => "KILNEXUS_ZIG_BUILD_DIR",
        .Rust => "KILNEXUS_RUST_BUILD_DIR",
        .Musl => "KILNEXUS_MUSL_BUILD_DIR",
    };
    if (std.process.getEnvVarOwned(std.heap.page_allocator, env_key)) |value| {
        return value;
    } else |_| {}
    return std.fs.path.join(std.heap.page_allocator, &[_][]const u8{ source_root, fallback });
}

pub fn muslInstallDirRel(version: []const u8) ![]const u8 {
    return std.fs.path.join(std.heap.page_allocator, &[_][]const u8{
        ".knx",
        "toolchains",
        "musl",
        version,
    });
}

pub fn repoEnvKey(tool: SourceTool) []const u8 {
    return switch (tool) {
        .Zig => "KILNEXUS_ZIG_SOURCE_REPO",
        .Rust => "KILNEXUS_RUST_SOURCE_REPO",
        .Musl => "KILNEXUS_MUSL_SOURCE_REPO",
    };
}

pub fn tagEnvKey(tool: SourceTool) []const u8 {
    return switch (tool) {
        .Zig => "KILNEXUS_ZIG_RELEASE_TAG",
        .Rust => "KILNEXUS_RUST_RELEASE_TAG",
        .Musl => "KILNEXUS_MUSL_RELEASE_TAG",
    };
}

pub fn assetEnvKey(tool: SourceTool) []const u8 {
    return switch (tool) {
        .Zig => "KILNEXUS_ZIG_SOURCE_ASSET",
        .Rust => "KILNEXUS_RUST_SOURCE_ASSET",
        .Musl => "KILNEXUS_MUSL_SOURCE_ASSET",
    };
}

pub fn stageEnvKey(tool: SourceTool, suffix: []const u8) []const u8 {
    return switch (tool) {
        .Zig => if (std.mem.eql(u8, suffix, "STAGE1_PATH")) "KILNEXUS_ZIG_STAGE1_PATH" else if (std.mem.eql(u8, suffix, "STAGE2_PATH")) "KILNEXUS_ZIG_STAGE2_PATH" else "KILNEXUS_ZIG_STAGE3_PATH",
        .Rust => if (std.mem.eql(u8, suffix, "STAGE1_PATH")) "KILNEXUS_RUST_STAGE1_PATH" else if (std.mem.eql(u8, suffix, "STAGE2_PATH")) "KILNEXUS_RUST_STAGE2_PATH" else "KILNEXUS_RUST_STAGE3_PATH",
        .Musl => if (std.mem.eql(u8, suffix, "STAGE1_PATH")) "KILNEXUS_MUSL_STAGE1_PATH" else if (std.mem.eql(u8, suffix, "STAGE2_PATH")) "KILNEXUS_MUSL_STAGE2_PATH" else "KILNEXUS_MUSL_STAGE3_PATH",
    };
}

pub fn signatureKeyEnvKey(tool: SourceTool) []const u8 {
    return switch (tool) {
        .Zig => "KILNEXUS_ZIG_SOURCE_PUBKEY",
        .Rust => "KILNEXUS_RUST_SOURCE_PUBKEY",
        .Musl => "KILNEXUS_MUSL_SOURCE_PUBKEY",
    };
}

pub fn envOrNull(allocator: std.mem.Allocator, key: []const u8) !?[]const u8 {
    return std.process.getEnvVarOwned(allocator, key) catch |err| switch (err) {
        error.EnvironmentVariableNotFound => null,
        else => err,
    };
}

pub fn envOrDefault(allocator: std.mem.Allocator, key: []const u8, default_value: []const u8) !EnvValue {
    if (std.process.getEnvVarOwned(allocator, key)) |value| {
        return .{ .value = value, .owned = true };
    } else |_| {}
    return .{ .value = default_value, .owned = false };
}

pub fn exeNameAlloc(allocator: std.mem.Allocator, base: []const u8) !OwnedStr {
    const builtin = @import("builtin");
    if (builtin.os.tag != .windows) return .{ .value = base, .owned = false };
    if (std.mem.endsWith(u8, base, ".exe")) return .{ .value = base, .owned = false };
    const value = try std.fmt.allocPrint(allocator, "{s}.exe", .{base});
    return .{ .value = value, .owned = true };
}

pub fn fileExists(path: []const u8) bool {
    std.fs.cwd().access(path, .{}) catch return false;
    return true;
}

pub fn dirExists(path: []const u8) bool {
    var dir = std.fs.cwd().openDir(path, .{}) catch return false;
    dir.close();
    return true;
}

pub fn ensureDir(path: []const u8) !void {
    std.fs.cwd().makePath(path) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };
}

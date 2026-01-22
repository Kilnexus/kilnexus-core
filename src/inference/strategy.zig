const std = @import("std");
const detector = @import("detector.zig");
const zig_driver = @import("../toolchain/driver.zig");
const toolchain = @import("../toolchain/manager.zig");
const bootstrap = @import("../toolchain/bootstrap.zig");

pub fn buildInferred(allocator: std.mem.Allocator, project_type: detector.ProjectType, cwd: std.fs.Dir) !void {
    var stdout_buffer: [32 * 1024]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;
    defer stdout.flush() catch {};

    switch (project_type) {
        .C => try buildC(allocator, cwd),
        .Rust => try buildRust(allocator, cwd),
        .Go => try buildGo(allocator, cwd),
        .Python => try buildPython(allocator, cwd),
        .Unknown => try printTodo("Unknown", stdout),
    }
}

fn buildC(allocator: std.mem.Allocator, cwd: std.fs.Dir) !void {
    if (exists(cwd, "build.zig")) {
        const zig_path = try resolveOrBootstrapZig(allocator, cwd, toolchain.default_zig_version);
        defer allocator.free(zig_path);
        try runProcess(allocator, cwd, &[_][]const u8{ zig_path, "build" });
        return;
    }

    const zig_path = try resolveOrBootstrapZig(allocator, cwd, toolchain.default_zig_version);
    defer allocator.free(zig_path);

    if (exists(cwd, "main.c")) {
        try zig_driver.compileC(allocator, cwd, "main.c", .{
            .output_name = "kilnexus-out",
            .static = true,
            .zig_path = zig_path,
            .env = .{ .target = null },
        });
        return;
    }

    if (exists(cwd, "main.cpp")) {
        try zig_driver.compileCpp(allocator, cwd, "main.cpp", .{
            .output_name = "kilnexus-out",
            .static = true,
            .zig_path = zig_path,
            .env = .{ .target = null },
        });
        return;
    }

    if (exists(cwd, "main.cc")) {
        try zig_driver.compileCpp(allocator, cwd, "main.cc", .{
            .output_name = "kilnexus-out",
            .static = true,
            .zig_path = zig_path,
            .env = .{ .target = null },
        });
        return;
    }

    if (exists(cwd, "main.cxx")) {
        try zig_driver.compileCpp(allocator, cwd, "main.cxx", .{
            .output_name = "kilnexus-out",
            .static = true,
            .zig_path = zig_path,
            .env = .{ .target = null },
        });
        return;
    }

    return error.MissingSource;
}

fn buildRust(allocator: std.mem.Allocator, cwd: std.fs.Dir) !void {
    if (!exists(cwd, "Cargo.toml")) return error.MissingCargoManifest;
    const zig_path = try resolveOrBootstrapZig(allocator, cwd, toolchain.default_zig_version);
    defer allocator.free(zig_path);
    var rust_paths = try resolveOrBootstrapRust(allocator, cwd, toolchain.default_rust_version);
    defer rust_paths.deinit(allocator);
    try zig_driver.buildRustCargo(allocator, cwd, .{
        .zig_path = zig_path,
        .rustc_path = rust_paths.rustc,
        .cargo_path = rust_paths.cargo,
        .cargo_manifest_path = "Cargo.toml",
    });
}

fn buildGo(allocator: std.mem.Allocator, cwd: std.fs.Dir) !void {
    if (!exists(cwd, "go.mod")) return error.MissingGoModule;
    const go_path = try resolveOrBootstrapGo(allocator, cwd, toolchain.default_go_version);
    defer allocator.free(go_path);
    try runProcess(allocator, cwd, &[_][]const u8{ go_path, "build", "-o", "kilnexus-out", "." });
}

fn buildPython(allocator: std.mem.Allocator, cwd: std.fs.Dir) !void {
    if (exists(cwd, "requirements.txt")) {
        try runProcess(allocator, cwd, &[_][]const u8{ "python", "-m", "pip", "install", "-r", "requirements.txt" });
        return;
    }
    if (exists(cwd, "pyproject.toml") or exists(cwd, "setup.py")) {
        try runProcess(allocator, cwd, &[_][]const u8{ "python", "-m", "pip", "install", "." });
        return;
    }
    return error.MissingPythonManifest;
}

fn exists(dir: std.fs.Dir, filename: []const u8) bool {
    dir.access(filename, .{}) catch return false;
    return true;
}

fn printTodo(label: []const u8, writer: anytype) !void {
    try writer.print(">> TODO: {s} build strategy not implemented yet.\n", .{label});
}

fn runProcess(allocator: std.mem.Allocator, cwd: std.fs.Dir, argv: []const []const u8) !void {
    var child = std.process.Child.init(argv, allocator);
    child.cwd_dir = cwd;
    child.stdin_behavior = .Inherit;
    child.stdout_behavior = .Inherit;
    child.stderr_behavior = .Inherit;

    const term = try child.spawnAndWait();
    switch (term) {
        .Exited => |code| {
            if (code != 0) return error.CompileFailed;
        },
        else => return error.CompileFailed,
    }
}

const RustPaths = struct {
    rustc: []const u8,
    cargo: []const u8,

    fn deinit(self: *RustPaths, allocator: std.mem.Allocator) void {
        allocator.free(self.rustc);
        allocator.free(self.cargo);
    }
};

fn resolveOrBootstrapZig(allocator: std.mem.Allocator, cwd: std.fs.Dir, version: []const u8) ![]const u8 {
    return toolchain.resolveZigPathForVersion(allocator, cwd, version) catch |err| {
        if (err != error.ToolchainMissing) return err;
        try bootstrap.bootstrapZig(allocator, cwd, version);
        return try toolchain.resolveZigPathForVersion(allocator, cwd, version);
    };
}

fn resolveOrBootstrapRust(allocator: std.mem.Allocator, cwd: std.fs.Dir, version: []const u8) !RustPaths {
    const rustc_path = toolchain.resolveRustcPathForVersion(allocator, cwd, version) catch |err| blk: {
        if (err != error.ToolchainMissing) return err;
        try bootstrap.bootstrapRust(allocator, cwd, version);
        break :blk try toolchain.resolveRustcPathForVersion(allocator, cwd, version);
    };
    errdefer allocator.free(rustc_path);

    const cargo_path = toolchain.resolveCargoPathForVersion(allocator, cwd, version) catch |err| blk: {
        if (err != error.ToolchainMissing) return err;
        try bootstrap.bootstrapRust(allocator, cwd, version);
        break :blk try toolchain.resolveCargoPathForVersion(allocator, cwd, version);
    };

    return .{ .rustc = rustc_path, .cargo = cargo_path };
}

fn resolveOrBootstrapGo(allocator: std.mem.Allocator, cwd: std.fs.Dir, version: []const u8) ![]const u8 {
    return toolchain.resolveGoPathForVersion(allocator, cwd, version) catch |err| {
        if (err != error.ToolchainMissing) return err;
        try bootstrap.bootstrapGo(allocator, cwd, version);
        return try toolchain.resolveGoPathForVersion(allocator, cwd, version);
    };
}

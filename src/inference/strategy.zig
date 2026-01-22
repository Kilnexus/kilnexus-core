const std = @import("std");
const detector = @import("detector.zig");
const common = @import("../toolchain/common.zig");
const zig_builder = @import("../toolchain/builder/zig.zig");
const rust_builder = @import("../toolchain/builder/rust.zig");
const toolchain = @import("../toolchain/manager.zig");
const bootstrap = @import("../toolchain/bootstrap.zig");
const executor_mod = @import("../toolchain/executor.zig");
const iface = @import("strategies/interface.zig");
const c_strategy = @import("strategies/c.zig");
const rust_strategy = @import("strategies/rust.zig");
const go_strategy = @import("strategies/go.zig");
const python_strategy = @import("strategies/python.zig");
const unknown_strategy = @import("strategies/unknown.zig");

pub fn buildInferred(allocator: std.mem.Allocator, project_type: detector.ProjectType, cwd: std.fs.Dir) !void {
    var stdout_buffer: [32 * 1024]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;
    defer stdout.flush() catch {};

    const ctx = try buildContext(cwd);
    const plan = switch (project_type) {
        .C => c_strategy.plan(ctx),
        .Rust => rust_strategy.plan(ctx),
        .Go => go_strategy.plan(ctx),
        .Python => python_strategy.plan(ctx),
        .Unknown => unknown_strategy.plan(ctx),
    };

    try executePlan(allocator, cwd, plan, stdout);
}

fn buildContext(cwd: std.fs.Dir) !iface.BuildContext {
    return .{
        .has_build_zig = exists(cwd, "build.zig"),
        .has_main_c = exists(cwd, "main.c"),
        .has_main_cpp = exists(cwd, "main.cpp"),
        .has_main_cc = exists(cwd, "main.cc"),
        .has_main_cxx = exists(cwd, "main.cxx"),
        .has_cargo_toml = exists(cwd, "Cargo.toml"),
        .has_go_mod = exists(cwd, "go.mod"),
        .has_requirements = exists(cwd, "requirements.txt"),
        .has_pyproject = exists(cwd, "pyproject.toml"),
        .has_setup_py = exists(cwd, "setup.py"),
    };
}

fn executePlan(allocator: std.mem.Allocator, cwd: std.fs.Dir, plan: iface.BuildPlan, stdout: anytype) !void {
    switch (plan) {
        .ZigBuild => {
            const zig_path = try resolveOrBootstrapZig(allocator, cwd, toolchain.default_zig_version);
            defer allocator.free(zig_path);
            try executor_mod.runProcess(allocator, cwd, &[_][]const u8{ zig_path, "build" });
        },
        .CompileC => |source| {
            const zig_path = try resolveOrBootstrapZig(allocator, cwd, toolchain.default_zig_version);
            defer allocator.free(zig_path);
            const options = common.CompileOptions{
                .output_name = "kilnexus-out",
                .static = true,
                .zig_path = zig_path,
                .env = .{ .target = null },
            };
            var args = try zig_builder.buildZigArgs(allocator, "cc", source, options);
            defer args.deinit(allocator);
            var env_map = try executor_mod.getEnvMap(allocator);
            defer env_map.deinit();
            try executor_mod.ensureSourceDateEpoch(&env_map);
            try executor_mod.runWithEnvMap(allocator, cwd, args.argv.items, options.env, &env_map);
        },
        .CompileCpp => |source| {
            const zig_path = try resolveOrBootstrapZig(allocator, cwd, toolchain.default_zig_version);
            defer allocator.free(zig_path);
            const options = common.CompileOptions{
                .output_name = "kilnexus-out",
                .static = true,
                .zig_path = zig_path,
                .env = .{ .target = null },
            };
            var args = try zig_builder.buildZigArgs(allocator, "c++", source, options);
            defer args.deinit(allocator);
            var env_map = try executor_mod.getEnvMap(allocator);
            defer env_map.deinit();
            try executor_mod.ensureSourceDateEpoch(&env_map);
            try executor_mod.runWithEnvMap(allocator, cwd, args.argv.items, options.env, &env_map);
        },
        .RustCargo => {
            const zig_path = try resolveOrBootstrapZig(allocator, cwd, toolchain.default_zig_version);
            defer allocator.free(zig_path);
            var rust_paths = try resolveOrBootstrapRust(allocator, cwd, toolchain.default_rust_version);
            defer rust_paths.deinit(allocator);
            const options = common.CompileOptions{
                .zig_path = zig_path,
                .rustc_path = rust_paths.rustc,
                .cargo_path = rust_paths.cargo,
                .cargo_manifest_path = "Cargo.toml",
            };
            var cargo_plan = try rust_builder.buildCargoPlan(allocator, options);
            defer cargo_plan.deinit(allocator);
            var env_map = try executor_mod.getEnvMap(allocator);
            defer env_map.deinit();
            const existing_rustflags = env_map.get("RUSTFLAGS");
            const remap_prefix = try getRemapPrefix(allocator, cwd);
            defer if (remap_prefix) |prefix| allocator.free(prefix);
            var env_update = try rust_builder.buildCargoEnvUpdate(
                allocator,
                options,
                cargo_plan.target_value,
                existing_rustflags,
                remap_prefix,
            );
            defer env_update.deinit(allocator);
            try env_map.put("RUSTFLAGS", env_update.rustflags_value);
            if (env_update.linker_key) |key| {
                try env_map.put(key, env_update.linker_value.?);
            }
            try env_map.put("RUSTC", options.rustc_path);
            try executor_mod.ensureSourceDateEpoch(&env_map);
            try executor_mod.runProcessWithEnv(allocator, cwd, cargo_plan.args.argv.items, &env_map);
        },
        .GoBuild => {
            const go_path = try resolveOrBootstrapGo(allocator, cwd, toolchain.default_go_version);
            defer allocator.free(go_path);
            try executor_mod.runProcess(allocator, cwd, &[_][]const u8{ go_path, "build", "-o", "kilnexus-out", "." });
        },
        .PythonInstallRequirements => {
            try executor_mod.runProcess(allocator, cwd, &[_][]const u8{ "python", "-m", "pip", "install", "-r", "requirements.txt" });
        },
        .PythonInstallProject => {
            try executor_mod.runProcess(allocator, cwd, &[_][]const u8{ "python", "-m", "pip", "install", "." });
        },
        .MissingSource => return error.MissingSource,
        .MissingCargoManifest => return error.MissingCargoManifest,
        .MissingGoModule => return error.MissingGoModule,
        .MissingPythonManifest => return error.MissingPythonManifest,
        .Unknown => try printTodo("Unknown", stdout),
    }
}

fn exists(dir: std.fs.Dir, filename: []const u8) bool {
    dir.access(filename, .{}) catch return false;
    return true;
}

fn printTodo(label: []const u8, writer: anytype) !void {
    try writer.print(">> TODO: {s} build strategy not implemented yet.\n", .{label});
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

fn getRemapPrefix(allocator: std.mem.Allocator, cwd: std.fs.Dir) !?[]const u8 {
    return cwd.realpathAlloc(allocator, ".") catch null;
}

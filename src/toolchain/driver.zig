const std = @import("std");

const fixed_source_date_epoch = "0";
const remap_dest = ".";

pub const VirtualEnv = struct {
    target: ?[]const u8 = null,
    kernel_version: ?[]const u8 = null,
    sysroot: ?[]const u8 = null,
    virtual_root: ?[]const u8 = null,
};

pub const CompileOptions = struct {
    output_name: []const u8 = "a.out",
    static: bool = true,
    zig_path: []const u8 = "zig",
    rustc_path: []const u8 = "rustc",
    cargo_path: []const u8 = "cargo",
    env: VirtualEnv = .{},
    rust_crate_type: ?[]const u8 = null,
    rust_edition: ?[]const u8 = null,
    cargo_manifest_path: ?[]const u8 = null,
    cargo_release: bool = false,
    extra_args: []const []const u8 = &[_][]const u8{},
};

const ArgvBuild = struct {
    argv: std.ArrayList([]const u8),
    owned: std.ArrayList([]const u8),

    fn init() ArgvBuild {
        return .{ .argv = .empty, .owned = .empty };
    }

    fn deinit(self: *ArgvBuild, allocator: std.mem.Allocator) void {
        for (self.owned.items) |item| allocator.free(item);
        self.owned.deinit(allocator);
        self.argv.deinit(allocator);
    }
};

const CargoBuildPlan = struct {
    args: ArgvBuild,
    target_value: ?[]const u8,

    fn deinit(self: *CargoBuildPlan, allocator: std.mem.Allocator) void {
        self.args.deinit(allocator);
    }
};

const EnvUpdate = struct {
    rustflags_value: []const u8,
    linker_key: ?[]const u8,
    linker_value: ?[]const u8,
    owned: std.ArrayList([]const u8),

    fn init() EnvUpdate {
        return .{
            .rustflags_value = "",
            .linker_key = null,
            .linker_value = null,
            .owned = .empty,
        };
    }

    fn deinit(self: *EnvUpdate, allocator: std.mem.Allocator) void {
        for (self.owned.items) |item| allocator.free(item);
        self.owned.deinit(allocator);
    }
};

const Executor = struct {
    allocator: std.mem.Allocator,
    cwd: std.fs.Dir,

    fn init(allocator: std.mem.Allocator, cwd: std.fs.Dir) Executor {
        return .{ .allocator = allocator, .cwd = cwd };
    }

    fn run(self: Executor, argv: []const []const u8, env: VirtualEnv) !void {
        if (env.virtual_root) |root| {
            return self.runInVirtualRoot(argv, root);
        }
        try self.runProcess(argv);
    }

    fn runWithEnvMap(self: Executor, argv: []const []const u8, env: VirtualEnv, env_map: *std.process.EnvMap) !void {
        if (env.virtual_root) |root| {
            return self.runInVirtualRootWithEnv(argv, root, env_map);
        }
        try self.runProcessWithEnv(argv, env_map);
    }

    fn runInVirtualRoot(self: Executor, argv: []const []const u8, root: []const u8) !void {
        const builtin = @import("builtin");
        if (builtin.os.tag != .linux) return error.VirtualRootUnsupported;

        var wrapper = std.ArrayList([]const u8).empty;
        defer wrapper.deinit(self.allocator);

        try wrapper.appendSlice(self.allocator, &[_][]const u8{
            "unshare",
            "--mount",
            "--map-root-user",
            "--uts",
            "--pid",
            "--fork",
            "--mount-proc",
            "--root",
            root,
            "--",
        });
        try wrapper.appendSlice(self.allocator, argv);
        try self.runProcess(wrapper.items);
    }

    fn runInVirtualRootWithEnv(self: Executor, argv: []const []const u8, root: []const u8, env_map: *std.process.EnvMap) !void {
        const builtin = @import("builtin");
        if (builtin.os.tag != .linux) return error.VirtualRootUnsupported;

        var wrapper = std.ArrayList([]const u8).empty;
        defer wrapper.deinit(self.allocator);

        try wrapper.appendSlice(self.allocator, &[_][]const u8{
            "unshare",
            "--mount",
            "--map-root-user",
            "--uts",
            "--pid",
            "--fork",
            "--mount-proc",
            "--root",
            root,
            "--",
        });
        try wrapper.appendSlice(self.allocator, argv);
        try self.runProcessWithEnv(wrapper.items, env_map);
    }

    fn runProcess(self: Executor, argv: []const []const u8) !void {
        var child = std.process.Child.init(argv, self.allocator);
        child.cwd_dir = self.cwd;
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

    fn runProcessWithEnv(self: Executor, argv: []const []const u8, env_map: *std.process.EnvMap) !void {
        var child = std.process.Child.init(argv, self.allocator);
        child.cwd_dir = self.cwd;
        child.stdin_behavior = .Inherit;
        child.stdout_behavior = .Inherit;
        child.stderr_behavior = .Inherit;
        child.env_map = env_map;

        const term = try child.spawnAndWait();
        switch (term) {
            .Exited => |code| {
                if (code != 0) return error.CompileFailed;
            },
            else => return error.CompileFailed,
        }
    }

    fn getEnvMap(self: Executor) !std.process.EnvMap {
        return std.process.EnvMap.init(self.allocator);
    }
};

pub fn compileC(
    allocator: std.mem.Allocator,
    cwd: std.fs.Dir,
    source_path: []const u8,
    options: CompileOptions,
) !void {
    try compileZig(allocator, cwd, "cc", source_path, options);
}

pub fn compileCpp(
    allocator: std.mem.Allocator,
    cwd: std.fs.Dir,
    source_path: []const u8,
    options: CompileOptions,
) !void {
    try compileZig(allocator, cwd, "c++", source_path, options);
}

pub fn compileRust(
    allocator: std.mem.Allocator,
    cwd: std.fs.Dir,
    source_path: []const u8,
    options: CompileOptions,
) !void {
    const remap_prefix = try getRemapPrefix(allocator, cwd);
    defer if (remap_prefix) |prefix| allocator.free(prefix);

    var args = try buildRustArgs(allocator, source_path, options, remap_prefix);
    defer args.deinit(allocator);

    var executor = Executor.init(allocator, cwd);
    var env_map = try executor.getEnvMap();
    defer env_map.deinit();
    try ensureSourceDateEpoch(&env_map);
    try executor.runWithEnvMap(args.argv.items, options.env, &env_map);
}

pub fn buildRustCargo(
    allocator: std.mem.Allocator,
    cwd: std.fs.Dir,
    options: CompileOptions,
) !void {
    var plan = try buildCargoPlan(allocator, options);
    defer plan.deinit(allocator);

    var executor = Executor.init(allocator, cwd);
    var env_map = try executor.getEnvMap();
    defer env_map.deinit();

    const existing_rustflags = env_map.get("RUSTFLAGS");
    const remap_prefix = try getRemapPrefix(allocator, cwd);
    defer if (remap_prefix) |prefix| allocator.free(prefix);

    var env_update = try buildCargoEnvUpdate(allocator, options, plan.target_value, existing_rustflags, remap_prefix);
    defer env_update.deinit(allocator);

    try env_map.put("RUSTFLAGS", env_update.rustflags_value);
    if (env_update.linker_key) |key| {
        try env_map.put(key, env_update.linker_value.?);
    }
    try env_map.put("RUSTC", options.rustc_path);
    try ensureSourceDateEpoch(&env_map);

    try executor.runProcessWithEnv(plan.args.argv.items, &env_map);
}

fn compileZig(
    allocator: std.mem.Allocator,
    cwd: std.fs.Dir,
    zig_mode: []const u8,
    source_path: []const u8,
    options: CompileOptions,
) !void {
    var args = try buildZigArgs(allocator, zig_mode, source_path, options);
    defer args.deinit(allocator);

    var executor = Executor.init(allocator, cwd);
    var env_map = try executor.getEnvMap();
    defer env_map.deinit();
    try ensureSourceDateEpoch(&env_map);
    try executor.runWithEnvMap(args.argv.items, options.env, &env_map);
}

const TargetResolution = struct {
    value: []const u8,
    owned: ?[]const u8,
};

fn zigCompilerPath(options: CompileOptions) []const u8 {
    return options.zig_path;
}

fn rustCompilerPath(options: CompileOptions) []const u8 {
    return options.rustc_path;
}

fn cargoCompilerPath(options: CompileOptions) []const u8 {
    return options.cargo_path;
}

fn resolveTargetIfNeeded(allocator: std.mem.Allocator, env: VirtualEnv) !?[]const u8 {
    if (env.target == null or env.kernel_version == null) return null;
    const resolved = try resolveTarget(allocator, env.target.?, env.kernel_version);
    if (resolved.owned == null) return null;
    return resolved.owned;
}

fn resolveTarget(allocator: std.mem.Allocator, target: []const u8, kernel_version: ?[]const u8) !TargetResolution {
    if (kernel_version) |version| {
        if (needsKernelSuffix(target, version)) {
            const combined = try std.fmt.allocPrint(allocator, "{s}.{s}", .{ target, version });
            return .{ .value = combined, .owned = combined };
        }
    }
    return .{ .value = target, .owned = null };
}

fn needsKernelSuffix(target: []const u8, kernel_version: []const u8) bool {
    if (std.mem.indexOf(u8, target, kernel_version) != null) return false;
    if (std.mem.indexOf(u8, target, "linux-gnu") == null) return false;
    if (std.mem.indexOf(u8, target, "linux-gnu.") != null) return false;
    return true;
}

fn buildZigArgs(
    allocator: std.mem.Allocator,
    zig_mode: []const u8,
    source_path: []const u8,
    options: CompileOptions,
) !ArgvBuild {
    var args = ArgvBuild.init();

    try args.argv.appendSlice(allocator, &[_][]const u8{
        zigCompilerPath(options),
        zig_mode,
        source_path,
        "-o",
        options.output_name,
    });
    if (options.static) try args.argv.append(allocator, "-static");

    const resolved_target = try resolveTargetIfNeeded(allocator, options.env);
    if (resolved_target) |value| try args.owned.append(allocator, value);

    if (options.env.target) |target| {
        try args.argv.append(allocator, "-target");
        try args.argv.append(allocator, resolved_target orelse target);
    }

    if (options.env.sysroot) |sysroot| {
        try args.argv.append(allocator, "--sysroot");
        try args.argv.append(allocator, sysroot);
    }

    if (options.extra_args.len != 0) {
        try args.argv.appendSlice(allocator, options.extra_args);
    }

    return args;
}

fn buildRustArgs(
    allocator: std.mem.Allocator,
    source_path: []const u8,
    options: CompileOptions,
    remap_prefix: ?[]const u8,
) !ArgvBuild {
    var args = ArgvBuild.init();

    const linker_arg = try std.fmt.allocPrint(allocator, "linker={s}", .{zigCompilerPath(options)});
    try args.owned.append(allocator, linker_arg);
    try args.argv.appendSlice(allocator, &[_][]const u8{
        rustCompilerPath(options),
        source_path,
        "-o",
        options.output_name,
        "-C",
        linker_arg,
        "-C",
        "link-arg=cc",
    });

    if (options.rust_crate_type) |crate_type| {
        try args.argv.append(allocator, "--crate-type");
        try args.argv.append(allocator, crate_type);
    }

    if (options.rust_edition) |edition| {
        try args.argv.append(allocator, "--edition");
        try args.argv.append(allocator, edition);
    }

    if (options.static) {
        try args.argv.appendSlice(allocator, &[_][]const u8{ "-C", "link-arg=-static" });
    }

    if (options.env.target) |target| {
        const resolved = try resolveTarget(allocator, target, options.env.kernel_version);
        if (resolved.owned) |value| try args.owned.append(allocator, value);
        try args.argv.append(allocator, "--target");
        try args.argv.append(allocator, resolved.value);
        try args.argv.appendSlice(allocator, &[_][]const u8{ "-C", "link-arg=-target" });
        const link_target = try std.fmt.allocPrint(allocator, "link-arg={s}", .{resolved.value});
        try args.owned.append(allocator, link_target);
        try args.argv.appendSlice(allocator, &[_][]const u8{ "-C", link_target });
    }

    if (options.env.sysroot) |sysroot| {
        try args.argv.appendSlice(allocator, &[_][]const u8{ "-C", "link-arg=--sysroot" });
        const link_sysroot = try std.fmt.allocPrint(allocator, "link-arg={s}", .{sysroot});
        try args.owned.append(allocator, link_sysroot);
        try args.argv.appendSlice(allocator, &[_][]const u8{ "-C", link_sysroot });
    }

    if (remap_prefix) |prefix| {
        const mapping = try std.fmt.allocPrint(allocator, "{s}={s}", .{ prefix, remap_dest });
        try args.owned.append(allocator, mapping);
        try args.argv.appendSlice(allocator, &[_][]const u8{ "--remap-path-prefix", mapping });
    }

    if (options.extra_args.len != 0) {
        try args.argv.appendSlice(allocator, options.extra_args);
    }

    return args;
}

fn buildCargoPlan(
    allocator: std.mem.Allocator,
    options: CompileOptions,
) !CargoBuildPlan {
    var args = ArgvBuild.init();
    var target_value: ?[]const u8 = null;

    try args.argv.appendSlice(allocator, &[_][]const u8{ cargoCompilerPath(options), "build" });
    if (options.cargo_release) try args.argv.append(allocator, "--release");
    if (options.cargo_manifest_path) |manifest| {
        try args.argv.append(allocator, "--manifest-path");
        try args.argv.append(allocator, manifest);
    }

    if (options.env.target) |target| {
        const resolved = try resolveTarget(allocator, target, options.env.kernel_version);
        if (resolved.owned) |value| try args.owned.append(allocator, value);
        target_value = resolved.value;
        try args.argv.append(allocator, "--target");
        try args.argv.append(allocator, resolved.value);
    }

    return .{ .args = args, .target_value = target_value };
}

fn buildRustFlags(
    allocator: std.mem.Allocator,
    options: CompileOptions,
    target_value: ?[]const u8,
    remap_prefix: ?[]const u8,
) ![]const u8 {
    var parts = std.ArrayList([]const u8).empty;
    defer parts.deinit(allocator);
    var owned = std.ArrayList([]const u8).empty;
    defer {
        for (owned.items) |item| allocator.free(item);
        owned.deinit(allocator);
    }

    const linker_arg = try std.fmt.allocPrint(allocator, "-C linker={s}", .{options.zig_path});
    try owned.append(allocator, linker_arg);
    try parts.append(allocator, linker_arg);
    try parts.append(allocator, "-C link-arg=cc");

    if (options.static) try parts.append(allocator, "-C link-arg=-static");

    if (target_value) |target| {
        try parts.append(allocator, "-C link-arg=-target");
        const target_arg = try std.fmt.allocPrint(allocator, "-C link-arg={s}", .{target});
        try owned.append(allocator, target_arg);
        try parts.append(allocator, target_arg);
    }

    if (options.env.sysroot) |sysroot| {
        try parts.append(allocator, "-C link-arg=--sysroot");
        const sysroot_arg = try std.fmt.allocPrint(allocator, "-C link-arg={s}", .{sysroot});
        try owned.append(allocator, sysroot_arg);
        try parts.append(allocator, sysroot_arg);
    }

    if (remap_prefix) |prefix| {
        const mapping = try std.fmt.allocPrint(allocator, "{s}={s}", .{ prefix, remap_dest });
        try owned.append(allocator, mapping);
        try parts.append(allocator, "--remap-path-prefix");
        try parts.append(allocator, mapping);
    }

    return try std.mem.join(allocator, " ", parts.items);
}

fn buildCargoEnvUpdate(
    allocator: std.mem.Allocator,
    options: CompileOptions,
    target_value: ?[]const u8,
    existing_rustflags: ?[]const u8,
    remap_prefix: ?[]const u8,
) !EnvUpdate {
    var update = EnvUpdate.init();

    const rustflags = try buildRustFlags(allocator, options, target_value, remap_prefix);
    try update.owned.append(allocator, rustflags);
    update.rustflags_value = rustflags;

    if (existing_rustflags) |existing| {
        const merged = try std.fmt.allocPrint(allocator, "{s} {s}", .{ existing, rustflags });
        try update.owned.append(allocator, merged);
        update.rustflags_value = merged;
    }

    if (target_value) |resolved_target| {
        const linker_key = try cargoTargetLinkerKey(allocator, resolved_target);
        try update.owned.append(allocator, linker_key);
        update.linker_key = linker_key;
        update.linker_value = zigCompilerPath(options);
    }

    return update;
}

fn cargoTargetLinkerKey(allocator: std.mem.Allocator, target: []const u8) ![]const u8 {
    var key = std.ArrayList(u8).empty;
    defer key.deinit(allocator);

    try key.appendSlice(allocator, "CARGO_TARGET_");
    for (target) |ch| {
        if (ch == '-') {
            try key.append(allocator, '_');
        } else if (ch == '.') {
            try key.append(allocator, '_');
        } else {
            try key.append(allocator, std.ascii.toUpper(ch));
        }
    }
    try key.appendSlice(allocator, "_LINKER");
    return try key.toOwnedSlice(allocator);
}

fn getRemapPrefix(allocator: std.mem.Allocator, cwd: std.fs.Dir) !?[]const u8 {
    return cwd.realpathAlloc(allocator, ".") catch null;
}

fn ensureSourceDateEpoch(env_map: *std.process.EnvMap) !void {
    if (env_map.get("SOURCE_DATE_EPOCH") == null) {
        try env_map.put("SOURCE_DATE_EPOCH", fixed_source_date_epoch);
    }
}

fn argvHasPair(argv: []const []const u8, first: []const u8, second: []const u8) bool {
    if (argv.len < 2) return false;
    var i: usize = 0;
    while (i + 1 < argv.len) : (i += 1) {
        if (std.mem.eql(u8, argv[i], first) and std.mem.eql(u8, argv[i + 1], second)) return true;
    }
    return false;
}

test "buildZigArgs uses kernel suffix for linux-gnu target" {
    const allocator = std.testing.allocator;
    const options = CompileOptions{
        .env = .{
            .target = "x86_64-linux-gnu",
            .kernel_version = "2.6.32",
        },
    };
    var args = try buildZigArgs(allocator, "cc", "main.c", options);
    defer args.deinit(allocator);

    try std.testing.expect(argvHasPair(args.argv.items, "-target", "x86_64-linux-gnu.2.6.32"));
}

test "buildRustArgs uses kernel suffix for linux-gnu target" {
    const allocator = std.testing.allocator;
    const options = CompileOptions{
        .env = .{
            .target = "aarch64-linux-gnu",
            .kernel_version = "5.10",
        },
    };
    var args = try buildRustArgs(allocator, "main.rs", options, null);
    defer args.deinit(allocator);

    try std.testing.expect(argvHasPair(args.argv.items, "--target", "aarch64-linux-gnu.5.10"));
    try std.testing.expect(argvHasPair(args.argv.items, "-C", "link-arg=aarch64-linux-gnu.5.10"));
}

test "buildRustArgs keeps non-linux-gnu target without suffix" {
    const allocator = std.testing.allocator;
    const options = CompileOptions{
        .env = .{
            .target = "x86_64-windows-gnu",
            .kernel_version = "5.10",
        },
    };
    var args = try buildRustArgs(allocator, "main.rs", options, null);
    defer args.deinit(allocator);

    try std.testing.expect(argvHasPair(args.argv.items, "--target", "x86_64-windows-gnu"));
}

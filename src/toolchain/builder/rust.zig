const std = @import("std");
const common = @import("../common.zig");
const argv_builder = @import("argv.zig");
const target_builder = @import("target.zig");

const remap_dest = ".";

pub const CargoBuildPlan = struct {
    args: argv_builder.ArgvBuild,
    target_value: ?[]const u8,

    pub fn deinit(self: *CargoBuildPlan, allocator: std.mem.Allocator) void {
        self.args.deinit(allocator);
    }
};

pub const EnvUpdate = struct {
    rustflags_value: []const u8,
    linker_key: ?[]const u8,
    linker_value: ?[]const u8,
    owned: std.ArrayList([]const u8),

    pub fn init() EnvUpdate {
        return .{
            .rustflags_value = "",
            .linker_key = null,
            .linker_value = null,
            .owned = .empty,
        };
    }

    pub fn deinit(self: *EnvUpdate, allocator: std.mem.Allocator) void {
        for (self.owned.items) |item| allocator.free(item);
        self.owned.deinit(allocator);
    }
};

pub fn buildRustArgs(
    allocator: std.mem.Allocator,
    source_path: []const u8,
    options: common.CompileOptions,
    remap_prefix: ?[]const u8,
) !argv_builder.ArgvBuild {
    var args = argv_builder.ArgvBuild.init();

    const linker_arg = try std.fmt.allocPrint(allocator, "linker={s}", .{options.zig_path});
    try args.owned.append(allocator, linker_arg);
    try args.argv.appendSlice(allocator, &[_][]const u8{
        options.rustc_path,
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

    if (options.lib_dirs.len != 0) {
        for (options.lib_dirs) |dir| {
            try args.argv.append(allocator, "-L");
            try args.argv.append(allocator, dir);
        }
    }

    if (options.link_libs.len != 0) {
        for (options.link_libs) |lib| {
            try args.argv.append(allocator, "-l");
            try args.argv.append(allocator, lib);
        }
    }

    if (options.env.target) |target| {
        const resolved = try target_builder.resolveTarget(allocator, target, options.env.kernel_version);
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

pub fn buildCargoPlan(
    allocator: std.mem.Allocator,
    options: common.CompileOptions,
) !CargoBuildPlan {
    var args = argv_builder.ArgvBuild.init();
    var target_value: ?[]const u8 = null;

    try args.argv.appendSlice(allocator, &[_][]const u8{ options.cargo_path, "build" });
    if (options.cargo_release) try args.argv.append(allocator, "--release");
    if (options.cargo_manifest_path) |manifest| {
        try args.argv.append(allocator, "--manifest-path");
        try args.argv.append(allocator, manifest);
    }

    if (options.env.target) |target| {
        const resolved = try target_builder.resolveTarget(allocator, target, options.env.kernel_version);
        if (resolved.owned) |value| try args.owned.append(allocator, value);
        target_value = resolved.value;
        try args.argv.append(allocator, "--target");
        try args.argv.append(allocator, resolved.value);
    }

    return .{ .args = args, .target_value = target_value };
}

pub fn buildCargoEnvUpdate(
    allocator: std.mem.Allocator,
    options: common.CompileOptions,
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
        update.linker_value = options.zig_path;
    }

    return update;
}

fn buildRustFlags(
    allocator: std.mem.Allocator,
    options: common.CompileOptions,
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

    if (options.lib_dirs.len != 0) {
        for (options.lib_dirs) |dir| {
            const lib_arg = try std.fmt.allocPrint(allocator, "-L {s}", .{dir});
            try owned.append(allocator, lib_arg);
            try parts.append(allocator, lib_arg);
        }
    }

    if (options.link_libs.len != 0) {
        for (options.link_libs) |lib| {
            const lib_arg = try std.fmt.allocPrint(allocator, "-l {s}", .{lib});
            try owned.append(allocator, lib_arg);
            try parts.append(allocator, lib_arg);
        }
    }

    if (remap_prefix) |prefix| {
        const mapping = try std.fmt.allocPrint(allocator, "{s}={s}", .{ prefix, remap_dest });
        try owned.append(allocator, mapping);
        try parts.append(allocator, "--remap-path-prefix");
        try parts.append(allocator, mapping);
    }

    if (options.rustflags_extra.len != 0) {
        for (options.rustflags_extra) |flag| {
            try parts.append(allocator, flag);
        }
    }

    return try std.mem.join(allocator, " ", parts.items);
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

fn argvHasPair(argv: []const []const u8, first: []const u8, second: []const u8) bool {
    if (argv.len < 2) return false;
    var i: usize = 0;
    while (i + 1 < argv.len) : (i += 1) {
        if (std.mem.eql(u8, argv[i], first) and std.mem.eql(u8, argv[i + 1], second)) return true;
    }
    return false;
}

test "buildRustArgs uses kernel suffix for linux-gnu target" {
    const allocator = std.testing.allocator;
    const options = common.CompileOptions{
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
    const options = common.CompileOptions{
        .env = .{
            .target = "x86_64-windows-gnu",
            .kernel_version = "5.10",
        },
    };
    var args = try buildRustArgs(allocator, "main.rs", options, null);
    defer args.deinit(allocator);

    try std.testing.expect(argvHasPair(args.argv.items, "--target", "x86_64-windows-gnu"));
}

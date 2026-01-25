const std = @import("std");
const core = @import("../../root.zig");
const deterministic_flags = @import("../deterministic/flags.zig");
const toolchain = @import("../toolchain_resolver.zig");
const build_env = @import("../build_env.zig");
const build_types = @import("../build_types.zig");

pub fn buildC(allocator: std.mem.Allocator, cwd: std.fs.Dir, stdout: anytype, inputs: build_types.BuildInputs) !void {
    const zig_path = toolchain.resolveOrBootstrapZig(
        allocator,
        cwd,
        stdout,
        inputs.zig_version,
        inputs.bootstrap_sources.zig,
        inputs.bootstrap_seed,
    ) catch return;
    defer allocator.free(zig_path);
    var env_holder = try build_env.initEnvHolder(allocator, inputs.isolation_level, &[_][]const u8{zig_path});
    defer env_holder.deinit();

    var extra_args = std.ArrayList([]const u8).empty;
    defer extra_args.deinit(allocator);
    if (inputs.deterministic_level) |level| {
        try extra_args.appendSlice(allocator, deterministic_flags.DeterministicFlags.forZig(level));
        try extra_args.appendSlice(allocator, deterministic_flags.DeterministicFlags.forC(level));
    }
    if (inputs.remap_prefix) |prefix| {
        try extra_args.appendSlice(allocator, &[_][]const u8{ "--remap-path-prefix", prefix });
    }
    const options = core.toolchain_common.CompileOptions{
        .output_name = inputs.output_name,
        .static = true,
        .zig_path = zig_path,
        .env = inputs.env,
        .cross_target = inputs.cross_target,
        .include_dirs = inputs.include_dirs,
        .lib_dirs = inputs.lib_dirs,
        .link_libs = inputs.link_libs,
        .extra_sources = inputs.extra_sources,
        .extra_args = extra_args.items,
        .env_map = env_holder.envMap(),
    };
    const driver = core.toolchain_cross.zig_driver.ZigDriver.init(allocator, cwd);
    try driver.compileC(inputs.path, options);
}

pub fn buildCpp(allocator: std.mem.Allocator, cwd: std.fs.Dir, stdout: anytype, inputs: build_types.BuildInputs) !void {
    const zig_path = toolchain.resolveOrBootstrapZig(
        allocator,
        cwd,
        stdout,
        inputs.zig_version,
        inputs.bootstrap_sources.zig,
        inputs.bootstrap_seed,
    ) catch return;
    defer allocator.free(zig_path);
    var env_holder = try build_env.initEnvHolder(allocator, inputs.isolation_level, &[_][]const u8{zig_path});
    defer env_holder.deinit();

    var extra_args = std.ArrayList([]const u8).empty;
    defer extra_args.deinit(allocator);
    if (inputs.deterministic_level) |level| {
        try extra_args.appendSlice(allocator, deterministic_flags.DeterministicFlags.forZig(level));
        try extra_args.appendSlice(allocator, deterministic_flags.DeterministicFlags.forC(level));
    }
    if (inputs.remap_prefix) |prefix| {
        try extra_args.appendSlice(allocator, &[_][]const u8{ "--remap-path-prefix", prefix });
    }
    const options = core.toolchain_common.CompileOptions{
        .output_name = inputs.output_name,
        .static = true,
        .zig_path = zig_path,
        .env = inputs.env,
        .cross_target = inputs.cross_target,
        .include_dirs = inputs.include_dirs,
        .lib_dirs = inputs.lib_dirs,
        .link_libs = inputs.link_libs,
        .extra_sources = inputs.extra_sources,
        .extra_args = extra_args.items,
        .env_map = env_holder.envMap(),
    };
    const driver = core.toolchain_cross.zig_driver.ZigDriver.init(allocator, cwd);
    try driver.compileCpp(inputs.path, options);
}

const std = @import("std");
const core = @import("../../root.zig");
const common = @import("../common.zig");
const embed = @import("../packaging/embed.zig");
const toolchain = @import("../../cli/toolchain_resolver.zig");
const build_env = @import("../executor/env.zig");
const build_types = @import("../types.zig");

pub fn buildRust(allocator: std.mem.Allocator, cwd: std.fs.Dir, stdout: anytype, inputs: build_types.BuildInputs) !void {
    const zig_path = toolchain.resolveOrBootstrapZig(
        allocator,
        cwd,
        stdout,
        inputs.zig_version,
        inputs.bootstrap_sources.zig,
        inputs.bootstrap_seed,
    ) catch return;
    defer allocator.free(zig_path);
    var rust_paths = toolchain.resolveOrBootstrapRust(
        allocator,
        cwd,
        stdout,
        inputs.rust_version,
        inputs.bootstrap_sources.rust,
    ) catch return;
    defer rust_paths.deinit(allocator);

    var env_holder = try build_env.initEnvHolder(
        allocator,
        inputs.isolation_level,
        &[_][]const u8{ zig_path, rust_paths.rustc },
    );
    defer env_holder.deinit();

    try embed.prepareRustEmbeds(
        allocator,
        cwd,
        rust_paths.rustc,
        inputs.rust_embeds,
        inputs.rustc_extra_args,
        inputs.rustflags_extra,
        inputs.owned,
    );

    const options = core.toolchain_common.CompileOptions{
        .output_name = inputs.output_name,
        .static = true,
        .zig_path = zig_path,
        .rustc_path = rust_paths.rustc,
        .rust_crt_static = inputs.static_libc_enabled,
        .env = inputs.env,
        .cross_target = inputs.cross_target,
        .lib_dirs = inputs.lib_dirs,
        .link_libs = inputs.link_libs,
        .extra_args = inputs.rustc_extra_args.items,
    };
    const remap_prefix = if (inputs.remap_prefix) |prefix| prefix else try common.getRemapPrefix(allocator, cwd);
    if (inputs.remap_prefix == null) {
        defer if (remap_prefix) |prefix| allocator.free(prefix);
    }
    var args = try core.toolchain_builder_rust.buildRustArgs(allocator, inputs.path, options, remap_prefix);
    defer args.deinit(allocator);
    const env_map = env_holder.envMap();
    try core.toolchain_executor.ensureSourceDateEpoch(env_map);
    try core.toolchain_executor.runWithEnvMap(allocator, cwd, args.argv.items, inputs.env, env_map);
}

pub fn buildCargo(allocator: std.mem.Allocator, cwd: std.fs.Dir, stdout: anytype, inputs: build_types.BuildInputs) !void {
    const zig_path = toolchain.resolveOrBootstrapZig(
        allocator,
        cwd,
        stdout,
        inputs.zig_version,
        inputs.bootstrap_sources.zig,
        inputs.bootstrap_seed,
    ) catch return;
    defer allocator.free(zig_path);
    var rust_paths = toolchain.resolveOrBootstrapRust(
        allocator,
        cwd,
        stdout,
        inputs.rust_version,
        inputs.bootstrap_sources.rust,
    ) catch return;
    defer rust_paths.deinit(allocator);

    var env_holder = try build_env.initEnvHolder(
        allocator,
        inputs.isolation_level,
        &[_][]const u8{ zig_path, rust_paths.rustc, rust_paths.cargo },
    );
    defer env_holder.deinit();

    try embed.prepareRustEmbeds(
        allocator,
        cwd,
        rust_paths.rustc,
        inputs.rust_embeds,
        inputs.rustc_extra_args,
        inputs.rustflags_extra,
        inputs.owned,
    );

    const manifest_path = try common.resolveCargoManifestPath(allocator, cwd, inputs.path);
    defer allocator.free(manifest_path);
    const options = core.toolchain_common.CompileOptions{
        .zig_path = zig_path,
        .rustc_path = rust_paths.rustc,
        .cargo_path = rust_paths.cargo,
        .rust_crt_static = inputs.static_libc_enabled,
        .env = inputs.env,
        .cross_target = inputs.cross_target,
        .cargo_manifest_path = manifest_path,
        .lib_dirs = inputs.lib_dirs,
        .link_libs = inputs.link_libs,
        .rustflags_extra = inputs.rustflags_extra.items,
    };
    var plan = try core.toolchain_builder_rust.buildCargoPlan(allocator, options);
    defer plan.deinit(allocator);
    const env_map = env_holder.envMap();
    const existing_rustflags = env_map.get("RUSTFLAGS");
    const remap_prefix = if (inputs.remap_prefix) |prefix| prefix else try common.getRemapPrefix(allocator, cwd);
    if (inputs.remap_prefix == null) {
        defer if (remap_prefix) |prefix| allocator.free(prefix);
    }
    var env_update = try core.toolchain_builder_rust.buildCargoEnvUpdate(
        allocator,
        options,
        plan.target_value,
        existing_rustflags,
        remap_prefix,
    );
    defer env_update.deinit(allocator);
    try env_map.put("RUSTFLAGS", env_update.rustflags_value);
    if (env_update.linker_key) |key| {
        try env_map.put(key, env_update.linker_value.?);
    }
    try env_map.put("RUSTC", options.rustc_path);
    try core.toolchain_executor.ensureSourceDateEpoch(env_map);
    try core.toolchain_executor.runProcessWithEnv(allocator, cwd, plan.args.argv.items, env_map);
}

const std = @import("std");
const core = @import("../root.zig");
const common = @import("common.zig");
const embed = @import("embed_generator.zig");
const toolchain = @import("toolchain_resolver.zig");
const deterministic_env = @import("deterministic/env_isolate.zig");
const deterministic_flags = @import("deterministic/flags.zig");
const deterministic_order = @import("deterministic/order.zig");
const deterministic_path = @import("deterministic/path_normalize.zig");

pub const BuildInputs = struct {
    path: []const u8,
    output_name: []const u8,
    project_name: ?[]const u8,
    env: core.toolchain_common.VirtualEnv,
    cross_target: ?core.toolchain_cross.target.CrossTarget,
    include_dirs: []const []const u8,
    lib_dirs: []const []const u8,
    link_libs: []const []const u8,
    extra_sources: []const []const u8,
    rust_embeds: []const embed.RustEmbed,
    rustc_extra_args: *std.ArrayList([]const u8),
    rustflags_extra: *std.ArrayList([]const u8),
    owned: *std.ArrayList([]const u8),
    deterministic_level: ?core.protocol_types.DeterministicLevel,
    isolation_level: ?core.protocol_types.IsolationLevel,
    remap_prefix: ?[]const u8,
    zig_version: []const u8,
    rust_version: []const u8,
    bootstrap_sources: common.BootstrapSourceVersions,
    bootstrap_seed: ?common.BootstrapSeedSpec,
    static_libc_enabled: bool,
    verify_reproducible: bool,
    pack_format: ?core.protocol.PackOptions.Format,
};

const EnvHolder = struct {
    env_map: ?std.process.EnvMap = null,
    isolated: ?deterministic_env.IsolatedEnv = null,

    pub fn envMap(self: *EnvHolder) *std.process.EnvMap {
        if (self.isolated) |*isolated| return isolated.toEnvMap();
        return &self.env_map.?;
    }

    pub fn deinit(self: *EnvHolder) void {
        if (self.isolated) |*isolated| isolated.deinit();
        if (self.env_map) |*map| map.deinit();
    }
};

fn initEnvHolder(
    allocator: std.mem.Allocator,
    isolation_level: ?core.protocol_types.IsolationLevel,
    toolchain_paths: []const []const u8,
) !EnvHolder {
    if (isolation_level) |level| {
        if (level == .None) {
            return .{ .env_map = try core.toolchain_executor.getEnvMap(allocator) };
        }
        var isolated = try deterministic_env.IsolatedEnv.init(allocator, level);
        for (toolchain_paths) |path| {
            const dir = std.fs.path.dirname(path) orelse path;
            try isolated.addToolchain(dir);
        }
        return .{ .isolated = isolated };
    }
    return .{ .env_map = try core.toolchain_executor.getEnvMap(allocator) };
}

fn applyDeterministicFlags(
    allocator: std.mem.Allocator,
    inputs: *BuildInputs,
    level: core.protocol_types.DeterministicLevel,
) !void {
    const rust_flags = deterministic_flags.DeterministicFlags.forRust(level);
    try inputs.rustc_extra_args.appendSlice(allocator, rust_flags);
    try inputs.rustflags_extra.appendSlice(allocator, rust_flags);
}

fn sortPathsByNormalized(
    allocator: std.mem.Allocator,
    normalizer: *deterministic_path.PathNormalizer,
    paths: []const []const u8,
    owned: *std.ArrayList([]const u8),
) !void {
    if (paths.len < 2) return;

    var keys = try allocator.alloc([]const u8, paths.len);
    defer allocator.free(keys);

    for (paths, 0..) |path, idx| {
        const key = try normalizer.normalize(path);
        try owned.append(allocator, key);
        keys[idx] = key;
    }

    const indices = try allocator.alloc(usize, paths.len);
    defer allocator.free(indices);
    for (indices, 0..) |*slot, idx| slot.* = idx;

    std.sort.insertion(usize, indices, keys, struct {
        fn lessThan(keys_ctx: []const []const u8, a: usize, b: usize) bool {
            return std.mem.lessThan(u8, keys_ctx[a], keys_ctx[b]);
        }
    }.lessThan);

    var reordered = try allocator.alloc([]const u8, paths.len);
    defer allocator.free(reordered);
    for (indices, 0..) |idx, pos| reordered[pos] = paths[idx];
    std.mem.copyForwards([]const u8, @constCast(paths), reordered);
}

pub fn executeBuild(
    allocator: std.mem.Allocator,
    cwd: std.fs.Dir,
    stdout: anytype,
    inputs: BuildInputs,
) !void {
    var effective_inputs = inputs;

    if (inputs.deterministic_level) |level| {
        try applyDeterministicFlags(allocator, &effective_inputs, level);

        var normalizer = try deterministic_path.PathNormalizer.init(allocator, cwd, "/build");
        defer normalizer.deinit();

        const remap_prefix = try normalizer.getRemapArg();
        try effective_inputs.owned.append(allocator, remap_prefix);
        effective_inputs.remap_prefix = remap_prefix;

        if (effective_inputs.include_dirs.len != 0) {
            try sortPathsByNormalized(allocator, &normalizer, effective_inputs.include_dirs, effective_inputs.owned);
        }
        if (effective_inputs.lib_dirs.len != 0) {
            try sortPathsByNormalized(allocator, &normalizer, effective_inputs.lib_dirs, effective_inputs.owned);
        }
        if (effective_inputs.extra_sources.len != 0) {
            try sortPathsByNormalized(allocator, &normalizer, effective_inputs.extra_sources, effective_inputs.owned);
        }
        if (effective_inputs.link_libs.len != 0) {
            deterministic_order.DeterministicOrder.sortLibs(@constCast(effective_inputs.link_libs));
        }
    }

    if (std.mem.endsWith(u8, effective_inputs.path, ".c")) {
        try buildC(allocator, cwd, stdout, effective_inputs);
    } else if (std.mem.endsWith(u8, effective_inputs.path, ".cpp") or std.mem.endsWith(u8, effective_inputs.path, ".cc") or std.mem.endsWith(u8, effective_inputs.path, ".cxx")) {
        try buildCpp(allocator, cwd, stdout, effective_inputs);
    } else if (std.mem.endsWith(u8, effective_inputs.path, ".rs")) {
        try buildRust(allocator, cwd, stdout, effective_inputs);
    } else if (std.mem.endsWith(u8, effective_inputs.path, "Cargo.toml") or try common.containsCargoManifest(cwd, effective_inputs.path)) {
        try buildCargo(allocator, cwd, stdout, effective_inputs);
    } else {
        try stdout.print(">> TODO: BUILD supports only C/C++/Rust sources or Cargo.toml for now.\n", .{});
        return;
    }

    try stdout.print(">> Build complete: {s}\n", .{inputs.output_name});
    try verifyStaticLinking(stdout, inputs.output_name);
    if (inputs.verify_reproducible) {
        try verifyReproducibility(allocator, cwd, stdout, inputs.output_name);
    }
    if (inputs.pack_format) |format| {
        try packOutput(allocator, cwd, stdout, inputs.output_name, inputs.project_name, format);
    }
}

fn buildC(allocator: std.mem.Allocator, cwd: std.fs.Dir, stdout: anytype, inputs: BuildInputs) !void {
    const zig_path = toolchain.resolveOrBootstrapZig(
        allocator,
        cwd,
        stdout,
        inputs.zig_version,
        inputs.bootstrap_sources.zig,
        inputs.bootstrap_seed,
    ) catch return;
    defer allocator.free(zig_path);
    var env_holder = try initEnvHolder(allocator, inputs.isolation_level, &[_][]const u8{zig_path});
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

fn buildCpp(allocator: std.mem.Allocator, cwd: std.fs.Dir, stdout: anytype, inputs: BuildInputs) !void {
    const zig_path = toolchain.resolveOrBootstrapZig(
        allocator,
        cwd,
        stdout,
        inputs.zig_version,
        inputs.bootstrap_sources.zig,
        inputs.bootstrap_seed,
    ) catch return;
    defer allocator.free(zig_path);
    var env_holder = try initEnvHolder(allocator, inputs.isolation_level, &[_][]const u8{zig_path});
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

fn buildRust(allocator: std.mem.Allocator, cwd: std.fs.Dir, stdout: anytype, inputs: BuildInputs) !void {
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

    var env_holder = try initEnvHolder(
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

fn buildCargo(allocator: std.mem.Allocator, cwd: std.fs.Dir, stdout: anytype, inputs: BuildInputs) !void {
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

    var env_holder = try initEnvHolder(
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

fn verifyStaticLinking(stdout: anytype, output_name: []const u8) !void {
    core.toolchain_static.verifyNoSharedDeps(output_name) catch |err| {
        switch (err) {
            error.UnsupportedBinary,
            error.UnsupportedEndianness,
            => {
                try stdout.print(">> Static verification skipped: unsupported binary format.\n", .{});
            },
            error.SharedDependenciesFound => {
                try stdout.print("!! Static verification failed: shared dependencies detected.\n", .{});
                return err;
            },
            else => return err,
        }
    };
}

fn verifyReproducibility(
    allocator: std.mem.Allocator,
    cwd: std.fs.Dir,
    stdout: anytype,
    output_name: []const u8,
) !void {
    try core.reproducibility_verifier.generateBuildManifest();
    try common.ensureReproDir(cwd);
    const repro_path = try std.fs.path.join(allocator, &[_][]const u8{ ".knx", "repro", output_name });
    defer allocator.free(repro_path);
    if (common.exists(cwd, repro_path)) {
        const matches = try core.reproducibility_verifier.compareBinaries(output_name, repro_path);
        if (!matches) {
            try stdout.print("!! Reproducibility check failed: output differs from baseline.\n", .{});
            return error.ReproducibleMismatch;
        }
        try stdout.print(">> Reproducibility check: OK\n", .{});
    } else {
        try common.copyFile(cwd, output_name, repro_path);
        try stdout.print(">> Reproducibility baseline stored: {s}\n", .{repro_path});
    }
}

pub fn packOutput(
    allocator: std.mem.Allocator,
    cwd: std.fs.Dir,
    stdout: anytype,
    output_name: []const u8,
    project_name: ?[]const u8,
    format: core.protocol.PackOptions.Format,
) !void {
    if (!common.exists(cwd, output_name)) {
        try stdout.print("!! PACK requested but output not found: {s}\n", .{output_name});
        return;
    }

    cwd.makePath("dist") catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };

    const base = project_name orelse output_name;
    const archive_name = try std.fmt.allocPrint(
        allocator,
        "{s}-{s}-{s}.{s}",
        .{
            base,
            core.toolchain_manager.hostOsName(),
            core.toolchain_manager.hostArchName(),
            if (format == .TarGz) "tar.gz" else "zip",
        },
    );
    defer allocator.free(archive_name);

    const archive_path = try std.fs.path.join(allocator, &[_][]const u8{ "dist", archive_name });
    defer allocator.free(archive_path);

    const mtime = core.archive.sourceDateEpochSeconds();
    if (format == .TarGz) {
        try core.archive.packTarGzSingleFile(allocator, cwd, output_name, archive_path, output_name, mtime);
    } else {
        try core.archive.packZipSingleFile(allocator, cwd, output_name, archive_path, output_name, mtime);
    }
    try stdout.print(">> Packed: {s}\n", .{archive_path});
}

const std = @import("std");
const core = @import("../root.zig");
const common = @import("common.zig");
const embed = @import("embed_generator.zig");
const toolchain = @import("toolchain_resolver.zig");

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
    zig_version: []const u8,
    rust_version: []const u8,
    bootstrap_sources: common.BootstrapSourceVersions,
    bootstrap_seed: ?common.BootstrapSeedSpec,
    static_libc_enabled: bool,
    verify_reproducible: bool,
    pack_format: ?core.protocol.PackOptions.Format,
};

pub fn executeBuild(
    allocator: std.mem.Allocator,
    cwd: std.fs.Dir,
    stdout: anytype,
    inputs: BuildInputs,
) !void {
    if (std.mem.endsWith(u8, inputs.path, ".c")) {
        try buildC(allocator, cwd, stdout, inputs);
    } else if (std.mem.endsWith(u8, inputs.path, ".cpp") or std.mem.endsWith(u8, inputs.path, ".cc") or std.mem.endsWith(u8, inputs.path, ".cxx")) {
        try buildCpp(allocator, cwd, stdout, inputs);
    } else if (std.mem.endsWith(u8, inputs.path, ".rs")) {
        try buildRust(allocator, cwd, stdout, inputs);
    } else if (std.mem.endsWith(u8, inputs.path, "Cargo.toml") or try common.containsCargoManifest(cwd, inputs.path)) {
        try buildCargo(allocator, cwd, stdout, inputs);
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
    const remap_prefix = try common.getRemapPrefix(allocator, cwd);
    defer if (remap_prefix) |prefix| allocator.free(prefix);
    var args = try core.toolchain_builder_rust.buildRustArgs(allocator, inputs.path, options, remap_prefix);
    defer args.deinit(allocator);
    var env_map = try core.toolchain_executor.getEnvMap(allocator);
    defer env_map.deinit();
    try core.toolchain_executor.ensureSourceDateEpoch(&env_map);
    try core.toolchain_executor.runWithEnvMap(allocator, cwd, args.argv.items, inputs.env, &env_map);
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
    var env_map = try core.toolchain_executor.getEnvMap(allocator);
    defer env_map.deinit();
    const existing_rustflags = env_map.get("RUSTFLAGS");
    const remap_prefix = try common.getRemapPrefix(allocator, cwd);
    defer if (remap_prefix) |prefix| allocator.free(prefix);
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
    try core.toolchain_executor.ensureSourceDateEpoch(&env_map);
    try core.toolchain_executor.runProcessWithEnv(allocator, cwd, plan.args.argv.items, &env_map);
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

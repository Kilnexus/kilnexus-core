const std = @import("std");
const core = @import("../root.zig");
const common = @import("common.zig");
const dependency = @import("dependency.zig");
const embed = @import("embed_generator.zig");
const toolchain = @import("toolchain_resolver.zig");
const builder = @import("build_executor.zig");
const manifest_types = @import("manifest_types.zig");
const manifest_parser = @import("manifest_parser.zig");

pub const Manifest = manifest_types.Manifest;

pub fn handle(allocator: std.mem.Allocator, cwd: std.fs.Dir, stdout: anytype, manifest_name: []const u8) !void {
    var manifest = try manifest_parser.parseManifest(allocator, cwd, stdout, manifest_name);
    defer manifest.deinit(allocator);

    if (manifest.build_path == null) {
        try stdout.print("!! No BUILD command found.\n", .{});
        return;
    }

    const path = manifest.build_path.?;
    if (!common.exists(cwd, path)) {
        try stdout.print("!! BUILD path not found: {s}\n", .{path});
        return;
    }

    if (manifest.project_kind) |kind| {
        try toolchain.bootstrapProjectToolchains(
            allocator,
            cwd,
            stdout,
            kind,
            manifest.bootstrap_versions,
            manifest.bootstrap_sources,
            manifest.bootstrap_seed,
        );
    }

    try dependency.ensureDepsDirs(cwd);

    var include_dirs = std.ArrayList([]const u8).empty;
    defer include_dirs.deinit(allocator);
    var lib_dirs = std.ArrayList([]const u8).empty;
    defer lib_dirs.deinit(allocator);
    var link_libs = std.ArrayList([]const u8).empty;
    defer link_libs.deinit(allocator);
    var extra_sources = std.ArrayList([]const u8).empty;
    defer extra_sources.deinit(allocator);
    var rustc_extra_args = std.ArrayList([]const u8).empty;
    defer rustc_extra_args.deinit(allocator);
    var rustflags_extra = std.ArrayList([]const u8).empty;
    defer rustflags_extra.deinit(allocator);
    var rust_embeds = std.ArrayList(embed.RustEmbed).empty;
    defer rust_embeds.deinit(allocator);
    var owned = std.ArrayList([]const u8).empty;
    defer {
        for (owned.items) |item| allocator.free(item);
        owned.deinit(allocator);
    }

    for (manifest.uses.items) |dep| {
        const resolved = try dependency.ensureDependency(allocator, cwd, stdout, dep, &owned);
        if (dep.strategy != .Embed) {
            if (resolved.include_dir) |inc| try include_dirs.append(allocator, inc);
            if (resolved.lib_dir) |lib| try lib_dirs.append(allocator, lib);
            if (dep.strategy == .Static and resolved.lib_dir != null) {
                const static_libs = try dependency.extractStaticLibs(resolved.lib_dir.?);
                defer dependency.freeStaticLibs(static_libs);
                if (static_libs.len != 0) {
                    for (static_libs) |lib_path| {
                        const name = std.fs.path.basename(lib_path);
                        const arg = try std.fmt.allocPrint(allocator, ":{s}", .{name});
                        try owned.append(allocator, arg);
                        try link_libs.append(allocator, arg);
                    }
                } else {
                    try link_libs.append(allocator, dep.name);
                }
            } else {
                try link_libs.append(allocator, dep.name);
            }
        } else {
            if (resolved.embed_dir) |embed_dir| {
                const alias = dep.alias orelse dep.name;
                const c_result = try embed.generateCEmbed(allocator, cwd, embed_dir, alias, &owned);
                if (c_result.c_path) |c_path| try extra_sources.append(allocator, c_path);
                if (c_result.include_dir) |inc_dir| try include_dirs.append(allocator, inc_dir);
                if (c_result.rust_embed) |rust_embed| try rust_embeds.append(allocator, rust_embed);
            } else {
                try stdout.print(">> USE {s}:{s} has no embed/ or assets/ directory.\n", .{ dep.name, dep.version });
            }
        }
    }

    var static_libc_root: ?[]const u8 = null;
    if (manifest.static_libc) |libc| {
        if (std.ascii.eqlIgnoreCase(libc.name, "musl") and manifest.bootstrap_sources.musl != null) {
            const spec = manifest.bootstrap_sources.musl.?;
            const version = spec.version;
            try core.toolchain_source_builder.buildMuslFromSource(version, spec.sha256);
            const root = try std.fs.path.join(allocator, &[_][]const u8{ ".knx", "toolchains", "musl", version });
            try owned.append(allocator, root);
            static_libc_root = root;
            if (try dependency.resolveOptionalChild(allocator, cwd, root, "include", &owned)) |inc| try include_dirs.append(allocator, inc);
            if (try dependency.resolveOptionalChild(allocator, cwd, root, "lib", &owned)) |lib| try lib_dirs.append(allocator, lib);
        } else {
            const resolved = try dependency.ensureDependency(allocator, cwd, stdout, .{
                .name = libc.name,
                .version = libc.version,
                .alias = null,
                .strategy = .Static,
            }, &owned);
            if (resolved.include_dir) |inc| try include_dirs.append(allocator, inc);
            if (resolved.lib_dir) |lib| try lib_dirs.append(allocator, lib);
            static_libc_root = resolved.root;
        }
        if (manifest.sysroot_spec == null and static_libc_root != null) {
            manifest.sysroot_spec = .{ .source = .ExternalPath, .path = static_libc_root };
        }
    }

    var sysroot_path: ?[]const u8 = null;
    if (manifest.sysroot_spec) |spec| {
        var config = try core.toolchain_cross.sysroot.resolveSysroot(
            allocator,
            manifest.target,
            spec,
            static_libc_root,
        );
        defer config.deinit(allocator);
        sysroot_path = config.root;
        if (config.include_dirs.items.len != 0) {
            for (config.include_dirs.items) |dir| try include_dirs.append(allocator, dir);
        }
        if (config.lib_dirs.items.len != 0) {
            for (config.lib_dirs.items) |dir| try lib_dirs.append(allocator, dir);
        }
    }

    const output_name = manifest.project_name orelse "Kilnexus-out";
    var virtual_root = manifest.virtual_root;
    if (manifest.sandbox_build and virtual_root == null) {
        const sandbox_root = ".knx/sandbox";
        try cwd.makePath(sandbox_root);
        virtual_root = sandbox_root;
    }
    const env = core.toolchain_common.VirtualEnv{
        .target = if (manifest.target) |target| target.toZigTarget() else null,
        .kernel_version = manifest.kernel_version,
        .sysroot = sysroot_path,
        .virtual_root = virtual_root,
    };

    const inputs = builder.BuildInputs{
        .path = path,
        .output_name = output_name,
        .project_name = manifest.project_name,
        .knxfile_path = manifest_name,
        .env = env,
        .cross_target = manifest.target,
        .include_dirs = include_dirs.items,
        .lib_dirs = lib_dirs.items,
        .link_libs = link_libs.items,
        .extra_sources = extra_sources.items,
        .rust_embeds = rust_embeds.items,
        .rustc_extra_args = &rustc_extra_args,
        .rustflags_extra = &rustflags_extra,
        .owned = &owned,
        .deterministic_level = manifest.deterministic_level,
        .isolation_level = manifest.isolation_level,
        .remap_prefix = null,
        .zig_version = manifest.bootstrap_versions.zig orelse core.toolchain_manager.default_zig_version,
        .rust_version = manifest.bootstrap_versions.rust orelse core.toolchain_manager.default_rust_version,
        .bootstrap_sources = manifest.bootstrap_sources,
        .bootstrap_seed = manifest.bootstrap_seed,
        .static_libc_enabled = manifest.static_libc != null,
        .verify_reproducible = manifest.verify_reproducible,
        .pack_format = manifest.pack_format,
    };
    try builder.executeBuild(allocator, cwd, stdout, inputs);
}

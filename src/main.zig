const std = @import("std");
const core = @import("root.zig");

pub fn main() !void {
    var stdout_buffer: [32 * 1024]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;
    defer stdout.flush() catch {};
    try stdout.print("KILNEXUS CLI v0.0.1 [Constructing...]\n", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var cwd = std.fs.cwd();
    try core.toolchain_manager.ensureProjectCache(cwd);
    const has_manifest = if (cwd.access("Kilnexusfile", .{})) |_| true else |err| switch (err) {
        error.FileNotFound => false,
        else => return err,
    };

    if (has_manifest) {
        try stdout.print(">> Detected Kilnexusfile. Parsing protocol...\n", .{});
        try handleManifest(allocator, cwd, stdout);
    } else {
        try stdout.print(">> No manifest. Initiating Inference Engine...\n", .{});
        const project_type = try core.inference.detect(cwd);
        try core.strategy.buildInferred(allocator, project_type, cwd);
    }
}

const UseSpec = struct {
    name: []const u8,
    version: []const u8,
    alias: ?[]const u8,
    strategy: core.protocol.UseDependency.Strategy,
};

const Manifest = struct {
    project_name: ?[]const u8 = null,
    project_kind: ?core.protocol.ProjectKind = null,
    target: ?[]const u8 = null,
    kernel_version: ?[]const u8 = null,
    sysroot: ?[]const u8 = null,
    virtual_root: ?[]const u8 = null,
    build_path: ?[]const u8 = null,
    pack_format: ?core.protocol.PackOptions.Format = null,
    uses: std.ArrayList(UseSpec) = .empty,
    bootstrap_versions: BootstrapVersions = .{},

    fn deinit(self: *Manifest, allocator: std.mem.Allocator) void {
        self.uses.deinit(allocator);
    }
};

const RustEmbed = struct {
    alias: []const u8,
    rs_path: []const u8,
    rlib_path: []const u8,
};

fn handleManifest(allocator: std.mem.Allocator, cwd: std.fs.Dir, stdout: anytype) !void {
    const file = try cwd.openFile("Kilnexusfile", .{});
    defer file.close();

    const source = try file.readToEndAlloc(allocator, 1024 * 1024);
    defer allocator.free(source);

    var parser = core.protocol.KilnexusParser.init(allocator, source);
    var manifest = Manifest{};
    defer manifest.deinit(allocator);

    while (true) {
        const cmd = parser.next() catch |err| {
            try stdout.print("!! Kilnexusfile syntax error at line {d}: {s}\n", .{
                parser.currentLine(),
                core.protocol_error.parserErrorMessage(err),
            });
            const line_text = parser.currentLineText();
            if (line_text.len > 0) {
                try stdout.print("!!   {s}\n", .{line_text});
                const caret_line = core.protocol_error.formatCaretLine(allocator, parser.currentErrorColumn()) catch "";
                defer if (caret_line.len > 0) allocator.free(caret_line);
                if (caret_line.len > 0) {
                    try stdout.print("!!   {s}\n", .{caret_line});
                }
            }
            return err;
        } orelse break;
        switch (cmd) {
            .Project => |spec| {
                manifest.project_name = spec.name;
                if (spec.kind) |kind| manifest.project_kind = kind;
            },
            .Target => |value| manifest.target = value,
            .Kernel => |value| manifest.kernel_version = value,
            .Sysroot => |value| manifest.sysroot = value,
            .VirtualRoot => |value| manifest.virtual_root = value,
            .Build => |path| manifest.build_path = path,
            .Bootstrap => |boot| switch (boot.tool) {
                .Zig => manifest.bootstrap_versions.zig = boot.version,
                .Rust => manifest.bootstrap_versions.rust = boot.version,
                .Go => manifest.bootstrap_versions.go = boot.version,
            },
            .Use => |spec| try manifest.uses.append(allocator, .{
                .name = spec.name,
                .version = spec.version,
                .alias = spec.alias,
                .strategy = spec.strategy,
            }),
            .Pack => |pack| manifest.pack_format = pack.format,
        }
    }

    if (manifest.build_path == null) {
        try stdout.print("!! No BUILD command found.\n", .{});
        return;
    }

    const path = manifest.build_path.?;
    if (!exists(cwd, path)) {
        try stdout.print("!! BUILD path not found: {s}\n", .{path});
        return;
    }

    if (manifest.project_kind) |kind| {
        try bootstrapProjectToolchains(allocator, cwd, stdout, kind, manifest.bootstrap_versions);
    }

    try ensureDepsDirs(cwd);

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
    var rust_embeds = std.ArrayList(RustEmbed).empty;
    defer rust_embeds.deinit(allocator);
    var owned = std.ArrayList([]const u8).empty;
    defer {
        for (owned.items) |item| allocator.free(item);
        owned.deinit(allocator);
    }

    for (manifest.uses.items) |dep| {
        const resolved = try ensureDependency(allocator, cwd, stdout, dep, &owned);
        if (dep.strategy != .Embed) {
            if (resolved.include_dir) |inc| try include_dirs.append(allocator, inc);
            if (resolved.lib_dir) |lib| try lib_dirs.append(allocator, lib);
            try link_libs.append(allocator, dep.name);
        } else {
            if (resolved.embed_dir) |embed_dir| {
                const alias = dep.alias orelse dep.name;
                const c_result = try generateCEmbed(allocator, cwd, embed_dir, alias, &owned);
                if (c_result.c_path) |c_path| try extra_sources.append(allocator, c_path);
                if (c_result.include_dir) |inc_dir| try include_dirs.append(allocator, inc_dir);
                if (c_result.rust_embed) |rust_embed| try rust_embeds.append(allocator, rust_embed);
            } else {
                try stdout.print(">> USE {s}:{s} has no embed/ or assets/ directory.\n", .{ dep.name, dep.version });
            }
        }
    }

    const output_name = manifest.project_name orelse "Kilnexus-out";
    const env = core.toolchain_common.VirtualEnv{
        .target = manifest.target,
        .kernel_version = manifest.kernel_version,
        .sysroot = manifest.sysroot,
        .virtual_root = manifest.virtual_root,
    };
    if (std.mem.endsWith(u8, path, ".c")) {
        const zig_version = manifest.bootstrap_versions.zig orelse core.toolchain_manager.default_zig_version;
        const zig_path = resolveOrBootstrapZig(allocator, cwd, stdout, zig_version) catch return;
        defer allocator.free(zig_path);
        const options = core.toolchain_common.CompileOptions{
            .output_name = output_name,
            .static = true,
            .zig_path = zig_path,
            .env = env,
            .include_dirs = include_dirs.items,
            .lib_dirs = lib_dirs.items,
            .link_libs = link_libs.items,
            .extra_sources = extra_sources.items,
        };
        var args = try core.toolchain_builder_zig.buildZigArgs(allocator, "cc", path, options);
        defer args.deinit(allocator);
        var env_map = try core.toolchain_executor.getEnvMap(allocator);
        defer env_map.deinit();
        try core.toolchain_executor.ensureSourceDateEpoch(&env_map);
        try core.toolchain_executor.runWithEnvMap(allocator, cwd, args.argv.items, env, &env_map);
    } else if (std.mem.endsWith(u8, path, ".cpp") or std.mem.endsWith(u8, path, ".cc") or std.mem.endsWith(u8, path, ".cxx")) {
        const zig_version = manifest.bootstrap_versions.zig orelse core.toolchain_manager.default_zig_version;
        const zig_path = resolveOrBootstrapZig(allocator, cwd, stdout, zig_version) catch return;
        defer allocator.free(zig_path);
        const options = core.toolchain_common.CompileOptions{
            .output_name = output_name,
            .static = true,
            .zig_path = zig_path,
            .env = env,
            .include_dirs = include_dirs.items,
            .lib_dirs = lib_dirs.items,
            .link_libs = link_libs.items,
            .extra_sources = extra_sources.items,
        };
        var args = try core.toolchain_builder_zig.buildZigArgs(allocator, "c++", path, options);
        defer args.deinit(allocator);
        var env_map = try core.toolchain_executor.getEnvMap(allocator);
        defer env_map.deinit();
        try core.toolchain_executor.ensureSourceDateEpoch(&env_map);
        try core.toolchain_executor.runWithEnvMap(allocator, cwd, args.argv.items, env, &env_map);
    } else if (std.mem.endsWith(u8, path, ".rs")) {
        const zig_version = manifest.bootstrap_versions.zig orelse core.toolchain_manager.default_zig_version;
        const rust_version = manifest.bootstrap_versions.rust orelse core.toolchain_manager.default_rust_version;
        const zig_path = resolveOrBootstrapZig(allocator, cwd, stdout, zig_version) catch return;
        defer allocator.free(zig_path);
        var rust_paths = resolveOrBootstrapRust(allocator, cwd, stdout, rust_version) catch return;
        defer rust_paths.deinit(allocator);
        try prepareRustEmbeds(allocator, cwd, rust_paths.rustc, rust_embeds.items, &rustc_extra_args, &rustflags_extra, &owned);
        const options = core.toolchain_common.CompileOptions{
            .output_name = output_name,
            .static = true,
            .zig_path = zig_path,
            .rustc_path = rust_paths.rustc,
            .env = env,
            .lib_dirs = lib_dirs.items,
            .link_libs = link_libs.items,
            .extra_args = rustc_extra_args.items,
        };
        const remap_prefix = try getRemapPrefix(allocator, cwd);
        defer if (remap_prefix) |prefix| allocator.free(prefix);
        var args = try core.toolchain_builder_rust.buildRustArgs(allocator, path, options, remap_prefix);
        defer args.deinit(allocator);
        var env_map = try core.toolchain_executor.getEnvMap(allocator);
        defer env_map.deinit();
        try core.toolchain_executor.ensureSourceDateEpoch(&env_map);
        try core.toolchain_executor.runWithEnvMap(allocator, cwd, args.argv.items, env, &env_map);
    } else if (std.mem.endsWith(u8, path, "Cargo.toml") or try containsCargoManifest(cwd, path)) {
        const zig_version = manifest.bootstrap_versions.zig orelse core.toolchain_manager.default_zig_version;
        const rust_version = manifest.bootstrap_versions.rust orelse core.toolchain_manager.default_rust_version;
        const zig_path = resolveOrBootstrapZig(allocator, cwd, stdout, zig_version) catch return;
        defer allocator.free(zig_path);
        var rust_paths = resolveOrBootstrapRust(allocator, cwd, stdout, rust_version) catch return;
        defer rust_paths.deinit(allocator);
        try prepareRustEmbeds(allocator, cwd, rust_paths.rustc, rust_embeds.items, &rustc_extra_args, &rustflags_extra, &owned);
        const manifest_path = try resolveCargoManifestPath(allocator, cwd, path);
        defer allocator.free(manifest_path);
        const options = core.toolchain_common.CompileOptions{
            .zig_path = zig_path,
            .rustc_path = rust_paths.rustc,
            .cargo_path = rust_paths.cargo,
            .env = env,
            .cargo_manifest_path = manifest_path,
            .lib_dirs = lib_dirs.items,
            .link_libs = link_libs.items,
            .rustflags_extra = rustflags_extra.items,
        };
        var plan = try core.toolchain_builder_rust.buildCargoPlan(allocator, options);
        defer plan.deinit(allocator);
        var env_map = try core.toolchain_executor.getEnvMap(allocator);
        defer env_map.deinit();
        const existing_rustflags = env_map.get("RUSTFLAGS");
        const remap_prefix = try getRemapPrefix(allocator, cwd);
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
    } else {
        try stdout.print(">> TODO: BUILD supports only C/C++/Rust sources or Cargo.toml for now.\n", .{});
        return;
    }

    try stdout.print(">> Build complete: {s}\n", .{output_name});

    if (manifest.pack_format) |format| {
        try packOutput(allocator, cwd, stdout, output_name, manifest.project_name, format);
    }
}

fn exists(dir: std.fs.Dir, filename: []const u8) bool {
    dir.access(filename, .{}) catch return false;
    return true;
}

fn ensureDepsDirs(cwd: std.fs.Dir) !void {
    cwd.makePath(".knx/deps") catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };
    cwd.makePath(".knx/gen") catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };
}

const DepResolve = struct {
    root: []const u8,
    include_dir: ?[]const u8,
    lib_dir: ?[]const u8,
    embed_dir: ?[]const u8,
};

fn ensureDependency(
    allocator: std.mem.Allocator,
    cwd: std.fs.Dir,
    stdout: anytype,
    dep: UseSpec,
    owned: *std.ArrayList([]const u8),
) !DepResolve {
    const dep_parent = try std.fs.path.join(allocator, &[_][]const u8{ ".knx", "deps", dep.name });
    try owned.append(allocator, dep_parent);
    const dep_root = try std.fs.path.join(allocator, &[_][]const u8{ dep_parent, dep.version });
    try owned.append(allocator, dep_root);

    if (!dirExists(cwd, dep_root)) {
        try cwd.makePath(dep_root);
        const archive_name = try std.fmt.allocPrint(allocator, "{s}.tar.gz", .{dep.version});
        try owned.append(allocator, archive_name);
        const archive_path = try std.fs.path.join(allocator, &[_][]const u8{ dep_parent, archive_name });
        try owned.append(allocator, archive_path);

        const url = try core.archive.buildRegistryUrl(allocator, dep.name, dep.version);
        defer allocator.free(url);
        try stdout.print(">> Fetching {s}:{s} from {s}\n", .{ dep.name, dep.version, url });
        try core.archive.downloadFile(allocator, url, archive_path);
        try core.archive.extractTarGz(allocator, archive_path, dep_root, 0);
        cwd.deleteFile(archive_path) catch {};
    }

    const include_dir = try resolveOptionalChild(allocator, cwd, dep_root, "include", owned);
    const lib_dir = try resolveOptionalChild(allocator, cwd, dep_root, "lib", owned);
    const embed_dir = blk: {
        if (try resolveOptionalChild(allocator, cwd, dep_root, "embed", owned)) |value| break :blk value;
        break :blk try resolveOptionalChild(allocator, cwd, dep_root, "assets", owned);
    };

    return .{
        .root = dep_root,
        .include_dir = include_dir,
        .lib_dir = lib_dir,
        .embed_dir = embed_dir,
    };
}

fn resolveOptionalChild(
    allocator: std.mem.Allocator,
    cwd: std.fs.Dir,
    root: []const u8,
    name: []const u8,
    owned: *std.ArrayList([]const u8),
) !?[]const u8 {
    const path = try std.fs.path.join(allocator, &[_][]const u8{ root, name });
    if (dirExists(cwd, path)) {
        try owned.append(allocator, path);
        return path;
    }
    allocator.free(path);
    return null;
}

fn dirExists(cwd: std.fs.Dir, path: []const u8) bool {
    var dir = cwd.openDir(path, .{}) catch return false;
    dir.close();
    return true;
}

const EmbedResult = struct {
    c_path: ?[]const u8 = null,
    include_dir: ?[]const u8 = null,
    rust_embed: ?RustEmbed = null,
};

fn generateCEmbed(
    allocator: std.mem.Allocator,
    cwd: std.fs.Dir,
    embed_dir: []const u8,
    alias: []const u8,
    owned: *std.ArrayList([]const u8),
) !EmbedResult {
    const gen_dir = ".knx/gen";
    const safe_alias = try sanitizeIdentifier(allocator, alias);
    defer allocator.free(safe_alias);
    const c_name = try std.fmt.allocPrint(allocator, "{s}_embed.c", .{safe_alias});
    try owned.append(allocator, c_name);
    const h_name = try std.fmt.allocPrint(allocator, "{s}_embed.h", .{safe_alias});
    try owned.append(allocator, h_name);

    const c_path = try std.fs.path.join(allocator, &[_][]const u8{ gen_dir, c_name });
    try owned.append(allocator, c_path);
    const h_path = try std.fs.path.join(allocator, &[_][]const u8{ gen_dir, h_name });
    try owned.append(allocator, h_path);

    var h_file = try cwd.createFile(h_path, .{ .truncate = true });
    defer h_file.close();
    var h_buf: [32 * 1024]u8 = undefined;
    var h_writer = h_file.writer(&h_buf);
    try h_writer.interface.writeAll("#pragma once\n#include <stddef.h>\n");

    var c_file = try cwd.createFile(c_path, .{ .truncate = true });
    defer c_file.close();
    var c_buf: [32 * 1024]u8 = undefined;
    var c_writer = c_file.writer(&c_buf);
    try c_writer.interface.print("#include \"{s}\"\n", .{h_name});

    var rust_embed: ?RustEmbed = null;
    const rust_path = try std.fmt.allocPrint(allocator, ".knx/gen/{s}_embed.rs", .{safe_alias});
    try owned.append(allocator, rust_path);
    var rust_file = try cwd.createFile(rust_path, .{ .truncate = true });
    defer rust_file.close();
    var rust_buf: [32 * 1024]u8 = undefined;
    var rust_writer = rust_file.writer(&rust_buf);

    const zig_path = try std.fmt.allocPrint(allocator, ".knx/gen/{s}.zig", .{safe_alias});
    try owned.append(allocator, zig_path);
    var zig_file = try cwd.createFile(zig_path, .{ .truncate = true });
    defer zig_file.close();
    var zig_buf: [32 * 1024]u8 = undefined;
    var zig_writer = zig_file.writer(&zig_buf);

    var dir = try cwd.openDir(embed_dir, .{ .iterate = true });
    defer dir.close();
    var walker = try dir.walk(allocator);
    defer walker.deinit();
    while (try walker.next()) |entry| {
        if (entry.kind != .file) continue;
        const sym = try buildSymbol(allocator, safe_alias, entry.path);
        defer allocator.free(sym);
        const file_path = try std.fs.path.join(allocator, &[_][]const u8{ embed_dir, entry.path });
        defer allocator.free(file_path);
        var file = try cwd.openFile(file_path, .{});
        defer file.close();
        const data = try file.readToEndAlloc(allocator, 16 * 1024 * 1024);
        defer allocator.free(data);

        try h_writer.interface.print("extern const unsigned char {s}[];\n", .{sym});
        try h_writer.interface.print("extern const size_t {s}_len;\n", .{sym});
        try c_writer.interface.print("const unsigned char {s}[] = {{", .{sym});
        for (data, 0..) |byte, i| {
            if (i % 12 == 0) try c_writer.interface.writeAll("\n  ");
            try c_writer.interface.print("0x{X:0>2}, ", .{byte});
        }
        try c_writer.interface.writeAll("\n};\n");
        try c_writer.interface.print("const size_t {s}_len = {d};\n", .{ sym, data.len });

        const abs_path = try cwd.realpathAlloc(allocator, file_path);
        defer allocator.free(abs_path);
        try rust_writer.interface.print("pub static {s}: &[u8] = include_bytes!(r#\"{s}\"#);\n", .{ sym, abs_path });
        try zig_writer.interface.print("pub const {s} = @embedFile(\"{s}\");\n", .{ sym, abs_path });
    }

    try h_writer.interface.flush();
    try c_writer.interface.flush();
    try rust_writer.interface.flush();
    try zig_writer.interface.flush();

    const rust_alias = try allocator.dupe(u8, safe_alias);
    try owned.append(allocator, rust_alias);
    rust_embed = .{
        .alias = rust_alias,
        .rs_path = rust_path,
        .rlib_path = try std.fmt.allocPrint(allocator, ".knx/gen/{s}_embed.rlib", .{safe_alias}),
    };
    try owned.append(allocator, rust_embed.?.rlib_path);

    return .{
        .c_path = c_path,
        .include_dir = gen_dir,
        .rust_embed = rust_embed,
    };
}

fn buildSymbol(allocator: std.mem.Allocator, prefix: []const u8, rel_path: []const u8) ![]const u8 {
    var buf = std.ArrayList(u8).empty;
    defer buf.deinit(allocator);
    try appendSanitized(&buf, allocator, prefix);
    try buf.append(allocator, '_');
    try appendSanitized(&buf, allocator, rel_path);
    return try buf.toOwnedSlice(allocator);
}

fn appendSanitized(buf: *std.ArrayList(u8), allocator: std.mem.Allocator, text: []const u8) !void {
    for (text) |ch| {
        if ((ch >= 'a' and ch <= 'z') or (ch >= 'A' and ch <= 'Z') or (ch >= '0' and ch <= '9')) {
            try buf.append(allocator, ch);
        } else {
            try buf.append(allocator, '_');
        }
    }
}

fn sanitizeIdentifier(allocator: std.mem.Allocator, text: []const u8) ![]const u8 {
    var buf = std.ArrayList(u8).empty;
    defer buf.deinit(allocator);
    try appendSanitized(&buf, allocator, text);
    return try buf.toOwnedSlice(allocator);
}

fn prepareRustEmbeds(
    allocator: std.mem.Allocator,
    cwd: std.fs.Dir,
    rustc_path: []const u8,
    embeds: []const RustEmbed,
    rustc_extra_args: *std.ArrayList([]const u8),
    rustflags_extra: *std.ArrayList([]const u8),
    owned: *std.ArrayList([]const u8),
) !void {
    for (embeds) |embed| {
        const args = &[_][]const u8{
            rustc_path,
            "--crate-type",
            "rlib",
            "--crate-name",
            embed.alias,
            embed.rs_path,
            "-o",
            embed.rlib_path,
        };
        try core.toolchain_executor.runProcess(allocator, cwd, args);
        const extern_arg = try std.fmt.allocPrint(allocator, "{s}={s}", .{ embed.alias, embed.rlib_path });
        try owned.append(allocator, extern_arg);
        try rustc_extra_args.appendSlice(allocator, &[_][]const u8{ "--extern", extern_arg });
        try rustflags_extra.appendSlice(allocator, &[_][]const u8{ "--extern", extern_arg });
    }
}

fn packOutput(
    allocator: std.mem.Allocator,
    cwd: std.fs.Dir,
    stdout: anytype,
    output_name: []const u8,
    project_name: ?[]const u8,
    format: core.protocol.PackOptions.Format,
) !void {
    if (!exists(cwd, output_name)) {
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

const BootstrapVersions = struct {
    zig: ?[]const u8 = null,
    rust: ?[]const u8 = null,
    go: ?[]const u8 = null,
};

const RustPaths = struct {
    rustc: []const u8,
    cargo: []const u8,

    fn deinit(self: *RustPaths, allocator: std.mem.Allocator) void {
        allocator.free(self.rustc);
        allocator.free(self.cargo);
    }
};

fn resolveOrBootstrapZig(allocator: std.mem.Allocator, cwd: std.fs.Dir, stdout: anytype, version: []const u8) ![]const u8 {
    return core.toolchain_manager.resolveZigPathForVersion(allocator, cwd, version) catch |err| {
        if (err != error.ToolchainMissing) return err;
        try stdout.print(">> Zig toolchain missing. Bootstrapping...\n", .{});
        core.toolchain_bootstrap.bootstrapZig(allocator, cwd, version) catch |boot_err| {
            switch (boot_err) {
                error.MinisignKeyIdMismatch,
                error.MinisignInvalidPublicKey,
                error.MinisignInvalidSignature,
                error.MinisignInvalidSignatureFile,
                error.SignatureVerificationFailed,
                => {
                    try stdout.print("!! Bootstrap failed: signature verification failed for {s} ({s}-{s}).\n", .{
                        version,
                        core.toolchain_manager.hostOsName(),
                        core.toolchain_manager.hostArchName(),
                    });
                },
                else => {
                    try stdout.print("!! Bootstrap failed: {s}\n", .{@errorName(boot_err)});
                },
            }
            try printToolchainHints(allocator, stdout, version);
            return error.ToolchainMissing;
        };
        return try core.toolchain_manager.resolveZigPathForVersion(allocator, cwd, version);
    };
}

fn resolveOrBootstrapRust(allocator: std.mem.Allocator, cwd: std.fs.Dir, stdout: anytype, version: []const u8) !RustPaths {
    const rustc_path = core.toolchain_manager.resolveRustcPathForVersion(allocator, cwd, version) catch |err| blk: {
        if (err != error.ToolchainMissing) return err;
        try stdout.print(">> Rust toolchain missing. Bootstrapping...\n", .{});
        core.toolchain_bootstrap.bootstrapRust(allocator, cwd, version) catch |boot_err| {
            try stdout.print("!! Bootstrap failed: {s}\n", .{@errorName(boot_err)});
            return error.ToolchainMissing;
        };
        break :blk try core.toolchain_manager.resolveRustcPathForVersion(allocator, cwd, version);
    };
    errdefer allocator.free(rustc_path);

    const cargo_path = core.toolchain_manager.resolveCargoPathForVersion(allocator, cwd, version) catch |err| blk: {
        if (err != error.ToolchainMissing) return err;
        try stdout.print(">> Rust toolchain missing. Bootstrapping...\n", .{});
        core.toolchain_bootstrap.bootstrapRust(allocator, cwd, version) catch |boot_err| {
            try stdout.print("!! Bootstrap failed: {s}\n", .{@errorName(boot_err)});
            return error.ToolchainMissing;
        };
        break :blk try core.toolchain_manager.resolveCargoPathForVersion(allocator, cwd, version);
    };

    return .{
        .rustc = rustc_path,
        .cargo = cargo_path,
    };
}

fn resolveOrBootstrapGo(allocator: std.mem.Allocator, cwd: std.fs.Dir, stdout: anytype, version: []const u8) ![]const u8 {
    return core.toolchain_manager.resolveGoPathForVersion(allocator, cwd, version) catch |err| {
        if (err != error.ToolchainMissing) return err;
        try stdout.print(">> Go toolchain missing. Bootstrapping...\n", .{});
        core.toolchain_bootstrap.bootstrapGo(allocator, cwd, version) catch |boot_err| {
            try stdout.print("!! Bootstrap failed: {s}\n", .{@errorName(boot_err)});
            return error.ToolchainMissing;
        };
        return try core.toolchain_manager.resolveGoPathForVersion(allocator, cwd, version);
    };
}

fn bootstrapProjectToolchains(
    allocator: std.mem.Allocator,
    cwd: std.fs.Dir,
    stdout: anytype,
    project_kind: core.protocol.ProjectKind,
    versions: BootstrapVersions,
) !void {
    switch (project_kind) {
        .Rust => {
            const zig_path = try resolveOrBootstrapZig(allocator, cwd, stdout, versions.zig orelse core.toolchain_manager.default_zig_version);
            defer allocator.free(zig_path);
            var rust_paths = try resolveOrBootstrapRust(allocator, cwd, stdout, versions.rust orelse core.toolchain_manager.default_rust_version);
            defer rust_paths.deinit(allocator);
        },
        .Go => {
            const go_path = try resolveOrBootstrapGo(allocator, cwd, stdout, versions.go orelse core.toolchain_manager.default_go_version);
            defer allocator.free(go_path);
        },
        .C, .Cpp, .Zig => {
            const zig_path = try resolveOrBootstrapZig(allocator, cwd, stdout, versions.zig orelse core.toolchain_manager.default_zig_version);
            defer allocator.free(zig_path);
        },
        .Python => {},
    }
}

fn containsCargoManifest(cwd: std.fs.Dir, path: []const u8) !bool {
    var dir = cwd.openDir(path, .{}) catch return false;
    defer dir.close();
    dir.access("Cargo.toml", .{}) catch return false;
    return true;
}

fn resolveCargoManifestPath(allocator: std.mem.Allocator, cwd: std.fs.Dir, path: []const u8) ![]const u8 {
    if (std.mem.endsWith(u8, path, "Cargo.toml")) return allocator.dupe(u8, path);
    var dir = cwd.openDir(path, .{}) catch return error.MissingCargoManifest;
    defer dir.close();
    dir.access("Cargo.toml", .{}) catch return error.MissingCargoManifest;
    return try std.fs.path.join(allocator, &[_][]const u8{ path, "Cargo.toml" });
}

fn getRemapPrefix(allocator: std.mem.Allocator, cwd: std.fs.Dir) !?[]const u8 {
    return cwd.realpathAlloc(allocator, ".") catch null;
}

fn printToolchainHints(allocator: std.mem.Allocator, stdout: anytype, version: []const u8) !void {
    const rel_path = core.toolchain_manager.zigRelPathForVersion(allocator, version) catch null;
    if (rel_path) |path| {
        defer allocator.free(path);
        try stdout.print(">> Project path: {s}\n", .{path});
    }
    const global_path = core.toolchain_manager.zigGlobalPathForVersion(allocator, version) catch null;
    if (global_path) |path| {
        defer allocator.free(path);
        try stdout.print(">> Global path: {s}\n", .{path});
    }
}

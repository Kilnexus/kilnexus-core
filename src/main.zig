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

fn handleManifest(allocator: std.mem.Allocator, cwd: std.fs.Dir, stdout: anytype) !void {
    const file = try cwd.openFile("Kilnexusfile", .{});
    defer file.close();

    const source = try file.readToEndAlloc(allocator, 1024 * 1024);
    defer allocator.free(source);

    var parser = core.protocol.KilnexusParser.init(allocator, source);
    var project_name: ?[]const u8 = null;
    var project_kind: ?core.protocol.ProjectKind = null;
    var target: ?[]const u8 = null;
    var kernel_version: ?[]const u8 = null;
    var sysroot: ?[]const u8 = null;
    var virtual_root: ?[]const u8 = null;
    var build_path: ?[]const u8 = null;
    var bootstrap_versions = BootstrapVersions{};

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
                project_name = spec.name;
                if (spec.kind) |kind| project_kind = kind;
            },
            .Target => |value| target = value,
            .Kernel => |value| kernel_version = value,
            .Sysroot => |value| sysroot = value,
            .VirtualRoot => |value| virtual_root = value,
            .Build => |path| build_path = path,
            .Bootstrap => |boot| switch (boot.tool) {
                .Zig => bootstrap_versions.zig = boot.version,
                .Rust => bootstrap_versions.rust = boot.version,
                .Go => bootstrap_versions.go = boot.version,
            },
            .Use => |_| {},
            .Pack => |_| {},
        }
    }

    if (build_path == null) {
        try stdout.print("!! No BUILD command found.\n", .{});
        return;
    }

    const path = build_path.?;
    if (!exists(cwd, path)) {
        try stdout.print("!! BUILD path not found: {s}\n", .{path});
        return;
    }

    if (project_kind) |kind| {
        try bootstrapProjectToolchains(allocator, cwd, stdout, kind, bootstrap_versions);
    }

    const output_name = project_name orelse "Kilnexus-out";
    const env = core.toolchain_common.VirtualEnv{
        .target = target,
        .kernel_version = kernel_version,
        .sysroot = sysroot,
        .virtual_root = virtual_root,
    };
    if (std.mem.endsWith(u8, path, ".c")) {
        const zig_version = bootstrap_versions.zig orelse core.toolchain_manager.default_zig_version;
        const zig_path = resolveOrBootstrapZig(allocator, cwd, stdout, zig_version) catch return;
        defer allocator.free(zig_path);
        const options = core.toolchain_common.CompileOptions{
            .output_name = output_name,
            .static = true,
            .zig_path = zig_path,
            .env = env,
        };
        var args = try core.toolchain_builder_zig.buildZigArgs(allocator, "cc", path, options);
        defer args.deinit(allocator);
        var env_map = try core.toolchain_executor.getEnvMap(allocator);
        defer env_map.deinit();
        try core.toolchain_executor.ensureSourceDateEpoch(&env_map);
        try core.toolchain_executor.runWithEnvMap(allocator, cwd, args.argv.items, env, &env_map);
    } else if (std.mem.endsWith(u8, path, ".cpp") or std.mem.endsWith(u8, path, ".cc") or std.mem.endsWith(u8, path, ".cxx")) {
        const zig_version = bootstrap_versions.zig orelse core.toolchain_manager.default_zig_version;
        const zig_path = resolveOrBootstrapZig(allocator, cwd, stdout, zig_version) catch return;
        defer allocator.free(zig_path);
        const options = core.toolchain_common.CompileOptions{
            .output_name = output_name,
            .static = true,
            .zig_path = zig_path,
            .env = env,
        };
        var args = try core.toolchain_builder_zig.buildZigArgs(allocator, "c++", path, options);
        defer args.deinit(allocator);
        var env_map = try core.toolchain_executor.getEnvMap(allocator);
        defer env_map.deinit();
        try core.toolchain_executor.ensureSourceDateEpoch(&env_map);
        try core.toolchain_executor.runWithEnvMap(allocator, cwd, args.argv.items, env, &env_map);
    } else if (std.mem.endsWith(u8, path, ".rs")) {
        const zig_version = bootstrap_versions.zig orelse core.toolchain_manager.default_zig_version;
        const rust_version = bootstrap_versions.rust orelse core.toolchain_manager.default_rust_version;
        const zig_path = resolveOrBootstrapZig(allocator, cwd, stdout, zig_version) catch return;
        defer allocator.free(zig_path);
        var rust_paths = resolveOrBootstrapRust(allocator, cwd, stdout, rust_version) catch return;
        defer rust_paths.deinit(allocator);
        const options = core.toolchain_common.CompileOptions{
            .output_name = output_name,
            .static = true,
            .zig_path = zig_path,
            .rustc_path = rust_paths.rustc,
            .env = env,
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
        const zig_version = bootstrap_versions.zig orelse core.toolchain_manager.default_zig_version;
        const rust_version = bootstrap_versions.rust orelse core.toolchain_manager.default_rust_version;
        const zig_path = resolveOrBootstrapZig(allocator, cwd, stdout, zig_version) catch return;
        defer allocator.free(zig_path);
        var rust_paths = resolveOrBootstrapRust(allocator, cwd, stdout, rust_version) catch return;
        defer rust_paths.deinit(allocator);
        const manifest_path = try resolveCargoManifestPath(allocator, cwd, path);
        defer allocator.free(manifest_path);
        const options = core.toolchain_common.CompileOptions{
            .zig_path = zig_path,
            .rustc_path = rust_paths.rustc,
            .cargo_path = rust_paths.cargo,
            .env = env,
            .cargo_manifest_path = manifest_path,
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
}

fn exists(dir: std.fs.Dir, filename: []const u8) bool {
    dir.access(filename, .{}) catch return false;
    return true;
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

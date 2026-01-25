const std = @import("std");
const manager = @import("../toolchain/manager.zig");
const protocol_types = @import("../protocol/types.zig");
const cross_target_mod = @import("../toolchain/cross/target.zig");
const toolchain_common = @import("../toolchain/common.zig");

pub const BuildManifest = struct {
    version: []const u8 = "1.0",

    timestamp: u64,
    source_date_epoch: u64,
    kilnexus_version: []const u8,

    host: HostInfo,
    toolchains: ToolchainInfo,
    target: ?TargetInfo,
    dependencies: []DependencyInfo,
    build_config: BuildConfig,
    environment: []EnvVar,
    inputs: InputHashes,
    output: OutputInfo,
};

pub const HostInfo = struct {
    os: []const u8,
    arch: []const u8,
    kernel_version: ?[]const u8,
};

pub const ToolchainInfo = struct {
    zig: ?ToolchainVersion,
    rust: ?ToolchainVersion,
    go: ?ToolchainVersion,
    bootstrap_seed: ?BootstrapSeedInfo,
};

pub const ToolchainVersion = struct {
    version: []const u8,
    sha256: ?[]const u8,
    source: enum { Binary, Source },
};

pub const BootstrapSeedInfo = struct {
    version: []const u8,
    sha256: ?[]const u8,
};

pub const TargetInfo = struct {
    triple: []const u8,
    sysroot: ?[]const u8,
    kernel_version: ?[]const u8,
};

pub const DependencyInfo = struct {
    name: []const u8,
    version: []const u8,
    strategy: []const u8,
    sha256: ?[]const u8,
};

pub const BuildConfig = struct {
    deterministic_level: []const u8,
    isolation_level: []const u8,
    static_libc: bool,
    compiler_flags: CompilerFlags,
    path_remap: ?[]const u8,
};

pub const CompilerFlags = struct {
    zig: []const []const u8,
    rust: []const []const u8,
    c: []const []const u8,
};

pub const EnvVar = struct {
    key: []const u8,
    value: []const u8,
};

pub const InputHashes = struct {
    main_source: ?[]const u8,
    extra_sources: []SourceHash,
    knxfile: ?[]const u8,
};

pub const SourceHash = struct {
    path: []const u8,
    sha256: []const u8,
};

pub const OutputInfo = struct {
    name: []const u8,
    sha256: []const u8,
    size: u64,
};

pub const BuildManifestInputs = struct {
    timestamp: u64,
    output_name: []const u8,
    build_path: []const u8,
    project_name: ?[]const u8,
    knxfile_path: ?[]const u8,
    cross_target: ?cross_target_mod.CrossTarget,
    env: toolchain_common.VirtualEnv,
    deterministic_level: ?protocol_types.DeterministicLevel,
    isolation_level: ?protocol_types.IsolationLevel,
    static_libc: bool,
    remap_prefix: ?[]const u8,
    zig_version: []const u8,
    rust_version: []const u8,
    zig_source: bool,
    rust_source: bool,
    bootstrap_seed: ?BootstrapSeedInfo,
    extra_sources: []const []const u8,
};

pub fn compareBinaries(path1: []const u8, path2: []const u8) !bool {
    var file1 = try std.fs.cwd().openFile(path1, .{});
    defer file1.close();
    var file2 = try std.fs.cwd().openFile(path2, .{});
    defer file2.close();

    const stat1 = try file1.stat();
    const stat2 = try file2.stat();
    if (stat1.size != stat2.size) return false;

    const hash1 = try sha256File(file1);
    const hash2 = try sha256File(file2);
    return std.mem.eql(u8, hash1[0..], hash2[0..]);
}

pub fn generateBuildManifest(allocator: std.mem.Allocator, inputs: BuildManifestInputs) !void {
    const manifest = try buildManifestFromInputs(allocator, inputs);
    defer freeManifest(allocator, manifest);

    std.fs.cwd().makePath(".knx") catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };

    var file = try std.fs.cwd().createFile(".knx/build-manifest.json", .{ .truncate = true });
    defer file.close();

    try std.json.stringify(manifest, .{ .whitespace = .indent_2 }, file.writer());
}

fn buildManifestFromInputs(
    allocator: std.mem.Allocator,
    inputs: BuildManifestInputs,
) !BuildManifest {
    const deps = try allocator.alloc(DependencyInfo, 0);
    const env_vars = try buildEnvironment(allocator);
    const input_hashes = try buildInputHashes(allocator, inputs.build_path, inputs.knxfile_path, inputs.extra_sources);
    const output = try buildOutputInfo(allocator, inputs.output_name);

    const zig_info = ToolchainVersion{
        .version = inputs.zig_version,
        .sha256 = null,
        .source = if (inputs.zig_source) .Source else .Binary,
    };
    const rust_info = ToolchainVersion{
        .version = inputs.rust_version,
        .sha256 = null,
        .source = if (inputs.rust_source) .Source else .Binary,
    };

    const target_info = if (inputs.cross_target) |target| TargetInfo{
        .triple = target.toZigTarget(),
        .sysroot = inputs.env.sysroot,
        .kernel_version = inputs.env.kernel_version,
    } else null;

    const manifest = BuildManifest{
        .timestamp = inputs.timestamp,
        .source_date_epoch = sourceDateEpoch(),
        .kilnexus_version = "0.0.1",
        .host = .{
            .os = manager.hostOsName(),
            .arch = manager.hostArchName(),
            .kernel_version = inputs.env.kernel_version,
        },
        .toolchains = .{
            .zig = zig_info,
            .rust = rust_info,
            .go = null,
            .bootstrap_seed = inputs.bootstrap_seed,
        },
        .target = target_info,
        .dependencies = deps,
        .build_config = .{
            .deterministic_level = deterministicName(inputs.deterministic_level),
            .isolation_level = isolationName(inputs.isolation_level),
            .static_libc = inputs.static_libc,
            .compiler_flags = .{
                .zig = &[_][]const u8{},
                .rust = &[_][]const u8{},
                .c = &[_][]const u8{},
            },
            .path_remap = inputs.remap_prefix,
        },
        .environment = env_vars,
        .inputs = input_hashes,
        .output = output,
    };

    return manifest;
}

fn buildEnvironment(allocator: std.mem.Allocator) ![]EnvVar {
    const value = std.process.getEnvVarOwned(allocator, "SOURCE_DATE_EPOCH") catch |err| switch (err) {
        error.EnvironmentVariableNotFound => null,
        else => return err,
    };
    if (value == null) {
        return allocator.alloc(EnvVar, 0);
    }

    var env_vars = try allocator.alloc(EnvVar, 1);
    env_vars[0] = .{ .key = "SOURCE_DATE_EPOCH", .value = value.? };
    return env_vars;
}

fn buildInputHashes(
    allocator: std.mem.Allocator,
    build_path: []const u8,
    knxfile_path: ?[]const u8,
    extra_sources: []const []const u8,
) !InputHashes {
    var main_hash: ?[]const u8 = null;
    if (try isFile(build_path)) {
        main_hash = try hashSourceFile(allocator, build_path);
    } else if (try cargoManifestFor(allocator, build_path)) |manifest_path| {
        defer allocator.free(manifest_path);
        main_hash = try hashSourceFile(allocator, manifest_path);
    }

    var knx_hash: ?[]const u8 = null;
    if (knxfile_path) |path| {
        if (try isFile(path)) {
            knx_hash = try hashSourceFile(allocator, path);
        }
    }

    const extra = try hashSourceFiles(allocator, extra_sources);
    return .{
        .main_source = main_hash,
        .extra_sources = extra,
        .knxfile = knx_hash,
    };
}

fn buildOutputInfo(allocator: std.mem.Allocator, output_name: []const u8) !OutputInfo {
    var file = try std.fs.cwd().openFile(output_name, .{});
    defer file.close();
    const stat = try file.stat();
    const digest = try sha256File(file);
    const hash_hex = try digestHexAlloc(allocator, &digest);
    return .{
        .name = output_name,
        .sha256 = hash_hex,
        .size = stat.size,
    };
}

fn deterministicName(level: ?protocol_types.DeterministicLevel) []const u8 {
    if (level == null) return "default";
    return switch (level.?) {
        .Strict => "strict",
        .Standard => "standard",
        .Relaxed => "relaxed",
    };
}

fn isolationName(level: ?protocol_types.IsolationLevel) []const u8 {
    if (level == null) return "default";
    return switch (level.?) {
        .Full => "full",
        .Minimal => "minimal",
        .None => "none",
    };
}

pub fn hashSourceFile(allocator: std.mem.Allocator, path: []const u8) ![]const u8 {
    var file = try std.fs.cwd().openFile(path, .{});
    defer file.close();
    const digest = try sha256File(file);
    return digestHexAlloc(allocator, &digest);
}

pub fn hashSourceFiles(
    allocator: std.mem.Allocator,
    paths: []const []const u8,
) ![]SourceHash {
    var result = try allocator.alloc(SourceHash, paths.len);
    for (paths, 0..) |path, i| {
        const hash = try hashSourceFile(allocator, path);
        result[i] = .{
            .path = path,
            .sha256 = hash,
        };
    }
    return result;
}

fn digestHexAlloc(allocator: std.mem.Allocator, digest: *const [32]u8) ![]const u8 {
    var hex_buf = try allocator.alloc(u8, 64);
    _ = try std.fmt.bufPrint(hex_buf, "{}", .{std.fmt.fmtSliceHexLower(digest[0..])});
    return hex_buf;
}

fn isFile(path: []const u8) !bool {
    var file = std.fs.cwd().openFile(path, .{}) catch |err| switch (err) {
        error.FileNotFound => return false,
        error.IsDir => return false,
        else => return err,
    };
    file.close();
    return true;
}

fn cargoManifestFor(allocator: std.mem.Allocator, path: []const u8) !?[]const u8 {
    if (std.mem.endsWith(u8, path, "Cargo.toml")) return allocator.dupe(u8, path);
    var dir = std.fs.cwd().openDir(path, .{}) catch return null;
    defer dir.close();
    dir.access("Cargo.toml", .{}) catch return null;
    return try std.fs.path.join(allocator, &[_][]const u8{ path, "Cargo.toml" });
}

fn sha256File(file: std.fs.File) ![32]u8 {
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    var buf: [32 * 1024]u8 = undefined;
    var f = file;
    try f.seekTo(0);
    while (true) {
        const amt = try f.read(buf[0..]);
        if (amt == 0) break;
        hasher.update(buf[0..amt]);
    }
    return hasher.finalResult();
}

fn sourceDateEpoch() u64 {
    const value = std.process.getEnvVarOwned(std.heap.page_allocator, "SOURCE_DATE_EPOCH") catch return 0;
    defer std.heap.page_allocator.free(value);
    return std.fmt.parseInt(u64, value, 10) catch 0;
}

fn freeManifest(allocator: std.mem.Allocator, manifest: BuildManifest) void {
    allocator.free(manifest.dependencies);
    for (manifest.environment) |env_var| {
        if (std.mem.eql(u8, env_var.key, "SOURCE_DATE_EPOCH")) {
            allocator.free(env_var.value);
        }
    }
    allocator.free(manifest.environment);

    if (manifest.inputs.main_source) |hash| allocator.free(hash);
    if (manifest.inputs.knxfile) |hash| allocator.free(hash);
    for (manifest.inputs.extra_sources) |source| allocator.free(source.sha256);
    allocator.free(manifest.inputs.extra_sources);

    allocator.free(manifest.output.sha256);
}

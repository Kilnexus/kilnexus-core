const std = @import("std");
const manager = @import("../toolchain/manager.zig");
const protocol_types = @import("../protocol/types.zig");
const manifest_types = @import("manifest_types.zig");
const hash_utils = @import("hash_utils.zig");

pub fn buildManifestFromInputs(
    allocator: std.mem.Allocator,
    inputs: manifest_types.BuildManifestInputs,
) !manifest_types.BuildManifest {
    const deps = try allocator.alloc(manifest_types.DependencyInfo, 0);
    const env_vars = try buildEnvironment(allocator);
    const input_hashes = try buildInputHashes(allocator, inputs.build_path, inputs.knxfile_path, inputs.extra_sources);
    const output = try buildOutputInfo(allocator, inputs.output_name);

    const zig_info = manifest_types.ToolchainVersion{
        .version = inputs.zig_version,
        .sha256 = null,
        .source = if (inputs.zig_source) .Source else .Binary,
    };
    const rust_info = manifest_types.ToolchainVersion{
        .version = inputs.rust_version,
        .sha256 = null,
        .source = if (inputs.rust_source) .Source else .Binary,
    };

    const target_info = if (inputs.cross_target) |target| manifest_types.TargetInfo{
        .triple = target.toZigTarget(),
        .sysroot = inputs.env.sysroot,
        .kernel_version = inputs.env.kernel_version,
    } else null;

    const manifest = manifest_types.BuildManifest{
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

fn buildEnvironment(allocator: std.mem.Allocator) ![]manifest_types.EnvVar {
    const value = std.process.getEnvVarOwned(allocator, "SOURCE_DATE_EPOCH") catch |err| switch (err) {
        error.EnvironmentVariableNotFound => null,
        else => return err,
    };
    if (value == null) {
        return allocator.alloc(manifest_types.EnvVar, 0);
    }

    var env_vars = try allocator.alloc(manifest_types.EnvVar, 1);
    env_vars[0] = .{ .key = "SOURCE_DATE_EPOCH", .value = value.? };
    return env_vars;
}

fn buildInputHashes(
    allocator: std.mem.Allocator,
    build_path: []const u8,
    knxfile_path: ?[]const u8,
    extra_sources: []const []const u8,
) !manifest_types.InputHashes {
    var main_hash: ?[]const u8 = null;
    if (try isFile(build_path)) {
        main_hash = try hash_utils.hashSourceFile(allocator, build_path);
    } else if (try cargoManifestFor(allocator, build_path)) |manifest_path| {
        defer allocator.free(manifest_path);
        main_hash = try hash_utils.hashSourceFile(allocator, manifest_path);
    }

    var knx_hash: ?[]const u8 = null;
    if (knxfile_path) |path| {
        if (try isFile(path)) {
            knx_hash = try hash_utils.hashSourceFile(allocator, path);
        }
    }

    const extra = try hash_utils.hashSourceFiles(allocator, extra_sources);
    return .{
        .main_source = main_hash,
        .extra_sources = extra,
        .knxfile = knx_hash,
    };
}

fn buildOutputInfo(allocator: std.mem.Allocator, output_name: []const u8) !manifest_types.OutputInfo {
    var file = try std.fs.cwd().openFile(output_name, .{});
    defer file.close();
    const stat = try file.stat();
    const digest = try hash_utils.sha256File(file);
    const hash_hex = try hash_utils.digestHexAlloc(allocator, &digest);
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
    if (std.mem.endsWith(u8, path, "Cargo.toml")) {
        const duped = try allocator.dupe(u8, path);
        return @as([]const u8, duped);
    }
    var dir = std.fs.cwd().openDir(path, .{}) catch return null;
    defer dir.close();
    dir.access("Cargo.toml", .{}) catch return null;
    const joined = try std.fs.path.join(allocator, &[_][]const u8{ path, "Cargo.toml" });
    return @as([]const u8, joined);
}

fn sourceDateEpoch() u64 {
    const value = std.process.getEnvVarOwned(std.heap.page_allocator, "SOURCE_DATE_EPOCH") catch return 0;
    defer std.heap.page_allocator.free(value);
    return std.fmt.parseInt(u64, value, 10) catch 0;
}

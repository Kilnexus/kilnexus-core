const std = @import("std");
const manifest_types = @import("manifest_types.zig");
const manifest_builder = @import("manifest_builder.zig");
const hash_utils = @import("hash_utils.zig");
const paths_config = @import("../paths/config.zig");

pub const BuildManifest = manifest_types.BuildManifest;
pub const BuildManifestInputs = manifest_types.BuildManifestInputs;
pub const BootstrapSeedInfo = manifest_types.BootstrapSeedInfo;

pub fn compareBinaries(path1: []const u8, path2: []const u8) !bool {
    var file1 = try std.fs.cwd().openFile(path1, .{});
    defer file1.close();
    var file2 = try std.fs.cwd().openFile(path2, .{});
    defer file2.close();

    const stat1 = try file1.stat();
    const stat2 = try file2.stat();
    if (stat1.size != stat2.size) return false;

    const hash1 = try hash_utils.sha256File(file1);
    const hash2 = try hash_utils.sha256File(file2);
    return std.mem.eql(u8, hash1[0..], hash2[0..]);
}

pub fn generateBuildManifest(allocator: std.mem.Allocator, inputs: BuildManifestInputs) !void {
    const manifest = try manifest_builder.buildManifestFromInputs(allocator, inputs);
    defer freeManifest(allocator, manifest);

    const project_dir = try paths_config.projectPath(allocator, &[_][]const u8{});
    defer allocator.free(project_dir);
    std.fs.cwd().makePath(project_dir) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };

    const manifest_path = try paths_config.projectPath(allocator, &[_][]const u8{ "build-manifest.json" });
    defer allocator.free(manifest_path);
    var file = try std.fs.cwd().createFile(manifest_path, .{ .truncate = true });
    defer file.close();

    var writer_buffer: [32 * 1024]u8 = undefined;
    var writer = file.writer(&writer_buffer);
    try std.json.Stringify.value(manifest, .{ .whitespace = .indent_2 }, &writer.interface);
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

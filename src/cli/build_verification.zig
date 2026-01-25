const std = @import("std");
const core = @import("../root.zig");
const common = @import("common.zig");
const build_types = @import("build_types.zig");
const paths_config = @import("../paths/config.zig");

pub fn verifyStaticLinking(stdout: anytype, output_name: []const u8) !void {
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

pub fn verifyReproducibility(
    allocator: std.mem.Allocator,
    cwd: std.fs.Dir,
    stdout: anytype,
    output_name: []const u8,
    inputs: build_types.BuildInputs,
) !void {
    const manifest_inputs = core.reproducibility_verifier.BuildManifestInputs{
        .timestamp = @intCast(std.time.timestamp()),
        .output_name = output_name,
        .build_path = inputs.path,
        .project_name = inputs.project_name,
        .knxfile_path = inputs.knxfile_path,
        .cross_target = inputs.cross_target,
        .env = inputs.env,
        .deterministic_level = inputs.deterministic_level,
        .isolation_level = inputs.isolation_level,
        .static_libc = inputs.static_libc_enabled,
        .remap_prefix = inputs.remap_prefix,
        .zig_version = inputs.zig_version,
        .rust_version = inputs.rust_version,
        .zig_source = inputs.bootstrap_sources.zig != null,
        .rust_source = inputs.bootstrap_sources.rust != null,
        .bootstrap_seed = if (inputs.bootstrap_seed) |seed| core.reproducibility_verifier.BootstrapSeedInfo{
            .version = seed.version,
            .sha256 = seed.sha256,
        } else null,
        .extra_sources = inputs.extra_sources,
    };
    try core.reproducibility_verifier.generateBuildManifest(allocator, manifest_inputs);
    try common.ensureReproDir(cwd);
    const repro_path = try paths_config.projectPath(allocator, &[_][]const u8{ "repro", output_name });
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

const std = @import("std");
const core = @import("../root.zig");
const common = @import("common.zig");
const deterministic_flags = @import("deterministic/flags.zig");
const deterministic_order = @import("deterministic/order.zig");
const deterministic_path = @import("deterministic/path_normalize.zig");
const build_types = @import("build_types.zig");
const c_builder = @import("builders/c_builder.zig");
const rust_builder = @import("builders/rust_builder.zig");
const verification = @import("build_verification.zig");
const packaging = @import("build_packaging.zig");

pub const BuildInputs = build_types.BuildInputs;

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
        try c_builder.buildC(allocator, cwd, stdout, effective_inputs);
    } else if (std.mem.endsWith(u8, effective_inputs.path, ".cpp") or std.mem.endsWith(u8, effective_inputs.path, ".cc") or std.mem.endsWith(u8, effective_inputs.path, ".cxx")) {
        try c_builder.buildCpp(allocator, cwd, stdout, effective_inputs);
    } else if (std.mem.endsWith(u8, effective_inputs.path, ".rs")) {
        try rust_builder.buildRust(allocator, cwd, stdout, effective_inputs);
    } else if (std.mem.endsWith(u8, effective_inputs.path, "Cargo.toml") or try common.containsCargoManifest(cwd, effective_inputs.path)) {
        try rust_builder.buildCargo(allocator, cwd, stdout, effective_inputs);
    } else {
        try stdout.print(">> TODO: BUILD supports only C/C++/Rust sources or Cargo.toml for now.\n", .{});
        return;
    }

    try stdout.print(">> Build complete: {s}\n", .{inputs.output_name});
    try verification.verifyStaticLinking(stdout, inputs.output_name);
    if (inputs.verify_reproducible) {
        try verification.verifyReproducibility(allocator, cwd, stdout, inputs.output_name, inputs);
    }
    if (inputs.pack_format) |format| {
        try packaging.packOutput(allocator, cwd, stdout, inputs.output_name, inputs.project_name, format);
    }
}

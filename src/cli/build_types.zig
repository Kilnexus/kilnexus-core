const std = @import("std");
const core = @import("../root.zig");
const common = @import("common.zig");
const embed = @import("embed_generator.zig");

pub const BuildInputs = struct {
    path: []const u8,
    output_name: []const u8,
    project_name: ?[]const u8,
    knxfile_path: ?[]const u8,
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

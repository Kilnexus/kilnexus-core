const std = @import("std");
const core = @import("../../root.zig");
const common = @import("../../build/common.zig");

pub const Manifest = struct {
    project_name: ?[]const u8 = null,
    project_kind: ?core.protocol.ProjectKind = null,
    target: ?core.protocol_types.CrossTarget = null,
    kernel_version: ?[]const u8 = null,
    sysroot_spec: ?core.protocol_types.SysrootSpec = null,
    virtual_root: ?[]const u8 = null,
    build_path: ?[]const u8 = null,
    pack_format: ?core.protocol.PackOptions.Format = null,
    uses: std.ArrayList(common.UseSpec) = .empty,
    bootstrap_versions: common.BootstrapVersions = .{},
    bootstrap_sources: common.BootstrapSourceVersions = .{},
    bootstrap_seed: ?common.BootstrapSeedSpec = null,
    static_libc: ?StaticLibcSpec = null,
    deterministic_level: ?core.protocol_types.DeterministicLevel = null,
    isolation_level: ?core.protocol_types.IsolationLevel = null,
    verify_reproducible: bool = false,
    sandbox_build: bool = false,

    pub fn deinit(self: *Manifest, allocator: std.mem.Allocator) void {
        self.uses.deinit(allocator);
    }
};

pub const StaticLibcSpec = struct {
    name: []const u8,
    version: []const u8,
};

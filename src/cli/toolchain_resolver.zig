const std = @import("std");
const core = @import("../root.zig");
const common = @import("common.zig");

pub const RustPaths = struct {
    rustc: []const u8,
    cargo: []const u8,

    pub fn deinit(self: *RustPaths, allocator: std.mem.Allocator) void {
        allocator.free(self.rustc);
        allocator.free(self.cargo);
    }
};

pub fn resolveOrBootstrapZig(
    allocator: std.mem.Allocator,
    cwd: std.fs.Dir,
    stdout: anytype,
    version: []const u8,
    source_spec: ?common.BootstrapSourceSpec,
    seed_spec: ?common.BootstrapSeedSpec,
) ![]const u8 {
    return core.toolchain_manager.resolveZigPathForVersion(allocator, cwd, version) catch |err| {
        if (err != error.ToolchainMissing) return err;
        if (source_spec != null) {
            try stdout.print(">> Zig toolchain missing. Bootstrapping from source...\n", .{});
            const seed = if (seed_spec) |spec| core.toolchain_source_builder.BootstrapSeedSpec{
                .version = spec.version,
                .sha256 = spec.sha256,
                .command = spec.command,
            } else null;
            core.toolchain_source_builder.buildZigFromSource(version, source_spec.?.sha256, seed) catch |boot_err| {
                try stdout.print("!! Source bootstrap failed: {s}\n", .{@errorName(boot_err)});
                try printToolchainHints(allocator, stdout, version);
                return error.ToolchainMissing;
            };
            return try core.toolchain_manager.resolveZigPathForVersion(allocator, cwd, version);
        }
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

pub fn resolveOrBootstrapRust(
    allocator: std.mem.Allocator,
    cwd: std.fs.Dir,
    stdout: anytype,
    version: []const u8,
    source_spec: ?common.BootstrapSourceSpec,
) !RustPaths {
    const rustc_path = core.toolchain_manager.resolveRustcPathForVersion(allocator, cwd, version) catch |err| blk: {
        if (err != error.ToolchainMissing) return err;
        if (source_spec != null) {
            try stdout.print(">> Rust toolchain missing. Bootstrapping from source...\n", .{});
            core.toolchain_source_builder.buildRustFromSource(version, source_spec.?.sha256) catch |boot_err| {
                try stdout.print("!! Source bootstrap failed: {s}\n", .{@errorName(boot_err)});
                return error.ToolchainMissing;
            };
            break :blk try core.toolchain_manager.resolveRustcPathForVersion(allocator, cwd, version);
        }
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
        if (source_spec != null) {
            try stdout.print(">> Rust toolchain missing. Bootstrapping from source...\n", .{});
            core.toolchain_source_builder.buildRustFromSource(version, source_spec.?.sha256) catch |boot_err| {
                try stdout.print("!! Source bootstrap failed: {s}\n", .{@errorName(boot_err)});
                return error.ToolchainMissing;
            };
            break :blk try core.toolchain_manager.resolveCargoPathForVersion(allocator, cwd, version);
        }
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

pub fn resolveOrBootstrapGo(
    allocator: std.mem.Allocator,
    cwd: std.fs.Dir,
    stdout: anytype,
    version: []const u8,
) ![]const u8 {
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

pub fn bootstrapProjectToolchains(
    allocator: std.mem.Allocator,
    cwd: std.fs.Dir,
    stdout: anytype,
    project_kind: core.protocol.ProjectKind,
    versions: common.BootstrapVersions,
    sources: common.BootstrapSourceVersions,
    seed: ?common.BootstrapSeedSpec,
) !void {
    switch (project_kind) {
        .Rust => {
            const zig_path = try resolveOrBootstrapZig(
                allocator,
                cwd,
                stdout,
                versions.zig orelse core.toolchain_manager.default_zig_version,
                sources.zig,
                seed,
            );
            defer allocator.free(zig_path);
            var rust_paths = try resolveOrBootstrapRust(
                allocator,
                cwd,
                stdout,
                versions.rust orelse core.toolchain_manager.default_rust_version,
                sources.rust,
            );
            defer rust_paths.deinit(allocator);
        },
        .Go => {
            const go_path = try resolveOrBootstrapGo(allocator, cwd, stdout, versions.go orelse core.toolchain_manager.default_go_version);
            defer allocator.free(go_path);
        },
        .C, .Cpp, .Zig => {
            const zig_path = try resolveOrBootstrapZig(
                allocator,
                cwd,
                stdout,
                versions.zig orelse core.toolchain_manager.default_zig_version,
                sources.zig,
                seed,
            );
            defer allocator.free(zig_path);
        },
        .Python => {},
    }
}

pub fn printToolchainHints(allocator: std.mem.Allocator, stdout: anytype, version: []const u8) !void {
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

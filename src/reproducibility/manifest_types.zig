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

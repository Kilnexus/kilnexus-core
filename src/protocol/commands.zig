const protocol_types = @import("types.zig");

pub const Command = union(enum) {
    Project: ProjectSpec,
    Target: protocol_types.TargetSpec,
    Kernel: []const u8,
    Sysroot: protocol_types.SysrootSpec,
    VirtualRoot: []const u8,
    Use: UseDependency,
    Build: ?[]const u8,
    Deterministic: protocol_types.DeterministicLevel,
    Isolation: protocol_types.IsolationLevel,
    Bootstrap: BootstrapOptions,
    BootstrapFromSource: BootstrapFromSourceOptions,
    BootstrapSeed: BootstrapSeedOptions,
    BootstrapSeedCommand: BootstrapSeedCommandOptions,
    Pack: PackOptions,
    StaticLibc: StaticLibcOptions,
    VerifyReproducible: bool,
    SandboxBuild: bool,
};

pub const UseDependency = struct {
    pub const Strategy = enum { Static, Dynamic, Embed };

    name: []const u8,
    version: []const u8,
    alias: ?[]const u8,
    strategy: Strategy,
};

pub const PackOptions = struct {
    pub const Format = enum { TarGz, Zip };

    format: Format,
};

pub const BootstrapOptions = struct {
    pub const Tool = enum { Zig, Rust, Go };

    tool: Tool,
    version: []const u8,
};

pub const BootstrapFromSourceOptions = struct {
    pub const Tool = enum { Zig, Rust, Musl };

    tool: Tool,
    version: []const u8,
    sha256: ?[]const u8,
};

pub const BootstrapSeedOptions = struct {
    pub const Tool = enum { Zig };

    tool: Tool,
    version: []const u8,
    sha256: ?[]const u8,
};

pub const BootstrapSeedCommandOptions = struct {
    tool: BootstrapSeedOptions.Tool,
    version: []const u8,
    command: []const u8,
};

pub const StaticLibcOptions = struct {
    name: []const u8,
    version: []const u8,
};

pub const ProjectSpec = struct {
    name: ?[]const u8,
    kind: ?ProjectKind,
};

pub const ProjectKind = enum {
    Zig,
    Rust,
    Go,
    C,
    Cpp,
    Python,
};

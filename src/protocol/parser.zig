const std = @import("std");
const tokenizer = @import("tokenizer.zig");
const protocol_types = @import("types.zig");
const sysroot_mod = @import("../toolchain/cross/sysroot.zig");
const target_mod = @import("../toolchain/cross/target.zig");

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

pub const KilnexusParser = struct {
    allocator: std.mem.Allocator,
    source: []const u8,
    pos: usize = 0,
    line: usize = 0,
    last_line: []const u8 = "",
    error_column: usize = 0,

    pub fn init(allocator: std.mem.Allocator, source: []const u8) KilnexusParser {
        return .{
            .allocator = allocator,
            .source = source,
            .pos = 0,
            .line = 0,
            .last_line = "",
            .error_column = 0,
        };
    }

    pub fn currentLine(self: *const KilnexusParser) usize {
        return self.line;
    }

    pub fn currentLineText(self: *const KilnexusParser) []const u8 {
        return self.last_line;
    }

    pub fn currentErrorColumn(self: *const KilnexusParser) usize {
        return self.error_column;
    }

    pub fn next(self: *KilnexusParser) !?Command {
        while (self.pos < self.source.len) {
            const line_start = self.pos;
            const line_end = std.mem.indexOfScalarPos(u8, self.source, self.pos, '\n') orelse self.source.len;
            self.pos = if (line_end < self.source.len) line_end + 1 else line_end;
            self.line += 1;
            self.error_column = 0;

            var line = self.source[line_start..line_end];
            if (line.len > 0 and line[line.len - 1] == '\r') {
                line = line[0 .. line.len - 1];
            }
            self.last_line = line;

            const tokens = try tokenizer.tokenizeLine(self.allocator, line);
            defer self.allocator.free(tokens);

            if (tokens.len == 0) continue;

            const keyword = tokens[0].text;
            if (std.ascii.eqlIgnoreCase(keyword, "PROJECT")) {
                if (tokens.len < 2) {
                    self.error_column = line.len + 1;
                    return error.MissingArgument;
                }
                return parseProject(tokens, &self.error_column) catch |err| {
                    if (self.error_column == 0) self.error_column = tokens[1].start + 1;
                    return err;
                };
            } else if (std.ascii.eqlIgnoreCase(keyword, "TARGET")) {
                if (tokens.len < 2) {
                    self.error_column = line.len + 1;
                    return error.MissingArgument;
                }
                return parseTarget(tokens, &self.error_column) catch |err| {
                    if (self.error_column == 0) self.error_column = tokens[1].start + 1;
                    return err;
                };
            } else if (std.ascii.eqlIgnoreCase(keyword, "KERNEL") or std.ascii.eqlIgnoreCase(keyword, "KERNEL_VERSION")) {
                if (tokens.len < 2) {
                    self.error_column = line.len + 1;
                    return error.MissingArgument;
                }
                return Command{ .Kernel = tokens[1].text };
            } else if (std.ascii.eqlIgnoreCase(keyword, "SYSROOT")) {
                if (tokens.len < 2) {
                    self.error_column = line.len + 1;
                    return error.MissingArgument;
                }
                return Command{ .Sysroot = sysroot_mod.parseSysrootSpec(tokens[1].text) };
            } else if (std.ascii.eqlIgnoreCase(keyword, "VROOT") or std.ascii.eqlIgnoreCase(keyword, "VIRTUAL_ROOT")) {
                if (tokens.len < 2) {
                    self.error_column = line.len + 1;
                    return error.MissingArgument;
                }
                return Command{ .VirtualRoot = tokens[1].text };
            } else if (std.ascii.eqlIgnoreCase(keyword, "USE")) {
                if (tokens.len < 2) {
                    self.error_column = line.len + 1;
                    return error.MissingArgument;
                }
                return parseUse(tokens, &self.error_column) catch |err| {
                    if (self.error_column == 0) self.error_column = tokens[1].start + 1;
                    return err;
                };
            } else if (std.ascii.eqlIgnoreCase(keyword, "BUILD")) {
                const path = if (tokens.len >= 2) tokens[1].text else null;
                return Command{ .Build = path };
            } else if (std.ascii.eqlIgnoreCase(keyword, "DETERMINISTIC")) {
                if (tokens.len < 2) {
                    self.error_column = line.len + 1;
                    return error.MissingArgument;
                }
                const value = parseDeterministicLevel(tokens[1].text) orelse {
                    self.error_column = tokens[1].start + 1;
                    return error.InvalidDeterministicLevel;
                };
                return Command{ .Deterministic = value };
            } else if (std.ascii.eqlIgnoreCase(keyword, "ISOLATION")) {
                if (tokens.len < 2) {
                    self.error_column = line.len + 1;
                    return error.MissingArgument;
                }
                const value = parseIsolationLevel(tokens[1].text) orelse {
                    self.error_column = tokens[1].start + 1;
                    return error.InvalidIsolationLevel;
                };
                return Command{ .Isolation = value };
            } else if (std.ascii.eqlIgnoreCase(keyword, "BOOTSTRAP")) {
                if (tokens.len < 2) {
                    self.error_column = line.len + 1;
                    return error.MissingArgument;
                }
                return parseBootstrap(tokens, &self.error_column) catch |err| {
                    if (self.error_column == 0) self.error_column = tokens[1].start + 1;
                    return err;
                };
            } else if (std.ascii.eqlIgnoreCase(keyword, "BOOTSTRAP_SEED")) {
                if (tokens.len < 2) {
                    self.error_column = line.len + 1;
                    return error.MissingArgument;
                }
                return parseBootstrapSeed(tokens, &self.error_column) catch |err| {
                    if (self.error_column == 0) self.error_column = tokens[1].start + 1;
                    return err;
                };
            } else if (isBootstrapFromSourceKeyword(keyword)) {
                if (tokens.len < 2) {
                    self.error_column = line.len + 1;
                    return error.MissingArgument;
                }
                return parseBootstrapFromSource(tokens, &self.error_column) catch |err| {
                    if (self.error_column == 0) self.error_column = tokens[1].start + 1;
                    return err;
                };
            } else if (std.ascii.eqlIgnoreCase(keyword, "PACK")) {
                if (tokens.len < 2) {
                    self.error_column = line.len + 1;
                    return error.MissingArgument;
                }
                return parsePack(tokens, &self.error_column) catch |err| {
                    if (self.error_column == 0) self.error_column = tokens[1].start + 1;
                    return err;
                };
            } else if (std.ascii.eqlIgnoreCase(keyword, "STATIC_LIBC")) {
                if (tokens.len < 3) {
                    self.error_column = line.len + 1;
                    return error.MissingArgument;
                }
                return parseStaticLibc(tokens, &self.error_column) catch |err| {
                    if (self.error_column == 0) self.error_column = tokens[1].start + 1;
                    return err;
                };
            } else if (std.ascii.eqlIgnoreCase(keyword, "VERIFY_REPRODUCIBLE")) {
                if (tokens.len < 2) {
                    self.error_column = line.len + 1;
                    return error.MissingArgument;
                }
                const value = parseBool(tokens[1].text) orelse {
                    self.error_column = tokens[1].start + 1;
                    return error.InvalidBoolean;
                };
                return Command{ .VerifyReproducible = value };
            } else if (std.ascii.eqlIgnoreCase(keyword, "SANDBOX_BUILD")) {
                if (tokens.len < 2) {
                    self.error_column = line.len + 1;
                    return error.MissingArgument;
                }
                const value = parseBool(tokens[1].text) orelse {
                    self.error_column = tokens[1].start + 1;
                    return error.InvalidBoolean;
                };
                return Command{ .SandboxBuild = value };
            } else {
                self.error_column = tokens[0].start + 1;
                return error.UnknownCommand;
            }
        }

        return null;
    }
};

fn parseUse(tokens: []const tokenizer.Token, error_column: *usize) !Command {
    const spec = tokens[1].text;
    const colon = std.mem.indexOfScalar(u8, spec, ':') orelse {
        error_column.* = tokens[1].start + 1;
        return error.InvalidUseSpec;
    };
    const name = spec[0..colon];
    const version = spec[colon + 1 ..];

    var alias: ?[]const u8 = null;
    var strategy: UseDependency.Strategy = .Static;

    var i: usize = 2;
    while (i < tokens.len) : (i += 1) {
        const word = tokens[i].text;
        if (std.ascii.eqlIgnoreCase(word, "AS")) {
            if (i + 1 >= tokens.len) {
                error_column.* = tokens[i].end + 1;
                return error.MissingArgument;
            }
            alias = tokens[i + 1].text;
            i += 1;
        } else if (std.ascii.eqlIgnoreCase(word, "STRATEGY")) {
            if (i + 1 >= tokens.len) {
                error_column.* = tokens[i].end + 1;
                return error.MissingArgument;
            }
            strategy = parseStrategy(tokens[i + 1].text) orelse {
                error_column.* = tokens[i + 1].start + 1;
                return error.InvalidStrategy;
            };
            i += 1;
        }
    }

    return Command{
        .Use = .{
            .name = name,
            .version = version,
            .alias = alias,
            .strategy = strategy,
        },
    };
}

fn parseTarget(tokens: []const tokenizer.Token, error_column: *usize) !Command {
    const target_text = tokens[1].text;
    const target = target_mod.CrossTarget.parse(target_text) catch {
        error_column.* = tokens[1].start + 1;
        return error.InvalidTarget;
    };

    var sysroot_spec: ?protocol_types.SysrootSpec = null;
    var i: usize = 2;
    while (i < tokens.len) : (i += 1) {
        const word = tokens[i].text;
        if (std.ascii.eqlIgnoreCase(word, "SYSROOT")) {
            if (i + 1 >= tokens.len) {
                error_column.* = tokens[i].end + 1;
                return error.MissingArgument;
            }
            sysroot_spec = sysroot_mod.parseSysrootSpec(tokens[i + 1].text);
            i += 1;
        }
    }

    return Command{ .Target = .{ .target = target, .sysroot = sysroot_spec } };
}

fn parsePack(tokens: []const tokenizer.Token, error_column: *usize) !Command {
    const format = parsePackFormat(tokens[1].text) orelse {
        error_column.* = tokens[1].start + 1;
        return error.InvalidPackFormat;
    };
    return Command{ .Pack = .{ .format = format } };
}

fn parseProject(tokens: []const tokenizer.Token, error_column: *usize) !Command {
    var name: ?[]const u8 = null;
    var kind: ?ProjectKind = null;

    if (tokens.len < 2) return error.MissingArgument;

    if (tokens.len == 2) {
        const maybe_kind = parseProjectKind(tokens[1].text);
        if (maybe_kind) |value| {
            kind = value;
        } else {
            name = tokens[1].text;
        }
        return Command{ .Project = .{ .name = name, .kind = kind } };
    }

    name = tokens[1].text;
    var i: usize = 2;
    while (i < tokens.len) : (i += 1) {
        const word = tokens[i].text;
        if (std.ascii.eqlIgnoreCase(word, "TYPE") or std.ascii.eqlIgnoreCase(word, "KIND")) {
            if (i + 1 >= tokens.len) {
                error_column.* = tokens[i].end + 1;
                return error.MissingArgument;
            }
            kind = parseProjectKind(tokens[i + 1].text) orelse {
                error_column.* = tokens[i + 1].start + 1;
                return error.InvalidProjectType;
            };
            i += 1;
            continue;
        }
        if (kind == null) {
            if (parseProjectKind(word)) |value| {
                kind = value;
            }
        }
    }

    return Command{ .Project = .{ .name = name, .kind = kind } };
}

fn parseBootstrap(tokens: []const tokenizer.Token, error_column: *usize) !Command {
    const spec = tokens[1].text;
    const sep = std.mem.indexOfScalar(u8, spec, ':') orelse {
        error_column.* = tokens[1].start + 1;
        return error.InvalidBootstrapSpec;
    };
    const tool_name = spec[0..sep];
    const version = spec[sep + 1 ..];
    if (version.len == 0) {
        error_column.* = tokens[1].start + sep + 2;
        return error.InvalidBootstrapSpec;
    }

    const tool = parseBootstrapTool(tool_name) orelse {
        error_column.* = tokens[1].start + 1;
        return error.InvalidBootstrapSpec;
    };

    return Command{ .Bootstrap = .{ .tool = tool, .version = version } };
}

fn parseBootstrapFromSource(tokens: []const tokenizer.Token, error_column: *usize) !Command {
    const base = "BOOTSTRAP_FROM_SOURCE";
    const keyword = tokens[0].text;
    if (!startsWithIgnoreCase(keyword, base)) return error.InvalidBootstrapSourceSpec;

    const suffix = keyword[base.len..];
    var tool_text: []const u8 = undefined;
    var version_index: usize = 1;
    if (suffix.len != 0) {
        tool_text = suffix;
    } else {
        if (tokens.len < 3) {
            error_column.* = tokens[0].end + 1;
            return error.MissingArgument;
        }
        tool_text = tokens[1].text;
        version_index = 2;
    }

    if (tokens.len <= version_index) {
        error_column.* = tokens[0].end + 1;
        return error.MissingArgument;
    }
    const version = tokens[version_index].text;

    const tool = parseSourceTool(tool_text) orelse {
        error_column.* = tokens[0].start + 1;
        return error.InvalidBootstrapSourceSpec;
    };

    var sha256: ?[]const u8 = null;
    if (tokens.len > version_index + 1) {
        sha256 = parseSha256(tokens[version_index + 1].text) orelse {
            error_column.* = tokens[version_index + 1].start + 1;
            return error.InvalidBootstrapSourceSpec;
        };
    }

    return Command{ .BootstrapFromSource = .{
        .tool = tool,
        .version = version,
        .sha256 = sha256,
    } };
}

fn parseBootstrapSeed(tokens: []const tokenizer.Token, error_column: *usize) !Command {
    if (tokens.len < 3) {
        error_column.* = tokens[0].end + 1;
        return error.MissingArgument;
    }
    const tool = parseBootstrapSeedTool(tokens[1].text) orelse {
        error_column.* = tokens[1].start + 1;
        return error.InvalidBootstrapSeedSpec;
    };
    const version = tokens[2].text;
    if (version.len == 0) {
        error_column.* = tokens[2].start + 1;
        return error.InvalidBootstrapSeedSpec;
    }

    var sha256: ?[]const u8 = null;
    if (tokens.len > 3) {
        sha256 = parseSha256(tokens[3].text) orelse {
            error_column.* = tokens[3].start + 1;
            return error.InvalidBootstrapSeedSpec;
        };
    }

    return Command{ .BootstrapSeed = .{
        .tool = tool,
        .version = version,
        .sha256 = sha256,
    } };
}

fn parseStaticLibc(tokens: []const tokenizer.Token, error_column: *usize) !Command {
    if (tokens.len < 3) return error.MissingArgument;
    const name = tokens[1].text;
    const version = tokens[2].text;
    if (name.len == 0 or version.len == 0) {
        error_column.* = tokens[1].start + 1;
        return error.InvalidStaticLibcSpec;
    }
    return Command{ .StaticLibc = .{ .name = name, .version = version } };
}

fn parseStrategy(raw: []const u8) ?UseDependency.Strategy {
    if (std.ascii.eqlIgnoreCase(raw, "static")) return .Static;
    if (std.ascii.eqlIgnoreCase(raw, "dynamic")) return .Dynamic;
    if (std.ascii.eqlIgnoreCase(raw, "embed")) return .Embed;
    return null;
}

fn parseSourceTool(raw: []const u8) ?BootstrapFromSourceOptions.Tool {
    if (std.ascii.eqlIgnoreCase(raw, "zig")) return .Zig;
    if (std.ascii.eqlIgnoreCase(raw, "rust")) return .Rust;
    if (std.ascii.eqlIgnoreCase(raw, "musl")) return .Musl;
    return null;
}

fn parsePackFormat(raw: []const u8) ?PackOptions.Format {
    if (std.ascii.eqlIgnoreCase(raw, "tar.gz")) return .TarGz;
    if (std.ascii.eqlIgnoreCase(raw, "zip")) return .Zip;
    return null;
}

fn parseProjectKind(raw: []const u8) ?ProjectKind {
    if (std.ascii.eqlIgnoreCase(raw, "zig")) return .Zig;
    if (std.ascii.eqlIgnoreCase(raw, "rust")) return .Rust;
    if (std.ascii.eqlIgnoreCase(raw, "go")) return .Go;
    if (std.ascii.eqlIgnoreCase(raw, "c")) return .C;
    if (std.ascii.eqlIgnoreCase(raw, "cpp") or std.ascii.eqlIgnoreCase(raw, "c++")) return .Cpp;
    if (std.ascii.eqlIgnoreCase(raw, "python")) return .Python;
    return null;
}

fn parseDeterministicLevel(raw: []const u8) ?protocol_types.DeterministicLevel {
    if (std.ascii.eqlIgnoreCase(raw, "strict")) return .Strict;
    if (std.ascii.eqlIgnoreCase(raw, "standard")) return .Standard;
    if (std.ascii.eqlIgnoreCase(raw, "relaxed")) return .Relaxed;
    return null;
}

fn parseIsolationLevel(raw: []const u8) ?protocol_types.IsolationLevel {
    if (std.ascii.eqlIgnoreCase(raw, "full")) return .Full;
    if (std.ascii.eqlIgnoreCase(raw, "minimal")) return .Minimal;
    if (std.ascii.eqlIgnoreCase(raw, "none")) return .None;
    return null;
}

fn parseBootstrapTool(raw: []const u8) ?BootstrapOptions.Tool {
    if (std.ascii.eqlIgnoreCase(raw, "zig")) return .Zig;
    if (std.ascii.eqlIgnoreCase(raw, "rust")) return .Rust;
    if (std.ascii.eqlIgnoreCase(raw, "go")) return .Go;
    return null;
}

fn parseBootstrapSeedTool(raw: []const u8) ?BootstrapSeedOptions.Tool {
    if (std.ascii.eqlIgnoreCase(raw, "zig")) return .Zig;
    return null;
}

fn parseSha256(raw: []const u8) ?[]const u8 {
    const prefix = "sha256:";
    if (!startsWithIgnoreCase(raw, prefix)) return null;
    if (raw.len <= prefix.len) return null;
    return raw[prefix.len..];
}

fn parseBool(raw: []const u8) ?bool {
    if (std.ascii.eqlIgnoreCase(raw, "true")) return true;
    if (std.ascii.eqlIgnoreCase(raw, "false")) return false;
    return null;
}

fn startsWithIgnoreCase(haystack: []const u8, needle: []const u8) bool {
    if (haystack.len < needle.len) return false;
    return std.ascii.eqlIgnoreCase(haystack[0..needle.len], needle);
}

fn isBootstrapFromSourceKeyword(keyword: []const u8) bool {
    return startsWithIgnoreCase(keyword, "BOOTSTRAP_FROM_SOURCE");
}

test "parser line and column reporting" {
    const allocator = std.testing.allocator;
    var parser = KilnexusParser.init(allocator, "PROJECT\n");
    _ = parser.next() catch |err| {
        try std.testing.expectEqual(error.MissingArgument, err);
        try std.testing.expectEqual(@as(usize, 1), parser.currentLine());
        try std.testing.expectEqualStrings("PROJECT", parser.currentLineText());
        try std.testing.expectEqual(@as(usize, 8), parser.currentErrorColumn());
        return;
    };
    try std.testing.expect(false);
}

test "parser invalid strategy column" {
    const allocator = std.testing.allocator;
    var parser = KilnexusParser.init(allocator, "USE name:1 STRATEGY fast\n");
    _ = parser.next() catch |err| {
        try std.testing.expectEqual(error.InvalidStrategy, err);
        try std.testing.expectEqual(@as(usize, 21), parser.currentErrorColumn());
        return;
    };
    try std.testing.expect(false);
}

const std = @import("std");
const tokenizer = @import("tokenizer.zig");
const protocol_types = @import("types.zig");
const sysroot_mod = @import("../toolchain/cross/sysroot.zig");
const target_mod = @import("../toolchain/cross/target.zig");
const commands = @import("commands.zig");

const Command = commands.Command;

pub fn parseUse(tokens: []const tokenizer.Token, error_column: *usize) !Command {
    const spec = tokens[1].text;
    const colon = std.mem.indexOfScalar(u8, spec, ':') orelse {
        error_column.* = tokens[1].start + 1;
        return error.InvalidUseSpec;
    };
    const name = spec[0..colon];
    const version = spec[colon + 1 ..];

    var alias: ?[]const u8 = null;
    var strategy: commands.UseDependency.Strategy = .Static;

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

pub fn parseTarget(tokens: []const tokenizer.Token, error_column: *usize) !Command {
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

pub fn parsePack(tokens: []const tokenizer.Token, error_column: *usize) !Command {
    const format = parsePackFormat(tokens[1].text) orelse {
        error_column.* = tokens[1].start + 1;
        return error.InvalidPackFormat;
    };
    return Command{ .Pack = .{ .format = format } };
}

pub fn parseProject(tokens: []const tokenizer.Token, error_column: *usize) !Command {
    var name: ?[]const u8 = null;
    var kind: ?commands.ProjectKind = null;

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

pub fn parseBootstrap(tokens: []const tokenizer.Token, error_column: *usize) !Command {
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

pub fn parseBootstrapFromSource(tokens: []const tokenizer.Token, error_column: *usize) !Command {
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

pub fn parseBootstrapSeed(tokens: []const tokenizer.Token, error_column: *usize) !Command {
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

pub fn parseBootstrapSeedCommand(tokens: []const tokenizer.Token, error_column: *usize) !Command {
    if (tokens.len < 4) {
        error_column.* = tokens[0].end + 1;
        return error.MissingArgument;
    }
    const tool = parseBootstrapSeedTool(tokens[1].text) orelse {
        error_column.* = tokens[1].start + 1;
        return error.InvalidBootstrapSeedCommandSpec;
    };
    const version = tokens[2].text;
    if (version.len == 0) {
        error_column.* = tokens[2].start + 1;
        return error.InvalidBootstrapSeedCommandSpec;
    }
    const command = tokens[3].text;
    if (command.len == 0) {
        error_column.* = tokens[3].start + 1;
        return error.InvalidBootstrapSeedCommandSpec;
    }

    return Command{ .BootstrapSeedCommand = .{
        .tool = tool,
        .version = version,
        .command = command,
    } };
}

pub fn parseStaticLibc(tokens: []const tokenizer.Token, error_column: *usize) !Command {
    if (tokens.len < 3) return error.MissingArgument;
    const name = tokens[1].text;
    const version = tokens[2].text;
    if (name.len == 0 or version.len == 0) {
        error_column.* = tokens[1].start + 1;
        return error.InvalidStaticLibcSpec;
    }
    return Command{ .StaticLibc = .{ .name = name, .version = version } };
}

fn parseStrategy(raw: []const u8) ?commands.UseDependency.Strategy {
    if (std.ascii.eqlIgnoreCase(raw, "static")) return .Static;
    if (std.ascii.eqlIgnoreCase(raw, "dynamic")) return .Dynamic;
    if (std.ascii.eqlIgnoreCase(raw, "embed")) return .Embed;
    return null;
}

fn parseSourceTool(raw: []const u8) ?commands.BootstrapFromSourceOptions.Tool {
    if (std.ascii.eqlIgnoreCase(raw, "zig")) return .Zig;
    if (std.ascii.eqlIgnoreCase(raw, "rust")) return .Rust;
    if (std.ascii.eqlIgnoreCase(raw, "musl")) return .Musl;
    return null;
}

fn parsePackFormat(raw: []const u8) ?commands.PackOptions.Format {
    if (std.ascii.eqlIgnoreCase(raw, "tar.gz")) return .TarGz;
    if (std.ascii.eqlIgnoreCase(raw, "zip")) return .Zip;
    return null;
}

fn parseProjectKind(raw: []const u8) ?commands.ProjectKind {
    if (std.ascii.eqlIgnoreCase(raw, "zig")) return .Zig;
    if (std.ascii.eqlIgnoreCase(raw, "rust")) return .Rust;
    if (std.ascii.eqlIgnoreCase(raw, "go")) return .Go;
    if (std.ascii.eqlIgnoreCase(raw, "c")) return .C;
    if (std.ascii.eqlIgnoreCase(raw, "cpp") or std.ascii.eqlIgnoreCase(raw, "c++")) return .Cpp;
    if (std.ascii.eqlIgnoreCase(raw, "python")) return .Python;
    return null;
}

pub fn parseDeterministicLevel(raw: []const u8) ?protocol_types.DeterministicLevel {
    if (std.ascii.eqlIgnoreCase(raw, "strict")) return .Strict;
    if (std.ascii.eqlIgnoreCase(raw, "standard")) return .Standard;
    if (std.ascii.eqlIgnoreCase(raw, "relaxed")) return .Relaxed;
    return null;
}

pub fn parseIsolationLevel(raw: []const u8) ?protocol_types.IsolationLevel {
    if (std.ascii.eqlIgnoreCase(raw, "full")) return .Full;
    if (std.ascii.eqlIgnoreCase(raw, "minimal")) return .Minimal;
    if (std.ascii.eqlIgnoreCase(raw, "none")) return .None;
    return null;
}

fn parseBootstrapTool(raw: []const u8) ?commands.BootstrapOptions.Tool {
    if (std.ascii.eqlIgnoreCase(raw, "zig")) return .Zig;
    if (std.ascii.eqlIgnoreCase(raw, "rust")) return .Rust;
    if (std.ascii.eqlIgnoreCase(raw, "go")) return .Go;
    return null;
}

fn parseBootstrapSeedTool(raw: []const u8) ?commands.BootstrapSeedOptions.Tool {
    if (std.ascii.eqlIgnoreCase(raw, "zig")) return .Zig;
    return null;
}

fn parseSha256(raw: []const u8) ?[]const u8 {
    const prefix = "sha256:";
    if (!startsWithIgnoreCase(raw, prefix)) return null;
    if (raw.len <= prefix.len) return null;
    return raw[prefix.len..];
}

pub fn parseBool(raw: []const u8) ?bool {
    if (std.ascii.eqlIgnoreCase(raw, "true")) return true;
    if (std.ascii.eqlIgnoreCase(raw, "false")) return false;
    return null;
}

fn startsWithIgnoreCase(haystack: []const u8, needle: []const u8) bool {
    if (haystack.len < needle.len) return false;
    return std.ascii.eqlIgnoreCase(haystack[0..needle.len], needle);
}

pub fn isBootstrapFromSourceKeyword(keyword: []const u8) bool {
    return startsWithIgnoreCase(keyword, "BOOTSTRAP_FROM_SOURCE");
}

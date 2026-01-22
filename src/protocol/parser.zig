const std = @import("std");
const tokenizer = @import("tokenizer.zig");

pub const Command = union(enum) {
    Project: ProjectSpec,
    Target: []const u8,
    Kernel: []const u8,
    Sysroot: []const u8,
    VirtualRoot: []const u8,
    Use: UseDependency,
    Build: ?[]const u8,
    Bootstrap: BootstrapOptions,
    Pack: PackOptions,
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
                return Command{ .Target = tokens[1].text };
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
                return Command{ .Sysroot = tokens[1].text };
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
            } else if (std.ascii.eqlIgnoreCase(keyword, "BOOTSTRAP")) {
                if (tokens.len < 2) {
                    self.error_column = line.len + 1;
                    return error.MissingArgument;
                }
                return parseBootstrap(tokens, &self.error_column) catch |err| {
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

fn parseStrategy(raw: []const u8) ?UseDependency.Strategy {
    if (std.ascii.eqlIgnoreCase(raw, "static")) return .Static;
    if (std.ascii.eqlIgnoreCase(raw, "dynamic")) return .Dynamic;
    if (std.ascii.eqlIgnoreCase(raw, "embed")) return .Embed;
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

fn parseBootstrapTool(raw: []const u8) ?BootstrapOptions.Tool {
    if (std.ascii.eqlIgnoreCase(raw, "zig")) return .Zig;
    if (std.ascii.eqlIgnoreCase(raw, "rust")) return .Rust;
    if (std.ascii.eqlIgnoreCase(raw, "go")) return .Go;
    return null;
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

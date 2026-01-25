const std = @import("std");
const tokenizer = @import("tokenizer.zig");
const sysroot_mod = @import("../toolchain/cross/sysroot.zig");
const commands = @import("commands.zig");
const command_parsers = @import("command_parsers.zig");

pub const Command = commands.Command;
pub const UseDependency = commands.UseDependency;
pub const PackOptions = commands.PackOptions;
pub const BootstrapOptions = commands.BootstrapOptions;
pub const BootstrapFromSourceOptions = commands.BootstrapFromSourceOptions;
pub const BootstrapSeedOptions = commands.BootstrapSeedOptions;
pub const BootstrapSeedCommandOptions = commands.BootstrapSeedCommandOptions;
pub const StaticLibcOptions = commands.StaticLibcOptions;
pub const ProjectSpec = commands.ProjectSpec;
pub const ProjectKind = commands.ProjectKind;

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
                return command_parsers.parseProject(tokens, &self.error_column) catch |err| {
                    if (self.error_column == 0) self.error_column = tokens[1].start + 1;
                    return err;
                };
            } else if (std.ascii.eqlIgnoreCase(keyword, "TARGET")) {
                if (tokens.len < 2) {
                    self.error_column = line.len + 1;
                    return error.MissingArgument;
                }
                return command_parsers.parseTarget(tokens, &self.error_column) catch |err| {
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
                return command_parsers.parseUse(tokens, &self.error_column) catch |err| {
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
                const value = command_parsers.parseDeterministicLevel(tokens[1].text) orelse {
                    self.error_column = tokens[1].start + 1;
                    return error.InvalidDeterministicLevel;
                };
                return Command{ .Deterministic = value };
            } else if (std.ascii.eqlIgnoreCase(keyword, "ISOLATION")) {
                if (tokens.len < 2) {
                    self.error_column = line.len + 1;
                    return error.MissingArgument;
                }
                const value = command_parsers.parseIsolationLevel(tokens[1].text) orelse {
                    self.error_column = tokens[1].start + 1;
                    return error.InvalidIsolationLevel;
                };
                return Command{ .Isolation = value };
            } else if (std.ascii.eqlIgnoreCase(keyword, "BOOTSTRAP")) {
                if (tokens.len < 2) {
                    self.error_column = line.len + 1;
                    return error.MissingArgument;
                }
                return command_parsers.parseBootstrap(tokens, &self.error_column) catch |err| {
                    if (self.error_column == 0) self.error_column = tokens[1].start + 1;
                    return err;
                };
            } else if (std.ascii.eqlIgnoreCase(keyword, "BOOTSTRAP_SEED")) {
                if (tokens.len < 2) {
                    self.error_column = line.len + 1;
                    return error.MissingArgument;
                }
                return command_parsers.parseBootstrapSeed(tokens, &self.error_column) catch |err| {
                    if (self.error_column == 0) self.error_column = tokens[1].start + 1;
                    return err;
                };
            } else if (std.ascii.eqlIgnoreCase(keyword, "BOOTSTRAP_SEED_COMMAND")) {
                if (tokens.len < 4) {
                    self.error_column = line.len + 1;
                    return error.MissingArgument;
                }
                return command_parsers.parseBootstrapSeedCommand(tokens, &self.error_column) catch |err| {
                    if (self.error_column == 0) self.error_column = tokens[1].start + 1;
                    return err;
                };
            } else if (command_parsers.isBootstrapFromSourceKeyword(keyword)) {
                if (tokens.len < 2) {
                    self.error_column = line.len + 1;
                    return error.MissingArgument;
                }
                return command_parsers.parseBootstrapFromSource(tokens, &self.error_column) catch |err| {
                    if (self.error_column == 0) self.error_column = tokens[1].start + 1;
                    return err;
                };
            } else if (std.ascii.eqlIgnoreCase(keyword, "PACK")) {
                if (tokens.len < 2) {
                    self.error_column = line.len + 1;
                    return error.MissingArgument;
                }
                return command_parsers.parsePack(tokens, &self.error_column) catch |err| {
                    if (self.error_column == 0) self.error_column = tokens[1].start + 1;
                    return err;
                };
            } else if (std.ascii.eqlIgnoreCase(keyword, "STATIC_LIBC")) {
                if (tokens.len < 3) {
                    self.error_column = line.len + 1;
                    return error.MissingArgument;
                }
                return command_parsers.parseStaticLibc(tokens, &self.error_column) catch |err| {
                    if (self.error_column == 0) self.error_column = tokens[1].start + 1;
                    return err;
                };
            } else if (std.ascii.eqlIgnoreCase(keyword, "VERIFY_REPRODUCIBLE")) {
                if (tokens.len < 2) {
                    self.error_column = line.len + 1;
                    return error.MissingArgument;
                }
                const value = command_parsers.parseBool(tokens[1].text) orelse {
                    self.error_column = tokens[1].start + 1;
                    return error.InvalidBoolean;
                };
                return Command{ .VerifyReproducible = value };
            } else if (std.ascii.eqlIgnoreCase(keyword, "SANDBOX_BUILD")) {
                if (tokens.len < 2) {
                    self.error_column = line.len + 1;
                    return error.MissingArgument;
                }
                const value = command_parsers.parseBool(tokens[1].text) orelse {
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

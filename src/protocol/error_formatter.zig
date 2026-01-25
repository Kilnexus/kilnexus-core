const std = @import("std");

pub fn parserErrorMessage(err: anyerror) []const u8 {
    return switch (err) {
        error.MissingArgument => "Missing argument after keyword.",
        error.UnknownCommand => "Unknown command.",
        error.InvalidUseSpec => "Invalid USE spec (expected name:version).",
        error.InvalidStrategy => "Invalid USE strategy (static|dynamic|embed).",
        error.InvalidPackFormat => "Invalid PACK format (tar.gz|zip).",
        error.InvalidBootstrapSpec => "Invalid BOOTSTRAP spec (expected zig:<version>, rust:<version>, or go:<version>).",
        error.InvalidBootstrapSourceSpec => "Invalid BOOTSTRAP_FROM_SOURCE spec (expected tool, version, optional sha256:...).",
        error.InvalidBootstrapSeedSpec => "Invalid BOOTSTRAP_SEED spec (expected zig <version> optional sha256:...).",
        error.InvalidStaticLibcSpec => "Invalid STATIC_LIBC spec (expected name version).",
        error.InvalidBoolean => "Invalid boolean (expected true|false).",
        error.InvalidProjectType => "Invalid PROJECT type.",
        else => @errorName(err),
    };
}

pub fn formatCaretLine(allocator: std.mem.Allocator, column: usize) ![]const u8 {
    const caret_column = if (column == 0) 1 else column;
    const prefix_len = caret_column - 1;
    var buf = try allocator.alloc(u8, prefix_len + 1);
    @memset(buf[0..prefix_len], ' ');
    buf[prefix_len] = '^';
    return buf;
}

test "parser error messages" {
    try std.testing.expectEqualStrings("Missing argument after keyword.", parserErrorMessage(error.MissingArgument));
    try std.testing.expectEqualStrings("Invalid USE spec (expected name:version).", parserErrorMessage(error.InvalidUseSpec));
    try std.testing.expectEqualStrings("Unknown command.", parserErrorMessage(error.UnknownCommand));
}

test "caret formatting" {
    var gpa = std.testing.allocator;
    const caret = try formatCaretLine(gpa, 5);
    defer gpa.free(caret);
    try std.testing.expectEqualStrings("    ^", caret);
}

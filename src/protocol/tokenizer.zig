const std = @import("std");

pub const Token = struct {
    kind: Kind,
    text: []const u8,
    start: usize,
    end: usize,
};

pub const Kind = enum {
    Word,
    String,
};

pub fn tokenizeLine(allocator: std.mem.Allocator, line: []const u8) ![]Token {
    var tokens = std.ArrayList(Token).empty;
    errdefer tokens.deinit(allocator);

    var i: usize = 0;
    while (i < line.len) {
        while (i < line.len and std.ascii.isWhitespace(line[i])) : (i += 1) {}
        if (i >= line.len) break;
        if (line[i] == '#') break;

        if (line[i] == '"') {
            i += 1;
            const start = i;
            while (i < line.len and line[i] != '"') : (i += 1) {}
            const end = i;
            if (i < line.len and line[i] == '"') i += 1;
            try tokens.append(allocator, .{
                .kind = .String,
                .text = line[start..end],
                .start = start,
                .end = end,
            });
        } else {
            const start = i;
            while (i < line.len and !std.ascii.isWhitespace(line[i]) and line[i] != '#') : (i += 1) {}
            const end = i;
            if (start < end) {
                try tokens.append(allocator, .{
                    .kind = .Word,
                    .text = line[start..end],
                    .start = start,
                    .end = end,
                });
            }
            if (i < line.len and line[i] == '#') break;
        }
    }

    return tokens.toOwnedSlice(allocator);
}

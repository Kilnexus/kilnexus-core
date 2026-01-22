const std = @import("std");

pub const ProjectType = enum {
    Rust,
    Go,
    Python,
    C,
    Unknown,
};

pub fn detect(dir: std.fs.Dir) !ProjectType {
    if (exists(dir, "Cargo.toml")) return .Rust;
    if (exists(dir, "go.mod")) return .Go;
    if (exists(dir, "pyproject.toml")) return .Python;
    if (exists(dir, "build.zig")) return .C;
    if (try containsCSource(dir)) return .C;

    return .Unknown;
}

fn exists(dir: std.fs.Dir, filename: []const u8) bool {
    dir.access(filename, .{}) catch return false;
    return true;
}

fn containsCSource(dir: std.fs.Dir) !bool {
    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        if (entry.kind != .file) continue;
        if (isCOrCppSource(entry.name)) return true;
    }
    return false;
}

fn isCOrCppSource(name: []const u8) bool {
    return std.mem.endsWith(u8, name, ".c") or
        std.mem.endsWith(u8, name, ".cpp") or
        std.mem.endsWith(u8, name, ".cc") or
        std.mem.endsWith(u8, name, ".cxx");
}

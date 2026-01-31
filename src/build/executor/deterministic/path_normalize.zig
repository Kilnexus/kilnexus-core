const std = @import("std");

pub const PathNormalizer = struct {
    allocator: std.mem.Allocator,
    canonical_cwd: []const u8,
    remap_prefix: []const u8,

    pub fn init(allocator: std.mem.Allocator, cwd: std.fs.Dir, remap_prefix: []const u8) !PathNormalizer {
        const real = try cwd.realpathAlloc(allocator, ".");
        const normalized = try normalizeSeparatorsAlloc(allocator, real);
        allocator.free(real);
        return .{
            .allocator = allocator,
            .canonical_cwd = normalized,
            .remap_prefix = remap_prefix,
        };
    }

    pub fn deinit(self: *PathNormalizer) void {
        self.allocator.free(self.canonical_cwd);
    }

    pub fn normalize(self: *PathNormalizer, path: []const u8) ![]const u8 {
        const normalized = try normalizeSeparatorsAlloc(self.allocator, path);
        if (!isAbsoluteNormalized(normalized)) return normalized;

        const relative = relativeToCwd(normalized, self.canonical_cwd) orelse stripAbsoluteRoot(normalized);
        const trimmed = trimLeadingSlash(relative);
        if (trimmed.len == 0) {
            self.allocator.free(normalized);
            return self.allocator.dupe(u8, self.remap_prefix);
        }

        const remapped = try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ self.remap_prefix, trimmed });
        self.allocator.free(normalized);
        return remapped;
    }

    pub fn normalizeList(self: *PathNormalizer, paths: []const []const u8) ![]const []const u8 {
        var out = try self.allocator.alloc([]const u8, paths.len);
        var i: usize = 0;
        while (i < paths.len) : (i += 1) {
            out[i] = try self.normalize(paths[i]);
        }
        return out;
    }

    pub fn getRemapArg(self: *PathNormalizer) ![]const u8 {
        return std.fmt.allocPrint(self.allocator, "{s}={s}", .{ self.canonical_cwd, self.remap_prefix });
    }
};

fn normalizeSeparatorsAlloc(allocator: std.mem.Allocator, path: []const u8) ![]const u8 {
    const out = try allocator.dupe(u8, path);
    std.mem.replaceScalar(u8, out, '\\', '/');
    return out;
}

fn isAbsoluteNormalized(path: []const u8) bool {
    if (std.fs.path.isAbsolute(path)) return true;
    return hasDrivePrefix(path);
}

fn hasDrivePrefix(path: []const u8) bool {
    if (path.len < 2) return false;
    if (!std.ascii.isAlphabetic(path[0])) return false;
    return path[1] == ':';
}

fn relativeToCwd(path: []const u8, cwd: []const u8) ?[]const u8 {
    if (path.len < cwd.len) return null;
    if (!pathPrefixEqual(path, cwd)) return null;
    if (path.len == cwd.len) return "";
    if (path[cwd.len] == '/') return path[cwd.len + 1 ..];
    return path[cwd.len..];
}

fn pathPrefixEqual(path: []const u8, prefix: []const u8) bool {
    if (path.len < prefix.len) return false;
    if (hasDrivePrefix(path) or hasDrivePrefix(prefix)) {
        return std.ascii.eqlIgnoreCase(path[0..prefix.len], prefix);
    }
    return std.mem.eql(u8, path[0..prefix.len], prefix);
}

fn stripAbsoluteRoot(path: []const u8) []const u8 {
    var start: usize = 0;
    if (hasDrivePrefix(path)) {
        start = 2;
        if (path.len > 2 and path[2] == '/') start = 3;
    } else if (path.len > 0 and path[0] == '/') {
        start = 1;
    }
    return path[start..];
}

fn trimLeadingSlash(path: []const u8) []const u8 {
    if (path.len > 0 and path[0] == '/') return path[1..];
    return path;
}

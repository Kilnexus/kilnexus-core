const std = @import("std");
const builtin = @import("builtin");

pub const default_project_dir = ".knx";
pub const legacy_project_dir = ".kilnexus";
pub const default_output_dir = "kilnexus-out";

pub fn projectPath(allocator: std.mem.Allocator, segments: []const []const u8) ![]const u8 {
    const project_dir = try envOrDefaultOwned(allocator, "KNX_PROJECT_DIR", default_project_dir);
    defer allocator.free(project_dir);
    return joinWithBase(allocator, project_dir, segments);
}

pub fn legacyProjectPath(allocator: std.mem.Allocator, segments: []const []const u8) ![]const u8 {
    return joinWithBase(allocator, legacy_project_dir, segments);
}

pub fn globalRootDir(allocator: std.mem.Allocator) ![]const u8 {
    if (std.process.getEnvVarOwned(allocator, "KNX_HOME")) |value| {
        return value;
    } else |_| {}
    const home = try homeDir(allocator);
    defer allocator.free(home);
    return std.fs.path.join(allocator, &[_][]const u8{ home, default_project_dir });
}

pub fn globalPath(allocator: std.mem.Allocator, segments: []const []const u8) ![]const u8 {
    const root = try globalRootDir(allocator);
    defer allocator.free(root);
    return joinWithBase(allocator, root, segments);
}

pub fn outputDirName(allocator: std.mem.Allocator) ![]const u8 {
    return envOrDefaultOwned(allocator, "KNX_OUTPUT_DIR", default_output_dir);
}

pub fn envBoolOrDefault(allocator: std.mem.Allocator, key: []const u8, default_value: bool) !bool {
    if (std.process.getEnvVarOwned(allocator, key)) |value| {
        defer allocator.free(value);
        return parseBool(value) orelse default_value;
    } else |_| {}
    return default_value;
}

fn joinWithBase(allocator: std.mem.Allocator, base: []const u8, segments: []const []const u8) ![]const u8 {
    const parts = try allocator.alloc([]const u8, segments.len + 1);
    defer allocator.free(parts);
    parts[0] = base;
    std.mem.copyForwards([]const u8, parts[1..], segments);
    return std.fs.path.join(allocator, parts);
}

fn envOrDefaultOwned(allocator: std.mem.Allocator, key: []const u8, default_value: []const u8) ![]const u8 {
    if (std.process.getEnvVarOwned(allocator, key)) |value| {
        return value;
    } else |_| {}
    return allocator.dupe(u8, default_value);
}

fn homeDir(allocator: std.mem.Allocator) ![]const u8 {
    if (builtin.target.os.tag == .windows) {
        return std.process.getEnvVarOwned(allocator, "USERPROFILE");
    }
    return std.process.getEnvVarOwned(allocator, "HOME");
}

fn parseBool(value: []const u8) ?bool {
    if (value.len == 0) return null;
    if (std.ascii.eqlIgnoreCase(value, "1") or std.ascii.eqlIgnoreCase(value, "true") or std.ascii.eqlIgnoreCase(value, "yes")) return true;
    if (std.ascii.eqlIgnoreCase(value, "0") or std.ascii.eqlIgnoreCase(value, "false") or std.ascii.eqlIgnoreCase(value, "no")) return false;
    return null;
}

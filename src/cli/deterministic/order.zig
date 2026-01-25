const std = @import("std");

pub const DeterministicOrder = struct {
    pub fn sortPaths(paths: [][]const u8) void {
        sortList(paths);
    }

    pub fn sortLibs(libs: [][]const u8) void {
        sortList(libs);
    }

    pub fn sortArgs(args: [][]const u8) void {
        sortList(args);
    }

    pub fn sortEnvKeys(env_keys: [][]const u8) void {
        sortList(env_keys);
    }
};

fn sortList(list: [][]const u8) void {
    std.sort.insertion([]const u8, list, {}, struct {
        fn lessThan(_: void, a: []const u8, b: []const u8) bool {
            return std.mem.lessThan(u8, a, b);
        }
    }.lessThan);
}

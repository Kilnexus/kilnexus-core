const std = @import("std");

pub const InterceptionEnv = struct {};

pub const Interceptor = struct {
    pub fn prepare(_: *InterceptionEnv, _: std.mem.Allocator) !void {
        return;
    }
};
const std = @import("std");

pub fn wrap(allocator: std.mem.Allocator, argv: []const []const u8, target_triple: []const u8) ![]const []const u8 {
    if (argv.len == 0) return error.EmptyCommand;
    if (hasTargetFlag(argv)) {
        return dupArgv(allocator, argv);
    }
    const target_arg = try std.fmt.allocPrint(allocator, "--target={s}", .{target_triple});
    errdefer allocator.free(target_arg);

    var out = try allocator.alloc([]const u8, argv.len + 1);
    out[0] = argv[0];
    out[1] = target_arg;
    if (argv.len > 1) {
        std.mem.copyForwards([]const u8, out[2..], argv[1..]);
    }
    return out;
}

fn hasTargetFlag(args: []const []const u8) bool {
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.startsWith(u8, arg, "--target=")) return true;
        if (std.mem.eql(u8, arg, "--target")) {
            return i + 1 < args.len;
        }
    }
    return false;
}

fn dupArgv(allocator: std.mem.Allocator, argv: []const []const u8) ![]const []const u8 {
    var out = try allocator.alloc([]const u8, argv.len);
    std.mem.copyForwards([]const u8, out, argv);
    return out;
}

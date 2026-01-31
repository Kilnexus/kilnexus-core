const std = @import("std");

pub const MakeVars = struct {
    cc: ?[]const u8 = null,
    cxx: ?[]const u8 = null,
    ar: ?[]const u8 = null,
    ld: ?[]const u8 = null,
};

pub fn wrap(allocator: std.mem.Allocator, argv: []const []const u8, vars: MakeVars) ![]const []const u8 {
    if (argv.len == 0) return error.EmptyCommand;
    const extra = countVars(argv, vars);
    var out = try allocator.alloc([]const u8, argv.len + extra);
    out[0] = argv[0];

    var idx: usize = 1;
    if (vars.cc) |cc| {
        if (!hasVar(argv, "CC")) {
            out[idx] = try std.fmt.allocPrint(allocator, "CC={s}", .{cc});
            idx += 1;
        }
    }
    if (vars.cxx) |cxx| {
        if (!hasVar(argv, "CXX")) {
            out[idx] = try std.fmt.allocPrint(allocator, "CXX={s}", .{cxx});
            idx += 1;
        }
    }
    if (vars.ar) |ar| {
        if (!hasVar(argv, "AR")) {
            out[idx] = try std.fmt.allocPrint(allocator, "AR={s}", .{ar});
            idx += 1;
        }
    }
    if (vars.ld) |ld| {
        if (!hasVar(argv, "LD")) {
            out[idx] = try std.fmt.allocPrint(allocator, "LD={s}", .{ld});
            idx += 1;
        }
    }

    if (argv.len > 1) {
        std.mem.copyForwards([]const u8, out[idx..], argv[1..]);
    }
    return out;
}

fn countVars(argv: []const []const u8, vars: MakeVars) usize {
    var extra: usize = 0;
    if (vars.cc != null and !hasVar(argv, "CC")) extra += 1;
    if (vars.cxx != null and !hasVar(argv, "CXX")) extra += 1;
    if (vars.ar != null and !hasVar(argv, "AR")) extra += 1;
    if (vars.ld != null and !hasVar(argv, "LD")) extra += 1;
    return extra;
}

fn hasVar(argv: []const []const u8, key: []const u8) bool {
    for (argv) |arg| {
        if (std.mem.startsWith(u8, arg, key) and arg.len > key.len and arg[key.len] == '=') {
            return true;
        }
    }
    return false;
}

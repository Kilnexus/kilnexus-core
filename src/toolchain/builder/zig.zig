const std = @import("std");
const common = @import("../common.zig");
const argv_builder = @import("argv.zig");
const target_builder = @import("target.zig");

pub fn buildZigArgs(
    allocator: std.mem.Allocator,
    zig_mode: []const u8,
    source_path: []const u8,
    options: common.CompileOptions,
) !argv_builder.ArgvBuild {
    var args = argv_builder.ArgvBuild.init();

    try args.argv.appendSlice(allocator, &[_][]const u8{
        options.zig_path,
        zig_mode,
        source_path,
        "-o",
        options.output_name,
    });
    if (options.static) try args.argv.append(allocator, "-static");

    if (options.env.target) |target| {
        const resolved = try target_builder.resolveTarget(allocator, target, options.env.kernel_version);
        if (resolved.owned) |value| try args.owned.append(allocator, value);
        try args.argv.append(allocator, "-target");
        try args.argv.append(allocator, resolved.value);
    }

    if (options.env.sysroot) |sysroot| {
        try args.argv.append(allocator, "--sysroot");
        try args.argv.append(allocator, sysroot);
    }

    if (options.extra_args.len != 0) {
        try args.argv.appendSlice(allocator, options.extra_args);
    }

    return args;
}

fn argvHasPair(argv: []const []const u8, first: []const u8, second: []const u8) bool {
    if (argv.len < 2) return false;
    var i: usize = 0;
    while (i + 1 < argv.len) : (i += 1) {
        if (std.mem.eql(u8, argv[i], first) and std.mem.eql(u8, argv[i + 1], second)) return true;
    }
    return false;
}

test "buildZigArgs uses kernel suffix for linux-gnu target" {
    const allocator = std.testing.allocator;
    const options = common.CompileOptions{
        .env = .{
            .target = "x86_64-linux-gnu",
            .kernel_version = "2.6.32",
        },
    };
    var args = try buildZigArgs(allocator, "cc", "main.c", options);
    defer args.deinit(allocator);

    try std.testing.expect(argvHasPair(args.argv.items, "-target", "x86_64-linux-gnu.2.6.32"));
}

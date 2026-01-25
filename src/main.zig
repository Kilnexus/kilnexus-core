const std = @import("std");
const core = @import("root.zig");
const manifest_handler = @import("cli/manifest_handler.zig");

pub fn main() !void {
    var stdout_buffer: [32 * 1024]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;
    defer stdout.flush() catch {};
    try stdout.print("KILNEXUS CLI v0.0.1 [Constructing...]\n", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var cwd = std.fs.cwd();
    try core.toolchain_manager.ensureProjectCache(cwd);
    const has_knxfile = if (cwd.access("Knxfile", .{})) |_| true else |err| switch (err) {
        error.FileNotFound => false,
        else => return err,
    };
    const has_legacy_manifest = if (cwd.access("Kilnexusfile", .{})) |_| true else |err| switch (err) {
        error.FileNotFound => false,
        else => return err,
    };

    if (has_knxfile or has_legacy_manifest) {
        const manifest_name = if (has_knxfile) "Knxfile" else "Kilnexusfile";
        try stdout.print(">> Detected {s}. Parsing protocol...\n", .{manifest_name});
        try manifest_handler.handle(allocator, cwd, stdout, manifest_name);
    } else {
        try stdout.print(">> No manifest. Initiating Inference Engine...\n", .{});
        const project_type = try core.inference.detect(cwd);
        try core.strategy.buildInferred(allocator, project_type, cwd);
    }
}

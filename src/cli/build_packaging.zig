const std = @import("std");
const core = @import("../root.zig");
const common = @import("common.zig");

pub fn packOutput(
    allocator: std.mem.Allocator,
    cwd: std.fs.Dir,
    stdout: anytype,
    output_name: []const u8,
    project_name: ?[]const u8,
    format: core.protocol.PackOptions.Format,
) !void {
    if (!common.exists(cwd, output_name)) {
        try stdout.print("!! PACK requested but output not found: {s}\n", .{output_name});
        return;
    }

    cwd.makePath("dist") catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };

    const base = project_name orelse output_name;
    const archive_name = try std.fmt.allocPrint(
        allocator,
        "{s}-{s}-{s}.{s}",
        .{
            base,
            core.toolchain_manager.hostOsName(),
            core.toolchain_manager.hostArchName(),
            if (format == .TarGz) "tar.gz" else "zip",
        },
    );
    defer allocator.free(archive_name);

    const archive_path = try std.fs.path.join(allocator, &[_][]const u8{ "dist", archive_name });
    defer allocator.free(archive_path);

    const mtime = core.archive.sourceDateEpochSeconds();
    if (format == .TarGz) {
        try core.archive.packTarGzSingleFile(allocator, cwd, output_name, archive_path, output_name, mtime);
    } else {
        try core.archive.packZipSingleFile(allocator, cwd, output_name, archive_path, output_name, mtime);
    }
    try stdout.print(">> Packed: {s}\n", .{archive_path});
}

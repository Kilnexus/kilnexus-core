const std = @import("std");

pub fn downloadFile(allocator: std.mem.Allocator, url: []const u8, output_path: []const u8) !void {
    var client = std.http.Client{ .allocator = allocator };
    defer client.deinit();

    var file = try std.fs.cwd().createFile(output_path, .{ .truncate = true });
    defer file.close();

    var writer_buffer: [32 * 1024]u8 = undefined;
    var writer = file.writer(&writer_buffer);

    const result = try client.fetch(.{
        .location = .{ .url = url },
        .response_writer = &writer.interface,
    });

    try writer.interface.flush();
    if (result.status.class() != .success) return error.HttpFailed;
}

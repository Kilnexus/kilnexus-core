const std = @import("std");

pub fn extractTarGz(allocator: std.mem.Allocator, archive_path: []const u8, install_dir: []const u8, strip_components: u8) !void {
    _ = allocator;
    var archive = try std.fs.cwd().openFile(archive_path, .{});
    defer archive.close();

    var reader_buffer: [32 * 1024]u8 = undefined;
    const file_reader = archive.reader(&reader_buffer);
    var in_reader = file_reader.interface;
    var window: [std.compress.flate.max_window_len]u8 = undefined;
    const decomp = std.compress.flate.Decompress.init(&in_reader, .gzip, &window);
    var tar_reader = decomp.reader;

    var out_dir = try std.fs.cwd().openDir(install_dir, .{});
    defer out_dir.close();

    try std.tar.pipeToFileSystem(out_dir, &tar_reader, .{
        .strip_components = strip_components,
    });
}

const std = @import("std");

pub fn extractArchive(allocator: std.mem.Allocator, archive_path: []const u8, install_dir: []const u8, strip_components: u8) !void {
    if (std.mem.endsWith(u8, archive_path, ".tar.xz")) {
        try extractTarXz(allocator, archive_path, install_dir, strip_components);
        return;
    }
    if (std.mem.endsWith(u8, archive_path, ".tar.gz")) {
        try extractTarGz(allocator, archive_path, install_dir, strip_components);
        return;
    }
    return error.UnsupportedArchive;
}

pub fn extractTarXz(allocator: std.mem.Allocator, archive_path: []const u8, install_dir: []const u8, strip_components: u8) !void {
    var archive_file = try std.fs.cwd().openFile(archive_path, .{});
    defer archive_file.close();

    var reader_buffer: [32 * 1024]u8 = undefined;
    var file_reader = archive_file.reader(&reader_buffer);
    const old_reader = file_reader.interface.adaptToOldInterface();

    var xz = try std.compress.xz.decompress(allocator, old_reader);
    defer xz.deinit();

    var xz_reader = xz.reader();
    var adapter_buffer: [32 * 1024]u8 = undefined;
    const adapter = xz_reader.adaptToNewApi(&adapter_buffer);
    var tar_reader = adapter.new_interface;

    var out_dir = try std.fs.cwd().openDir(install_dir, .{});
    defer out_dir.close();

    try std.tar.pipeToFileSystem(out_dir, &tar_reader, .{
        .strip_components = strip_components,
    });
}

pub fn extractTarGz(allocator: std.mem.Allocator, archive_path: []const u8, install_dir: []const u8, strip_components: u8) !void {
    _ = allocator;
    var archive_file = try std.fs.cwd().openFile(archive_path, .{});
    defer archive_file.close();

    var reader_buffer: [32 * 1024]u8 = undefined;
    const file_reader = archive_file.reader(&reader_buffer);
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

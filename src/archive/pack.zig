const std = @import("std");
const gzip_writer = @import("gzip_writer.zig");
const zip_writer = @import("zip_writer.zig");
const common = @import("common.zig");

pub fn packTarGzSingleFile(
    allocator: std.mem.Allocator,
    cwd: std.fs.Dir,
    input_path: []const u8,
    output_path: []const u8,
    entry_name: []const u8,
    mtime_seconds: u64,
) !void {
    _ = allocator;
    var input = try cwd.openFile(input_path, .{});
    defer input.close();

    var output = try cwd.createFile(output_path, .{ .truncate = true });
    defer output.close();

    var output_buffer: [32 * 1024]u8 = undefined;
    var output_writer = output.writer(&output_buffer);

    var gzip = try gzip_writer.GzipStoredWriter.init(&output_writer.interface, mtime_seconds);
    defer gzip.finish() catch {};

    var tar = std.tar.Writer{ .underlying_writer = &gzip.writer };

    var reader_buffer: [32 * 1024]u8 = undefined;
    var reader = input.reader(&reader_buffer);
    const mtime_ns: i128 = @as(i128, @intCast(mtime_seconds)) * std.time.ns_per_s;
    try tar.writeFile(entry_name, &reader, mtime_ns);
}

pub fn packZipSingleFile(
    allocator: std.mem.Allocator,
    cwd: std.fs.Dir,
    input_path: []const u8,
    output_path: []const u8,
    entry_name: []const u8,
    mtime_seconds: u64,
) !void {
    _ = allocator;
    var input = try cwd.openFile(input_path, .{});
    defer input.close();

    const stat = try input.stat();
    const file_size: u32 = @intCast(stat.size);

    var crc = std.hash.Crc32.init();
    var reader_buffer: [32 * 1024]u8 = undefined;
    var reader = input.reader(&reader_buffer);
    while (true) {
        const amt = try reader.interface.readSliceShort(reader_buffer[0..]);
        if (amt == 0) break;
        crc.update(reader_buffer[0..amt]);
    }

    try input.seekTo(0);

    var output = try cwd.createFile(output_path, .{ .truncate = true });
    defer output.close();
    var out_buffer: [32 * 1024]u8 = undefined;
    var out = output.writer(&out_buffer);

    const dos_time = common.dosTimeFromEpoch(mtime_seconds);
    const dos_date = common.dosDateFromEpoch(mtime_seconds);
    const name_len: u16 = @intCast(entry_name.len);
    const local_header_offset: u32 = 0;
    const crc32_value: u32 = crc.final();

    try zip_writer.writeLocalHeader(&out.interface, dos_time, dos_date, name_len, crc32_value, file_size, entry_name);

    var file_reader = input.reader(&reader_buffer);
    _ = try out.interface.sendFileAll(&file_reader, .unlimited);

    const central_dir_offset: u32 = @intCast(30 + entry_name.len + file_size);
    const central_dir_size: u32 = @intCast(46 + entry_name.len);

    try zip_writer.writeCentralDirectory(
        &out.interface,
        dos_time,
        dos_date,
        name_len,
        crc32_value,
        file_size,
        local_header_offset,
        entry_name,
    );
    try zip_writer.writeEndOfCentralDirectory(&out.interface, central_dir_offset, central_dir_size);

    try out.interface.flush();
}

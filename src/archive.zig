const std = @import("std");

pub const default_registry = "https://registry.kilnexus.org";

pub fn registryBase(allocator: std.mem.Allocator) ![]const u8 {
    return std.process.getEnvVarOwned(allocator, "KILNEXUS_REGISTRY_URL") catch |err| switch (err) {
        error.EnvironmentVariableNotFound => allocator.dupe(u8, default_registry),
        else => err,
    };
}

pub fn buildRegistryUrl(allocator: std.mem.Allocator, name: []const u8, version: []const u8) ![]const u8 {
    const base = try registryBase(allocator);
    defer allocator.free(base);
    return std.fmt.allocPrint(allocator, "{s}/{s}/{s}.tar.gz", .{ base, name, version });
}

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

pub fn extractTarGz(allocator: std.mem.Allocator, archive_path: []const u8, install_dir: []const u8, strip_components: u8) !void {
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

pub fn sourceDateEpochSeconds() u64 {
    const value = std.process.getEnvVarOwned(std.heap.page_allocator, "SOURCE_DATE_EPOCH") catch return 0;
    defer std.heap.page_allocator.free(value);
    return std.fmt.parseInt(u64, value, 10) catch 0;
}

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

    var gzip = try GzipStoredWriter.init(&output_writer.interface, mtime_seconds);
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
        const amt = try reader.read(reader_buffer[0..]);
        if (amt == 0) break;
        crc.update(reader_buffer[0..amt]);
    }

    try input.seekTo(0);

    var output = try cwd.createFile(output_path, .{ .truncate = true });
    defer output.close();
    var out_buffer: [32 * 1024]u8 = undefined;
    var out = output.writer(&out_buffer);

    const dos_time = dosTimeFromEpoch(mtime_seconds);
    const dos_date = dosDateFromEpoch(mtime_seconds);
    const name_len: u16 = @intCast(entry_name.len);
    const local_header_offset: u32 = 0;
    const crc32_value: u32 = crc.final();

    try writeU32(&out.interface, 0x04034b50);
    try writeU16(&out.interface, 20);
    try writeU16(&out.interface, 0);
    try writeU16(&out.interface, 0);
    try writeU16(&out.interface, dos_time);
    try writeU16(&out.interface, dos_date);
    try writeU32(&out.interface, crc32_value);
    try writeU32(&out.interface, file_size);
    try writeU32(&out.interface, file_size);
    try writeU16(&out.interface, name_len);
    try writeU16(&out.interface, 0);
    try out.interface.writeAll(entry_name);

    var file_reader = input.reader(&reader_buffer);
    try out.interface.sendFileAll(&file_reader, .unlimited);

    const central_dir_offset: u32 = @intCast(30 + entry_name.len + file_size);
    const central_dir_size: u32 = @intCast(46 + entry_name.len);

    try writeU32(&out.interface, 0x02014b50);
    try writeU16(&out.interface, 20);
    try writeU16(&out.interface, 20);
    try writeU16(&out.interface, 0);
    try writeU16(&out.interface, 0);
    try writeU16(&out.interface, dos_time);
    try writeU16(&out.interface, dos_date);
    try writeU32(&out.interface, crc32_value);
    try writeU32(&out.interface, file_size);
    try writeU32(&out.interface, file_size);
    try writeU16(&out.interface, name_len);
    try writeU16(&out.interface, 0);
    try writeU16(&out.interface, 0);
    try writeU16(&out.interface, 0);
    try writeU16(&out.interface, 0);
    try writeU32(&out.interface, 0);
    try writeU32(&out.interface, local_header_offset);
    try out.interface.writeAll(entry_name);

    try writeU32(&out.interface, 0x06054b50);
    try writeU16(&out.interface, 0);
    try writeU16(&out.interface, 0);
    try writeU16(&out.interface, 1);
    try writeU16(&out.interface, 1);
    try writeU32(&out.interface, central_dir_size);
    try writeU32(&out.interface, central_dir_offset);
    try writeU16(&out.interface, 0);

    try out.interface.flush();
}

fn writeU16(writer: *std.Io.Writer, value: u16) !void {
    var buf: [2]u8 = undefined;
    std.mem.writeInt(u16, &buf, value, .little);
    try writer.writeAll(&buf);
}

fn writeU32(writer: *std.Io.Writer, value: u32) !void {
    var buf: [4]u8 = undefined;
    std.mem.writeInt(u32, &buf, value, .little);
    try writer.writeAll(&buf);
}

fn dosTimeFromEpoch(epoch_seconds: u64) u16 {
    const seconds = epoch_seconds % 60;
    const minutes = (epoch_seconds / 60) % 60;
    const hours = (epoch_seconds / 3600) % 24;
    return @intCast((hours << 11) | (minutes << 5) | (seconds / 2));
}

fn dosDateFromEpoch(epoch_seconds: u64) u16 {
    const unix_epoch = std.time.epoch.EpochSeconds{ .secs = @as(i64, @intCast(epoch_seconds)) };
    const date = unix_epoch.getUtcDate();
    const year = @as(u16, @intCast(date.year));
    const month = @as(u16, @intCast(date.month));
    const day = @as(u16, @intCast(date.day));
    const dos_year = if (year < 1980) 0 else year - 1980;
    return @intCast((dos_year << 9) | (month << 5) | day);
}

const GzipStoredWriter = struct {
    out: *std.Io.Writer,
    block_writer: std.compress.flate.BlockWriter,
    crc: std.hash.Crc32,
    size: u32,
    writer_buffer: [4096]u8,
    buffer: [65535]u8,
    buffered: usize = 0,
    writer: std.Io.Writer,

    pub fn init(out: *std.Io.Writer, mtime_seconds: u64) !GzipStoredWriter {
        var header: [10]u8 = .{ 0x1f, 0x8b, 0x08, 0x00, 0, 0, 0, 0, 0x00, 0xff };
        const mtime: u32 = @intCast(@min(mtime_seconds, std.math.maxInt(u32)));
        std.mem.writeInt(u32, header[4..8], mtime, .little);
        try out.writeAll(&header);

        var self = GzipStoredWriter{
            .out = out,
            .block_writer = std.compress.flate.BlockWriter.init(out),
            .crc = std.hash.Crc32.init(),
            .size = 0,
            .writer_buffer = undefined,
            .buffer = undefined,
            .writer = undefined,
        };
        self.writer = .{
            .vtable = &.{ .drain = drain },
            .buffer = self.writer_buffer[0..],
        };
        return self;
    }

    pub fn finish(self: *GzipStoredWriter) !void {
        if (self.buffered > 0) {
            try self.block_writer.storedBlock(self.buffer[0..self.buffered], true);
            self.buffered = 0;
        } else {
            try self.block_writer.storedBlock("", true);
        }
        try self.block_writer.flush();

        var footer: [8]u8 = undefined;
        std.mem.writeInt(u32, footer[0..4], self.crc.final(), .little);
        std.mem.writeInt(u32, footer[4..8], self.size, .little);
        try self.out.writeAll(&footer);
        try self.out.flush();
    }

    fn drain(w: *std.Io.Writer, data: []const []const u8, splat: usize) std.Io.Writer.Error!usize {
        const self: *GzipStoredWriter = @fieldParentPtr("writer", w);
        if (w.end > 0) {
            try self.writeAll(w.buffer[0..w.end]);
            w.end = 0;
        }
        var written: usize = 0;
        for (data) |chunk| {
            try self.writeAll(chunk);
            written += chunk.len;
        }
        if (splat != 0) {
            const last = if (data.len > 0 and data[data.len - 1].len > 0)
                data[data.len - 1][data[data.len - 1].len - 1]
            else
                0;
            var remaining = splat;
            var buf: [256]u8 = undefined;
            while (remaining > 0) {
                const n = @min(remaining, buf.len);
                @memset(buf[0..n], last);
                try self.writeAll(buf[0..n]);
                remaining -= n;
            }
        }
        return written;
    }

    fn writeAll(self: *GzipStoredWriter, bytes: []const u8) !void {
        self.crc.update(bytes);
        self.size +%= @intCast(bytes.len);
        var remaining = bytes;
        while (remaining.len > 0) {
            const capacity = self.buffer.len - self.buffered;
            const chunk_len = @min(capacity, remaining.len);
            @memcpy(self.buffer[self.buffered..][0..chunk_len], remaining[0..chunk_len]);
            self.buffered += chunk_len;
            remaining = remaining[chunk_len..];
            if (self.buffered == self.buffer.len) {
                try self.block_writer.storedBlock(self.buffer[0..self.buffered], false);
                self.buffered = 0;
            }
        }
    }
};

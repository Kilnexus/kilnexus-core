const std = @import("std");

pub const GzipStoredWriter = struct {
    out: *std.Io.Writer,
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
            try self.flushBuffer(true);
        } else {
            try self.writeStoredBlock("", true);
        }

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
                try self.flushBuffer(false);
            }
        }
    }

    fn flushBuffer(self: *GzipStoredWriter, final: bool) !void {
        try self.writeStoredBlock(self.buffer[0..self.buffered], final);
        self.buffered = 0;
    }

    fn writeStoredBlock(self: *GzipStoredWriter, data: []const u8, final: bool) !void {
        const header: u8 = if (final) 0x01 else 0x00;
        try self.out.writeAll(&[_]u8{header});
        const len: u16 = @intCast(data.len);
        const nlen: u16 = ~len;
        var buf: [4]u8 = undefined;
        std.mem.writeInt(u16, buf[0..2], len, .little);
        std.mem.writeInt(u16, buf[2..4], nlen, .little);
        try self.out.writeAll(&buf);
        if (data.len > 0) {
            try self.out.writeAll(data);
        }
    }
};

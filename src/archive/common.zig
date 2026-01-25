const std = @import("std");

pub fn sourceDateEpochSeconds() u64 {
    const value = std.process.getEnvVarOwned(std.heap.page_allocator, "SOURCE_DATE_EPOCH") catch return 0;
    defer std.heap.page_allocator.free(value);
    return std.fmt.parseInt(u64, value, 10) catch 0;
}

pub fn writeU16(writer: *std.Io.Writer, value: u16) !void {
    var buf: [2]u8 = undefined;
    std.mem.writeInt(u16, &buf, value, .little);
    try writer.writeAll(&buf);
}

pub fn writeU32(writer: *std.Io.Writer, value: u32) !void {
    var buf: [4]u8 = undefined;
    std.mem.writeInt(u32, &buf, value, .little);
    try writer.writeAll(&buf);
}

pub fn dosTimeFromEpoch(epoch_seconds: u64) u16 {
    const seconds = epoch_seconds % 60;
    const minutes = (epoch_seconds / 60) % 60;
    const hours = (epoch_seconds / 3600) % 24;
    return @intCast((hours << 11) | (minutes << 5) | (seconds / 2));
}

pub fn dosDateFromEpoch(epoch_seconds: u64) u16 {
    const unix_epoch = std.time.epoch.EpochSeconds{ .secs = epoch_seconds };
    const year_day = unix_epoch.getEpochDay().calculateYearDay();
    const month_day = year_day.calculateMonthDay();
    const year = year_day.year;
    const month = @as(u16, @intCast(@intFromEnum(month_day.month) + 1));
    const day = @as(u16, @intCast(month_day.day_index + 1));
    const dos_year = if (year < 1980) 0 else year - 1980;
    return @intCast((dos_year << 9) | (month << 5) | day);
}

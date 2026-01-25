const std = @import("std");
const common = @import("common.zig");

pub fn writeLocalHeader(
    writer: *std.Io.Writer,
    dos_time: u16,
    dos_date: u16,
    name_len: u16,
    crc32_value: u32,
    file_size: u32,
    entry_name: []const u8,
) !void {
    try common.writeU32(writer, 0x04034b50);
    try common.writeU16(writer, 20);
    try common.writeU16(writer, 0);
    try common.writeU16(writer, 0);
    try common.writeU16(writer, dos_time);
    try common.writeU16(writer, dos_date);
    try common.writeU32(writer, crc32_value);
    try common.writeU32(writer, file_size);
    try common.writeU32(writer, file_size);
    try common.writeU16(writer, name_len);
    try common.writeU16(writer, 0);
    try writer.writeAll(entry_name);
}

pub fn writeCentralDirectory(
    writer: *std.Io.Writer,
    dos_time: u16,
    dos_date: u16,
    name_len: u16,
    crc32_value: u32,
    file_size: u32,
    local_header_offset: u32,
    entry_name: []const u8,
) !void {
    try common.writeU32(writer, 0x02014b50);
    try common.writeU16(writer, 20);
    try common.writeU16(writer, 20);
    try common.writeU16(writer, 0);
    try common.writeU16(writer, 0);
    try common.writeU16(writer, dos_time);
    try common.writeU16(writer, dos_date);
    try common.writeU32(writer, crc32_value);
    try common.writeU32(writer, file_size);
    try common.writeU32(writer, file_size);
    try common.writeU16(writer, name_len);
    try common.writeU16(writer, 0);
    try common.writeU16(writer, 0);
    try common.writeU16(writer, 0);
    try common.writeU16(writer, 0);
    try common.writeU32(writer, 0);
    try common.writeU32(writer, local_header_offset);
    try writer.writeAll(entry_name);
}

pub fn writeEndOfCentralDirectory(
    writer: *std.Io.Writer,
    central_dir_offset: u32,
    central_dir_size: u32,
) !void {
    try common.writeU32(writer, 0x06054b50);
    try common.writeU16(writer, 0);
    try common.writeU16(writer, 0);
    try common.writeU16(writer, 1);
    try common.writeU16(writer, 1);
    try common.writeU32(writer, central_dir_size);
    try common.writeU32(writer, central_dir_offset);
    try common.writeU16(writer, 0);
}

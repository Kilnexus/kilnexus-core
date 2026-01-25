const std = @import("std");
const manager = @import("../toolchain/manager.zig");

pub fn compareBinaries(path1: []const u8, path2: []const u8) !bool {
    var file1 = try std.fs.cwd().openFile(path1, .{});
    defer file1.close();
    var file2 = try std.fs.cwd().openFile(path2, .{});
    defer file2.close();

    const stat1 = try file1.stat();
    const stat2 = try file2.stat();
    if (stat1.size != stat2.size) return false;

    const hash1 = try sha256File(file1);
    const hash2 = try sha256File(file2);
    return std.mem.eql(u8, hash1[0..], hash2[0..]);
}

pub fn generateBuildManifest() !void {
    std.fs.cwd().makePath(".knx") catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };

    var file = try std.fs.cwd().createFile(".knx/build-manifest.json", .{ .truncate = true });
    defer file.close();

    var buffer: [4096]u8 = undefined;
    var writer = file.writer(&buffer);
    var epoch_buf: [32]u8 = undefined;
    const epoch = try std.fmt.bufPrint(&epoch_buf, "{d}", .{sourceDateEpoch()});
    try writer.interface.print(
        "{{\n  \"source_date_epoch\": {s},\n  \"host_os\": \"{s}\",\n  \"host_arch\": \"{s}\"\n}}\n",
        .{ epoch, manager.hostOsName(), manager.hostArchName() },
    );
    try writer.interface.flush();
}

fn sha256File(file: std.fs.File) ![32]u8 {
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    var buf: [32 * 1024]u8 = undefined;
    var f = file;
    try f.seekTo(0);
    while (true) {
        const amt = try f.read(buf[0..]);
        if (amt == 0) break;
        hasher.update(buf[0..amt]);
    }
    return hasher.finalResult();
}

fn sourceDateEpoch() u64 {
    const value = std.process.getEnvVarOwned(std.heap.page_allocator, "SOURCE_DATE_EPOCH") catch return 0;
    defer std.heap.page_allocator.free(value);
    return std.fmt.parseInt(u64, value, 10) catch 0;
}

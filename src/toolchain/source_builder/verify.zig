const std = @import("std");
const common = @import("common.zig");
const reproducibility = @import("../../reproducibility/verifier.zig");

pub fn verifyStages(tool: common.SourceTool, build_dir: []const u8) !void {
    const allocator = std.heap.page_allocator;
    const stage1 = try common.envOrNull(allocator, common.stageEnvKey(tool, "STAGE1_PATH"));
    defer if (stage1) |value| allocator.free(value);
    const stage2 = try common.envOrNull(allocator, common.stageEnvKey(tool, "STAGE2_PATH"));
    defer if (stage2) |value| allocator.free(value);

    if (stage1 != null and stage2 != null) {
        try compareStages(stage1.?, stage2.?);
        return;
    }

    switch (tool) {
        .Zig => {
            const stage2_name = try common.exeNameAlloc(allocator, "zig");
            defer if (stage2_name.owned) allocator.free(stage2_name.value);
            const stage2_path = try std.fs.path.join(allocator, &[_][]const u8{ build_dir, "bin", stage2_name.value });
            defer allocator.free(stage2_path);
            if (!common.fileExists(stage2_path)) return;

            const stage1_candidates = &[_][]const u8{
                "zig-stage1",
                "zig1",
            };
            for (stage1_candidates) |name| {
                const stage1_name = try common.exeNameAlloc(allocator, name);
                defer if (stage1_name.owned) allocator.free(stage1_name.value);
                const candidate = try std.fs.path.join(allocator, &[_][]const u8{ build_dir, "bin", stage1_name.value });
                defer allocator.free(candidate);
                if (common.fileExists(candidate)) {
                    try compareStages(candidate, stage2_path);
                    return;
                }
            }
        },
        .Rust => {
            const stage1_path = try findStageRustc(allocator, build_dir, "stage1");
            defer if (stage1_path) |path| allocator.free(path);
            const stage2_path = try findStageRustc(allocator, build_dir, "stage2");
            defer if (stage2_path) |path| allocator.free(path);
            if (stage1_path != null and stage2_path != null) {
                try compareStages(stage1_path.?, stage2_path.?);
                return;
            }
        },
        .Musl => return,
    }
}

pub fn compareStages(stage1: []const u8, stage2: []const u8) !void {
    const matches = try reproducibility.compareBinaries(stage1, stage2);
    if (!matches) return error.StageMismatch;
}

pub fn findStageRustc(allocator: std.mem.Allocator, build_dir: []const u8, stage: []const u8) !?[]const u8 {
    var dir = std.fs.cwd().openDir(build_dir, .{ .iterate = true }) catch return null;
    defer dir.close();
    var walker = try dir.walk(allocator);
    defer walker.deinit();
    const rustc_name = try common.exeNameAlloc(allocator, "rustc");
    defer if (rustc_name.owned) allocator.free(rustc_name.value);
    const suffix = try std.fmt.allocPrint(allocator, "{s}/bin/{s}", .{ stage, rustc_name.value });
    defer allocator.free(suffix);
    while (try walker.next()) |entry| {
        if (entry.kind != .file) continue;
        if (!std.mem.endsWith(u8, entry.path, suffix)) continue;
        return try std.fs.path.join(allocator, &[_][]const u8{ build_dir, entry.path });
    }
    return null;
}

pub fn findStageBinDir(allocator: std.mem.Allocator, build_dir: []const u8, stage: []const u8) ![]const u8 {
    var dir = std.fs.cwd().openDir(build_dir, .{ .iterate = true }) catch return error.SourceBuildMissing;
    defer dir.close();
    var walker = try dir.walk(allocator);
    defer walker.deinit();
    const suffix = try std.fmt.allocPrint(allocator, "{s}/bin", .{stage});
    defer allocator.free(suffix);
    while (try walker.next()) |entry| {
        if (entry.kind != .directory) continue;
        if (!std.mem.endsWith(u8, entry.path, suffix)) continue;
        return try std.fs.path.join(allocator, &[_][]const u8{ build_dir, entry.path });
    }
    return error.SourceBuildMissing;
}

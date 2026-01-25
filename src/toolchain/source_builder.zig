const std = @import("std");
const manager = @import("manager.zig");
const archive = @import("../archive.zig");
const reproducibility = @import("../reproducibility/verifier.zig");

pub fn buildZigFromSource(version: []const u8, sha256: ?[]const u8) !void {
    const allocator = std.heap.page_allocator;
    const source_root = try prepareSource(.Zig, version, sha256);
    defer allocator.free(source_root);
    const build_dir = try buildDirFor(.Zig, source_root, "zig-out");
    defer allocator.free(build_dir);
    try buildZig(source_root);
    try verifyStages(.Zig, build_dir, source_root);
    const install_dir = try manager.zigInstallDirRelForVersion(allocator, version);
    defer allocator.free(install_dir);
    try installFromBuild(build_dir, install_dir);
}

pub fn buildRustFromSource(version: []const u8, sha256: ?[]const u8) !void {
    const allocator = std.heap.page_allocator;
    const source_root = try prepareSource(.Rust, version, sha256);
    defer allocator.free(source_root);
    const build_dir = try buildDirFor(.Rust, source_root, "build");
    defer allocator.free(build_dir);
    try buildRust(source_root);
    try verifyStages(.Rust, build_dir, source_root);
    const install_dir = try manager.rustInstallDirRelForVersion(allocator, version);
    defer allocator.free(install_dir);
    try installRustFromStage(build_dir, install_dir);
}

pub fn buildMuslFromSource(version: []const u8, sha256: ?[]const u8) !void {
    const allocator = std.heap.page_allocator;
    const source_root = try prepareSource(.Musl, version, sha256);
    defer allocator.free(source_root);
    const build_dir = try buildDirFor(.Musl, source_root, "install");
    defer allocator.free(build_dir);
    try buildMusl(source_root, build_dir);
    const install_dir = try muslInstallDirRel(version);
    defer allocator.free(install_dir);
    try installFromBuild(build_dir, install_dir);
}

const SourceTool = enum {
    Zig,
    Rust,
    Musl,
};

fn prepareSource(tool: SourceTool, version: []const u8, sha256: ?[]const u8) ![]const u8 {
    const allocator = std.heap.page_allocator;
    const source_root = try sourceRootFor(tool, version);
    if (dirExists(source_root)) return source_root;

    try ensureDir(source_root);
    const archive_name = try sourceArchiveName(tool, version);
    defer allocator.free(archive_name);
    const archive_path = try std.fs.path.join(allocator, &[_][]const u8{ source_root, archive_name });
    defer allocator.free(archive_path);

    if (!fileExists(archive_path)) {
        const url = try sourceDownloadUrl(tool, version, archive_name);
        defer allocator.free(url);
        try archive.downloadFile(allocator, url, archive_path);
    }
    if (sha256) |expected| {
        try verifySha256(archive_path, expected);
    }

    try extractArchive(allocator, archive_path, source_root, 1);
    return source_root;
}

fn buildZig(source_root: []const u8) !void {
    const allocator = std.heap.page_allocator;
    const zig = try envOrDefault(allocator, "KILNEXUS_ZIG_BOOTSTRAP", "zig");
    defer if (zig.owned) allocator.free(zig.value);
    const args = &[_][]const u8{ zig.value, "build", "-Doptimize=ReleaseFast" };
    try runCommand(allocator, source_root, args);
}

fn buildRust(source_root: []const u8) !void {
    const allocator = std.heap.page_allocator;
    const python = try envOrDefault(allocator, "KILNEXUS_RUST_PYTHON", "python");
    defer if (python.owned) allocator.free(python.value);
    const args = &[_][]const u8{ python.value, "x.py", "build", "--stage", "2" };
    try runCommand(allocator, source_root, args);
}

fn buildMusl(source_root: []const u8, install_dir: []const u8) !void {
    const allocator = std.heap.page_allocator;
    const configure = &[_][]const u8{ "./configure", "--prefix", install_dir };
    try runCommand(allocator, source_root, configure);
    const make_args = &[_][]const u8{ "make" };
    try runCommand(allocator, source_root, make_args);
    const install_args = &[_][]const u8{ "make", "install" };
    try runCommand(allocator, source_root, install_args);
}

fn verifyStages(tool: SourceTool, build_dir: []const u8, source_root: []const u8) !void {
    const allocator = std.heap.page_allocator;
    const stage1 = try envOrNull(allocator, stageEnvKey(tool, "STAGE1_PATH"));
    defer if (stage1) |value| allocator.free(value);
    const stage2 = try envOrNull(allocator, stageEnvKey(tool, "STAGE2_PATH"));
    defer if (stage2) |value| allocator.free(value);

    if (stage1 != null and stage2 != null) {
        try compareStages(stage1.?, stage2.?);
        return;
    }

    switch (tool) {
        .Zig => {
    const stage2_name = try exeNameAlloc(allocator, "zig");
    defer if (stage2_name.owned) allocator.free(stage2_name.value);
    const stage2_path = try std.fs.path.join(allocator, &[_][]const u8{ build_dir, "bin", stage2_name.value });
    defer allocator.free(stage2_path);
    if (!fileExists(stage2_path)) return;

    const stage1_candidates = &[_][]const u8{
        "zig-stage1",
        "zig1",
    };
    for (stage1_candidates) |name| {
        const stage1_name = try exeNameAlloc(allocator, name);
        defer if (stage1_name.owned) allocator.free(stage1_name.value);
        const candidate = try std.fs.path.join(allocator, &[_][]const u8{ build_dir, "bin", stage1_name.value });
        defer allocator.free(candidate);
        if (fileExists(candidate)) {
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
        .Musl => {
            _ = source_root;
            return;
        },
    }
}

fn compareStages(stage1: []const u8, stage2: []const u8) !void {
    const matches = try reproducibility.compareBinaries(stage1, stage2);
    if (!matches) return error.StageMismatch;
}

fn findStageRustc(allocator: std.mem.Allocator, build_dir: []const u8, stage: []const u8) !?[]const u8 {
    var dir = std.fs.cwd().openDir(build_dir, .{ .iterate = true }) catch return null;
    defer dir.close();
    var walker = try dir.walk(allocator);
    defer walker.deinit();
    const rustc_name = try exeNameAlloc(allocator, "rustc");
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

fn installFromBuild(build_dir: []const u8, install_dir: []const u8) !void {
    ensureDir(install_dir) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };

    var src = try std.fs.cwd().openDir(build_dir, .{ .iterate = true });
    defer src.close();
    var dst = try std.fs.cwd().openDir(install_dir, .{ .iterate = true });
    defer dst.close();
    try copyTree(std.heap.page_allocator, src, dst);
}

fn installRustFromStage(build_dir: []const u8, install_dir: []const u8) !void {
    ensureDir(install_dir) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };
    var dst = try std.fs.cwd().openDir(install_dir, .{ .iterate = true });
    defer dst.close();
    const stage2_bin = try findStageBinDir(std.heap.page_allocator, build_dir, "stage2");
    defer std.heap.page_allocator.free(stage2_bin);
    try copyStageTools(stage2_bin, dst);
}

fn copyStageTools(stage_bin: []const u8, dst: std.fs.Dir) !void {
    var src = std.fs.cwd().openDir(stage_bin, .{ .iterate = true }) catch return error.SourceBuildMissing;
    defer src.close();

    try dst.makePath("rustc/bin");
    try dst.makePath("cargo/bin");
    var rustc_dir = try dst.openDir("rustc/bin", .{ .iterate = true });
    defer rustc_dir.close();
    var cargo_dir = try dst.openDir("cargo/bin", .{ .iterate = true });
    defer cargo_dir.close();

    try copyIfExists(src, rustc_dir, "rustc");
    try copyIfExists(src, rustc_dir, "rustdoc");
    try copyIfExists(src, cargo_dir, "cargo");
}

fn copyIfExists(src: std.fs.Dir, dst: std.fs.Dir, name: []const u8) !void {
    const allocator = std.heap.page_allocator;
    const file_name = try exeNameAlloc(allocator, name);
    defer if (file_name.owned) allocator.free(file_name.value);
    src.access(file_name.value, .{}) catch return;
    try copyFile(src, dst, file_name.value);
}

fn findStageBinDir(allocator: std.mem.Allocator, build_dir: []const u8, stage: []const u8) ![]const u8 {
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

fn copySubdir(allocator: std.mem.Allocator, root: []const u8, name: []const u8, dst: std.fs.Dir) !void {
    const path = try std.fs.path.join(allocator, &[_][]const u8{ root, name });
    defer allocator.free(path);
    var src = std.fs.cwd().openDir(path, .{ .iterate = true }) catch return error.SourceBuildMissing;
    defer src.close();
    try dst.makePath(name);
    var dst_sub = try dst.openDir(name, .{ .iterate = true });
    defer dst_sub.close();
    try copyTree(allocator, src, dst_sub);
}

fn copyTree(allocator: std.mem.Allocator, src: std.fs.Dir, dst: std.fs.Dir) !void {
    var walker = try src.walk(allocator);
    defer walker.deinit();
    while (try walker.next()) |entry| {
        switch (entry.kind) {
            .directory => try dst.makePath(entry.path),
            .file => try copyFile(src, dst, entry.path),
            else => {},
        }
    }
}

fn copyFile(src: std.fs.Dir, dst: std.fs.Dir, rel_path: []const u8) !void {
    var in_file = try src.openFile(rel_path, .{});
    defer in_file.close();
    if (std.fs.path.dirname(rel_path)) |dir_name| {
        try dst.makePath(dir_name);
    }
    var out_file = try dst.createFile(rel_path, .{ .truncate = true });
    defer out_file.close();

    var buf: [32 * 1024]u8 = undefined;
    while (true) {
        const amt = try in_file.read(buf[0..]);
        if (amt == 0) break;
        try out_file.writeAll(buf[0..amt]);
    }
}

fn ensureDir(path: []const u8) !void {
    std.fs.cwd().makePath(path);
}

fn sourceRootFor(tool: SourceTool, version: []const u8) ![]const u8 {
    const env_key = switch (tool) {
        .Zig => "KILNEXUS_ZIG_SOURCE_DIR",
        .Rust => "KILNEXUS_RUST_SOURCE_DIR",
        .Musl => "KILNEXUS_MUSL_SOURCE_DIR",
    };
    if (std.process.getEnvVarOwned(std.heap.page_allocator, env_key)) |value| {
        return value;
    } else |_| {}
    return std.fs.path.join(std.heap.page_allocator, &[_][]const u8{
        ".knx",
        "sources",
        toolName(tool),
        version,
    });
}

fn buildDirFor(tool: SourceTool, source_root: []const u8, fallback: []const u8) ![]const u8 {
    const env_key = switch (tool) {
        .Zig => "KILNEXUS_ZIG_BUILD_DIR",
        .Rust => "KILNEXUS_RUST_BUILD_DIR",
        .Musl => "KILNEXUS_MUSL_BUILD_DIR",
    };
    if (std.process.getEnvVarOwned(std.heap.page_allocator, env_key)) |value| {
        return value;
    } else |_| {}
    return std.fs.path.join(std.heap.page_allocator, &[_][]const u8{ source_root, fallback });
}

fn toolName(tool: SourceTool) []const u8 {
    return switch (tool) {
        .Zig => "zig",
        .Rust => "rust",
        .Musl => "musl",
    };
}

fn muslInstallDirRel(version: []const u8) ![]const u8 {
    return std.fs.path.join(std.heap.page_allocator, &[_][]const u8{
        ".knx",
        "toolchains",
        "musl",
        version,
    });
}

fn sourceArchiveName(tool: SourceTool, version: []const u8) ![]const u8 {
    const allocator = std.heap.page_allocator;
    const env_key = assetEnvKey(tool);
    if (std.process.getEnvVarOwned(allocator, env_key)) |value| {
        return value;
    } else |_| {}
    return switch (tool) {
        .Zig => std.fmt.allocPrint(std.heap.page_allocator, "zig-{s}.tar.xz", .{version}),
        .Rust => std.fmt.allocPrint(std.heap.page_allocator, "rustc-{s}-src.tar.xz", .{version}),
        .Musl => std.fmt.allocPrint(std.heap.page_allocator, "musl-{s}.tar.gz", .{version}),
    };
}

fn sourceDownloadUrl(tool: SourceTool, version: []const u8, archive_name: []const u8) ![]const u8 {
    const allocator = std.heap.page_allocator;
    const url_key = switch (tool) {
        .Zig => "KILNEXUS_ZIG_SOURCE_URL",
        .Rust => "KILNEXUS_RUST_SOURCE_URL",
        .Musl => "KILNEXUS_MUSL_SOURCE_URL",
    };
    if (std.process.getEnvVarOwned(allocator, url_key)) |value| {
        return value;
    } else |_| {}

    const repo = try envOrDefault(allocator, repoEnvKey(tool), defaultRepo(tool));
    defer if (repo.owned) allocator.free(repo.value);
    const tag_default = try defaultTag(tool, version);
    defer allocator.free(tag_default);
    const tag = try envOrDefault(allocator, tagEnvKey(tool), tag_default);
    defer if (tag.owned) allocator.free(tag.value);

    return std.fmt.allocPrint(allocator, "https://github.com/{s}/releases/download/{s}/{s}", .{
        repo.value,
        tag.value,
        archive_name,
    });
}

fn defaultRepo(tool: SourceTool) []const u8 {
    return switch (tool) {
        .Zig => "ziglang/zig",
        .Rust => "rust-lang/rust",
        .Musl => "ifduyue/musl",
    };
}

fn defaultTag(tool: SourceTool, version: []const u8) ![]const u8 {
    return switch (tool) {
        .Zig, .Rust => std.heap.page_allocator.dupe(u8, version),
        .Musl => std.fmt.allocPrint(std.heap.page_allocator, "v{s}", .{version}),
    };
}

fn repoEnvKey(tool: SourceTool) []const u8 {
    return switch (tool) {
        .Zig => "KILNEXUS_ZIG_SOURCE_REPO",
        .Rust => "KILNEXUS_RUST_SOURCE_REPO",
        .Musl => "KILNEXUS_MUSL_SOURCE_REPO",
    };
}

fn tagEnvKey(tool: SourceTool) []const u8 {
    return switch (tool) {
        .Zig => "KILNEXUS_ZIG_RELEASE_TAG",
        .Rust => "KILNEXUS_RUST_RELEASE_TAG",
        .Musl => "KILNEXUS_MUSL_RELEASE_TAG",
    };
}

fn assetEnvKey(tool: SourceTool) []const u8 {
    return switch (tool) {
        .Zig => "KILNEXUS_ZIG_SOURCE_ASSET",
        .Rust => "KILNEXUS_RUST_SOURCE_ASSET",
        .Musl => "KILNEXUS_MUSL_SOURCE_ASSET",
    };
}

fn stageEnvKey(tool: SourceTool, suffix: []const u8) []const u8 {
    return switch (tool) {
        .Zig => if (std.mem.eql(u8, suffix, "STAGE1_PATH")) "KILNEXUS_ZIG_STAGE1_PATH" else "KILNEXUS_ZIG_STAGE2_PATH",
        .Rust => if (std.mem.eql(u8, suffix, "STAGE1_PATH")) "KILNEXUS_RUST_STAGE1_PATH" else "KILNEXUS_RUST_STAGE2_PATH",
        .Musl => if (std.mem.eql(u8, suffix, "STAGE1_PATH")) "KILNEXUS_MUSL_STAGE1_PATH" else "KILNEXUS_MUSL_STAGE2_PATH",
    };
}

fn envOrNull(allocator: std.mem.Allocator, key: []const u8) !?[]const u8 {
    return std.process.getEnvVarOwned(allocator, key) catch |err| switch (err) {
        error.EnvironmentVariableNotFound => null,
        else => err,
    };
}

const EnvValue = struct {
    value: []const u8,
    owned: bool,
};

const OwnedStr = struct {
    value: []const u8,
    owned: bool,
};

fn envOrDefault(allocator: std.mem.Allocator, key: []const u8, default_value: []const u8) !EnvValue {
    if (std.process.getEnvVarOwned(allocator, key)) |value| {
        return .{ .value = value, .owned = true };
    } else |_| {}
    return .{ .value = default_value, .owned = false };
}

fn verifySha256(path: []const u8, expected_hex: []const u8) !void {
    if (expected_hex.len != 64) return error.InvalidSha256;
    var file = try std.fs.cwd().openFile(path, .{});
    defer file.close();
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    var buf: [32 * 1024]u8 = undefined;
    while (true) {
        const amt = try file.read(buf[0..]);
        if (amt == 0) break;
        hasher.update(buf[0..amt]);
    }
    const digest = hasher.finalResult();
    var hex_buf: [64]u8 = undefined;
    _ = try std.fmt.bufPrint(&hex_buf, "{}", .{std.fmt.fmtSliceHexLower(digest[0..])});
    if (!std.ascii.eqlIgnoreCase(hex_buf[0..], expected_hex)) return error.Sha256Mismatch;
}

fn extractArchive(allocator: std.mem.Allocator, archive_path: []const u8, install_dir: []const u8, strip_components: u8) !void {
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

fn extractTarXz(allocator: std.mem.Allocator, archive_path: []const u8, install_dir: []const u8, strip_components: u8) !void {
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

fn extractTarGz(allocator: std.mem.Allocator, archive_path: []const u8, install_dir: []const u8, strip_components: u8) !void {
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

fn runCommand(allocator: std.mem.Allocator, cwd_path: []const u8, argv: []const []const u8) !void {
    var child = std.process.Child.init(argv, allocator);
    var cwd_dir = try std.fs.cwd().openDir(cwd_path, .{});
    defer cwd_dir.close();
    child.cwd_dir = cwd_dir;
    child.stdin_behavior = .Inherit;
    child.stdout_behavior = .Inherit;
    child.stderr_behavior = .Inherit;
    const term = try child.spawnAndWait();
    switch (term) {
        .Exited => |code| if (code != 0) return error.CompileFailed,
        else => return error.CompileFailed,
    }
}

fn exeNameAlloc(allocator: std.mem.Allocator, base: []const u8) !OwnedStr {
    const builtin = @import("builtin");
    if (builtin.os.tag != .windows) return .{ .value = base, .owned = false };
    if (std.mem.endsWith(u8, base, ".exe")) return .{ .value = base, .owned = false };
    const value = try std.fmt.allocPrint(allocator, "{s}.exe", .{base});
    return .{ .value = value, .owned = true };
}

fn fileExists(path: []const u8) bool {
    std.fs.cwd().access(path, .{}) catch return false;
    return true;
}

fn dirExists(path: []const u8) bool {
    var dir = std.fs.cwd().openDir(path, .{}) catch return false;
    dir.close();
    return true;
}

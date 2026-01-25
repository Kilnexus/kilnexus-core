const std = @import("std");
const archive = @import("../../archive.zig");
const common = @import("common.zig");
const extract = @import("extract.zig");
const minisign = @import("../minisign.zig");
const verify = @import("verify.zig");

pub fn prepareSource(tool: common.SourceTool, version: []const u8, sha256: ?[]const u8) ![]const u8 {
    const allocator = std.heap.page_allocator;
    const source_root = try common.sourceRootFor(tool, version);
    if (common.dirExists(source_root)) return source_root;

    try common.ensureDir(source_root);
    const archive_name = try sourceArchiveName(tool, version);
    defer allocator.free(archive_name);
    const archive_path = try std.fs.path.join(allocator, &[_][]const u8{ source_root, archive_name });
    defer allocator.free(archive_path);

    if (!common.fileExists(archive_path)) {
        const url = try sourceDownloadUrl(tool, version, archive_name);
        defer allocator.free(url);
        try archive.downloadFile(allocator, url, archive_path);
    }
    if (sha256) |expected| {
        try verifySha256(archive_path, expected);
    }
    const public_key = minisign.getPublicKeyForTool(toolToMinisignType(tool));
    if (public_key) |key| {
        const sig_name = try sourceSignatureName(tool, version, archive_name);
        defer allocator.free(sig_name);
        const sig_path = try std.fs.path.join(allocator, &[_][]const u8{ source_root, sig_name });
        defer allocator.free(sig_path);
        if (!common.fileExists(sig_path)) {
            const sig_url = try sourceSignatureUrl(tool, version, sig_name);
            defer allocator.free(sig_url);
            try archive.downloadFile(allocator, sig_url, sig_path);
        }
        try verify.verifySha256WithSignature(archive_path, sig_path, key);
    } else if (sha256 == null) {
        return error.NoVerificationAvailable;
    }

    try extract.extractArchive(allocator, archive_path, source_root, 1);
    return source_root;
}

pub fn sourceArchiveName(tool: common.SourceTool, version: []const u8) ![]const u8 {
    const allocator = std.heap.page_allocator;
    const env_key = common.assetEnvKey(tool);
    if (std.process.getEnvVarOwned(allocator, env_key)) |value| {
        return value;
    } else |_| {}
    return switch (tool) {
        .Zig => std.fmt.allocPrint(allocator, "zig-{s}.tar.xz", .{version}),
        .Rust => std.fmt.allocPrint(allocator, "rustc-{s}-src.tar.xz", .{version}),
        .Musl => std.fmt.allocPrint(allocator, "musl-{s}.tar.gz", .{version}),
    };
}

pub fn sourceDownloadUrl(tool: common.SourceTool, version: []const u8, archive_name: []const u8) ![]const u8 {
    const allocator = std.heap.page_allocator;
    const url_key = switch (tool) {
        .Zig => "KILNEXUS_ZIG_SOURCE_URL",
        .Rust => "KILNEXUS_RUST_SOURCE_URL",
        .Musl => "KILNEXUS_MUSL_SOURCE_URL",
    };
    if (std.process.getEnvVarOwned(allocator, url_key)) |value| {
        return value;
    } else |_| {}

    const repo = try common.envOrDefault(allocator, common.repoEnvKey(tool), defaultRepo(tool));
    defer if (repo.owned) allocator.free(repo.value);
    const tag_default = try defaultTag(tool, version);
    defer allocator.free(tag_default);
    const tag = try common.envOrDefault(allocator, common.tagEnvKey(tool), tag_default);
    defer if (tag.owned) allocator.free(tag.value);

    return std.fmt.allocPrint(allocator, "https://github.com/{s}/releases/download/{s}/{s}", .{
        repo.value,
        tag.value,
        archive_name,
    });
}

pub fn sourceSignatureName(tool: common.SourceTool, version: []const u8, archive_name: []const u8) ![]const u8 {
    _ = version;
    const allocator = std.heap.page_allocator;
    const env_key = signatureAssetEnvKey(tool);
    if (std.process.getEnvVarOwned(allocator, env_key)) |value| {
        return value;
    } else |_| {}
    return std.fmt.allocPrint(allocator, "{s}.minisig", .{archive_name});
}

pub fn sourceSignatureUrl(tool: common.SourceTool, version: []const u8, signature_name: []const u8) ![]const u8 {
    const allocator = std.heap.page_allocator;
    const env_key = signatureUrlEnvKey(tool);
    if (std.process.getEnvVarOwned(allocator, env_key)) |value| {
        return value;
    } else |_| {}

    const repo = try common.envOrDefault(allocator, common.repoEnvKey(tool), defaultRepo(tool));
    defer if (repo.owned) allocator.free(repo.value);
    const tag_default = try defaultTag(tool, version);
    defer allocator.free(tag_default);
    const tag = try common.envOrDefault(allocator, common.tagEnvKey(tool), tag_default);
    defer if (tag.owned) allocator.free(tag.value);

    return std.fmt.allocPrint(allocator, "https://github.com/{s}/releases/download/{s}/{s}", .{
        repo.value,
        tag.value,
        signature_name,
    });
}

pub fn defaultRepo(tool: common.SourceTool) []const u8 {
    return switch (tool) {
        .Zig => "ziglang/zig",
        .Rust => "rust-lang/rust",
        .Musl => "ifduyue/musl",
    };
}

pub fn defaultTag(tool: common.SourceTool, version: []const u8) ![]const u8 {
    return switch (tool) {
        .Zig, .Rust => std.heap.page_allocator.dupe(u8, version),
        .Musl => std.fmt.allocPrint(std.heap.page_allocator, "v{s}", .{version}),
    };
}

fn signatureAssetEnvKey(tool: common.SourceTool) []const u8 {
    return switch (tool) {
        .Zig => "KILNEXUS_ZIG_SOURCE_SIG",
        .Rust => "KILNEXUS_RUST_SOURCE_SIG",
        .Musl => "KILNEXUS_MUSL_SOURCE_SIG",
    };
}

fn signatureUrlEnvKey(tool: common.SourceTool) []const u8 {
    return switch (tool) {
        .Zig => "KILNEXUS_ZIG_SOURCE_SIG_URL",
        .Rust => "KILNEXUS_RUST_SOURCE_SIG_URL",
        .Musl => "KILNEXUS_MUSL_SOURCE_SIG_URL",
    };
}

fn toolToMinisignType(tool: common.SourceTool) minisign.ToolType {
    return switch (tool) {
        .Zig => .Zig,
        .Rust => .Rust,
        .Musl => .Musl,
    };
}

pub fn verifySha256(path: []const u8, expected_hex: []const u8) !void {
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
    const hex_buf = std.fmt.bytesToHex(digest, .lower);
    if (!std.ascii.eqlIgnoreCase(hex_buf[0..], expected_hex)) return error.Sha256Mismatch;
}

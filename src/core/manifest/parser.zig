const std = @import("std");
const core = @import("../../root.zig");
const manifest_types = @import("types.zig");

pub fn parseManifest(
    allocator: std.mem.Allocator,
    cwd: std.fs.Dir,
    stdout: anytype,
    manifest_name: []const u8,
) !manifest_types.Manifest {
    const file = try cwd.openFile(manifest_name, .{});
    defer file.close();

    const source = try file.readToEndAlloc(allocator, 1024 * 1024);
    defer allocator.free(source);

    var parser = core.protocol.KilnexusParser.init(allocator, source);
    var manifest = manifest_types.Manifest{};

    while (true) {
        const cmd = parser.next() catch |err| {
            try stdout.print("!! {s} syntax error at line {d}: {s}\n", .{
                manifest_name,
                parser.currentLine(),
                core.protocol_error.parserErrorMessage(err),
            });
            const line_text = parser.currentLineText();
            if (line_text.len > 0) {
                try stdout.print("!!   {s}\n", .{line_text});
                const caret_line = core.protocol_error.formatCaretLine(allocator, parser.currentErrorColumn()) catch "";
                defer if (caret_line.len > 0) allocator.free(caret_line);
                if (caret_line.len > 0) {
                    try stdout.print("!!   {s}\n", .{caret_line});
                }
            }
            return err;
        } orelse break;
        switch (cmd) {
            .Project => |spec| {
                manifest.project_name = spec.name;
                if (spec.kind) |kind| manifest.project_kind = kind;
            },
            .Target => |spec| {
                manifest.target = spec.target;
                if (spec.sysroot) |sysroot| manifest.sysroot_spec = sysroot;
            },
            .Kernel => |value| manifest.kernel_version = value,
            .Sysroot => |value| manifest.sysroot_spec = value,
            .VirtualRoot => |value| manifest.virtual_root = value,
            .Build => |path| manifest.build_path = path,
            .Deterministic => |level| manifest.deterministic_level = level,
            .Isolation => |level| manifest.isolation_level = level,
            .Bootstrap => |boot| switch (boot.tool) {
                .Zig => manifest.bootstrap_versions.zig = boot.version,
                .Rust => manifest.bootstrap_versions.rust = boot.version,
                .Go => manifest.bootstrap_versions.go = boot.version,
            },
            .BootstrapFromSource => |boot| switch (boot.tool) {
                .Zig => {
                    manifest.bootstrap_sources.zig = .{ .version = boot.version, .sha256 = boot.sha256 };
                    if (manifest.bootstrap_versions.zig == null) manifest.bootstrap_versions.zig = boot.version;
                },
                .Rust => {
                    manifest.bootstrap_sources.rust = .{ .version = boot.version, .sha256 = boot.sha256 };
                    if (manifest.bootstrap_versions.rust == null) manifest.bootstrap_versions.rust = boot.version;
                },
                .Musl => manifest.bootstrap_sources.musl = .{ .version = boot.version, .sha256 = boot.sha256 },
            },
            .BootstrapSeed => |boot| {
                const existing_command = if (manifest.bootstrap_seed) |seed| seed.command else null;
                manifest.bootstrap_seed = .{
                    .version = boot.version,
                    .sha256 = boot.sha256,
                    .command = existing_command,
                };
                if (manifest.bootstrap_versions.zig == null) manifest.bootstrap_versions.zig = boot.version;
            },
            .BootstrapSeedCommand => |boot| {
                const existing_sha = if (manifest.bootstrap_seed) |seed| seed.sha256 else null;
                manifest.bootstrap_seed = .{
                    .version = boot.version,
                    .sha256 = existing_sha,
                    .command = boot.command,
                };
                if (manifest.bootstrap_versions.zig == null) manifest.bootstrap_versions.zig = boot.version;
            },
            .Use => |spec| try manifest.uses.append(allocator, .{
                .name = spec.name,
                .version = spec.version,
                .alias = spec.alias,
                .strategy = spec.strategy,
            }),
            .Pack => |pack| manifest.pack_format = pack.format,
            .StaticLibc => |spec| manifest.static_libc = .{ .name = spec.name, .version = spec.version },
            .VerifyReproducible => |value| manifest.verify_reproducible = value,
            .SandboxBuild => |value| manifest.sandbox_build = value,
        }
    }

    return manifest;
}

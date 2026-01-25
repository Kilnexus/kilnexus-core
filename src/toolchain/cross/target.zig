const std = @import("std");

pub const Arch = enum {
    x86_64,
    aarch64,
    riscv64,
    wasm32,
};

pub const Os = enum {
    linux,
    windows,
    macos,
    freestanding,
};

pub const Abi = enum {
    musl,
    gnu,
    msvc,
    none,
};

pub const GoTarget = struct {
    goos: []const u8,
    goarch: []const u8,
};

pub const CrossTarget = struct {
    arch: Arch,
    os: Os,
    abi: Abi,

    pub fn parse(raw: []const u8) !CrossTarget {
        var it = std.mem.splitScalar(u8, raw, '-');
        const arch_text = it.next() orelse return error.InvalidTarget;
        const os_text = it.next() orelse return error.InvalidTarget;
        const abi_text = it.next();
        if (it.next() != null) return error.InvalidTarget;

        const arch = parseArch(arch_text) orelse return error.InvalidTarget;
        const os = parseOs(os_text) orelse return error.InvalidTarget;
        const abi = if (abi_text) |value| parseAbi(value) orelse return error.InvalidTarget else .none;

        const target = CrossTarget{ .arch = arch, .os = os, .abi = abi };
        if (!target.validate()) return error.InvalidTarget;
        return target;
    }

    pub fn validate(self: CrossTarget) bool {
        return switch (self.arch) {
            .x86_64 => switch (self.os) {
                .linux => self.abi == .musl or self.abi == .gnu,
                .windows => self.abi == .gnu or self.abi == .msvc,
                .macos => false,
                .freestanding => false,
            },
            .aarch64 => switch (self.os) {
                .linux => self.abi == .musl,
                .macos => self.abi == .none,
                .windows => false,
                .freestanding => false,
            },
            .riscv64 => switch (self.os) {
                .linux => self.abi == .gnu,
                else => false,
            },
            .wasm32 => self.os == .freestanding and self.abi == .none,
        };
    }

    pub fn toZigTarget(self: CrossTarget) []const u8 {
        return switch (self.arch) {
            .x86_64 => switch (self.os) {
                .linux => if (self.abi == .musl) "x86_64-linux-musl" else "x86_64-linux-gnu",
                .windows => if (self.abi == .msvc) "x86_64-windows-msvc" else "x86_64-windows-gnu",
                else => unreachable,
            },
            .aarch64 => switch (self.os) {
                .linux => "aarch64-linux-musl",
                .macos => "aarch64-macos",
                else => unreachable,
            },
            .riscv64 => "riscv64-linux-gnu",
            .wasm32 => "wasm32-freestanding",
        };
    }

    pub fn toRustTarget(self: CrossTarget) []const u8 {
        return switch (self.arch) {
            .x86_64 => switch (self.os) {
                .linux => if (self.abi == .musl) "x86_64-unknown-linux-musl" else "x86_64-unknown-linux-gnu",
                .windows => if (self.abi == .msvc) "x86_64-pc-windows-msvc" else "x86_64-pc-windows-gnu",
                else => unreachable,
            },
            .aarch64 => switch (self.os) {
                .linux => "aarch64-unknown-linux-musl",
                .macos => "aarch64-apple-darwin",
                else => unreachable,
            },
            .riscv64 => "riscv64gc-unknown-linux-gnu",
            .wasm32 => "wasm32-unknown-unknown",
        };
    }

    pub fn toGoTarget(self: CrossTarget) GoTarget {
        return switch (self.arch) {
            .x86_64 => switch (self.os) {
                .linux => .{ .goos = "linux", .goarch = "amd64" },
                .windows => .{ .goos = "windows", .goarch = "amd64" },
                .macos => .{ .goos = "darwin", .goarch = "amd64" },
                .freestanding => unreachable,
            },
            .aarch64 => switch (self.os) {
                .linux => .{ .goos = "linux", .goarch = "arm64" },
                .macos => .{ .goos = "darwin", .goarch = "arm64" },
                else => unreachable,
            },
            .riscv64 => switch (self.os) {
                .linux => .{ .goos = "linux", .goarch = "riscv64" },
                else => unreachable,
            },
            .wasm32 => .{ .goos = "js", .goarch = "wasm" },
        };
    }
};

fn parseArch(raw: []const u8) ?Arch {
    if (std.ascii.eqlIgnoreCase(raw, "x86_64")) return .x86_64;
    if (std.ascii.eqlIgnoreCase(raw, "aarch64")) return .aarch64;
    if (std.ascii.eqlIgnoreCase(raw, "riscv64")) return .riscv64;
    if (std.ascii.eqlIgnoreCase(raw, "wasm32")) return .wasm32;
    return null;
}

fn parseOs(raw: []const u8) ?Os {
    if (std.ascii.eqlIgnoreCase(raw, "linux")) return .linux;
    if (std.ascii.eqlIgnoreCase(raw, "windows")) return .windows;
    if (std.ascii.eqlIgnoreCase(raw, "macos")) return .macos;
    if (std.ascii.eqlIgnoreCase(raw, "freestanding")) return .freestanding;
    return null;
}

fn parseAbi(raw: []const u8) ?Abi {
    if (std.ascii.eqlIgnoreCase(raw, "musl")) return .musl;
    if (std.ascii.eqlIgnoreCase(raw, "gnu")) return .gnu;
    if (std.ascii.eqlIgnoreCase(raw, "msvc")) return .msvc;
    if (std.ascii.eqlIgnoreCase(raw, "none")) return .none;
    return null;
}

test "parse and map linux musl target" {
    const target = try CrossTarget.parse("x86_64-linux-musl");
    try std.testing.expectEqual(Arch.x86_64, target.arch);
    try std.testing.expectEqual(Os.linux, target.os);
    try std.testing.expectEqual(Abi.musl, target.abi);
    try std.testing.expectEqualStrings("x86_64-linux-musl", target.toZigTarget());
    try std.testing.expectEqualStrings("x86_64-unknown-linux-musl", target.toRustTarget());
    const go_target = target.toGoTarget();
    try std.testing.expectEqualStrings("linux", go_target.goos);
    try std.testing.expectEqualStrings("amd64", go_target.goarch);
}

test "reject unsupported target combo" {
    try std.testing.expectError(error.InvalidTarget, CrossTarget.parse("aarch64-linux-gnu"));
}

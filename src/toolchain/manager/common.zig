pub const Toolchain = enum {
    Zig,
    Rust,
    Go,
};

pub const default_zig_version = "0.15.2";
pub const default_rust_version = "1.76.0";
pub const default_go_version = "1.22.0";

pub fn toolchainName(tool: Toolchain) []const u8 {
    return switch (tool) {
        .Zig => "zig",
        .Rust => "rust",
        .Go => "go",
    };
}

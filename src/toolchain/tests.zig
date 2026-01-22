const std = @import("std");
const zig_builder = @import("builder/zig.zig");
const rust_builder = @import("builder/rust.zig");

test "builder modules load under toolchain module root" {
    _ = std;
    _ = zig_builder;
    _ = rust_builder;
}

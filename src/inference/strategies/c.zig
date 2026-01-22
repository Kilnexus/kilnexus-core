const std = @import("std");
const iface = @import("interface.zig");

pub fn plan(ctx: iface.BuildContext) iface.BuildPlan {
    if (ctx.has_build_zig) return .ZigBuild;
    if (ctx.has_main_c) return .{ .CompileC = "main.c" };
    if (ctx.has_main_cpp) return .{ .CompileCpp = "main.cpp" };
    if (ctx.has_main_cc) return .{ .CompileCpp = "main.cc" };
    if (ctx.has_main_cxx) return .{ .CompileCpp = "main.cxx" };
    return .MissingSource;
}

test "plan prefers build.zig" {
    const ctx = iface.BuildContext{
        .has_build_zig = true,
        .has_main_c = true,
        .has_main_cpp = false,
        .has_main_cc = false,
        .has_main_cxx = false,
        .has_cargo_toml = false,
        .has_go_mod = false,
        .has_requirements = false,
        .has_pyproject = false,
        .has_setup_py = false,
    };
    try std.testing.expect(plan(ctx) == .ZigBuild);
}

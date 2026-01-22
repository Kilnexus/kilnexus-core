const std = @import("std");
const iface = @import("interface.zig");

pub fn plan(ctx: iface.BuildContext) iface.BuildPlan {
    if (ctx.has_go_mod) return .GoBuild;
    return .MissingGoModule;
}

test "plan reports missing go.mod" {
    const ctx = iface.BuildContext{
        .has_build_zig = false,
        .has_main_c = false,
        .has_main_cpp = false,
        .has_main_cc = false,
        .has_main_cxx = false,
        .has_cargo_toml = false,
        .has_go_mod = false,
        .has_requirements = false,
        .has_pyproject = false,
        .has_setup_py = false,
    };
    try std.testing.expect(plan(ctx) == .MissingGoModule);
}

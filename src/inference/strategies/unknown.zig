const iface = @import("interface.zig");

pub fn plan(_: iface.BuildContext) iface.BuildPlan {
    return .Unknown;
}

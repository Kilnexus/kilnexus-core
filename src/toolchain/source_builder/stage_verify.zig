const reproducibility = @import("../../reproducibility/verifier.zig");

pub fn verifyThreeStageBootstrap(
    stage1_binary: []const u8,
    stage2_binary: []const u8,
    stage3_binary: []const u8,
) !void {
    if (!try reproducibility.compareBinaries(stage1_binary, stage2_binary)) return error.StageMismatch;
    if (!try reproducibility.compareBinaries(stage2_binary, stage3_binary)) return error.StageMismatch;
    if (!try reproducibility.compareBinaries(stage1_binary, stage3_binary)) return error.StageMismatch;
}

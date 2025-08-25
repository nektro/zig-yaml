const std = @import("std");
const deps = @import("./deps.zig");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const mode = b.option(std.builtin.Mode, "mode", "") orelse .Debug;
    const disable_llvm = b.option(bool, "disable_llvm", "use the non-llvm zig codegen") orelse false;

    const tests = b.addTest(.{
        .root_source_file = b.path("test.zig"),
        .target = target,
        .optimize = mode,
    });
    deps.addAllTo(tests);
    tests.use_llvm = !disable_llvm;
    tests.use_lld = !disable_llvm;

    const build_options = b.addOptions();
    build_options.addOption([:0]const u8, "yamltestsuite_root", deps.dirs._hi7zwl8ps6jd);
    tests.root_module.addImport("build_options", build_options.createModule());

    const test_step = b.step("test", "Run all library tests");
    const tests_run = b.addRunArtifact(tests);
    tests_run.has_side_effects = true;
    test_step.dependOn(&tests_run.step);
}

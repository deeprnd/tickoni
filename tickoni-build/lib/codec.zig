/// Codec shim helpers for the Firedancer/Tickoni codec layer.
///
/// Contains: linkTickoniCodec(), addTickoniCodecShimLibrary(),
/// addTickoniCodecShim(), addWindowsFdManifestFixups().

const std = @import("std");
const shims = @import("shims.zig");
const firedancer_deps = @import("firedancer_deps.zig");

/// Compile shim/ballet.c (Firedancer siphash/protobuf/JSON primitives)
/// and link it into the compile step.
///
/// NOTE: For tests, use `createTickoniCodecModule` to create a shared module
/// instead, which avoids compiling ballet.c once per test binary (which causes
/// duplicate-symbol errors when the module is shared across test binaries).
pub fn addTickoniCodecShim(b: *std.Build, step: *std.Build.Step.Compile) void {
    step.root_module.link_libc = true;
    step.root_module.addIncludePath(b.path("src"));
    const target_info = step.root_module.resolved_target.?.result;
    step.root_module.addCSourceFiles(.{
        .files = &.{
            "src/tickoni/c_abi/shim/ballet.c",
        },
        .flags = shims.shimCFlagsFor(target_info),
    });
}

/// Create a shared module for ballet.c so it can be used as an import (via
/// --dep) by multiple test binaries without compiling the C file twice.
pub fn createTickoniCodecModule(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) *std.Build.Module {
    const mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    mod.addIncludePath(b.path("src"));
    const target_info = target.result;
    mod.addCSourceFiles(.{
        .files = &.{
            "src/tickoni/c_abi/shim/ballet.c",
        },
        .flags = shims.shimCFlagsFor(target_info),
    });
    return mod;
}

/// Compile the shim library as a static archive (used on Windows only).
pub fn addTickoniCodecShimLibrary(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    name: []const u8,
) *std.Build.Step.Compile {
    const mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    mod.addIncludePath(b.path("src"));
    mod.addCSourceFiles(.{
        .files = &.{
            "src/tickoni/c_abi/shim/ballet.c",
        },
        .flags = shims.shimCFlagsFor(target.result),
    });
    return b.addLibrary(.{
        .name = name,
        .linkage = .static,
        .root_module = mod,
    });
}

/// Link shim/ballet.c (provides tk_* wrappers) and the Firedancer ballet/util
/// libraries (provides fd_* symbols).
///
/// On Windows: compile ballet.c and link libfd_ballet.a / libfd_util.a.
/// On Linux: compile ballet.c for tk_* symbols; libfd_ballet.a already
/// contains fd_* symbols that linkTickoniFiredancer links separately.
pub fn linkTickoniCodec(
    b: *std.Build,
    step: *std.Build.Step.Compile,
    lib_dir: []const u8,
) void {
    addTickoniCodecShim(b, step);
    step.root_module.addLibraryPath(b.path(lib_dir));
    step.root_module.addObjectFile(.{ .cwd_relative = b.fmt("{s}/libfd_ballet.a", .{lib_dir}) });
    step.root_module.addObjectFile(.{ .cwd_relative = b.fmt("{s}/libfd_util.a", .{lib_dir}) });
    if (step.root_module.resolved_target.?.result.os.tag == .windows) {
        step.root_module.addObjectFile(.{ .cwd_relative = b.fmt("{s}/libuuid.a", .{lib_dir}) });
        step.root_module.link_libcpp = true;
        return;
    }
    // Linux: ballet.c provides tk_* symbols; libfd_ballet.a/libfd_util.a provide fd_* symbols
}

/// Read and apply Windows FD manifest fixups for Zig linkage.
pub fn addWindowsFdManifestFixups(b: *std.Build, step: *std.Build.Step.Compile, manifest_path: []const u8) void {
    if (step.root_module.resolved_target.?.result.os.tag != .windows) return;
    var threaded = std.Threaded.init_single_threaded;
    const manifest = std.Io.Dir.cwd().readFileAlloc(
        threaded.io(),
        manifest_path,
        b.allocator,
        .limited(1024 * 1024),
    ) catch @panic("missing Windows FD Zig link manifest; run just build-fd first");
    defer b.allocator.free(manifest);
    var lines = std.mem.splitScalar(u8, manifest, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0) continue;
        step.root_module.addObjectFile(.{ .cwd_relative = trimmed });
    }
}

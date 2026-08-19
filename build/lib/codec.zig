/// Codec shim helpers for the Firedancer/Tickoni codec layer.
///
/// Contains: linkTickoniCodec(), addTickoniCodecShimLibrary(),
/// addTickoniCodecShim(), addWindowsFdManifestFixups().

const std = @import("std");
const shims = @import("shims.zig");

/// Links shim/ballet.c (Firedancer siphash/protobuf/JSON primitives). Audit
/// and canonical consumer-money hash codec logic is Zig; see
/// src/tickoni/codec/audit.zig and src/tickoni/codec/thesis.zig.
pub fn linkTickoniCodec(b: *std.Build, step: *std.Build.Step.Compile, fd_lib_dir: []const u8) void {
    addTickoniCodecShim(b, step);
    if (step.root_module.resolved_target.?.result.os.tag == .windows) {
        step.root_module.addLibraryPath(b.path(fd_lib_dir));
        step.root_module.addObjectFile(.{ .cwd_relative = b.fmt("{s}/libfd_ballet.a", .{fd_lib_dir}) });
        step.root_module.addObjectFile(.{ .cwd_relative = b.fmt("{s}/libfd_util.a", .{fd_lib_dir}) });
        step.root_module.addObjectFile(.{ .cwd_relative = b.fmt("{s}/libuuid.a", .{fd_lib_dir}) });
        // Windows doesn't have pkg-config, so use link_libcpp instead of
        // linkSystemLibrary("stdc++", .{}) which would invoke pkg-config.
        step.root_module.link_libcpp = true;
        return;
    }
    linkTickoniSystemLibraries(b, step, fd_lib_dir, &.{ "fd_ballet", "fd_util" });
}

fn addTickoniCodecShim(b: *std.Build, step: *std.Build.Step.Compile) void {
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

pub fn addTickoniCodecShimLibrary(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    name: []const u8,
) *std.Build.Step.Compile {
    return addTickoniShimLibrary(b, target, optimize, name, &.{
        "src/tickoni/c_abi/shim/ballet.c",
    });
}

fn addTickoniShimLibrary(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    name: []const u8,
    files: []const []const u8,
) *std.Build.Step.Compile {
    const mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    mod.addIncludePath(b.path("src"));
    mod.addCSourceFiles(.{
        .files = files,
        .flags = shims.shimCFlagsFor(target.result),
    });
    if (target.result.os.tag == .windows) {
        mod.addCSourceFiles(.{
            .files = &.{"src/tickoni/c_abi/shim/windows_crt.c"},
            .flags = shims.shimCFlagsFor(target.result),
        });
    }
    return b.addLibrary(.{
        .name = name,
        .linkage = .static,
        .root_module = mod,
    });
}

pub fn addWindowsFdManifestFixups(b: *std.Build, step: *std.Build.Step.Compile, manifest_path: []const u8) void {
    if (step.root_module.resolved_target.?.result.os.tag != .windows) return;

    // Read and apply Windows FD manifest fixups
    const manifest = std.Io.Dir.cwd().readFileAlloc(
        std.Io.failing,
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

pub fn linkTickoniSystemLibraries(b: *std.Build, step: *std.Build.Step.Compile, fd_lib_dir: []const u8, libs: []const []const u8) void {
    step.root_module.addLibraryPath(b.path(fd_lib_dir));
    if (step.root_module.resolved_target.?.result.os.tag == .windows) {
        // COFF static linking is less forgiving about archive-member discovery
        // across deep/transitive and same-archive dependencies. Repeat the
        // closure so later unresolveds can pull additional members from the
        // same Firedancer archives.
        // Windows doesn't have pkg-config — use link_libcpp instead of
        // linkSystemLibrary("stdc++", .{}) which would invoke pkg-config on
        // a Linux host doing cross-compilation.
        for (libs) |lib| step.root_module.linkSystemLibrary(lib, .{});
        for (libs) |lib| step.root_module.linkSystemLibrary(lib, .{});
        // Windows prebuilt FD libs (from CI) reference libuuid.a.
        // contrib/fd-build-windows.sh post-build step compiles
        // libuuid_stub.c and archives it as libuuid.a so the library lookup
        // succeeds. Do NOT add libuuid_stub.c as a raw C source file here —
        // that would create duplicate symbols with the .a archive.
        step.root_module.link_libcpp = true;
    } else {
        for (libs) |lib| step.root_module.linkSystemLibrary(lib, .{});
        step.root_module.linkSystemLibrary("stdc++", .{});
    }
}

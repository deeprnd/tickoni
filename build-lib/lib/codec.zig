const std = @import("std");
const shims = @import("shims.zig");

/// Link the Firedancer system libraries (crypto, stdc++, and the
/// given FD archive list). Windows and ARM64 Linux use explicit archive paths to
/// preserve link order and avoid pkg-config.BAT probing.
pub fn addTickoniSystemLibraries(b: *std.Build, step: *std.Build.Step.Compile, fd_lib_dir: []const u8, libs: []const []const u8) void {
    step.root_module.addLibraryPath(b.path(fd_lib_dir));
    const os_tag = step.root_module.resolved_target.?.result.os.tag;
    const cpu_arch = step.root_module.resolved_target.?.result.cpu.arch;

    // Windows setup builds OpenSSL into build/opt/lib as a COFF archive. Link
    // that concrete archive rather than asking Zig to discover a system
    // `crypto` library through pkg-config.BAT or fd_lib_dir.
    if (os_tag == .windows) {
        step.root_module.addObjectFile(.{ .cwd_relative = "build/opt/lib/libcrypto.a" });
    } else {
        // OpenSSL: link libcrypto; include path is handled by system defaults.
        step.root_module.linkSystemLibrary("crypto", .{});
    }

    if (os_tag == .windows) {
        // Windows: use explicit archive paths. Avoids pkg-config.BAT probing
        // and preserves link order.
        for (libs) |lib| {
            step.root_module.addObjectFile(.{ .cwd_relative = b.fmt("{s}/lib{s}.a", .{ fd_lib_dir, lib }) });
        }
        linkTickoniWindowsUuid(b, step, fd_lib_dir);
        step.root_module.link_libcpp = true;
    } else if (os_tag == .linux and cpu_arch == .aarch64) {
        // ARM64 Linux: use explicit archive paths to preserve link order with
        // ld.lld — fd_sandbox_* symbols from libfd_util.a must resolve after
        // the shim wrappers in sandbox.c reference them.
        for (libs) |lib| {
            step.root_module.addObjectFile(.{ .cwd_relative = b.fmt("{s}/lib{s}.a", .{ fd_lib_dir, lib }) });
        }
        step.root_module.link_libcpp = true;
    } else {
        // x86_64 Linux: link explicit .a archives because only static libraries
        // are built in build/fd-tickoni-fd/lib/; linkSystemLibrary would search
        // for .so files which don't exist.
        for (libs) |lib| {
            step.root_module.addObjectFile(.{ .cwd_relative = b.fmt("{s}/lib{s}.a", .{ fd_lib_dir, lib }) });
        }
        step.root_module.link_libcpp = true;
    }
}

/// Windows FD archives carry a libuuid.a default-library reference. The
/// FD build creates this compatibility archive from libuuid_stub.c; add
/// the archive explicitly for every Windows link.
pub fn linkTickoniWindowsUuid(b: *std.Build, step: *std.Build.Step.Compile, fd_lib_dir: []const u8) void {
    if (step.root_module.resolved_target.?.result.os.tag != .windows) return;
    step.root_module.addObjectFile(.{ .cwd_relative = b.fmt("{s}/libuuid.a", .{fd_lib_dir}) });
}

/// Create a static shim library from the given C source files.
pub fn addTickoniShimLibrary(
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

/// Supervisor shim library: all shim files needed by the Tickoni supervisor executable.
pub fn addTickoniSupervisorShimLibrary(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) *std.Build.Step.Compile {
    return addTickoniShimLibrary(b, target, optimize, "tickoni-supervisor-shims", &.{
        shims.ballet_c,
        "src/tickoni/c_abi/shim/tango.c",
        "src/tickoni/c_abi/shim/util.c",
        "src/tickoni/c_abi/shim/wksp.c",
        "src/tickoni/c_abi/shim/sandbox.c",
        "src/tickoni/c_abi/shim/os.c",
        "src/tickoni/c_abi/shim/topo_run.c",
        "src/tickoni/c_abi/shim/topo_run_platform_windows.c",
        "src/tickoni/c_abi/shim/topob.c",
        "src/tickoni/c_abi/shim/tile_run.c",
    });
}

/// Codec shim library: ballet.c only.
pub fn addTickoniCodecShimLibrary(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    name: []const u8,
) *std.Build.Step.Compile {
    return addTickoniShimLibrary(b, target, optimize, name, &.{
        shims.ballet_c,
    });
}

/// Apply Windows FD manifest fixups by reading the manifest file and adding
/// each listed archive as an object file.
pub fn addWindowsFdManifestFixups(b: *std.Build, step: *std.Build.Step.Compile, manifest_path: []const u8) void {
    if (step.root_module.resolved_target.?.result.os.tag != .windows) return;

    var threaded = std.Io.Threaded.init_single_threaded;
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

/// Add ballet.c shim C source to the given compile step.
fn addTickoniCodecShim(b: *std.Build, step: *std.Build.Step.Compile) void {
    step.root_module.link_libc = true;
    step.root_module.addIncludePath(b.path("src"));
    const target_info = step.root_module.resolved_target.?.result;
    step.root_module.addCSourceFiles(.{
        .files = &.{
            shims.ballet_c,
        },
        .flags = shims.shimCFlagsFor(target_info),
    });
}

/// Link the Tickoni codec shim (ballet.c) and Firedancer ballet/util libraries.
pub fn linkTickoniCodec(b: *std.Build, step: *std.Build.Step.Compile, fd_lib_dir: []const u8) void {
    addTickoniCodecShim(b, step);
    if (step.root_module.resolved_target.?.result.os.tag == .windows) {
        step.root_module.addLibraryPath(b.path(fd_lib_dir));
        step.root_module.addObjectFile(.{ .cwd_relative = b.fmt("{s}/libfd_ballet.a", .{fd_lib_dir}) });
        step.root_module.addObjectFile(.{ .cwd_relative = b.fmt("{s}/libfd_util.a", .{fd_lib_dir}) });
        linkTickoniWindowsUuid(b, step, fd_lib_dir);
        step.root_module.link_libcpp = true;
        return;
    }
    addTickoniSystemLibraries(b, step, fd_lib_dir, &.{"fd_ballet", "fd_util"});
}

/// Generated config from build_config.json.
/// DO NOT EDIT — regenerate with: python gen_config.py
/// Paths are relative to lib_dir (set via -Dfd-lib-dir).

const std = @import("std");

/// Object file dependency entry.
pub const ObjectDep = struct {
    path: []const u8,
};

/// System library group — Firedancer .a archives and linking flags.
pub const SystemLib = struct {
    name: []const u8,
    object_deps: []const ObjectDep = &.{},
    needs_libcpp: bool = false,
};

/// System library groups from JSON.
pub const system_libs: []const SystemLib = &.{
    SystemLib{
        .name = "codec",
        .object_deps = &.{
            .{ .path = "libfd_ballet.a" },
            .{ .path = "libfd_util.a" },
        },
        .needs_libcpp = true,
    },
    SystemLib{
        .name = "fd_tango",
        .object_deps = &.{
            .{ .path = "libfd_tango.a" },
            .{ .path = "libfd_util.a" },
        },
        .needs_libcpp = true,
    },
    SystemLib{
        .name = "topo_run",
        .object_deps = &.{
            .{ .path = "libfd_disco.a" },
            .{ .path = "libfd_ballet.a" },
            .{ .path = "libfd_waltz.a" },
        },
        .needs_libcpp = false,
    },
    SystemLib{
        .name = "tile_run",
        .object_deps = &.{
            .{ .path = "libfd_disco.a" },
            .{ .path = "libfd_ballet.a" },
            .{ .path = "libfd_waltz.a" },
        },
        .needs_libcpp = false,
    },
    SystemLib{
        .name = "test_system",
        .object_deps = &.{
            .{ .path = "libfd_ballet.a" },
            .{ .path = "libfd_util.a" },
            .{ .path = "libfd_tango.a" },
            .{ .path = "libfd_disco.a" },
        },
        .needs_libcpp = true,
    },
};

/// A single platform shim entry.
pub const PlatformShim = struct {
    platform: []const u8,
    files: []const []const u8,
};

/// All domain configs from JSON. Paths are relative to lib_dir.
pub const DomainConfig = struct {
    name: []const u8,
    strategy: []const u8,
    archive_name: ?[]const u8 = null,
    c_sources: []const []const u8 = &.{},
    object_deps: []const ObjectDep = &.{},
    dependencies: []const []const u8 = &.{},
    root_source: ?[]const u8 = null,
    c_flags: []const []const u8 = &.{},
    platform_shims: ?std.StringArrayHashMapUnmanaged([]const []const u8) = null,
};

/// All domain configs from JSON. Paths are relative to lib_dir.
pub const domain_configs: []const DomainConfig = &.{
    DomainConfig{
        .name = "ballet",
        .strategy = "c_builder",
        .archive_name = "libtickoni_ballet",
        .c_sources = &.{
            "src/tickoni/c_abi/shim/ballet.c",
        },
        .object_deps = &.{
            .{ .path = "libfd_ballet.a" },
            .{ .path = "libfd_util.a" },
        },
        .dependencies = &.{
        },
        .root_source = null,
        .c_flags = &.{
            "-std=c17",
            "-U__BMI2__",
            "-U__LZCNT__",
            "-DFD_HAS_HOSTED=1",
        },
        .platform_shims = null,
    },
    DomainConfig{
        .name = "flamenco",
        .strategy = "c_builder",
        .archive_name = "libtickoni_flamenco",
        .c_sources = &.{
            "src/tickoni/c_abi/shim/tango.c",
            "src/tickoni/c_abi/shim/util.c",
            "src/tickoni/c_abi/shim/wksp.c",
            "src/tickoni/c_abi/shim/sandbox.c",
            "src/tickoni/c_abi/shim/os.c",
        },
        .object_deps = &.{
            .{ .path = "libfd_tango.a" },
            .{ .path = "libfd_util.a" },
        },
        .dependencies = &.{
        },
        .root_source = null,
        .c_flags = &.{
            "-std=c17",
            "-U__BMI2__",
            "-U__LZCNT__",
            "-DFD_HAS_HOSTED=1",
        },
        .platform_shims = null,
    },
    DomainConfig{
        .name = "disco",
        .strategy = "c_builder",
        .archive_name = "libtickoni_disco",
        .c_sources = &.{
            "src/tickoni/c_abi/shim/topo_run.c",
            "src/tickoni/c_abi/shim/topob.c",
            "src/tickoni/c_abi/shim/tile_run.c",
        },
        .object_deps = &.{
            .{ .path = "libfd_disco.a" },
        },
        .dependencies = &.{
            "ballet",
            "flamenco",
        },
        .root_source = null,
        .c_flags = &.{
            "-std=c17",
            "-U__BMI2__",
            "-U__LZCNT__",
            "-DFD_HAS_HOSTED=1",
        },
        .platform_shims = &.{
            .{ .platform = "linux", .files = &.{
                "src/tickoni/c_abi/shim/topo_run_platform_linux.c",
            } },
            .{ .platform = "macos", .files = &.{
                "src/tickoni/c_abi/shim/topo_run_platform_macos.c",
            } },
            .{ .platform = "windows", .files = &.{
                "src/tickoni/c_abi/shim/topo_run_platform_windows.c",
                "src/tickoni/c_abi/shim/windows_crt.c",
            } },
        },
    },
    DomainConfig{
        .name = "c_abi",
        .strategy = "zig_module",
        .archive_name = null,
        .c_sources = &.{
        },
        .object_deps = &.{
        },
        .dependencies = &.{
        },
        .root_source = "src/tickoni/c_abi/c_abi.zig",
        .c_flags = &.{
        },
        .platform_shims = null,
    },
    DomainConfig{
        .name = "util",
        .strategy = "zig_module",
        .archive_name = null,
        .c_sources = &.{
        },
        .object_deps = &.{
        },
        .dependencies = &.{
        },
        .root_source = "src/tickoni/util/util.zig",
        .c_flags = &.{
        },
        .platform_shims = null,
    },
    DomainConfig{
        .name = "audit",
        .strategy = "composite",
        .archive_name = null,
        .c_sources = &.{
        },
        .object_deps = &.{
        },
        .dependencies = &.{
            "c_abi",
            "util",
            "ballet",
        },
        .root_source = "src/tickoni/tiles/audit/mod.zig",
        .c_flags = &.{
        },
        .platform_shims = null,
    },
    DomainConfig{
        .name = "policy",
        .strategy = "composite",
        .archive_name = null,
        .c_sources = &.{
        },
        .object_deps = &.{
        },
        .dependencies = &.{
            "c_abi",
            "util",
            "ballet",
        },
        .root_source = "src/tickoni/tiles/policy/mod.zig",
        .c_flags = &.{
        },
        .platform_shims = null,
    },
    DomainConfig{
        .name = "model",
        .strategy = "composite",
        .archive_name = null,
        .c_sources = &.{
        },
        .object_deps = &.{
        },
        .dependencies = &.{
            "c_abi",
            "util",
            "ballet",
        },
        .root_source = "src/tickoni/tiles/model/mod.zig",
        .c_flags = &.{
        },
        .platform_shims = null,
    },
    DomainConfig{
        .name = "adapter",
        .strategy = "composite",
        .archive_name = null,
        .c_sources = &.{
        },
        .object_deps = &.{
        },
        .dependencies = &.{
            "c_abi",
            "util",
            "ballet",
            "flamenco",
            "adapter_messages",
        },
        .root_source = "src/tickoni/tiles/adapter/mod.zig",
        .c_flags = &.{
        },
        .platform_shims = null,
    },
    DomainConfig{
        .name = "case",
        .strategy = "composite",
        .archive_name = null,
        .c_sources = &.{
        },
        .object_deps = &.{
        },
        .dependencies = &.{
            "c_abi",
            "util",
            "ballet",
        },
        .root_source = "src/tickoni/tiles/case/mod.zig",
        .c_flags = &.{
        },
        .platform_shims = null,
    },
    DomainConfig{
        .name = "disp",
        .strategy = "composite",
        .archive_name = null,
        .c_sources = &.{
        },
        .object_deps = &.{
        },
        .dependencies = &.{
            "c_abi",
            "util",
            "ballet",
        },
        .root_source = "src/tickoni/tiles/disp/mod.zig",
        .c_flags = &.{
        },
        .platform_shims = null,
    },
    DomainConfig{
        .name = "agent",
        .strategy = "composite",
        .archive_name = null,
        .c_sources = &.{
        },
        .object_deps = &.{
        },
        .dependencies = &.{
            "c_abi",
            "util",
            "ballet",
        },
        .root_source = "src/tickoni/tiles/agent/mod.zig",
        .c_flags = &.{
        },
        .platform_shims = null,
    },
    DomainConfig{
        .name = "tool",
        .strategy = "composite",
        .archive_name = null,
        .c_sources = &.{
        },
        .object_deps = &.{
        },
        .dependencies = &.{
            "c_abi",
            "util",
            "ballet",
        },
        .root_source = "src/tickoni/tiles/tool/mod.zig",
        .c_flags = &.{
        },
        .platform_shims = null,
    },
    DomainConfig{
        .name = "replay",
        .strategy = "composite",
        .archive_name = null,
        .c_sources = &.{
        },
        .object_deps = &.{
        },
        .dependencies = &.{
            "c_abi",
            "util",
            "ballet",
        },
        .root_source = "src/tickoni/tiles/replay/mod.zig",
        .c_flags = &.{
        },
        .platform_shims = null,
    },
    DomainConfig{
        .name = "payment",
        .strategy = "composite",
        .archive_name = null,
        .c_sources = &.{
        },
        .object_deps = &.{
        },
        .dependencies = &.{
            "c_abi",
            "util",
            "ballet",
            "flamenco",
        },
        .root_source = "src/tickoni/tiles/payment_pipeline/mod.zig",
        .c_flags = &.{
        },
        .platform_shims = null,
    },
    DomainConfig{
        .name = "adapter_messages",
        .strategy = "zig_module",
        .archive_name = null,
        .c_sources = &.{
        },
        .object_deps = &.{
        },
        .dependencies = &.{
        },
        .root_source = "src/tickoni/tiles/adapter/messages.zig",
        .c_flags = &.{
        },
        .platform_shims = null,
    },
    DomainConfig{
        .name = "thesis",
        .strategy = "zig_module",
        .archive_name = null,
        .c_sources = &.{
        },
        .object_deps = &.{
        },
        .dependencies = &.{
        },
        .root_source = "src/tickoni/schema/consumer_money/thesis.zig",
        .c_flags = &.{
        },
        .platform_shims = null,
    },
};

/// Get domain config by name. Returns null if not found.
pub fn getDomainByName(name: []const u8) ?DomainConfig {
    for (domain_configs) |dc| {
        if (std.mem.eql(u8, dc.name, name)) return dc;
    }
    return null;
}

/// Get system lib config by name. Returns null if not found.
pub fn getSystemLibByName(name: []const u8) ?SystemLib {
    for (system_libs) |sl| {
        if (std.mem.eql(u8, sl.name, name)) return sl;
    }
    return null;
}

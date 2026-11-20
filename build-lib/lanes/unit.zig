/// Unit test lane strategy — spec-driven.
///
/// Collects compile steps in a `run_sequence` array, then chains them all
/// sequentially via `shims.addPlainTestRunSeries`, avoiding Zig 0.17's
/// protocol-mode `--listen=-` which blocks on stdin.
const std = @import("std");
const shims = @import("../lib/shims.zig");
const codec = @import("../lib/codec.zig");
const factory = @import("../factory.zig");
const lane = @import("../lane.zig");
const firedancer = @import("../lib/firedancer.zig");
const topo_run = @import("../lib/topo_run.zig");
const shared_mod = @import("../mod/modules.zig");
const test_mod = @import("../mod/test_modules.zig");

/// Register all unit test binaries. Called from build.zig.
pub fn strategy(
    b: *std.Build,
    shared: shared_mod.Shared,
    tm: test_mod.TestModules,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    fd_lib_dir: []const u8,
    exe_install: *std.Build.Step.InstallArtifact,
) void {
    const int_mods = factory.ModuleFactory.init(b, shared, tm, target, optimize).createIntModules(null);

    // Collect all compile steps for sequential run.
    var run_sequence: [65]*std.Build.Step.Compile = undefined;
    var run_count: usize = 0;

    const tb = lane.TestBuilder{
        .b = b,
        .target = target,
        .optimize = optimize,
        .fd_lib_dir = fd_lib_dir,
    };

    // === Tile-based unit tests ===

    run_sequence[run_count] = tb.registerRunTest(.{
        .name = "test-topology",
        .source_file = "src/tickoni/runtime/topology.zig",
    });
    run_count += 1;

    run_sequence[run_count] = tb.registerRunTest(.{
        .name = "test-tile",
        .source_file = "src/tickoni/runtime/tile.zig",
    });
    run_count += 1;

    // app/topologies.zig — the concrete product topologies (payment pipeline,
    // agent process graph for 1..11 tkmodl instances, investment workflow). These
    // tests were only wired into the coverage lane, which does not run on every
    // host; they run here so the graph shapes and link bounds are always checked.
    run_sequence[run_count] = tb.registerRunTest(.{
        .name = "test-topologies",
        .source_file = "src/app/tickoni/topologies.zig",
        .imports = &.{
            .{ .name = "runtime", .module = shared.runtime },
            .{ .name = "audit_mod", .module = shared.audit_mod },
        },
        .linkage = .{ .needs_codec = true, .needs_firedancer = true, .needs_topo_run = true },
    });
    run_count += 1;

    run_sequence[run_count] = tb.registerRunTest(.{
        .name = "test-model-tier",
        .source_file = "src/tickoni/runtime/model_tier.zig",
    });
    run_count += 1;

    run_sequence[run_count] = tb.registerRunTest(.{
        .name = "test-topo-build",
        .source_file = "src/tickoni/runtime/topo_build.zig",
        .imports = &.{
            .{ .name = "c_abi", .module = shared.c_abi },
            .{ .name = "logger", .module = shared.logger },
            .{ .name = "util", .module = shared.util },
        },
        .linkage = .{ .needs_codec = true, .needs_firedancer = true, .needs_topo_run = true },
    });
    run_count += 1;

    // topology_spec.zig — the supervisor->child topology handoff contract
    // (magic, version, metric_port, event_count). event_count feeds tkdedu's
    // scratch footprint, so a silent change to this serialized shape makes
    // parent and child derive different workspace layouts. Its in-file tests
    // were previously unregistered and had rotted against the current std.Io
    // API; they run here so the contract is covered at unit scope.
    run_sequence[run_count] = tb.registerRunTest(.{
        .name = "test-topology-spec",
        .source_file = "src/tickoni/runtime/topology_spec.zig",
        .imports = &.{
            .{ .name = "c_abi", .module = shared.c_abi },
            .{ .name = "logger", .module = shared.logger },
            .{ .name = "util", .module = shared.util },
        },
        .linkage = .{ .needs_codec = true, .needs_firedancer = true, .needs_topo_run = true },
    });
    run_count += 1;

    // launch_spec.zig — the supervisor->child launch handoff (identity,
    // `(tile_id, tile_kind_id)`, link handle capacity). Its in-file tests were
    // not registered in any lane; the per-tile 128-input/32-output capacity
    // and the carried kind_id are contracts the tkagnt fan-in depends on.
    run_sequence[run_count] = tb.registerRunTest(.{
        .name = "test-launch-spec",
        .source_file = "src/tickoni/runtime/launch_spec.zig",
        .imports = &.{
            .{ .name = "c_abi", .module = shared.c_abi },
            .{ .name = "logger", .module = shared.logger },
            .{ .name = "util", .module = shared.util },
        },
        .linkage = .{ .needs_codec = true, .needs_firedancer = true, .needs_topo_run = true },
    });
    run_count += 1;

    // file_io.zig — absolute-vs-relative path resolution for the binary
    // spec/config round-trips (LaunchSpec, TopologySpec, ProcessConfig all
    // sit on it). Also previously unregistered.
    run_sequence[run_count] = tb.registerRunTest(.{
        .name = "test-file-io",
        .source_file = "src/tickoni/runtime/file_io.zig",
        .imports = &.{
            .{ .name = "util", .module = shared.util },
        },
        // util.tmpDir reads ZIG_LOCAL_CACHE_DIR through c.getenv.
        .linkage = .{ .needs_libc = true },
    });
    run_count += 1;

    run_sequence[run_count] = tb.registerRunTest(.{
        .name = "test-cpu",
        .source_file = "src/tickoni/util/cpu.zig",
    });
    run_count += 1;

    run_sequence[run_count] = tb.registerRunTest(.{
        .name = "test-process",
        .source_file = "src/tickoni/util/process.zig",
    });
    run_count += 1;

    run_sequence[run_count] = tb.registerRunTest(.{
        .name = "test-supervisor-lifecycle",
        .source_file = "src/app/tickoni/supervisor.zig",
        .imports = &.{
            .{ .name = "runtime", .module = shared.runtime },
            .{ .name = "tiles", .module = shared.tiles },
            .{ .name = "c_abi", .module = shared.c_abi },
            .{ .name = "util", .module = shared.util },
            .{ .name = "topologies", .module = shared.topologies },
            .{ .name = "logger", .module = shared.logger },
        },
        .linkage = .{ .needs_codec = true, .needs_firedancer = true, .needs_topo_run = true },
    });
    run_count += 1;

    // test-process-api — needs c_abi module, util module, and os.c shim (libc).
    {
        const pa_mod = b.createModule(.{
            .root_source_file = b.path("src/tickoni/util/test_process_api.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "c_abi", .module = shared.c_abi },
                .{ .name = "util", .module = shared.util },
            },
        });
        pa_mod.addCSourceFiles(.{ .files = &.{"src/tickoni/c_abi/shim/os.c"} });
        pa_mod.addCMacro("TK_PROCESS_TEST", "1");
        switch (target.result.os.tag) {
            .linux => pa_mod.addCMacro("FD_HAS_LINUX", "1"),
            .macos => pa_mod.addCMacro("FD_HAS_MACOS", "1"),
            .windows => pa_mod.addCMacro("FD_HAS_WINDOWS", "1"),
            else => {},
        }
        if (target.result.os.tag == .windows) {
            pa_mod.linkSystemLibrary("ws2_32", .{ .use_pkg_config = .no });
        }
        pa_mod.link_libc = true;
        const pa_test = b.addTest(.{ .name = "test-process-api", .root_module = pa_mod });
        run_sequence[run_count] = pa_test;
        run_count += 1;
    }

    run_sequence[run_count] = tb.registerRunTest(.{
        .name = "test-sandbox-defaults",
        .source_file = "src/tickoni/util/sandbox_defaults.zig",
    });
    run_count += 1;

    run_sequence[run_count] = tb.registerRunTest(.{
        .name = "test-linux-ids",
        .source_file = "src/tickoni/util/linux_ids.zig",
    });
    run_count += 1;

    run_sequence[run_count] = tb.registerRunTest(.{
        .name = "test-sizes",
        .source_file = "src/tickoni/util/sizes.zig",
    });
    run_count += 1;

    run_sequence[run_count] = tb.registerRunTest(.{
        .name = "test-cabi-boot",
        .source_file = "src/tickoni/c_abi/boot.zig",
    });
    run_count += 1;

    // tier.zig — shared.tier now owns compiler_version.c linkage.
    {
        const tier_test = b.addTest(.{ .name = "test-tier", .root_module = shared.tier });
        run_sequence[run_count] = tier_test;
        run_count += 1;
    }

    // === C ABI tests (need firedancer linkage) ===

    const cabi_tests = [_]struct { path: []const u8, name: []const u8 }{
        .{ .path = "src/tickoni/c_abi/queue.zig", .name = "test-queue" },
        .{ .path = "src/tickoni/c_abi/sandbox.zig", .name = "test-sandbox" },
        .{ .path = "src/tickoni/c_abi/dcache.zig", .name = "test-dcache" },
        .{ .path = "src/tickoni/c_abi/fseq.zig", .name = "test-fseq" },
        .{ .path = "src/tickoni/c_abi/fctl.zig", .name = "test-fctl" },
        .{ .path = "src/tickoni/c_abi/cnc.zig", .name = "test-cnc" },
        .{ .path = "src/tickoni/c_abi/tempo.zig", .name = "test-tempo" },
        .{ .path = "src/tickoni/c_abi/wksp.zig", .name = "test-wksp" },
    };

    inline for (cabi_tests) |t| {
        run_sequence[run_count] = tb.registerRunTest(.{
            .name = t.name,
            .source_file = t.path,
            .linkage = .{ .needs_firedancer = true },
        });
        run_count += 1;
    }

    // ballet.zig — needs codec linkage (siphash/pb/json in shim/ballet.c).
    run_sequence[run_count] = tb.registerRunTest(.{
        .name = "test-cabi-ballet",
        .source_file = "src/tickoni/c_abi/ballet.zig",
        .linkage = .{ .needs_codec = true },
    });
    run_count += 1;

    // sandbox.zig — needs util import.
    run_sequence[run_count] = tb.registerRunTest(.{
        .name = "test-sandbox",
        .source_file = "src/tickoni/runtime/sandbox.zig",
        .imports = &.{.{ .name = "util", .module = shared.util }},
    });
    run_count += 1;

    // === Tile tests with special linkage ===

    // audit/mod.zig — needs audit_codec, audit_schema, audit_consts, fixture_audit_gen, runtime.
    // audit_consts resolved via build-module (shared.audit_consts).
    const audit_mod_root = b.createModule(.{
        .root_source_file = b.path("src/tickoni/codec/audit/mod.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "audit_codec", .module = shared.audit_codec },
            .{ .name = "audit_schema", .module = shared.audit_schema },
            .{ .name = "audit_consts", .module = shared.audit_consts },
            .{ .name = "audit_mod", .module = shared.audit_mod },
            .{ .name = "c_abi", .module = shared.c_abi },
            .{ .name = "fixture_audit_gen", .module = tm.fixture_audit_gen },
            .{ .name = "runtime", .module = shared.runtime },
        },
    });
    const test_audit = b.addTest(.{ .root_module = audit_mod_root });
    codec.linkTickoniCodec(b, test_audit, fd_lib_dir);
    firedancer.linkTickoniFiredancer(b, test_audit, fd_lib_dir);
    run_sequence[run_count] = test_audit;
    run_count += 1;

    // payment_pipeline/mod.zig — needs audit, runtime, c_abi, logger, util.
    // audit_consts resolved via build-module (shared.audit_consts).
    const pp_mod_root = b.createModule(.{
        .root_source_file = b.path("src/tickoni/tiles/payment_pipeline/mod.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "audit", .module = shared.audit },
            .{ .name = "runtime", .module = shared.runtime },
            .{ .name = "audit_consts", .module = shared.audit_consts },
            .{ .name = "audit_mod", .module = shared.audit_mod },
            .{ .name = "agent_decision", .module = shared.agent_decision },
            .{ .name = "c_abi", .module = shared.c_abi },
            .{ .name = "logger", .module = shared.logger },
            .{ .name = "util", .module = shared.util },
        },
    });
    const test_pp = b.addTest(.{ .root_module = pp_mod_root });
    codec.linkTickoniCodec(b, test_pp, fd_lib_dir);
    firedancer.linkTickoniFiredancer(b, test_pp, fd_lib_dir);
    topo_run.linkTickoniTopoRun(b, test_pp, fd_lib_dir);
    run_sequence[run_count] = test_pp;
    run_count += 1;

    // case/mod.zig — standalone.
    run_sequence[run_count] = tb.registerRunTest(.{
        .name = "test-case",
        .source_file = "src/tickoni/tiles/case/mod.zig",
    });
    run_count += 1;

    // disp/mod.zig — standalone.
    run_sequence[run_count] = tb.registerRunTest(.{
        .name = "test-disp",
        .source_file = "src/tickoni/tiles/disp/mod.zig",
    });
    run_count += 1;

    // c_abi/tkmodl.zig — identity, fixed scratch, wire layout, and
    // configuration contract unit tests for the fixture/replay model stem shim.
    run_sequence[run_count] = tb.registerRunTest(.{
        .name = "test-tkmodl-identity",
        .source_file = "src/tickoni/c_abi/tkmodl.zig",
        .imports = &.{
            .{ .name = "audit_mod", .module = shared.audit_mod },
        },
        .linkage = .{ .needs_firedancer = true, .needs_topo_run = true },
    });
    run_count += 1;

    // c_abi/multipart.zig — Zig view of the multipart content wire contract:
    // the approved bounds, header layout, and the canonical hash vector shared
    // with test_multipart.c.
    run_sequence[run_count] = tb.registerRunTest(.{
        .name = "test-multipart-wire",
        .source_file = "src/tickoni/c_abi/multipart.zig",
        .imports = &.{
            .{ .name = "audit_mod", .module = shared.audit_mod },
        },
    });
    run_count += 1;

    // tiles/agent/decision.zig — Zig-owned agent routing and classifier-result
    // interpretation (pure, plain-data in/out) and the C hook table that
    // applies it. Needs the runtime module for the model tier list and
    // audit_mod for the shared hook types.
    run_sequence[run_count] = tb.registerRunTest(.{
        .name = "test-agent-decision",
        .source_file = "src/tickoni/tiles/agent/decision.zig",
        .imports = &.{
            .{ .name = "runtime", .module = shared.runtime },
            .{ .name = "audit_mod", .module = shared.audit_mod },
        },
        .linkage = .{ .needs_codec = true, .needs_firedancer = true, .needs_topo_run = true },
    });
    run_count += 1;

    // c_abi/tkagnt.zig — identity, scratch contract and configuration
    // validation for the agent-worker stem shim registered as tkagnt.
    run_sequence[run_count] = tb.registerRunTest(.{
        .name = "test-tkagnt-identity",
        .source_file = "src/tickoni/c_abi/tkagnt.zig",
        .imports = &.{
            .{ .name = "audit_mod", .module = shared.audit_mod },
        },
        .linkage = .{ .needs_firedancer = true, .needs_topo_run = true },
    });
    run_count += 1;

    // c_abi/tkdisp.zig — identity and scratch contract for the terminal-result
    // sink stem shim registered as tkdisp.
    run_sequence[run_count] = tb.registerRunTest(.{
        .name = "test-tkdisp-identity",
        .source_file = "src/tickoni/c_abi/tkdisp.zig",
        .imports = &.{
            .{ .name = "audit_mod", .module = shared.audit_mod },
        },
        .linkage = .{ .needs_firedancer = true, .needs_topo_run = true },
    });
    run_count += 1;

    // c_abi/tkdiag.zig — identity and scratch contract for the fan-in collector
    // stem shim registered as tkdiag, plus the fragment layout and aggregation
    // rules of tk_diag_fragment.h.
    run_sequence[run_count] = tb.registerRunTest(.{
        .name = "test-tkdiag-identity",
        .source_file = "src/tickoni/c_abi/tkdiag.zig",
        .imports = &.{
            .{ .name = "audit_mod", .module = shared.audit_mod },
        },
        .linkage = .{ .needs_firedancer = true, .needs_topo_run = true },
    });
    run_count += 1;

    // c_abi/os_stats.zig — the per-process OS statistics probe tkdiag uses for
    // per-tile CPU, fault, context-switch and memory metrics (Linux runs; the
    // macOS and Windows implementations are compile-checked only).
    run_sequence[run_count] = tb.registerRunTest(.{
        .name = "test-os-stats",
        .source_file = "src/tickoni/c_abi/os_stats.zig",
        .linkage = .{ .needs_firedancer = true, .needs_topo_run = true },
    });
    run_count += 1;

    // tiles/model/validator_parity.zig — C governance helper vs the retained Zig
    // validator, branch by branch.
    run_sequence[run_count] = tb.registerRunTest(.{
        .name = "test-model-validator-parity",
        .source_file = "src/tickoni/tiles/model/validator_parity.zig",
        .imports = &.{
            .{ .name = "c_abi", .module = shared.c_abi },
            .{ .name = "model_messages", .module = tm.model_messages },
        },
        .linkage = .{ .needs_firedancer = true, .needs_topo_run = true },
    });
    run_count += 1;

    // === V2.21.S3 modules ===

    // tknorm integration test — needs firedancer linkage for fd_topo_run_tile_t,
    // util module for tmpDir/process helpers, and supervisor/topologies for
    // the full pipeline integration tests.
    // This test self-execs build/zig-out/bin/tickoni-supervisor as its tile
    // processes, so the installed binary must be rebuilt first; otherwise a stale
    // binary lays out the workspace differently from this freshly compiled parent.
    const tknorm_integration = tb.registerRunTest(.{
        .name = "test-tknorm-integration",
        .source_file = "src/tickoni/test/integration/test_tile_tknorm.zig",
        .imports = &.{
            .{ .name = "runtime", .module = shared.runtime },
            .{ .name = "c_abi", .module = shared.c_abi },
            .{ .name = "util", .module = shared.util },
            .{ .name = "topologies", .module = shared.topologies },
            .{ .name = "supervisor", .module = b.createModule(.{
                .root_source_file = b.path("src/app/tickoni/supervisor.zig"),
                .target = target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "runtime", .module = shared.runtime },
                    .{ .name = "tiles", .module = shared.tiles },
                    .{ .name = "c_abi", .module = shared.c_abi },
                    .{ .name = "util", .module = shared.util },
                    .{ .name = "topologies", .module = shared.topologies },
                    .{ .name = "logger", .module = shared.logger },
                },
            }) },
        },
        .linkage = .{ .needs_codec = true, .needs_firedancer = true, .needs_topo_run = true },
    });
    tknorm_integration.step.dependOn(&exe_install.step);
    run_sequence[run_count] = tknorm_integration;
    run_count += 1;

    // c_abi/tknorm.zig — identity + scratch footprint unit tests for norm stem shim.
    run_sequence[run_count] = tb.registerRunTest(.{
        .name = "test-tknorm-identity",
        .source_file = "src/tickoni/c_abi/tknorm.zig",
        .linkage = .{ .needs_firedancer = true, .needs_topo_run = true },
    });
    run_count += 1;

    run_sequence[run_count] = tb.registerRunTest(.{
        .name = "test-tkings-identity",
        .source_file = "src/tickoni/c_abi/tkings.zig",
        .imports = &.{.{ .name = "audit_mod", .module = shared.audit_mod }},
        .linkage = .{ .needs_firedancer = true, .needs_topo_run = true },
    });
    run_count += 1;

    // c_abi/tkdedu.zig — identity + scratch footprint unit tests for dedu
    // stem shim.
    run_sequence[run_count] = tb.registerRunTest(.{
        .name = "test-tkdedu-identity",
        .source_file = "src/tickoni/c_abi/tkdedu.zig",
        .linkage = .{ .needs_firedancer = true, .needs_topo_run = true },
    });
    run_count += 1;

    // c_abi/audit.zig — identity + scratch footprint unit tests for the audit
    // stem shim, matching the tknorm/tkdedu registrations above. Needs
    // audit_schema because the module re-exports the translate-c schema types.
    run_sequence[run_count] = tb.registerRunTest(.{
        .name = "test-tkaudt-identity",
        .source_file = "src/tickoni/c_abi/audit.zig",
        .imports = &.{
            .{ .name = "audit_schema", .module = shared.audit_schema },
        },
        .linkage = .{ .needs_firedancer = true, .needs_topo_run = true },
    });
    run_count += 1;

    // c_abi/tkpoly.zig — identity + scratch footprint unit tests for the policy
    // stem shim.  Needs firedancer linkage for fd_topo_run_tile_t, and topo_run
    // linkage for the TK_POLICY_RUN descriptor.  Also needs audit_mod for the
    // C enum constants used by the policy helper tests.
    run_sequence[run_count] = tb.registerRunTest(.{
        .name = "test-tkpoly-identity",
        .source_file = "src/tickoni/c_abi/tkpoly.zig",
        .imports = &.{
            .{ .name = "audit_mod", .module = shared.audit_mod },
        },
        .linkage = .{ .needs_firedancer = true, .needs_topo_run = true },
    });
    run_count += 1;

    // === V2.21.S3 modules ===

    // version.zig — tier, audit_schema, build_options.
    {
        const v_mod = b.createModule(.{
            .root_source_file = b.path("src/tickoni/version.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "tier", .module = shared.tier },
                .{ .name = "audit_schema", .module = shared.audit_schema },
                .{ .name = "build_options", .module = shared.version_opts.createModule() },
            },
        });
        const v_test = b.addTest(.{ .name = "test-version", .root_module = v_mod });
        run_sequence[run_count] = v_test;
        run_count += 1;
    }

    // === Schema tests (all need codec linkage) ===

    // codec/thesis.zig — thesis, basket.
    run_sequence[run_count] = tb.registerRunTest(.{
        .name = "test-codec-thesis",
        .source_file = "src/tickoni/codec/thesis.zig",
        .imports = &.{
            .{ .name = "thesis", .module = shared.thesis },
            .{ .name = "basket", .module = shared.basket },
        },
        .linkage = .{ .needs_codec = true },
    });
    run_count += 1;

    // schema/thesis.zig — classification, c_abi, fixture_paths.
    run_sequence[run_count] = tb.registerRunTest(.{
        .name = "test-thesis",
        .source_file = "src/tickoni/schema/consumer_money/thesis.zig",
        .imports = &.{
            .{ .name = "classification", .module = shared.classification },
            .{ .name = "c_abi", .module = shared.c_abi },
            .{ .name = "fixture_paths", .module = shared.fixture_paths },
        },
        .linkage = .{ .needs_codec = true },
    });
    run_count += 1;

    // schema/catalog.zig — thesis, classification, catalog_schema.
    run_sequence[run_count] = tb.registerRunTest(.{
        .name = "test-catalog",
        .source_file = "src/tickoni/schema/consumer_money/catalog.zig",
        .imports = &.{
            .{ .name = "thesis", .module = shared.thesis },
            .{ .name = "classification", .module = shared.classification },
            .{ .name = "catalog_schema", .module = shared.catalog_schema },
        },
        .linkage = .{ .needs_codec = true },
    });
    run_count += 1;

    // schema/catalog_schema.zig — thesis.
    run_sequence[run_count] = tb.registerRunTest(.{
        .name = "test-catalog-schema",
        .source_file = "src/tickoni/schema/consumer_money/catalog_schema.zig",
        .imports = &.{.{ .name = "thesis", .module = shared.thesis }},
        .linkage = .{ .needs_codec = true },
    });
    run_count += 1;

    // schema/portfolio.zig — basket.
    run_sequence[run_count] = tb.registerRunTest(.{
        .name = "test-portfolio",
        .source_file = "src/tickoni/schema/portfolio/portfolio.zig",
        .imports = &.{.{ .name = "basket", .module = shared.basket }},
        .linkage = .{ .needs_codec = true },
    });
    run_count += 1;

    // test/fixtures/portfolio/fixture_portfolio.zig — portfolio, basket.
    run_sequence[run_count] = tb.registerRunTest(.{
        .name = "test-fixture-portfolio",
        .source_file = "src/tickoni/test/fixtures/portfolio/fixture_portfolio.zig",
        .imports = &.{
            .{ .name = "portfolio", .module = shared.portfolio },
            .{ .name = "basket", .module = shared.basket },
        },
        .linkage = .{ .needs_codec = true },
    });
    run_count += 1;

    // schema/trade_ticket.zig — basket, portfolio, fixture_portfolio, thesis.
    run_sequence[run_count] = tb.registerRunTest(.{
        .name = "test-trade-ticket",
        .source_file = "src/tickoni/schema/consumer_money/trade_ticket.zig",
        .imports = &.{
            .{ .name = "basket", .module = shared.basket },
            .{ .name = "portfolio", .module = shared.portfolio },
            .{ .name = "fixture_portfolio", .module = tm.fixture_portfolio },
            .{ .name = "thesis", .module = shared.thesis },
        },
        .linkage = .{ .needs_codec = true },
    });
    run_count += 1;

    // schema/impact.zig — basket, portfolio.
    run_sequence[run_count] = tb.registerRunTest(.{
        .name = "test-impact",
        .source_file = "src/tickoni/schema/consumer_money/impact.zig",
        .imports = &.{
            .{ .name = "basket", .module = shared.basket },
            .{ .name = "portfolio", .module = shared.portfolio },
        },
        .linkage = .{ .needs_codec = true },
    });
    run_count += 1;

    // schema/basket.zig — thesis, catalog, c_abi, fixture_paths.
    run_sequence[run_count] = tb.registerRunTest(.{
        .name = "test-basket",
        .source_file = "src/tickoni/schema/consumer_money/basket.zig",
        .imports = &.{
            .{ .name = "thesis", .module = shared.thesis },
            .{ .name = "catalog", .module = shared.catalog },
            .{ .name = "c_abi", .module = shared.c_abi },
            .{ .name = "fixture_paths", .module = shared.fixture_paths },
        },
        .linkage = .{ .needs_codec = true },
    });
    run_count += 1;

    // === Logger test (needs os.c shim) ===
    {
        const logger_mod = b.createModule(.{
            .root_source_file = b.path("src/tickoni/logger.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "util", .module = shared.util }},
        });
        logger_mod.addCSourceFiles(.{
            .files = &.{"src/tickoni/c_abi/shim/os.c"},
            .flags = &.{"-std=c17"},
        });
        switch (target.result.os.tag) {
            .linux => logger_mod.addCMacro("FD_HAS_LINUX", "1"),
            .macos => logger_mod.addCMacro("FD_HAS_MACOS", "1"),
            .windows => logger_mod.addCMacro("FD_HAS_WINDOWS", "1"),
            else => {},
        }
        if (target.result.os.tag == .windows) {
            logger_mod.linkSystemLibrary("ws2_32", .{ .use_pkg_config = .no });
        }
        logger_mod.linkSystemLibrary("c", .{});
        const logger_test = b.addTest(.{ .name = "test-logger", .root_module = logger_mod });
        run_sequence[run_count] = logger_test;
        run_count += 1;
    }

    // === Investment fixture test (needs codec linkage) ===

    run_sequence[run_count] = tb.registerRunTest(.{
        .name = "test-investment-fixture",
        .source_file = "src/tickoni/test/fixtures/investment/mod.zig",
        .imports = &.{
            .{ .name = "adapter", .module = int_mods.adapter_int_mod },
            .{ .name = "basket", .module = shared.basket },
            .{ .name = "cards", .module = tm.cards },
            .{ .name = "drift", .module = tm.drift },
            .{ .name = "impact", .module = tm.impact },
            .{ .name = "investment_support", .module = int_mods.investment_support_int_mod },
            .{ .name = "model", .module = int_mods.model_int_mod },
            .{ .name = "portfolio", .module = shared.portfolio },
            .{ .name = "replay", .module = int_mods.replay_int_mod },
            .{ .name = "thesis", .module = shared.thesis },
            .{ .name = "tkpoly", .module = int_mods.tkpoly_int_mod },
            .{ .name = "tool", .module = int_mods.tool_int_mod },
            .{ .name = "trade_ticket", .module = tm.trade_ticket },
        },
        .linkage = .{ .needs_codec = true },
    });
    run_count += 1;

    // === tile_main.zig tests (P4.2/P4.3 — config handoff) ===
    // tile_main.zig — tests for loadPolicyLimit (P4.3) and the tkpoly policy
    // limit handoff path (P4.2). Needs firedancer linkage for topo_build,
    // topo_run, boot, and the C ABI tkpoly setter.
    run_sequence[run_count] = tb.registerRunTest(.{
        .name = "test-tile-main",
        .source_file = "src/app/tickoni/tile_main.zig",
        .imports = &.{
            .{ .name = "runtime", .module = shared.runtime },
            .{ .name = "tiles", .module = shared.tiles },
            .{ .name = "c_abi", .module = shared.c_abi },
            .{ .name = "util", .module = shared.util },
            .{ .name = "logger", .module = shared.logger },
        },
        .linkage = .{ .needs_codec = true, .needs_firedancer = true, .needs_topo_run = true },
    });
    run_count += 1;

    // === tkpoly_bounded.zig tests (P5.1 — bounded tile context) ===
    run_sequence[run_count] = tb.registerRunTest(.{
        .name = "test-tkpoly-bounded",
        .source_file = "src/tickoni/tiles/policy/tkpoly_bounded.zig",
        .imports = &.{
            .{ .name = "c_abi", .module = shared.c_abi },
        },
        .linkage = .{ .needs_firedancer = true, .needs_topo_run = true },
    });
    run_count += 1;

    // === tkpoly DURING_FRAG unit test (P5.2 — staging validation) ===
    // C test that exercises DURING_FRAG: size validation, chunk bounds,
    // and the invariant that invalid transport changes no counters/state.
    // Uses a static library + executable pattern to avoid Zig root-module
    // initialization issues with bare addExecutable(C-file).
    {
        const test_lib = codec.addTickoniShimLibrary(b, target, optimize, "test-tkpoly-during-frag-lib", &.{"src/tickoni/test/unit/test_tkpoly_during_frag.c"});
        test_lib.root_module.addIncludePath(b.path("src/tickoni/c_abi/shim"));
        test_lib.root_module.addIncludePath(b.path("build/fd-tickoni-fd/src"));
        test_lib.root_module.addIncludePath(b.path("build/fd-tickoni-fd/firedancer"));
        test_lib.root_module.addObjectFile(.{ .cwd_relative = b.fmt("{s}/libfd_tango.a", .{fd_lib_dir}) });
        test_lib.root_module.addObjectFile(.{ .cwd_relative = b.fmt("{s}/libfd_util.a", .{fd_lib_dir}) });
        codec.linkTickoniWindowsUuid(b, test_lib, fd_lib_dir);

        // Create executable from the static library (re-exports the main)
        const test_exe = b.addExecutable(.{
            .name = "test-tkpoly-during-frag",
            .root_module = test_lib.root_module,
        });

        run_sequence[run_count] = test_exe;
        run_count += 1;
    }

    // === tkmodl DURING_FRAG unit test ===
    // Compiles the real tile source into the test and drives the real
    // tkmodl_during_frag / tkmodl_after_frag: staging, bounds, wire-shape
    // rejection, and the abandoned-fragment (stale stage_valid) case.
    {
        const test_lib = codec.addTickoniShimLibrary(b, target, optimize, "test-tkmodl-during-frag-lib", &.{
            "src/tickoni/test/unit/test_tkmodl_during_frag.c",
            "src/tickoni/test/unit/test_tkmodl_during_frag_stub.c",
        });
        test_lib.root_module.addIncludePath(b.path("src/tickoni/c_abi/shim"));
        test_lib.root_module.addIncludePath(b.path("build/fd-tickoni-fd/src"));
        test_lib.root_module.addIncludePath(b.path("build/fd-tickoni-fd/firedancer"));
        test_lib.root_module.addObjectFile(.{ .cwd_relative = b.fmt("{s}/libfd_tango.a", .{fd_lib_dir}) });
        test_lib.root_module.addObjectFile(.{ .cwd_relative = b.fmt("{s}/libfd_util.a", .{fd_lib_dir}) });
        test_lib.root_module.addObjectFile(.{ .cwd_relative = b.fmt("{s}/libfd_disco.a", .{fd_lib_dir}) });
        test_lib.root_module.addObjectFile(.{ .cwd_relative = b.fmt("{s}/libfd_ballet.a", .{fd_lib_dir}) });
        codec.linkTickoniWindowsUuid(b, test_lib, fd_lib_dir);

        const test_exe = b.addExecutable(.{
            .name = "test-tkmodl-during-frag",
            .root_module = test_lib.root_module,
        });

        run_sequence[run_count] = test_exe;
        run_count += 1;
    }

    // === tkaudt DURING_FRAG unit test ===
    // Compiles the real tile source into the test and drives the real
    // tk_audit_during_frag / tk_audit_after_frag across two inputs with
    // disjoint chunk ranges: the range check must use the fragment's own
    // input. Reuses the tkmodl stub for tk_topo_find_tile_obj (never called).
    {
        const test_lib = codec.addTickoniShimLibrary(b, target, optimize, "test-tkaudt-during-frag-lib", &.{
            "src/tickoni/test/unit/test_tkaudt_during_frag.c",
            "src/tickoni/test/unit/test_tkmodl_during_frag_stub.c",
        });
        test_lib.root_module.addIncludePath(b.path("src/tickoni/c_abi/shim"));
        test_lib.root_module.addIncludePath(b.path("build/fd-tickoni-fd/src"));
        test_lib.root_module.addIncludePath(b.path("build/fd-tickoni-fd/firedancer"));
        test_lib.root_module.addObjectFile(.{ .cwd_relative = b.fmt("{s}/libfd_tango.a", .{fd_lib_dir}) });
        test_lib.root_module.addObjectFile(.{ .cwd_relative = b.fmt("{s}/libfd_util.a", .{fd_lib_dir}) });
        test_lib.root_module.addObjectFile(.{ .cwd_relative = b.fmt("{s}/libfd_disco.a", .{fd_lib_dir}) });
        test_lib.root_module.addObjectFile(.{ .cwd_relative = b.fmt("{s}/libfd_ballet.a", .{fd_lib_dir}) });
        codec.linkTickoniWindowsUuid(b, test_lib, fd_lib_dir);

        const test_exe = b.addExecutable(.{
            .name = "test-tkaudt-during-frag",
            .root_module = test_lib.root_module,
        });

        run_sequence[run_count] = test_exe;
        run_count += 1;
    }

    // === tkagnt admission / correlation unit test ===
    // Compiles the real tile source into the test and drives the real
    // before_frag / after_frag with multipart streams: admission, routing
    // verdicts, correlation of results to the one pending dispatch, hash
    // verification, and fail-closed handling of bad directives and streams.
    {
        const test_lib = codec.addTickoniShimLibrary(b, target, optimize, "test-tkagnt-correlation-lib", &.{
            "src/tickoni/test/unit/test_tkagnt_correlation.c",
            "src/tickoni/test/unit/test_tkmodl_during_frag_stub.c",
        });
        test_lib.root_module.addIncludePath(b.path("src/tickoni/c_abi/shim"));
        test_lib.root_module.addIncludePath(b.path("build/fd-tickoni-fd/src"));
        test_lib.root_module.addIncludePath(b.path("build/fd-tickoni-fd/firedancer"));
        test_lib.root_module.addObjectFile(.{ .cwd_relative = b.fmt("{s}/libfd_tango.a", .{fd_lib_dir}) });
        test_lib.root_module.addObjectFile(.{ .cwd_relative = b.fmt("{s}/libfd_util.a", .{fd_lib_dir}) });
        test_lib.root_module.addObjectFile(.{ .cwd_relative = b.fmt("{s}/libfd_disco.a", .{fd_lib_dir}) });
        test_lib.root_module.addObjectFile(.{ .cwd_relative = b.fmt("{s}/libfd_ballet.a", .{fd_lib_dir}) });
        codec.linkTickoniWindowsUuid(b, test_lib, fd_lib_dir);

        const test_exe = b.addExecutable(.{
            .name = "test-tkagnt-correlation",
            .root_module = test_lib.root_module,
        });

        run_sequence[run_count] = test_exe;
        run_count += 1;
    }

    // === multipart model-content framing test ===
    // Pure protocol test of tk_multipart.h (bounded reassembly + sender):
    // exact round trip across the framing boundaries and above the 16-bit fd
    // fragment size, and fail-closed handling of every malformed stream.
    {
        const test_lib = codec.addTickoniShimLibrary(b, target, optimize, "test-multipart-lib", &.{"src/tickoni/test/unit/test_multipart.c"});
        test_lib.root_module.addIncludePath(b.path("src/tickoni/c_abi/shim"));
        test_lib.root_module.addIncludePath(b.path("build/fd-tickoni-fd/src"));
        test_lib.root_module.addIncludePath(b.path("build/fd-tickoni-fd/firedancer"));
        test_lib.root_module.addObjectFile(.{ .cwd_relative = b.fmt("{s}/libfd_ballet.a", .{fd_lib_dir}) });
        test_lib.root_module.addObjectFile(.{ .cwd_relative = b.fmt("{s}/libfd_util.a", .{fd_lib_dir}) });
        codec.linkTickoniWindowsUuid(b, test_lib, fd_lib_dir);

        const test_exe = b.addExecutable(.{
            .name = "test-multipart",
            .root_module = test_lib.root_module,
        });

        run_sequence[run_count] = test_exe;
        run_count += 1;
    }

    // === P6.1 dispatcher identity test ===
    // C test that proves TK_POLICY_RUN resolves to a real policy tile
    // descriptor: name == TILE_ID_TKPOLY, privileged_init != NULL,
    // run != NULL. Links only tk_policy_stem.c (no topob.c or other shim deps).
    {
        const test_lib = codec.addTickoniShimLibrary(b, target, optimize, "test-tile-dispatcher-lib", &.{
            "src/tickoni/test/unit/test_tile_dispatcher.c",
            "src/tickoni/test/unit/test_tile_dispatcher_stub.c",
            "src/tickoni/c_abi/shim/tk_policy_stem.c",
        });
        test_lib.root_module.addIncludePath(b.path("src/tickoni/c_abi/shim"));
        test_lib.root_module.addIncludePath(b.path("build/fd-tickoni-fd/src"));
        test_lib.root_module.addIncludePath(b.path("build/fd-tickoni-fd/firedancer"));
        test_lib.root_module.addObjectFile(.{ .cwd_relative = b.fmt("{s}/libfd_tango.a", .{fd_lib_dir}) });
        test_lib.root_module.addObjectFile(.{ .cwd_relative = b.fmt("{s}/libfd_util.a", .{fd_lib_dir}) });
        test_lib.root_module.addObjectFile(.{ .cwd_relative = b.fmt("{s}/libfd_disco.a", .{fd_lib_dir}) });
        codec.linkTickoniWindowsUuid(b, test_lib, fd_lib_dir);

        // Do not name this exe "*dispatch*": Windows' installer-detection
        // heuristic treats manifest-less exes containing "patch" as installers
        // and refuses to spawn them without elevation.
        const test_exe = b.addExecutable(.{
            .name = "test-tkdisp",
            .root_module = test_lib.root_module,
        });

        run_sequence[run_count] = test_exe;
        run_count += 1;
    }

    // Top-level step: compile and run all TK unit tests sequentially.
    // Uses shims.addPlainTestRunSeries which avoids Zig 0.17 protocol-mode.
    const test_unit_tk_run = shims.addPlainTestRunSeries(b, run_sequence[0..run_count]);
    const test_unit_tk_step = b.step("test-unit-tk", "Compile and run all TK unit tests sequentially");
    test_unit_tk_step.dependOn(&test_unit_tk_run.step);
}

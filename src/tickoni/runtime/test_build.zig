/// Single source of truth for "is this compilation part of a test build?"
///
/// Use `enabled` to gate test-only code — synthetic-input injection,
/// fault-injection hooks, and similar. Do NOT write
/// `@import("builtin").is_test` at a call site: that is only half the
/// answer, and mixing the two leaves no single rule for which to reach for.
///
/// `is_test` alone is insufficient because Tickoni runs tiles in two shapes:
///
/// - Thread mode: tiles run inside the Zig test binary (`b.addTest`), where
///   `@import("builtin").is_test` is true.
/// - Process mode: the supervisor fork+execs
///   `build/zig-out/bin/tickoni-supervisor` once per tile (see
///   src/app/tickoni/tile_registry.zig's process-mode wrappers, which call
///   into src/tickoni/tiles/payment_pipeline/process.zig). That binary is
///   built with `b.addExecutable`, so `is_test` is FALSE inside it even
///   though a test is driving the run. Test-only code gated on `is_test`
///   alone is silently dead in every process-mode integration test.
///
/// `TK_TEST_BUILD` closes that gap. It is set from `-Dtest=true`, the only
/// configuration under which build.zig registers the test lanes, so a
/// production `just build` leaves it false and every gated branch is
/// eliminated at compile time.
const build_options = @import("build_options");

/// True in Zig test binaries and in the `-Dtest=true` supervisor executable;
/// false in production builds. Comptime-known, so `if (enabled)` compiles the
/// branch out entirely when false.
pub const enabled: bool = @import("builtin").is_test or build_options.TK_TEST_BUILD;

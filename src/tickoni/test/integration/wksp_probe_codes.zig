/// Exit codes of tk-wksp-probe, shared by the probe (wksp_probe_main.zig) and
/// the test that reads them (test_process_wksp_exclusive_create.zig), so the
/// two cannot drift.

/// The probe created the workspace (and deleted it again).
pub const created: u8 = 0;
/// The create failed.
pub const refused: u8 = 10;
/// Bad arguments or boot failure; the probe never tried the create.
pub const usage: u8 = 2;

/// Pages of the workspace both the holder and the probe create. Equal shapes
/// make a refusal attributable to the name alone.
pub const page_cnt: usize = 256;

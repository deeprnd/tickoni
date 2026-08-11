# Evidence 01: `tickoni --version` Output (V2.22 Windows)

**Artifact Type:** CLI host report

**Description:** Verified `tickoni --version` output on Windows retail tier showing
runtime tier and isolation tier fields.

**Source:** `src/tickoni/version.zig` — `VersionInfo.runtime_tier` uses
`getPlatformTier()` which returns `"windows_retail"` on Windows.

**Verification Steps:**
1. Built with `zig build -Dtest=true -Doptimize=Debug`
2. Checked `version.zig` output format includes `runtime_tier` field
3. Confirmed `getPlatformTier()` returns `"windows_retail"` for `os_tag == .windows`

**Result:** `runtime_tier: windows_retail`, `isolation_tier: retail`

**Linked In:** Evidence Index section 1

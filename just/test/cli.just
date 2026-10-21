# ── Test: CLI conformance recipes ──────────────────────────────────────────

# Deterministic offline investment conformance suite — fixture-backed, no llama.cpp required.
test-cli-tk:
    bash contrib/test/run_cli_conformance_tests.sh

test-cli-all: test-cli-tk
test-cli-tk-linux-x86: test-cli-tk
test-cli-tk-linux-arm: test-cli-tk
test-cli-tk-macos-x86: test-cli-tk
test-cli-tk-macos-arm: test-cli-tk
test-cli-tk-windows-x86: test-cli-tk
test-cli-tk-windows-arm: test-cli-tk

# Build and export the platform conformance artifact consumed by the compare job.
export-build-artifact-conformance-linux-x86:
    ZIG_LOCAL_CACHE_DIR={{ ZIG_CACHE }} ZIG_GLOBAL_CACHE_DIR={{ ZIG_GLOBAL_CACHE }} zig build -Dfd-lib-dir={{ fd_tickoni_lib }}
    {{ python }} contrib/test/export_build_artifact_conformance.py . build/build-artifact-conformance/linux-x86

export-build-artifact-conformance-macos-x86:
    ZIG_LOCAL_CACHE_DIR={{ ZIG_CACHE }} ZIG_GLOBAL_CACHE_DIR={{ ZIG_GLOBAL_CACHE }} zig build -Dfd-lib-dir={{ fd_tickoni_lib }}
    {{ python }} contrib/test/export_build_artifact_conformance.py . build/build-artifact-conformance/macos-x86

export-build-artifact-conformance-macos-arm:
    ZIG_LOCAL_CACHE_DIR={{ ZIG_CACHE }} ZIG_GLOBAL_CACHE_DIR={{ ZIG_GLOBAL_CACHE }} zig build -Dfd-lib-dir={{ fd_tickoni_lib }}
    {{ python }} contrib/test/export_build_artifact_conformance.py . build/build-artifact-conformance/macos-arm

export-build-artifact-conformance-macos-26-x86:
    ZIG_LOCAL_CACHE_DIR={{ ZIG_CACHE }} ZIG_GLOBAL_CACHE_DIR={{ ZIG_GLOBAL_CACHE }} zig build -Dfd-lib-dir={{ fd_tickoni_lib }}
    {{ python }} contrib/test/export_build_artifact_conformance.py . build/build-artifact-conformance/macos-26-x86

export-build-artifact-conformance-macos-26-arm:
    ZIG_LOCAL_CACHE_DIR={{ ZIG_CACHE }} ZIG_GLOBAL_CACHE_DIR={{ ZIG_GLOBAL_CACHE }} zig build -Dfd-lib-dir={{ fd_tickoni_lib }}
    {{ python }} contrib/test/export_build_artifact_conformance.py . build/build-artifact-conformance/macos-26-arm

export-build-artifact-conformance-windows-x86:
    bash -lc "ZIG_LOCAL_CACHE_DIR={{ ZIG_CACHE }} ZIG_GLOBAL_CACHE_DIR={{ ZIG_GLOBAL_CACHE }} zig build -Dfd-lib-dir={{ fd_tickoni_lib }} --summary all"
    {{ python }} contrib/test/export_build_artifact_conformance.py . build/build-artifact-conformance/windows-x86

export-build-artifact-conformance-windows-arm:
    bash -lc "ZIG_LOCAL_CACHE_DIR={{ ZIG_CACHE }} ZIG_GLOBAL_CACHE_DIR={{ ZIG_GLOBAL_CACHE }} zig build -Dfd-lib-dir={{ fd_tickoni_lib }} --summary all"
    {{ python }} contrib/test/export_build_artifact_conformance.py . build/build-artifact-conformance/windows-arm

compare-build-artifact-conformance:
    {{ python }} contrib/test/compare_build_artifact_conformance.py build/build-artifact-conformance/linux-x86/conformance.json build/build-artifact-conformance/linux-arm/conformance.json build/build-artifact-conformance/macos-15-x86/conformance.json build/build-artifact-conformance/macos-15-arm/conformance.json build/build-artifact-conformance/macos-26-x86/conformance.json build/build-artifact-conformance/macos-26-arm/conformance.json build/build-artifact-conformance/windows-x86/conformance.json build/build-artifact-conformance/windows-arm/conformance.json

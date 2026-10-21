# ── Build: Artifact export recipes ─────────────────────────────────────────

# Build tests, run the domain integration suite (which writes conformance.json
# when TK_CONFORMANCE_JSON is set), then verify the output.
export-build-artifact-conformance-linux-x86:
    mkdir -p build/build-artifact-conformance/linux-x86
    ZIG_LOCAL_CACHE_DIR={{ ZIG_CACHE }} ZIG_GLOBAL_CACHE_DIR={{ ZIG_GLOBAL_CACHE }} \
        TK_CONFORMANCE_JSON=build/build-artifact-conformance/linux-x86 \
        zig build -Dtest=true -Dfd-lib-dir={{ fd_tickoni_lib }} \
        integration-test-domain

export-build-artifact-conformance-linux-arm:
    mkdir -p build/build-artifact-conformance/linux-arm
    ZIG_LOCAL_CACHE_DIR={{ ZIG_CACHE }} ZIG_GLOBAL_CACHE_DIR={{ ZIG_GLOBAL_CACHE }} \
        TK_CONFORMANCE_JSON=build/build-artifact-conformance/linux-arm \
        zig build -Dtest=true -Dfd-lib-dir={{ fd_tickoni_lib }} \
        integration-test-domain

export-build-artifact-conformance-macos-15-x86:
    mkdir -p build/build-artifact-conformance/macos-15-x86
    ZIG_LOCAL_CACHE_DIR={{ ZIG_CACHE }} ZIG_GLOBAL_CACHE_DIR={{ ZIG_GLOBAL_CACHE }} \
        TK_CONFORMANCE_JSON=build/build-artifact-conformance/macos-15-x86 \
        zig build -Dtest=true -Dfd-lib-dir={{ fd_tickoni_lib }} \
        integration-test-domain

export-build-artifact-conformance-macos-15-arm:
    mkdir -p build/build-artifact-conformance/macos-15-arm
    ZIG_LOCAL_CACHE_DIR={{ ZIG_CACHE }} ZIG_GLOBAL_CACHE_DIR={{ ZIG_GLOBAL_CACHE }} \
        TK_CONFORMANCE_JSON=build/build-artifact-conformance/macos-15-arm \
        zig build -Dtest=true -Dfd-lib-dir={{ fd_tickoni_lib }} \
        integration-test-domain

export-build-artifact-conformance-macos-26-x86:
    mkdir -p build/build-artifact-conformance/macos-26-x86
    ZIG_LOCAL_CACHE_DIR={{ ZIG_CACHE }} ZIG_GLOBAL_CACHE_DIR={{ ZIG_GLOBAL_CACHE }} \
        TK_CONFORMANCE_JSON=build/build-artifact-conformance/macos-26-x86 \
        zig build -Dtest=true -Dfd-lib-dir={{ fd_tickoni_lib }} \
        integration-test-domain

export-build-artifact-conformance-macos-26-arm:
    mkdir -p build/build-artifact-conformance/macos-26-arm
    ZIG_LOCAL_CACHE_DIR={{ ZIG_CACHE }} ZIG_GLOBAL_CACHE_DIR={{ ZIG_GLOBAL_CACHE }} \
        TK_CONFORMANCE_JSON=build/build-artifact-conformance/macos-26-arm \
        zig build -Dtest=true -Dfd-lib-dir={{ fd_tickoni_lib }} \
        integration-test-domain

export-build-artifact-conformance-windows-x86:
    mkdir -p build/build-artifact-conformance/windows-x86
    bash -lc "ZIG_LOCAL_CACHE_DIR={{ ZIG_CACHE }} ZIG_GLOBAL_CACHE_DIR={{ ZIG_GLOBAL_CACHE }} \
        TK_CONFORMANCE_JSON=build/build-artifact-conformance/windows-x86 \
        zig build -Dtest=true -Dfd-lib-dir={{ fd_tickoni_lib }} \
        integration-test-domain --summary all"

export-build-artifact-conformance-windows-arm:
    mkdir -p build/build-artifact-conformance/windows-arm
    bash -lc "ZIG_LOCAL_CACHE_DIR={{ ZIG_CACHE }} ZIG_GLOBAL_CACHE_DIR={{ ZIG_GLOBAL_CACHE }} \
        TK_CONFORMANCE_JSON=build/build-artifact-conformance/windows-arm \
        zig build -Dtest=true -Dfd-lib-dir={{ fd_tickoni_lib }} \
        integration-test-domain --summary all"

# Compare build artifacts across all platforms for conformance.
compare-build-artifact-conformance:
    {{ python }} contrib/test/compare_build_artifact_conformance.py build/build-artifact-conformance/linux-x86/conformance.json build/build-artifact-conformance/linux-arm/conformance.json build/build-artifact-conformance/macos-15-x86/conformance.json build/build-artifact-conformance/macos-15-arm/conformance.json build/build-artifact-conformance/macos-26-x86/conformance.json build/build-artifact-conformance/macos-26-arm/conformance.json build/build-artifact-conformance/windows-x86/conformance.json build/build-artifact-conformance/windows-arm/conformance.json

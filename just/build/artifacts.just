# ── Build: Artifact export recipes ─────────────────────────────────────────
!default

output_dir = build/build-artifact-conformance/linux-x86

# Build tests, run the domain integration suite (which writes conformance.json
# when TICKONI_CONFORMANCE_JSON is set), then verify the output.
export-build-artifact-conformance-linux-x86:
    mkdir -p {{ output_dir }}
    ZIG_LOCAL_CACHE_DIR={{ ZIG_CACHE }} ZIG_GLOBAL_CACHE_DIR={{ ZIG_GLOBAL_CACHE }} \
        TICKONI_CONFORMANCE_JSON={{ output_dir }} \
        zig build -Dtest=true -Dfd-lib-dir={{ fd_tickoni_lib }} \
        integration-test-domain

output_dir = build/build-artifact-conformance/macos-x86
export-build-artifact-conformance-macos-x86:
    mkdir -p {{ output_dir }}
    ZIG_LOCAL_CACHE_DIR={{ ZIG_CACHE }} ZIG_GLOBAL_CACHE_DIR={{ ZIG_GLOBAL_CACHE }} \
        TICKONI_CONFORMANCE_JSON={{ output_dir }} \
        zig build -Dtest=true -Dfd-lib-dir={{ fd_tickoni_lib }} \
        integration-test-domain

output_dir = build/build-artifact-conformance/macos-arm
export-build-artifact-conformance-macos-arm:
    mkdir -p {{ output_dir }}
    ZIG_LOCAL_CACHE_DIR={{ ZIG_CACHE }} ZIG_GLOBAL_CACHE_DIR={{ ZIG_GLOBAL_CACHE }} \
        TICKONI_CONFORMANCE_JSON={{ output_dir }} \
        zig build -Dtest=true -Dfd-lib-dir={{ fd_tickoni_lib }} \
        integration-test-domain

output_dir = build/build-artifact-conformance/macos-26-x86
export-build-artifact-conformance-macos-26-x86:
    mkdir -p {{ output_dir }}
    ZIG_LOCAL_CACHE_DIR={{ ZIG_CACHE }} ZIG_GLOBAL_CACHE_DIR={{ ZIG_GLOBAL_CACHE }} \
        TICKONI_CONFORMANCE_JSON={{ output_dir }} \
        zig build -Dtest=true -Dfd-lib-dir={{ fd_tickoni_lib }} \
        integration-test-domain

output_dir = build/build-artifact-conformance/macos-26-arm
export-build-artifact-conformance-macos-26-arm:
    mkdir -p {{ output_dir }}
    ZIG_LOCAL_CACHE_DIR={{ ZIG_CACHE }} ZIG_GLOBAL_CACHE_DIR={{ ZIG_GLOBAL_CACHE }} \
        TICKONI_CONFORMANCE_JSON={{ output_dir }} \
        zig build -Dtest=true -Dfd-lib-dir={{ fd_tickoni_lib }} \
        integration-test-domain

output_dir = build/build-artifact-conformance/windows-x86
export-build-artifact-conformance-windows-x86:
    mkdir -p {{ output_dir }}
    bash -lc "ZIG_LOCAL_CACHE_DIR={{ ZIG_CACHE }} ZIG_GLOBAL_CACHE_DIR={{ ZIG_GLOBAL_CACHE }} \
        TICKONI_CONFORMANCE_JSON={{ output_dir }} \
        zig build -Dtest=true -Dfd-lib-dir={{ fd_tickoni_lib }} \
        integration-test-domain --summary all"

output_dir = build/build-artifact-conformance/windows-arm
export-build-artifact-conformance-windows-arm:
    mkdir -p {{ output_dir }}
    bash -lc "ZIG_LOCAL_CACHE_DIR={{ ZIG_CACHE }} ZIG_GLOBAL_CACHE_DIR={{ ZIG_GLOBAL_CACHE }} \
        TICKONI_CONFORMANCE_JSON={{ output_dir }} \
        zig build -Dtest=true -Dfd-lib-dir={{ fd_tickoni_lib }} \
        integration-test-domain --summary all"

# Compare build artifacts across all platforms for conformance.
compare-build-artifact-conformance:
    {{ python }} contrib/test/compare_build_artifact_conformance.py build/build-artifact-conformance/linux-x86/conformance.json build/build-artifact-conformance/linux-arm/conformance.json build/build-artifact-conformance/macos-15-x86/conformance.json build/build-artifact-conformance/macos-15-arm/conformance.json build/build-artifact-conformance/macos-26-x86/conformance.json build/build-artifact-conformance/macos-26-arm/conformance.json build/build-artifact-conformance/windows-x86/conformance.json build/build-artifact-conformance/windows-arm/conformance.json

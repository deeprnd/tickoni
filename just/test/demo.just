# Test: Demo conformance recipes

# Deterministic offline investment conformance suite — fixture-backed, no llama.cpp required.
test-demo-tk:
    bash contrib/test/run_cli_demo_tests.sh

test-demo-tk-linux-x86: test-demo-tk
test-demo-tk-macos-x86: test-demo-tk
test-demo-tk-macos-arm: test-demo-tk
test-demo-tk-windows-x86: test-demo-tk
test-demo-tk-windows-arm: test-demo-tk

# Build and export the platform conformance artifact consumed by the compare job.
export-demo-conformance-linux:
    ZIG_GLOBAL_CACHE_DIR=.zig-global-cache zig build -Dfd-lib-dir={{ fd_tickoni_lib }}
    {{ python }} contrib/test/export_demo_conformance_bundle.py . build/demo-conformance/linux

export-demo-conformance-macos-15-x86_64:
    ZIG_GLOBAL_CACHE_DIR=.zig-global-cache zig build -Dfd-lib-dir={{ fd_tickoni_lib }}
    {{ python }} contrib/test/export_demo_conformance_bundle.py . build/demo-conformance/macos-15-x86_64

export-demo-conformance-macos-15-arm:
    ZIG_GLOBAL_CACHE_DIR=.zig-global-cache zig build -Dfd-lib-dir={{ fd_tickoni_lib }}
    {{ python }} contrib/test/export_demo_conformance_bundle.py . build/demo-conformance/macos-15-arm

export-demo-conformance-macos-26-x86_64:
    ZIG_GLOBAL_CACHE_DIR=.zig-global-cache zig build -Dfd-lib-dir={{ fd_tickoni_lib }}
    {{ python }} contrib/test/export_demo_conformance_bundle.py . build/demo-conformance/macos-26-x86_64

export-demo-conformance-macos-26-arm:
    ZIG_GLOBAL_CACHE_DIR=.zig-global-cache zig build -Dfd-lib-dir={{ fd_tickoni_lib }}
    {{ python }} contrib/test/export_demo_conformance_bundle.py . build/demo-conformance/macos-26-arm

export-demo-conformance-windows-x86:
    bash -lc "ZIG_GLOBAL_CACHE_DIR=.zig-global-cache zig build -Dfd-lib-dir={{ fd_tickoni_lib }} --summary all"
    {{ python }} contrib/test/export_demo_conformance_bundle.py . build/demo-conformance/windows-x86_64

export-demo-conformance-windows-arm:
    bash -lc "ZIG_GLOBAL_CACHE_DIR=.zig-global-cache zig build -Dfd-lib-dir={{ fd_tickoni_lib }} --summary all"
    {{ python }} contrib/test/export_demo_conformance_bundle.py . build/demo-conformance/windows-arm

compare-demo-conformance:
    {{ python }} contrib/test/compare_demo_conformance.py build/demo-conformance/linux/conformance.json build/demo-conformance/macos-15-x86_64/conformance.json build/demo-conformance/macos-15-arm/conformance.json build/demo-conformance/macos-26-x86_64/conformance.json build/demo-conformance/macos-26-arm/conformance.json build/demo-conformance/windows-x86_64/conformance.json build/demo-conformance/windows-arm/conformance.json

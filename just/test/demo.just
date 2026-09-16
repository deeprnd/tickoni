# Test: Demo conformance recipes

# Deterministic offline investment conformance suite — fixture-backed, no llama.cpp required.
test-demo-tk:
	bash {{ justfile_dir }}/contrib/test/run_cli_demo_tests.sh

test-demo-tk-linux-x86: test-demo-tk
test-demo-tk-linux-arm: test-demo-tk
test-demo-tk-macos-x86: test-demo-tk
test-demo-tk-macos-arm: test-demo-tk
test-demo-tk-windows-x86: test-demo-tk
test-demo-tk-windows-arm: test-demo-tk

# Firedancer demo lane: no demo tests yet.
test-demo-fd:
	@true

# Aggregate demo lane with badge update.
test-demo-all:
	{{ python }} {{ justfile_dir }}/contrib/tool/readme/run-badged-command.py demo bash -c "just test-demo-fd && just test-demo-tk"

# Build and export the platform conformance artifact consumed by the compare job.

export-demo-conformance-linux:
	(cd {{ justfile_dir }} && ZIG_LOCAL_CACHE_DIR={{ ZIG_CACHE }} ZIG_GLOBAL_CACHE_DIR={{ ZIG_GLOBAL_CACHE }} zig build -Dfd-lib-dir={{ fd_tickoni_lib }})
	{{ python }} {{ justfile_dir }}/contrib/test/export_demo_conformance_bundle.py . build/demo-conformance/linux

export-demo-conformance-macos-15-x86_64:
	(cd {{ justfile_dir }} && ZIG_LOCAL_CACHE_DIR={{ ZIG_CACHE }} ZIG_GLOBAL_CACHE_DIR={{ ZIG_GLOBAL_CACHE }} zig build -Dfd-lib-dir={{ fd_tickoni_lib }})
	{{ python }} {{ justfile_dir }}/contrib/test/export_demo_conformance_bundle.py . build/demo-conformance/macos-15-x86_64

export-demo-conformance-macos-15-arm:
	(cd {{ justfile_dir }} && ZIG_LOCAL_CACHE_DIR={{ ZIG_CACHE }} ZIG_GLOBAL_CACHE_DIR={{ ZIG_GLOBAL_CACHE }} zig build -Dfd-lib-dir={{ fd_tickoni_lib }})
	{{ python }} {{ justfile_dir }}/contrib/test/export_demo_conformance_bundle.py . build/demo-conformance/macos-15-arm

export-demo-conformance-macos-26-x86_64:
	(cd {{ justfile_dir }} && ZIG_LOCAL_CACHE_DIR={{ ZIG_CACHE }} ZIG_GLOBAL_CACHE_DIR={{ ZIG_GLOBAL_CACHE }} zig build -Dfd-lib-dir={{ fd_tickoni_lib }})
	{{ python }} {{ justfile_dir }}/contrib/test/export_demo_conformance_bundle.py . build/demo-conformance/macos-26-x86_64

export-demo-conformance-macos-26-arm:
	(cd {{ justfile_dir }} && ZIG_LOCAL_CACHE_DIR={{ ZIG_CACHE }} ZIG_GLOBAL_CACHE_DIR={{ ZIG_GLOBAL_CACHE }} zig build -Dfd-lib-dir={{ fd_tickoni_lib }})
	{{ python }} {{ justfile_dir }}/contrib/test/export_demo_conformance_bundle.py . build/demo-conformance/macos-26-arm

export-demo-conformance-windows-x86:
	bash -lc "(cd {{ justfile_dir }} && ZIG_LOCAL_CACHE_DIR={{ ZIG_CACHE }} ZIG_GLOBAL_CACHE_DIR={{ ZIG_GLOBAL_CACHE }} zig build -Dfd-lib-dir={{ fd_tickoni_lib }} --summary all)"
	{{ python }} {{ justfile_dir }}/contrib/test/export_demo_conformance_bundle.py . build/demo-conformance/windows-x86_64

export-demo-conformance-windows-arm:
	bash -lc "(cd {{ justfile_dir }} && ZIG_LOCAL_CACHE_DIR={{ ZIG_CACHE }} ZIG_GLOBAL_CACHE_DIR={{ ZIG_GLOBAL_CACHE }} zig build -Dfd-lib-dir={{ fd_tickoni_lib }} --summary all)"
	{{ python }} {{ justfile_dir }}/contrib/test/export_demo_conformance_bundle.py . build/demo-conformance/windows-arm

compare-demo-conformance:
	{{ python }} {{ justfile_dir }}/contrib/test/compare_demo_conformance.py build/demo-conformance/linux/conformance.json build/demo-conformance/macos-15-x86_64/conformance.json build/demo-conformance/macos-15-arm/conformance.json build/demo-conformance/macos-26-x86_64/conformance.json build/demo-conformance/macos-26-arm/conformance.json build/demo-conformance/windows-x86_64/conformance.json build/demo-conformance/windows-arm/conformance.json

# Test: Performance recipes

# Tickoni performance lane: Linux-only CPU placement performance proofs.
test-perf-tk-linux-x86:
    #!/usr/bin/env bash
    set -euo pipefail
    (cd {{ justfile_dir }} && ZIG_LOCAL_CACHE_DIR={{ ZIG_CACHE }} ZIG_GLOBAL_CACHE_DIR={{ ZIG_GLOBAL_CACHE }} zig build -p {{ ZIG_PREFIX }} -Dperf=true -Dfd-lib-dir={{ fd_tickoni_lib }} perf-test)

test-perf-tk-linux-arm:
    #!/usr/bin/env bash
    set -euo pipefail
    (cd {{ justfile_dir }} && ZIG_LOCAL_CACHE_DIR={{ ZIG_CACHE }} ZIG_GLOBAL_CACHE_DIR={{ ZIG_GLOBAL_CACHE }} zig build -p {{ ZIG_PREFIX }} -Dperf=true -Dfd-lib-dir={{ fd_tickoni_lib }} perf-test)

test-perf-tk-macos-x86:
    @echo "SKIPPED: test-perf-tk-macos-x86 — CPU placement perf tests are Linux-only"

test-perf-tk-macos-arm:
    @echo "SKIPPED: test-perf-tk-macos-arm — CPU placement perf tests are Linux-only"

test-perf-tk-windows-x86:
    @echo "SKIPPED: test-perf-tk-windows-x86 — CPU placement perf tests are Linux-only"

test-perf-tk-windows-arm:
    @echo "SKIPPED: test-perf-tk-windows-arm — CPU placement perf tests are Linux-only"

# Bare dispatcher; canonical platform recipes are in dispatch map.
test-perf-tk:
    {{ python }} {{ justfile_dir }}/contrib/tool/readme/run-badged-command.py perf bash -c "just test-perf-tk-linux-x86"

test-perf-fd:
    @true

test-perf-qt:
    @true

test-perf-all:
    {{ python }} {{ justfile_dir }}/contrib/tool/readme/run-badged-command.py perf bash -c "just test-perf-tk && just test-perf-fd && just test-perf-qt"

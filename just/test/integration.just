# Test: Integration recipes
test-integration-fd:
    @true

# Tickoni integration lane: transport and boundary wiring against local mocks.

# ── Infra lane (7 infra files + mock series) ─────────────────────────
test-integration-tk-infra-linux-x86:
    #!/usr/bin/env bash
    set -euo pipefail
    (cd {{ justfile_dir }} && ZIG_LOCAL_CACHE_DIR={{ ZIG_CACHE }} ZIG_GLOBAL_CACHE_DIR={{ ZIG_GLOBAL_CACHE }} zig build -p {{ ZIG_PREFIX }} {{ zig_linux_x86_cpu }} -Dtest=true -Dfd-lib-dir={{ fd_tickoni_lib }} integration-test-infra)

test-integration-tk-infra-linux-arm:
    #!/usr/bin/env bash
    set -euo pipefail
    (cd {{ justfile_dir }} && ZIG_LOCAL_CACHE_DIR={{ ZIG_CACHE }} ZIG_GLOBAL_CACHE_DIR={{ ZIG_GLOBAL_CACHE }} zig build -p {{ ZIG_PREFIX }} -Dtest=true -Dfd-lib-dir={{ fd_tickoni_lib }} integration-test-infra)

test-integration-tk-infra-macos-x86:
    #!/usr/bin/env bash
    set -euo pipefail
    (cd {{ justfile_dir }} && ZIG_LOCAL_CACHE_DIR={{ ZIG_CACHE }} ZIG_GLOBAL_CACHE_DIR={{ ZIG_GLOBAL_CACHE }} zig build -p {{ ZIG_PREFIX }} -Dtest=true -Dfd-lib-dir={{ fd_tickoni_lib }} integration-test-infra)

test-integration-tk-infra-macos-arm:
    #!/usr/bin/env bash
    set -euo pipefail
    (cd {{ justfile_dir }} && ZIG_LOCAL_CACHE_DIR={{ ZIG_CACHE }} ZIG_GLOBAL_CACHE_DIR={{ ZIG_GLOBAL_CACHE }} zig build -p {{ ZIG_PREFIX }} -Dtest=true -Dfd-lib-dir={{ fd_tickoni_lib }} integration-test-infra)

test-integration-tk-infra-windows-x86:
    # Uses SHELL=/usr/bin/bash to work around MSYS2 miniperl access violation (0xc0000005).
    set -euo pipefail
    (cd {{ justfile_dir }} && ZIG_LOCAL_CACHE_DIR={{ ZIG_CACHE }} ZIG_GLOBAL_CACHE_DIR={{ ZIG_GLOBAL_CACHE }} zig build -p {{ ZIG_PREFIX }} -Dtest=true -Dfd-lib-dir={{ fd_tickoni_lib }} integration-test-infra)

test-integration-tk-infra-windows-arm:
    # Uses SHELL=/usr/bin/bash to work around MSYS2 miniperl access violation (0xc0000005).
    set -euo pipefail
    (cd {{ justfile_dir }} && ZIG_LOCAL_CACHE_DIR={{ ZIG_CACHE }} ZIG_GLOBAL_CACHE_DIR={{ ZIG_GLOBAL_CACHE }} zig build -p {{ ZIG_PREFIX }} -Dtest=true -Dfd-lib-dir={{ fd_tickoni_lib }} integration-test-infra)

# ── Domain lane (7 domain files) ──────────────────────────────────────
test-integration-tk-domain-linux-x86:
    #!/usr/bin/env bash
    set -euo pipefail
    (cd {{ justfile_dir }} && ZIG_LOCAL_CACHE_DIR={{ ZIG_CACHE }} ZIG_GLOBAL_CACHE_DIR={{ ZIG_GLOBAL_CACHE }} zig build -p {{ ZIG_PREFIX }} {{ zig_linux_x86_cpu }} -Dtest=true -Dfd-lib-dir={{ fd_tickoni_lib }} integration-test-domain)

test-integration-tk-domain-linux-arm:
    #!/usr/bin/env bash
    set -euo pipefail
    (cd {{ justfile_dir }} && ZIG_LOCAL_CACHE_DIR={{ ZIG_CACHE }} ZIG_GLOBAL_CACHE_DIR={{ ZIG_GLOBAL_CACHE }} zig build -p {{ ZIG_PREFIX }} -Dtest=true -Dfd-lib-dir={{ fd_tickoni_lib }} integration-test-domain)

test-integration-tk-domain-macos-x86:
    #!/usr/bin/env bash
    set -euo pipefail
    (cd {{ justfile_dir }} && ZIG_LOCAL_CACHE_DIR={{ ZIG_CACHE }} ZIG_GLOBAL_CACHE_DIR={{ ZIG_GLOBAL_CACHE }} zig build -p {{ ZIG_PREFIX }} -Dtest=true -Dfd-lib-dir={{ fd_tickoni_lib }} integration-test-domain)

test-integration-tk-domain-macos-arm:
    #!/usr/bin/env bash
    set -euo pipefail
    (cd {{ justfile_dir }} && ZIG_LOCAL_CACHE_DIR={{ ZIG_CACHE }} ZIG_GLOBAL_CACHE_DIR={{ ZIG_GLOBAL_CACHE }} zig build -p {{ ZIG_PREFIX }} -Dtest=true -Dfd-lib-dir={{ fd_tickoni_lib }} integration-test-domain)

test-integration-tk-domain-windows-x86:
    # Uses SHELL=/usr/bin/bash to work around MSYS2 miniperl access violation (0xc0000005).
    set -euo pipefail
    (cd {{ justfile_dir }} && ZIG_LOCAL_CACHE_DIR={{ ZIG_CACHE }} ZIG_GLOBAL_CACHE_DIR={{ ZIG_GLOBAL_CACHE }} zig build -p {{ ZIG_PREFIX }} -Dtest=true -Dfd-lib-dir={{ fd_tickoni_lib }} integration-test-domain)

test-integration-tk-domain-windows-arm:
    # Uses SHELL=/usr/bin/bash to work around MSYS2 miniperl access violation (0xc0000005).
    set -euo pipefail
    (cd {{ justfile_dir }} && ZIG_LOCAL_CACHE_DIR={{ ZIG_CACHE }} ZIG_GLOBAL_CACHE_DIR={{ ZIG_GLOBAL_CACHE }} zig build -p {{ ZIG_PREFIX }} -Dtest=true -Dfd-lib-dir={{ fd_tickoni_lib }} integration-test-domain)

# ── Combined lane (infra + domain) ────────────────────────────────────
test-integration-tk-linux-x86:
    #!/usr/bin/env bash
    set -euo pipefail
    (cd {{ justfile_dir }} && ZIG_LOCAL_CACHE_DIR={{ ZIG_CACHE }} ZIG_GLOBAL_CACHE_DIR={{ ZIG_GLOBAL_CACHE }} zig build -p {{ ZIG_PREFIX }} {{ zig_linux_x86_cpu }} -Dtest=true -Dfd-lib-dir={{ fd_tickoni_lib }} integration-test)

test-integration-tk-linux-arm:
    #!/usr/bin/env bash
    set -euo pipefail
    (cd {{ justfile_dir }} && ZIG_LOCAL_CACHE_DIR={{ ZIG_CACHE }} ZIG_GLOBAL_CACHE_DIR={{ ZIG_GLOBAL_CACHE }} zig build -p {{ ZIG_PREFIX }} -Dtest=true -Dfd-lib-dir={{ fd_tickoni_lib }} integration-test)

test-integration-tk-macos-x86:
    #!/usr/bin/env bash
    set -euo pipefail
    (cd {{ justfile_dir }} && ZIG_LOCAL_CACHE_DIR={{ ZIG_CACHE }} ZIG_GLOBAL_CACHE_DIR={{ ZIG_GLOBAL_CACHE }} zig build -p {{ ZIG_PREFIX }} -Dtest=true -Dfd-lib-dir={{ fd_tickoni_lib }} integration-test)

test-integration-tk-macos-arm:
    #!/usr/bin/env bash
    set -euo pipefail
    (cd {{ justfile_dir }} && ZIG_LOCAL_CACHE_DIR={{ ZIG_CACHE }} ZIG_GLOBAL_CACHE_DIR={{ ZIG_GLOBAL_CACHE }} zig build -p {{ ZIG_PREFIX }} -Dtest=true -Dfd-lib-dir={{ fd_tickoni_lib }} integration-test)

test-integration-tk-windows-x86:
    # Uses SHELL=/usr/bin/bash to work around MSYS2 miniperl access violation (0xc0000005).
    set -euo pipefail
    (cd {{ justfile_dir }} && ZIG_LOCAL_CACHE_DIR={{ ZIG_CACHE }} ZIG_GLOBAL_CACHE_DIR={{ ZIG_GLOBAL_CACHE }} zig build -p {{ ZIG_PREFIX }} -Dtest=true -Dfd-lib-dir={{ fd_tickoni_lib }} integration-test)

test-integration-tk-windows-arm:
    # Uses SHELL=/usr/bin/bash to work around MSYS2 miniperl access violation (0xc0000005).
    set -euo pipefail
    (cd {{ justfile_dir }} && ZIG_LOCAL_CACHE_DIR={{ ZIG_CACHE }} ZIG_GLOBAL_CACHE_DIR={{ ZIG_GLOBAL_CACHE }} zig build -p {{ ZIG_PREFIX }} -Dtest=true -Dfd-lib-dir={{ fd_tickoni_lib }} integration-test)

# Bare dispatcher; canonical platform recipes are in dispatch map.
test-integration-tk:
	{{ python }} {{ justfile_dir }}/scripts/dispatch test-integration-tk

test-integration-tk-infra:
	{{ python }} {{ justfile_dir }}/scripts/dispatch test-integration-tk-infra

test-integration-tk-domain:
	{{ python }} {{ justfile_dir }}/scripts/dispatch test-integration-tk-domain

test-integration-all:
	{{ python }} {{ justfile_dir }}/contrib/tool/readme/run-badged-command.py integration bash -c "just test-integration-fd && just test-integration-tk"

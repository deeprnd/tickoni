# ── Memory (hugepages) ─────────────────────────────────────────────────────

# Initialize hugepage shared memory config with permissions and owner.
system-mem-init mode="0700" user="":
    #!/usr/bin/env bash
    set -euo pipefail
    owner="{{ user }}"
    if [ -z "$owner" ]; then owner="$USER"; fi
    sudo src/util/shmem/fd_shmem_cfg init {{ mode }} "$owner" ""

system-mem-query:
    sudo src/util/shmem/fd_shmem_cfg query

system-mem-reset:
    sudo src/util/shmem/fd_shmem_cfg reset

system-mem-fini:
    sudo src/util/shmem/fd_shmem_cfg fini

# Allocate specified number of hugepages on the given NUMA node.
system-mem-alloc pages="24" page_type="gigantic" numa="0":
    sudo src/util/shmem/fd_shmem_cfg alloc {{ pages }} {{ page_type }} {{ numa }}

# Auto-calculate hugepage allocation based on available memory (reserve 4 GB for system).
system-mem-alloc-auto numa="0":
    pages="$(( ((( $(awk '/MemTotal:/ {print $2}' /proc/meminfo) * 1024 )) - (4 * 1024 * 1024 * 1024)) / (6 * 1024 * 1024 * 1024) * 6 ))"; \
    if [ "$pages" -lt 0 ]; then pages=0; fi; \
    echo "allocating $pages gigantic pages on NUMA {{ numa }}"; \
    sudo src/util/shmem/fd_shmem_cfg alloc "$pages" gigantic {{ numa }}

# Release hugepages on the given NUMA node.
system-mem-free page_type="gigantic" numa="0":
    sudo src/util/shmem/fd_shmem_cfg free {{ page_type }} {{ numa }}
    just system-mem-drop-caches

system-mem-drop-caches:
    # Free page cache, dentries, and inodes so tests can mlock memory.
    # sync alone does not free memory — drop_caches is required.
    sudo sh -c 'echo 3 > /proc/sys/vm/drop_caches' || echo "system-mem-drop-caches: could not free caches (may be read-only or non-root)"

# ── Kill test processes ────────────────────────────────────────────────────────

system-kill-test:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "killing test processes (user: $USER)..."
    case "{{ os }}" in
      linux)
        # Phase 1: kill child tile processes first (tkings, tknorm, tkdedu, etc.)
        pkill -u "$USER" -f 'zig-out/bin/tk[a-z]\+ ' 2>/dev/null || true
        pkill -u "$USER" -f 'target/debug/tk[a-z]\+ ' 2>/dev/null || true
        pkill -u "$USER" -f 'target/release/tk[a-z]\+ ' 2>/dev/null || true
        # Phase 1b: kill test-* binaries
        pkill -u "$USER" -f 'zig-out/bin/test-' 2>/dev/null || true
        pkill -u "$USER" -f 'target/debug/test-' 2>/dev/null || true
        pkill -u "$USER" -f 'target/release/test-' 2>/dev/null || true
        # Phase 2: kill tickoni-supervisor (parent of tile processes)
        pkill -u "$USER" -f 'tickoni-supervisor' 2>/dev/null || true
        # Phase 3: kill any remaining orphans still children of a supervisor
        for pid in $(pgrep -u "$USER" -f 'tickoni-supervisor' 2>/dev/null || true); do
          pkill -u "$USER" -P "$pid" 2>/dev/null || true
        done
        echo "done."
        ;;
      macos)
        pkill -u "$USER" -f 'tickoni-supervisor' 2>/dev/null || true
        pkill -u "$USER" -f 'zig-out/bin/tk[a-z]\+ ' 2>/dev/null || true
        pkill -u "$USER" -f 'target/debug/tk[a-z]\+ ' 2>/dev/null || true
        pkill -u "$USER" -f 'target/release/tk[a-z]\+ ' 2>/dev/null || true
        pkill -u "$USER" -f 'zig-out/bin/test-' 2>/dev/null || true
        echo "done."
        ;;
      windows)
        # Windows: use taskkill with image-name filters for tk* and test-*
        for img in tkings tknorm tkdedu tkcase tkpoly tkaudt tkrepl tkmetr tkdiag tkdisp tkagnt tkmodl tktool tkadpt tkapi tickoni-supervisor; do
          taskkill /F /FI "IMAGENAME eq ${img}.exe" /T > /dev/null 2>&1 || true
        done
        # Kill any zig-out/test-* processes by matching the path
        taskkill /F /FI "CMDLINE eq *zig-out/bin/test-*" /T > /dev/null 2>&1 || true
        taskkill /F /FI "CMDLINE eq *target/debug/test-*" /T > /dev/null 2>&1 || true
        # Kill any remaining tickoni-* processes
        for img in $(wmic process where "name like '%tickoni%'" get name /value 2>/dev/null | grep -oP '[a-z-]+\.exe' | sort -u || true); do
          taskkill /F /FI "IMAGENAME eq $img" /T > /dev/null 2>&1 || true
        done
        echo "done."
        ;;
      *)
        echo "unsupported OS for system-kill-test: {{ os }}" >&2
        exit 1
        ;;
    esac

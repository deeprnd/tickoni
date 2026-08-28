#!/usr/bin/env bash
# Coverage report generator.
# Usage: coverage.sh <job-name>
set -euo pipefail
JOB="${1:?Usage: coverage.sh <job-name>}"

_start=$(date +%s)
log() { echo "[$(date +%H:%M:%S)] [$(( $(date +%s) - _start ))s] $*"; }

if [ "$JOB" = "coverage-fd" ]; then
    COVDIR=build/fd-cov
    RAWDIR="${COVDIR}/cov/raw"

    # Always start fresh — delete coverage artifacts to prevent stale state.
    rm -f "${COVDIR}/cov.profdata"

    # Build cov.profdata from .profraw files (llvm-cov step 1.3).
    mkdir -p "${COVDIR}"
    _t0=$(date +%s)
    llvm-profdata merge -o "${COVDIR}/cov.profdata" "${RAWDIR}"/*.profraw
    log "[profdata] merge done in $(( $(date +%s) - _t0 ))s"

    # Run coverage report using test binaries. llvm-cov export takes ~0.1s
    # with binary IDs vs ~900s with individual .o files.
    _t0=$(date +%s)
    set +e
    timeout 900 python3 contrib/readme/coverage_report.py coverage-fd \
        "${COVDIR}" \
        build/coverage/fd/coverage-summary.json \
        --config contrib/test/coverage-fd.json
    cov_rc=$?
    set -e
    _t1=$(( $(date +%s) - _t0 ))
    log "[coverage-report] exit=$cov_rc in ${_t1}s"
    if [ "$cov_rc" -eq 137 ]; then
        echo "ERROR: llvm-cov export timed out after 900s" >&2
        exit 1
    fi
    exit "$cov_rc"
elif [ "$JOB" = "coverage-tk" ]; then
    command -v kcov >/dev/null 2>&1 || {
        echo "ERROR: kcov not found. Install it with: sudo apt-get install kcov" >&2
        exit 1
    }

    COV_BINS="zig-out/cov"
    COV_RAW="build/coverage/tk/kcov"
    SUMMARY="build/coverage/tk/coverage-summary.json"
    CONFIG="contrib/test/coverage-tk.json"
    COV_CACHE="build/coverage/tk/zig-cache"
    COV_GLOBAL_CACHE="build/coverage/tk/zig-global-cache"

    # ReleaseSafe triggers DWARFv4 output (via LLVM backend), which kcov handles
    # correctly across multiple CUs. Debug mode emits DWARFv5 with per-CU
    # rnglists_base; kcov v44 only honours the first CU's base, silently dropping
    # all subsequent user-code CUs from the coverage report.
    # Coverage builds must not reuse the repository Zig caches. An interrupted
    # build can leave cache metadata referring to object files that no longer
    # exist, causing Zig 0.17 to report missing *_zcu.o files at link time.
    rm -rf "$COV_CACHE" "$COV_GLOBAL_CACHE" "$COV_BINS" "$COV_RAW"
    ZIG_GLOBAL_CACHE_DIR="$COV_GLOBAL_CACHE" zig build \
        --cache-dir "$COV_CACHE" \
        -Dtest=true cov -Doptimize=ReleaseSafe -Dfd-lib-dir=build/fd-tickoni-fd/lib

    mkdir -p "$COV_RAW"

    # Run tests via kcov
    for bin in "${COV_BINS}"/*; do
        [ -f "$bin" ] || continue
        name="$(basename "$bin")"
        kcov --include-pattern=src/tickoni \
            "${COV_RAW}"/"$name" \
            "$bin"
    done

    # Merge kcov outputs — find directories created by each binary run
    MERGED="${COV_RAW}/merged"
    kcov_dirs=()
    for d in "${COV_RAW}"/*/; do
        [ -d "$d" ] || continue
        base="$(basename "$d")"
        [ "$base" = "merged" ] && continue
        kcov_dirs+=("$d")
    done
    if [ "${#kcov_dirs[@]}" -ge 2 ]; then
        kcov --merge "$MERGED" "${kcov_dirs[@]}"
    elif [ "${#kcov_dirs[@]}" -eq 1 ]; then
        mkdir -p "$MERGED"
        ln -sfn "$(realpath "${kcov_dirs[0]}")" "$MERGED"
    else
        echo 'ERROR: no kcov output directories found' >&2
        exit 1
    fi

    python3 contrib/readme/coverage_report.py coverage-tk \
        "${COV_RAW}/merged" \
        "$SUMMARY" \
        --config "$CONFIG"
else
    echo "Unknown job: $JOB"
    exit 1
fi

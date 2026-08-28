#!/usr/bin/env bash
set -uo pipefail

build_cmd=(bash contrib/zigw.sh build -Dfd-lib-dir=build/fd-tickoni-fd/lib)
log_path="${RUNNER_TEMP:-/tmp}/build-tk.log"
rm -f "$log_path"

if just build-tk 2>&1 | tee "$log_path"; then
  exit 0
fi

status=$?
echo "::warning::just build-tk failed; rerunning raw Zig build via contrib/zigw.sh with --summary all --verbose-link for diagnostics"
echo "::group::build-tk verbose diagnostics"
ZIG_GLOBAL_CACHE_DIR=.zig-global-cache "${build_cmd[@]}" --summary all --verbose-link 2>&1 | tee -a "$log_path" || true
echo "::endgroup::"
echo "diagnostic log: $log_path"
exit "$status"

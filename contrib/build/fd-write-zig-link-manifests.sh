#!/usr/bin/env bash
# Emit the FD-side Windows Zig link-contract manifests consumed by build.zig.
# Usage: contrib/fd-write-zig-link-manifests.sh <BUILDDIR>
set -euo pipefail
cd "$(dirname "$0")/.."

BUILDDIR="${1:?usage: fd-write-zig-link-manifests.sh <BUILDDIR>}"
LIBDIR="build/${BUILDDIR}/lib"
mkdir -p "$LIBDIR"

supervisor_manifest="${LIBDIR}/fd_windows_zig_supervisor_link.txt"
codec_manifest="${LIBDIR}/fd_windows_zig_codec_link.txt"

write_manifest() {
  local path="$1"
  shift
  printf '%s\n' "$@" > "$path"
}

log_obj="build/${BUILDDIR}/obj/util/log/fd_log.o"
if [ -f "build/${BUILDDIR}/obj/util/log/fd_log_windows.o" ]; then
  log_obj="build/${BUILDDIR}/obj/util/log/fd_log_windows.o"
fi

write_manifest "$supervisor_manifest" \
  "build/${BUILDDIR}/obj/tango/mcache/fd_mcache.o" \
  "build/${BUILDDIR}/obj/tango/dcache/fd_dcache.o" \
  "build/${BUILDDIR}/obj/tango/fseq/fd_fseq.o" \
  "build/${BUILDDIR}/obj/tango/fctl/fd_fctl.o" \
  "build/${BUILDDIR}/obj/tango/tempo/fd_tempo.o" \
  "build/${BUILDDIR}/obj/tango/cnc/fd_cnc.o" \
  "build/${BUILDDIR}/obj/util/wksp/fd_wksp_helper.o" \
  "build/${BUILDDIR}/obj/util/wksp/fd_wksp_user.o" \
  "build/${BUILDDIR}/obj/util/shmem/fd_shmem_windows_stub.o" \
  "build/${BUILDDIR}/obj/disco/topo/fd_topob.o" \
  "build/${BUILDDIR}/obj/disco/topo/fd_topo.o" \
  "$log_obj" \
  "build/${BUILDDIR}/obj/util/pod/fd_pod.o" \
  "build/${BUILDDIR}/obj/util/fd_util.o" \
  "build/${BUILDDIR}/obj/ballet/siphash13/fd_siphash13.o" \
  "build/${BUILDDIR}/obj/ballet/pb/fd_pb_tokenize.o" \
  "build/${BUILDDIR}/obj/third_party/cjson/cJSON.o" \
  "build/${BUILDDIR}/obj/disco/events/fd_event_report.o" \
  "build/${BUILDDIR}/obj/disco/metrics/fd_metrics.o" \
  "build/${BUILDDIR}/obj/util/cstr/fd_cstr.o" \
  "build/${BUILDDIR}/obj/util/tile/fd_tile_threads.o"

write_manifest "$codec_manifest" \
  "build/${BUILDDIR}/obj/ballet/siphash13/fd_siphash13.o" \
  "build/${BUILDDIR}/obj/ballet/pb/fd_pb_tokenize.o" \
  "build/${BUILDDIR}/obj/third_party/cjson/cJSON.o" \
  "$log_obj" \
  "build/${BUILDDIR}/obj/util/env/fd_env.o" \
  "build/${BUILDDIR}/obj/util/cstr/fd_cstr.o" \
  "build/${BUILDDIR}/obj/util/alloc/fd_alloc.o" \
  "build/${BUILDDIR}/obj/util/wksp/fd_wksp_admin.o"

printf '[+] wrote %s\n' "$supervisor_manifest"
printf '[+] wrote %s\n' "$codec_manifest"

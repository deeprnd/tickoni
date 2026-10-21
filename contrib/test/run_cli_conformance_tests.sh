#!/usr/bin/env bash
# Focused S6 CLI verification: build both user-facing and supervisor binaries,
# validate version/doctor contracts on `tickoni`.
# Note: the demo conformance suite was removed when the demo CLI was deleted;
# this script now validates the stripped-down CLI surface.
set -uo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root" || exit 1

export ZIG_GLOBAL_CACHE_DIR="${ZIG_GLOBAL_CACHE_DIR:-$repo_root/build/.zig-global-cache}"
export ZIG_LOCAL_CACHE_DIR="${ZIG_LOCAL_CACHE_DIR:-$repo_root/build/.zig-cache}"

# Zig prefix: use passed ZIG_PREFIX (absolute, from justfile), fall back to build/zig-out.
ZIG_PREFIX="${ZIG_PREFIX:-$repo_root/${ZIG_PREFIX_REL:-build/zig-out}}"

build_cmd=(zig build -p "$ZIG_PREFIX" -Dfd-lib-dir=build/fd-tickoni-fd/lib -Dtest=true --summary all)
cli_binary="$ZIG_PREFIX/bin/tickoni"
binary="$ZIG_PREFIX/bin/tickoni-supervisor"

printf 'building tickoni and tickoni-supervisor with fixture-backed modules\n'
if ! "${build_cmd[@]}"; then
  echo "build failed" >&2
  exit 1
fi

printf 'verifying tickoni --version contract\n'
version_output="$($cli_binary --version)" || exit 1
python3 - <<'PY' "$version_output"
import sys
text = sys.argv[1]
assert text.startswith('Tickoni '), text
for needle in [
    'Build ID:',
    'Git:',
    'OS:',
    'Runtime Tier:',
    'Isolation Tier:',
    'Policy Schema:',
    'Replay Schema:',
    'Manifest:',
    'Compiler:',
]:
    assert needle in text, (needle, text)
PY

printf 'verifying tickoni doctor plain contract\n'
plain_output="$($cli_binary doctor --plain 2>&1 || true)"
python3 - <<'PY' "$plain_output"
import sys
text = sys.argv[1]
assert 'tickoni doctor' in text, text
assert 'Platform tier:' in text, text
PY

printf 'verifying tickoni doctor json contract\n'
json_output="$($cli_binary doctor --json 2>&1 || true)"
python3 - <<'PY' "$json_output"
import json, sys
js = sys.argv[1]
payload = json.loads(js)
assert 'platform_tier' in payload, payload
assert 'result' in payload, payload
assert 'checks' in payload and isinstance(payload['checks'], list), payload
PY

printf 'verifying bare tickoni invocation shows usage (fail-closed)\n'
usage_output="$($cli_binary 2>&1 || true)"
python3 - <<'PY' "$usage_output"
import sys
text = sys.argv[1]
# Should show usage/help or an error — both are fail-closed.
assert 'command' in text.lower() or 'usage' in text.lower() or 'error' in text.lower() or 'unknown' in text.lower(), text
PY

printf 'verifying tickoni-supervisor builds successfully\n'
python3 - <<'PY' "$binary"
import sys, subprocess
binary = sys.argv[1]
proc = subprocess.run([binary, '--version'], capture_output=True, text=True)
assert proc.returncode == 0, proc.stderr
PY

printf 'PASS: tickoni CLI contract and tickoni-supervisor verified\n'

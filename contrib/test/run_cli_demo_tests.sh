#!/usr/bin/env bash
# Focused S6/S7 CLI verification: build both user-facing and supervisor binaries,
# validate version/doctor contracts on `tickoni`, then assert the fixture-backed
# conformance suite JSON contract on `tickoni-supervisor`.
set -uo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root" || exit 1

build_cmd=(zig build -Dfd-lib-dir=build/fd-tickoni-fd/lib --summary all)
manifest="src/tickoni/demo/fixtures/demo.manifest.json"
cli_binary="zig-out/bin/tickoni"
binary="zig-out/bin/tickoni-supervisor"

export ZIG_GLOBAL_CACHE_DIR=.zig-global-cache

printf 'building tickoni and tickoni-supervisor with fixture-backed demo modules\n'
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
    'Demo Manifest:',
    'Compiler:',
]:
    assert needle in text, (needle, text)
PY

printf 'verifying tickoni doctor plain/json contracts\n'
plain_output="$($cli_binary doctor --plain 2>&1 || true)"
json_output="$($cli_binary doctor --json 2>&1 || true)"
python3 - <<'PY' "$plain_output" "$json_output"
import json, sys
plain = sys.argv[1]
js = sys.argv[2]
assert 'tickoni doctor — host report' in plain, plain
assert 'Platform tier:' in plain, plain
payload = json.loads(js)
assert 'platform_tier' in payload, payload
assert 'result' in payload, payload
assert 'checks' in payload and isinstance(payload['checks'], list), payload
PY

printf 'verifying bare demo usage fails closed\n'
usage_output="$($binary demo 2>&1)"
usage_status=$?
if [[ $usage_status -eq 0 ]]; then
  echo "expected bare demo invocation to fail" >&2
  exit 1
fi
python3 - <<'PY' "$usage_output"
import sys
text = sys.argv[1]
assert 'demo usage error' in text or 'Usage:' in text, text
PY

printf 'running JSON conformance suite\n'
json_output="$($binary demo investment --json --manifest "$manifest")" || exit 1
python3 - <<'PY' "$json_output"
import json, sys, pathlib

payload = json.loads(sys.argv[1])
assert payload['preflight'] == 'passed', payload
suite = payload['suite']
assert len(suite) == 4, suite

# Platform-aware: get the actual runtime tier from the manifest
manifest_path = pathlib.Path("src/tickoni/demo/fixtures/demo.manifest.json")
m = json.loads(manifest_path.read_text())
assert len(m['supported_runtime_tiers']) > 0, m

comparison = payload['comparison']
assert comparison['all_match'] is True, comparison
assert len(comparison['scenarios']) == 4, comparison
scenarios = {item['scenario']: item for item in suite}
assert set(scenarios) == {'allowed', 'oversized_blocked', 'restricted_instrument', 'tampered_replay'}, scenarios
assert scenarios['allowed']['policy_outcome'] == 'allow', scenarios['allowed']
assert scenarios['allowed']['external_effects_disabled'] is True, scenarios['allowed']
assert scenarios['oversized_blocked']['policy_outcome'] == 'deny', scenarios['oversized_blocked']
assert scenarios['oversized_blocked']['blocked_diagnostic']['code'] == 'policy_denied', scenarios['oversized_blocked']
assert scenarios['restricted_instrument']['blocked_diagnostic']['code'] == 'restricted_instrument', scenarios['restricted_instrument']
assert scenarios['tampered_replay']['blocked_diagnostic']['code'] == 'tampered_replay_artifact', scenarios['tampered_replay']
assert scenarios['tampered_replay']['replay_result']['replay_match'] is False, scenarios['tampered_replay']
for item in suite:
    assert item['runtime_tier'], item
    assert item['isolation_tier'], item
    assert item['normalized_event_hash'], item
    assert item['proposal_hash'] is not None, item
PY

printf 'running plain-text conformance suite\n'
plain_output="$($binary demo investment --plain --manifest "$manifest")" || exit 1
python3 - <<'PY' "$plain_output"
import sys
text = sys.argv[1]
assert 'comparison_all_match: true' in text, text
assert 'comparison_scenario: allowed match=true mismatch_count=0' in text, text
assert text.count('manifest_id: demo.investment.v1') == 4, text
assert 'scenario: tampered_replay' in text, text
assert 'blocked_code: tampered_replay_artifact' in text, text
PY

printf 'verifying fail-closed preflight diagnostics\n'
python3 - <<'PY' "$binary" "$manifest"
import json, os, pathlib, subprocess, sys, tempfile
binary = sys.argv[1]
manifest_path = pathlib.Path(sys.argv[2])
base = json.loads(manifest_path.read_text())
case_map = {
    'unsupported_runtime_tier': ('blocked_code: unsupported_runtime_tier', dict(base, supported_runtime_tiers=['macos_retail'])),
    'missing_fixture': ('blocked_code: missing_fixture', dict(base, required_fixtures=['does_not_exist'])),
    'stale_manifest': ('blocked_code: stale_manifest', dict(base, min_tickoni_version='999.0.0')),
    'missing_isolation_prerequisite': ('blocked_code: missing_isolation_prerequisite', dict(base, required_isolation_by_tier={'linux_full': 'retail', 'macos_retail': 'retail'})),
    'attempted_live_execution': ('blocked_code: attempted_live_execution', dict(base, expected_no_live_effect=False)),
}
for name, (needle, payload) in case_map.items():
    fd, temp_path = tempfile.mkstemp(prefix='hermes-cli-demo-', suffix='.json')
    os.close(fd)
    path = pathlib.Path(temp_path)
    path.write_text(json.dumps(payload))
    proc = subprocess.run([binary, 'demo', 'investment', '--manifest', str(path)], text=True, capture_output=True)
    assert proc.returncode == 1, (name, proc.returncode, proc.stdout, proc.stderr)
    assert 'Preflight failure:' in proc.stderr, (name, proc.stderr)
    assert needle in proc.stderr, (name, proc.stderr)
    path.unlink()
PY

printf 'PASS: tickoni CLI contract and tickoni-supervisor demo contract verified\n'

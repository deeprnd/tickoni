# ── Test: CLI conformance recipes ──────────────────────────────────────────

# Deterministic offline investment conformance suite — fixture-backed, no llama.cpp required.

# Bare dispatcher; canonical platform/compiler recipes below are the implementation.
test-cli-tk:
    #!/usr/bin/env bash
    set -euo pipefail
    case "{{ os }}-{{ arch }}" in
    linux-x86) exec just test-cli-tk-linux-x86 ;;
    linux-arm) exec just test-cli-tk-linux-arm ;;
    macos-x86) exec just test-cli-tk-macos-x86 ;;
    macos-arm) exec just test-cli-tk-macos-arm ;;
    windows-x86) exec just test-cli-tk-windows-x86 ;;
    windows-arm) exec just test-cli-tk-windows-arm ;;
    *) echo "unsupported host platform for test-cli-tk: {{ os }}-{{ arch }}" >&2; exit 1 ;;
    esac

test-cli-all: test-cli-tk

test-cli-tk-linux-x86:
    bash contrib/test/run_cli_conformance_tests.sh

test-cli-tk-linux-arm: test-cli-tk-linux-x86

test-cli-tk-macos-x86: test-cli-tk-linux-x86

test-cli-tk-macos-arm: test-cli-tk-macos-x86

test-cli-tk-windows-x86: test-cli-tk-linux-x86

test-cli-tk-windows-arm: test-cli-tk-windows-x86

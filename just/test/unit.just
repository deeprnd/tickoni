# Test: Unit recipes

# Print computed hash and wire bytes for every audit fixture event, and emit audit JSONL.
# Use the output to understand or snapshot the current encoding after intentional changes.
gen-audit-fixtures:
    TK_GEN_FIXTURES=1 ZIG_GLOBAL_CACHE_DIR=.zig-global-cache zig build -Dtest=true test 2>&1
    TK_GEN_FIXTURES=1 ZIG_GLOBAL_CACHE_DIR=.zig-global-cache zig build -Dtest=true integration-test 2>&1

# Run Python unit tests for contrib/test/* (pytest, no FD build required).
test-unit-setup:
    {{ python }} -m pip install -q --upgrade pip
    {{ python }} -m pip install -q --upgrade pytest
    cd contrib/test && {{ python }} -m pytest test_dynamic_test_opts.py test_llama_server.py test_build_orchestrator.py test_setup_asset_resolution.py test_setup_checks.py test_setup_install_method.py test_setup_msvc.py test_setup_shell.py test_windows_uuid_link.py --tb=short -v

test-unit-all:
    {{ python }} contrib/tool/readme/run-badged-command.py unit bash -c "just test-unit-setup && just test-unit-tk && just test-unit-fd"

# Bare dispatcher; canonical platform recipes are in dispatch map.
test-unit-tk:
    python3 scripts/dispatch test-unit-tk

# Bare dispatcher; canonical platform recipes are in dispatch map.
test-unit-fd:
    python3 scripts/dispatch test-unit-fd

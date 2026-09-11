# Test: Unit recipes

# Print computed hash and wire bytes for every audit fixture event, and emit audit JSONL.
# Use the output to understand or snapshot the current encoding after intentional changes.
gen-audit-fixtures:
    TK_GEN_FIXTURES=1 ZIG_GLOBAL_CACHE_DIR=.zig-global-cache zig build -Dtest=true test 2>&1
    TK_GEN_FIXTURES=1 ZIG_GLOBAL_CACHE_DIR=.zig-global-cache zig build -Dtest=true integration-test 2>&1

# Run Python unit tests for contrib/test/* (pytest, no FD build required).
test-unit-setup:
    {{ python }} ../contrib/setup/orchestrator.py test-tools
    {{ python }} -m pytest contrib/test/

test-unit-all:
    {{ python }} contrib/tool/readme/run-badged-command.py unit bash -c "just test-unit-setup && just test-unit-tk && just test-unit-fd"

# Note: test-unit-tk and test-unit-fd dispatchers are defined in justfile.

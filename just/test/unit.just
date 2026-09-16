# Test: Unit recipes

# Print computed hash and wire bytes for every audit fixture event, and emit audit JSONL.
# Use the output to understand or snapshot the current encoding after intentional changes.
gen-audit-fixtures:
    ZIG_LOCAL_CACHE_DIR={{ ZIG_CACHE }} TK_GEN_FIXTURES=1 ZIG_GLOBAL_CACHE_DIR={{ ZIG_GLOBAL_CACHE }} zig build -Dtest=true test 2>&1
    ZIG_LOCAL_CACHE_DIR={{ ZIG_CACHE }} TK_GEN_FIXTURES=1 ZIG_GLOBAL_CACHE_DIR={{ ZIG_GLOBAL_CACHE }} zig build -Dtest=true integration-test 2>&1

# Run Python unit tests for contrib/test/* (pytest, no FD build required).
test-unit-setup:
    {{ python }} -m pytest {{ justfile_dir }}/contrib/test/

test-unit-all:
    {{ python }} {{ justfile_dir }}/contrib/tool/readme/run-badged-command.py unit bash -c "just test-unit-setup && just test-unit-tk && just test-unit-fd"

# Note: test-unit-tk and test-unit-fd dispatchers are defined in justfile.

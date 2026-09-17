# Test: Unit recipes

# Print computed hash and wire bytes for every audit fixture event, and emit audit JSONL.
# Use the output to understand or snapshot the current encoding after intentional changes.
gen-audit-fixtures:
    (cd {{ justfile_dir }} && ZIG_LOCAL_CACHE_DIR={{ ZIG_CACHE }} TK_GEN_FIXTURES=1 ZIG_GLOBAL_CACHE_DIR={{ ZIG_GLOBAL_CACHE }} zig build -Dtest=true test 2>&1)
    (cd {{ justfile_dir }} && ZIG_LOCAL_CACHE_DIR={{ ZIG_CACHE }} TK_GEN_FIXTURES=1 ZIG_GLOBAL_CACHE_DIR={{ ZIG_GLOBAL_CACHE }} zig build -Dtest=true integration-test 2>&1)

# Run Python unit tests for contrib/test/* (pytest, no FD build required).
test-unit-setup:
    {{ python }} {{ justfile_dir }}/contrib/setup/orchestrator.py test-tools
    cd {{ justfile_dir }} && {{ python }} -m pytest --basetemp=build/pytest -o cache_dir=build/pytest-cache contrib/test/

test-unit-all:
    {{ python }} {{ justfile_dir }}/contrib/tool/readme/run-badged-command.py unit bash -c "just test-unit-setup && just test-unit-tk && just test-unit-fd"

# Note: test-unit-tk and test-unit-fd dispatchers are defined in justfile.

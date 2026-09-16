# Test: E2E recipes

# Firedancer e2e lane: integration-test + local topology.
test-e2e-fd:
    @true

# Tickoni e2e lane — currently folded into test-demo-tk and test-e2e-fd.
test-e2e-tk:
    @true

# Aggregate e2e lane with badge update.
test-e2e-all:
    {{ python }} {{ justfile_dir }}/contrib/tool/readme/run-badged-command.py e2e bash -c "just test-e2e-fd && just test-e2e-tk"

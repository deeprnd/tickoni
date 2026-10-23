# ── Test: E2E recipes ───────────────────────────────────────────────────
# E2E lanes (currently no-op placeholders).

test-e2e-fd:
    @true

# Tickoni E2E lane: dispatcher → platform-specific recipes.
test-e2e-tk:
    @true

test-e2e-all:
    {{ python }} contrib/tool/readme/run-badged-command.py e2e bash -c "just test-e2e-fd && just test-e2e-tk"

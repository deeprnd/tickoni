# ── Setup: Git ─────────────────────────────────────────────────────────────
# Activate tracked git hooks (commit-msg strips anthropic AI co-authors)

setup-git:
    git config core.hooksPath .githooks
    chmod +x .githooks/commit-msg

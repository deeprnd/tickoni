# ── Setup: Quality recipes ─────────────────────────────────────────────────
# Quality tool installation (shellcheck, actionlint, yamllint, pre-commit, buf + go).

# Quality: build + quality tools
setup-quality-linux-x86:
    {{ python }} contrib/setup/orchestrator.py core,essential,toolchain,build
    {{ python }} contrib/setup/orchestrator.py quality

setup-quality-macos-x86:
    {{ python }} contrib/setup/orchestrator.py core,essential,toolchain,build
    {{ python }} contrib/setup/orchestrator.py quality

setup-quality-macos-arm:
    {{ python }} contrib/setup/orchestrator.py core,essential,toolchain,build
    {{ python }} contrib/setup/orchestrator.py quality

setup-quality-windows-x86:
    {{ python }} contrib/setup/orchestrator.py core,essential,toolchain,build
    {{ python }} contrib/setup/orchestrator.py quality --platform windows-x86

setup-quality-windows-arm:
    {{ python }} contrib/setup/orchestrator.py core,essential,toolchain,build
    {{ python }} contrib/setup/orchestrator.py quality --platform windows-arm

# ── Setup: Coverage toolchain ──────────────────────────────────────────────

setup-coverage-linux-x86-clang:
    {{ python }} contrib/setup/orchestrator.py coverage,toolchain

setup-coverage-macos-x86:
    {{ python }} contrib/setup/orchestrator.py core,build,toolchain,coverage

setup-coverage-macos-arm:
    {{ python }} contrib/setup/orchestrator.py core,build,toolchain,coverage

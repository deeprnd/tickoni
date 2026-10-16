"""Verify all justfile-referenced helper scripts exist on disk.

This catches broken references before they cause CI failures — similar to
the `run_unit_tests_dynamic.sh` → `infra/dynamic_test_opts.py` migration
where the justfile reference was never updated.

Usage:
    pytest contrib/test/test_justfile_script_refs.py
"""

import re
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parent.parent.parent
JUSTFILE = REPO_ROOT / "justfile"


# ── Fixture ──────────────────────────────────────────────────────────────
@pytest.fixture(scope="module")
def justfile_content() -> str:
    return JUSTFILE.read_text(encoding="utf-8")


# ── Test ─────────────────────────────────────────────────────────────────
def test_justfile_referenced_scripts_exist(justfile_content: str) -> None:
    """Every contrib/ script path referenced in justfile must exist."""

    scripts: set[str] = set()

    # bash <path>
    for m in re.finditer(r"\bbash\s+(contrib/[^ \t\n]+)", justfile_content):
        scripts.add(m.group(1))

    # python3 <path>
    for m in re.finditer(r"\bpython3\s+(contrib/[^ \t\n]+)", justfile_content):
        scripts.add(m.group(1))

    # {{ python }} <path>
    for m in re.finditer(r"\{\{\s*python\s*\}\}\s+(contrib/[^ \t\n]+)", justfile_content):
        scripts.add(m.group(1))

    # `bash <script> [args...]` backtick commands — capture up to the
    # first whitespace after contrib/ to avoid treating arguments as paths
    for m in re.finditer(r"`bash\s+(contrib/[^` \t\n]+)", justfile_content):
        scripts.add(m.group(1))

    # source <path>
    for m in re.finditer(r"\bsource\s+(contrib/[^ \t\n]+)", justfile_content):
        scripts.add(m.group(1))

    # Deduplicate: keep only clean paths (no trailing backtick artifacts)
    scripts = {s for s in scripts if not s.rstrip().endswith("`")}

    missing: list[str] = []
    for script in sorted(scripts):
        full = REPO_ROOT / script
        if not full.exists():
            missing.append(script)

    if missing:
        pytest.fail(
            f"justfile references {len(missing)} non-existent scripts:\n"
            + "\n".join(f"  - {s}" for s in missing)
        )

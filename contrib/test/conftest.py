"""Pytest compatibility hooks for the Tickoni test suite."""

from __future__ import annotations

import os
import sys
from pathlib import Path

from _pytest import pathlib as _pytest_pathlib


_original_bestrelpath = _pytest_pathlib.bestrelpath


def _patched_bestrelpath(directory: Path, dest: Path) -> str:
    """Avoid pytest's Windows path-formatting crash for equivalent paths."""
    try:
        return str(_original_bestrelpath(directory, dest))
    except ValueError:
        try:
            return os.path.relpath(str(dest), str(directory))
        except ValueError:
            return str(dest)


_pytest_pathlib.bestrelpath = _patched_bestrelpath

for _module_name in ("_pytest.config", "_pytest.terminal"):
    _module = sys.modules.get(_module_name)
    if _module is not None:
        _module.bestrelpath = _patched_bestrelpath

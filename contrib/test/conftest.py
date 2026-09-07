"""Monkey-patch pytest bestrelpath to avoid a crash on Windows CI.

In pytest 8.3.x the terminal reporter calls ``bestrelpath(invocation_params.dir,
fullpath)`` to build the location line.  When both resolve to the same
absolute path (which happens when ``pytest contrib/test/`` is invoked from the
repo root on Windows), ``Path.relative_to`` raises::

    ValueError: 'D:\\a\\tickoni\\tickoni' is not in the subpath of ...

This patch intercepts that ``ValueError`` and returns the directory itself,
which is the correct identity fallback.
"""

from _pytest import pathlib as _pytest_pathlib
from pathlib import Path


def _patched_bestrelpath(directory: Path, base: Path) -> Path:
    try:
        return directory.relative_to(base)
    except ValueError:
        return directory


_pytest_pathlib.bestrelpath = _patched_bestrelpath

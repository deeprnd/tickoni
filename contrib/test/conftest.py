"""Monkey-patch pytest bestrelpath to avoid a crash on Windows CI.

In pytest 8.3.x the terminal reporter calls ``bestrelpath(invocation_params.dir,
fullpath)`` to build the location line.  When both resolve to the same
absolute path (which happens when ``pytest contrib/test/`` is invoked from the
repo root on Windows), ``Path.relative_to`` raises::

    ValueError: 'D:\\\\a\\\\tickoni\\\\tickoni' is not in the subpath of ...

This patch intercepts that ``ValueError`` and returns the directory itself,
which is the correct identity fallback.

Why patch in multiple modules?  ``pytest.config.__init__`` does
``from _pytest.pathlib import bestrelpath``, so patching only the module
attribute doesn't update that local binding — we must patch every module
that imported it.
"""

import sys
from pathlib import Path


def _patched_bestrelpath(directory: Path, base: Path) -> str:
    try:
        return str(directory.relative_to(base))
    except ValueError:
        return str(directory)


# Patch the source module.
_pytest_pathlib = sys.modules.get("_pytest.pathlib")
if _pytest_pathlib is not None:
    _pytest_pathlib.bestrelpath = _patched_bestrelpath

# Patch modules that did ``from _pytest.pathlib import bestrelpath``.
for _mod_name in ("_pytest.config", "_pytest.terminal"):
    _mod = sys.modules.get(_mod_name)
    if _mod is not None:
        _mod.bestrelpath = _patched_bestrelpath

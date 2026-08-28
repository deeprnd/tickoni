#!/usr/bin/env python3
"""Run a shell command and update badges with the result."""

import os
import signal
import subprocess
import sys
import time
from pathlib import Path

SCRIPT_DIR = Path(__file__).parent
REPO_ROOT = SCRIPT_DIR.parent.parent
LOCK_PATH = REPO_ROOT / "doc/execution/testing-tickoni.md.lock"
LOCK_POLL_S = 0.05
LOCK_TIMEOUT_S = 30

import importlib.util as _ilu

_spec = _ilu.spec_from_file_location("refresh_badges", SCRIPT_DIR / "refresh-badges.py")
_mod = _ilu.module_from_spec(_spec)
_spec.loader.exec_module(_mod)
update_badge = _mod.update_badge
update_badge_unknown = _mod.update_badge_unknown
README_PATH = _mod.README_PATH

README_BADGES = frozenset({"build", "unit", "security", "cov-tk"})


def _update_readme(name: str, exit_code: int) -> None:
    update_badge(name, exit_code, README_PATH)


def _update_readme_unknown(name: str) -> None:
    update_badge_unknown(name, README_PATH)


def is_process_alive(pid: int) -> bool:
    try:
        os.kill(pid, 0)
        return True
    except OSError:
        return False


def acquire_lock() -> None:
    deadline = time.monotonic() + LOCK_TIMEOUT_S
    while time.monotonic() < deadline:
        try:
            fd = os.open(str(LOCK_PATH), os.O_CREAT | os.O_EXCL | os.O_WRONLY)
            os.write(fd, str(os.getpid()).encode())
            os.close(fd)
            return
        except FileExistsError:
            try:
                owner = int(LOCK_PATH.read_text(encoding="utf-8").strip())
                if not is_process_alive(owner):
                    LOCK_PATH.unlink(missing_ok=True)
                    continue
            except (ValueError, OSError):
                pass
        time.sleep(LOCK_POLL_S)
    raise TimeoutError(f"Timed out waiting for testing doc lock after {LOCK_TIMEOUT_S}s")


def release_lock() -> None:
    LOCK_PATH.unlink(missing_ok=True)


def run_command(argv: list) -> int:
    print(f"[badge] exec: {argv}", file=sys.stderr)
    result = subprocess.run(argv)
    print(f"[badge] exit: {result.returncode}", file=sys.stderr)
    return result.returncode


def update_badge_with_lock(update_fn, badge_name: str, *args) -> int:
    status = 0
    acquire_lock()
    try:
        fname = getattr(update_fn, "__name__", str(update_fn))
        print(f"[badge] update '{badge_name}' via {fname}{args}", file=sys.stderr)
        update_fn(badge_name, *args)
        print(f"[badge] update '{badge_name}' ok", file=sys.stderr)
    except Exception as e:
        print(f"[badge] update '{badge_name}' failed: {e}", file=sys.stderr)
        status = 1
    finally:
        release_lock()
    return status


def main() -> None:
    args = sys.argv[1:]
    if len(args) < 2:
        print("Usage: run-badged-command.py <badge-name> <argv...>", file=sys.stderr)
        sys.exit(1)

    badge_name = args[0]
    command_argv = args[1:]

    def _cleanup(signum, frame):
        release_lock()
        signal.signal(signum, signal.SIG_DFL)
        os.kill(os.getpid(), signum)

    for sig_name in ("SIGINT", "SIGTERM", "SIGHUP"):
        sig = getattr(signal, sig_name, None)
        if sig is not None:
            signal.signal(sig, _cleanup)

    badge_status = update_badge_with_lock(update_badge_unknown, badge_name)
    command_status = run_command(command_argv)
    badge_status |= update_badge_with_lock(update_badge, badge_name, command_status)

    if badge_name in README_BADGES:
        badge_status |= update_badge_with_lock(_update_readme_unknown, badge_name)
        badge_status |= update_badge_with_lock(_update_readme, badge_name, command_status)

    sys.exit(command_status if command_status != 0 else badge_status)


if __name__ == "__main__":
    main()

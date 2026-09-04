#!/usr/bin/env python3
"""Zig build/test execution strategy.

Invokes `zig build <target>` with the standard test flags.
No server management — pure build/test execution.
"""
import os
import subprocess
import sys


def run_zig_build(target, run_tests):
    """Run zig build <target> with appropriate flags.

    Args:
        target: Zig build target (e.g. 'system-test', 'demo').
        run_tests: If True, adds -Dtest=true and runs the target as a test.

    Returns exit code.
    """
    env = os.environ.copy()
    env.setdefault("ZIG_GLOBAL_CACHE_DIR", ".zig-global-cache")

    cmd = ["zig", "build"]
    if run_tests:
        cmd.append("-Dtest=true")

    cmd.extend(["-Dfd-lib-dir=build/fd-tickoni-fd/lib"])
    cmd.append(target)
    cmd.append("--summary")
    cmd.append("all")

    print(f"running: {' '.join(cmd)}")

    result = subprocess.run(
        cmd,
        env=env,
    )
    return result.returncode

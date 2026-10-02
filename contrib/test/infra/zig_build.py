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
    # Use script directory to resolve paths, not os.getcwd() — 'just' changes
    # cwd to the directory of the imported justfile (e.g. just/test/) which
    # breaks relative path resolution for fd_lib_dir, build_orch, etc.
    script_dir = os.path.dirname(os.path.abspath(__file__))
    repo_root = os.path.normpath(os.path.join(script_dir, "..", "..", ".."))
    env = os.environ.copy()
    env.setdefault("ZIG_GLOBAL_CACHE_DIR", os.path.join(repo_root, "build", ".zig-global-cache"))

    # Ensure fd-lib-dir exists — the build orchestrator must compile
    # libfd_ballet.a, libfd_util.a, etc. before Zig can link them.
    # This mirrors what test-unit-fd-* recipes do in just/common.just.
    build_orch = os.path.join(
        os.path.dirname(os.path.abspath(__file__)),
        "..", "..", "build", "orchestrator.py",
    )
    if not os.path.isfile(build_orch):
        build_orch = os.path.join(
            os.path.dirname(os.path.abspath(__file__)),
            "..", "build", "orchestrator.py",
        )
    fd_lib_dir_abs = os.path.join(repo_root, "build/fd-tickoni-fd/lib")
    if not os.path.isdir(fd_lib_dir_abs) or not os.listdir(fd_lib_dir_abs):
        print(f"fd-lib-dir {fd_lib_dir_abs} not found — building Firedancer libs first")
        subprocess.run([sys.executable, build_orch, "build-fd", "fd-tickoni-fd", "test"], check=True)

    cmd = ["zig", "build"]
    if run_tests:
        cmd.append("-Dtest=true")

    # Use absolute path — zig passes fd_lib_dir through to C compiler
    # commands as a relative path. When cwd differs from repo root (e.g.
    # `just` imports justfile from a subdirectory), relative resolution
    # fails.
    cmd.extend([f"-Dfd-lib-dir={fd_lib_dir_abs}"])
    cmd.append(target)
    cmd.append("--summary")
    cmd.append("all")

    print(f"running: {' '.join(cmd)}")

    result = subprocess.run(
        cmd,
        env=env,
    )
    return result.returncode

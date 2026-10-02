"""Regression tests for Windows system-test shell path handling."""

import os
from pathlib import Path, PureWindowsPath
import subprocess

import pytest


REPO_ROOT = Path(__file__).resolve().parents[2]
LIVE_RUNNER = REPO_ROOT / "contrib" / "test" / "run_live_investment_demo_win.sh"
MODEL_RUNNER = REPO_ROOT / "contrib" / "test" / "run_system_model_tests_win.sh"


def _git_bash() -> str:
    program_files = os.environ.get("ProgramFiles")
    if program_files is None:
        raise RuntimeError("ProgramFiles is required to locate Git Bash on Windows")
    return str(PureWindowsPath(program_files) / "Git" / "bin" / "bash.exe")


def _write_capture_command(path: Path, name: str) -> None:
    path.write_text(
        "#!/usr/bin/bash\n"
        f"printf '{name}|%s|%s\\n' \"$(pwd -W)\" \"$*\" >> \"$CAPTURE_FILE\"\n",
        encoding="utf-8",
    )
    path.chmod(path.stat().st_mode | 0o111)


@pytest.mark.skipif(os.name != "nt", reason="requires Git Bash on Windows")
def test_windows_system_scripts_pass_repo_relative_paths_to_native_tools(
    tmp_path: Path,
) -> None:
    capture_file = tmp_path / "commands.log"
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    _write_capture_command(bin_dir / "python", "python")

    env = os.environ.copy()
    env["CAPTURE_FILE"] = str(capture_file)
    env["PATH"] = str(bin_dir) + os.pathsep + env["PATH"]

    for runner in (LIVE_RUNNER, MODEL_RUNNER):
        result = subprocess.run(
            [_git_bash(), str(runner), "windows-arm"],
            cwd=tmp_path,
            env=env,
            capture_output=True,
            text=True,
        )
        assert result.returncode == 0, result.stdout + result.stderr

    commands = capture_file.read_text(encoding="utf-8").splitlines()
    expected_cwd = os.path.normcase(os.path.realpath(REPO_ROOT))
    command_cwds = [
        os.path.normcase(os.path.realpath(line.split("|", 2)[1]))
        for line in commands
    ]
    assert all(cwd == expected_cwd for cwd in command_cwds), command_cwds
    assert any(
        line.endswith(
            "|contrib/setup/orchestrator.py llm-server --platform windows-arm"
        )
        for line in commands
    )
    assert any(
        line.endswith("|contrib/test/orchestrator.py llm-server-start")
        for line in commands
    )
    assert any(
        line.endswith("|contrib/test/orchestrator.py llm-server-stop")
        for line in commands
    )
    assert any(
        line.endswith(
            "|contrib/test/orchestrator.py zig-test --target system-test"
        )
        for line in commands
    )

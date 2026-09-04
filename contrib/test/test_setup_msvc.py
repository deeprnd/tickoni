"""Regression tests for the Windows MSVC bootstrap command."""

from types import SimpleNamespace
import sys
import importlib.util
from pathlib import Path


setup_dir = Path(__file__).resolve().parents[1] / "setup"
sys.path.insert(0, str(setup_dir))
platform_spec = importlib.util.spec_from_file_location("platform", setup_dir / "platform.py")
platform_module = importlib.util.module_from_spec(platform_spec)
sys.modules["platform"] = platform_module
platform_spec.loader.exec_module(platform_module)
from contrib.setup.install.strategies import apt


def test_windows_msvc_install_requests_vctools_workload(monkeypatch):
    commands = []

    monkeypatch.setattr(apt, "_find_winget_shell", lambda: "winget.exe")

    def run(command, **kwargs):
        commands.append(command)
        return SimpleNamespace(returncode=0, stdout="", stderr="")

    monkeypatch.setattr(apt.subprocess, "run", run)

    apt.WingetInstallStrategy().execute(
        {
            "name": "msvc",
            "parameters": {
                "package": "Microsoft.VisualStudio.2022.BuildTools",
                "override": (
                    "--add Microsoft.VisualStudio.Workload.VCTools "
                    "--includeRecommended --quiet --wait --norestart"
                ),
            },
        },
        {},
        "windows-arm",
        False,
    )

    assert commands == [[
        "winget.exe", "install", "--exact", "--id", "Microsoft.VisualStudio.2022.BuildTools",
        "--accept-package-agreements", "--accept-source-agreements",
        "--disable-interactivity", "--source", "winget", "--override",
        "--add Microsoft.VisualStudio.Workload.VCTools --includeRecommended "
        "--quiet --wait --norestart",
    ]]
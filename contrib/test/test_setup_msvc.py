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
from contrib.setup.install.strategies import system_package


def test_windows_msvc_install_requests_vctools_workload(monkeypatch):
    commands = []

    monkeypatch.setattr(system_package, "_require_winget", lambda: "winget.exe")

    def run(command, **kwargs):
        commands.append(command)
        return SimpleNamespace(returncode=0, stdout="", stderr="")

    monkeypatch.setattr(system_package.subprocess, "run", run)

    system_package.WingetInstallStrategy().execute(
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


def test_windows_msvc_absolute_winget_path_is_invoked_directly(monkeypatch):
    commands = []
    monkeypatch.setattr(
        system_package, "_require_winget",
        lambda: r"C:\Program Files\WindowsApps\AppInstaller\winget.exe",
    )

    def run(command, **kwargs):
        commands.append(command)
        return SimpleNamespace(returncode=0, stdout="", stderr="")

    monkeypatch.setattr(system_package.subprocess, "run", run)
    system_package.WingetInstallStrategy().execute(
        {"name": "ccache", "parameters": {"package": "Ccache.Ccache"}},
        {}, "windows-arm", False,
    )

    assert commands[0][:2] == [
        r"C:\Program Files\WindowsApps\AppInstaller\winget.exe", "install",
    ]
    assert "/c" not in commands[0]
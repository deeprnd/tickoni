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
from contrib.setup.install.strategies import winget


def test_windows_msvc_install_requests_vctools_and_arm64_toolsets(monkeypatch):
    commands = []
    component_calls = []

    monkeypatch.setattr(winget, "_require_winget", lambda: "winget.exe")
    monkeypatch.setattr(
        winget, "_ensure_visual_studio_components",
        lambda components: component_calls.append(components),
    )

    def run(command, **kwargs):
        commands.append(command)
        return SimpleNamespace(returncode=0, stdout="", stderr="")

    monkeypatch.setattr(winget.subprocess, "run", run)

    winget.WingetInstallStrategy().execute(
        {
            "name": "msvc",
            "parameters": {
                "package": "Microsoft.VisualStudio.2022.BuildTools",
                "components": ["Microsoft.VisualStudio.Component.VC.Tools.ARM64"],
                "override": (
                    "--add Microsoft.VisualStudio.Workload.VCTools "
                    "--add Microsoft.VisualStudio.Component.VC.Tools.ARM64 "
                    "--includeRecommended --quiet --norestart"
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
        "--add Microsoft.VisualStudio.Workload.VCTools "
        "--add Microsoft.VisualStudio.Component.VC.Tools.ARM64 --includeRecommended "
        "--quiet --norestart",
    ]]
    assert component_calls == [["Microsoft.VisualStudio.Component.VC.Tools.ARM64"]]


def test_missing_msvc_component_is_reconciled_by_synchronous_bootstrapper(monkeypatch):
    commands = []

    def run(command, **kwargs):
        commands.append(command)
        if len(commands) == 1:
            return SimpleNamespace(
                returncode=0,
                stdout="C:\\Program Files (x86)\\Microsoft Visual Studio\\2022\\BuildTools\n",
                stderr="",
            )
        return SimpleNamespace(returncode=0, stdout="", stderr="")

    compiler_checks = iter([[], [r"C:\\compiler\\cl.exe"]])
    monkeypatch.setattr(winget.subprocess, "run", run)
    monkeypatch.setattr(winget.glob, "glob", lambda pattern: next(compiler_checks))
    monkeypatch.setattr(winget.tempfile, "gettempdir", lambda: r"C:\Temp")
    monkeypatch.setattr(winget.os.path, "isfile", lambda path: True)

    winget._ensure_visual_studio_components(["Microsoft.VisualStudio.Component.VC.Tools.ARM64"])

    assert commands[1] == [
        r"C:\Temp\tickoni-vs-buildtools.exe", "--quiet", "--wait", "--norestart",
        "--installPath", r"C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools",
        "--add", "Microsoft.VisualStudio.Component.VC.Tools.ARM64", "--includeRecommended",
    ]


def test_windows_msvc_absolute_winget_path_is_invoked_directly(monkeypatch):
    commands = []
    monkeypatch.setattr(
        winget, "_require_winget",
        lambda: r"C:\Program Files\WindowsApps\AppInstaller\winget.exe",
    )

    def run(command, **kwargs):
        commands.append(command)
        return SimpleNamespace(returncode=0, stdout="", stderr="")

    monkeypatch.setattr(winget.subprocess, "run", run)
    winget.WingetInstallStrategy().execute(
        {"name": "ccache", "parameters": {"package": "Ccache.Ccache"}},
        {}, "windows-arm", False,
    )

    assert commands[0][:2] == [
        r"C:\Program Files\WindowsApps\AppInstaller\winget.exe", "install",
    ]
    assert "/c" not in commands[0]
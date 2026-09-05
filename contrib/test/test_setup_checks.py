"""Tests for platform-aware setup idempotency checks."""

from types import SimpleNamespace
from unittest.mock import patch

from contrib.setup.install.checks import ExecutableCheck, ShellCheckCommand, build_check
from contrib.setup.install.strategies import apt


def test_windows_simple_command_v_uses_executable_lookup():
    check = build_check(
        {'idempotent_check': 'command -v curl'},
        'windows-arm',
    )

    assert isinstance(check, ExecutableCheck)
    with patch('contrib.setup.install.checks.command.shutil.which', return_value='curl.exe'):
        assert check.is_satisfied()


def test_non_windows_check_keeps_shell_command():
    check = build_check({'idempotent_check': 'command -v curl'}, 'linux-x86')

    assert isinstance(check, ShellCheckCommand)


def test_windows_compound_check_keeps_shell_command():
    check = build_check(
        {'idempotent_check': 'command -v ninja || command -v make'},
        'windows-arm',
    )

    assert isinstance(check, ShellCheckCommand)


def test_winget_resolution_reports_app_installer_missing():
    with patch.object(apt, '_refresh_winget_path'), \
         patch.object(apt.shutil, 'which', side_effect=lambda name: 'pwsh' if name == 'pwsh' else None), \
         patch.object(apt, '_probe_winget_power_shell', return_value=False), \
         patch.object(apt, '_app_installer_present', return_value=False), \
         patch.object(apt.subprocess, 'run', return_value=SimpleNamespace(returncode=1, stdout='', stderr='')):
        resolution = apt._find_winget_shell()

    assert resolution.command is None
    assert resolution.status == 'app_installer_missing'


def test_winget_path_refresh_does_not_append_entire_package_tree(monkeypatch):
    monkeypatch.setenv('LOCALAPPDATA', 'C:/Users/runner/AppData/Local')
    monkeypatch.setenv('PATH', 'C:/Windows/System32')
    calls = []

    def fake_glob(pattern, recursive=False):
        calls.append((pattern, recursive))
        normalized = pattern.replace(chr(92), '/')
        if normalized.endswith('Packages/*'):
            return ['C:/package-root/ccache']
        if normalized.endswith('Packages/*/bin'):
            return ['C:/package-root/ccache/bin']
        if normalized.endswith('Packages/*/*/bin'):
            return ['C:/package-root/ccache/version/bin']
        return []

    monkeypatch.setattr(apt.glob, 'glob', fake_glob)
    monkeypatch.setattr(apt.os.path, 'isdir', lambda path: True)

    apt._refresh_winget_path()

    path_entries = apt.os.environ['PATH'].split(apt.os.pathsep)
    assert len(path_entries) == 5
    assert all(not recursive for _, recursive in calls)
    assert all('Packages/**' not in pattern for pattern, _ in calls)


def test_winget_failure_classifies_missing_package():
    assert apt._winget_failure_status(
        'No package found matching input criteria.'
    ) == 'package_not_found_or_unsupported'
    assert apt._winget_failure_status('network failure') == 'install_failed'

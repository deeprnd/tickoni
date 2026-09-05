"""Tests for platform-aware setup idempotency checks."""

from types import SimpleNamespace
from unittest.mock import patch

from contrib.setup.install.checks import ExecutableCheck, ShellCheckCommand, build_check
from contrib.setup.install.strategies import system_package


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
    with patch.object(system_package, '_refresh_winget_path'), \
         patch.object(system_package.shutil, 'which', side_effect=lambda name: 'pwsh' if name == 'pwsh' else None), \
         patch.object(system_package, '_probe_winget_power_shell', return_value=False), \
         patch.object(system_package, '_app_installer_present', return_value=False), \
         patch.object(system_package.subprocess, 'run', return_value=SimpleNamespace(returncode=1, stdout='', stderr='')):
        resolution = system_package._find_winget_shell()

    assert resolution.command is None
    assert resolution.status == 'app_installer_missing'


def test_winget_resolution_uses_registered_appx_executable():
    with patch.object(system_package, '_refresh_winget_path'), \
         patch.object(system_package.shutil, 'which', side_effect=lambda name: 'pwsh' if name == 'pwsh' else None), \
         patch.object(system_package, '_appx_winget_path', return_value='C:/WindowsApps/AppInstaller/winget.exe'), \
         patch.object(system_package.subprocess, 'run', return_value=SimpleNamespace(
             returncode=0, stdout='v1.29.290\n', stderr='')):
        resolution = system_package._find_winget_shell()

    assert resolution.command == 'C:/WindowsApps/AppInstaller/winget.exe'
    assert resolution.status == 'appx'


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

    monkeypatch.setattr(system_package.glob, 'glob', fake_glob)
    monkeypatch.setattr(system_package.os.path, 'isdir', lambda path: True)

    system_package._refresh_winget_path()

    path_entries = system_package.os.environ['PATH'].split(system_package._WINDOWS_PATH_SEP)
    assert len(path_entries) == 5
    assert all(not recursive for _, recursive in calls)
    assert all('Packages/**' not in pattern for pattern, _ in calls)


def test_winget_failure_classifies_missing_package():
    assert system_package._winget_failure_status(
        'No package found matching input criteria.'
    ) == 'package_not_found_or_unsupported'
    assert system_package._winget_failure_status('network failure') == 'install_failed'

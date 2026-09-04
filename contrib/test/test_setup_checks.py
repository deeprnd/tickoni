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


def test_winget_failure_classifies_missing_package():
    assert apt._winget_failure_status(
        'No package found matching input criteria.'
    ) == 'package_not_found_or_unsupported'
    assert apt._winget_failure_status('network failure') == 'install_failed'

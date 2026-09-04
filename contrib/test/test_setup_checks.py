"""Tests for platform-aware setup idempotency checks."""

from unittest.mock import patch

from contrib.setup.install.checks import ExecutableCheck, ShellCheckCommand, build_check


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

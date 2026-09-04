"""Native command selection for setup helper scripts."""
import os
import shutil
from pathlib import Path


def bash_command():
    """Return a native shell command for running repo Bash helpers.

    Native Windows runners can have ``C:\\Windows\\System32\\bash.exe``
    (the WSL launcher) ahead of Git for Windows on PATH. The WSL launcher
    fails before executing a script when WSL is not installed or current, so
    setup helpers must select Git Bash explicitly on Windows.
    """
    if os.name != 'nt':
        return 'bash'

    candidates = []
    bash_on_path = shutil.which('bash.exe') or shutil.which('bash')
    if bash_on_path:
        candidates.append(Path(bash_on_path))

    git_on_path = shutil.which('git.exe') or shutil.which('git')
    if git_on_path:
        git_root = Path(git_on_path).parent.parent
        candidates.append(git_root / 'usr' / 'bin' / 'bash.exe')
        candidates.append(git_root / 'bin' / 'bash.exe')

    for root_var in ('ProgramFiles', 'ProgramFiles(x86)'):
        root = os.environ.get(root_var)
        if root:
            candidates.append(Path(root) / 'Git' / 'usr' / 'bin' / 'bash.exe')
            candidates.append(Path(root) / 'Git' / 'bin' / 'bash.exe')

    for candidate in candidates:
        normalized = str(candidate).lower().replace('\\', '/')
        if candidate.is_file() and '/windows/system32/' not in normalized:
            return str(candidate)

    raise RuntimeError(
        'Git Bash was not found on PATH or under Program Files; '
        'the Windows setup helpers require Git for Windows'
    )

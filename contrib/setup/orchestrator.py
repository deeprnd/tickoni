#!/usr/bin/env python3
"""CI tool orchestrator — reads tool-versions.json and installs tools.

Facade pattern: single API that hides the dependency-resolution →
tool-collection → platform-filter → install pipeline.

Usage:
    python3 orchestrator.py <category1,category2,...>     # Install
    python3 orchestrator.py <categories> --dry-run        # Preview
    python3 orchestrator.py --deps <category>              # Show resolved deps
    python3 orchestrator.py --list <category>              # List tools
    python3 orchestrator.py <categories> --platform linux-x86  # Override platform
"""
import argparse
import os
import sys

try:
    from dotenv import load_dotenv
except ImportError:
    load_dotenv = lambda *a, **k: None


# Ensure the setup directory is on sys.path so that
# `import config`, `import install`, etc. work regardless of cwd.
_script_dir = os.path.dirname(os.path.abspath(__file__))
if _script_dir not in sys.path:
    sys.path.insert(0, _script_dir)


# ── Imports ──────────────────────────────────────────────────────────────────

from config import load_config, env_flag
from resolver import DependencyResolver
from platform import matches_platform, detect_platform, get_platform_from_string
from install import get as get_strategy
from install.checks import build_check


def _resolve_install_method(method, platform_str: str, tool_name: str) -> str:
    """Pick the concrete install strategy for the target platform.

    ``install_method`` is normally a strategy name (``"apt"``, ``"brew"``,
    ``"winget"``, ``"pip"``, ...). A tool available on several platforms via
    different system package managers instead maps OS → strategy, e.g.
    ``{"linux": "apt", "macos": "brew", "windows": "winget"}``. Choosing one for
    this run is orchestrator logic; the strategies stay single-purpose.
    """
    if isinstance(method, str):
        return method
    if not isinstance(method, dict):
        raise KeyError(f"{tool_name}: install_method must be a string or an OS map")
    os_name, _ = get_platform_from_string(platform_str)
    if os_name == 'darwin':
        os_name = 'macos'
    selected = method.get(os_name)
    if not selected:
        raise KeyError(
            f"{tool_name}: install_method has no entry for '{os_name}' "
            f"(platform '{platform_str}'); has {sorted(method)}"
        )
    return selected


# ── Orchestrator Facade ──────────────────────────────────────────────────────

class Orchestrator:
    """Facade: setup_categories(['fd']) → installs everything."""

    def __init__(self, config: dict):
        self.config = config
        self.resolver = DependencyResolver(config['dependencies'])

    def setup(self, categories: list[str], platform_str: str, dry_run: bool, skip_idempotency: bool = False) -> list[dict]:
        """Run the full setup pipeline. Returns list of install results."""
        resolved = self.resolver.resolve(categories)
        tools = self.resolver.collect(resolved, self.config['categories'], self.config['tools'])
        tools = [t for t in tools if matches_platform(t, platform_str)]
        results = []
        for tool in tools:
            result = self._install_tool(tool, platform_str, dry_run, skip_idempotency)
            results.append(result)
        return results

    def _install_tool(self, tool: dict, platform_str: str, dry_run: bool, skip_idempotency: bool = False) -> dict:
        """Install a single tool using the strategy registry and command pattern."""
        name = tool['name']
        try:
            method = _resolve_install_method(tool['install_method'], platform_str, name)
        except KeyError as e:
            print(f"ERROR: {e}", file=sys.stderr)
            return {'tool': name, 'status': 'error', 'error': str(e)}

        # Idempotency check via Command pattern.
        # For install_zig, skip the idempotency shortcut — we need to write
        # GITHUB_PATH for PATH propagation even when the tool is already
        # installed. build_from_source and binary_download use their
        # idempotent_check like normal methods.
        skip_path = method not in ('install_zig',)
        check_cmd = build_check(tool, platform_str)
        if check_cmd and check_cmd.is_satisfied() and skip_path and not skip_idempotency:
            return {'tool': name, 'status': 'already_installed'}

        if dry_run:
            print(f"[DRY-RUN] Would install {name} via {method}")
            return {'tool': name, 'status': 'dry_run'}

        print(f"[INSTALL] {name} (method={method})")

        try:
            strategy = get_strategy(method)
            strategy.execute(tool, self.config, platform_str, dry_run=False)
            return {'tool': name, 'status': 'installed'}
        except KeyError as e:
            print(f"ERROR: unknown install_method '{method}' for {name}", file=sys.stderr)
            return {'tool': name, 'status': 'error', 'error': str(e)}
        except SystemExit:
            return {'tool': name, 'status': 'failed'}


# ── Main ─────────────────────────────────────────────────────────────────────

def main():
    # Load .env file into environment if it exists (local dev credentials).
    # CI: secrets (QT_USERNAME, QT_PASSWORD) are already in the runner env.
    _repo_root = os.path.dirname(os.path.dirname(_script_dir))
    load_dotenv(os.path.join(_repo_root, '.env'), override=False)

    parser = argparse.ArgumentParser(description='CI tool orchestrator')
    parser.add_argument('categories', nargs='?', help='Comma-separated category list')
    parser.add_argument('--deps', help='Show resolved dependency graph for a category')
    parser.add_argument('--list', help='List all tools in a category')
    parser.add_argument('--dry-run', action='store_true', help='Preview without installing')
    parser.add_argument('--skip-idempotency', action='store_true', help='Skip idempotency checks — reinstall all tools')
    parser.add_argument('--platform', help='Platform string from contrib/platform.sh (e.g. linux-x86, macos-arm)')

    args = parser.parse_args()

    # Support SKIP_IDEMPOTENCY env var (used by justfile recipes)
    skip_idempotency = args.skip_idempotency or env_flag('SKIP_IDEMPOTENCY')

    if args.deps:
        config = load_config()
        resolver = DependencyResolver(config['dependencies'])
        cats = resolver.resolve([args.deps])
        print(f"Dependencies for '{args.deps}': {', '.join(cats)}")
        return

    if args.list:
        config = load_config()
        cat_config = config['categories']
        for t in cat_config.get(args.list, {}).get('tools', []):
            print(f"  {t}")
        return

    if not args.categories:
        parser.print_help()
        sys.exit(1)

    config = load_config()
    requested = [c.strip() for c in args.categories.split(',')]

    orch = Orchestrator(config)
    resolved = orch.resolver.resolve(requested)
    print(f"Resolved categories: {', '.join(resolved)}")

    plat = detect_platform(args.platform)
    print(f"Platform: {plat}")

    results = orch.setup(requested, plat, dry_run=args.dry_run, skip_idempotency=skip_idempotency)

    if not args.dry_run:
        ok = sum(1 for r in results if r['status'] in ('installed', 'already_installed'))
        fail = sum(1 for r in results if r['status'] == 'failed')
        print(f"\n[COMPLETE] {ok}/{len(results)} tools handled ({fail} failed)")
        if fail > 0:
            sys.exit(1)
    else:
        print(f"\n[DRY-RUN] Would install {len(results)} tools on {plat}")


if __name__ == '__main__':
    main()

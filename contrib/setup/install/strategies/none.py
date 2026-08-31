"""None strategy — no-op install."""
from ..base import InstallStrategy
from .. import register


@register('none')
class NoneStrategy(InstallStrategy):
    """No-op strategy for tools that don't need installation."""

    def execute(self, tool: dict, config: dict, platform_str: str, dry_run: bool) -> None:
        if dry_run:
            print(f"  [DRY-RUN] Would skip (none)")

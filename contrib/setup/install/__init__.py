"""Install strategies — registry and factory."""
import os
import sys

# Ensure the setup directory is on sys.path so that install/strategies can
# import config and platform from the parent (setup) directory.
_setup_dir = os.path.dirname(os.path.abspath(__file__))
_parent = os.path.dirname(_setup_dir)
if _parent not in sys.path:
    sys.path.insert(0, _parent)

from .base import InstallStrategy


_REGISTRY: dict[str, type[InstallStrategy]] = {}


def register(method_name: str):
    """Decorator: register a strategy class under a method name."""
    def decorator(cls: type[InstallStrategy]) -> type[InstallStrategy]:
        _REGISTRY[method_name] = cls
        return cls
    return decorator


def get(method_name: str) -> InstallStrategy:
    """Factory + registry: return a ready-to-use strategy instance."""
    cls = _REGISTRY.get(method_name)
    if cls is None:
        raise KeyError(f"unknown install_method '{method_name}'")
    return cls()


# Import all strategy modules to trigger @register decorators
from . import strategies  # noqa: F401, E402

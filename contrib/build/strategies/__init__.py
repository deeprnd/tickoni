#!/usr/bin/env python3
"""Strategy registry for platform-specific build logic."""

import importlib
import sys
import os


def load(platform: str):
    """Load and return the strategy module for the given platform string.

    Platform strings match the keys in build-config.json (e.g. "linux-x86",
    "macos-arm", "windows-x86").
    """
    platform = platform.lower()
    if platform.startswith("linux"):
        module = importlib.import_module(".linux", "contrib.build.strategies")
    elif platform.startswith("macos"):
        module = importlib.import_module(".macos", "contrib.build.strategies")
    elif platform.startswith("windows"):
        module = importlib.import_module(".windows", "contrib.build.strategies")
    else:
        raise ValueError(f"Unknown platform: {platform}")
    return module

#!/usr/bin/env bash
# Resolve the justfile directory path with forward slashes on every platform.
#
# justfile_directory() returns backslashes on Windows which bash interprets
# as escape sequences (\t → tab, etc.). This script normalises the path
# to always use forward slashes so recipe paths work identically everywhere.
#
# Usage:
#   contrib/justfile.sh          → full path (forward slashes)
#
set -euo pipefail

# Get the repo root (where the justfile lives) via git, then normalise slashes.
git rev-parse --show-toplevel 2>/dev/null | sed 's|\\|/|g'

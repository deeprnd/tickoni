#!/usr/bin/env python3
"""Phase 1b.4: Update build_config.json + regenerate config + rewrite affected files."""

import json
import sys
from pathlib import Path

BUILD_DIR = Path(__file__).parent
CONFIG_JSON = BUILD_DIR / "build_config.json"

def main():
    # 1. Add "fd_tango" system_lib group for Firedancer substrate (tango+util+uuid)
    with open(CONFIG_JSON) as f:
        data = json.load(f)
    
    # Insert "fd_tango" after "codec" in system_libs
    system_libs = data.get("system_libs", [])
    fd_tango = {
        "name": "fd_tango",
        "object_deps": [
            {"path": "libfd_tango.a"},
            {"path": "libfd_util.a"},
            {"path": "libuuid.a"}
        ],
        "needs_libcpp": True
    }
    # Find index of "codec" and insert after it
    codec_idx = next((i for i, sl in enumerate(system_libs) if sl["name"] == "codec"), -1)
    if codec_idx >= 0:
        system_libs.insert(codec_idx + 1, fd_tango)
        data["system_libs"] = system_libs
    
    with open(CONFIG_JSON, "w") as f:
        json.dump(data, f, indent=2)
        f.write("\n")
    
    print(f"Updated {CONFIG_JSON} — added 'fd_tango' system_lib group")
    
    # 2. Regenerate config.zig
    gen_config = BUILD_DIR / "gen_config.py"
    import subprocess
    result = subprocess.run([sys.executable, str(gen_config)], capture_output=True, text=True)
    if result.returncode != 0:
        print(f"ERROR: gen_config.py failed: {result.stderr}", file=sys.stderr)
        sys.exit(1)
    print(result.stdout.strip())

if __name__ == "__main__":
    main()

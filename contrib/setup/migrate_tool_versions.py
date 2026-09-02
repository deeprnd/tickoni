#!/usr/bin/env python3
"""Migration script to normalize tool-versions.json.

Reads the current tool-versions.json and build-config.json, applies
transformations per the normalization rules, and writes the new file.
"""
import json
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
ROOT = SCRIPT_DIR.parent
TOOL_VERSIONS = SCRIPT_DIR / 'tool-versions.json'
BUILD_CONFIG = ROOT / 'build' / 'build-config.json'


def load(path):
    with open(path) as f:
        return json.load(f)


def migrate(versions, tools):
    """Apply all normalization rules to versions and tools dicts."""
    new_versions = {}

    for name in list(versions.keys()):
        entry = versions[name]

        # 1. Skip zig-minisign — its key moves into zig.options
        if name == 'zig-minisign':
            continue

        # 2. Simple versions (bare strings) → {version: "..."}
        if isinstance(entry, str):
            new_versions[name] = {"version": entry}
            continue

        # 3. OpenSSL: version + tag at same level → wrap tag in options
        if name == 'openssl':
            new_versions[name] = {
                "version": entry.get("version", ""),
                "options": {"tag": entry.get("tag", "")}
            }
            continue

        # 4. gcc, clang, msvc: platform keys directly → wrap in options
        if name in ('gcc', 'clang', 'msvc'):
            new_versions[name] = {
                "version": "multi",
                "options": dict(entry)
            }
            continue

        new_versions[name] = entry

    # 5. Zig: add minisign key from removed zig-minisign entry
    zig_key = versions.get('zig-minisign', {})
    if isinstance(zig_key, dict):
        minisign_key = zig_key.get('key', '')
    else:
        minisign_key = str(zig_key)

    zig_entry = new_versions.get('zig', {})
    if 'options' not in zig_entry:
        zig_entry['options'] = {}
    zig_entry['options']['minisign_key'] = minisign_key
    new_versions['zig'] = zig_entry

    # 6. llama-cpp: pull from build-config.json
    build_config = load(BUILD_CONFIG)
    llama_config = build_config.get('llama_cpp', {})
    artifacts = llama_config.get('artifacts', {})
    llama_version = llama_config.get('version', '')

    sha_map = {}
    filename_map = {}
    extract_dir_map = {}
    server_bin_map = {}
    for plat, art in artifacts.items():
        sha_map[plat] = art.get('sha256')
        filename_map[plat] = art.get('filename', '')
        extract_dir_map[plat] = art.get('extract_dir', '.')
        sb = art.get('server_bin')
        if sb:
            server_bin_map[plat] = sb

    new_versions['llama-cpp'] = {
        "version": llama_version,
        "options": {
            "base_url": llama_config.get('base_url', ''),
            "sha256": sha_map,
            "filename": filename_map,
            "extract_dir": extract_dir_map,
            "server_bin": server_bin_map
        }
    }

    # 7. Tools: remove version_ref_sig from zig, ensure version_ref at tool level
    if 'zig' in tools:
        zig_tool = tools['zig']
        zig_tool.pop('version_ref_sig', None)
        if 'version_ref' not in zig_tool:
            zig_tool['version_ref'] = 'zig'

    return new_versions, tools


def main():
    data = load(TOOL_VERSIONS)
    new_versions, new_tools = migrate(data['versions'], data.get('tools', {}))

    result = {
        "versions": new_versions,
        "categories": data.get("categories", {}),
        "dependencies": data.get("dependencies", {}),
        "tools": new_tools
    }

    with open(TOOL_VERSIONS, 'w') as f:
        json.dump(result, f, indent=2)
        f.write('\n')

    print(f"OK: migrated {TOOL_VERSIONS}")


if __name__ == '__main__':
    main()

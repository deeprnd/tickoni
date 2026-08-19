#!/usr/bin/env python3
"""Generate Zig config from build_config.json.

This is a build-time generator that runs before zig build.
It reads tickoni-build/build_config.json and outputs
tickoni-build/generated/config.zig with Zig struct definitions.

Paths are stored relative to lib_dir — the actual lib_dir is
provided by -Dfd-lib-dir at build time. This eliminates hardcoded
path strings from Zig code.
"""

import json
import sys
from pathlib import Path

def strip_lib_dir_prefix(path, lib_dir_prefix="build/fd-tickoni-fd/lib/"):
    """Strip the lib_dir prefix from a path, keeping just the filename."""
    if path.startswith(lib_dir_prefix):
        return path[len(lib_dir_prefix):]
    # If path doesn't match expected prefix, just return the basename
    return Path(path).name

def generate():
    script_dir = Path(__file__).parent
    config_path = script_dir / "build_config.json"
    output_path = script_dir / "generated" / "config.zig"
    
    if not config_path.exists():
        print(f"ERROR: {config_path} not found.", file=sys.stderr)
        sys.exit(1)
    
    with open(config_path, "r") as f:
        data = json.load(f)
    
    output_path.parent.mkdir(parents=True, exist_ok=True)
    
    lines = []
    lines.append('/// Generated config from build_config.json.')
    lines.append('/// DO NOT EDIT — regenerate with: python gen_config.py')
    lines.append('/// Paths are relative to lib_dir (set via -Dfd-lib-dir).')
    lines.append('')
    lines.append('const std = @import("std");')
    lines.append('')
    lines.append('/// Object file dependency entry.')
    lines.append('pub const ObjectDep = struct {')
    lines.append('    path: []const u8,')
    lines.append('};')
    lines.append('')
    lines.append('/// Domain configuration entry — mirrors build_config.json domains array.')
    lines.append('pub const DomainConfig = struct {')
    lines.append('    name: []const u8,')
    lines.append('    strategy: []const u8,')
    lines.append('    archive_name: ?[]const u8 = null,')
    lines.append('    c_sources: []const []const u8 = &.{},')
    lines.append('    object_deps: []const ObjectDep = &.{},')
    lines.append('    dependencies: []const []const u8 = &.{},')
    lines.append('    root_source: ?[]const u8 = null,')
    lines.append('    c_flags: []const []const u8 = &.{},')
    lines.append('};')
    lines.append('')
    lines.append('/// All domain configs from JSON. Paths are relative to lib_dir.')
    lines.append('pub const domain_configs: []const DomainConfig = &.{')
    
    for domain in data.get("domains", []):
        name = domain["name"]
        strategy = domain.get("strategy", "zig_module")
        archive_name = domain.get("archive_name", None)
        c_sources = domain.get("c_sources", [])
        deps = domain.get("object_deps", [])
        dependencies = domain.get("dependencies", [])
        root_source = domain.get("root_source", None)
        c_flags = domain.get("c_flags", [])
        
        # Strip lib_dir prefix from paths - keep only filename
        cleaned_deps = []
        for dep in deps:
            dep_path = strip_lib_dir_prefix(dep["path"])
            cleaned_deps.append(dep_path)
        
        lines.append(f'    DomainConfig{{')
        lines.append(f'        .name = "{name}",')
        lines.append(f'        .strategy = "{strategy}",')
        
        if archive_name:
            lines.append(f'        .archive_name = "{archive_name}",')
        else:
            lines.append(f'        .archive_name = null,')
        
        lines.append(f'        .c_sources = &.{{')
        for src in c_sources:
            lines.append(f'            "{src}",')
        lines.append(f'        }},')
        
        lines.append(f'        .object_deps = &.{{')
        for dep_path in cleaned_deps:
            lines.append(f'            .{{ .path = "{dep_path}" }},')
        lines.append(f'        }},')
        
        lines.append(f'        .dependencies = &.{{')
        for dep in dependencies:
            lines.append(f'            "{dep}",')
        lines.append(f'        }},')
        
        if root_source:
            lines.append(f'        .root_source = "{root_source}",')
        else:
            lines.append(f'        .root_source = null,')
        
        lines.append(f'        .c_flags = &.{{')
        for flag in c_flags:
            lines.append(f'            "{flag}",')
        lines.append(f'        }},')
        
        lines.append(f'    }},')
    
    lines.append('};')
    lines.append('')
    
    # Generate domain lookup function
    lines.append('/// Get domain config by name. Returns null if not found.')
    lines.append('pub fn getDomainByName(name: []const u8) ?DomainConfig {')
    lines.append('    for (domain_configs) |dc| {')
    lines.append('        if (std.mem.eql(u8, dc.name, name)) return dc;')
    lines.append('    }')
    lines.append('    return null;')
    lines.append('}')
    lines.append('')
    
    with open(output_path, "w") as f:
        f.write("\n".join(lines))
    
    print(f"Generated {output_path}")

if __name__ == "__main__":
    generate()

#!/usr/bin/env python3
"""Thread fd_lib_dir through the build.zig → specs → helpers call chain."""

import re
import sys

# --- 1. build.zig: add fd_lib_dir to allModules call ---
with open("build.zig") as f:
    content = f.read()

# Change: const all = mod.allModules(b, target, optimize);
# To:     const all = mod.allModules(b, target, optimize, fd_lib_dir);
content = content.replace(
    "const all = mod.allModules(b, target, optimize);",
    "const all = mod.allModules(b, target, optimize, fd_lib_dir);"
)

with open("build.zig", "w") as f:
    f.write(content)
print("build.zig: ✓")

# --- 2. unit_specs.zig: add fd_lib_dir param to registerUnitSpecs, then update all call sites ---
with open("build/test/unit_specs.zig") as f:
    content = f.read()

# Add fd_lib_dir param to the function signature
content = re.sub(
    r'(pub fn registerUnitSpecs\(\s*b: \*std\.Build,\s*modules: @import\("build/mod\.zig"\)\.Modules,)'
    r'(\s*target: std\.Build\.ResolvedTarget,\s*optimize: std\.builtin\.OptimizeMode,\s*step: \*std\.Build\.Step,\s*\) void \{)',
    r'\1\n    fd_lib_dir: []const u8,\2',
    content
)

# Replace all helpers.addPlainTestRun(b, step, xxx); with helpers.addPlainTestRun(b, step, xxx, fd_lib_dir);
content = re.sub(
    r'helpers\.addPlainTestRun\(b, step, ([^\)]+)\)',
    r'helpers.addPlainTestRun(b, step, \1, fd_lib_dir)',
    content
)

with open("build/test/unit_specs.zig", "w") as f:
    f.write(content)
print("unit_specs.zig: ✓")

# --- 3. integration_specs.zig ---
try:
    with open("build/test/integration_specs.zig") as f:
        content = f.read()
    
    # Add fd_lib_dir param
    content = re.sub(
        r'(pub fn registerIntegrationSpecs\(\s*b: \*std\.Build,)'
        r'(\s*modules: @import\("build/mod\.zig"\)\.Modules,\s*test_modules: @import\("build/mod\.zig"\)\.TestModules,\s*target: std\.Build\.ResolvedTarget,\s*optimize: std\.builtin\.OptimizeMode,\s*step: \*std\.Build\.Step,\s*\) void \{)',
        r'\1\n    fd_lib_dir: []const u8,\2',
        content
    )
    
    # Replace all helpers.call sites
    content = re.sub(
        r'helpers\.addPlainTestRun\(b, step, ([^\)]+)\)',
        r'helpers.addPlainTestRun(b, step, \1, fd_lib_dir)',
        content
    )
    
    with open("build/test/integration_specs.zig", "w") as f:
        f.write(content)
    print("integration_specs.zig: ✓")
except FileNotFoundError:
    print("integration_specs.zig: SKIP (not found)")

# --- 4. system_specs.zig ---
try:
    with open("build/test/system_specs.zig") as f:
        content = f.read()
    
    content = re.sub(
        r'(pub fn registerSystemSpecs\(\s*b: \*std\.Build,)'
        r'(\s*modules: @import\("build/mod\.zig"\)\.Modules,\s*test_modules: @import\("build/mod\.zig"\)\.TestModules,\s*target: std\.Build\.ResolvedTarget,\s*optimize: std\.builtin\.OptimizeMode,\s*step: \*std\.Build\.Step,\s*\) void \{)',
        r'\1\n    fd_lib_dir: []const u8,\2',
        content
    )
    
    content = re.sub(
        r'helpers\.addPlainTestRun\(b, step, ([^\)]+)\)',
        r'helpers.addPlainTestRun(b, step, \1, fd_lib_dir)',
        content
    )
    
    with open("build/test/system_specs.zig", "w") as f:
        f.write(content)
    print("system_specs.zig: ✓")
except FileNotFoundError:
    print("system_specs.zig: SKIP (not found)")

print("\nDone. Now manually update build.zig calls to registerSpecs functions.")

"""
Silly tool that verifies whether C/C++ header include guards match
Firedancer code style.
"""

from pathlib import Path
import os


def check_file(path):
    guard_name = "HEADER_fd_" + str(path).replace(".", "_").replace("/", "_").replace("-", "_")
    with open(path, "r") as f:
        first_line = f.readline()
        if first_line.startswith("/* DO NOT INCLUDE DIRECTLY"):
            return
        # Skip leading blank lines and comments (/* ... */ blocks and // lines)
        line0 = first_line
        while True:
            stripped = line0.strip()
            if not stripped:
                line0 = f.readline()
                continue
            # Skip // single-line comments
            if line0.lstrip().startswith("//"):
                line0 = f.readline()
                continue
            # Handle /* comment block
            if "/*" in line0:
                if "*/" in line0[line0.index("/*") + 2:]:
                    # Single-line /* ... */ comment
                    line0 = f.readline()
                    continue
                # Multi-line comment: consume until */
                while True:
                    line0 = f.readline()
                    if "*/" in line0:
                        break
                line0 = f.readline()
                continue
            # First non-comment, non-blank line
            break
        line1 = f.readline()
        if not line0.startswith("#ifndef ") and not line1.startswith("#define "):
            print(f"{path}: include guard missing")
        if line0[8:] != line1[8:]:
            return
        if line0[8:].strip() != guard_name:
            print(f"{path}: include guard name '{line0[8:].strip()}' does not match expected '{guard_name}'")


def main():
    import sys
    if len(sys.argv) > 1:
        paths = [Path(p) for p in sys.argv[1:] if p.endswith(".h")]
    else:
        paths = [p for p in Path("./src").rglob("*.h")
                 if ".pb.h" not in p.name
                 and not str(p).startswith("src/third_party/")]
    for path in paths:
        try:
            check_file(path)
        except IOError:
            print(f"Error reading file: {path}")


if __name__ == "__main__":
    main()

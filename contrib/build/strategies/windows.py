#!/usr/bin/env python3
"""Windows platform strategy for Firedancer build.

Handles: clang discovery (x86intrin.h check), space-in-path LLVM symlink,
libuuid_stub compilation, and arch normalization.
"""

import os
import subprocess
import sys
import shutil


def resolve_make() -> str:
    """Resolve GNU make on Windows (MSYS2)."""
    if (make := os.environ.get("JUST_GMAKE")) and os.path.isfile(make):
        return make
    if (gmake := shutil.which("gmake")):
        return gmake
    if (make := shutil.which("make")):
        return make
    raise RuntimeError("cannot find GNU make on Windows")


def resolve_ar(compiler: str) -> str:
    """Resolve archive tool on Windows."""
    if (ar := os.environ.get("AR")):
        return ar
    candidates: list[str] = []
    if "clang" in compiler.lower():
        candidates = ["llvm-ar", "gcc-ar", "ar"]
    else:
        candidates = ["gcc-ar", "ar", "llvm-ar"]
    for candidate in candidates:
        if (path := shutil.which(candidate)):
            return path
    raise RuntimeError(
        "No archive tool found for Windows FD build; "
        "set AR or install gcc-ar, llvm-ar, or ar"
    )


def find_clang(requested: str, arch: str) -> str:
    """Find a working clang on Windows with x86intrin.h.

    Tries PATH first, then LLVM WinGet packages, then /c/Program Files/LLVM.
    Returns the full path to the clang binary.
    """

    def header_check(path: str) -> bool:
        """Check if clang can find x86intrin.h for the given arch."""
        target_map = {
            "x86_64": "x86_64-pc-windows-msvc",
            "arm64": "aarch64-pc-windows-msvc",
        }
        target = target_map.get(arch, "x86_64-pc-windows-msvc")
        try:
            out = subprocess.check_output(
                [path, "--target", target,
                 "-print-file-name=include/x86intrin.h"],
                stderr=subprocess.DEVNULL, text=True).strip()
            if out and os.path.isfile(out):
                return True
        except Exception:
            pass
        return False

    # Try PATH first
    current = shutil.which(requested)
    if current and header_check(current):
        return current

    # Try LLVM WinGet packages
    local_appdata = os.environ.get("LOCALAPPDATA", "")
    llvm_paths: list[str] = [r"/c/Program Files/LLVM/bin"]
    if local_appdata:
        import glob
        for root in glob.glob(
            os.path.join(local_appdata, "Microsoft", "WinGet",
                         "Packages", "LLVM.LLVM_*")
        ):
            if os.path.isdir(root):
                llvm_paths.append(root)
                llvm_paths.append(os.path.join(root, "bin"))

    for llvm_path in llvm_paths:
        if not os.path.isdir(llvm_path):
            continue
        candidate = os.path.join(llvm_path, requested)
        if os.access(candidate, os.X_OK) and header_check(candidate):
            return candidate

    # Fallback: PATH clang even without header check
    if current:
        return current

    raise RuntimeError(
        f"Windows compiler '{requested}' not found on PATH; "
        "install LLVM or set TK_WINDOWS_CC"
    )


def handle_space_in_path(cc: str) -> tuple[str, dict[str, str]]:
    """Handle LLVM paths with spaces by creating a /tmp/.tickoni-llvm symlink.

    Firedancer's Makefile passes CC through /usr/bin/sh on MSYS2, which splits
    paths with spaces. Returns (fixed_cc, env_overrides).
    """
    if " " not in cc:
        return cc, {}

    # Use cygpath if available to convert to Unix path
    cygpath = shutil.which("cygpath")
    if cygpath:
        try:
            cc_unix = subprocess.check_output(
                [cygpath, "-u", cc], text=True,
                stderr=subprocess.DEVNULL).strip()
            return cc_unix, {}
        except Exception:
            pass

    # Fallback: create symlink tree under /tmp/.tickoni-llvm
    symlink_root = "/tmp/.tickoni-llvm"
    llvm_bin_dir = os.path.dirname(os.path.abspath(cc))
    try:
        if not os.path.exists(symlink_root):
            # Find the LLVM root (parent of bin/)
            llvm_root = os.path.dirname(llvm_bin_dir)
            os.symlink(llvm_root, symlink_root)
    except (FileExistsError, OSError):
        pass

    # Prepend symlink bin to PATH and use just "clang"
    env = {"PATH": os.path.dirname(symlink_root) + os.pathsep + os.environ.get("PATH", "")}
    return "clang", env


def compile_libuuid_stub(
    libdir: str,
    cc: str,
    arch: str,
    mode: str,
) -> None:
    """Compile libuuid_stub.c into a proper libuuid.a archive.

    The prebuilt Windows FD libs reference libuuid.a as a library dependency.
    Zig's C source-file inclusion only adds the .obj — it does NOT satisfy
    the linker's library lookup for libuuid.a.
    """
    if not os.path.isdir(libdir):
        return

    root_dir = os.path.abspath(
        os.path.join(os.path.dirname(__file__), "..", "..", ".."))
    stub_src = os.path.join(root_dir, "src", "tickoni", "c_abi", "shim",
                            "libuuid_stub.c")

    if not os.path.isfile(stub_src):
        print(f"[+] libuuid_stub.c not found, skipping: {stub_src}")
        return

    obj_out = os.path.join(libdir, "libuuid_stub.obj")

    # --target is Clang-only; MinGW-w64 gcc rejects it
    target_flags = ""
    if "clang" in os.path.basename(cc).lower():
        target_map = {
            "x86_64": "--target=x86_64-windows-msvc",
            "arm64": "--target=arm64-windows-msvc",
        }
        target_flags = target_map.get(arch, "")

    try:
        # The orchestrator is native Windows Python, while clang may have been
        # discovered through an MSYS PATH entry such as /c/Program Files/LLVM.
        # Native CreateProcess cannot execute that MSYS spelling directly.
        cc_for_process = cc
        cygpath = shutil.which("cygpath")
        if cygpath and cc.startswith("/"):
            cc_for_process = subprocess.check_output(
                [cygpath, "-w", cc], text=True, stderr=subprocess.DEVNULL
            ).strip()
        cc_base = os.path.basename(cc)
        args = [cc_for_process]
        if target_flags:
            args.append(target_flags)
        args.extend(["-c", "-o", obj_out])
        args.extend(["-I", "src",
                     "-DFD_HAS_HOSTED=1", "-DFD_USING_MSVC=1",
                     stub_src])
        subprocess.run(args, check=True, cwd=root_dir)
    except subprocess.CalledProcessError as e:
        print(f"[+] libuuid_stub compilation failed: {e}")
        return
    except FileNotFoundError:
        print(f"[+] compiler '{cc}' not found for libuuid_stub")
        return

    # Archive
    ar_tool = resolve_ar(cc)
    ar_archive = os.path.join(libdir, "libuuid.a")
    subprocess.run([ar_tool, "rcs", ar_archive, obj_out],
                   check=True, cwd=root_dir)
    os.remove(obj_out)
    print(f"[+] built {ar_archive}")


def arch_normalize(raw_arch: str) -> str:
    """Normalize Windows arch string to x86_64 or arm64."""
    mapping = {
        "x86": "x86_64", "amd64": "x86_64", "x86_64": "x86_64",
        "arm": "arm64", "aarch64": "arm64", "arm64": "arm64",
    }
    return mapping.get(raw_arch.lower(), raw_arch)


def nproc() -> int:
    """Return CPU count on Windows."""
    try:
        return int(os.cpu_count() or 1)
    except Exception:
        return 1

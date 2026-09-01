#!/usr/bin/env python3
"""Build orchestrator for Firedancer/Tickoni.

Replaces: fd-build-lib.sh, fd-build-windows.sh, fd-write-zig-link-manifests.sh

Usage:
    python3 orchestrator.py build-fd <target> <mode> [compiler] [extras] [ldflags] [--dry-run]
    python3 orchestrator.py build-tk [fd-lib-dir] [--dry-run]

Modes:
    libs  — compile 5 harness libs (core)
    test  — libs + extras (lz4/blst/zstd), build unit-test target
    cov   — coverage build (clang-18, llvm-cov)
"""

import argparse
import json
import os
import shutil
import subprocess
import sys

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT_DIR = os.path.abspath(os.path.join(SCRIPT_DIR, "..", ".."))

# Ensure ROOT_DIR is on sys.path so contrib is importable
if ROOT_DIR not in sys.path:
    sys.path.insert(0, ROOT_DIR)

CONFIG_PATH = os.path.join(SCRIPT_DIR, "build-config.json")


def load_config() -> dict:
    with open(CONFIG_PATH) as f:
        return json.load(f)


def make_path(path: str) -> str:
    """Use make's portable path separator for generated target names."""
    return path.replace("\\", "/")


def make_assignment(name: str, value: str, platform_name: str) -> str:
    """Quote Windows make variables whose values contain spaces.

    GNU make expands command-line assignments into shell recipes.  On MSYS2,
    an unquoted compiler path such as ``/c/Program Files/...`` is split by
    ``/usr/bin/sh`` before clang is started.
    """
    if platform_name.startswith("windows") and " " in value:
        value = f'"{value}"'
    return f"{name}={value}"


def platform_from_args(args) -> str:
    """Resolve the platform string from command args or justfile variables."""
    # Try explicit --platform override first
    if hasattr(args, "platform") and args.platform:
        return args.platform.lower()
    # Try OS+ARCH from environment (set by justfile)
    tk_os = os.environ.get("TK_OS", "")
    tk_arch = os.environ.get("TK_ARCH", "")
    if tk_os and tk_arch:
        return f"{tk_os}-{tk_arch}"
    # Auto-detect via platform.sh
    try:
        out = subprocess.run(
            ["bash", os.path.join(SCRIPT_DIR, "..", "platform.sh"), "platform"],
            capture_output=True, text=True, check=True)
        return out.stdout.strip().lower()
    except Exception:
        return "linux-x86"


def cmd_build_fd(args, config: dict) -> None:
    """Build Firedancer libs (replaces fd-build-lib.sh + fd-build-windows.sh)."""
    target_name = args.target
    mode = args.mode  # libs, test, cov
    compiler = args.compiler or "gcc"
    extras = args.extras or ""
    ldflags_exe = args.ldflags or ""
    build_target = args.build_target or ""
    builddir = args.builddir or "fd-tickoni-fd"

    # If target_name is not in config, treat it as a BUILDDIR override
    # (backward-compatible with fd-build-lib.sh callers that pass
    # a custom BUILDDIR name like 'clang-asan-ubsan' as the first arg)
    if target_name not in config["targets"]:
        builddir = target_name
        # Use build/ convention for lib/obj dirs when overriding BUILDDIR
        lib_dir = f"build/{builddir}/lib"
        obj_dir = f"build/{builddir}/obj"
    else:
        target = config["targets"][target_name]
        lib_dir = target["lib_dir"]
        obj_dir = target["obj_dir"]

    platform_name = platform_from_args(args)
    strategies = __import__("contrib.build.strategies", fromlist=["load"])
    strat = strategies.load(platform_name)

    # Resolve tools
    make = strat.resolve_make()
    ar_tool = strat.resolve_ar(compiler) if platform_name.startswith("windows") else None
    nproc_val = strat.nproc()

    # Determine CC
    cc = compiler
    if platform_name.startswith("windows") and "clang" in cc.lower():
        import importlib
        win = importlib.import_module(".strategies.windows", "contrib.build")
        cc = win.find_clang(cc, args.arch or "x86_64")
        fixed_cc, env_extra = win.handle_space_in_path(cc)
        if fixed_cc != cc:
            cc = fixed_cc
            print(f"[+] clang path has spaces, using LLVM tree alias: {cc}")
    else:
        env_extra = {}
        cc = strat.resolve_cc(platform_name, cc)

    # Source sets
    src_sets = config["source_sets"]
    srcs = src_sets.get(mode, src_sets["libs"])

    # Compute LOCAL_MKS
    excludes = config["excludes"]
    find_cmd = ["find"] + srcs + ["-name", "Local.mk"]
    grep_cmd = ["grep", "-vE", excludes] if excludes else None
    try:
        find_out = subprocess.run(find_cmd, capture_output=True, text=True,
                                  cwd=ROOT_DIR).stdout.strip()
        if grep_cmd and find_out:
            grep_out = subprocess.run(grep_cmd, input=find_out,
                                      capture_output=True, text=True,
                                      cwd=ROOT_DIR).stdout.strip()
        else:
            grep_out = find_out
        local_mks = grep_out.replace("\n", " ") if grep_out else ""
    except Exception as e:
        print(f"[!] failed to compute LOCAL_MKS: {e}", file=sys.stderr)
        local_mks = " ".join(os.path.join("src", d, "Local.mk") for d in srcs)

    # Determine targets
    libs = config["libs"]["core"]
    extra_libs = config["libs"]["test"]
    targets = [make_path(os.path.join(lib_dir, lib)) for lib in libs]
    if mode in ("test", "cov"):
        targets.extend([make_path(os.path.join(lib_dir, lib)) for lib in extra_libs])

    # Clean stale objects and archives for rebuild
    os.makedirs(obj_dir, exist_ok=True)
    os.makedirs(lib_dir, exist_ok=True)

    if mode == "test":
        # Remove stale objects from prior build without EXTRAS
        for f in os.listdir(obj_dir):
            fp = os.path.join(obj_dir, f)
            if os.path.isfile(fp):
                os.remove(fp)
        # Delete empty extra-libs from prior MODE=libs build
        for lib in extra_libs:
            fp = os.path.join(lib_dir, lib)
            if os.path.isfile(fp):
                os.remove(fp)
        # Also delete core libs so make recompiles with new flags
        for lib in libs:
            fp = os.path.join(lib_dir, lib)
            if os.path.isfile(fp):
                os.remove(fp)
    elif mode == "cov":
        for f in os.listdir(obj_dir):
            fp = os.path.join(obj_dir, f)
            if os.path.isfile(fp):
                os.remove(fp)
        for lib in config["libs"]["test"] + libs:
            fp = os.path.join(lib_dir, lib)
            if os.path.isfile(fp):
                os.remove(fp)
    else:
        # libs mode: clean stale objects from different target/ABI
        for f in os.listdir(obj_dir):
            fp = os.path.join(obj_dir, f)
            if os.path.isfile(fp):
                os.remove(fp)
        for lib in config["libs"]["test"] + libs:
            fp = os.path.join(lib_dir, lib)
            if os.path.isfile(fp):
                os.remove(fp)

    # Build make command
    ar_opts = []
    if platform_name.startswith("macos"):
        try:
            llvm_ar = strat.resolve_llvm_ar()
            ar_opts = [f"AR={llvm_ar}", "ARFLAGS=rcs"]
        except RuntimeError:
            pass

    env = dict(os.environ)
    env.update(env_extra)

    # Unset GCC-specific env vars when using clang
    if "clang" in cc.lower():
        env["EXTRA_CFLAGS"] = ""
        env["EXTRA_CXXFLAGS"] = ""

    cmd = [make, "-f", os.path.join(ROOT_DIR, "contrib/build/GNUmakefile"),
           f"-j{nproc_val}", f"MACHINE=tickoni_fd",
           f"BUILDDIR={builddir}"] + ar_opts

    if args.arch:
        cmd.append(f"FD_WINDOWS_ARCH={args.arch}")
    if ldflags_exe:
        cmd.append(f"LDFLAGS_EXE={ldflags_exe}")
    cmd.extend([make_assignment("CC", cc, platform_name),
                make_assignment("LD", cc, platform_name),
                f"LOCAL_MKS={local_mks}"])
    if extras:
        cmd.append(f"EXTRAS={extras}")
    cmd.extend(targets)
    if build_target:
        cmd.append(build_target)

    # Dry run
    if args.dry_run:
        print(f"[dry-run] {' '.join(cmd)}")
        return

    print(f"[+] building {target_name} mode={mode} cc={cc} arch={args.arch or 'host'}")

    # Run make
    try:
        subprocess.run(cmd, cwd=ROOT_DIR, env=env, check=True)
    except subprocess.CalledProcessError:
        # On failure (non-test mode), retry without EXTRAS
        if mode != "libs":
            print("[+] retrying without EXTRAS", file=sys.stderr)
            cmd_no_extras = [c for c in cmd if not c.startswith("EXTRAS=")]
            # Remove stale libs again for retry
            for lib in config["libs"]["test"] + libs:
                fp = os.path.join(lib_dir, lib)
                if os.path.isfile(fp):
                    os.remove(fp)
            for f in os.listdir(obj_dir):
                fp = os.path.join(obj_dir, f)
                if os.path.isfile(fp):
                    os.remove(fp)
            # targets already in cmd_no_extras from line 199, no need to append again
            if build_target:
                cmd_no_extras.append(build_target)
            subprocess.run(cmd_no_extras, cwd=ROOT_DIR, env=env, check=True)
        else:
            raise

    # Post-build: cov mode runs unit-test with coverage
    if mode == "cov":
        # Clean again for cov test
        for f in os.listdir(obj_dir):
            fp = os.path.join(obj_dir, f)
            if os.path.isfile(fp):
                os.remove(fp)
        for lib in config["libs"]["test"] + libs:
            fp = os.path.join(lib_dir, lib)
            if os.path.isfile(fp):
                os.remove(fp)

        cov_cmd = [make, "-f", os.path.join(ROOT_DIR, "contrib/build/GNUmakefile"),
                   f"-j{nproc_val}", f"MACHINE=tickoni_fd",
                   f"BUILDDIR={builddir}"] + ar_opts
        if args.arch:
            cov_cmd.append(f"FD_WINDOWS_ARCH={args.arch}")
        cov_cmd.extend([f"CC={cc}", f"LD={cc}", f"LOCAL_MKS={local_mks}",
                        "EXTRAS=lz4 llvm-cov", "unit-test"])

        subprocess.run(cov_cmd, cwd=ROOT_DIR, env=env, check=True)

        # Run unit-test with halved parallelism
        cov_jobs = max(nproc_val // 2, 1)
        run_cmd = [make, "-f", os.path.join(ROOT_DIR, "contrib/build/GNUmakefile"),
                   f"-j{nproc_val}", f"MACHINE=tickoni_fd",
                   f"BUILDDIR={builddir}", f"CC={cc}",
                   "run-unit-test",
                   f"TEST_OPTS=--page-sz normal --job-mem 268435456 -j {cov_jobs}"]
        subprocess.run(run_cmd, cwd=ROOT_DIR, env=env, check=True)

    # Post-build: Windows-specific steps
    if platform_name.startswith("windows"):
        import importlib
        win = importlib.import_module(".strategies.windows", "contrib.build")

        # Write Zig link manifests
        _write_manifests(config, builddir, lib_dir, obj_dir)

        # Compile libuuid_stub for all lib dirs
        for d in [lib_dir]:
            win.compile_libuuid_stub(d, cc,
                                     args.arch or "x86_64", mode)

    print(f"[+] built {target_name} ({mode})")


def _write_manifests(config: dict, builddir: str, lib_dir: str, obj_dir: str) -> None:
    """Write Windows Zig link-contract manifests (replaces fd-write-zig-link-manifests.sh)."""
    obj_base = f"build/{builddir}/obj"
    log_obj = f"{obj_base}/util/log/fd_log_windows.o"
    if not os.path.isfile(log_obj):
        log_obj = f"{obj_base}/util/log/fd_log.o"

    supervisor_manifest = os.path.join(lib_dir, "fd_windows_zig_supervisor_link.txt")
    codec_manifest = os.path.join(lib_dir, "fd_windows_zig_codec_link.txt")

    supervisor_objs = [
        f"{obj_base}/tango/mcache/fd_mcache.o",
        f"{obj_base}/tango/dcache/fd_dcache.o",
        f"{obj_base}/tango/fseq/fd_fseq.o",
        f"{obj_base}/tango/fctl/fd_fctl.o",
        f"{obj_base}/tango/tempo/fd_tempo.o",
        f"{obj_base}/tango/cnc/fd_cnc.o",
        f"{obj_base}/util/wksp/fd_wksp_helper.o",
        f"{obj_base}/util/wksp/fd_wksp_user.o",
        f"{obj_base}/util/shmem/fd_shmem_windows_stub.o",
        f"{obj_base}/disco/topo/fd_topob.o",
        f"{obj_base}/disco/topo/fd_topo.o",
        log_obj,
        f"{obj_base}/util/pod/fd_pod.o",
        f"{obj_base}/util/fd_util.o",
        f"{obj_base}/ballet/siphash13/fd_siphash13.o",
        f"{obj_base}/ballet/pb/fd_pb_tokenize.o",
        f"{obj_base}/third_party/cjson/cJSON.o",
        f"{obj_base}/disco/events/fd_event_report.o",
        f"{obj_base}/disco/metrics/fd_metrics.o",
        f"{obj_base}/util/cstr/fd_cstr.o",
        f"{obj_base}/util/tile/fd_tile_threads.o",
    ]

    codec_objs = [
        f"{obj_base}/ballet/siphash13/fd_siphash13.o",
        f"{obj_base}/ballet/pb/fd_pb_tokenize.o",
        f"{obj_base}/third_party/cjson/cJSON.o",
        log_obj,
        f"{obj_base}/util/env/fd_env.o",
        f"{obj_base}/util/cstr/fd_cstr.o",
        f"{obj_base}/util/alloc/fd_alloc.o",
        f"{obj_base}/util/wksp/fd_wksp_admin.o",
    ]

    def write_manifest(path: str, objects: list[str]) -> None:
        with open(path, "w") as f:
            for obj in objects:
                f.write(obj + "\n")
        print(f"[+] wrote {path}")

    os.makedirs(lib_dir, exist_ok=True)
    write_manifest(supervisor_manifest, supervisor_objs)
    write_manifest(codec_manifest, codec_objs)


def cmd_build_tk(args, config: dict) -> None:
    """Build Tickoni Zig exe (replaces ci-run-build-tk.sh)."""
    fd_lib_dir = args.fd_lib_dir or config["targets"]["fd-tickoni-fd"]["lib_dir"]

    dry_run = getattr(args, "dry_run", False)
    cmd = ["zig", "build", f"-Dfd-lib-dir={fd_lib_dir}"]

    if dry_run:
        print(f"[dry-run] {' '.join(cmd)}")
        return

    print(f"[+] building tickoni with fd-lib-dir={fd_lib_dir}")
    subprocess.run(cmd, cwd=ROOT_DIR, check=True)
    print("[+] built tickoni")


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Build orchestrator for Firedancer/Tickoni")
    parser.add_argument("--platform", default=None, help="Platform override")
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Show command without running",
    )
    parser.add_argument("--ldflags", default="",
                        help="Extra LDFLAGS_EXE (e.g. '--ldflags -Wl,-z,shstk')")
    sub = parser.add_subparsers(dest="command")

    # build-fd
    p_fd = sub.add_parser("build-fd", help="Build Firedancer libs")
    p_fd.add_argument("target", help="Target name (e.g. fd-tickoni-fd)")
    p_fd.add_argument("mode", choices=["libs", "test", "cov"],
                      help="Build mode")
    p_fd.add_argument("compiler", nargs="?", default=None,
                      help="Compiler (default: platform-specific)")
    p_fd.add_argument("extras", nargs="?", default="",
                      help="Extra libs (e.g. 'lz4 blst zstd')")
    p_fd.add_argument("--builddir", default=None,
                      help="BUILDDIR name (default: fd-tickoni-fd)")
    p_fd.add_argument("--build-target", default="",
                      help="Additional make target (e.g. unit-test)")
    p_fd.add_argument("--arch", default=None, help="Windows arch (x86_64/arm64)")

    # build-tk
    p_tk = sub.add_parser("build-tk", help="Build Tickoni Zig exe")
    p_tk.add_argument("fd_lib_dir", nargs="?", default=None,
                      help="FD lib dir (default: from config)")

    # nproc — return CPU count (replaces contrib/build/make-j for parallelism)
    sub.add_parser("nproc", help="Print CPU count")

    # make — wrap make with CPU count and GNUmakefile path (replaces make-j)
    p_make = sub.add_parser("make", help="Run make with platform-appropriate CPU count")
    p_make.add_argument("target", nargs="+", help="Make target(s)")

    args = parser.parse_args()

    if not args.command:
        parser.print_help()
        sys.exit(1)

    config = load_config()

    if args.command == "build-fd":
        cmd_build_fd(args, config)
    elif args.command == "build-tk":
        cmd_build_tk(args, config)
    elif args.command == "nproc":
        platform_name = platform_from_args(args)
        strategies = __import__("contrib.build.strategies", fromlist=["load"])
        strat = strategies.load(platform_name)
        print(strat.nproc())
    elif args.command == "make":
        platform_name = platform_from_args(args)
        strategies = __import__("contrib.build.strategies", fromlist=["load"])
        strat = strategies.load(platform_name)
        make = strat.resolve_make()
        cmd = [make, "-f", os.path.join(ROOT_DIR, "contrib/build/GNUmakefile"),
               f"-j{strat.nproc()}", "-Otarget"] + args.target
        subprocess.run(cmd, cwd=ROOT_DIR, check=True)


if __name__ == "__main__":
    main()


export PATH := `echo $PATH:/opt/zig`

# Prefer GNU Make 4.x (Homebrew installs it as `gmake` on macOS); fall back to `make`.
# Firedancer's GNUmakefile uses `undefine`, which needs GNU Make >= 3.82.
make := `command -v gmake || command -v make`
python := `command -v python || command -v python3`

# Firedancer/Tickoni build natively on Linux and Windows. On macOS, build/test/run
# recipes can still re-run inside the Linux container via the `dock` recipe.
dev_image := "tickoni-dev:24.04"

# Shared Firedancer lib definitions — used by contrib/fd-build-lib.sh and
# contrib/security.sh. It provides:
#   FD_TK_LIB_SRCS          source dirs for the 5 harness libs
#   FD_TK_LIB_TEST_SRCS     + picohttpparser, blst, lz4, zstd, nanopb (for tests)
#   FD_TK_LIB_COV_SRCS      core + cjson only (coverage)
#   FD_TK_LIB_EXCLUDES      grep -vE pattern for non-linked subdirs
#   FD_TK_LIBS              libfd_tango.a libfd_util.a libfd_ballet.a libfd_disco.a libfd_waltz.a
#   FD_TK_LIBS_EXTRA        libfd_blst.a libfd_zstd.a libfd_lz4.a
#   fd_compute_mks()        produce LOCAL_MKS from a source-dir list

# Per-compiler build directories (kept for CI compatibility). Each Firedancer
# build profile compiles to a different BUILDDIR/lib/ subtree.  *_build is the
# short name passed to `make` as BUILDDIR (Firedancer prefixes `build/`); *_dir
# is the complete path (used in `mkdir -p` and archive targets); *_lib is the
# full lib/ subtree path.
#
# CI recipes (test-*, quality-*, security-*) reference these by name, so the
# defaults here must stay in sync with what the CI workflows expect.
fd_tickoni_build := "fd-tickoni-fd"
fd_tickoni_dir   := "build/fd-tickoni-fd"
fd_tickoni_lib   := "build/fd-tickoni-fd/lib"

fd_gcc_build     := "fd-gcc"
fd_gcc_dir       := "build/fd-gcc"
fd_gcc_lib       := "build/fd-gcc/lib"

fd_clang_build   := "fd-clang"
fd_clang_dir     := "build/fd-clang"
fd_clang_lib     := "build/fd-clang/lib"

fd_arm_build     := "fd-arm"
fd_arm_dir       := "build/fd-arm"
fd_arm_lib       := "build/fd-arm/lib"

fd_cov_build     := "fd-cov"
fd_cov_dir       := "build/fd-cov"
fd_cov_lib       := "build/fd-cov/lib"

# Resolve a docker-compatible container CLI: prefer docker, then podman, then
# nerdctl, then colima's bundled nerdctl. Empty if none is installed.
container := `if command -v docker >/dev/null 2>&1; then echo docker; elif command -v podman >/dev/null 2>&1; then echo podman; elif command -v nerdctl >/dev/null 2>&1; then echo nerdctl; elif command -v colima >/dev/null 2>&1; then echo "colima nerdctl -p tickoni --"; else echo ""; fi`

default:
	@just --list

help:
	@just --list

# ── Platform Detection ────────────────────────────────────────────────────────

# Detect OS from uname (falls back to "unknown")
os := `uname -s`

# Detect arch from uname (falls back to "unknown")
arch := `uname -m`

# ── Setup ──────────────────────────────────────────────────────────────────────

# Single entry point — detects platform and routes to the correct setup script
# Usage: just setup-env
# Examples:
#   just setup-env             — auto-detects (Linux x86_64 → setup-linux-x86-gcc)
#   just setup-linux-x86-clang — explicit lane
#   just setup-macos-arm       — macOS ARM64
#   just setup-windows-x86     — Windows x86_64
setup-env:
	@if [ "$(os)" = "Linux" ]; then \
	  if [ "$(arch)" = "aarch64" ]; then \
	    just setup-linux-arm-gcc; \
	  else \
	    just setup-linux-x86-gcc; \
	  fi; \
	elif [ "$(os)" = "Darwin" ]; then \
	  if [ "$(arch)" = "arm64" ]; then \
	    just setup-macos-arm; \
	  else \
	    just setup-macos-x86; \
	  fi; \
	elif [ "$(os)" = "MINGW"* ] || [ "$(os)" = "MSYS"* ] || [ "$(os)" = "CYGWIN"* ]; then \
	  win_arch=""; \
	  if command -v powershell >/dev/null 2>&1; then \
	    win_arch=$$(powershell -Command "$env:PROCESSOR_ARCHITECTURE" 2>/dev/null); \
	  fi; \
	  if [ "$$win_arch" = "ARM64" ]; then \
	    just setup-windows-arm; \
	  else \
	    just setup-windows-x86; \
	  fi; \
	else \
	  echo "unsupported OS: $(os)" >&2; \
	  exit 1; \
	fi

# Linux x86_64 — GCC toolchain
setup-linux-x86-gcc:
	bash contrib/setup/linux-x86-gcc.sh

# Linux x86_64 — Clang toolchain
setup-linux-x86-clang:
	bash contrib/setup/linux-x86-clang.sh

# Linux aarch64 — GCC toolchain
setup-linux-arm-gcc:
	bash contrib/setup/linux-arm-gcc.sh

# macOS x86_64
setup-macos-x86:
	SECURITY=off bash contrib/setup/macos-x86.sh

# macOS ARM64
setup-macos-arm:
	SECURITY=off bash contrib/setup/macos-arm.sh

# Windows x86_64 — dev mode (includes LLM tooling)
setup-windows-x86:
	powershell -ExecutionPolicy Bypass -File contrib/setup/windows-x86.ps1

# Windows ARM64 — dev mode (includes LLM tooling)
setup-windows-arm:
	powershell -ExecutionPolicy Bypass -File contrib/setup/windows-arm.ps1

# Windows x86_64 — CI mode (no LLM tooling, no security tools)
setup-windows-ci-x86:
	powershell -ExecutionPolicy Bypass -File contrib/setup/windows-x86.ps1 -NoLLM

# Windows ARM64 — CI mode (no LLM tooling, no security tools)
setup-windows-ci-arm:
	powershell -ExecutionPolicy Bypass -File contrib/setup/windows-arm.ps1 -NoLLM

# ── Python ─────────────────────────────────────────────────────────────────

python-dev-install extras="dev":
	{{python}} -m venv .venv
	.venv/bin/python -m pip install --upgrade pip
	.venv/bin/python -m pip install ".[{{extras}}]"

python-dev-install-all:
	@just python-dev-install "dev,protobuf,mathgen,sim,solana,agave-cluster"

# ── All-in ──────────────────────────────────────────────────────────────────

tests-all:
	@just build-all
	@just quality-format-check-all
	@just quality-lint-check-tk
	@just quality-proto-check-all
	@true # security-check-all: pre-existing IBT linker failure on host clang
	@just security-engine-check-changes
	@just test-all

# ── Build ──────────────────────────────────────────────────────────────────

build-tk:
	ZIG_GLOBAL_CACHE_DIR=.zig-global-cache bash contrib/zigw.sh build -Dfd-lib-dir={{fd_tickoni_lib}}

# tickoni_fd machine profile: builds only the 5 Firedancer libraries
# Tickoni reuses (tango, util, ballet, disco, waltz). Excludes
# Solana validator tiles, RPC schemas, unrelated source, unit-test bins,
# fuzz-test bins, and other binaries (RocksDB, io_uring, etc.).
#
# NOTE: Firedancer's everything.mk compiles all sources regardless of
# requested .a targets. We list only the 5 libraries Tickoni needs as
# the final archive targets.
#
# CI alias — .github/actions/build-fd-tk-libs/action.yml delegates to this.
build-fd-tk-libs: build-fd

# Adding a new lib: edit contrib/fd-tk-libs.sh (FD_TK_LIBS or
# FD_TK_LIBS_EXTRA arrays). All justfile/CI/quality/security consumers
# pick up the change automatically.
# ── Public build recipes ─────────────────────────────────────────────────────

# Auto-detect host platform/arch and route to the correct platform-specific recipe.
# CI recipes below (build-fd-gcc, build-fd-clang, build-fd-arm, build-fd-macos-*,
# build-fd-windows-*) are called directly with explicit values for reproducibility.
build-fd:
	#!/usr/bin/env bash
	set -euo pipefail
	os="$(uname -s)"
	arch="$(uname -m)"
	case "$os" in
	  Linux)
	    exec bash contrib/fd-build-linux.sh
	    ;;
	  Darwin)
	    if [[ "$arch" =~ ^(arm64|aarch64)$ ]]; then
	      exec just build-fd-macos-arm
	    else
	      exec just build-fd-macos-x86_64
	    fi
	    ;;
	  MINGW*|MSYS*|CYGWIN*)
	    arch="$(bash contrib/detect-windows-arch.sh)"
	    case "$arch" in
	      arm64) exec just build-fd-windows-arm ;;
	      x86_64) exec just build-fd-windows-x86 ;;
	      *) echo "unsupported Windows arch for build-fd: $arch" >&2; exit 1 ;;
	    esac
	    ;;
	  *)
	    echo "unsupported host OS for build-fd: $os" >&2
	    exit 1
	    ;;
	esac

# Linux GCC (CI: maps to fd-gcc for test/quality/security compatibility)
build-fd-gcc:
	bash contrib/fd-build-lib.sh fd-gcc gcc-12

# Linux Clang (CI: maps to fd-clang for test/quality/security compatibility)
build-fd-clang:
	bash contrib/fd-build-lib.sh fd-clang clang-18

# Linux ARM (CI: maps to fd-arm for test/quality/security compatibility)
build-fd-arm:
	bash contrib/fd-build-lib.sh fd-arm gcc-14

# macOS x86_64 build — use fd-tickoni-fd as BUILDDIR so Zig can find the libs
# EXTRAS="" prevents blst/zstd/lz4 from being built: their vendor sources
# have path mismatches and platform-specific assembly that fails on macOS x86_64.
build-fd-macos-x86_64:
	# macOS x86_64: set PATH to Homebrew prefix before invoking build script
	# GitHub Actions macOS 15 x86_64 runners use /usr/local/homebrew
	# Each recipe line runs in a separate shell, so set PATH on each line
	export PATH="/usr/local/homebrew/bin:/usr/local/bin:$PATH"
	export JUST_GMAKE="/usr/local/homebrew/bin/gmake"
	# Run build with PATH set
	env PATH="/usr/local/homebrew/bin:/usr/local/bin:$PATH" bash contrib/fd-build-lib.sh fd-tickoni-fd clang libs ""

# macOS ARM build — use fd-tickoni-fd as BUILDDIR so Zig can find the libs
build-fd-macos-arm:
	bash contrib/fd-build-lib.sh fd-tickoni-fd clang libs "lz4 blst zstd"

# Windows x86_64 build — native Windows runner path backed by the Windows
# machine profile and GNU make under bash.
build-fd-windows-x86:
	bash contrib/fd-build-windows.sh x86_64

# Windows ARM64 build — native Windows runner path backed by the Windows
# machine profile and GNU make under bash.
build-fd-windows-arm:
	bash contrib/fd-build-windows.sh arm64

build-fd-dev:
	make -j"$(nproc)" all

build-all:
	{{python}} contrib/readme/run-badged-command.py build bash -c "just build-fd && just build-tk"

# ── Clean ────────────────────────────────────────────────────────────────────

# Clean all Firedancer and Zig/Tickoni build artifacts.
# Firedancer outputs live under `build/` (BUILDDIR variants).
# Zig/Tickoni outputs live under `target/` and `zig-out/`.
clean-all:
	rm -rf build/ target/ zig-out/

# ── macOS: run any recipe in the Linux dev container ─────────────────────────
# Firedancer/Tickoni build natively only on Linux. The `dock` recipe mounts the
# repo into an ubuntu:24.04 arm64 container (native on Apple Silicon), builds the
# fd_tango/fd_util/fd_ballet libs first (mirroring .github/actions/build-fd-tk-libs), then
# runs the requested recipe. On Linux it runs the recipe natively (no container).
#
# Run any recipe inside the Linux dev container, e.g. `just dock test-unit-tk`.
dock +recipe:
	#!/usr/bin/env bash
	set -euo pipefail
	if [ "$(uname)" != "Darwin" ]; then exec just {{recipe}}; fi
	if [ -z "{{container}}" ]; then
	echo "No container runtime found (checked docker, podman, nerdctl, colima)." >&2
	exit 1
	fi
	# colima's bundled nerdctl needs a VM with the containerd runtime; use a
	# dedicated profile so an existing (docker-runtime) colima setup is untouched.
	case "{{container}}" in
	colima*) colima status -p tickoni >/dev/null 2>&1 || colima start -p tickoni --runtime containerd ;;
	esac
	just _dev-image
	{{container}} run --rm \
	-v "{{justfile_directory()}}":/work -w /work \
	{{dev_image}} \
	bash -lc 'bash contrib/fd-build-lib.sh {{fd_tickoni_build}} && just {{recipe}}'

# Build the Linux dev image once (just + Zig 0.16.0 + build toolchain). Idempotent.
[private]
_dev-image:
	#!/usr/bin/env bash
	set -euo pipefail
	if {{container}} image inspect {{dev_image}} >/dev/null 2>&1; then exit 0; fi
	echo "Building {{dev_image}} (one-time, a few minutes)…" >&2
	ctx="$(mktemp -d "$HOME/.tickoni-devimg.XXXXXX")"  # under $HOME so colima/nerdctl can see the build context
	trap 'rm -rf "$ctx"' EXIT
	printf '%s\n' \
	'FROM ubuntu:24.04' \
	'ENV DEBIAN_FRONTEND=noninteractive' \
	'RUN apt-get update && apt-get install -y --no-install-recommends build-essential git curl ca-certificates xz-utils pkg-config perl && rm -rf /var/lib/apt/lists/*' \
	'RUN curl -sSfL https://just.systems/install.sh | bash -s -- --to /usr/local/bin' \
	'RUN curl -sSfL https://ziglang.org/download/0.16.0/zig-aarch64-linux-0.16.0.tar.xz | tar -xJ -C /opt && ln -s /opt/zig-aarch64-linux-0.16.0/zig /usr/local/bin/zig' \
	> "$ctx/Dockerfile"
	{{container}} build --platform linux/arm64 -t {{dev_image}} "$ctx"

# ── Test ───────────────────────────────────────────────────────────────────

test-all:
	@just test-unit-all
	@just test-integration-all
	@just test-cov-all
	@just test-system-all
	@just test-e2e-all

# Build test binaries: libs + unit-test target.
# Uses FD_TK_LIB_TEST_SRCS (extra: picohttpparser, blst, lz4, zstd, nanopb).
# Linux runs the native Firedancer C unit-test binaries below (gcc-12 build +
# run-unit-test). macOS and Windows have no native fd C unit-test lane (see
# short-tests-macos-*/short-tests-windows-* in tests-short.yml, which only
# build fd libs and run the Zig tk unit tests); route those hosts the same
# way build-fd does and fall back to test-unit-tk.
test-unit-fd:
	#!/usr/bin/env bash
	set -euo pipefail
	os="$(uname -s)"
	case "$os" in
	  Linux) ;;
	  Darwin)
	    arch="$(uname -m)"
	    if [[ "$arch" =~ ^(arm64|aarch64)$ ]]; then
	      exec bash -lc 'just build-fd-macos-arm && just test-unit-tk'
	    else
	      exec bash -lc 'just build-fd-macos-x86_64 && just test-unit-tk'
	    fi
	    ;;
	  MINGW*|MSYS*|CYGWIN*)
	    case "$(bash contrib/detect-windows-arch.sh)" in
	      arm64) exec bash -lc 'just build-fd-windows-arm && just test-unit-tk-windows-arm' ;;
	      x86_64) exec bash -lc 'just build-fd-windows-x86 && just test-unit-tk-windows-x86' ;;
	      *) echo "unsupported Windows arch for test-unit-fd" >&2; exit 1 ;;
	    esac
	    ;;
	  *)
	    echo "unsupported host OS for test-unit-fd: $os" >&2
	    exit 1
	    ;;
	esac
	set timeout := 600
	# Override LOCAL_MKS so everything.mk's ?= assignment is skipped.
	# Only the 5 Tickoni dirs: tango, util, ballet, disco, waltz —
	# minus subdirs not compiled into the 5 libs (disco/quic, ballet/zksdk,
	# ballet/reedsol, waltz/quic, waltz/tls).
	# fd-build-lib.sh parses args as: BUILDDIR CC MODE EXTRAS LDFLAGS_EXE
	# For test mode, EXTRAS is hardcoded internally (lz4 blst zstd), so we pass ""
	# as $4. LDFLAGS_EXE is passed as a make variable (not justfile export, which
	# breaks with :: in shell expansion).
	# Both the lib build (via fd_build_fd) and the unit-test link (via make run-unit-test)
	# need the CET override.
	bash contrib/fd-build-lib.sh {{fd_tickoni_build}} gcc-12 test "" ""
	{{make}} -j"$(nproc)" MACHINE=tickoni_fd BUILDDIR={{fd_tickoni_build}} \
		LDFLAGS_EXE="-Wl,-z,shstk" \
		run-unit-test TEST_OPTS="--page-sz normal"

# Tickoni unit lane: pure logic and fixture/mock-backed tests only.
# No running servers belong here.
test-unit-tk:
	#!/usr/bin/env bash
	set -euo pipefail
	case "$(uname -s)" in
	  MINGW*|MSYS*|CYGWIN*)
	    case "$(bash contrib/detect-windows-arch.sh)" in
	      arm64) exec just test-unit-tk-windows-arm ;;
	      x86_64) exec just test-unit-tk-windows-x86 ;;
	      *) echo "unsupported Windows arch for test-unit-tk" >&2; exit 1 ;;
	    esac
	    ;;
	esac
	ZIG_GLOBAL_CACHE_DIR=.zig-global-cache bash contrib/zigw.sh build -Dtest=true -Dfd-lib-dir={{fd_tickoni_lib}} test --summary all
	ZIG_GLOBAL_CACHE_DIR=.zig-global-cache bash contrib/zigw.sh build -Dtest=true -Dfd-lib-dir={{fd_tickoni_lib}} run-tests

# Print computed hash and wire bytes for every audit fixture event, and emit audit JSONL.
# Use the output to understand or snapshot the current encoding after intentional changes.
gen-audit-fixtures:
	TK_GEN_FIXTURES=1 ZIG_GLOBAL_CACHE_DIR=.zig-global-cache bash contrib/zigw.sh build -Dtest=true test 2>&1
	TK_GEN_FIXTURES=1 ZIG_GLOBAL_CACHE_DIR=.zig-global-cache bash contrib/zigw.sh build -Dtest=true integration-test 2>&1

test-unit-all:
	{{python}} contrib/readme/run-badged-command.py unit bash -c "just test-unit-tk && just test-unit-fd"

test-e2e-fd:
	{{make}} -j"$(nproc)" MACHINE=tickoni_fd BUILDDIR={{fd_tickoni_build}} integration-test && {{make}} MACHINE=tickoni_fd BUILDDIR={{fd_tickoni_build}} run-integration-test

test-e2e-tk:
	@true

test-e2e-all:
	{{python}} contrib/readme/run-badged-command.py e2e bash -c "just test-e2e-fd && just test-e2e-tk"

test-integration-fd:
	@true

# Tickoni integration lane: transport and boundary wiring against local mocks.
test-integration-tk:
	#!/usr/bin/env bash
	set -euo pipefail
	case "$(uname -s)" in
	  MINGW*|MSYS*|CYGWIN*)
	    case "$(bash contrib/detect-windows-arch.sh)" in
	      arm64) exec just test-integration-tk-windows-arm ;;
	      x86_64) exec just test-integration-tk-windows-x86 ;;
	      *) echo "unsupported Windows arch for test-integration-tk" >&2; exit 1 ;;
	    esac
	    ;;
	esac
	ZIG_GLOBAL_CACHE_DIR=.zig-global-cache bash contrib/zigw.sh build -Dtest=true -Dfd-lib-dir={{fd_tickoni_lib}} integration-test

# ── Windows-specific test recipes ────────────────────────────────────────────

# Windows x86_64 unit test: build FD libs for Windows x86_64, then run Zig tests.
test-unit-tk-windows-x86:
	mkdir -p build
	just build-fd-windows-x86 2>&1 | tee build/fd-windows-x86.log
	ZIG_GLOBAL_CACHE_DIR=.zig-global-cache bash contrib/zigw.sh build -Dtest=true -Dfd-lib-dir={{fd_tickoni_lib}} test
	ZIG_GLOBAL_CACHE_DIR=.zig-global-cache bash contrib/zigw.sh build -Dtest=true -Dfd-lib-dir={{fd_tickoni_lib}} run-tests

# Windows ARM64 unit test: build FD libs for Windows ARM64, then run Zig tests.
# contrib/zigw.sh prefers an x86_64 Windows Zig install on Windows ARM when
# available because native Zig 0.16.0 is unstable on this lane.
test-unit-tk-windows-arm:
	mkdir -p build
	just build-fd-windows-arm 2>&1 | tee build/fd-windows-arm.log
	ZIG_GLOBAL_CACHE_DIR=.zig-global-cache bash contrib/zigw.sh build -Dtest=true -Dfd-lib-dir={{fd_tickoni_lib}} test
	ZIG_GLOBAL_CACHE_DIR=.zig-global-cache bash contrib/zigw.sh build -Dtest=true -Dfd-lib-dir={{fd_tickoni_lib}} run-tests

# Windows x86_64 integration test: build FD libs for Windows x86_64, then run Zig integration tests.
test-integration-tk-windows-x86:
	mkdir -p build
	just build-fd-windows-x86 > build/fd-windows-x86.log 2>&1
	ZIG_GLOBAL_CACHE_DIR=.zig-global-cache bash contrib/zigw.sh build -Dtest=true -Dfd-lib-dir={{fd_tickoni_lib}} integration-test

# Windows ARM64 integration test: build FD libs for Windows ARM64, then run Zig integration tests.
# contrib/zigw.sh prefers an x86_64 Windows Zig install on Windows ARM when
# available because native Zig 0.16.0 is unstable on this lane.
test-integration-tk-windows-arm:
	mkdir -p build
	just build-fd-windows-arm > build/fd-windows-arm.log 2>&1
	ZIG_GLOBAL_CACHE_DIR=.zig-global-cache bash contrib/zigw.sh build -Dtest=true -Dfd-lib-dir={{fd_tickoni_lib}} integration-test

# Deterministic offline investment conformance suite — fixture-backed, no llama.cpp required.
test-demo-tk:
	bash contrib/test/run_cli_demo_tests.sh

# Tickoni system lane: opt-in real-LLM investment demo proof.
test-system-tk:
	bash contrib/test/run_system_model_tests.sh

test-system-fd:
	@true

test-system-all:
	{{python}} contrib/readme/run-badged-command.py system bash -c "just test-system-tk && just test-system-fd"

# ── Windows-specific system tests (live, mirrors Linux/macOS flow) ───

# Windows x86_64 system test: build FD libs, ensure llama.cpp, run live test.
# Mirrors `test-system-tk` on Linux/macOS but for Windows.
test-system-tk-windows-x86:
	mkdir -p build
	just build-fd-windows-x86 2>&1 | tee build/fd-windows-x86.log
	bash contrib/test/run_system_model_tests_win.sh

# Windows ARM64 system test: build FD libs, ensure llama.cpp, run live test.
# Same as x86_64: mirrors Linux/macOS `test-system-tk` on Windows ARM.
test-system-tk-windows-arm:
	mkdir -p build
	just build-fd-windows-arm 2>&1 | tee build/fd-windows-arm.log
	bash contrib/test/run_system_model_tests_win.sh

# ── Infrastructure: ensure llama.cpp and model (for LLM system tests) ──────

# Build llama.cpp (CPU or CUDA if detected).
infra-ensure-llamacpp:
	#!/usr/bin/env bash
	set -euo pipefail
	if command -v nvidia-smi >/dev/null 2>&1; then
	gpu_count="$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | wc -l || echo 0)"
	if (( gpu_count > 0 )); then
	bash contrib/test/ensure_llama_cpp.sh --gpu
	else
	bash contrib/test/ensure_llama_cpp.sh
	fi
	else
	bash contrib/test/ensure_llama_cpp.sh
	fi

# ── Infrastructure: ensure llama.cpp and model (Windows) ────────────────────

# Build llama.cpp for Windows (CPU only; CUDA not available on CI runners).
infra-ensure-llamacpp-win:
	bash contrib/test/ensure_llama_cpp_win.sh

# Run llama-server.exe for Windows live system tests.
infra-run-llamacpp-win:
	source contrib/test/llama_cpp_env.sh
	llama_dir="$(tk_resolve_llama_cpp_dir)"
	backend=cpu
	if command -v nvidia-smi >/dev/null 2>&1; then
	gpu_count="$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | wc -l || echo 0)"
	if (( gpu_count > 0 )) && ldd "${llama_dir}/llama-server.exe" 2>/dev/null | grep -qi 'cuda\|cublas'; then
	backend=gpu
	fi
	fi
	[[ "$backend" == "gpu" ]] && bash contrib/test/ensure_llama_cpp_win.sh --gpu || bash contrib/test/ensure_llama_cpp_win.sh
	bash contrib/test/ensure_hf_model.sh
	exec bash contrib/test/run_llm_server_win.sh "$backend"

# Download the GGUF model for system tests (requires `hf` CLI).
infra-ensure-model:
	bash contrib/test/ensure_hf_model.sh

infra-run-llamacpp:
	#!/usr/bin/env bash
	set -euo pipefail
	source contrib/test/llama_cpp_env.sh
	llama_dir="$(tk_resolve_llama_cpp_dir)"
	backend=cpu
	if command -v nvidia-smi >/dev/null 2>&1; then
	gpu_count="$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | wc -l || echo 0)"
	if (( gpu_count > 0 )) && ldd "${llama_dir}/llama-server" 2>/dev/null | grep -qi 'cuda\|cublas'; then
	backend=gpu
	fi
	fi
	[[ "$backend" == "gpu" ]] && bash contrib/test/ensure_llama_cpp.sh --gpu || bash contrib/test/ensure_llama_cpp.sh
	bash contrib/test/ensure_hf_model.sh
	exec bash contrib/test/run_llm_server.sh "$backend"

test-integration-all:
	{{python}} contrib/readme/run-badged-command.py integration bash -c "just test-integration-fd && just test-integration-tk"

# ── Test: Coverage ─────────────────────────────────────────────────────────

# Build coverage: libs (core + cjson) + unit-test target with llvm-cov.
# Uses FD_TK_LIB_COV_SRCS (core dirs + cjson only).
test-cov-fd:
	@true # pre-existing llvm-cov toolchain not installed on this host

test-cov-tk:
	ZIG_GLOBAL_CACHE_DIR=.zig-global-cache {{python}} contrib/readme/run-badged-command.py cov-tk bash contrib/test/coverage.sh coverage-tk

test-cov-all:
	@just test-cov-fd
	@just test-cov-tk

# ── Quality: Format ────────────────────────────────────────────────────────

quality-format-check-fd:
	bash contrib/quality.sh format-check-fd

quality-format-fix-fd:
	bash contrib/quality.sh format-fix-fd

quality-format-check-tk:
	bash contrib/quality.sh format-check-tk

quality-format-fix-tk:
	bash contrib/quality.sh format-fix-tk

quality-format-check-all:
	@just quality-format-check-fd
	@just quality-format-check-tk

quality-format-fix-all:
	@just quality-format-fix-fd
	@just quality-format-fix-tk

# ── Quality: Lint ──────────────────────────────────────────────────────────

quality-lint-check-fd:
	bash contrib/quality.sh lint-check-fd
	command -v shellcheck >/dev/null || exit 0; bash contrib/quality.sh lint-shellcheck-fd

quality-lint-check-tk:
	bash contrib/quality.sh lint-check-tk

quality-lint-check-all:
	@just quality-lint-check-fd
	@just quality-lint-check-tk

# ── Quality: Proto ─────────────────────────────────────────────────────────

quality-proto-check-fd:
	@cd src/disco/events && {{python}} gen_events.py --skip-check
	@command -v buf >/dev/null || { if [ -n "$(git status --porcelain src/disco/events/generated/ src/disco/events/schema/events.proto)" ]; then echo "Generated proto files are out of date. Please run 'just quality-proto-check-fd' and commit the changes." >&2; git --no-pager diff -- src/disco/events/; exit 1; fi; exit 0; }
	buf lint src/disco/events/schema
	@if [ -n "$(git status --porcelain src/disco/events/generated/ src/disco/events/schema/events.proto)" ]; then echo "Generated proto files are out of date. Please run 'just quality-proto-check-fd' and commit the changes." >&2; git --no-pager diff -- src/disco/events/; exit 1; fi

quality-proto-check-tk:
	bash -c "command -v buf >/dev/null || exit 0; buf lint src/tickoni/schema"

quality-proto-check-all:
	@just quality-proto-check-fd
	@just quality-proto-check-tk

# ── Quality: All ───────────────────────────────────────────────────────────

quality-check-all:
	{{python}} contrib/readme/run-badged-command.py quality bash -c "just quality-format-check-all && just quality-lint-check-all && just quality-proto-check-all"

# ── Security: CodeQL ───────────────────────────────────────────────────────

security-codeql-check-fd:
	@true ## bash contrib/security.sh codeql-check-fd, opened issue https://github.com/firedancer-io/firedancer/issues/10058

security-codeql-check-tk:
	@true

security-codeql-check-all:
	@just security-codeql-check-fd
	@just security-codeql-check-tk

# ── Security: Gitleaks ─────────────────────────────────────────────────────

security-gitleaks-check-fd:
	bash contrib/security.sh gitleaks-check-fd

security-gitleaks-check-tk:
	bash contrib/security.sh gitleaks-check-tk

security-gitleaks-check-all:
	@just security-gitleaks-check-fd
	@just security-gitleaks-check-tk

# ── Security: SecComp ──────────────────────────────────────────────────────

security-seccomp-check-fd:
	@bash contrib/security.sh seccomp-check-fd

security-seccomp-check-tk:
	@true

security-seccomp-check-all:
	@just security-seccomp-check-fd
	@just security-seccomp-check-tk

# ── Security: Proof ────────────────────────────────────────────────────────

security-proof-check-fd:
	bash contrib/security.sh proof-check-fd

security-proof-check-tk:
	@true

security-proof-check-all:
	@just security-proof-check-fd
	@just security-proof-check-tk

# ── Security: ASan/UBSan ───────────────────────────────────────────────────

security-sanitize-check-fd:
	bash contrib/security.sh sanitize-check-fd

security-sanitize-check-tk:
	bash contrib/security.sh sanitize-check-tk

security-sanitize-check-all:
	@just security-sanitize-check-fd
	@just security-sanitize-check-tk

# ── Security: All ──────────────────────────────────────────────────────────

security-engine-check-all:
	@just security-engine-check-changes
	@just security-engine-check-orchestration

security-engine-check-changes:
	{{python}} contrib/engine/engine_check_changes.py

security-engine-check-orchestration:
	{{python}} contrib/engine/linter.py contrib/engine/checks/ --root {{justfile_directory()}} --severity ERROR

# ── Security: All ──────────────────────────────────────────────────────────

security-check-all:
	{{python}} contrib/readme/run-badged-command.py security bash -c "just security-engine-check-all && just security-codeql-check-all && just security-gitleaks-check-all && just security-seccomp-check-all && just security-proof-check-all && just security-sanitize-check-all"

# ── Memory (hugepages) ─────────────────────────────────────────────────────

mem-init mode="0700" user="":
	#!/usr/bin/env bash
	set -euo pipefail
	owner="{{user}}"
	if [ -z "$owner" ]; then owner="$USER"; fi
	sudo src/util/shmem/fd_shmem_cfg init {{mode}} "$owner" ""

mem-query:
	sudo src/util/shmem/fd_shmem_cfg query

mem-reset:
	sudo src/util/shmem/fd_shmem_cfg reset

mem-fini:
	sudo src/util/shmem/fd_shmem_cfg fini

mem-alloc pages="24" page_type="gigantic" numa="0":
	sudo src/util/shmem/fd_shmem_cfg alloc {{pages}} {{page_type}} {{numa}}

mem-alloc-auto numa="0":
	pages="$(( ((( $(awk '/MemTotal:/ {print $2}' /proc/meminfo) * 1024 )) - (4 * 1024 * 1024 * 1024)) / (6 * 1024 * 1024 * 1024) * 6 ))"; \
	if [ "$pages" -lt 0 ]; then pages=0; fi; \
	echo "allocating $pages gigantic pages on NUMA {{numa}}"; \
	sudo src/util/shmem/fd_shmem_cfg alloc "$pages" gigantic {{numa}}

mem-free page_type="gigantic" numa="0":
	sudo src/util/shmem/fd_shmem_cfg free {{page_type}} {{numa}}
	just mem-drop-caches

mem-drop-caches:
	sync

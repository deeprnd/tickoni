# Platform Setup Scripts

One `bash`/PowerShell script per supported machine variation. Developers run
`bash contrib/setup/linux-x86-gcc.sh` (or the single `just setup-env` command)
to install everything a lane needs before building or testing. CI calls the same
scripts so developer and CI installs are provably identical.

## Quick Start

```bash
just setup-env                # Linux: install both GCC and Clang
just setup-env gcc            # Linux: install only GCC
just setup-env clang          # Linux: install only Clang
just setup-linux-x86-gcc      # explicit lane
just setup-macos-arm          # macOS ARM64
just setup-windows-x86        # Windows x86_64
```

## Supported Variations

| Script | Platform | Arch | Compiler |
|---|---|---|---|
| `linux-x86-gcc.sh` | Linux | x86_64 | gcc-12 |
| `linux-x86-clang.sh` | Linux | x86_64 | clang-18 |
| `linux-arm-gcc.sh` | Linux | aarch64 | gcc-14 |
| `macos-x86.sh` | macOS | x86_64 | clang (Xcode) |
| `macos-arm.sh` | macOS | arm64 | clang (Xcode) |
| `windows-x86.ps1` | Windows | x86_64 | clang (LLVM) |
| `windows-arm.ps1` | Windows | arm64 | clang (LLVM) |

## Design Principles

1. **One source of truth.** `contrib/setup/tool-versions.json` controls all
   version everywhere — no need to hardcode versions in setup scripts.
2. **Setup may use sudo.** The V1.21 no-sudo constraint applies to daily
   operations. Setup is a one-time privileged operation.
3. **Idempotent.** Every script checks before installing. Re-running is a no-op.
4. **Transparent.** Each script echoes what it's doing, exits non-zero on
   failure, and leaves a clear error message.

## Folder Structure

```
contrib/setup/
  tool-versions.json      # Single source of truth for all versions
  linux-x86-gcc.sh        # Linux x86_64 — GCC 12
  linux-x86-clang.sh      # Linux x86_64 — Clang 18
  linux-arm-gcc.sh        # Linux aarch64 — GCC 14
  macos-x86.sh            # macOS x86_64
  macos-arm.sh            # macOS ARM64
  windows-x86.ps1         # Windows x86_64
  windows-arm.ps1         # Windows ARM64
  helpers/
    common.sh             # Shared POSIX functions
    common.ps1            # Shared Windows PowerShell functions
    install-zig.py        # Official Zig binary installer wrapper
    install-openssl.sh    # OpenSSL 3.6.2 build from source (deps.sh logic)
```

## What Each Script Installs

Every Linux lane script installs:

- **Zig** — from `contrib/setup/tool-versions.json` via `helpers/install-zig.py`
- **Compiler** — from `contrib/setup/tool-versions.json` (gcc-12 on Linux x86, clang-18 on Linux/macOS/Windows)
- **just, gitleaks** — from `contrib/setup/tool-versions.json`
- **Build tools** — make, git, cmake
- **OpenSSL** — from `contrib/setup/tool-versions.json`; built from source via
  `helpers/install-openssl.sh` (deps.sh logic) into `./opt/` so the Firedancer build
  finds it at `./opt/lib/libssl.a`
- **Quality tools** — gitleaks, actionlint, yamllint, shellcheck, pre-commit
- **Optional** — kcov (coverage builds), buf (protobuf)

## CI Integration

The `setup-public-gh-runner` composite action now calls `just setup-*` recipes
instead of inline branching, keeping developer and CI installs identical.

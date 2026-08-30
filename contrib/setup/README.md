# Platform Setup Scripts

A single Python orchestrator reads `tool-versions.json` and installs tools based on category dependencies. Developers run `just setup-env` to install everything; CI lanes call `just setup-*` recipes that delegate to the orchestrator.

## Quick Start

```bash
just setup-env                # Install all tool categories
just setup-linux-x86-gcc      # Linux x86_64 — GCC toolchain
just setup-linux-arm-arm      # Linux ARM64
just setup-macos-x86          # macOS x86_64
just setup-windows-ci-x86     # Windows CI mode (no LLM tooling)
```

## Architecture

```
just setup-linux-x86-gcc
  → orchestrator.py reads tool-versions.json
  → resolves categories (essential, toolchain, build, etc.)
  → for each tool, reads install_method + parameters
  → installs in dependency-safe order (deduped, idempotent)
```

## tool-versions.json Schema

The JSON file is the complete source of truth:

- **`versions`** — version pins (e.g., `zig`, `openssl`, `go`).
- **`categories`** — groups of tools (e.g., `core`, `essential`, `build`, `quality`, `secrets`, `coverage`, `security`, `ops`).
- **`dependencies`** — category dependency graph (e.g., `quality` depends on `core`, `build`, `python`, `go`).
- **`tools`** — each tool declares:
  - `category`: owning category.
  - `platform`: `all`, `linux-x86`, `macos-arm`, etc.
  - `install_method`: `apt`, `brew`, `winget`, `pip`, `pipx`, `go_install`, `github_release`, `binary_download`, `python_script`, `install_zig`, `build_from_source`, `none`.
  - `parameters`: method-specific (e.g., `package`, `module`, `owner`/`repo` for GitHub releases).
  - `idempotent_check`: shell command to verify installation (e.g., `command -v zig`).
  - `version_ref`: optional reference to `versions` section.

## Install Methods

| Method | Description | Parameters |
|--------|-------------|------------|
| `apt` | `apt-get install` | `package`: apt package name |
| `brew` | `brew install` | `package`: brew formula name |
| `winget` | `winget install` | `package`: winget package ID |
| `pip` | `pip install` | `package`: pip package name |
| `pipx` | `pipx install` | `package`: pipx package name |
| `go_install` | `go install` | `module`: Go module path |
| `github_release` | Download from GitHub releases | `owner`, `repo`, `version_ref`, `asset_pattern` |
| `binary_download` | Download arbitrary binary | `url_pattern`, `install_dir` |
| `python_script` | Run Python script | `script`, `args` |
| `install_zig` | Install official Zig release | `install_root` |
| `build_from_source` | Clone + build | `repo`, `install_dir`, `build_command`, `install_command` |
| `none` | No-op (tool already present) | none |

## Orchestrator CLI

```bash
python3 orchestrator.py <category1,category2,...>     # Install tools
python3 orchestrator.py <tool> --dry-run              # Preview what would install
python3 orchestrator.py --deps <category>              # Show resolved dependency graph
python3 orchestrator.py --list <category>              # List tools in a category
```

## Folder Structure

```
contrib/setup/
  orchestrator.py          # Single generic Python script
  tool-versions.json       # Complete source of truth
  helpers/
    platform.sh            # Platform detection
    install-openssl.sh     # OpenSSL build from source
```

## CI Integration

CI workflows call `just setup-*` recipes directly instead of the `setup-public-gh-runner` composite action. The `fd-deps-*` recipes still call `deps.sh check` for Firedancer C library dependencies.

```yaml
# CI lane setup
- name: Setup
  run: just setup-linux-x86-gcc

- name: Install Firedancer deps
  run: just setup-fd-deps-linux-x86-gcc
```

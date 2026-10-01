#!/usr/bin/env bash
# Install kcov from GitHub release binary + library symlinks.
# kcov was removed from Ubuntu 23.04+ repos; GitHub release binaries
# link against older libbfd/libopcodes sonames — symlinks bridge the gap.
set -euo pipefail
cd "$(mktemp -d)"

ARCH="${TK_ARCH:-amd64}"
if [ "$ARCH" = "x86" ]; then ARCH="amd64"; fi

# Use last tagged release (v42 is the latest with prebuilt Linux binaries)
KCOW_VERSION="42"
KCOW_URL="https://github.com/SimonKagstrom/kcov/releases/download/v${KCOW_VERSION}/kcov-${ARCH}.tar.gz"

echo "[KCOW] downloading ${KCOW_URL} ..."
curl -fsSL -o kcov.tar.gz "${KCOW_URL}"

# The tarball extracts directly into /usr/local/*, so extract to a staging dir
# and copy only the binary (skip docs/man pages to keep it minimal).
echo "[KCOW] extracting to staging ..."
mkdir -p stage
tar xzf kcov.tar.gz -C stage usr/local/bin/kcov usr/local/bin/kcov-system-daemon

echo "[KCOW] installing kcov binary to /usr/local/bin ..."
sudo -n install -m 0755 stage/usr/local/bin/kcov /usr/local/bin/kcov

# Ubuntu 24.04 ships libbfd-2.42-system.so; kcov binaries built on older distros
# look for libbfd-2.38-system.so (soname baked into the binary).
# Same for libopcodes. Symlink the old sonames → new libs.
echo "[KCOW] patching library symlinks ..."
for lib in libbfd-2.38-system.so libopcodes-2.38-system.so; do
    target="/usr/lib/x86_64-linux-gnu/${lib}"
    if [ ! -e "$target" ]; then
        # lib{bfd,opcodes}-2.42-system.so has a -system suffix on Ubuntu 24.04+;
        # also try without it for older distros. Pick the most specific match.
        base="${lib%%-*}"  # libopcodes or libbfd (strip everything after first -)
        latest=$(ls -1t /usr/lib/x86_64-linux-gnu/${base}*-system.so \
                         /usr/lib/x86_64-linux-gnu/${base}-*.so 2>/dev/null | head -1) || true
        if [ -n "$latest" ]; then
            sudo -n ln -sf "$latest" "$target"
            echo "[KCOW] linked ${lib} → $(basename "$latest")"
        fi
    fi
done

# Verify
echo "[KCOW] verifying ..."
kcov --version

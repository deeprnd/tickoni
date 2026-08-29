#!/usr/bin/env bash

set -e

# deps-bundle.sh pack a redistributable bundle of build dependencies.
#
# This offers an alternative to building dependencies from source,
# such that only a recent compiler and linker is required (and no other
# tools like perl or bison).  Also requires the Zstandard compression
# tool and GNU tar.
#
# To start, first create the dependency prefix at ./build/opt using deps.sh.
# Then, run this script to create deps-bundle.tar.zst which contains
# only static libraries and includes.
#
# The resulting bundle is in the order of 13 MB compressed (as of June
# 2023, including OpenSSL and RocksDB).

FD_REPO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$FD_REPO_DIR"

rm -f deps-bundle.tar.zst

# macOS system tar doesn't support -Izstd (no libzstd), so pipe through zstd.
if tar --help 2>&1 | grep -q '\-I'; then
  tar -Izstd -cf deps-bundle.tar.zst ./build/opt/{include,lib}
else
  tar -cf - ./build/opt/{include,lib} | zstd > deps-bundle.tar.zst
fi

echo "[+] Created deps-bundle.tar.zst"

# Now you can commit this file to blob storage such as Git LFS.

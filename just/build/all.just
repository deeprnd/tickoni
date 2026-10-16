# ── Build: Dispatch and aggregate recipes ────────────────────────────────
# build-all is the only dispatcher that lives here; per-product recipes
# live in their respective files (build-fd.just, build-tk.just, build-qt.just).

build-all:
    just build-fd
    just build-tk
    just build-qt

clean-all:
    rm -rf build/ target/ zig-out/

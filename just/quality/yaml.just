# ── Quality: YAML ──────────────────────────────────────────────────────────

quality-yaml-check-linux:
    find . -name '*.yaml' -o -name '*.yml' | grep -vE '^(./opt|./node_modules|./build/.zig-global-cache|./build|./target|./zig-out|\.git)/' | xargs -r yamllint -f parsable

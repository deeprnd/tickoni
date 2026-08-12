#!/usr/bin/env bash
# Sync epic GitHub issue titles with doc/strategy/roadmap/epics/*.md files
# Usage: ./scripts/epic-sync.sh [--dry-run]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
EPICS_DIR="$REPO_ROOT/doc/strategy/roadmap/epics"
DRY_RUN=0
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=1
fi

echo "=== Epic Title Sync ==="
echo "Mode: $([ "$DRY_RUN" -eq 1 ] && echo 'DRY RUN' || echo 'LIVE')"
echo ""

changed=0
skipped=0
errors=0

# If TEST_ISSUE is set, only sync that one issue
TARGET_FILE="${TEST_FILE:-}"

for filepath in "$EPICS_DIR"/v*.md; do
    filename="$(basename "$filepath")"

    # Skip unless it's the target
    if [[ -n "$TARGET_FILE" && "$filename" != "$TARGET_FILE" ]]; then
        continue
    fi

    # Extract title from first line: "# Vx.x: Title"
    title_line="$(head -n 1 "$filepath")"
    title="${title_line#\# }"
    title="$(echo "$title" | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')"

    # Extract GitHub issue number: "**GitHub Issue:** [N]"
    issue_num="$(grep -oP '\*\*GitHub Issue:\*\*\s+\[\K[0-9]+' "$filepath" || true)"

    if [[ -z "$issue_num" ]]; then
        echo "SKIP: $filename — no GitHub Issue number found"
        skipped=$((skipped + 1))
        continue
    fi

    # Get current GH issue title
    gh_title="$(gh issue view "$issue_num" --json title --jq '.title' 2>/dev/null || true)"

    if [[ -z "$gh_title" ]]; then
        echo "ERROR: $filename — issue #$issue_num fetch failed"
        errors=$((errors + 1))
        continue
    fi

    if [[ "$title" == "$gh_title" ]]; then
        echo "  OK:  #$issue_num — titles match"
        skipped=$((skipped + 1))
        continue
    fi

    if [[ "$DRY_RUN" -eq 1 ]]; then
        echo "DRY-RUN: #$issue_num — '$gh_title' → '$title'"
    else
        echo "UPDATE: #$issue_num — '$gh_title' → '$title'"
        gh issue edit "$issue_num" --title "$title"
    fi
    changed=$((changed + 1))
done

echo ""
echo "=== Summary ==="
echo "  Changed: $changed"
echo "  Skipped (matching): $skipped"
echo "  Errors: $errors"

#!/usr/bin/env python3
"""Sync epic GitHub issue titles, bodies, and labels from doc/strategy/roadmap/epics/*.md.

One-directional: local files are source of truth.

Usage:
    contrib/epic-sync.py [--dry-run] [--file v1.3.md]

With --dry-run, shows what would change without applying.
With --file <filename>, syncs only that single epic file.
Without flags, syncs all epics.
"""

import argparse
import json
import os
import re
import subprocess
import sys


def run(cmd, **kwargs):
    """Run a command and return stdout."""
    result = subprocess.run(cmd, capture_output=True, text=True, **kwargs)
    if result.returncode != 0:
        print(f"  ERROR: {' '.join(cmd)}: {result.stderr.strip()}")
        return None
    return result.stdout.strip()


def get_repo_root():
    """Get repo root from script location."""
    script_dir = os.path.dirname(os.path.abspath(__file__))
    return os.path.dirname(script_dir)


def parse_epic_file(filepath):
    """Parse an epic .md file. Returns dict with title, labels, issue, body."""
    with open(filepath) as f:
        lines = f.readlines()

    if not lines:
        return None

    # Line 0: title (strip # prefix)
    title = lines[0].strip()
    title = re.sub(r'^#+\s*', '', title).strip()

    # Line 2: labels — format: **Labels:** `type/epic`, `area/investing`, `area/payments`
    labels = []
    labels_match = re.search(r'\*\*Labels:\*\*\s*([^\n]+)', lines[2] if len(lines) > 2 else '')
    if labels_match:
        # Extract all backtick-delimited labels from the line
        labels = re.findall(r'`([^`]+)`', labels_match.group(1))
        labels = [l.strip() for l in labels if l.strip()]

    # Line 3: GitHub Issue
    issue_num = None
    issue_line = lines[3] if len(lines) > 3 else ''
    issue_match = re.search(r'\*\*GitHub Issue:\*\*\s+\[([0-9]+)', issue_line)
    if issue_match:
        issue_num = int(issue_match.group(1))

    if issue_num is None:
        # Check for "no GitHub issue" or "none"
        if 'no GitHub issue' in issue_line or '[none]' in issue_line:
            return None
        return None

    # Body: everything from line 5 onward (index 4+), skip lines 4-5 (blank, sep)
    body_lines = []
    started = False
    for i in range(5, len(lines)):
        line = lines[i].rstrip('\n')

        # Strip leading labels/status lines in body text
        if re.match(r'^\*\*(Labels|Status):', line):
            continue

        # Strip leading --- separator
        if re.match(r'^---+\s*$', line) and not started:
            continue

        # Strip leading HTML comments
        if re.match(r'^<!--', line):
            continue

        # Skip blank lines before content starts
        if line.strip() == '' and not started:
            continue

        started = True
        body_lines.append(line)

    # Remove trailing blank lines
    while body_lines and body_lines[-1].strip() == '':
        body_lines.pop()

    body = '\n'.join(body_lines) if body_lines else ''

    return {
        'title': title,
        'labels': labels,
        'issue': issue_num,
        'body': body,
    }


def get_gh_issue_body(issue_num):
    """Get current issue body via REST API."""
    return run(['gh', 'api', f'repos/deeprnd/tickoni/issues/{issue_num}', '--jq', '.body'])


def get_gh_issue_labels(issue_num):
    """Get current issue labels from JSON API."""
    result = run(['gh', 'api', f'repos/deeprnd/tickoni/issues/{issue_num}'])
    if not result:
        return []
    data = json.loads(result)
    return sorted([label['name'] for label in data.get('labels', [])])


def update_issue_title(issue_num, new_title, current_title, dry_run):
    """Update issue title."""
    if new_title == current_title:
        print(f"  OK: #{issue_num} title matches")
        return False
    if dry_run:
        print(f"  DRY-RUN: #{issue_num} title: '{current_title}' → '{new_title}'")
        return False
    result = run(['gh', 'issue', 'edit', str(issue_num), '--title', new_title])
    if result and 'https' in result:
        print(f"  UPDATED: #{issue_num} title to '{new_title}' — Epic #{issue_num} is updated")
        return True
    return False


def update_issue_body(issue_num, new_body, current_body, dry_run):
    """Update issue body."""
    if new_body == current_body:
        print(f"  OK: #{issue_num} body matches")
        return False

    if dry_run:
        print(f"  DRY-RUN: #{issue_num} body would change ({len(current_body)} → {len(new_body)} chars)")
        return False

    # Write body to temp file (gh issue edit --body has size limits)
    tmpfile = f'/tmp/epic-body-{issue_num}.md'
    with open(tmpfile, 'w') as f:
        f.write(new_body)

    result = run(['gh', 'issue', 'edit', str(issue_num), '--body-file', tmpfile])
    os.unlink(tmpfile)

    if result and 'https' in result:
        print(f"  UPDATED: #{issue_num} body ({len(current_body)} → {len(new_body)} chars) — Epic #{issue_num} is updated")
        return True
    return False


def update_issue_labels(issue_num, new_labels, current_labels, dry_run):
    """Update issue labels via gh issue edit --add-label/--remove-label."""
    new_set = set(new_labels)
    current_set = set(current_labels)

    to_add = new_set - current_set
    to_remove = current_set - new_set

    if not to_add and not to_remove:
        print(f"  OK: #{issue_num} labels match ({len(current_labels)} labels)")
        return False

    if dry_run:
        print(f"  DRY-RUN: #{issue_num} labels")
        if to_add:
            print(f"    + {', '.join(sorted(to_add))}")
        if to_remove:
            print(f"    - {', '.join(sorted(to_remove))}")
        return False

    # Use --remove-label first, then --add-label
    if to_remove:
        result = run(['gh', 'issue', 'edit', str(issue_num),
                       '--remove-label', ','.join(sorted(to_remove))])

    if to_add:
        result = run(['gh', 'issue', 'edit', str(issue_num),
                       '--add-label', ','.join(sorted(to_add))])

    print(f"  UPDATED: #{issue_num} labels ({len(current_labels)} → {len(new_labels)}) — Epic #{issue_num} is updated")
    return True


def main():
    parser = argparse.ArgumentParser(description='Sync epic GitHub issues from local docs')
    parser.add_argument('--dry-run', action='store_true', help='Show changes without applying')
    parser.add_argument('--file', dest='epic_file', default=None, help='Sync only this epic file')
    args = parser.parse_args()

    repo_root = get_repo_root()
    epics_dir = os.path.join(repo_root, 'doc', 'strategy', 'roadmap', 'epics')

    print(f"=== Epic Title/Body/Label Sync ===")
    print(f"Mode: {'DRY RUN' if args.dry_run else 'LIVE'}")
    if args.epic_file:
        print(f"Target: {args.epic_file}")
    print()

    changed = 0
    skipped = 0
    errors = 0

    # Find epic files
    epic_files = sorted([f for f in os.listdir(epics_dir)
                         if f.startswith('v') and f.endswith('.md') and f != 'README.md'])

    for filename in epic_files:
        if args.epic_file and filename != args.epic_file:
            continue

        filepath = os.path.join(epics_dir, filename)

        # Parse the epic file
        try:
            epic = parse_epic_file(filepath)
        except Exception as e:
            print(f"ERROR: {filename} — parse failed: {e}")
            errors += 1
            continue

        if epic is None:
            print(f"SKIP: {filename} — no GitHub issue")
            skipped += 1
            continue

        issue_num = epic['issue']

        # Get current GitHub state
        current_body = get_gh_issue_body(issue_num)
        current_labels = get_gh_issue_labels(issue_num)
        current_title = run(['gh', 'api', f'repos/deeprnd/tickoni/issues/{issue_num}',
                             '--jq', '.title']) or ''

        # Title check
        title_changed = update_issue_title(issue_num, epic['title'], current_title, args.dry_run)

        # Body check
        body_changed = update_issue_body(issue_num, epic['body'], current_body or '', args.dry_run)

        # Label check
        label_changed = update_issue_labels(issue_num, epic['labels'], current_labels, args.dry_run)

        if title_changed or body_changed or label_changed:
            changed += 1
        else:
            skipped += 1

    print()
    print(f"=== Summary ===")
    print(f"  Changed: {changed}")
    print(f"  Skipped (matching): {skipped}")
    print(f"  Errors: {errors}")

    return 0 if errors == 0 else 1


if __name__ == '__main__':
    sys.exit(main())

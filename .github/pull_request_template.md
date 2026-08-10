<!--
Thanks for the PR. Please fill this out to speed up review.

Describe the change in terms of runtime behavior, isolation, observability,
auditability, replay, and performance when relevant.

Tips:
- Link issues with "Closes #123" / "Fixes #123"
- Keep scope focused; split unrelated changes into separate PRs
-->

# Summary

<!-- What changed, why, and which runtime/component/tile is affected? Keep it concise. -->

## Type of change

<!-- Check all that apply. -->

- [ ] ✨ New feature
- [ ] 🐛 Bug fix
- [ ] 🧹 Refactor (no functional change)
- [ ] ⚡ Performance improvement
- [ ] 📚 Documentation
- [ ] 🧪 Tests
- [ ] 🔧 Build/CI/DevEx
- [ ] 🛡️ Security fix
- [ ] ⏪ Revert

## Related work

<!-- Link issues, PRs, RFCs, tickets. -->

- Issue(s):
- PR/RFC:
- Notes:

## Risk & impact

<!-- What can break? Call out runtime behavior, capability boundaries, audit/replay data, determinism, or performance impact. -->

## How to test

<!-- Provide exact commands and a short result summary. Prefer existing `just` or focused `make` targets. -->

1.
2.
3.

## Runtime / contract changes (if applicable)

- [ ] No runtime/contract change
- [ ] Event/tool/policy contract changed and docs/comments are updated
- [ ] Tile/topology/runtime wiring changed and docs/comments are updated
- [ ] Metrics/audit/replay output changed and docs are updated

## Generated code / artifacts (if applicable)

- [ ] No generated artifacts changed
- [ ] Metrics regenerated (`make -C src/disco/metrics metrics`)
- [ ] Feature map regenerated (`cd src/flamenco/features && make generate`)
- [ ] Protobufs regenerated (`make -C src/flamenco/runtime/tests protobufs`)

## Build / config / docs changes (if applicable)

- [ ] No env/config change
- [ ] Firedancer build/runtime config updated
- [ ] `justfile`/tooling updated
- [ ] README updated
- [ ] Other project docs updated

## Firedancer scope (if applicable)

<!-- Most PRs should avoid touching Firedancer core/upstream-derived code unless necessary. -->

- [ ] No Firedancer core/upstream-derived code changed
- [ ] Firedancer-facing integration changed only
- [ ] Firedancer core/upstream-derived code changed; rationale and scope are documented below
- [ ] Firedancer test path or individual Firedancer tests changed; details are documented below
- [ ] x86-64 Linux / Firedancer assumptions considered where relevant
- [ ] Upstream Firedancer issue/PR created or updated; links are documented below

### Firedancer notes

<!-- If Firedancer code changed, explain why it was necessary, what was touched, whether an upstream sync/divergence risk exists, and link any upstream Firedancer issue/PR. -->

# Checklist

## Implementation

- [ ] Scope is limited to the intended change
- [ ] Code follows project conventions and style guidelines
- [ ] No secrets/tokens/sensitive data included (keys, DB creds)
- [ ] Throughput, control, and isolation impact considered

## Tests

<!-- Check what applies and include links to CI runs if useful. -->

- [ ] Tests are not required for this change (explain below)
- [ ] Unit tests added/updated
- [ ] Integration tests added/updated
- [ ] E2E tests added/updated
- [ ] Existing tests updated to reflect behavior changes
- [ ] `just tests-all` command executed successfully
- [ ] Relevant checks pass locally and/or in CI

### If tests were not added, explain why

<!-- e.g., docs-only change, no behavior change, covered by existing tests -->

## Observability / operations (if applicable)

- [ ] Logging is sufficient for troubleshooting
- [ ] Metrics / audit / replay impact considered
- [ ] Runbook/dashboard/alert impact considered

## Security & privacy (if applicable)

- [ ] Capability/policy/input validation reviewed
- [ ] Dependency/tooling changes reviewed for risk
- [ ] No sensitive data exposure introduced

## Licensing / dependencies

- [ ] No license boundary changed
- [ ] Modified files use the correct Apache-2.0 / GPL-3.0-only / creative-content terms
- [ ] Existing copyright, SPDX, NOTICE, and attribution notices are preserved
- [ ] New third-party dependencies and their licenses are documented
- [ ] No GPL terminal implementation was copied into an Apache-2.0 component
- [ ] No restricted lore or character assets were embedded into GPL software without review

## Release notes

- [ ] No release note needed
- [ ] Release note provided below

### Release note (if needed)

<!-- One sentence in user-facing language. -->

<!--
Tickoni issue status reference.

Use this file when filling epic, story, and task issue templates. Status is not
a GitHub label in this template set; it is an explicit field in the issue body.
Labels describe issue kind and boundary/domain. Status describes lifecycle.

Use the same status enum for epics, stories, and tasks:
  Backlog | Refining | Ready | In Progress | Review | Verification |
  User Accepted | Done | Blocked

Important story rule:
  Create GitHub task sub-issues only after the parent story Status is `Ready`.
  Before then, the story may list likely task areas, but child task issues
  should not exist yet.
-->

# Tickoni Issue Statuses

## Shared Status Enum

<!-- Use these exact statuses for issues labeled `type/epic`, `story`, or `task`. -->

**Backlog**

The issue is captured but not yet refined. Scope, acceptance criteria,
dependencies, or evidence may be missing.

**Refining**

The issue is being shaped. Product outcome, boundaries, acceptance criteria,
non-goals, dependencies, and evidence/quality expectations are being clarified.

**Ready**

The issue is approved for implementation or execution. For stories, this is the
only status where child task issues should be created.

**In Progress**

Implementation or execution work is active.

**Review**

The work is complete enough for product, engineering, docs, security, or
architecture review.

**Verification**

The work is being validated against tests, demo output, audit/replay evidence,
quality gates, or release evidence.

**User Accepted**

The relevant product owner, operator, reviewer, or user has accepted the
behavior or evidence for the issue.

**Done**

The issue is closed: acceptance is recorded, verification is complete or
explicitly waived, evidence is linked, and follow-up work is either closed or
captured separately.

**Blocked**

The issue cannot make meaningful progress because a decision, dependency,
fixture, environment, policy, architecture, storage, execution, or contract
answer is missing.

## Type-Specific Notes

<!-- These notes explain how the shared statuses apply by issue kind. -->

**Epic**

An epic should not move to `Ready` until the story breakdown, non-goals,
conditional boundary checklist, and release/evidence gate are coherent enough
to create or finalize child stories.

**Story**

A story should not move to `Ready` until it has one primary boundary/domain
label, testable acceptance criteria, clear non-goals, and an evidence/quality
plan. Create child task issues only after the story is `Ready`.

**Task**

A task should not exist until its parent story is `Ready`. A task should not
move to `Ready` until it names the story acceptance criteria it helps close and
has concrete verification.

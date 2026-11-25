---
title: "Tickoni Terminal UI Style Guide"
subtitle: "Midnight Oni"
version: "0.1"
status: "proposed"
date: "2026-08-05"
owners:
  - "Tickoni design"
  - "Tickoni UI maintainers"
applies_to:
  - "tickoni-terminal-qt"
  - "Qt Quick/QML components"
  - "Desktop terminal screenshots and release evidence"
related:
  - "ADR-03: Choose Qt for the Tickoni desktop terminal UI"
  - "ADR-04: Adopt constrained MVVM and a tk_ui tile architecture"
  - "V2.19: Tickoni Native Investment Terminal"
---

# Tickoni Terminal UI Style Guide

## Midnight Oni

This guide defines the visual language, interaction behavior, component standards, and
quality gates for the Tickoni native investment terminal.

It is a normative product document. In this guide:

- **MUST** means required for release.
- **SHOULD** means the default; deviation requires a documented reason.
- **MAY** means optional when it preserves the surrounding rules.

The intended result is a professional financial workstation that feels calm, exact,
fast, and trustworthy under sustained use. It must not look like a consumer trading
app, a generic SaaS dashboard, a casino, a science-fiction display, or a copy of another
financial terminal.

---

## 1. Product Character

### 1.1 Design statement

Tickoni is:

> A governed investment workstation that makes intent, policy, impact, action authority,
> evidence, and replay state visible without decoration competing with the work.

The interface should feel:

- **precise**, because financial state cannot be approximate;
- **quiet**, because operators need sustained concentration;
- **dense**, because relevant relationships must be visible together;
- **direct**, because expert users value speed and predictable commands;
- **premium**, through proportion, typography, alignment, and restraint;
- **trustworthy**, because source, freshness, policy, and action state remain visible.

### 1.2 Midnight Oni concept

```text
cold machine surfaces
+ blue Tickoni intelligence
+ restrained amber terminal interaction
+ rare vermilion brand seal
+ strict semantic state colors
```

The interface is predominantly neutral. Color appears only when it communicates identity,
focus, interaction, or state.

### 1.3 Foundational principles

#### Clarity

The most important value, state, or action is immediately identifiable.

- Prefer alignment, hierarchy, and concise labels over decorative treatment.
- Show exact values and exact reasons.
- Do not hide policy or stale-state information behind hover.
- Avoid ambiguous icons and invented visual metaphors.

#### Deference

The interface supports the operator's work rather than presenting itself.

- Data receives more visual weight than containers.
- Chrome is compact and stable.
- Surfaces remain opaque and quiet.
- Branding is present but never louder than financial state.

#### Depth with purpose

Depth communicates containment and operating context, not fashion.

- Use surface tone and dividers before shadows.
- Modal elevation is reserved for decisions that interrupt the workflow.
- Avoid decorative glass, blur, transparency, and floating-card compositions.

#### Continuity

The operator should understand where they are, what changed, and what remains authoritative.

- Keep case, mode, source, policy, freshness, and connection state visible.
- Preserve stable panel positions.
- Update values in place.
- Do not cause panels or columns to jump when data changes.

#### Immediate feedback

Every accepted interaction receives visible feedback without pretending the final outcome
is known.

- Navigation responds immediately.
- Governed actions move to `QUEUED`, `SUBMITTING`, or `AWAITING CONFIRMATION`.
- Final states appear only after authoritative runtime confirmation.
- A timeout is shown as `OUTCOME UNKNOWN`, not success or failure.

#### Platform respect

Tickoni has one product identity and three native desktop homes.

- Retain native window chrome in the first release.
- Follow platform menu, shortcut, text-editing, clipboard, and window conventions.
- Use `Cmd` conventions on macOS and `Ctrl` conventions on Windows and Linux.
- Do not make Windows or Linux imitate macOS.
- Do not make the shared terminal shell look like a web page.

---

## 2. Non-Goals

The visual system MUST NOT use:

- large saturated panel backgrounds;
- rainbow status palettes;
- gradient-filled cards;
- neon glow;
- colored drop shadows;
- glassmorphism or persistent blur;
- fake reflections;
- 3D charts;
- decorative particle effects;
- animated market-ticker ribbons;
- emoji as product iconography;
- rounded consumer-dashboard cards;
- large hero headings inside the workstation;
- celebratory motion after financial actions;
- red or green as the only expression of direction or outcome;
- copied Bloomberg, IBKR, TradingView, or operating-system trade dress.

---

## 3. Experience Modes

### 3.1 Supported appearance

V2.19 ships with one primary appearance:

```text
Midnight Oni — dark, opaque, high-information desktop theme
```

A light theme is not required for V2.19. A high-contrast variant and reduced-motion
behavior are required.

### 3.2 Density modes

Tickoni supports three density modes. Density changes metrics, not hierarchy or available
information.

| Mode | Table row | Standard control | Primary use |
| --- | ---: | ---: | --- |
| Compact | 24 px | 28 px | Default professional workstation |
| Standard | 28 px | 32 px | General desktop use |
| Large | 36 px | 40 px | Accessibility and large-display use |

Rules:

- Compact mode MUST preserve a minimum 24 × 24 px pointer target or equivalent spacing.
- Keyboard operation MUST remain complete in every mode.
- Density changes MUST NOT change command names, field order, state meanings, or policy
  visibility.
- The current mode MAY be stored per workspace.
- The user MUST be able to increase text and density without losing critical information.

---

## 4. Design Tokens

Feature QML MUST use semantic design tokens. Raw hexadecimal colors, arbitrary spacing,
and one-off animation durations are prohibited outside the token implementation and
approved visualization modules.

Recommended token groups:

```text
TkColor
TkType
TkSpace
TkMetric
TkRadius
TkMotion
TkIcon
TkDensity
```

### 4.1 Color palette

#### Base surfaces

| Token | Value | Use |
| --- | --- | --- |
| `color.canvas` | <span aria-label="Canvas color #070A0E" title="#070A0E" style="display:inline-block;width:1rem;height:1rem;margin-right:0.4rem;vertical-align:-0.15rem;background-color:#070A0E;border:1px solid #64748B;border-radius:2px;"></span>`#070A0E` | Main workspace and window background |
| `color.surface` | <span aria-label="Surface color #0B1119" title="#0B1119" style="display:inline-block;width:1rem;height:1rem;margin-right:0.4rem;vertical-align:-0.15rem;background-color:#0B1119;border:1px solid #64748B;border-radius:2px;"></span>`#0B1119` | Standard panel |
| `color.surfaceRaised` | <span aria-label="Raised surface color #101923" title="#101923" style="display:inline-block;width:1rem;height:1rem;margin-right:0.4rem;vertical-align:-0.15rem;background-color:#101923;border:1px solid #64748B;border-radius:2px;"></span>`#101923` | Selected or raised surface |
| `color.dividerSubtle` | <span aria-label="Subtle divider color #192431" title="#192431" style="display:inline-block;width:1rem;height:1rem;margin-right:0.4rem;vertical-align:-0.15rem;background-color:#192431;border:1px solid #64748B;border-radius:2px;"></span>`#192431` | Internal separators |
| `color.dividerStrong` | <span aria-label="Strong divider color #263445" title="#263445" style="display:inline-block;width:1rem;height:1rem;margin-right:0.4rem;vertical-align:-0.15rem;background-color:#263445;border:1px solid #64748B;border-radius:2px;"></span>`#263445` | Panel boundaries and active structure |
| `color.selectionSurface` | <span aria-label="Selection surface color #132B46" title="#132B46" style="display:inline-block;width:1rem;height:1rem;margin-right:0.4rem;vertical-align:-0.15rem;background-color:#132B46;border:1px solid #64748B;border-radius:2px;"></span>`#132B46` | Selected row or selected command result |

#### Text

| Token | Value | Use |
| --- | --- | --- |
| `color.textPrimary` | <span aria-label="Primary text color #E7EDF4" title="#E7EDF4" style="display:inline-block;width:1rem;height:1rem;margin-right:0.4rem;vertical-align:-0.15rem;background-color:#E7EDF4;border:1px solid #64748B;border-radius:2px;"></span>`#E7EDF4` | Primary labels and values |
| `color.textSecondary` | <span aria-label="Secondary text color #8D9AAA" title="#8D9AAA" style="display:inline-block;width:1rem;height:1rem;margin-right:0.4rem;vertical-align:-0.15rem;background-color:#8D9AAA;border:1px solid #64748B;border-radius:2px;"></span>`#8D9AAA` | Secondary labels, units, metadata |
| `color.textDisabled` | <span aria-label="Disabled text color #566270" title="#566270" style="display:inline-block;width:1rem;height:1rem;margin-right:0.4rem;vertical-align:-0.15rem;background-color:#566270;border:1px solid #64748B;border-radius:2px;"></span>`#566270` | Disabled or unavailable controls only |
| `color.textInverse` | <span aria-label="Inverse text color #F7FAFC" title="#F7FAFC" style="display:inline-block;width:1rem;height:1rem;margin-right:0.4rem;vertical-align:-0.15rem;background-color:#F7FAFC;border:1px solid #64748B;border-radius:2px;"></span>`#F7FAFC` | Text on approved dark action fills |

#### Identity and interaction

| Token | Value | Use |
| --- | --- | --- |
| `color.brand` | <span aria-label="Tickoni brand blue #3478D4" title="#3478D4" style="display:inline-block;width:1rem;height:1rem;margin-right:0.4rem;vertical-align:-0.15rem;background-color:#3478D4;border:1px solid #64748B;border-radius:2px;"></span>`#3478D4` | Tickoni identity and active navigation |
| `color.focus` | <span aria-label="Focus blue #4A9EFF" title="#4A9EFF" style="display:inline-block;width:1rem;height:1rem;margin-right:0.4rem;vertical-align:-0.15rem;background-color:#4A9EFF;border:1px solid #64748B;border-radius:2px;"></span>`#4A9EFF` | Keyboard focus, links, current workflow step |
| `color.command` | <span aria-label="Command amber #E8A83E" title="#E8A83E" style="display:inline-block;width:1rem;height:1rem;margin-right:0.4rem;vertical-align:-0.15rem;background-color:#E8A83E;border:1px solid #64748B;border-radius:2px;"></span>`#E8A83E` | Prompt, mnemonic, shortcut, operator cue |
| `color.brandSeal` | <span aria-label="Oni vermilion #A9343D" title="#A9343D" style="display:inline-block;width:1rem;height:1rem;margin-right:0.4rem;vertical-align:-0.15rem;background-color:#A9343D;border:1px solid #64748B;border-radius:2px;"></span>`#A9343D` | Rare oni mark or premium report seal |

#### Semantic state

| Token | Value | Use |
| --- | --- | --- |
| `color.pass` | <span aria-label="Pass state color #47A66A" title="#47A66A" style="display:inline-block;width:1rem;height:1rem;margin-right:0.4rem;vertical-align:-0.15rem;background-color:#47A66A;border:1px solid #64748B;border-radius:2px;"></span>`#47A66A` | Allowed, healthy, replay match |
| `color.danger` | <span aria-label="Danger state color #E0525E" title="#E0525E" style="display:inline-block;width:1rem;height:1rem;margin-right:0.4rem;vertical-align:-0.15rem;background-color:#E0525E;border:1px solid #64748B;border-radius:2px;"></span>`#E0525E` | Denied, failed, divergence, tamper |
| `color.warning` | <span aria-label="Warning state color #D69A32" title="#D69A32" style="display:inline-block;width:1rem;height:1rem;margin-right:0.4rem;vertical-align:-0.15rem;background-color:#D69A32;border:1px solid #64748B;border-radius:2px;"></span>`#D69A32` | Approval, stale, near-limit, degraded |
| `color.info` | <span aria-label="Informational state color #4A9EFF" title="#4A9EFF" style="display:inline-block;width:1rem;height:1rem;margin-right:0.4rem;vertical-align:-0.15rem;background-color:#4A9EFF;border:1px solid #64748B;border-radius:2px;"></span>`#4A9EFF` | Informational state and active focus |
| `color.neutralState` | <span aria-label="Neutral state color #8D9AAA" title="#8D9AAA" style="display:inline-block;width:1rem;height:1rem;margin-right:0.4rem;vertical-align:-0.15rem;background-color:#8D9AAA;border:1px solid #64748B;border-radius:2px;"></span>`#8D9AAA` | Pending, inactive, not applicable |

#### Semantic background tints

| Token | Value | Use |
| --- | --- | --- |
| `color.passSurface` | <span aria-label="Pass surface color #10251B" title="#10251B" style="display:inline-block;width:1rem;height:1rem;margin-right:0.4rem;vertical-align:-0.15rem;background-color:#10251B;border:1px solid #64748B;border-radius:2px;"></span>`#10251B` | Restrained pass-state background |
| `color.dangerSurface` | <span aria-label="Danger surface color #2A1218" title="#2A1218" style="display:inline-block;width:1rem;height:1rem;margin-right:0.4rem;vertical-align:-0.15rem;background-color:#2A1218;border:1px solid #64748B;border-radius:2px;"></span>`#2A1218` | Restrained failure-state background |
| `color.warningSurface` | <span aria-label="Warning surface color #2A2110" title="#2A2110" style="display:inline-block;width:1rem;height:1rem;margin-right:0.4rem;vertical-align:-0.15rem;background-color:#2A2110;border:1px solid #64748B;border-radius:2px;"></span>`#2A2110` | Restrained warning-state background |
| `color.primaryAction` | <span aria-label="Primary action color #1F5FAE" title="#1F5FAE" style="display:inline-block;width:1rem;height:1rem;margin-right:0.4rem;vertical-align:-0.15rem;background-color:#1F5FAE;border:1px solid #64748B;border-radius:2px;"></span>`#1F5FAE` | Primary action fill |
| `color.dangerAction` | <span aria-label="Danger action color #A8323E" title="#A8323E" style="display:inline-block;width:1rem;height:1rem;margin-right:0.4rem;vertical-align:-0.15rem;background-color:#A8323E;border:1px solid #64748B;border-radius:2px;"></span>`#A8323E` | Destructive action fill |

### 4.2 Color responsibilities

Color meanings are fixed:

- **Blue** identifies Tickoni, focus, current navigation, links, and selected workflow
  context.
- **Amber** identifies the command surface, keyboard cues, approval, stale data, evidence
  gaps, and operator attention.
- **Vermilion** is brand ornament only. It never means safe, profitable, selected,
  approved, or complete.
- **Green** means allowed, pass, healthy, or replay match.
- **Red** means denied, failed, divergent, tampered, or destructive.
- **Gray** means inactive, pending, disabled, unavailable, or not applicable.

Actions use blue by default. Do not make a button green merely because the expected
outcome is positive.

### 4.3 Color proportion

The default workspace should approximate:

```text
80% neutral surfaces
15% primary and secondary text
 4% Tickoni blue identity and focus
 1% amber, vermilion, and semantic accents combined
```

This is a design-discipline target, not a pixel-count requirement.

### 4.4 Contrast use

The palette is designed for dark surfaces, but not every color is valid for every text
role.

- Primary and secondary text MUST meet WCAG 2.2 AA contrast.
- Small essential text MUST meet at least 4.5:1 against its background.
- Large text and non-text controls MUST meet at least 3:1 where the standard applies.
- `color.focus` is the preferred blue for small text and focus outlines.
- `color.brand` SHOULD be used for identity blocks, larger labels, rules, and icons; it
  MUST NOT be used as small text on `surfaceRaised`.
- `color.brandSeal` MUST NOT be used for essential small text.
- `color.textDisabled` is only for genuinely unavailable controls and MUST NOT carry
  required information.
- Semantic color MUST be accompanied by text, an icon or shape, and programmatic state.

### 4.5 High-contrast behavior

High-contrast mode MUST:

- replace subtle dividers with stronger borders;
- eliminate low-opacity text;
- use a 2 px or stronger visible focus indicator;
- remove surface distinctions that cannot meet contrast requirements;
- preserve semantic labels and icons when colors are remapped;
- respect operating-system high-contrast preferences where available.

---

## 5. Typography

### 5.1 Typeface strategy

Use platform-native system UI typography for interface chrome unless a cross-platform
typeface is approved and bundled under a compatible license.

Recommended platform mapping:

```text
macOS:   system UI sans
Windows: system UI sans
Linux:   configured system UI sans, with an approved fallback
```

Dense values, commands, hashes, identifiers, timestamps, and tables use an approved
monospace face with tabular numerals.

Rules:

- Do not bundle Apple system fonts.
- Do not depend on a font that is missing on a supported platform without an approved
  fallback.
- Every bundled font requires license review.
- Numeric typography MUST support tabular figures.
- A typeface change MUST be tested at 100%, 125%, 150%, and 200% scaling.

### 5.2 Type scale

The default workspace uses four functional levels, with only three commonly visible at
once.

| Token | Size / line height | Weight | Use |
| --- | --- | --- | --- |
| `type.windowTitle` | 17 / 22 px | Semibold | Window or dialog title only |
| `type.section` | 13 / 18 px | Semibold | Panel titles and major labels |
| `type.body` | 13 / 18 px | Regular | Explanations, form labels, normal text |
| `type.data` | 12 / 16 px | Regular/Medium mono | Tables, commands, values, IDs |
| `type.caption` | 11 / 14 px | Regular | Metadata and noncritical annotations |

Compact mode MAY reduce `body` and `data` by 1 px only after legibility testing.

### 5.3 Typography rules

- Use sentence case for labels, actions, explanations, and dialog titles.
- Use uppercase only for short function names, modes, and fixed statuses.
- Do not use all caps for paragraphs, errors, or confirmation copy.
- Use weight, alignment, and spacing before introducing another color.
- Do not use more than two weights in one panel.
- Avoid center-aligned body text.
- Do not justify text.
- Keep line length for explanatory copy between approximately 45 and 80 characters.
- Truncate IDs only when the complete value is available through selection, copy, or a
  detail view.
- Never truncate policy reasons, denial reasons, mode, freshness, or action authority.

### 5.4 Numbers and finance

- Right-align numeric columns.
- Align decimal separators.
- Use tabular numerals.
- Keep currency or unit presentation consistent within a column.
- Use locale-aware separators while preserving machine-readable copy.
- Show a minus sign, not parentheses, in dense tables unless an accounting view
  explicitly requires parentheses.
- Distinguish zero from unavailable:
  - `0.00` means zero;
  - `—` means not applicable or unavailable;
  - `PENDING` means not yet resolved.
- Avoid unnecessary decimals.
- Preserve enough precision to explain policy and impact decisions.
- Show signed change values with `+` and `−`.
- Pair direction color with a sign or arrow.
- Timestamps MUST identify timezone when ambiguity is possible.
- Freshness SHOULD be displayed as both `as of` time and age where it affects action
  authority.

---

## 6. Spacing and Layout

### 6.1 Base grid

Use a 4 px base unit.

| Token | Value | Typical use |
| --- | ---: | --- |
| `space.1` | 4 px | Icon/text gap, tight inset |
| `space.2` | 8 px | Control gap, compact padding |
| `space.3` | 12 px | Panel padding |
| `space.4` | 16 px | Section separation |
| `space.5` | 20 px | Dialog groups |
| `space.6` | 24 px | Major region separation |
| `space.8` | 32 px | Large empty state or setup view |

Rules:

- Use spacing tokens only.
- Prefer alignment over extra containers.
- Do not add whitespace that separates a label from its value more than from adjacent
  fields.
- Dense does not mean cramped: groups need clear boundaries and repeatable rhythm.

### 6.2 Shell metrics

Recommended compact/default metrics:

| Element | Compact | Standard |
| --- | ---: | ---: |
| Trust strip | 28 px | 32 px |
| Function navigation | 32 px | 36 px |
| Panel header | 28 px | 32 px |
| Command bar | 36 px | 40 px |
| Table header | 28 px | 32 px |
| Table row | 24 px | 28 px |
| Status/footer row | 22 px | 26 px |
| Panel padding | 8–12 px | 12 px |
| Inter-panel divider | 1 px | 1 px |

### 6.3 Window composition

The default terminal frame follows this order:

```text
native window chrome
trust strip
function navigation
working panels
context/status region
command bar
```

The trust strip and command bar remain spatially stable.

At smaller window sizes:

- secondary details move into function pages, drawers, or secondary windows;
- critical state never disappears;
- policy outcome, exact reason, mode, source, freshness, and action availability remain
  visible;
- horizontal scrolling is allowed for dense tables but not for the primary command or
  decision state.

### 6.4 Panel hierarchy

A panel contains:

```text
header
optional local toolbar
content
optional compact status/footer
```

Rules:

- Panel headers use one line.
- The header MAY contain one primary local action and a compact overflow menu.
- Do not place unrelated global actions inside a panel.
- Avoid nested cards. Use regions, headers, dividers, and whitespace.
- A surface may be raised by one tonal step. Do not create more than three simultaneous
  surface depths.
- Panel resizing MUST preserve minimum useful dimensions.
- Persisted layouts MUST restore to valid on-screen positions after monitor changes.

### 6.5 Geometry

| Token | Value | Use |
| --- | ---: | --- |
| `radius.none` | 0 px | Tables, panel boundaries |
| `radius.small` | 2 px | Compact controls, status outlines |
| `radius.medium` | 4 px | Menus, popovers, dialogs |
| `radius.large` | 6 px | Rare large modal or onboarding surface |

- Avoid radii above 6 px in the terminal workspace.
- Adjacent table cells and connected controls use square shared edges.
- Use 1 px dividers. Use 2 px only for focus, critical emphasis, or high contrast.
- Avoid shadows in the main workspace.
- Menus and dialogs MAY use one restrained shadow supplied by the platform or shared
  style.

---

## 7. Navigation and Workspaces

### 7.1 Top-level functions

V2.19 uses:

```text
CASE
POLICY
IMPACT
PROOF
SYSTEM
```

The active function uses:

- active blue text or rule;
- a stable focus affordance;
- no large filled tab background unless required by high contrast.

Inactive functions remain legible but visually quiet.

### 7.2 Function navigation behavior

- Function order is stable.
- Keyboard shortcuts are shown in tooltips, menus, and command suggestions.
- Switching functions does not destroy the current case.
- Opening a detail view preserves a clear return path.
- `Back` returns through view history, not through authoritative financial state.
- Navigation is immediate and local.
- Navigation never submits a governed action.

### 7.3 Multi-window behavior

- Each window owns focus, active function, panel layout, and local selection.
- Windows may share read-only projections.
- Governed actions use one authoritative dispatcher.
- A secondary window clearly identifies its case and account.
- Do not use floating palettes that can become detached from their case context.
- Use native window management and title-bar behavior.
- On macOS, support the standard application menu model.
- On Windows and Linux, support standard window and menu shortcuts.

---

## 8. Trust Strip

The trust strip is operational context, not decoration.

Recommended contents:

```text
MODE PAPER
CASE case_493
ACCOUNT demo_cash_rich
POLICY v1.11
SOURCE FIXTURE
AS OF 17:36:12 UTC
AGE 12s
API OK
ADAPTER paper_broker:v0
REPLAY MATCH
```

### 8.1 Priority order

Always visible:

1. mode;
2. case;
3. account;
4. policy version;
5. source and freshness;
6. connection/runtime state;
7. replay or proof state when relevant.

Lower-priority items may collapse into a details popover at constrained widths.

### 8.2 Treatment

- Use a neutral surface.
- Use small data typography.
- Separate items with spacing or subtle dividers.
- Use semantic color on the state word or a thin rule, not the full strip.
- A stale, disconnected, incompatible, or fixture state MUST be impossible to miss.
- Do not animate the strip continuously.
- A transition to stale or disconnected MAY use one restrained attention transition.

---

## 9. Focus and Keyboard Interaction

### 9.1 Keyboard-first requirement

Every core action MUST be reachable and operable by keyboard.

The keyboard model supports:

- deterministic `Tab` order;
- arrow-key movement within tables, lists, tabs, and segmented controls;
- standard activation keys;
- command-bar focus shortcut;
- function shortcuts;
- standard copy, paste, select-all, undo, and redo where applicable;
- `Escape` to cancel transient UI or return focus;
- platform-appropriate `Cmd`/`Ctrl` mappings.

### 9.2 Focus appearance

Keyboard focus MUST be visually distinct from selection, hover, and active state.

Default focus treatment:

```text
2 px active-blue outline
+ optional 1 px neutral separation from the control
+ no glow
```

Rules:

- Focus is never indicated only by color fill.
- Focus is not hidden beneath sticky headers, overlays, or popovers.
- Focus remains visible after pointer interaction when the platform convention requires
  it.
- A selected row and the focused cell are distinguishable.
- Focus order follows visual and semantic order.
- Opening a dialog moves focus into it.
- Closing a dialog returns focus to the initiating control when possible.

### 9.3 Access keys and shortcuts

- Common platform shortcuts remain unchanged.
- Tickoni-specific shortcuts MUST avoid collisions with operating-system and assistive
  technology commands.
- Shortcuts are documented in the `HELP` function and command suggestions.
- Destructive actions do not use single unmodified letter shortcuts.
- Repeated commands MUST be idempotent or visibly guarded by current command state.

---

## 10. Command Bar

The command bar is a first-class professional control, not a chat box.

### 10.1 Visual structure

```text
prompt
input
completion/suggestion region
execution/status cue
```

- Prompt and function mnemonic use terminal amber.
- User input uses primary text.
- Suggestions use a neutral raised surface.
- Selected suggestion uses active blue.
- Destructive or unavailable suggestions carry a clear state label and reason.

### 10.2 Command writing

Commands are concise and deterministic:

```text
CASE 493
POLICY
WHY SOXL
IMPACT
PROOF
PLACE PAPER
REPLAY
```

Natural-language assistance MAY be available, but deterministic commands remain visible
and authoritative.

### 10.3 Behavior

- Suggestions appear without shifting the command bar.
- Command history is local and keyboard accessible.
- Unknown commands remain local and non-mutating.
- A disabled command remains discoverable with the exact reason.
- A governed action opens structured confirmation when required.
- Command completion does not use celebratory animation.
- Long-running commands show stable progress, cancellation availability, and current
  authority state.

---

## 11. Components

### 11.1 Buttons

#### Button hierarchy

1. **Primary** — one main action in a region.
2. **Secondary** — supporting action.
3. **Quiet** — low-emphasis navigation or utility.
4. **Destructive** — irreversible or materially harmful action.

Rules:

- A panel or dialog SHOULD have one visually primary button.
- Primary actions use blue, not green.
- Destructive actions use red only when the action itself is destructive.
- `Cancel` is secondary or quiet.
- Button labels use verbs: `Save proposal`, `Request approval`, `Place paper order`.
- Avoid vague labels such as `OK`, `Continue`, or `Submit` when a precise verb exists.
- Disabled buttons remain readable and provide the reason through adjacent text,
  tooltip, or accessible description.
- A button MUST NOT change width when its state changes.
- Loading state preserves the label where possible and adds a compact progress cue.
- Button height follows the selected density mode.

#### Primary button

```text
fill: primaryAction
text: textInverse
radius: small
```

#### Secondary button

```text
fill: surfaceRaised or transparent
border: dividerStrong
text: textPrimary
```

#### Quiet button

```text
fill: transparent
text/icon: textSecondary
hover: surfaceRaised
```

#### Destructive button

```text
fill: dangerAction for confirmed destructive action
or
transparent with danger text for lower-emphasis destructive action
```

### 11.2 Icon buttons

- Default icon size: 16 px.
- Compact utility icon: 14 px.
- Pointer target: at least 24 × 24 px; 28 × 28 px preferred.
- Use a text label when the action is unfamiliar, consequential, or ambiguous.
- Every icon-only button has an accessible name and tooltip.
- Do not place icon buttons in every table cell.
- Prefer row selection plus a shared action area for frequent actions.

### 11.3 Text fields

- Labels remain visible; placeholder text does not replace a label.
- Use monospace for command, identifier, hash, and code-like input.
- Show units as suffixes outside the editable value when possible.
- Validation appears near the field and includes a correction.
- Do not validate every keystroke when the intermediate value is naturally incomplete.
- Preserve user input after server or runtime rejection unless unsafe.
- Passwords, tokens, and runtime credentials are not entered in ordinary terminal forms.

### 11.4 Selection controls

- Use checkboxes for independent choices.
- Use radio buttons or a compact segmented control for one-of-many choices.
- Use switches only for immediate binary settings, never for a governed financial action.
- Do not use a switch for `Live trading`, `Place order`, `Approve`, or equivalent
  consequential actions.
- Selection state and focus state remain visually distinct.

### 11.5 Menus and popovers

- Use menus for secondary commands.
- Keep menu labels short and verb-led.
- Group commands by task, not implementation subsystem.
- Show keyboard shortcuts.
- Dangerous commands are separated and clearly labeled.
- Popovers close on `Escape` and restore focus.
- Do not use a popover for information the operator must continuously monitor.

### 11.6 Dialogs and confirmations

Use a modal dialog only when the user must decide before continuing.

A governed-action confirmation includes:

```text
action
account
mode
proposal or ticket identity
policy outcome
policy version
notional or amount
estimated cost
cash/buying power after
freshness
evidence/replay state
irreversible consequence
```

Rules:

- Dialog titles name the action: `Place paper order`, not `Confirmation`.
- The primary button repeats the action.
- Destructive actions require an explicit destructive label.
- Critical identifiers and amounts use tabular or monospace typography.
- Do not hide the consequence in body copy.
- Do not use countdowns, urgency language, or persuasive design.
- `Enter` activates the default only when doing so cannot cause accidental material
  action.
- Very consequential actions MAY require a deliberate typed phrase or second step, but
  friction must be proportional and documented.

### 11.7 Status indicators

Preferred status treatment:

```text
thin colored rule
+ compact icon or square
+ explicit text
+ optional reason/code
```

Examples:

```text
ALLOWED
DENIED — exposure limit exceeded
APPROVAL REQUIRED
STALE — 37s old
UNAVAILABLE — adapter offline
REPLAY MATCH
DIVERGENCE — sequence 184
```

Avoid large filled status cards.

### 11.8 Banners

Banners are reserved for state that affects the current region or whole workspace:

- disconnected;
- stale;
- incompatible protocol/schema;
- fixture mode;
- action authority unavailable;
- resynchronizing.

A banner includes:

1. what happened;
2. what is affected;
3. whether action is blocked;
4. what happens next or what the user can do.

Persistent banners do not animate.

### 11.9 Toasts and transient messages

Use a toast only for low-risk, nonpersistent confirmation.

Good:

```text
Workspace saved
Copied proposal ID
Export created
```

Do not use a toast as the only presentation for:

- denial;
- failed command;
- outcome unknown;
- disconnected state;
- stale state;
- approval result;
- execution result;
- audit or replay divergence.

Important results remain visible in the relevant panel or status region.

### 11.10 Progress

- Use determinate progress when the runtime provides meaningful progress.
- Use an indeterminate indicator only when work is active and progress is unavailable.
- Do not place an independent spinner in every table row.
- Background work appears in a shared status location.
- Long operations expose elapsed time and cancellation when supported.
- Progress indicators stop when a panel is hidden or the operation ends.

### 11.11 Empty, loading, unavailable, and error states

These states are distinct:

| State | Meaning | Treatment |
| --- | --- | --- |
| Empty | Valid result with no items | Explain what would appear and the next valid action |
| Loading | Request accepted, result pending | Preserve layout; show compact progress |
| Unavailable | Required source or capability absent | State dependency and blocked functions |
| Stale | Last confirmed data is too old | Show age; disable governed action as required |
| Error | Operation failed | Explain cause, affected scope, and recovery |
| Outcome unknown | Command may have been accepted | Reconcile by command ID; do not invite resubmission |

Do not use one generic illustration for all states.

---

## 12. Tables and Dense Data

Tables are a primary interface, not a secondary component.

### 12.1 Table anatomy

```text
optional table title and scope
column header
rows
selection/focus
optional totals
compact footer/status
```

### 12.2 Column behavior

- Text columns align left.
- Numeric columns align right.
- Codes and short statuses MAY align left or center, but use one rule consistently.
- Headers align with their data.
- Column widths remain stable during updates.
- Essential columns have protected minimum widths.
- User-resized columns MAY persist per workspace.
- Sorting is explicit and visible.
- The active sort includes direction and priority where multisort exists.
- Filters remain visible and removable.
- Hidden columns are discoverable through column settings.

### 12.3 Row behavior

- Default row height follows density mode.
- Do not use zebra striping by default.
- Use a subtle hover surface.
- Use a stronger selected surface.
- Focused cell uses the focus outline.
- Selection never relies only on text color.
- Do not change row height when a status or value changes.
- Expansion rows are used sparingly; prefer a detail panel for complex information.

### 12.4 Live updates

Tickoni is not an HFT visualization surface. The UI must preserve operator comprehension
and frame stability rather than animate every runtime event.

Rules:

- Do not emit one visual animation per tick or per cell.
- Coalesce latest-value updates before they reach delegates.
- Update only affected roles and cells.
- Never reset the whole model for one value.
- Preserve ordered correctness-bearing state.
- Use signed text, arrows, or a restrained state role for direction.
- High-frequency cells MUST NOT run individual timers.
- A brief changed-state tint MAY be applied by a batched model role, but:
  - it must not change geometry;
  - it must not animate opacity or scale;
  - it must be disabled in reduced-motion mode;
  - it must be capped to visible, meaningful updates;
  - it must not obscure the current value.
- Critical state transitions MAY receive one restrained emphasis transition.

### 12.5 Table performance design

A hot delegate should contain only:

- background/selection item;
- one or two text items;
- optional compact status icon;
- focus treatment.

Avoid in hot delegates:

- nested general-purpose controls;
- charts;
- loaders for ordinary content;
- shadows;
- clipping unless necessary;
- per-cell timers;
- JavaScript loops;
- dynamic object creation;
- network or service objects;
- independent tooltips instantiated for every cell;
- complex implicit-size chains.

Details appear in an external panel, popover created on demand, or dedicated page.

---

## 13. Financial State and Decision Presentation

### 13.1 Decision hierarchy

When a proposal is evaluated, present information in this order:

1. outcome;
2. exact reason;
3. policy/check identity;
4. observed value;
5. permitted limit;
6. source and freshness;
7. available next action.

Example:

```text
DENIED
Concentration exceeds the account limit.

Observed       31.4%
Maximum        25.0%
Policy check   concentration.max_position
Policy         v1.11
As of          17:36:12 UTC
```

Do not show only a red badge.

### 13.2 Action authority

A control's enabled state derives from current semantic state, not appearance.

The UI distinguishes:

```text
available
unavailable
blocked by policy
approval required
stale
disconnected
submitting
outcome unknown
completed
```

Each unavailable action has a reason.

### 13.3 Positive and negative values

- Green/red may indicate positive/negative movement only when the financial context
  defines that meaning.
- A rising liability, cost, or risk is not automatically positive.
- Use `+`, `−`, arrows, labels, and context.
- Do not use wealth vermilion for gains.
- Do not use green for a button that places or approves an action.
- Policy outcome colors override generic market-direction coloring where both could
  appear.

### 13.4 Stale state

Stale values remain visible when useful, but they are visibly marked.

A stale treatment includes:

- `STALE`;
- data age;
- source;
- reduced emphasis or warning rule;
- exact effect on actions.

Do not blur stale values. Operators may still need to read and compare them.

---

## 14. Charts and Data Visualization

### 14.1 Purpose

A chart must answer a defined operator question. It is not decorative background.

Examples:

- How has price or exposure changed?
- What is the before/after portfolio impact?
- Where did replay diverge?
- Which policy threshold is approached or exceeded?
- How fresh and complete is the source data?

### 14.2 Visual rules

- Primary series: active blue.
- Comparison series: muted steel or cool white.
- Annotation and operator cue: amber.
- Pass/fail markers: semantic green/red with labels or symbols.
- Background: canvas or surface.
- Grid lines: subtle divider.
- Axes: secondary text.
- Crosshair: active blue or primary text.
- Use solid lines before patterns; add patterns when color differentiation is insufficient.
- No 3D.
- No glow.
- No gradients unless encoding uncertainty has a documented meaning.
- No chart junk.
- Avoid area fills when they obscure comparison.
- Do not animate entire historical series on load.

### 14.3 Financial charts

- Show source and `as of` state.
- Mark gaps rather than interpolating silently.
- Identify adjusted versus unadjusted data.
- Display timezone.
- Keep volume visually subordinate to price unless volume is the primary question.
- Use crosshair and keyboard navigation.
- Order, proposal, and policy markers use distinct shapes and text.
- Do not imply execution precision beyond the supplied data.
- Streaming data is published to the chart at a bounded visual cadence.
- Hidden charts stop continuous redraw.

### 14.4 Impact visualization

Before/after impact should favor aligned numbers and restrained bars over decorative
charts.

Preferred:

```text
Cash                 42,000  ->  31,250
Buying power         84,000  ->  62,500
Largest position       18.2% ->    24.6%
Sector exposure        31.0% ->    38.4%
```

Use a chart only when it reveals a relationship not clear in the numbers.

---

## 15. Iconography

### 15.1 Style

- Simple geometric symbols.
- Consistent stroke or fill language.
- Optical alignment at 14–16 px.
- No decorative multicolor icons in the workspace.
- No emoji.
- Avoid brand marks for ordinary actions.

### 15.2 Semantic icons

Icons supplement text:

```text
check       pass
x/octagon   denied or failed
triangle    warning
clock       stale or pending
link        evidence/reference
shield      policy/authority
branch      replay/divergence
plug        adapter/connection
```

Do not rely on an icon alone for a critical status.

### 15.3 Platform symbols

Use platform-standard symbols where behavior is platform-standard, such as window,
clipboard, reveal, and navigation actions. Maintain Tickoni-specific symbols for domain
concepts.

---

## 16. Motion and Feedback

### 16.1 Motion principles

Motion communicates:

- focus movement;
- panel reveal;
- command acceptance;
- connection transition;
- replay progress;
- critical state change.

Motion does not celebrate, decorate, or create urgency.

### 16.2 Durations

| Token | Duration | Use |
| --- | ---: | --- |
| `motion.instant` | 0 ms | Data and layout updates |
| `motion.fast` | 80 ms | Hover and pressed feedback |
| `motion.standard` | 140 ms | Focus or compact reveal |
| `motion.emphasis` | 200 ms | Critical state transition |
| `motion.long` | 280 ms | Rare panel transition |

Rules:

- Data values update immediately; do not tween numeric truth.
- Use opacity only for small transient overlays, not large workspace regions.
- Avoid spring and bounce motion.
- Avoid continuous pulsing.
- At most one continuous progress animation is visible in the default workspace.
- Background and hidden views stop animation and redraw.
- Reduced-motion mode converts nonessential transitions to instant state changes.

### 16.3 Sound and haptics

Desktop sound is off by default.

A sound MAY be available for:

- approval request;
- connection loss;
- completed long-running task;
- critical operational alert.

Rules:

- sound is user-configurable;
- no trading-floor sound effects;
- no sound for every price update;
- every auditory alert has a visual equivalent.

---

## 17. Accessibility

Tickoni targets WCAG 2.2 AA principles as applied to desktop software, plus platform
accessibility conventions.

### 17.1 Required behavior

- Every core function is keyboard accessible.
- Focus is visible and programmatically exposed.
- Controls have accessible names, roles, values, and states.
- Status changes are announced without flooding assistive technology.
- Color is never the only carrier of meaning.
- Primary text meets 4.5:1 contrast.
- Non-text controls and focus indicators meet applicable contrast requirements.
- Pointer targets meet at least 24 × 24 px or satisfy the spacing exception.
- Text and layout remain usable at 200% scaling.
- Critical content is not clipped at supported display scales.
- Reduced motion is supported.
- High contrast is supported.
- Screen-reader reading order follows visual and task order.
- Drag-only actions have keyboard and single-pointer alternatives.
- Table headers, row labels, selected state, sort state, and cell values are exposed.
- Timeouts do not remove information or complete consequential actions without consent.

### 17.2 Accessible naming

Good:

```text
"Request approval for proposal P-882"
"Policy outcome: denied"
"Data age: 37 seconds, stale"
"Replay status: match"
```

Bad:

```text
"Button"
"Red icon"
"Error"
"Status"
```

### 17.3 Zoom and scaling

Test:

```text
100%
125%
150%
200%
```

At every scale:

- numeric columns remain legible;
- focused controls remain visible;
- dialogs fit or scroll;
- action state and policy reason remain visible;
- multi-monitor movement does not corrupt scale;
- custom graphics render sharply.

---

## 18. Content Design

### 18.1 Voice

Tickoni copy is:

- direct;
- factual;
- calm;
- specific;
- nonpromotional;
- nonanthropomorphic;
- free of blame.

Do not use:

```text
Oops
Great news!
We think...
The AI decided...
Something went wrong
Are you sure? (without naming the action)
```

Prefer:

```text
Proposal denied
Concentration exceeds the 25.0% account limit.

Connection lost
Current account state is unavailable. Governed actions are disabled.

Outcome unknown
The command timed out after submission. Tickoni is reconciling request req_8192.
```

### 18.2 Error structure

Every actionable error answers:

1. What happened?
2. What is affected?
3. Why did it happen, when known?
4. What can the operator do?
5. What identifier supports diagnosis?

Example:

```text
Replay could not start

Capsule capsule_102 requires runtime schema 14; this terminal supports schema 13.
Update the terminal or connect to a compatible runtime.

Reference: err_schema_204
```

### 18.3 Terminology

Use one term for one concept.

Preferred fixed vocabulary:

```text
case
intent
proposal
ticket
policy
check
outcome
approval
paper order
evidence
audit
replay
divergence
source
freshness
adapter
runtime
```

Do not alternate casually between `trade`, `order`, `action`, `execution`, and `proposal`
when they represent different lifecycle stages.

### 18.4 Status vocabulary

Approved statuses:

```text
ALLOWED
DENIED
APPROVAL REQUIRED
PENDING
UNAVAILABLE
STALE
DISCONNECTED
RESYNCHRONIZING
SUBMITTING
OUTCOME UNKNOWN
COMPLETED
FAILED
REPLAY MATCH
DIVERGENCE
```

A new status requires design and semantic review.

---

## 19. Cross-Platform Standards

### 19.1 Shared product identity

The central workspace, data hierarchy, color semantics, and component metrics remain
consistent across Linux, macOS, and Windows.

### 19.2 Native conventions

Adapt:

- menu placement;
- keyboard modifier labels;
- standard edit commands;
- window controls;
- file and folder selection;
- system notifications;
- text cursor and selection behavior;
- context menus;
- accessibility APIs;
- high-contrast and reduced-motion preferences.

### 19.3 Window chrome

Retain native window chrome unless a later ADR proves custom chrome can meet:

- resize reliability;
- accessibility;
- high-DPI behavior;
- multi-monitor behavior;
- platform window management;
- drag regions;
- full-screen behavior;
- system menu access.

### 19.4 Shortcut notation

Display platform-correct shortcuts:

```text
macOS:   ⌘K, ⌘W, ⌘C
Windows: Ctrl+K, Ctrl+W, Ctrl+C
Linux:   Ctrl+K, Ctrl+W, Ctrl+C
```

The command language itself remains platform independent.

### 19.5 Pointer and context menus

- Right-click and platform-equivalent context actions are supported.
- Context menus contain only actions relevant to the selected object.
- All context actions are available by keyboard or another visible command route.
- Do not hide essential commands exclusively in a context menu.

---

## 20. Qt Quick Implementation Style

Visual quality and runtime performance are one design problem. A visually correct
component that causes binding churn, frame drops, or memory growth is not acceptable.

### 20.1 Control foundation

Use a custom Tickoni Qt Quick Controls style based on the lightweight Basic style unless
a measured platform-specific requirement justifies another implementation.

Rules:

- Do not mix unrelated Qt control styles within one window.
- Centralize control backgrounds, indicators, padding, metrics, and states.
- Use native system dialogs and window chrome where required.
- Feature teams do not restyle base controls locally.

### 20.2 QML boundaries

QML components:

- render typed state;
- collect local input;
- call a typed ViewModel method;
- contain small display-only formatting.

QML components do not:

- make HTTP requests;
- open WebSockets;
- access shared-memory channels;
- parse runtime messages;
- own credentials;
- submit directly to adapters or brokers;
- run large JavaScript transformations;
- store authoritative financial state.

### 20.3 Bindings

Hot-path bindings MUST be:

- side-effect free;
- constant-time;
- local;
- based on a small number of typed properties or roles.

Avoid:

- binding chains through global singletons;
- large `QVariantMap` screen state;
- per-frame formatting;
- bindings that allocate arrays or objects;
- multiple bindings expressing the same derived value;
- width calculations that depend recursively on many children.

Compute shared derived values once in C++ and expose them through typed properties or
model roles.

### 20.4 Delegates

Qt view delegate complexity directly affects creation and scrolling performance.

- Keep delegates visually and structurally small.
- Reuse items where supported.
- Reset transient state when a delegate is reused.
- Pause timers or activity while pooled.
- Do not retain row authority in a delegate.
- Create detail UI lazily outside the hot delegate.
- Use anchors or simple layouts rather than many arithmetic position bindings.
- Keep role types stable.
- Avoid dynamic role types.
- Test delegate creation and scrolling with realistic data.

### 20.5 Update discipline

The UI receives:

- lossless ordered correctness events;
- coalesced latest-value projections;
- bounded GUI model patches.

Design implications:

- do not visually represent every internal message;
- do not create one queued animation or signal per tick;
- separate runtime event frequency from display update frequency;
- preserve exact final value, revision, age, and semantic state;
- keep the GUI frame budget available for input and rendering.

### 20.6 Performance-sensitive visual effects

The following require explicit profiling evidence:

- blur;
- shader effects;
- large translucent layers;
- clipping of complex subtrees;
- many simultaneous animations;
- nested scrolling regions;
- charts inside table delegates;
- large text shadows;
- continuously changing gradients;
- custom scene-graph components.

Default answer: do not use them.

### 20.7 Hidden content

A hidden page or panel:

- stops continuous animation;
- unsubscribes from presentation-only updates when safe;
- does not keep expensive delegates alive without need;
- may retain authoritative projection state outside QML;
- resumes from current projection rather than replaying every hidden update visually.

---

## 21. Component State Matrix

Every interactive component must define these states where applicable:

| State | Required treatment |
| --- | --- |
| Default | Neutral, clear affordance |
| Hover | Subtle surface or border change |
| Pressed | Immediate compact feedback |
| Focused | 2 px focus indicator |
| Selected | Stable selected surface or rule |
| Disabled | Reduced emphasis plus reason |
| Loading | Stable geometry and progress |
| Invalid | Exact error; danger treatment |
| Stale | Warning treatment plus age |
| Disconnected | Unavailable state and effect |
| Submitting | Prevent duplicate submission |
| Outcome unknown | Persistent reconciliation state |

Hover MUST NOT be the only way to discover information or functionality.

---

## 22. Design Tokens in QML

Illustrative token shape:

```qml
pragma Singleton

QtObject {
    readonly property color canvas: "#070A0E"
    readonly property color surface: "#0B1119"
    readonly property color surfaceRaised: "#101923"
    readonly property color dividerSubtle: "#192431"
    readonly property color dividerStrong: "#263445"

    readonly property color textPrimary: "#E7EDF4"
    readonly property color textSecondary: "#8D9AAA"
    readonly property color textDisabled: "#566270"

    readonly property color brand: "#3478D4"
    readonly property color focus: "#4A9EFF"
    readonly property color command: "#E8A83E"
    readonly property color brandSeal: "#A9343D"

    readonly property color pass: "#47A66A"
    readonly property color danger: "#E0525E"
    readonly property color warning: "#D69A32"
}
```

The production token implementation SHOULD expose semantic names rather than visual names
where a token is tied to a component state.

Good:

```text
button.primary.background
table.row.selected
focus.outline
status.denied.foreground
```

Avoid:

```text
blue2
darkGray4
redLight
```

---

## 23. Reference Screen Rules

### 23.1 CASE

- Default working function.
- Intent and account context appear before proposal detail.
- Proposal table is central.
- Decision state is visible without opening another page.
- Impact and proof summaries link to full functions.
- Primary governed action is singular and clearly qualified.

### 23.2 POLICY

- Outcome and exact reason lead.
- Each check shows observed value, limit, operator, and source.
- Denied and warning states remain legible without color.
- Checks can be copied or referenced by stable identity.
- Do not collapse failed checks by default.

### 23.3 IMPACT

- Before and after values align.
- Cash, buying power, exposure, and concentration lead.
- Units are explicit.
- Warnings identify threshold and consequence.
- Charts are secondary to exact values.

### 23.4 PROOF

- Audit identity, evidence references, hashes, replay state, and divergence are grouped
  by question.
- Long hashes use monospace and copy affordances.
- Match and divergence use text plus symbols.
- Do not imply proof from a green visual alone.

### 23.5 SYSTEM

- Show connection mode, tile identity, source, freshness, queue lag, versions, and
  compatibility.
- Use diagnostic density without becoming a full operations console.
- Transport, tile, and policy errors remain distinct.
- Sensitive payloads and credentials never appear.

---

## 24. Design Review Checklist

A feature is not ready for implementation review until the design answers:

### Hierarchy

- What is the primary operator question?
- What is the primary value or outcome?
- What can be safely deferred?
- Is critical context visible?

### Interaction

- Can every action be completed by keyboard?
- Is focus order explicit?
- Is the command equivalent defined?
- Are disabled and blocked states explained?
- Can duplicate governed submission occur?

### Financial correctness

- Is authoritative state distinguishable from local state?
- Is stale state visible?
- Are source and freshness available?
- Are exact limits and observed values shown?
- Is color supplemented with text or shape?

### Visual system

- Are only approved tokens used?
- Is color proportion restrained?
- Is typography limited and aligned?
- Are surfaces flat and calm?
- Is the component using an unnecessary card, radius, shadow, or animation?

### Accessibility

- Does contrast meet the required threshold?
- Does the control have an accessible name, role, value, and state?
- Does it work at 200%?
- Is important content reachable without hover or drag?
- Does reduced-motion behavior exist?

### QML performance

- Is a large collection using `QAbstractItemModel`?
- Is the delegate minimal and reusable?
- Are bindings local and bounded?
- Is high-frequency state coalesced?
- Does one data update avoid rebuilding the page?
- Does hidden content stop rendering?
- Has the representative path been profiled?

### Cross-platform

- Are shortcuts platform-correct?
- Does native window behavior remain intact?
- Has the design been checked at all supported scale factors?
- Does the layout survive monitor and window-size changes?

---

## 25. Release Evidence

Every release candidate SHOULD include:

- screenshots at 1280 × 720, 1920 × 1080, and 2560 × 1440;
- screenshots at 100%, 125%, 150%, and 200% scaling;
- compact, standard, and large density evidence;
- keyboard-only workflow recording;
- screen-reader checks for command, function navigation, decision, and confirmation;
- high-contrast screenshots;
- reduced-motion verification;
- 10,000-row table scrolling evidence;
- live-update frame-time and binding profile;
- stale, disconnected, denied, approval, unavailable, and outcome-unknown states;
- multi-window and multi-monitor evidence on Linux, macOS, and Windows;
- token audit showing no unapproved raw colors or metrics in feature QML.

---

## 26. Governance

### 26.1 Source of truth

This document owns:

- visual identity;
- design tokens;
- density and component metrics;
- interaction and content conventions;
- accessibility design requirements;
- QML visual-performance constraints.

ADR-0002 owns:

- architecture;
- channels and queues;
- thread ownership;
- model and ViewModel boundaries;
- `tk_ui` and `tk_gate` communication.

The runtime and API contracts own:

- financial truth;
- policy semantics;
- freshness and revision validity;
- action authority;
- audit and replay identity.

### 26.2 Adding a component

A new shared component requires:

1. documented purpose;
2. state matrix;
3. keyboard behavior;
4. accessibility contract;
5. token usage;
6. density behavior;
7. QML performance review;
8. screenshot and interaction evidence.

### 26.3 Exceptions

A deviation requires:

- reason the standard pattern is insufficient;
- affected platforms and functions;
- accessibility impact;
- performance impact;
- owner and approval;
- removal or review trigger.

A deviation cannot permit direct networking, broker access, policy interpretation, or
execution authority in a QML component.

---

## 27. External Standards and References

This guide adapts established desktop and accessibility principles to Tickoni's
cross-platform Qt terminal rather than copying any platform's visual trade dress.

- [Apple Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/)
- [Apple HIG — Designing for macOS](https://developer.apple.com/design/human-interface-guidelines/designing-for-macos/)
- [Apple HIG — Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility/)
- [Apple HIG — Color](https://developer.apple.com/design/human-interface-guidelines/color/)
- [Apple HIG — Typography](https://developer.apple.com/design/human-interface-guidelines/typography/)
- [WCAG 2.2](https://www.w3.org/TR/WCAG22/)
- [WCAG2ICT 2.2](https://www.w3.org/TR/wcag2ict-22/)
- [Microsoft — Windows app design guidelines](https://learn.microsoft.com/windows/apps/design/guidelines-overview)
- [Microsoft — Windows accessibility checklist](https://learn.microsoft.com/windows/apps/design/accessibility/accessibility-checklist)
- [GNOME Human Interface Guidelines](https://developer.gnome.org/hig/)
- [Qt Quick performance considerations](https://doc.qt.io/qt-6/qtquick-performance.html)
- [Qt Quick TableView](https://doc.qt.io/qt-6/qml-qtquick-tableview.html)
- [Qt Quick Controls styles](https://doc.qt.io/qt-6/qtquickcontrols-styles.html)
- [Qt accessibility](https://doc.qt.io/qt-6/accessible.html)
- [Qt high-DPI support](https://doc.qt.io/qt-6/highdpi.html)

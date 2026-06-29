---
type: "core"
name: "Design System & UI Standards"
status: "stable"
dependencies: ["05-app-structure"]
description: "The single source of truth for Airclone's visual design — tokens, typography, spacing, elevation, and core components."
---

# 🎨 Design System

The single source of truth for visual design. **Components reference only semantic tokens, never raw
hex.** All semantic tokens have light and dark values. Token naming follows the convention
`--color-*`, `--text-*`, `--space-*`, `--radius-*`, `--elevation-*`.

## 🧭 Design Principles

1. **Every cloud feels local** — one surface for all backends; no "cloud mode."
2. **Direct manipulation first** — drag to move/copy/sync; dialogs are for precision, not basics.
3. **Safe by default, powerful on demand** — dry-run + diff before destructive ops; advanced controls
   one disclosure away.
4. **Progressive disclosure of power** — sane defaults up front; VFS modes, bandwidth windows, filter
   rules, conflict strategies behind "Advanced."
5. **Always-on observability** — transfers/jobs/mounts are never hidden behind a screen you must
   remember to open.

**Voice & microcopy:** warm, concise, scannable. Plain language over jargon ("Two-way sync" not
"bisync"; "Mirror →" not `--delete-dest`). Every dangerous confirmation gets a one-line "what's about
to happen" explainer. No emoji in product UI.

## 🌈 Color Tokens

| Token | Role | Light | Dark |
| :--- | :--- | :--- | :--- |
| `--color-surface` | App background | `#F7F8FA` | `#16181D` |
| `--color-surface-raised` | Cards, panels | `#FFFFFF` | `#1F2229` |
| `--color-surface-sunken` | Wells, input bg | `#EDEFF3` | `#101216` |
| `--color-border` | Dividers, outlines | `#E2E5EB` | `#2C313B` |
| `--color-border-strong` | Focused/active outline | `#C4C9D4` | `#3C434F` |
| `--color-text` | Primary text | `#1A1D23` | `#ECEEF2` |
| `--color-text-muted` | Secondary text | `#5C6470` | `#9AA2AF` |
| `--color-text-faint` | Tertiary/meta | `#8A929E` | `#6B7280` |
| `--color-primary` | Brand, primary actions | `#2F7DF6` | `#5C9CFF` |
| `--color-primary-hover` | Primary hover | `#1F6AE0` | `#7AB0FF` |
| `--color-on-primary` | Text on primary | `#FFFFFF` | `#0B1220` |
| `--color-secondary` | Secondary accent | `#7C5CFC` | `#A48BFF` |
| `--color-success` | Connected, complete | `#1FA672` | `#3FD49A` |
| `--color-success-bg` | Success surface | `#E4F7EF` | `#10322A` |
| `--color-warning` | Changed, caution | `#D9882B` | `#F0B45E` |
| `--color-warning-bg` | Warning surface | `#FBF0E1` | `#3A2C14` |
| `--color-error` | Failure, destructive | `#E14B4B` | `#FF6B6B` |
| `--color-error-bg` | Error surface | `#FBE6E6` | `#3A1A1A` |
| `--color-info` | Neutral info | `#3B82C4` | `#6BA6E0` |
| `--color-diff-only-a` | "Only in source" | `#3B82C4` | `#6BA6E0` |
| `--color-diff-only-b` | "Only in dest" | `#7C5CFC` | `#A48BFF` |
| `--color-overlay` | Modal scrim | `rgba(16,18,22,.45)` | `rgba(0,0,0,.6)` |

**Diff/status legend** (reused identically in the sync dialog and Compare view): match = `--color-success`,
changed = `--color-warning`, only-in-source = `--color-diff-only-a`, only-in-dest = `--color-diff-only-b`.

## 🔠 Typography Scale

System stack: `-apple-system, "Segoe UI", Roboto, "Inter", sans-serif`. Monospace for paths/sizes:
`"JetBrains Mono", ui-monospace, monospace` with `font-variant-numeric: tabular-nums`.

| Token | Size / line-height | Weight | Use |
| :--- | :--- | :--- | :--- |
| `--text-display` | 28 / 34 | 700 | Onboarding headers |
| `--text-h1` | 22 / 28 | 600 | View titles |
| `--text-h2` | 18 / 24 | 600 | Section headers, dialog titles |
| `--text-body` | 14 / 20 | 400 | Default UI text, file rows |
| `--text-body-strong` | 14 / 20 | 600 | Emphasis, remote names |
| `--text-label` | 12 / 16 | 500 | Field labels, chips |
| `--text-meta` | 12 / 16 | 400 | Sizes, timestamps (mono, tabular) |
| `--text-caption` | 11 / 14 | 400 | Hints, status-bar text |

> Mobile bumps `--text-body` to 16/22 and file-row min-height to 56px for touch comfort.

## 🔳 Spacing, Radius & Elevation

4px base spacing scale: `--space-1` 4 · `--space-2` 8 · `--space-3` 12 · `--space-4` 16 ·
`--space-5` 24 · `--space-6` 32 · `--space-8` 48 (`--space-0` = 0).

Radius: `--radius-sm` 4px · `--radius-md` 8px (cards, buttons) · `--radius-lg` 12px (mobile cards,
modals) · `--radius-full` 999px (chips, toggles).

| Elevation | Light | Dark | Use |
| :--- | :--- | :--- | :--- |
| `--elevation-0` | none | none | Flush rows |
| `--elevation-1` | `0 1px 2px rgba(20,22,28,.06)` | `0 1px 2px rgba(0,0,0,.4)` | Cards, panels |
| `--elevation-2` | `0 4px 12px rgba(20,22,28,.10)` | `0 4px 12px rgba(0,0,0,.5)` | Popovers, dropdowns |
| `--elevation-3` | `0 12px 32px rgba(20,22,28,.16)` | `0 12px 32px rgba(0,0,0,.6)` | Modals, drag-ghost |

## 🧩 Key Components

See the [Components Index](../components/components-index.md) for the full catalog. Anchors:

- **Remote card** — `--surface-raised`, `--radius-md`, `--elevation-1`, padding `--space-3`. Provider
  icon (28px) + name (`--text-body-strong`) + connection dot (`--color-success` up / `--color-error`
  down) + storage bar (4px track, `--color-primary` fill) + muted usage label. Mobile adds a
  **"Show in Files"** toggle row.
- **File row** — 36px desktop / 56px mobile. Leading type icon/thumbnail, name (`--text-body`,
  truncates), trailing meta (size + modified, `--text-meta` mono tabular). Hover `--surface-sunken`;
  selected = `--color-primary` 12%-alpha bg + left accent bar; status-glyph slot for transfer state.
- **Transfer row** — type label + `source → dest` (mono, middle-truncating) + progress bar
  (`--color-primary`, `--color-error` on fail) + speed + ETA + status chip; indeterminate shimmer
  while starting.
- **Job chip** — `--radius-full`, `--text-label`. Running (`--color-info` + spinner) · Success
  (`--color-success-bg`/`--color-success`) · Failed (`--color-error-bg`/`--color-error`) · Scheduled
  (muted outline) · Watching (`--color-secondary`).
- **Primary button** — `--color-primary` bg, `--color-on-primary` text, `--radius-md`, padding
  `--space-2 --space-4`, `--text-body-strong`; hover `--color-primary-hover`; focus 2px
  `--color-primary` ring @40%; disabled 40% opacity. Secondary = transparent + `--color-border-strong`
  outline. Destructive = `--color-error` bg.

## ♿ Accessibility & Responsive

- **Contrast:** all text/bg pairs meet WCAG AA (4.5:1 body, 3:1 large). **Status is never
  color-only** — pair every dot/chip with an icon and text label.
- **Keyboard (desktop):** full operability — arrow-key file nav, `Ctrl/Cmd+A`, Shift-range,
  Ctrl-click multi-select, `F2` rename, `Del` delete, `Ctrl+C/X/V` across panes, `Tab` switches
  panes, `Esc` cancels. Visible 2px `--color-primary` focus ring on every interactive element. Every
  drag has a keyboard-equivalent (copy/move via menu).
- **Screen readers:** panes = `tree`/`grid`, job panel = `log` with `aria-live="polite"`; toggles
  expose `aria-pressed`.
- **Touch (mobile):** 44×44px minimum targets; primary actions in the thumb zone; destructive actions
  confirm, never a bare swipe; honor OS dynamic-type.
- **Motion & themes:** respect `prefers-reduced-motion` and `prefers-color-scheme` (with manual
  override). All meaning survives in monochrome/high-contrast.

**Responsive breakpoints:** ≥1100px full dual-pane + sidebar + docked job panel · 820–1100px sidebar
collapses to icon rail · <820px folds to single-pane + bottom-sheet job panel · mobile (<600px)
single-pane browser + bottom nav, no dual pane/mount, full-screen dialog sheets.

> The same domain/RC client and component primitives back both form factors — only the layout shell
> and navigation model differ. See [05-app-structure.md](05-app-structure.md) for the layouts and
> wireframes.

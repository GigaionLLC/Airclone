# Airclone — Design & Frontend Guidelines 🎨

To keep Airclone visually consistent across desktop and mobile, all UI work **MUST** follow the
master design system.

> [!IMPORTANT]
> Before creating or modifying any UI, read the full specification:
> ➡️ **[wiki/core/06-design-system.md](wiki/core/06-design-system.md)**
> and the layouts/wireframes in **[wiki/core/05-app-structure.md](wiki/core/05-app-structure.md)**.

## 🎨 Creative North Star

Calm, confident, quietly powerful. Airclone treats 70+ cloud backends as if they were folders on your
own disk, hides rclone's flag soup behind sane defaults, and keeps every advanced control one
disclosure away. Principles: *every cloud feels local · direct manipulation first · safe by default,
powerful on demand · progressive disclosure · always-on observability.*

## ⚙️ Core Design Tokens (quick reference)

Components reference **only** semantic tokens — never raw hex. Full table (light + dark) in the
[Design System](wiki/core/06-design-system.md).

| Token | Purpose |
| :--- | :--- |
| `--color-surface` / `--color-surface-raised` / `--color-surface-sunken` | App canvas · cards/panels · wells/inputs |
| `--color-text` / `--color-text-muted` / `--color-text-faint` | Primary · secondary · meta text |
| `--color-primary` / `--color-on-primary` | Brand & primary actions · text on primary |
| `--color-secondary` | Secondary accent |
| `--color-success` | Connected / complete |
| `--color-warning` | Changed / caution |
| `--color-error` | Failure / destructive |
| `--color-diff-only-a` / `--color-diff-only-b` | Compare diff: only-in-source / only-in-dest |

Type tokens: `--text-display/h1/h2/body/body-strong/label/meta/caption`. Spacing: 4px base
(`--space-1…8`). Radius: `--radius-sm/md/lg/full`. Elevation: `--elevation-0…3`.

## ✅ Rules

1. **Never hardcode** colors, spacing, or component styles — use tokens and shared primitives.
2. **Status is never color-only** — pair every dot/chip with an icon + text label.
3. **Destructive actions** show a one-line "what's about to happen" explainer and require confirmation.
4. **Plain language over jargon** — "Two-way sync" not "bisync"; "Mirror →" not `--delete-dest`.
5. **Responsive + accessible** — meet WCAG AA; full keyboard operability on desktop; 44px touch
   targets on mobile; respect `prefers-reduced-motion` and `prefers-color-scheme`.

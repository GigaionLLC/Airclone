# Airclone — Agent Entry Point 🚀

**Welcome to the Airclone workspace.**
Airclone is a modern, intuitive, **cross-platform** (desktop + mobile) GUI for
[rclone](https://rclone.org/) — "make every cloud feel like a local folder." This repository uses a
structured documentation library split into **`wiki/`** (architecture knowledge) and **`dev/`**
(operational process tooling), serving as the single source of truth for the codebase, architecture,
state, and UI.

Instead of searching the entire codebase to understand context, **STOP** and read the localized
intelligence hub first.

## 📌 Mandatory Reading (The Docs Hub)

### 1. 🗺️ Start here: [`wiki/core/00-system-index.md`](wiki/core/00-system-index.md)
The master router and architecture flow — how modules and data stores interact.

### 2. 🎯 Understand the product: [`wiki/core/01-vision-north-star.md`](wiki/core/01-vision-north-star.md)
What Airclone is, who it's for, and the magic moment. Read before proposing features.

### 3. 🎨 Building or editing UI? Read [`wiki/core/06-design-system.md`](wiki/core/06-design-system.md) **FIRST.**
Do not guess CSS classes, colors, or component styles. Airclone uses a strict token-based design
system (see also [`DESIGN.md`](DESIGN.md)).

### 4. 🧱 Architecture & rclone integration: [`wiki/core/08-core-architecture.md`](wiki/core/08-core-architecture.md)
The single most important decision in this project is **how we drive the rclone engine** (spawned
`rclone rcd` + RC HTTP API on desktop vs. in-process `librclone`/gomobile on mobile) behind one
`RcloneClient` interface. Read this before touching anything that talks to rclone.

### 5. 💾 Application state: [`wiki/core/07-state-context.md`](wiki/core/07-state-context.md)
Store shapes, contexts, and data models.

### 6. 🛠️ Editing a screen or feature? Check [`wiki/features/`](wiki/features/features-index.md) and the physical map in [`wiki/core/04-directory-structure.md`](wiki/core/04-directory-structure.md).

---

## 🔎 Task Lookup

| Task | Read first | Then drill into |
|---|---|---|
| Understanding the product / pitching a feature | [Vision & North Star](wiki/core/01-vision-north-star.md) | [Product Context](wiki/core/02-product-context.md) |
| Building or editing a UI component | [Components Index](wiki/components/components-index.md) | Specific component doc |
| Building or editing a screen / view | [Features Index](wiki/features/features-index.md) | Specific feature doc |
| Anything that talks to rclone | [Core Architecture](wiki/core/08-core-architecture.md) | [rclone integration logic](wiki/logic/logic-index.md) |
| Cross-platform / mobile concerns | [Core Architecture](wiki/core/08-core-architecture.md) | [Cross-Platform Plan](dev/plans/) |
| Editing overall layout or app shell | [App Structure](wiki/core/05-app-structure.md) | Core layout component docs |
| Understanding state shapes / context | [State & Context](wiki/core/07-state-context.md) | State management docs |
| Extending a utility or helper | [Logic Index](wiki/logic/logic-index.md) | Specific utility doc |
| Checking roadmap / parked items | [Backlog Index](dev/backlog/backlog-index.md) | [Feature Backlog](dev/backlog/feature-backlog.md) |

> **🔒 Reference material:** Deep competitive research and notes that name third-party projects live
> under **`reference/`**, which is **gitignored** and must never be committed. Read it for ideas, but
> keep external-project names out of committed files — cite our own docs in committed code.

---

## ⚡ Core Development Rules
1. **One rclone abstraction.** Never call rclone two different ways from the UI. Everything goes
   through the single `RcloneClient` interface (see Core Architecture). The UI must not know whether
   the engine is a spawned daemon or an in-process library.
2. **Never hardcode UI.** Use the design-system tokens and shared component primitives.
3. **Follow design specs.** Adhere strictly to the palettes, fonts, spacing, and behaviors in the
   [Design System](wiki/core/06-design-system.md).
4. **Destructive actions require confirmation.** Delete/purge/overwrite and "sync (one-way, deletes
   extra files)" must show an explicit confirmation surface.
5. **Context review.** Before writing code, review the last 3 entries in
   [`dev/logs/agent-changelog.md`](dev/logs/agent-changelog.md).
6. **Plan multi-step work.** Create/update a plan under [`dev/plans/`](dev/plans/) using the
   [Template Plan](dev/plans/template-plan.md).
7. **Cross-platform first.** Every feature is specified for desktop **and** mobile (or explicitly
   marked desktop-only / mobile-only with rationale).

## ✅ Mandatory Wrap-Up Protocol
Whenever a task or feature is complete — including when the user says "wrap up", "we're done", "ship
it", "that's it", or closes out a conversation — you **MUST**:

**Part 1 — Audit logging:** Add a row to [`dev/logs/agent-changelog.md`](dev/logs/agent-changelog.md):
```markdown
## [YYYY-MM-DD HH:MM] - [Task Name]
**Agent:** [Application/Agent Name] ([Model Name])
**Files Modified:**
- `src/...`
**Database/API Changes:** None | [describe if any]
**Summary:** One sentence summary of changes.
```

**Part 2 — Docs sync:** Update any `wiki/` file whose described behavior changed.

**Part 3 — Archive completed plans:** Move the finished plan from `dev/plans/[plan].md` to
`dev/archive-plans/[plan].md`.

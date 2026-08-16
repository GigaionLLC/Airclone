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
| Extending a utility or helper | [Utility Standards](wiki/core/12-utility-standards.md) | [Logic Index](wiki/logic/logic-index.md) |
| Adding an input field, a console/CLI surface, or a destructive action | [Validation Standards](wiki/core/11-validation-standards.md) | [Security](wiki/core/15-security.md) |
| Anything that reads file **content**, spawns a process, or polls | [Performance & Reliability Standards](wiki/core/14-performance-standards.md) | [External Integrations](wiki/core/10-external-integrations.md) |
| Native / platform build work (Android jniLibs, librclone, FUSE, channels) | [External Integrations](wiki/core/10-external-integrations.md) | [dev hub](dev/README.md) → `dev/android/`, `dev/desktop/` |
| Cutting a release | [dev hub](dev/README.md) (Release checklist) | [`dev/releases/`](dev/releases/) — notes must exist **before** the tag |
| Submitting to a store (Microsoft / Play / Apple) | [Store submissions index](docs/store/README.md) | [Windows](dev/windows-signing-and-store.md) · [Play](dev/google-play-store.md) · [Apple/macOS](dev/apple-appstore-and-macos.md) |
| Writing, moving, or removing a doc | [Docs Blueprint](wiki/core/17-docs-blueprint.md) | [Knowledge Capture](wiki/core/18-knowledge-capture.md) |
| Checking roadmap / parked items | [Backlog Index](dev/backlog/backlog-index.md) | [Feature Backlog](dev/backlog/feature-backlog.md) |

> **🔒 Reference material:** Deep competitive research and notes that name third-party projects live
> under **`reference/`**, which is **gitignored** and must never be committed. Read it for ideas, but
> keep external-project names out of committed files — cite our own docs in committed code.

> **🔐 Real account values:** store publisher identity, signing profiles, release hosting and other
> per-developer identifiers live in **[`dev/secrets/dev-profile.env`](dev/secrets/README.md)**, which
> is **gitignored**. Read it when you genuinely need a real value, but **never copy a PRIVATE or
> SECRET value into a committed file, commit message, doc or store listing** — refer to it by key
> name (`MSIX_PUBLISHER`), never by value. That file belongs to one builder; if you cloned this repo
> it will not exist, and that is expected — copy `dev-profile.example.env` and fill in your own.

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
8. **CI warnings are work, not noise.** A GitHub Actions run that is green but warning is a
   scheduled outage. Two kinds recur here and both must be fixed in the same change that surfaces
   them, never "later":
   - **Node runtime deprecations** — *"The following actions target Node.js 20 but are being forced
     to run on Node.js 24"*. Fix by bumping the action's MAJOR version (`actions/setup-python@v6`,
     `actions/setup-java@v5`, `actions/upload-artifact@v6`, `actions/checkout@v5`,
     `actions/download-artifact@v7`, `actions/setup-go@v6`). When adding ANY first-party action,
     check its current major first — the newest major is the one on the supported runtime.
   - **Input deprecations** — e.g. `r0adkll/upload-google-play`'s `track:` → `tracks:`. These break
     *silently* on a later action release, and for a publishing lane that means shipping quietly
     stops.

   Grep the whole tree, not just the file you touched:
   `grep -rn "uses:" .github/workflows/ .github/actions/ | sed 's/.*uses: *//' | sort | uniq -c`
9. **Verify by artifact, not by green check.** A step reporting success is not evidence the thing
   happened. This repo has shipped three Windows releases with no bundled rclone because
   `continue-on-error` hid the failure, and a Play upload can commit an edit that lands nothing.
   Where an external system holds the result, ask it: [`tool/play_tracks.py`](tool/play_tracks.py)
   asserts Play actually serves the version code CI just built, and the release job fails if it does
   not.

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

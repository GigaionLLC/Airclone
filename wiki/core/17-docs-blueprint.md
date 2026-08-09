---
type: "core"
name: "Docs Blueprint"
status: "stable"
dependencies: ["00-system-index", "18-knowledge-capture"]
description: "The documentation architecture standard: which tree a doc belongs in, the shape every doc must have, and how to register a new one so it is reachable."
---

# 📐 Docs Blueprint

The standard for Airclone's documentation library — where a doc lives, what it must contain, and how
it gets registered so an agent with no prior context can still find it.

**When to read this:** you are about to create, move, renumber, or delete a documentation file, or
you found a doc that is unreachable, duplicated, or contradicted by another doc and need to know who
owns the topic.

---

## 🗂️ 1. Two libraries (plus two things that are not libraries)

| Tree | Holds | Does **not** hold | Lifetime |
| :--- | :--- | :--- | :--- |
| **`wiki/`** | Durable architecture knowledge: how the system is built and why. Statements that stay true across releases. | Dated work, per-release prose, runbook steps, credentials. | **Rewritten in place** when behaviour changes. |
| **`dev/`** | Operational process: plans, backlog, session logs, per-tag release notes, platform/signing/store runbooks and build scripts. | Architecture explanation — link to `wiki/` instead. | **Appended to.** History, kept honest. |
| **`docs/`** | Published, outward-facing assets: brand images, screenshots, store listing copy and their manifests. | Agent-facing architecture. | Per submission / per release. |
| **`reference/`** | Competitive research naming third-party projects. **Gitignored — never committed, never cited from a committed file.** | Anything that ships. | Local only. |
| **Root `*.md`** | Entry points that route rather than explain: [`AGENT.md`](../../AGENT.md) (agents), [`README.md`](../../README.md) (users), [`DESIGN.md`](../../DESIGN.md), [`HOW-TO.md`](../../HOW-TO.md), [`PRIVACY.md`](../../PRIVACY.md). | Detail. They point at the library. | Edited as the library moves. |

**Placement test.** Ask in this order:

1. Will this still be true after the next five releases? → `wiki/`.
2. Does it record *what we did*, or *the steps to do a thing*? → `dev/`.
3. Will an end user or a store reviewer read it? → `docs/`.

**Inside `wiki/`:** `core/` holds the numbered "brain" documents (§2); `features/`, `components/`,
`logic/` and `database/` each hold topic docs **plus an index that lists every doc in that folder** —
[features](../features/features-index.md) · [components](../components/components-index.md) ·
[logic](../logic/logic-index.md) · [persistence](../database/database-index.md).

**Inside `dev/`:** `plans/` (live work, from [`template-plan.md`](../../dev/plans/template-plan.md)) ·
[`archive-plans/`](../../dev/archive-plans/README.md) (finished plans) ·
[`backlog/`](../../dev/backlog/backlog-index.md) · `logs/` · `releases/` (one file per tag) · the
per-platform runbooks and build scripts. The hub that indexes all of it is
[`dev/README.md`](../../dev/README.md).

---

## 🔢 2. The `wiki/core/` numbering scheme

Numbers are **stable identities**, not ordering. Agents, commit messages and prior sessions all cite
documents as "read 08" — renumbering silently breaks every one of those references as well as every
inbound link.

| Rule | Detail |
| :--- | :--- |
| A number is assigned once | Never reuse a number, even after the doc is deleted. |
| `00` is the router | [`00-system-index.md`](00-system-index.md) carries the authoritative table of every core doc. Do not duplicate that table elsewhere. |
| Bands | `01–06` product, UX and design · `07–14` technical standards · `15–16` cross-cutting (security, glossary) · `17–18` meta (this doc and [knowledge capture](18-knowledge-capture.md)) · `19+` appended as topics arise. |
| Intentionally unused | **`09`** — reserved for in-app AI features; Airclone ships none. **`13`** — reserved for localisation/linguistics; the app has no `flutter_localizations` dependency, no `.arb` files and no `supportedLocales`, so UI strings are single-locale English today. Neither number is linked from any index; do not recycle them. If either becomes real, revive that same number. |
| Next free number | `21`. |

---

## 📄 3. The required shape of a doc

```markdown
---
type: "core"                       # core | index | feature | component | logic | backlog
name: "Human Name"
status: "stable"                   # stable | seed | proposed
dependencies: ["08-core-architecture"]   # optional; core docs only
description: "One sentence — this string is copied into index tables."
---

# 🔧 Human Name

One sentence saying what this document is.

**When to read this:** the concrete task that sends someone here.

## 🧩 Body section
…

## Related
[Neighbour](…) · [Neighbour](…) · [Hub](00-system-index.md)
```

| Part | Rule |
| :--- | :--- |
| Frontmatter | `description` is lifted verbatim into indexes — write it to stand alone, not as a fragment. |
| H1 | Emoji + the same words as frontmatter `name`. Emoji headers are the local convention; follow it rather than inventing a new style. |
| Purpose | Exactly one sentence, no preamble, immediately under the H1. |
| **When to read this** | Names a **task**, not a topic. "You are about to add a field to a provider form" — not "about validation". This is the line a low-context agent scans. |
| Body | Terse and factual. Three or more parallel items want a table, not paragraphs. Every behavioural claim links the source file it was checked against. |
| `## Related` | Last section. Neighbouring docs plus the hub, separated by `·`. |

Older core docs end with a `---` rule and a bold `**Related:**` line instead of a `## Related`
heading. Both mean the same thing; new and substantially-edited docs use the heading so the section
is mechanically findable.

---

## 🔗 4. Linking rules

- **One owner per topic.** If another doc owns it, spend one line linking instead of restating it.
  Duplicated prose is how two docs start disagreeing, and the reader cannot tell which copy is stale.
- **Every doc is reachable from a hub** — [`00-system-index.md`](00-system-index.md), its category
  index, or [`dev/README.md`](../../dev/README.md). A doc nothing links to does not exist for an
  agent that navigates rather than greps.
- **Relative links only.** The library is read on disk and on GitHub; absolute paths break both.
- **Do not link removed docs** (`09`, `13` — see §2) or anything under `reference/`.

Get the depth right — this is the single most common breakage:

| Doc lives in | Sibling core doc | App source | `dev/` | Repo root |
| :--- | :--- | :--- | :--- | :--- |
| `wiki/core/` | `08-core-architecture.md` | `../../app/lib/src/state/browser_controller.dart` | `../../dev/plans/…` | `../../AGENT.md` |
| `wiki/features/` (and the other categories) | `../core/08-core-architecture.md` | `../../app/lib/…` | `../../dev/…` | `../../AGENT.md` |
| `dev/` (top level) | `../wiki/core/08-core-architecture.md` | `../app/lib/…` | `./…` | `../AGENT.md` |
| `dev/plans/`, `dev/backlog/`, `dev/logs/` | `../../wiki/core/08-core-architecture.md` | `../../app/lib/…` | `../…` | `../../AGENT.md` |
| Repo root | `wiki/core/08-core-architecture.md` | `app/lib/…` | `dev/…` | `./…` |

**Citing code:** link the file and name the symbol in the sentence —
[`browser_controller.dart`](../../app/lib/src/state/browser_controller.dart). Line numbers drift, so
treat a `file.dart:1225` suffix as a hint inside a dated `dev/` note, never as the identifier a
`wiki/` doc depends on. Files move too: at the time of writing
[`command-console-plan.md`](../../dev/plans/command-console-plan.md) still links
`app/lib/src/rclone/engine_flags.dart`, which now lives at
[`app/lib/src/state/engine_flags.dart`](../../app/lib/src/state/engine_flags.dart).

---

## ➕ 5. Adding, moving, and removing a doc

**Adding**

1. Pick the tree with the placement test (§1); in `wiki/core/` take the next free number and never
   reuse an old one (§2).
2. Write it to the shape in §3.
3. **Register it.** An unregistered doc is invisible to a low-context agent:

   | Kind of doc | Register in |
   | :--- | :--- |
   | `wiki/core/NN-*.md` | the Core Brain table in [`00-system-index.md`](00-system-index.md) |
   | `wiki/features` · `components` · `logic` · `database` | that folder's `*-index.md` table |
   | `dev/plans/*.md` | [`dev/README.md`](../../dev/README.md), plus a row in [`backlog-index.md`](../../dev/backlog/backlog-index.md) when it is roadmap work |
   | `dev/backlog/*.md` | [`backlog-index.md`](../../dev/backlog/backlog-index.md) |
   | A `dev/` runbook | [`dev/README.md`](../../dev/README.md) |
   | `docs/store/*` | [`docs/store/README.md`](../../docs/store/README.md) |
   | Anything that answers a recurring task | a row in the **Task Lookup** table in [`AGENT.md`](../../AGENT.md) |

4. Add it to the `## Related` of the one or two docs nearest it, so it is reachable from more than
   its hub.
5. Run the checks in §7–§8.

**Moving** — grep the old filename and fix every inbound link in the same commit. Renumbering a
`wiki/core/` doc is a last resort (§2).

**Removing** — delete the file, remove its row from every index, remove it from every `## Related`,
then grep the filename to zero hits. A deleted doc that is still linked is worse than one nobody
reads.

---

## 🚫 6. What must never appear in a committed doc

This repository is **public**.

- **No identifiers:** GUIDs of any kind (publisher, tenant, seller, app, subscription), physical
  addresses, D-U-N-S numbers, personal email addresses, infrastructure hostnames, keys or secrets.
  Write `<placeholder>` and name **where the real value lives** — the pattern already used for the
  Store package identity, which CI injects from repository variables (`MSIX_IDENTITY_NAME`,
  `MSIX_PUBLISHER`, `MSIX_DISPLAY_NAME`) rather than from any committed file. See the reminder in
  [`docs/store/README.md`](../../docs/store/README.md) and [Security](15-security.md).
  **Where the real values actually live:** [`dev/secrets/`](../../dev/secrets/README.md) — a
  gitignored, per-developer profile that tooling and agents may read but must never quote from.
  Refer to a value by its KEY NAME in anything committed, never by its value.
- **No `reference/` material** — the gitignored research names third-party projects; keep those names
  out of committed files.
- **No unverified behaviour stated as fact.** If you did not read the code or run the command, either
  drop the claim or mark it "unverified" in the sentence.

---

## ✅ 7. Pre-commit checklist

- [ ] Every behavioural claim was checked against the file I linked (not from memory).
- [ ] The doc has frontmatter, an H1, a one-sentence purpose, **When to read this**, and `## Related`.
- [ ] It is registered in at least one hub/index (§5) and linked from at least one sibling.
- [ ] Nothing is duplicated — anything another doc owns is a link, not a paragraph.
- [ ] No identifiers, secrets, or hostnames; placeholders name where the real value lives (§6).
- [ ] `python tool/check-docs.py` is clean, or the remaining hits are pre-existing and called out in
      the commit message (§8).
- [ ] If a doc was removed or moved, its filename greps to zero stale hits.
- [ ] If the same commit touches `app/`, `dart format` and `flutter analyze` are clean — CI runs both
      and fails on either ([`ci.yml`](../../.github/workflows/ci.yml)).

---

## 🔍 8. The checks are mechanical — run them

All three failure modes in this blueprint are mechanically detectable, so there is a committed linter.
**Run it from the repo root before committing any doc change:**

```bash
python tool/check-docs.py
```

[`tool/check-docs.py`](../../tool/check-docs.py) reports, in one pass:

| Check | What it catches | Why a reader never notices it |
| :--- | :--- | :--- |
| **Broken links** | any `](path)` that does not resolve on disk, **including links into `app/` source** | code moves; the doc still renders fine and the link only fails when someone follows it |
| **Orphans** | a doc no other doc links to | reachable by `grep` but not by navigation — invisible to a low-context agent that starts at a hub |
| **Doc shape** | a `wiki/core/` doc missing an H1, a "When to read this", or a Related section (§3) | the doc exists but gives no entry or exit, so it is a dead end |

It strips fenced blocks and inline code first, so link *examples* — including the skeleton in §3 —
are not reported as broken. Exit code is `0` when clean and `1` on broken links; pass `--strict` to
also fail on orphans and shape violations, and `--quiet` for totals only.

**No CI job runs it yet.** [`ci.yml`](../../.github/workflows/ci.yml) covers format, analyze and tests
against `app/` only, so documentation is enforced by habit and review, not by a gate. The script is
dependency-free and platform-neutral precisely so it can be added to CI when someone wants that.

What it caught on its first run, all invisible from the hub: nine `wiki/core/` documents promised by
[00-system-index.md](00-system-index.md) that did not exist, two stale code paths in
[`command-console-plan.md`](../../dev/plans/command-console-plan.md) (one file moved, one renamed),
and thirteen orphans — among them every store and release runbook, so an agent could not reach
[`windows-signing-and-store.md`](../../dev/windows-signing-and-store.md) by following links at all.

---

## Related

[System Index](00-system-index.md) · [Knowledge Capture](18-knowledge-capture.md) ·
[Directory Structure & Build](04-directory-structure.md) · [Glossary](16-glossary-of-terms.md) ·
[Security](15-security.md) · [dev hub](../../dev/README.md) · [AGENT.md](../../AGENT.md)

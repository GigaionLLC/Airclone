---
type: "core"
name: "Knowledge Capture"
status: "stable"
dependencies: ["17-docs-blueprint"]
description: "Where a hard-won fact goes so it survives: release note vs agent changelog vs plan vs durable invariant vs process runbook, with a decision table."
---

# 🧠 Knowledge Capture

Where something you just learned gets written down, so the next agent — who has none of your context
— finds it *before* repeating the mistake that taught it to you.

**When to read this:** you have just finished a change, a debugging session, a release, or a failed
store submission, and you are deciding what to record and where it belongs.

---

## 🎯 1. Record the failure, not just the rule

A rule on its own reads as an arbitrary constraint. The next agent — simplifying, refactoring, or
"cleaning up" — deletes it in good faith. A rule with its failure attached defends itself: removing
it now means deliberately re-choosing a known outcome.

Every durable note answers four things:

| Field | Why it earns its space |
| :--- | :--- |
| **Symptom** — what was actually observed | Lets the next agent recognise a recurrence instead of debugging it from scratch. |
| **Root cause** — the mechanism | Separates the real rule from the coincidence that looked like one. |
| **The rule** — what must stay true | The thing to obey. |
| **The refuted alternative** — what was tried and did not work, and why | The most valuable line in the note: it is precisely the fix the next agent will reach for first. |

Three examples already in this repo, each worth imitating:

- **At the line you would edit.** The `RCLONE_VERSION` pin in
  [`release.yml`](../../.github/workflows/release.yml) carries not just the version but the
  regression it guards — that `config/create` still requires the `parameters` key on every call
  *including continue steps*, "the regression that cost a Store certification cycle". An agent
  bumping the pin cannot miss it.
- **Next to the process it protects.** [`dev/windows-signing-and-store.md`](../../dev/windows-signing-and-store.md)
  says "Verify the artifact — do NOT trust the green check", and immediately explains why: a
  `continue-on-error` step had hidden a broken bundle across several releases (the fix shipped in
  [v0.5.3](../../dev/releases/v0.5.3.md)). Without the incident, the instruction reads as paranoia
  and gets skipped.
- **Including the fix that was wrong.** The alpha.85 entry in
  [`agent-changelog.md`](../../dev/logs/agent-changelog.md) records that the *first* shortcut fix was
  refuted in review — a matched `CallbackShortcuts` binding consumes the key even when its callback
  does nothing, which left Backspace dead inside text fields. That paragraph is why nobody re-lands
  the appealing-looking version.

---

## 📥 2. Decision table — "I just learned X → it goes HERE"

| What you learned | It goes here | Shape |
| :--- | :--- | :--- |
| A user-visible change shipping under a tag | [`dev/releases/<tag>.md`](../../dev/releases/) | Prose in the user's language. CI publishes it verbatim (§4). |
| What you, the agent, changed this session | [`dev/logs/agent-changelog.md`](../../dev/logs/agent-changelog.md) | The block template in [`AGENT.md`](../../AGENT.md); newest entry at the **top**. |
| A rule the code must keep obeying — concurrency budget, ordering/race invariant, retry policy | [14-performance-standards.md](14-performance-standards.md) | Invariant + the failure that motivated it. |
| A secrets, permissions, or trust-boundary rule | [15-security.md](15-security.md) | Rule + threat it closes. |
| A validation rule, or a new way an error reaches the user | [11-validation-standards.md](11-validation-standards.md) | Tier + surfacing. |
| A formatter, unit, or precision rule | [12-utility-standards.md](12-utility-standards.md) | Helper + its contract. |
| How an outside surface *actually* behaves — an RC method quirk, a MethodChannel contract, an FFI signature, an OS integration | [10-external-integrations.md](10-external-integrations.md) | Observed behaviour + the version it was observed on. |
| A provider, controller, or state shape | [07-state-context.md](07-state-context.md) | Shape + who owns writes. |
| A layer boundary or engine-seam decision | [08-core-architecture.md](08-core-architecture.md) | Decision + what it forbids. |
| A platform/tooling gotcha — signing, store certification, emulator, Gradle/NDK, build scripts | the matching `dev/` runbook: [Windows](../../dev/windows-signing-and-store.md) · [Play](../../dev/google-play-store.md) · [Apple](../../dev/apple-appstore-and-macos.md) · `dev/android/` · `dev/desktop/`, indexed from [`dev/README.md`](../../dev/README.md) | Dated incident + the step that now prevents it. |
| A submission rule that applies to every store | [`docs/store/README.md`](../../docs/store/README.md) | A line in the pre-submission audit. |
| Multi-step work you are about to start | [`dev/plans/`](../../dev/plans/) from [`template-plan.md`](../../dev/plans/template-plan.md) | Live document; archive to [`dev/archive-plans/`](../../dev/archive-plans/README.md) with a row in its README when done. |
| Worth doing, but not now | [`dev/backlog/`](../../dev/backlog/backlog-index.md) | A row in the backlog index, with enough evidence to re-find the problem. |
| A term the team keeps saying | [16-glossary-of-terms.md](16-glossary-of-terms.md) | One-line canonical definition. |
| A rule about the doc library itself | [17-docs-blueprint.md](17-docs-blueprint.md) | Standard + the checklist entry that enforces it. |
| A rule that only makes sense at one line of code | **A comment at that line — *and* the doc row above.** | Both. The comment catches the agent who never opens the wiki. |

---

## 🧾 3. The five artifacts, and why they are not interchangeable

| Artifact | Audience | Lifetime | Read/consumed by | Edited later? |
| :--- | :--- | :--- | :--- | :--- |
| **Release note** `dev/releases/<tag>.md` | End users | Frozen at the tag | CI (§4) and everyone browsing GitHub Releases | No — a shipped tag's note is history |
| **Agent changelog** `dev/logs/agent-changelog.md` | The next agent | Append-only session log | Humans and agents | No — add a new entry instead |
| **Plan** `dev/plans/*.md` | The agent doing the work | Live, then archived | Humans and agents | Continuously, until archived |
| **Durable invariant** `wiki/core/07–16` | Everyone who touches the code | As long as the behaviour holds | Humans and agents | **Yes — rewritten in place** |
| **Process gotcha** `dev/<runbook>.md` | Whoever runs that process next | Grows one incident at a time | The operator | Appended |

The distinction that matters: **`wiki/` is rewritten to stay true; `dev/` is appended to stay
honest.** Never put a dated log entry into the wiki, and never explain the architecture inside a
release note.

**The logs drift; the release notes cannot.** At the time of writing, the newest entry in
`agent-changelog.md` is dated 2026-07-15 and the highest row in
[`version-history.md`](../../dev/logs/version-history.md) is `v0.1.0-beta.1`, while `dev/releases/`
runs to `v0.6.1` — because CI reads the per-tag note and warns loudly when it is missing, whereas
nothing enforces the two logs. Treat the logs as context, not as a complete history; if you find one
behind, add your own entry at the top rather than reconstructing months you did not do.
(`agent-changelog.md` also carries an inherited `<!-- New entries go above this line -->` comment that
is no longer at the top of the file — the operative rule is most-recent-first at the top.)

---

## 🔁 4. What CI does with a release note

Two verified behaviours in [`release.yml`](../../.github/workflows/release.yml) make the release note
a build input rather than decoration:

| Step | Behaviour | Consequence for how you write |
| :--- | :--- | :--- |
| `release` job | Creates the GitHub Release with `--notes-file dev/releases/<tag>.md`. Missing file → falls back to `--generate-notes` **with a warning**. Tags containing `alpha`/`beta`/`rc` are marked pre-release. | Write the note **before** pushing the tag; the file name must match the tag exactly. |
| Android job | Derives the Play "what's new" from the **same file**: drops every line beginning with `#`, `|`, or `---`, deletes blanks, and takes the first **480 characters**. | The opening prose must stand alone as a store blurb. A note that starts with a table or nothing but headings distils to something useless. |

---

## 🔐 5. Public repo — what never goes into any of these

Airclone's repository is public, and every artifact above is committed to it. Never write GUIDs
(publisher, tenant, seller, app, subscription), physical addresses, D-U-N-S numbers, personal email
addresses, infrastructure hostnames, or secrets.

When the fact you learned **is** an identifier, record the **name of the variable or secret that
holds it**, never the value — the pattern already used for the Store package identity, which CI
injects from repository variables (`MSIX_IDENTITY_NAME`, `MSIX_PUBLISHER`, `MSIX_DISPLAY_NAME`) and
which the runbooks refer to by name only. Details in [17 §6](17-docs-blueprint.md) and
[`docs/store/README.md`](../../docs/store/README.md).

---

## ✅ 6. Before you call it done

[`AGENT.md`](../../AGENT.md) owns the mandatory wrap-up protocol (changelog entry · docs sync ·
archive the finished plan) — follow it there. These are the capture-specific additions:

- [ ] Each new rule carries its **symptom, cause, and refuted alternative**, not just the rule.
- [ ] A rule that lives at one line of code also has a comment at that line.
- [ ] Wiki docs whose described behaviour changed were **edited in place**, not appended to.
- [ ] Shipping under a tag? `dev/releases/<tag>.md` exists and opens with plain prose (§4).
- [ ] Anything parked rather than fixed has a backlog row with enough evidence to re-find it.
- [ ] Nothing recorded that must not appear in a public repository (§5).

---

## Related

[Docs Blueprint](17-docs-blueprint.md) · [System Index](00-system-index.md) ·
[Performance Standards](14-performance-standards.md) · [Security](15-security.md) ·
[Directory Structure & Build](04-directory-structure.md) · [dev hub](../../dev/README.md) ·
[Store submissions](../../docs/store/README.md) · [AGENT.md](../../AGENT.md)

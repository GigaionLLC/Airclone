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
Do not guess colors, spacing, or component styles. Airclone uses a strict token-based design system,
and the tokens are Dart, not CSS: `Space`, `Radii` and `AircloneTheme.of(context)` from
`app/lib/src/ui/theme/tokens.dart`, under four OS skins × light/dark. [`DESIGN.md`](DESIGN.md) is the
one-page reference for both.

### 4. 🧱 Architecture & rclone integration: [`wiki/core/08-core-architecture.md`](wiki/core/08-core-architecture.md)
The single most important decision in this project is **how we drive the rclone engine** behind one
`RcloneClient` interface. There are three cases, not two: desktop spawns `rclone rcd` and talks to the
RC HTTP API; Android runs its bundled rclone binary as a jniLib, spawned as a loopback `rcd`; iOS and
the Mac App Store build — neither of which may spawn a subprocess — link `librclone` in-process over
`dart:ffi`, which desktop can also opt into. The decision itself is pure and unit-tested in `resolveEngineMode`
(`app/lib/src/state/engine_mode.dart`); `_resolveEngineMode` in
`app/lib/src/state/engine_controller.dart` supplies what is actually available and calls it;
the doc above owns the explanation. Read it before touching anything that talks to rclone.

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
| Replying to a bug report on a GitHub issue | [Bug-report replies](dev/bug-reports.md) | Plain and short, and close the issue with it. The mechanism goes in the commit message, not the reply |
| Cutting a release | [dev hub](dev/README.md) (Release checklist) | [`dev/releases/`](dev/releases/) — notes must exist **before** the tag |
| Submitting to a store (Microsoft / Play / Apple) | [Store submissions index](docs/store/README.md) | [Windows](dev/windows-signing-and-store.md) · [Play](dev/google-play-store.md) · [Apple/macOS runbook](dev/apple-appstore-and-macos.md) + [Apple current state & traps](dev/apple-handoff.md) |
| Writing, moving, or removing a doc | [Docs Blueprint](wiki/core/17-docs-blueprint.md) | [Knowledge Capture](wiki/core/18-knowledge-capture.md) — then `python tool/check-docs.py`, a CI gate: a broken relative link (into `wiki/`, `dev/`, `docs/` **or** `app/` source) or a control byte fails the build |
| Editing a GitHub Actions workflow | [dev hub → CI workflows](dev/README.md) | `python tool/check-workflows.py` before pushing — an empty GitHub expression anywhere in a `.yml`, **comments included**, invalidates the whole file, and GitHub reports that as a logless run named after the path |
| Checking roadmap / parked items | [Backlog Index](dev/backlog/backlog-index.md) | [Feature Backlog](dev/backlog/feature-backlog.md) |

> **🔒 Reference material:** Deep competitive research and notes that name third-party projects live
> under **`reference/`**, which is **gitignored** and must never be committed. Read it for ideas, but
> keep external-project names out of committed files — cite our own docs in committed code.

> **🔐 Real account values** live in two places, and never in a committed doc:
> - **[`dev/secrets/dev-profile.env`](dev/secrets/README.md)** — store publisher identity, signing
>   profiles, release hosting and other per-developer identifiers. **Gitignored**: it belongs to one
>   builder, so on a fresh clone it will not exist, and that is expected — copy
>   `dev-profile.example.env` and fill in your own.
> - **[`dev/vault/vault.enc`](dev/vault/README.md)** — encrypted and **committed on purpose**, opened
>   with `python tool/vault.py unlock` into the gitignored `dev/vault/notes/`. It holds the Apple /
>   App Store Connect as-built record and the App Review contact, so unlike the file above it survives
>   a clone.
>
> Read either when you genuinely need a real value, but **never copy a PRIVATE or SECRET value into a
> committed file, commit message, doc or store listing** — refer to it by key name (`MSIX_PUBLISHER`),
> never by value.

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
10. **NEVER commit a Microsoft Store submission through the API.** Committing sets the price of this
    product to **0** and publishes it free — it happened on 2026-08-17 with v0.6.8, and once a
    submission reaches *Publishing* it cannot be stopped by anyone, by any means. The listing was
    free for the whole certification cycle of the fix.
    - The *only* supported route is **`mode: stage`**, then press **Submit for certification** in
      Partner Center, which re-derives pricing from the pricing module.
      [`tool/store_submit.py`](tool/store_submit.py) now refuses `--commit` for a product on the
      advanced pricing model — **do not remove that guard** to "unblock" a release.
    - The `pricing.priceId` the API returns (`Base`) is a legacy projection it will not accept back.
      Every writable payload reads back as `Free`. That is expected on a *staged draft* and harmless;
      it is only fatal at commit. Full account: [`dev/msstore-ci-setup.md`](dev/msstore-ci-setup.md).
11. **Partner Center is the authority on pricing and availability — never the API JSON, never a
    module's status label.** When touching a Store submission:
    - **Re-load the page and re-read the value** after saving. *Save draft* gives no confirmation,
      and a click that lands on the nav overlay silently does nothing — two saves were lost that way.
    - **Use a viewport ≥ 1400px wide.** Below that, Partner Center overlays its nav on the content,
      controls stop responding, and modules render blank. Every "this page is broken" moment in this
      repo has been a too-narrow window.
    - A module label of *Unchanged* tracks **module configuration**, not uploaded binaries — a new
      MSIX shows "Packages: Unchanged". Do not read it as "nothing happened".
12. **Never print non-ASCII from a `tool/` script.** GitHub's Windows runners give Python a **cp1252**
    stdout; an em dash survives, an arrow (`→`) raises `UnicodeEncodeError` and kills the process —
    in the v0.6.8 run, *after* it had already created a Store submission, leaving a draft behind.
    Scripts reconfigure stdout to UTF-8 defensively, but keep printed strings ASCII anyway: a
    cosmetic character must never be able to abort a job mid-side-effect.
13. **When a later finding contradicts an earlier alarm, find the variable that differs before
    deciding which was wrong.** On 2026-08-17 a staged draft showed $1.49 while a committed
    submission showed $0; both observations were correct, and the difference was *stage vs commit*.
    Concluding "the earlier alarm was a false positive" without isolating that variable is what
    published the app for free. A contradiction is evidence of a missing variable, not of a mistake.
14. **A green audit is only evidence for the checks it actually performs.** Rule 9 distrusts a step
    that reports success; this one distrusts the *checker*. Apple refused both 0.7.5 submissions for a
    missing per-version `whatsNew` minutes after a dry run of the submit workflow printed **"No
    gaps"** — one hole on each side: the listing script never sent the field, and the audit never
    looked for it. When an external system refuses something your audit passed, the audit is part of
    the defect: **add the missing check in the same change as the fix**, or the next release spends
    another submission cycle learning it again. Account:
    [`dev/apple-handoff.md`](dev/apple-handoff.md).

15. **A comment that states an invariant is not the invariant.** `http_rclone_client.dart` explained
    that user flags go FIRST because rclone lets the last occurrence of a repeated flag win, "so the
    rc listener stays loopback-bound no matter what a user pastes". Last-wins beats a *repeat* of the
    same flag. It does nothing about a *different* flag reaching the same behaviour, and
    `--rc-no-auth` has no later flag that undoes it — so the protection described had never existed.
    The defence is now a denylist (`kRefusedEngineFlags`), and the comment says what ordering
    actually buys. When a comment claims something is safe, find the code that makes it safe; if you
    cannot point at it, it is not.
    - Corollary, learned the same hour: **hardening belongs where the policy applies, not in the
      shared helper.** Putting that denylist inside `parseEngineFlags` — the quote-aware tokenizer
      the command console also uses — blinded the console's own safety classifier, because it must be
      able to *see* a dangerous flag in order to refuse it. Two console tests caught it. A tokenizer
      tokenizes.
16. **A secret in argv is a secret you published.** `rcd` was started with `--rc-pass <password>` on
    its command line, which `ps -ef` and `Win32_Process` show to every other account on the machine —
    and rclone's own docs equate rc access to shell access as the user running it. It travels as
    `RCLONE_RC_PASS` now, the same route `RCLONE_CONFIG_PASS` already used two lines below it, which
    is what made it an oversight rather than a trade-off. Every credential reaching a subprocess goes
    through `environment:`, never through an argument.
17. **A library's default is a policy, not an absence.** `Player()` with no configuration is not
    "no protocol whitelist" — media_kit ships one that includes `file`, and hardcodes
    `allowed_extensions=ALL` beside it, which disables the check in ffmpeg's `hls.c` that would
    otherwise refuse a segment with no media extension. Between them, a crafted `.m3u8` could open an
    arbitrary local path. Before writing "there is no X configured", read the dependency's source and
    find out what X defaults to.
    - Second half of the same lesson: **guarding your input does not guard what the library does
      next.** `ObjectRef.sendableHeaders` correctly refuses to send engine credentials to a
      non-loopback URL, and survived an adversarial attempt to defeat it. It is still insufficient,
      because media_kit maps headers onto mpv's *global* `http-header-fields`, which mpv replays on
      every segment a manifest names. The boundary only ever saw the top-level URL. Credentials now
      ride in the URL, where the thing making the requests scopes them.
18. **Code you generate can contain characters you cannot see.** A redaction rule added in a shell
    heredoc silently matched nothing for an hour: `\b` had become a literal **backspace byte (0x08)**
    inside the regex. It compiled, `flutter analyze` passed, the tests around it passed, and a
    security rule did nothing. Found with `cat -A`. When a change that looks obviously correct has no
    effect, check the bytes before rewriting the logic — and prefer writing tricky literals to a file
    with a quoted heredoc over threading them through another layer of escaping.

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
`dev/archive-plans/[plan].md` — read [`dev/archive-plans/README.md`](dev/archive-plans/README.md)
first. Source files and CI messages cite plans by path *and* by section number, so a bare `git mv`
dangles a pointer: sweep the inbound references in the same commit as the move.

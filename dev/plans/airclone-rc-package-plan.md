# 📦 Parcel Plan: `airclone_rc` in-repo package (Airclone v0.20.0)

## 📊 State Dashboard
| Metric | Value |
| :--- | :--- |
| **Status** | `PROPOSED` |
| **Version** | `v0.20.0` (the split) · typed API and pub.dev publishing follow |
| **Active Persona** | `Architect` |
| **Last Updated** | 2026-09-19 |

> Prompted by [GigaionLLC/Airclone#6](https://github.com/GigaionLLC/Airclone/issues/6)
> ("RcloneClient as package on pub.dev?"). **#6 stays open for the life of this plan, and we
> reply on it at every milestone.** See "Keeping #6 informed" in Phase 4. Related:
> `wiki/core/08-core-architecture.md` (the "one seam" this package becomes),
> [flathub-plan.md](flathub-plan.md) (lockfile consumer).
>
> **Priority:** Airclone comes first; this is a secondary project. The public reply on #6
> (2026-09-19) promised no timeline and named no version.

---

## 1️⃣ Phase 1: Expansion & Scoping
* **Intent:** Move the rclone transport layer (`RcloneClient`, the HTTP and FFI engines, and
  the rclone wire models) into a pure-Dart package, `airclone_rc`, at `packages/airclone_rc/`,
  **in this repo**. The app consumes it through a path dependency. v0.20.0 ships that split
  with **no user-visible behaviour change**. After a working proof of concept comes a typed
  API over `rpc`, which the app adopts gradually, and publishing to pub.dev when we choose.
* **Decisions already made (2026-09-19):**
  - **Name: `airclone_rc`.** In rclone's own vocabulary "rc" is the remote-control API
    (`rclone rc`, `rclone rcd`), which is exactly what this package drives. It also keeps
    "rclone" out of the package name, so it cannot be mistaken for an official rclone
    project. Describing it as working *with* rclone in the README is fine.
  - Monorepo, not a second repo. Fixes that touch both sides stay one commit. Of the 41
    commits that ever touched `app/lib/src/rclone/`, 32 also changed app code.
  - Plain path dependency, not a pub workspace. A workspace moves `pubspec.lock` to the
    repo root, which would touch 12 workflows using `working-directory: app` and the
    Flathub plan, which reads `app/pubspec.lock`.
  - **AGPLv3** for the package, same as the app.
  - **Consumers supply their own rclone binary or librclone.** The package ships no
    native code.
  - **Typed API comes after the proof of concept**, as a purely additive layer (see
    Milestone B, "Why deferring it costs nothing").
  - **Pure Dart package** (no `package:flutter` dependency). It runs in any Dart program,
    and Airclone consumes it like `http` or `crypto`. See Phase 3 for the reasoning.
* **In Scope (v0.20.0, Milestone A):**
  - Decouple the layer from app internals (≈10 call sites), in place, before moving anything.
  - Scaffold the package, `git mv` the files, rewrite imports, move the package's own tests.
  - Every CI, workflow and doc fix the move needs, **in the same step as the move**.
  - A go/no-go proof-of-concept checkpoint before anything reaches `main`.
* **Out of Scope (v0.20.0):**
  - The typed API (Milestone B) and publishing to pub.dev (Milestone C; `publish_to: none`
    until then).
  - Shipping librclone or rclone binaries in the package.
  - `RcloneEngine` (binary discovery, download and Store rules) and `WebRcloneClient`
    (Airclone's own Web UI server). Both are Airclone product logic and stay in the app.
  - Changing the app's own RC call sites.
  - A separate repo, a pub workspace, relicensing.

## 2️⃣ Phase 2: Requirements & Context (audit, 2026-09-19)

### What moves and what stays
| File | Lines | Decision | Why |
| :--- | ---: | :--- | :--- |
| `rclone/rclone_client.dart` | 177 | **move** | the interface, `ObjectUploader`, `ObjectRef`, `RcloneException`, `EngineStatus` |
| `rclone/http_rclone_client.dart` | 839 | **move** | spawns and drives `rclone rcd` |
| `rclone/ffi_rclone_client.dart` | 218 | **move** | in-process librclone |
| `rclone/librclone_ffi{,_io,_web}.dart` | 494 | **move** | FFI bindings; conditional export keeps the web build compiling |
| `rclone/librclone_object_server.dart` | 344 | **move** | loopback byte bridge for FFI previews |
| `rclone/windows_child_job{,_io,_web}.dart` | 223 | **move** | the HTTP engine needs it; the app also uses it (`archive_service`, `config_transfer_controller`), so it is exported |
| `models/rclone_file, provider, mount_info, serve_server, transfer_item, transferred_item` | 435 | **move** | pure rclone wire shapes (`fromJson` of RC responses) |
| `rclone/rclone_engine.dart` | 527 | **stay** | binary discovery and download, Store/MAS/Flatpak rules, `path_provider`, `flutter/services` |
| `rclone/web_rclone_client.dart` | 208 | **stay** | talks to Airclone's Web UI server (CSRF header, session expiry, `cloud_placeholder`) |
| `models/job.dart` | 141 | **stay** | the app's job queue (`JobType.archive`, `etaLabel`), not an rclone shape |
| `models/remote.dart` | 96 | **stay** | includes the synthetic local-disk location and the `copy_links` listing rule |
| `models/mount_options.dart` | 225 | **stay** | Airclone's opinionated mount defaults (the Explorer-freeze fix) |

About 2,730 lines move. The remaining files import the package (`job` → `transfer_item`,
`mount_options` → `mount_info`, `web_rclone_client` → `rclone_client`).

### What the moving files reach back into the app for (the whole list)
| Dependency | Call sites | Replacement |
| :--- | :--- | :--- |
| `state/diagnostics.dart` `logDiagnostic` | http ×3, object server ×1 | injected `RcloneLogSink`; the app passes an adapter to `logDiagnostic` |
| `flutter/foundation` `kDebugMode` | http ×1 (echo every engine line) | `echoEngineLines` constructor flag, default **false**; the app passes `kDebugMode` |
| `state/undecryptable_names.dart` `noteUndecryptableName` | http ×1 | `onUndecryptableName` callback |
| `state/host_platform.dart` | http ×2 (`isAndroid`), object server ×2 (`pathSeparator`) | package-private copy of those getters, same `kIsWeb` guard |
| `state/media_formats.dart` `isPlaylistExt` | ffi ×1 (path-shaped URL for HLS) | move `kPlaylistExts`/`isPlaylistExt` into the package; `media_formats` imports them back (one source of truth) |
| `flutter/foundation` `@immutable`, `@visibleForTesting` | models ×11, http | `package:meta` |
| Hardcoded `airclone_rcd_<pid>.pid` / `airclone_rcd.lock` | http (reaper) | **required** `instanceTag` (see R2) |

Nothing else. `native_probes`, `build_flavor`, `cloud_placeholder` and `webui_protocol` are
only used by files that stay.

### Blast radius
- 56 app `lib/` files and 49 of 181 test files import a moving file.
- 24 test fakes `implements RcloneClient`. They keep working as long as the interface never
  grows (rule P2).
- 6 tests exercise package internals and move with it: `engine_log_test`,
  `rcd_reaping_multi_instance_test`, `rc_retry_test`, `object_path_route_test`,
  `ffi_rclone_client_test`, `librclone_integration_test`. `undecryptable_names_test` stays
  (it is a UI test) and uses the public `isUndecryptableNameLine` export.
- Docs: 48 markdown links in 20 files point into `app/lib/src/rclone/`.
- Workflows: `librclone.yml`, `ios-verify.yml` and `mas-verify.yml` have `paths:` filters on
  the moving files.

### Relevant docs
- `wiki/core/08-core-architecture.md` → the seam's design; gets a "package boundary" section.
- `dev/plans/flathub-plan.md` → flatpak-flutter builds offline sources from `pubspec.lock`.
- `dev/plans/webui-plan.md` §"Stage A" → why the conditional exports exist.

## 3️⃣ Phase 3: User Clarification
* **Open Questions:**
  - `[x]` Package name → **Answer:** `airclone_rc` (2026-09-19). Unclaimed on pub.dev that
    day, but pub.dev cannot reserve a name without publishing.
  - `[x]` Typed API timing → **Answer:** after a working proof of concept, as an additive
    layer (Milestone B).
  - `[x]` Pure Dart or Flutter package → **Answer:** pure Dart (2026-09-19). The layer
    draws nothing; its only Flutter uses are `kDebugMode` (becomes `echoEngineLines`),
    `@immutable`/`@visibleForTesting` (really `package:meta`, which Flutter re-exports) and
    `flutter_test` in 6 moved tests (becomes `package:test`). Airclone uses it exactly as it
    uses `http` and `crypto` today. Anyone can use it, Flutter or not. The package physically
    cannot import UI code, and converting to a Flutter package later stays easy (the reverse
    would not). Flutter-only plugins (`path_provider` and the like) stay in the app; if ever
    needed, they go in a companion package (e.g. `airclone_rc_flutter`) layered on top.
  - `[ ]` When to reply on #6, and whether to reply before or after v0.20.0 lands.
    → **Answer:**
* **Note on AGPLv3 (for the README and the #6 reply; not legal advice):** an app that uses
  the package must be distributed under AGPL-compatible terms, with its source offered to its
  users, including users who interact with it over a network. It does not oblige anyone to
  send code to Gigaion. Third parties shipping AGPL code they do not hold copyright to on
  Apple's App Store face a known licence conflict. Airclone does not, because Gigaion holds
  the copyright.

## 4️⃣ Phase 4: Detailed Execution Plan

### Principles (these go into `wiki/core/08` when the work lands)
- **P1. The package never imports the app, or Flutter.** `packages/airclone_rc/lib` imports
  only `dart:*`, `http`, `ffi`, `crypto` and `meta`. Its `pubspec.yaml` has no
  `flutter:` SDK dependency, so an accidental `package:flutter` import fails
  `dart pub get`/`dart analyze` outright. A CI step also proves no app imports (A2.7).
- **P2. `RcloneClient` never grows.** New abilities become separate capability interfaces
  (`ObjectUploader` is the precedent), and the typed API is a facade over `rpc`. Widening the
  interface breaks 24 fakes here and every outside implementer.
- **P3. The log sink only ever receives filtered lines.** The release filter (failure lines
  only, de-duplicated, capped at 100 per session) stays inside the package, because at
  `-vv`/`--dump` rclone echoes request headers that carry the rc credentials. Airclone still
  redacts again at ingest in `logDiagnostic`.
- **P4. Each step is green on its own:** analyze clean, format clean, same tests passing.
- **P5. No step opens a risk that a later step closes.** Every fix lands in the same step as
  the change that would otherwise break it (see the "Closed in" column of the risk register).
  All of Milestone A happens on a branch; `main` sees it only as one merge after the
  checkpoint.

### Milestone A: the split (v0.20.0)

**A0. Baseline.** Branch `refactor/airclone-rc-package` from `main`. Record the passing test
count, confirm `flutter analyze` is clean, and save `app/pubspec.lock`. Make sure the last
`librclone.yml`, `ios-verify.yml` and `mas-verify.yml` runs on `main` are green, so later
failures can be attributed.

**A1. Decouple in place (files still under `app/lib/src/rclone/`).** One commit per item.
Behaviour must stay identical.
1. `RcloneLogSink` (`void Function(RcloneLogLevel level, String area, String message)`),
   defaulting to a no-op. `HttpRcloneClient`, `FfiRcloneClient` and `LibrcloneObjectServer`
   take it. `engine_controller._startWith` passes an adapter to `logDiagnostic`. The
   filter, cap and "undecryptable, once per session" logic stay where they are.
   *(closes R4 together with item 8)*
2. `echoEngineLines` replaces `kDebugMode` in `_onEngineLine`. The app passes `kDebugMode`.
3. `onUndecryptableName` replaces the direct `noteUndecryptableName()` call.
4. `instanceTag` (required) builds the marker and lock names and the reaper's prefix match.
   The app passes `'airclone'`, which produces **byte-identical** names, so the first
   v0.20.0 launch still reaps an orphan left by v0.13.x. The rc username and the multipart
   boundary use it too, so the wire traffic is unchanged. *(closes R2)*
5. Package-private `platform.dart` (`isAndroid`, `pathSeparator`) replaces `HostPlatform`
   in the moving files. Its web guard is
   `const bool.fromEnvironment('dart.library.js_interop')`, which is exactly how Flutter
   defines `kIsWeb` in 3.47.0, so behaviour is identical without importing Flutter.
   `rclone_engine.dart` keeps using `HostPlatform`.
6. Move `kPlaylistExts` and `isPlaylistExt` next to the object server. `media_formats.dart`
   imports them.
7. `@immutable` and `@visibleForTesting` come from `package:meta`. Add `meta` to
   `app/pubspec.yaml` at the version the lock already resolves, or
   `depend_on_referenced_packages` fires.
8. **New app test:** an `HttpRcloneClient` failure line reaches the diagnostics ring through
   the sink and comes out redacted. This pins the "redact at ingest" invariant across the
   boundary.

*Gate:* `grep -E "\.\./(state|native|webui|ui)/|package:flutter"` over the moving files
returns nothing, and all tests pass unchanged apart from the new constructor arguments.

**A2. Create the package and move, with every dependent fix in the same commit.**
"Pure move" here means **no logic edits**. Import lines, config and doc links change in the
same commit because they would be broken without it.
1. Add `packages/airclone_rc/` as a **pure Dart** package: `pubspec.yaml` with
   `name: airclone_rc`, `publish_to: none`, version `0.1.0`, an `environment: sdk:`
   constraint matching the app's (`^3.12.0`) and **no `flutter:` SDK entry**; dependencies
   `http`/`ffi`/`crypto`/`meta` at the app lock's versions; dev dependencies `test` and
   `flutter_lints` (itself a pure Dart package, so the rule set matches the app's exactly).
   Also `analysis_options.yaml` (same rules as the app), `LICENSE` (a copy of the repo's
   AGPLv3), `README.md`
   (unofficial, works with rclone, bring your own rclone/librclone, the AGPL note, the P2/P3
   rules) and `CHANGELOG.md`.
2. `git mv` the files from the table into `packages/airclone_rc/lib/src/` and keep their
   names. Their relative imports among themselves stay valid.
3. Add a barrel `lib/airclone_rc.dart` that exports the public surface and keeps the
   `dart.library.js_interop` conditional exports *(closes R6)*. It must export
   **everything the app and its tests use**, because `implementation_imports` (in
   `flutter_lints`) flags `package:airclone_rc/src/…` and CI fails on any info-level lint
   *(closes R7)*.
4. Add `airclone_rc: { path: ../packages/airclone_rc }` to `app/pubspec.yaml`. Rewrite the
   imports in 56 lib files, 49 test files and the 3 remaining rclone-layer files to
   `package:airclone_rc/airclone_rc.dart`. This is mechanical and scripted.
5. Move the 6 internal tests into `packages/airclone_rc/test/`, switching
   `package:flutter_test/flutter_test.dart` → `package:test/test.dart` (import lines only;
   `test`, `group` and `expect` are the same API). Verified 2026-09-19: none of the 6 uses
   `testWidgets`, `WidgetTester`, `TestWidgetsFlutterBinding` or any `package:flutter/`
   import.
6. **Workflow path filters:** repoint `librclone.yml` (lines 21–24), `ios-verify.yml`
   (line 42) and `mas-verify.yml` (line 38) to the new locations, and add
   `packages/airclone_rc/**`. `mas-verify.yml` line 37 (`rclone_engine.dart`) stays.
   `librclone.yml` runs the integration test from the package directory and keeps the
   `AIRCLONE_LIBRCLONE` environment variable name. *(closes R1)*
7. **Package CI job in `ci.yml`,** with explicit `working-directory: packages/airclone_rc`
   (the file defaults to `app`). It runs `dart pub get`,
   `dart format --output=none --set-exit-if-changed .`, `dart analyze --fatal-infos` and
   `dart test`. Add a P1 guard step that fails if anything under `packages/airclone_rc/lib`
   imports `package:airclone/`. **Keep the trailing slash**: without it the guard matches the
   package's own `package:airclone_rc/` imports. *(closes R3)*
8. **Doc links:** repoint the 48 links (20 files) so `python tool/check-docs.py` passes, and
   update the path comment in `dev/ios/librclone_ios.go`. *(closes R8)*

*Gate:* the `app/pubspec.lock` diff **only adds** the `airclone_rc` path entry, with no
version changes *(closes R5)*. App tests plus package tests equal the A0 count. Both analyze
clean, and `check-docs.py` reports no broken links. Git sees the files as renames, so
`git log --follow` and blame survive *(closes R10)*.

**A3. Proof-of-concept checkpoint (go/no-go).** On the branch, before anything merges:
- `ci.yml` green (app and package jobs), `check-docs.py` clean.
- Manual dispatch of `librclone.yml` and `mas-verify.yml` on the branch: the FFI engine and
  the sandboxed build still work.
- Desktop smoke: start the engine, list, copy, preview, kill the app hard and relaunch
  (orphan reaped).
- **Go:** continue to A4. **No-go:** delete the branch. `main` never changed, and the A1
  decoupling commits can still be cherry-picked on their own merits.

**A4. Remaining verification and docs.**
1. `flutter build web --no-web-resources-cdn` compiles (confirms R6).
2. Flathub: confirm flatpak-flutter tolerates a `source: path` entry in `pubspec.lock`.
   Record the result in `flathub-plan.md`. (Flathub AI policy applies: we verify locally and
   the human opens anything upstream.) *(closes R9)*
3. `wiki/core/08-core-architecture.md`: add a "Package boundary" section covering P1–P5 and
   the move/stay table. Add pointers in `AGENT.md`, and move this plan's row in
   `dev/backlog/backlog-index.md` (added 2026-09-19) to `IN PROGRESS`.
4. Merge the branch to `main` as one PR.

**A5. Release v0.20.0.** Version `0.20.0+N`. Write `dev/releases/v0.20.0.md` ("internal
restructuring; no user-visible change"). Run the full platform matrix and **verify by
artifact, not by the green check** (the v0.5.0–v0.5.2 bundling lesson). Run the Phase 8 smoke
matrix.

**Estimate:** 3–5 working days, dominated by per-platform verification rather than code.

### Milestone B: typed API (after the proof of concept, one namespace per PR)
```dart
final rc = RcApi(client);                          // any RcloneClient, including test fakes
final files = await rc.operations.list('gdrive:', 'papers');   // List<RcloneFile>
final remotes = await rc.config.listRemotes();                 // List<String>
final job = await rc.sync.copy(src, dst, options: const RcOptions(async: true)); // AsyncJob
final status = await rc.job.status(job.id);
await client.rpc('backend/command', {...});        // the raw call always stays available
```

**Why deferring it costs nothing.** The typed API is a new class that *calls* `rpc`; it
changes nothing that already exists.
- `RcloneClient`, `rpc`'s signature and the 24 fakes are untouched (P2). A fake that
  answers `rpc('operations/list')` automatically answers `rc.operations.list(...)`.
- The return types (`RcloneFile`, `RcloneProvider`, `MountInfo`, …) move in Milestone A, so
  they are already in the package, waiting.
- Raw `rpc` calls and typed calls coexist indefinitely, so the app migrates at its own pace
  and nothing forces a big-bang switch.
- Milestone C publishes only after B1. The first public version therefore already includes
  the typed API, and no public API has to break to add it.

**What Milestone A must not do, to keep B easy:** widen `RcloneClient`; move app models
(`Job`, `Remote`, `MountOptions`) into the package; or add Airclone-specific behaviour to
the wire models. The plan above does none of these.

- **B1. Foundation:** the `RcApi` facade and `RcOptions` (`_async`, `_group`, `_config`,
  `_filter`). Every method takes an `extra` params map merged last, so migrating a call site
  can never drop a knob. Examples: the `copy_links` listing fix (v0.13.2) and per-call
  `_config`.
- **B2. Golden-params tests:** for every typed method, a recording fake asserts the **exact
  method string and params map** sent. This is what makes each migration provably
  behaviour-preserving.
- **B3. Namespaces, ordered by app usage** (56 distinct RC methods across 37 files):
  `operations` (list ×21, stat, copyfile, movefile, deletefile, mkdir, about, fsinfo, …) →
  `core` (version ×9, stats, transferred, bwlimit) → `job` → `config` → `sync` → `mount` →
  `serve` → `vfs`/`options`.
- **B4. Encode known RC gotchas once**, in the method that owns them. For example,
  `config/create` and `config/update` need `parameters` on continue steps, or answering any
  provider question returns 400 (the v0.5.6 certification bug).
- **B5. Migrate app call sites** one namespace per PR, touching call sites only.
- **Stays raw by design:** `core/command` (the console and its policy), the console's
  argv→RC translator, and the Web UI server's RC allowlist.

### Milestone C: publish to pub.dev (when chosen)

**Prepared 2026-09-20. Everything that can be done without an account is done; what is left
needs a person, and is listed at the end of this section.**

- Preconditions: **all met.** B1 plus the `operations`, `core`, `job` and `config`
  namespaces done (all eight namespaces, in fact); an `example/` that runs against both
  engines; dartdoc building with **0 warnings** (three references to app classes survived the
  move and were dangling — a pub.dev reader would have hit them); `dart pub publish
  --dry-run` clean apart from the "uncommitted changes" notice a working tree produces.
- Hardening for outside users: the sink defaults to a no-op; the package redacts **its own
  session's** rc credentials from lines before handing them to any sink (outside sinks won't
  redact); `instanceTag` is required (R2).
- Automated publishing from GitHub Actions (OIDC) on tags matching
  `airclone_rc-v{{version}}`. That pattern does not match `release.yml`'s `v*`.
  **Written: [`publish-airclone-rc.yml`](../../.github/workflows/publish-airclone-rc.yml).**
  It re-runs format, analyze, tests and a zero-warning dartdoc build before it publishes,
  checks the tag against the pubspec version, and publishes only on a tag — a manual dispatch
  validates and stops, so the workflow can be exercised without consequence. There is no API
  key in it or in the repository's secrets: pub.dev verifies a short-lived OIDC token instead,
  which is what makes step 1 below load-bearing.
- Package versions are independent of the app, and stay `0.x` until the API settles.
- **Publishing is effectively permanent** (pub.dev versions can be retracted but not
  deleted). Configuring pub.dev and the first publish are the maintainer's actions.

#### What only the maintainer can do

1. **Claim the package name and enable automated publishing on pub.dev.** On the package's
   admin page, allow publishing from GitHub Actions for `GigaionLLC/Airclone` with the tag
   pattern `airclone_rc-v{{version}}`. This is the step that makes the workflow's OIDC token
   acceptable; nothing in this repository can do it, and nothing in this repository needs a
   secret once it is done.
2. **Remove `publish_to: none`** from `packages/airclone_rc/pubspec.yaml`. It is the guard
   that makes an accidental publish impossible, so it stays until step 1 is done. The
   workflow checks for it and stops with that explanation rather than failing obscurely.
3. **Decide the first version.** The package is at `0.1.0` and its version is independent of
   the app's. It stays `0.x` until the API settles.
4. **Tag it**: `airclone_rc-v0.1.0` (or whatever step 3 chose). That tag is the point of no
   return — everything before it is reversible, and the version it publishes can be retracted
   but never replaced.

A dry run costs nothing and needs none of the above: dispatch the workflow manually and it
validates the package and stops.

### Keeping #6 informed
[#6](https://github.com/GigaionLLC/Airclone/issues/6) stays **open** until the package is on
pub.dev. Each milestone below gets a short reply there. Every reply is drafted first and
posted only after the maintainer approves the wording. Record each one in the table.

| # | When | Say | Posted |
| :--- | :--- | :--- | :--- |
| 0 | Plan agreed | We'll do it: `airclone_rc`, pure Dart, AGPLv3, bring your own rclone; Airclone first, no timeline | 2026-09-19 ([comment](https://github.com/GigaionLLC/Airclone/issues/6#issuecomment-5744557750)) |
| 1 | Work starts (A0) | The split is under way | superseded — the work finished before a reply was approved, so it folds into update 2 |
| 2 | A4 merged to `main` | The package is in the repo; the git-dependency snippet now works; link to its README | 2026-09-20 ([comment](https://github.com/GigaionLLC/Airclone/issues/6#issuecomment-5754014996)) — posted as an AI-written progress report, labelled as one at the top |
| 3 | A5 released | Airclone v0.20.0 ships on the package | folded into update 2, which was posted after the release |
| 4 | B1–B2 land | The typed API foundation exists; ask for feedback on its shape | folded into update 2, which asks for exactly that — and says why now: a published API can be retracted, never replaced |
| 5 | C published | On pub.dev with a link; **close #6** | `[ ]` |

If the plan stalls or the A3 checkpoint is a no-go, say so on #6 as well, instead of going
quiet.

## 5️⃣ Phase 5: Product Owner Review
* **Status:** `PENDING`
* **Risk register (audit).** "Silent" means nothing fails; you just stop being protected.
  Per P5, each risk is closed in the step that would otherwise open it.

| # | Risk | Silent / Loud | Closed in |
| :--- | :--- | :--- | :--- |
| R1 | Workflow `paths:` filters still name `app/lib/src/rclone/…`, so FFI changes stop triggering `librclone`/`ios-verify`/`mas-verify` | **Silent** | A2.6, same commit as the move |
| R2 | Another app using the package with the same `airclone_rcd_*` names takes the reap lock and **SIGKILLs Airclone's live `rcd`** | **Silent** | A1.4, before the move: `instanceTag` required, no default; the app passes `'airclone'` |
| R3 | `ci.yml` formats and analyzes only `app/`, so package code escapes the gates | **Silent** | A2.7, same commit as the move |
| R4 | Engine lines stop reaching diagnostics, or reach them unredacted | **Silent** | A1.1 plus the A1.8 test |
| R5 | The move accidentally changes dependency versions | **Silent** | A2 gate: the lock diff only adds the path entry |
| R6 | The web UI build breaks on `dart:ffi` | Loud | A2.3 keeps the conditional exports; A4.1 confirms |
| R7 | `implementation_imports`, `depend_on_referenced_packages` or `invalid_use_of_visible_for_testing_member` infos fail CI | Loud | A1.7 (`meta`) and A2.3 (complete barrel) |
| R8 | Broken doc links fail the `docs` job | Loud | A2.8, same commit as the move |
| R9 | flatpak-flutter chokes on a path dependency | Loud (Flathub build) | A4.2, before release |
| R10 | Losing file history on the move | — | A2 as `git mv` renames with no logic edits |

## 6️⃣ Phase 6: Senior Dev Hygiene Review
* **Status:** `PENDING`
* **Findings:**
  - ⚠️ **Secret Management:** rc credentials are per-session and never persisted (unchanged).
    P3 keeps credential-bearing lines out of the sink. C adds package-side redaction.
  - ✅ **Abstraction & Architecture:** follows the existing seam; P2 protects the fakes.
  - ✅ **Error Handling:** `RcloneException` and `LibrcloneFfiException` move unchanged.
  - ✅ **Technical Debt & Deletion:** nothing duplicated; `isPlaylistExt` gets a single home.
* **Required Fixes:** None yet.

## 7️⃣ Phase 7: Implementation Checklist (Execution)
- `[x]` #6 update 0: plan agreed (2026-09-19)
- `[x]` A0 branch and baseline recorded (2026-09-19) · #6 update 1 folded into update 2
- `[x]` A1.1–A1.8 decoupling, one commit each, all green
- `[x]` A2 package, move, imports, tests, path filters, CI job, doc links (one commit); lock diff = one path entry
- `[x]` A3 proof-of-concept checkpoint → **go** (2026-09-20)
- `[x]` A4 web build, Flathub check, boundary docs, merge — PR #7, rebase-merged 2026-09-20 · #6 update 2 drafted
- `[ ]` A5 v0.20.0 release notes, matrix, artifacts verified · #6 update 3
- `[x]` B1–B2 typed API foundation and golden tests — PR #8 · #6 update 4 folded into update 2
- `[x]` B3–B5 namespaces migrated — PR #8: job, mount/serve/vfs, core/config, operations, then list
- `[ ]` C publish decision · #6 update 5, close #6

## 8️⃣ Phase 8: Verification Dashboard
* **Verification Status:** `PASSED` — A and B merged 2026-09-20. Beyond the commands below,
  the app itself is now checked against a real engine on every relevant PR:
  `app/integration_test/typed_engine_smoke_test.dart`, run by
  `.github/workflows/windows-runner.yml` on a windows-latest runner.
* **Commands:**
  - `cd app && flutter pub get && dart format --output=none --set-exit-if-changed . && flutter analyze && flutter test`
  - `cd packages/airclone_rc && dart pub get && dart format --output=none --set-exit-if-changed . && dart analyze --fatal-infos && dart test`
  - `python tool/check-docs.py`
  - `cd app && flutter build web --no-web-resources-cdn`
  - Manual dispatch of `librclone.yml`, `ios-verify.yml`, `mas-verify.yml`
* **Smoke matrix (real builds):**
  - `[ ]` Desktop, HTTP engine: start, list, copy, preview, upload, command console streaming
  - `[ ]` In-process FFI engine: start, list, image/video preview via the object server, HLS path-shaped URL
  - `[ ]` Android: start, list, thumbnails, preview
  - `[ ]` Kill the app hard, relaunch: orphan `rcd` reaped (marker path); on Windows, no orphan survives (job object)
  - `[ ]` Two instances at once: neither kills the other's engine
  - `[ ]` Crypt with a wrong `password2`: undecryptable hint appears, diagnostics has one warning line
  - `[ ]` Diagnostics export: engine ERROR lines present and redacted
  - `[ ]` Web UI: loads and lists through `WebRcloneClient`

## 9️⃣ Phase 9: User Verification
* **Status:** `PENDING`
* **User Feedback:**

## 🔟 Phase 10: Wrap Up & Archival
* **System Context Updates:** the package boundary rules (P1–P5) go into `wiki/core/08`, and
  the move/stay table goes into the package README.

## ✅ Completion Note
<!-- Added during wrap-up. Describe actual outcome and any deviations from the original plan. -->

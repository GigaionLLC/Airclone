---
type: "core"
name: "Validation Standards"
status: "stable"
dependencies: ["08-core-architecture", "07-state-context", "15-security"]
description: "Where Airclone validates input, how destructive actions are gated, and the fixed hierarchy by which a failure reaches the user."
---

# ✅ Validation Standards

How Airclone decides an input is acceptable, how it gates operations that can destroy data, and the
single rule set for getting an error in front of the user.

**When to read this:** you are adding a text field, a new command/CLI surface, an operation that can
delete or overwrite data, or any code path that calls `RcloneClient.rpc` and can therefore fail.

---

## 1. 🧱 The five gates

Validation is layered. Each gate has a different job and a different failure shape.

| # | Gate | Lives in | Refuses by | Example |
| :-- | :--- | :--- | :--- | :--- |
| 1 | **Widget-local** | a dialog / field's own `State` | an inline error string next to the input | [`_NameDialog._submit`](../../app/lib/src/ui/file_op_dialogs.dart#L139) |
| 2 | **Pure classifier** | a top-level function in `state/` | a typed tier / refusal / `ArgumentError` | [`classifyTier`](../../app/lib/src/state/console/rclone_commands.dart#L148), [`translateToRc`](../../app/lib/src/state/console/console_rc_translate.dart#L166), [`buildArchiveCommand`](../../app/lib/src/state/archive_command.dart#L116) |
| 3 | **Controller pre-flight** | a Riverpod `Notifier`, before it calls `rpc` | setting `state.error` and returning | [`AddRemoteController.submit`](../../app/lib/src/state/add_remote_controller.dart#L98) |
| 4 | **Engine seam** | `RcloneClient.rpc` (both transports) | throwing [`RcloneException`](../../app/lib/src/rclone/rclone_client.dart#L57) | [`HttpRcloneClient.rpc`](../../app/lib/src/rclone/http_rclone_client.dart#L201), [`mapRpcResult`](../../app/lib/src/rclone/ffi_rclone_client.dart#L141) |
| 5 | **rclone itself** | the backend | an `error` field in the RC body, or `job/status.error` | [`JobsController`](../../app/lib/src/state/jobs_controller.dart#L263) |

**Rule — validate downward, never only upward.** A UI gate is a convenience; the authoritative refusal
must live at the lowest gate that is reachable programmatically. The console demonstrates the pattern:
`ConsolePane._submit` shows the destructive confirm, and `ConsoleController.run()` re-checks the tier
as a backstop ([console_controller.dart#L156](../../app/lib/src/state/console/console_controller.dart#L156))
so a caller that skips the dialog still cannot run a blocked verb. Same shape for the enterprise
kill-switches: [`mountEnabledProvider`](../../app/lib/src/state/mount_policy.dart) and
[`serveEnabledProvider`](../../app/lib/src/state/serve_policy.dart) are checked by the button, the
dialog **and** the controller.

**Rule — classifiers are pure and unit-tested.** Anything in gate 2 must be a total function over plain
data with no engine, no `BuildContext`, no I/O, so its every branch is covered in `app/test/`
(`console_command_test.dart`, `console_rc_translate_test.dart`, `archive_command_test.dart`,
`name_conflict_test.dart`, `sync_guard_test.dart`).

---

## 2. 🏷️ Names and identifiers

| Input | Rule | Where |
| :--- | :--- | :--- |
| Remote name — **import / scan rename** | must match `^[A-Za-z0-9_.-]+$`, be non-empty, not collide with another final name in the same batch, and not collide with an existing remote | [config_import_dialog.dart#L48](../../app/lib/src/ui/config_import_dialog.dart#L48), [scan_from_desktop_sheet.dart#L99](../../app/lib/src/ui/scan_from_desktop_sheet.dart#L99) |
| Remote name — **add-remote wizard** | non-empty after `trim()` only; the charset is enforced by rclone's `config/create` and surfaced as an RC error | [add_remote_controller.dart#L98](../../app/lib/src/state/add_remote_controller.dart#L98) |
| New-folder / rename leaf | non-empty after `trim()`; refused inline when it collides with a sibling name passed in as `taken` | [file_op_dialogs.dart#L146](../../app/lib/src/ui/file_op_dialogs.dart#L146) |
| Pasted / dropped names | resolved by [`planPaste`](../../app/lib/src/state/name_conflict.dart#L14) under a `ConflictChoice`; *keep both* routes each name through [`uniqueName`](../../app/lib/src/state/name_conflict.dart#L40) against a **running** taken-set, so newly assigned names can't collide with each other either |
| File leaf staged for another app | [`_safeLeaf`](../../app/lib/src/state/open_external.dart#L290) strips `\ / : * ? " < > |` plus control characters and leading dots, so a name can never escape the staging directory |

There is deliberately **no single shared "is this a valid remote name" helper** — the charset regex is
currently declared twice (import dialog, phone scan sheet). If a third caller appears, hoist it into a
shared file rather than copying it a third time.

---

## 3. 🧵 Paths and patterns

- **Remote-relative joins** use [`joinPath`](../../app/lib/src/ui/pane_drag.dart#L6) (UI) or the
  identical [`join`](../../app/lib/src/state/file_ops.dart#L10) (inside `FileOps`). Both yield the bare
  name for an empty parent, i.e. the remote root. See
  [12-utility-standards.md](12-utility-standards.md) for the full helper inventory.
- **`remote:path` splitting** for console input uses
  [`splitFsRemote`](../../app/lib/src/state/console/console_rc_translate.dart#L71). It is
  connection-string aware (`:s3,env_auth=true:bucket`) and returns `null` — a refusal, not a guess —
  for a colon-less token or a Windows drive path like `C:/foo`.
- **A literal name used where rclone expects a glob MUST be escaped.**
  [`escapeRcloneGlob`](../../app/lib/src/state/archive_command.dart#L101) backslash-escapes
  `\ * ? [ ] { }`. Without it a multi-select compress of `data[1].csv` would emit
  `--include /data[1].csv`, whose `[1]` is a character class that matches `data1.csv` — silently
  archiving the wrong files. The one live caller is the browser's archive path
  ([browser_pane.dart#L631](../../app/lib/src/ui/browser_pane.dart#L631)); any new `--include` /
  `--exclude` built from a real file name must do the same.

---

## 4. ⌨️ The command console — allowlist by construction

The console is the largest validation surface in the app. Its pipeline, in order:

| Step | Function | Failure mode |
| :-- | :--- | :--- |
| 1. Tokenize | [`ConsoleCommand.parse`](../../app/lib/src/state/console/console_command.dart) → [`parseEngineFlags`](../../app/lib/src/state/engine_flags.dart#L83) | none — argv only, never a shell string, so shell-metacharacter injection is impossible by construction |
| 2. Classify | [`classifyTier(verb, flags)`](../../app/lib/src/state/console/rclone_commands.dart#L148) | `CommandTier.blocked` |
| 3. Verbosity gate | [`hasCredentialDump`](../../app/lib/src/state/console/console_redaction.dart#L63) | refused inline ("block over scrub") |
| 4. Tier gate | UI confirm + controller backstop | blocked → message; destructive → confirm dialog |
| 5. Dispatch | Path A `core/command` STREAM (binary engine) / Path B [`translateToRc`](../../app/lib/src/state/console/console_rc_translate.dart#L166) (FFI engine) | `RcRefusal` on Path B |
| 6. Redact | [`redactTokens`](../../app/lib/src/state/console/console_redaction.dart#L32) / [`redactOutputLine`](../../app/lib/src/state/console/console_redaction.dart#L142) | n/a — applied to every echoed command and every output line |

### Tiers

| Tier | Meaning | Gate |
| :--- | :--- | :--- |
| `safe` | read-only or additive (`ls`, `lsjson`, `size`, `cat`, `copy`, `mkdir`…) | runs freely |
| `destructive` | can delete or overwrite (`delete`, `purge`, `sync`, `move`, `bisync`, `dedupe`, `cleanup`, `backend`…) | confirm dialog showing the **redacted** preview |
| `blocked` | refused outright | error line naming why + where to do it in-app |

Three independent things force `blocked`:

1. **An unknown verb** — the catalog
   ([`kRcloneCommands`](../../app/lib/src/state/console/rclone_commands.dart#L43)) is an allowlist, so
   anything absent is refused rather than passed through.
2. **A blocked verb** — secret exfil (`reveal`, `obscure`), config mutation (`config`), long-lived
   servers outside Airclone's lifecycle managers (`mount`, `serve`, `rc`, `rcd`), or engine meta
   (`selfupdate`).
3. **A blocked global flag on *any* verb** —
   [`isBlockedGlobalFlag`](../../app/lib/src/state/console/rclone_commands.dart#L133) refuses
   `--rc*`, `--config*`, `--dump*`, because each turns a harmless command into a secret-exfil or
   listening-server vector inside the child process `core/command` spawns.

Promotion also runs the other way: a *safe* verb carrying a flag from
[`kDestructiveFlags`](../../app/lib/src/state/console/rclone_commands.dart#L116)
(`--delete-during/-before/-after`, `--delete-excluded`, `--rmdirs`) becomes `destructive`.

### Refusal messaging is part of the contract

[`blockedMessage`](../../app/lib/src/state/console/rclone_commands.dart#L205) returns **three distinct
messages** — unknown verb, blocked flag on a runnable verb, blocked verb — and for a blocked verb it
appends the in-app alternative from `_inAppAlternative`
([rclone_commands.dart#L171](../../app/lib/src/state/console/rclone_commands.dart#L171)).

> **Rule:** a refusal that names no alternative reads as a broken feature. Microsoft Store
> certification failed Airclone on exactly that (a reviewer ran `config create local local` and got a
> dead-end refusal). Every blocked verb the app *can* do another way must name that way, and those
> strings must stay in step with the real UI labels.

### Fail-closed translation (FFI engine)

`core/command` does not exist in `librclone`, so the in-process engine translates argv to pure RC
calls. That translator is **fail-closed**: an unknown verb, an unmapped flag, or a positional it
cannot confidently split returns
[`RcRefusal`](../../app/lib/src/state/console/console_rc_translate.dart#L57) and dispatches nothing.
Dropping an unrecognised flag would be the data-loss disaster (a silently ignored `--max-delete`), so
the whole command is refused instead. Recognised-but-effectless flags (`--progress`, `--stats`) are
surfaced as `notes`, never silently dropped.

---

## 5. ⚠️ Destructive-action confirmations

| Action | Gate | Where |
| :--- | :--- | :--- |
| Delete a file or folder | `showDeleteConfirm` — folder copy states that contents go too | [file_op_dialogs.dart#L45](../../app/lib/src/ui/file_op_dialogs.dart#L45) |
| Real (non-dry) one-way **Sync** | `_showSyncConfirm` — Cancel / **Dry run first** / Run. Fires only for run-now consumers; never at task-definition time, because persisting the dry-run choice would make every scheduled run a silent no-op | [transfer_options_dialog.dart#L160](../../app/lib/src/ui/transfer_options_dialog.dart#L160) |
| First **bisync** (`--resync` baseline) | `showBisyncBaselineConfirm` — Cancel / Dry run first / Establish | [bisync_confirm.dart](../../app/lib/src/ui/bisync_confirm.dart) |
| Changing a **`crypt`** remote's password | `_confirmCryptPasswordChange` — everything already uploaded becomes permanently undecryptable; **Cancel is autofocused** so a stray Enter cannot re-key | [add_remote_dialog.dart#L82](../../app/lib/src/ui/add_remote_dialog.dart#L82) |
| Destructive console verb | `_confirmDestructive`, showing `redactedPreview(cmd)` | [console_pane.dart#L215](../../app/lib/src/ui/console_pane.dart#L215) |
| Dedupe / folder cleanup / closing with mounts | dedicated confirms | [dedupe_dialog.dart](../../app/lib/src/ui/dedupe_dialog.dart), [folder_tools.dart](../../app/lib/src/ui/folder_tools.dart), [close_with_mounts_dialog.dart](../../app/lib/src/ui/close_with_mounts_dialog.dart) |

Rules for any new destructive action:

1. **Name the consequence, not the act.** "This permanently deletes the folder and everything inside
   it. This cannot be undone." — not "Are you sure?".
2. **Offer the dry run** wherever rclone supports one, as a first-class button.
3. **Cancel is the safe default** for irreversible operations (autofocus it).
4. **Prefer a real cap over prose.** One-way sync exposes `maxDeleteFiles` → rclone `--max-delete` (a
   count, sync-only); bisync exposes `maxDeletePercent`
   ([transfer_options.dart#L96](../../app/lib/src/state/transfer_options.dart#L96)). These are
   data-loss guards, not tuning knobs — a wrong or empty source can otherwise wipe a destination.
5. **The confirm is not the enforcement.** If the operation is reachable from a controller, guard it
   there too (§1).

---

## 6. 🔓 Untrusted input

Anything that arrives as bytes from outside the app — an imported config file, a photographed QR, a
drag payload — is hostile until parsed. These paths use **typed exceptions**, so callers can tell the
cases apart instead of string-matching:

| Exception | Means | Declared in |
| :--- | :--- | :--- |
| `NotAnOfflineQr` | wrong/absent scheme — "that's not the right QR" | [offline_qr.dart#L79](../../app/lib/src/state/offline_qr.dart#L79) |
| `OfflineQrTooLarge` | the sealed config exceeds one scannable QR (carries the sizes) | [offline_qr.dart#L67](../../app/lib/src/state/offline_qr.dart#L67) |
| `WrongPassphrase` | correct format, wrong code/password | [config_io.dart#L196](../../app/lib/src/state/config_io.dart#L196) |
| `CorruptEnvelope` | malformed header, truncation, unknown KDF, bad gzip, non-UTF-8 | [config_io.dart#L207](../../app/lib/src/state/config_io.dart#L207) |
| `FormatException` | invalid base45 / non-object config dump | `dart:core`, thrown from the same paths |

Accompanying rules:

- **Classify bytes before parsing them** —
  [`detectConfigFormat`](../../app/lib/src/state/config_io.dart#L80) decides envelope vs INI vs JSON
  dump; nothing is parsed speculatively.
- **Cap attacker-controlled cost.** A scanned QR carries its own Argon2id parameters, so the open path
  passes `maxMemoryKiB: kMaxOfflineQrArgon2MemoryKiB` (128 MiB) — a hostile QR cannot demand a
  device-OOMing KDF ([offline_qr.dart#L129](../../app/lib/src/state/offline_qr.dart#L129)).
- **Import is reviewed, and the review shows the endpoint.**
  [`remoteEndpointSummary`](../../app/lib/src/state/remote_summary.dart) renders a location-only
  `key: value` (never a secret) in both import reviews, so a remote silently re-pointed at an
  attacker's host is visible before anything is written.
- **Secrets from untrusted input stay in widget-local state** (`TextEditingController`s, a local
  `List<int>`), never in provider state, and are dropped when the dialog closes.

---

## 7. 📣 The error-surfacing hierarchy

State these as rules, in order. They are the contract for every new failure path.

**R1 — Every engine failure becomes an `RcloneException` at the seam.** Both transports normalise to
`RcloneException(method, message, statusCode?)`: HTTP maps a non-2xx body's `error` field, FFI's
[`mapRpcResult`](../../app/lib/src/rclone/ffi_rclone_client.dart#L141) does the same for librclone's
`(status, json)` pair. Nothing above the seam inspects HTTP status codes directly.

**R2 — A 2xx is not automatically success.** rclone's interactive config flow returns HTTP 200 with an
`Error` field in the body; `AddRemoteController._call` checks it explicitly
([add_remote_controller.dart#L241](../../app/lib/src/state/add_remote_controller.dart#L241)). Check
for in-body errors on any RC method that has them.

**R3 — Controllers catch; widgets never do.** A controller stores the failure in its own state
(`state.copyWith(error: …)`) and returns. An exception must never escape into a widget `build`.

**R4 — Pick the surface by the scope of the failure.**

| Scope of failure | Surface | Reference |
| :--- | :--- | :--- |
| The engine is not up at all | the full-screen `EngineGate` (locating / not installed / needs password / provisioning / error), not an error string | [engine_gate.dart](../../app/lib/src/ui/engine_gate.dart), [`EnginePhase`](../../app/lib/src/state/engine_controller.dart#L51) |
| A pane's content failed to load | inline, centred in the pane's content area | [browser_pane.dart#L310](../../app/lib/src/ui/browser_pane.dart#L310) |
| A field is invalid | inline next to / under the field | [file_op_dialogs.dart#L146](../../app/lib/src/ui/file_op_dialogs.dart#L146) |
| A wizard step failed | the controller's `state.error`, rendered by that step | [add_remote_controller.dart#L241](../../app/lib/src/state/add_remote_controller.dart#L241) |
| Anything **inside a modal dialog** | inline in the dialog — **never** a SnackBar; it renders behind the modal barrier and is easy to miss | [mount_panel.dart#L29](../../app/lib/src/ui/mount_panel.dart#L29) |
| A fire-and-forget action from a main surface | `SnackBar` via `ScaffoldMessenger.maybeOf` | [open_external_action.dart#L93](../../app/lib/src/ui/open_external_action.dart#L93) |
| A long-running transfer | the job row's `error`, in the Transfers panel | [jobs_controller.dart#L263](../../app/lib/src/state/jobs_controller.dart#L263) |
| A console command | an `ConsoleLineKind.error` line in that console's scrollback | [console_controller.dart](../../app/lib/src/state/console/console_controller.dart) |

**R5 — Show rclone's message, not Dart's `toString()`.** Prefer `e.message` when catching
`RcloneException`; fall back to `'$e'` only in the generic `catch`.

**R6 — Never surface a secret in an error.** Console output passes through `redactOutputLine` before
it enters the scrollback or persisted history, and credential-dumping verbosity (`-vv`, `--dump*`,
`--log-level DEBUG`) is **refused rather than scrubbed** — blocking beats trying to sanitise freeform
dump output.

**R7 — Recognise recoverable failure classes and offer the recovery.**
[`looksLikeBisyncNeedsResync`](../../app/lib/src/ui/jobs_panel.dart#L24) matches tolerantly on two
stable signals so wording drift between rclone releases still lands the "run `--resync`" hint. Match
loosely on signals, not on one exact sentence.

**R8 — Swallow only what the user cannot act on.** Housekeeping is best-effort and silent: pruning
staged files, a stats tick that momentarily fails, backup rotation, `SharedPreferences` writes. The
convention is that a silent `catch (_) {}` carries a one-line comment saying why silence is correct
("best-effort", "already gone or locked", "notification plumbing must never break transfers") — write
that comment, or surface the error instead.

**R9 — A stale result is a failure too.** An overlapping listing that returns after navigation has
moved on must commit nothing rather than surface a wrong error or a wrong folder; see the
supersede guard in [`BrowserController._load`](../../app/lib/src/state/browser_controller.dart#L420)
and the listing-race invariant in [14-performance-standards.md](14-performance-standards.md).

---

## 8. 📋 Checklist for a new input or operation

- [ ] Is there an existing pure classifier, or does this need a new one in `state/`? Pure + total +
      unit-tested.
- [ ] Does any user string become an rclone **pattern**? Escape it with `escapeRcloneGlob`.
- [ ] Does it add a CLI verb or flag path? Update the console catalog and its tier, and give a blocked
      verb an in-app alternative.
- [ ] Can it delete or overwrite? Add a confirm that names the consequence, offer a dry run, default
      to Cancel, and add the guard below the UI.
- [ ] Does it parse untrusted bytes? Classify first, throw a typed exception, cap attacker-controlled
      cost.
- [ ] Does it call `rpc`? Catch `RcloneException`, store the message in controller state, and pick the
      surface from R4.
- [ ] Could it read cloud-placeholder bytes? Gate on `wouldHydrateOnRead` — see
      [14-performance-standards.md](14-performance-standards.md).

---

## Related

[Core Architecture](08-core-architecture.md) · [State & Context](07-state-context.md) ·
[External Integrations](10-external-integrations.md) · [Utility Standards](12-utility-standards.md) ·
[Performance Standards](14-performance-standards.md) · [Security](15-security.md) ·
[Glossary](16-glossary-of-terms.md) · [System Index](00-system-index.md)

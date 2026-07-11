# Command Console plan: a first-class in-GUI rclone command surface

**Status:** proposed (design). **Pinned rclone:** `v1.74.4`.
**Owner interface:** [`RcloneClient`](../../app/lib/src/rclone/rclone_client.dart) — the ONE seam.
**Reuses:** [`JobsController`](../../app/lib/src/state/jobs_controller.dart) queue · [`PaneSplit`/`PaneTabStrip`](../../app/lib/src/ui) · [`parseEngineFlags`](../../app/lib/src/rclone/engine_flags.dart) · [`advanced_mode.dart`](../../app/lib/src/state/advanced_mode.dart)

---

## 1. Vision

**Pitch:** *A first-class, safety-railed rclone command console built into Airclone — type any rclone command with live autocomplete and doc links, watch it run with real streaming output and a Stop button, on desktop and mobile alike — because it dispatches through the RC API and the existing job queue, not a shell.*

The console is the **power-user escape hatch** that makes Airclone honest: everything the GUI does is rclone, so let advanced users reach the full command surface without dropping to a terminal (which mobile doesn't even have). It is *not* a POSIX shell and *not* a raw text pipe — it is a structured, argv-based dispatcher with autocomplete, destructive-op guards, and secret redaction. It sits inside the existing pane/tab system as a new pane kind and inside the existing job queue as a new job type, so it inherits Stop, retry, progress, and history for free.

Design tenets, in priority order:

1. **Argv, never a shell.** We tokenize and dispatch a structured `{command, arg[], opt{}}` — there is no string we hand to a shell, so injection is a non-issue *by construction*.
2. **Cross-engine or clearly degraded.** The primary run path must behave identically on desktop (spawned `rcd` / HTTP) and mobile (`librclone` / FFI). Where the engine genuinely can't (live `core/command` streaming on FFI), we degrade explicitly and visibly — never silently.
3. **Safe by default.** Advanced-Mode-gated, dry-run-forward, destructive verbs demand a typed confirm, secrets are redacted before they ever hit the output buffer or history.

---

## 2. Execution architecture

### 2.1 The two dispatch primitives

The console has to reconcile a hard engine split (documented below in §3). It does so by running **two kinds of commands over one seam**:

| Path | RC substrate | Engines | Live output | Use for |
|---|---|---|---|---|
| **A. CLI command** | `core/command` (re-execs the rclone binary) | **desktop only** (HTTP `rcd`) | true streamed stdout/stderr | arbitrary `rclone <subcommand>` — the "console" proper |
| **B. RC-method command** | any pure-data RC method (`operations/*`, `sync/*`, `core/stats`, …) | **both** (HTTP + FFI) | structured `core/stats` + log tail | the cross-platform substrate; the *only* path on mobile |

Both are modeled as the same **`JobType.command`** job and share one code path above the seam. The difference is entirely inside the client implementation and is invisible to the queue.

> **Why not force everything onto one primitive?** `core/command` is arbitrary-CLI power but is HTTP/subprocess-only (§3). RC methods are cross-engine but can't express "run `rclone lsjson --drive-shared-with-me`" as free text. We refuse to cripple desktop to match mobile, and we refuse to lie about mobile parity. So: **desktop gets the full CLI console; mobile gets a structured RC-method console with a curated palette + raw-RC advanced mode.** The UI communicates which one you're in.

### 2.2 Job-queue integration

A console run is a `Job` like any transfer. Add to [`job.dart`](../../app/lib/src/state/job.dart):

```dart
enum JobType { copy, move, sync, /* … */ command }
```

`TransferService` gets a sibling entry point (or a new `CommandService`):

```dart
Future<void> runCommand(ConsoleRequest req) async {
  final job = jobs.add(
    type: JobType.command,
    source: req.previewLine,   // redacted exact-command preview, shown as the row label
    dest: '',
  );
  jobs.enqueue(job.id, () => _dispatch(job, req));
}
```

`_dispatch` picks the lifecycle mode by request kind:

- **Path B (RC-method), long-running** — dispatch with `_async:true` + `_group:'airclone/console/<job.id>'`, record the returned rclone `jobid` via `jobs.update(jobid:)`. **Zero poller changes.** The existing 1 s `_poll` in [`jobs_controller.dart`](../../app/lib/src/state/jobs_controller.dart) already walks every running job with a non-null `jobid`, pulls `core/stats` scoped to the group for bytes/speed/transferring, and `job/status` for finished/success/error. Stop is `job/stop`. Final structured JSON is read from `job/status.output`.
- **Path B (RC-method), instant** (`lsjson`/`size`/`about`) — skip async: one `rpc()` returns JSON immediately, render, done. Identical on both engines.
- **Path A (CLI command)** — driven by the **streaming seam** (§2.3), not the poller. The subscription *is* the lifecycle: each line appends to the console scrollback and (tail) the job row; stream `done` → `markDone(success)`, stream error → `markDone(failed)`.

> ### ⚠️ Fix the group-id mismatch first (pre-req, latent existing bug)
> Today the transfer path tags stats with the **local** id (`airclone/${job.id}`, `transfer_service.dart`) but the poller queries `core/stats` with the **rclone** `jobid` (`airclone/$jobid`, `jobs_controller.dart`). App ids start at 0, rclone jobids at 1 — these never agree, so group-scoped progress likely doesn't light up at all today. Before reusing group-scoped progress for command jobs, **reconcile on one scheme**: dispatch AND poll on `airclone/console/<rcloneJobid>` (query only after the jobid is known), or switch the poller to the local id we already know at enqueue time. Pick the local-id scheme — we own it at dispatch and don't have to wait for the async round-trip. Verify transfer progress actually lights up after the fix.

### 2.3 The `RcloneClient` seam additions

The current seam is a single buffered `rpc()` that awaits the whole HTTP body then `jsonDecode`s it — it **cannot** consume `core/command`'s chunked plaintext. Add exactly two methods to [`rclone_client.dart`](../../app/lib/src/rclone/rclone_client.dart):

```dart
/// A live line stream for an arbitrary rclone subcommand.
/// HTTP: streamed POST to core/command (returnType STREAM*). FFI: throws
/// CommandUnavailableOnEngine (caller falls back to Path B).
Stream<ConsoleLine> commandStream(
  String command, {
  List<String> args = const [],
  Map<String, String> opts = const {},
  String? group,
  CommandStream returnType = CommandStream.combined, // combined|stdout|stderr
});

/// Cancel a live commandStream cleanly (closes the HTTP request → rclone
/// cancels the job ctx → kills the spawned child). No-op on a closed stream.
Future<void> cancelCommand(Object token);
```

`ConsoleLine { String text; LineChannel channel; /* stdout|stderr|log */ DateTime ts; }`.

**`HttpRcloneClient.commandStream`** (must live inside the class — `_port`/`_authHeader` are private):
- `POST /core/command` with `{command, arg, opt, returnType:'STREAM'}` — a **plain synchronous** request (no `_async`; §3 explains why `_async` silently breaks streaming).
- Read `http.StreamedResponse.stream` incrementally, decode UTF-8, split on `\n` **ourselves** (the body is an unframed byte pipe, chunked transfer-encoding, no JSON framing, no per-line flush — buffer bursts of ~2–4 KB or on child exit).
- Use the app's own `http.Client` so we can cancel; cancellation closes the request → `r.Context()` cancels → job ctx cancels → the `exec.CommandContext` child dies. This is the **primary Stop path** for CLI commands.
- **Do NOT** use the buffered `post` with its 30 s timeout — a `-vv` or long command would time out mid-stream.

**`FfiRcloneClient.commandStream`** throws `CommandUnavailableOnEngine`. The console layer catches it and routes to Path B (or the request never offered Path A on FFI in the first place — see §5 mode selection). We do **not** fake CLI streaming on FFI with `COMBINED_OUTPUT`, because `core/command` is rejected wholesale by librclone (§3) — there is nothing to buffer.

**Log-tail helper** (shared, engine-agnostic) — the second half of the cross-engine live-output story, detailed in §3:

```dart
Stream<ConsoleLine> tailEngineLog({required int fromOffset});
```

Both clients configure a single engine-wide JSON log file at `start()` (argv on the subprocess, env before `RcloneInitialize` on FFI) and expose its current byte offset so a command can tail only *its* slice.

---

## 3. Cross-engine live output — the single strategy

This is the crux. `RcloneRPC` returns the full JSON in one blocking call — **no incremental output crosses FFI, ever**. And `core/command` is declared `NeedsRequest:true` + `NeedsResponse:true`, which librclone hard-rejects (`method … needs request, not supported`) and which also re-execs `os.Executable()` (there is no binary to exec in-process). So `core/command` — every return type, including STREAM — is **categorically impossible on mobile**. There is no clever wrapper. Accept it and design around it.

**The unifying model: every command produces a `Stream<ConsoleLine>`, assembled from up to three sources, and the console renders that one stream identically regardless of engine.**

```
                         ┌─────────────── ConsoleController ───────────────┐
   Path A (desktop CLI)  │  commandStream() → stdout/stderr lines (STREAM) │
                         │                        +                        │
   Both engines          │  tailEngineLog(fromOffset) → JSON log records   │→  one merged,
                         │                        +                        │   timestamp-ordered
   Both, structured      │  core/stats(group) poll → progress lines/bar    │   ConsoleLine stream
                         └─────────────────────────────────────────────────┘
```

### 3.1 The three sources, unified

1. **stdout/stderr** (Path A, desktop only): the raw chunked body from `core/command` STREAM, split into `ConsoleLine(channel: stdout|stderr)`. This carries a CLI command's actual textual output (a `lsjson` dump, a `tree`, an `ncdu` frame). *Not available on FFI.*
2. **Engine log** (both engines): a single engine-wide log file, `--use-json-log`, tailed from the byte offset captured at command start, parsed as JSON records → `ConsoleLine(channel: log)`. This carries DEBUG/INFO/NOTICE/ERROR — the human narration (`Copied (new)`, `Deleted`, errors, retries). This is how mobile gets "live output" at all, and how *both* engines show what a transfer is *doing*.
3. **Structured progress** (both engines): `core/stats?group=…` polled at 250–1000 ms → the progress bar + a periodic stats line (bytes, ETA, speed, per-file `transferring[]`). Drives the job-row `LinearProgressIndicator` and an optional in-console progress widget.

The console merges 1–3 into one ordered scrollback. On desktop a CLI command shows all three; on mobile an RC-method command shows 2 + 3. **The renderer doesn't branch on engine** — it just consumes whatever lines arrive.

### 3.2 Configuring the single log file (once, at engine start)

- **`HttpRcloneClient.start()`**: add argv to the spawned `rcd` — `--log-file <appSupport>/airclone-engine.log --log-level DEBUG --use-json-log`. (Keep the existing `runInShell:false`.)
- **`FfiRcloneClient.start()`**: set `RCLONE_LOG_FILE=<sandbox>/airclone-engine.log`, `RCLONE_LOG_LEVEL=DEBUG`, `RCLONE_LOG_FORMAT=json` **before `RcloneInitialize`**, via the same `SetEnvironmentVariableW`/`setenv` path already used for `RCLONE_CONFIG_PASS`. Logging is process-global and set once at init; no RC method re-opens the log file, so this must be pre-init. Point it at a `path_provider` temp/support dir or `InitLogging` fatals.

Log file is single and appendable (default `MaxSize -1`, **no rotation** — rotation would break the tail). It interleaves *all* engine activity, so:

### 3.3 Correlating a command's slice

- **Offset capture:** at command start, `stat` the log file for its current byte length; `tailEngineLog(fromOffset:)` reads only bytes appended after. That bounds the tail to activity since this command began.
- **JSON fields for filtering:** `--use-json-log` records carry structured fields; filter/annotate by timestamp and (where present) `object`/`source`. There is no per-job id in stock log records, so correlation is heuristic — mitigated by:
  - **Serialize console commands** (one running console job at a time by default; the queue already serializes via `_pending`). This makes "everything since my offset" ≈ "my command".
  - **`core/stats` group** is the *authoritative* structured feed and *is* per-command (each job gets its own `_group`), so byte-progress is never ambiguous even when log lines are.
- **Phase-5 upgrade (optional, custom cgo):** rclone's `OutputHandler.AddOutput` (`fs/log/slog.go`) can push each structured log record to a Go callback at runtime — a clean, per-group, file-less feed. Not exposed via RC or the C ABI, so it needs a custom librclone export. Airclone already builds librclone from a custom module, so this is a feasible later swap for `tailEngineLog` that eliminates the interleave problem on FFI entirely. Not required to ship.

### 3.4 How Stop works on each engine

| | Desktop CLI (Path A) | Both engines, RC-method (Path B, async) |
|---|---|---|
| **Mechanism** | **Close the streamed HTTP request.** `r.Context()` is the parent of the job ctx; client disconnect cancels it → kills the `exec.CommandContext` child. | **`job/stop {jobid}`** cancels the job's context in the process-global `running` map. On FFI this reaches the same global state from the worker isolate because `_async:true` freed the worker. |
| **Why not the other** | `x-rclone-jobid` header is flushed *after* streaming starts, so it's not reliably delivered for streaming calls — don't depend on `job/stop` here. (Fallback: poll `job/list` `runningIds` to discover the jobid.) | The child process cancellation path doesn't exist in-process; `job/stop` is the only lever and it works. |

`JobsController.stop(id)` gains a **per-job cancel hook**: `Map<int, Future<void> Function()> _cancels`, populated at enqueue. `stop(id)` invokes the hook when the job has no rclone `jobid` (Path A: cancel the subscription/close the request); otherwise it falls through to the existing `job/stop` path (Path B). One Stop button, two mechanisms, invisible to the UI.

> **`_async` + STREAM is a silent trap** — it returns a jobid but the `http.ResponseWriter` dies when the handler returns, so the stream goes nowhere and can race-corrupt the response. **Path A is always a plain synchronous streamed request.** Never `_async` a STREAM.

---

## 4. Autocomplete + doc links

Four cached tables feed the suggestion model. Three come from **pure-data RC methods that run identically on both engines**; one is bundled static because rclone exposes no structured route to it.

| Table | Source | Both engines? | Cache key / invalidation |
|---|---|---|---|
| **Subcommands** | **bundled static JSON** (generated at build from `rclone help` / gendocs: name, one-line help, doc slug, tier) | n/a (static asset) | refresh when the pinned rclone version bumps |
| **Global flags** | `options/info` (flatten all blocks → `--<Name>`, Type, first-sentence Help, Groups, ShortOpt) | ✅ | disk cache keyed by `core/version` |
| **Backend flags** | `config/providers` (`RegInfo[]`; index `Options` by provider Name; each Option same schema as global flags, with Provider/Advanced) | ✅ | disk cache keyed by `core/version` |
| **Remotes** | `config/dump` (superset of `config/listremotes` — gives `type` too; **read only the `type` field**, never secrets) | ✅ | in-memory, invalidate on `config/create\|update\|delete` |
| **remote:path** | `operations/list fs=remote: remote=dir opt={dirsOnly}` | ✅ | per-`(fs,dir)` LRU, ~30 s TTL, debounced ~250 ms |

**Why subcommands are static:** the cobra command tree lives only in `cmd/` and is never emitted as JSON. The one RC route (`core/command command=help`) returns unstructured plaintext *and* is librclone-rejected — so it can't be the source of truth, especially on mobile. Bundle the list; it only changes when the binary does.

**Startup cost:** ~2 cacheable RC round-trips (`options/info` + `config/providers`, both version-stable across sessions) + `config/dump`. Never fetch per keystroke.

### 4.1 Ranking

Tokenize the line with `parseEngineFlags` (the same quote-aware tokenizer used for danger detection — §6). Then, by the token under the cursor:

- **token[0]** → suggest **subcommands** (filtered by the current mode's tier allowlist): prefix match > substring > fuzzy; boost recently-used; hide gated verbs unless the gate is unlocked.
- **after a subcommand** → suggest **flags**: merge global flags with the backend flags of any remote already named on the line (look up its `type` in the remotes table → `config/providers` Options). Common/non-Advanced first; Advanced collapsed. Dedupe by Name; hide `Hide!=0`.
- **empty token / matches a remote name** → suggest `remote:` entries, then transition to **`operations/list` path completion** after the `:` (prefetch on the trailing `:` or `/`).

Each suggestion carries a type hint (from `Option.Type`) and its first-sentence help inline.

### 4.2 Doc deep-links (verified URL patterns)

Every suggestion and every token in the exact-command preview gets a doc link:

- **command** → `https://rclone.org/commands/rclone_<name>/` (spaces → underscores: `rclone_copy`, `rclone_lsjson`, `rclone_config_create`)
- **commands index** → `https://rclone.org/commands/`
- **global flag** → `https://rclone.org/flags/#<flag>`
- **backend flag / remote type** → `https://rclone.org/<providerPrefix>/` (use `RegInfo.Prefix` — `drive`, `s3`, `dropbox` — never the display Name; keep a small override map + fall back to the command/overview page on 404)

Links open in the system browser (desktop) / in-app tab or external (mobile).

> **Gotchas to encode in the build-time generator:** `options/info` Names are internal snake_case and *mostly but not always* equal the CLI `--flag` spelling ("a few exceptions") — verify generated flag names against `rclone help flags`. A handful of backend Prefixes may not map 1:1 to a doc slug — hence the override map.

---

## 5. UX

### 5.1 The console pane (new pane kind)

The pane/tab/split system is already content-agnostic: [`PaneSplit`](../../app/lib/src/ui/pane_split.dart) takes arbitrary `first`/`second` widgets; [`PaneTabStrip`](../../app/lib/src/ui/tab_strip.dart) renders only `TabInfo.label`. So a console is a **new tab/pane KIND**, not new layout machinery.

- Add `enum PaneKind { browser, console }` (a `kind` on each `_Session`/`TabInfo` in [`browser_controller.dart`](../../app/lib/src/state/browser_controller.dart)).
- Each console session owns `ConsoleState { List<ConsoleLine> log; String draft; bool running; int? jobId; Object? cancelToken; List<ConsoleBlock> history; }` — a **ring-buffered** `log` (cap it; `-vv` output is unbounded) that survives tab switches and is independently splittable.
- In `BrowserPane._body` ([`browser_pane.dart`](../../app/lib/src/ui/browser_pane.dart)) branch on the active tab's `kind`: `console` renders `ConsolePane(index)`. **Guard every folder-assuming handler** (path bar, filter, drag/drop, context menus) against a null remote when the tab is a console.
- Add a "New console tab" affordance beside `newTab`.

Because the split/tab widgets are content-agnostic, the console is automatically tabbable, splittable, and resizable — a console can sit beside a browser, or two consoles side by side.

### 5.2 Smart input

Token-aware, backed by §4. Features:

- **Suggestion popover** anchored to the token under the cursor; ↑/↓/Tab to accept; each row shows label · type hint · first-sentence help · a doc-link affordance.
- **Ghost text** — inline dim completion of the current token (accept with →/Tab).
- **Form ⟷ Raw toggle.** *Raw*: one text field, `parseEngineFlags` tokenizes live. *Form*: a structured builder — subcommand dropdown, positional-arg fields, a flag list with typed inputs (bool → switch, enum → dropdown from `Option.Examples`). Form mode emits the same argv; it's the safer default for destructive verbs and the *only* mode on mobile's curated palette.
- **Dry-run toggle** — prominent, defaults **on** for any destructive verb (§6); injects `--dry-run` into `opt`.
- **Exact-command preview** — a always-visible, monospace, **redacted** rendering of the exact argv that will be dispatched (`rclone copy src: dst: --dry-run`), with per-token doc links. This is the row label too. What you see is exactly what runs.
- **Mode banner** — on FFI, a banner: "Mobile: structured RC-method console (CLI streaming unavailable on this engine)". On desktop the full CLI is available; the banner is absent or a subtle "CLI" chip.

### 5.3 Live output view

- **ANSI-aware** monospace scrollback (parse SGR color; strip cursor-motion). Auto-scroll with a "jump to bottom" pill when scrolled up.
- **Channel styling** — stdout default, stderr tinted, log records dimmed/prefixed by level.
- **Progress** — a `core/stats`-driven bar + a live stats line (bytes/ETA/speed) for transfer-type commands; flat/absent for non-transfer ones (that's fine — the poller just stays flat).
- **Filter** box (substring/level) over the buffered lines.
- **Copy** (selection or whole buffer; copies the **redacted** text).
- **Stop** button (wired to `JobsController.stop` → §3.4 dual mechanism).
- **Re-runnable blocks** — each completed command becomes a `ConsoleBlock` (redacted argv + status + collapsible output tail) with a **Re-run** action. Re-run of a block containing a `‹redacted›` sentinel prompts for the secret rather than replaying a placeholder (§6).
- **JobsPanel integration** — a `JobType.command` row shows status + Stop + a short output tail + a **"Reveal in console"** link that focuses the originating pane/tab. The authoritative scrollback lives in `ConsoleState.log`; the panel is a satellite view.

### 5.4 Wireframes

**Desktop** — console pane split beside a browser:

```
┌─ Airclone ──────────────────────────────────────────────────────────────────┐
│ [Browser ▾] [Console ✕] [＋]                                    Advanced ● │
├───────────────────────────────┬──────────────────────────────────────────────┤
│  gdrive:Photos/2024           │  CONSOLE                    [Form|▐Raw▌] CLI  │
│  ├ IMG_001.jpg                │ ┌──────────────────────────────────────────┐ │
│  ├ IMG_002.jpg                │ │ > copy gdrive:Photos s3:backup --dry-r▏  │ │
│  └ …                          │ │        ┌───────────────────────────────┐ │ │
│                               │ │        │ --dry-run     do a trial run  │ │ │
│                               │ │        │ --drive-*  (gdrive is a drive)│ │ │
│                               │ │        └───────────────────────────────┘ │ │
│                               │ ├──────────────────────────────────────────┤ │
│                               │ │ runs: rclone copy gdrive:Photos s3:backup │ │
│                               │ │       --dry-run   [🔗 docs]  ☑dry-run     │ │
│                               │ │                          [ Run ] [ Stop ] │ │
│                               │ ├──────────────────────────────────────────┤ │
│                               │ │ ⣾ 1.2 GB / 3.4 GB · 12 MB/s · ETA 3m     │ │
│                               │ │ ────────────────────────────░░░░  35%     │ │
│                               │ │ NOTICE: IMG_002.jpg: Skipped copy (dry)   │ │
│                               │ │ NOTICE: IMG_003.jpg: Skipped copy (dry)   │ │
│                               │ │ stderr… stdout…                    [filter]│ │
│                               │ │ ▼ copy gdrive:Photos s3:backup  ✓ (re-run)│ │
│                               │ └──────────────────────────────────────────┘ │
└───────────────────────────────┴──────────────────────────────────────────────┘
```

**Mobile** — full-screen console tab, RC-method mode:

```
┌──────────────────────────────┐
│ ‹ Console            ⋮  ●Adv  │
│ Mobile: structured RC console │
│ (CLI streaming n/a here)      │
├──────────────────────────────┤
│ command  [ copy          ▾]  │
│ src      [ gdrive:Photos   ]  │
│ dst      [ s3:backup       ]  │
│ ☑ dry-run    + add flag      │
│ runs: copy gdrive:Photos     │
│       s3:backup --dry-run 🔗 │
│        [   Run   ] [ Stop ]  │
├──────────────────────────────┤
│ ⣾ 1.2/3.4 GB · ETA 3m        │
│ ██████████░░░░░░░  35%        │
│ NOTICE IMG_002 Skipped (dry) │
│ NOTICE IMG_003 Skipped (dry) │
│ ─────────────────────────    │
│ ▸ copy … s3:backup ✓  ⟲      │
└──────────────────────────────┘
```

---

## 6. Safety

Guardrails are a first-class requirement, not a nicety — this is the one sanctioned exception to the repo's standing "avoid `core/command`" principle ([`airclone-avoid-command-rc`](../../wiki), `encrypt_remote_controller.dart` "uses only safe RC primitives"). The whole feature is **Advanced-Mode-gated** ([`advanced_mode.dart`](../../app/lib/src/state/advanced_mode.dart)) and off by default.

**1. Argv, not a shell — by construction.** We tokenize with `parseEngineFlags`, set `token[0]` = subcommand, split the rest into positional `arg[]` and flag `opt{}`, and dispatch JSON. No `Process`, no `runInShell`, no string concatenation. Shell metacharacters are inert because there is no shell. *Detection is always on the parsed tokens, never a substring/regex over the raw line.*

**2. Subcommand tiers (allowlist).** Validate `token[0]` against the bundled command table; reject unknown verbs. Three tiers:

- **Safe** — `ls`, `lsjson`, `lsd`, `size`, `cat`, `md5sum`, `about`, `version`, `tree`, … run freely.
- **Destructive** — `delete`, `deletefile`, `purge`, `rmdir`, `rmdirs`, `cleanup`, `dedupe`, `sync`, `move`, `moveto` — **and destructive *flags* on any verb**: `--delete-during/before/after`, `--delete-excluded`, `--rmdirs`. Classification considers the flag set, not just the verb (a `copy --delete-excluded` or a `move` is destructive too).
- **Blocked/separately-gated** — `config*` (secret exfil/mutation), `mount`, `nfsmount`, `serve`, `rcd`, `rc`, `authorize`. These either leak credentials or spawn long-lived servers that would occupy a job slot forever and run *outside* Airclone's own mount/serve lifecycle managers (orphan risk). Blocked by default; if ever enabled, behind a distinct explicit gate. The `config*` block is **load-bearing** — `core/command` inherits `rcd`'s `RCLONE_CONFIG_PASS` and full config, so `config show/dump/reveal` are plaintext-secret exfil vectors even with no `--dump` flag.

**3. Destructive → dry-run + typed confirm.** For a destructive command: inject `--dry-run`, run it, stream the preview into the output pane, then show a `bisync_confirm`-style **three-button** dialog (*Cancel* / *already previewed* / destructive confirm styled with `c.error`). Where `--dry-run` doesn't produce a meaningful diff (`cleanup`, empty-target `deletefile`/`purge`), require the user to **type the target name** to confirm. Mirror the existing `TransferOptions.dryRun → _config['DryRun']=true` and `MaxDelete` cap patterns.

**4. Secret redaction — one filter, applied before text ever enters the buffer.** The console output pane + persisted history are exactly the "persistent log" that `http_rclone_client.dart` already refuses to leak `-vv`/`--dump` into. Redact, on both live output and any persisted text:
- **Secret-flag values** — `--*-pass`, `--*-password`, `--*-key`, `--*-secret`, `--*-token`, `--*-sas-url`, `--*-account-key`, `--*-client-secret`, `--rc-pass`, `--rc-user`.
- **Connection-string secrets inside a positional arg** — `:sftp,host=x,pass=obscured:path` embeds the secret in the *arg token*, not a flag; parse inside the token and redact each `key=value` for secret keys.
- **High-verbosity dumps** — if parsed `opt` contains `-vv`/`--verbose>=2` or any `--dump` (headers/bodies/auth/requests/responses): **refuse or force-strip** from the console (these can echo the rc credentials — the exact `http_rclone_client.dart:168` rule). If ever allowed, pipe output through an `Authorization`/`Bearer`/`AWS4-HMAC`/`token=` scrubber before display. Prefer blocking over scrubbing freeform dumps.
- Redaction runs **before** append, so the un-redacted form never exists in app memory beyond the transient RPC result.

**5. History (new persistence surface → redaction-before-persist is net-new).** `Job.rcParams` is memory-only today; a restart-surviving history is new. Persist only: the **redacted** argv (secret values → `‹redacted›`), timestamp, subcommand, exit status, optional redacted+truncated output tail. **Never** persist `-vv`/`--dump` output. On re-run, if the recalled command contains a `‹redacted›` sentinel, prompt for the secret — never replay the placeholder, never reconstruct a stored secret.

**6. Mobile parity — honest degradation.** On the FFI engine `core/command` is unavailable, so the CLI console can't exist. Offer the **RC-method console** (curated palette of `operations/*`, `sync/*`, … + a raw-RC advanced mode: method + JSON body) with the *same* redaction and destructive-confirm logic. The mode banner (§5.2) states plainly that CLI streaming is unavailable — degrade **visibly**, never silently, or it reads as a bug.

---

## 7. Phasing

Each phase is independently shippable and independently verifiable.

### Phase 0 — pre-req: reconcile the group-id bug
Fix the `airclone/<localId>` (dispatch) vs `airclone/<rcloneJobid>` (poll) mismatch on one scheme; confirm transfer progress lights up. **Verify:** run a real copy, watch `core/stats` group progress appear on the job row.

### Phase 1 — MVP (desktop CLI, buffered)
`JobType.command`; `CommandService.runCommand`; console pane kind (branch in `_body`, guard folder handlers); Raw input with `parseEngineFlags`; **`core/command` COMBINED_OUTPUT** via a new streamed-but-buffered seam call; exact-command preview; Advanced-Mode gate; subcommand allowlist + tiers; **argv-only** dispatch. No autocomplete, no live stream yet.
**Verify:** on desktop, run `rclone lsjson gdrive:` and `size`, see output; confirm an unknown verb is rejected and a `config dump` is blocked; confirm the dispatched params are argv (never a shell string).

### Phase 2 — autocomplete + doc links + safety
Four cached tables (`options/info`, `config/providers`, `config/dump`, bundled subcommand JSON); token-aware suggestions + ghost text; doc deep-links; Form mode; **destructive dry-run + typed-confirm**; secret redaction filter; persisted redacted history + re-run.
**Verify:** type `copy gdrive:` → remote/flag suggestions appear; `delete` forces a dry-run + confirm; a `--sftp,pass=…` connection string is redacted in output and history; doc links resolve.

### Phase 3 — live streaming (desktop)
`HttpRcloneClient.commandStream` true STREAM; incremental newline splitting; ANSI render; per-job cancel hook in `JobsController.stop` (close request → child dies); log-file tail (`--log-file --use-json-log`) merged with stdout/stderr; `core/stats` progress bar.
**Verify:** run a long `copy`, watch lines stream, hit Stop, confirm the child `rclone` process actually exits (Task Manager / `job/list`).

### Phase 4 — mobile (FFI, RC-method console)
`FfiRcloneClient.commandStream` throws `CommandUnavailableOnEngine`; console defaults to RC-method mode on FFI; curated palette + raw-RC; `RCLONE_LOG_FILE`/`LEVEL`/`FORMAT=json` set pre-`RcloneInitialize`; `tailEngineLog` from offset; `core/stats` + `job/status` + `job/stop` drive lifecycle; mode banner; mobile wireframe UI.
**Verify:** on an emulator, run `copy` via the palette, see log-tail + progress stream live, Stop via `job/stop`; confirm the CLI mode is hidden and the banner explains why.

### Phase 5 — polish (optional)
Custom cgo `OutputHandler.AddOutput` export for a clean per-group log feed on FFI (retires the interleave heuristic); re-runnable blocks UX; filter/copy refinements; STREAM_ONLY_STDOUT/STDERR split view; ring-buffer tuning; split-pane console-beside-console.
**Verify:** on FFI, two concurrent activities produce cleanly separated per-command log feeds.

---

## 8. Open questions / risks

- **Streaming granularity (desktop):** rclone never calls `http.Flusher.Flush`, so low-volume/slow CLI output may sit in net/http's ~2–4 KB buffer until it fills or the process exits — the console can look "hung". Consider surfacing a subtle "running…" spinner driven by `core/stats`/log-tail so the UI never looks dead even when stdout is quiet. Can we upstream a per-line flush to our pinned rclone build?
- **FFI log interleave:** with stock librclone the single log file mixes background transfers, browsing, and the console command. The serialize-commands + `core/stats`-group + timestamp heuristic is *good enough* but not exact. Phase 5's `AddOutput` export is the real fix — is the cgo callback worth the custom-build maintenance now vs later?
- **Blocked-tier UX:** blocking `mount`/`serve`/`rc`/`config` is correct but power users will try them. How loud is the rejection, and do we offer a "use Airclone's own mount/serve manager instead" redirect?
- **Redaction is deny-list-shaped:** a novel backend secret flag not matching `--*-pass/key/token/secret` could leak. The `Authorization`/`Bearer`/`AWS4-HMAC`/`token=` output scrubber is the backstop — is it enough, or do we drive redaction from `config/providers` `Option.Sensitive`/`IsPassword` metadata (authoritative per-backend) instead of a pattern list?
- **Destructive-flag evasion:** `sync --track-renames`, `move` (deletes source), `--delete-excluded` on a `copy` — classification must key on the parsed flag set, and the flag denylist needs periodic review against new rclone versions. Own a test that asserts the destructive set against the bundled command table each version bump.
- **COMBINED_OUTPUT memory (Phase 1):** buffers all output in RAM — cap output size and prefer STREAM (Phase 3) for anything potentially large before shipping Phase 1 broadly.
- **Mobile expectation gap:** users will expect terminal-like CLI parity on mobile. The banner helps, but is "RC-method console" discoverable/teachable enough, or does it need an onboarding note?
- **rc security boundary:** `core/command` is arbitrary rclone-CLI execution; the rc port must stay localhost-bound with auth. Confirm no path widens the rc binding when the console is enabled.

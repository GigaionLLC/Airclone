# 📦 Parcel Plan: Guided remote setup ("Add a cloud" that walks you through it)

## 📊 State Dashboard
| Metric | Value |
| :--- | :--- |
| **Status** | `BUILT` — Phases A–F landed together; analyze, format and both test suites clean (1771 app + 91 package). §2.4 deleted the native stderr-capture code the design originally needed. Outstanding: the security review gate, and a manual pass on real accounts. |
| **Version** | `v2.0.0` |
| **Active Persona** | `Architect` |
| **Last Updated** | 2026-09-20 |

---

## 1️⃣ Phase 1: Expansion & Scoping

* **Intent:** Make adding a cloud the easy, obvious path on every platform. A **guided** flow is the
  default click — pick Google Drive, press *Sign in*, done — while today's full-options form stays
  intact behind **Advanced** for people who want to set every field themselves. The guided flow is
  driven by **rclone's own interactive config state machine**, the same one `rclone config` drives,
  not a parallel implementation.

* **In Scope:**
  - Guided mode as the default action of the add-remote flow; Advanced reachable from three places.
  - Correct use of the state machine: drop `opt.all`, pre-answer the noise, re-send sticky ephemeral
    answers on every `continue`, run the call `_async` and poll.
  - A real step UI: choice questions become pickers, bools become Yes/No, passwords obscure.
  - OAuth as a first-class screen: one primary *Sign in* button, with every method that can actually
    succeed for that backend on that platform behind an *Other ways* link. Progress, Cancel, and
    honest errors.
  - Auth-URL capture so mobile (where rclone cannot open a browser) can open it itself.
  - Curated provider picker: popular tiles first, friendly names, search aliases, and hand-written
    opening screens for eight key/secret providers.
  - The Google Drive / Google Photos shared-client_id screen and its bring-your-own walkthrough
    (§2.2), plus recognising that failure on an existing remote and offering the same walkthrough.
  - Connection verification after creation, with a real success screen.
  - Every failure path logged to `state/diagnostics.dart`.

* **Out of Scope:**
  - **Airclone registering its own OAuth client.** Google treats the full Drive scope as restricted,
    which carries an annual third-party security assessment; that is the likely reason rclone is
    retiring theirs. If it is ever revisited, the cost and obligations must be verified first — this
    plan does not assume it.
  - Proactively migrating existing Drive remotes off the shared client_id (§3 Round 5).
  - Provider brand **logos** (trademark). Names are nominative use and fine; artwork is not in this
    plan.
  - A full first-run onboarding tour. The zero-remotes empty state stays the entry point.
  - Any change to the config file format, config encryption, or the QR transfer envelope.
  - Editing an existing remote — `showEditRemoteDialog` keeps using the Advanced form as today.
  - **TV-specific machinery.** No LAN push, no D-pad token flow. On a TV the chooser hides what
    cannot work and points at importing a config; nothing new is built for it.

## 2️⃣ Phase 2: Requirements & Context

* **Relevant Docs:**
  - `wiki/core/08-core-architecture.md` → three engines behind one `RcloneClient`; the package
    boundary rules this plan must not break.
  - `wiki/core/06-design-system.md` + `DESIGN.md` → tokens for every new surface.
  - `wiki/core/11-validation-standards.md`, `wiki/core/15-security.md` → new input fields, pasted
    tokens, and a loopback listener.
  - `wiki/core/14-performance-standards.md` → polling budgets for the `_async` job poll.
  - `dev/backlog/feature-backlog.md` → records this exact gap: *"A **guided** first-run wizard is not
    built."*
  - `dev/archive-plans/config-portability-plan.md` → the QR/config transfer reused by the
    other-device branch.

* **Relevant Code:**
  - `app/lib/src/state/add_remote_controller.dart` → the state machine driver. Changes most.
  - `app/lib/src/ui/add_remote_dialog.dart` (685 lines) → split; becomes picker + guided + advanced.
  - `app/lib/src/state/providers_provider.dart` → cached `config/providers`; gains the curated join.
  - `packages/airclone_rc/lib/src/http_rclone_client.dart` → `_readOutput`/`_onEngineLine` already
    drain every `rcd` line; add the auth-URL observer beside the filtered log sink.
  - `packages/airclone_rc/lib/src/ffi_rclone_client.dart` + `librclone_ffi_io.dart` → the FFI worker
    isolate that must not be blocked, and where stderr capture is wired.
  - `app/lib/src/state/config_transfer_controller.dart`, `ui/scan_from_desktop_sheet.dart`,
    `ui/config_import_dialog.dart`, `state/offline_qr.dart` → reused by the other-device branch.
  - `app/lib/src/state/config_backups.dart` (shared-storage `Airclone/` folder) → the only way a TV
    can find a config file, since its file picker is a framework stub.
  - Entry points to keep working: `ui/browser_pane.dart:305`, `ui/home_screen.dart:529` and `:1109`,
    `ui/home_view.dart:182`, `ui/mobile_action_sheets.dart:488`.

### 2.1 Ground truth — how rclone's config machine actually behaves

Read from the **rclone v1.74.4** source in the local Go module cache, then **verified against a
locally built rclone v1.75.1** by live capture — see **§2.2**, which confirms every claim below that
the app depends on and adds one the source read could not have predicted.

1. **The state machine is frontend-agnostic on purpose.** `fs/backend_config.go` — *"The interactive
   config system for backends is state based. This is so that different frontends to the config can
   be attached, eg over the API or web page."* rclone ships `bin/config.py` as a reference frontend.
2. **librclone is not second-class.** `librclone/librclone.go` `RPC()` dispatches via
   `jobs.NewJob(...)`, the same path as the HTTP server — so `_async`, `_group` and `job/status` all
   work in-process. Both Airclone engines get identical config behaviour.
3. **`opt.all` is the wrong mode for a guided flow.** `configAll` walks *every* option one question
   at a time. With `all` off, only the backend's post-config (`ri.Config`) runs.
4. **Any question can be pre-answered.** `backendConfigStep`: *"If override value is set in the
   choices then use that"* — `choices` is the `parameters` map. This includes the ephemeral
   `config_*` questions (`config_is_local`, `config_change_team_drive`, `config_fs_advanced`).
5. **Ephemeral answers do not persist.** `updateRemote` skips `m.Set` for keys prefixed
   `fs.ConfigKeyEphemeralPrefix` (`config_`), and rebuilds `choices` from `parameters` on every call.
   So sticky pre-answers **must be re-sent on each `continue`**.
6. **Today we ask everything twice.** `submit()` sends only non-empty values with `all: true`, so
   every field left blank in the form comes back as a question. Adding Drive asks for `client_id`,
   `client_secret`, `scope`, `service_account_file` again, then "Edit advanced config?", before OAuth.
7. **OAuth blocks inside the RC call.** `oauthutil.configSetup` binds the hard-coded
   `127.0.0.1:53682`, calls `OpenURL`, then blocks on a channel until the redirect lands.
   - `OpenURL` is `var OpenURL = open.Start` — a documented override point.
   - `config_auth_no_browser` (non-empty) suppresses the browser open; rclone then only *logs* the
     link.
   - The link is always `http://127.0.0.1:53682/auth?state=<random>`.
8. **Nothing cancels that wait**, and `job/stop` will not help (it blocks on a channel, not on ctx).
   The listener holds the port, so a second attempt fails to bind. **But `handleAuth` pushes a
   failure onto the result channel for any request to `/` without a `code`** — so a plain
   `GET http://127.0.0.1:53682/` is a working Cancel, and releases the port.
9. **A half-finished create is already on disk.** `CreateRemote` deletes any existing section, sets
   `type`, runs the machine, and `updateRemote` calls `SaveConfig()` when the call returns — which it
   does at the first question. So by the time the sign-in screen appears, a typed-but-unauthorized
   remote exists. This is what makes the cancel policy in §4 Phase A necessary.
10. **23 of 69 backends have a post-config flow** (drive, dropbox, onedrive, box, pcloud, jottacloud,
    icloud, s3, …). The other 46 (b2, sftp, webdav, ftp, smb, azureblob, crypt, …) ask **nothing**
    when `all` is off — their fields are plain options.
11. **`Required` is not a usable recipe source.** s3 and azureblob mark **zero** options required;
    sftp marks one (`host`, not `user`/`pass`). b2 is the only tidy one. What *is* usable is rclone's
    standard/advanced split plus `MatchProvider` gating — picking "AWS" under s3 cuts ~95 options to
    roughly ten.
12. **Cross-device sign-in needs the loopback port on the browser's machine.** `remote_setup.md`
    documents three methods: `rclone authorize` on a machine that has rclone; copying the config
    file; and an **SSH tunnel** (`ssh -L localhost:53682:localhost:53682 user@host`) which needs no
    rclone on the browser side — because the provider always redirects to loopback:53682, that port
    simply has to resolve to the machine running rclone.
13. **Exactly one backend (HiDrive) still uses the old paste-a-code redirect**
    (`oauthutil.TitleBarRedirectURL`). Everywhere else, "copy a link, paste a code" cannot complete.
14. **The FFI worker serializes RPCs.** `librclone_ffi_io.dart` `_workerEntry` handles commands one
    at a time and `b.rpc(...)` is a blocking C call — so a blocking `config/create` freezes *every*
    RC call app-wide. `_async` is mandatory there, not a nicety.
15. **`RCLONE_LOG_FILE` does nothing under librclone.** `fs.GlobalOptionsInit()` — which loads
    registered global option blocks from `RCLONE_*` env — is called only from `cmd/cmd.go`.
    `log.InitLogging()` binds the writer once from `Opt.File`, and the `log` block registers no
    `Reload` hook, so `options/set` cannot enable it later either.
16. **`rcd` is started at default verbosity** (`http_rclone_client.dart` argv has no `-q`/
    `--log-level`), so rclone's NOTICE lines — including the auth link — do reach our line reader.
    A user-supplied `-q` in advanced flags would suppress them; handle that as a timeout.

### 2.2 Verification results — live capture against rclone v1.75.1

Built from the Go module cache and driven against scratch config files. No account, no credentials,
no browser opened, no network call to any provider. Transcripts become the test fixtures.

**New — not present in 1.74.4, and it changes the Google Drive design:**

Google Drive and Google Photos no longer open on OAuth. They open on a warning:

```
State:  client_id_warning
Option: config_shared_client_id   (bool, Exclusive, Default FALSE)
Help:   "rclone's shared Google Drive client_id is being retired and will stop working
         during 2026. Create your own to avoid interruption:
         https://rclone.org/drive/#making-your-own-client-id
         Continue using the shared client_id anyway?"
```

- Answer **true** → `*oauth-islocal,teamdrive,oauth,` — the familiar flow, on a client_id rclone says
  stops working during 2026 (and it is already 2026).
- Answer **false** → `client_id_set` (`client_id`, Required) → `client_secret_set` (`client_secret`,
  Required) → `*oauth-islocal,teamdrive,oauth,`.
- `googlecloudstorage` has **no** such warning; Drive and Google Photos do.
- **rclone's own default answer is `false`** — decline the shared ID.

This is a product decision, not an implementation detail: a one-click "Sign in with Google" that
silently answers `true` signs people up for something with a stated expiry. See the open question in
§3.

**Confirmed as written in §2.1:**

| Claim | Observed |
| :--- | :--- |
| §2.1.3/.10 — 46 backends ask nothing with `all` off | `s3`, `b2`, `sftp`, `webdav` all returned `"State": ""` immediately and wrote only `type = <backend>`. An empty, unusable remote. |
| §2.1.9 — a half-finished create is already on disk | Every opening call left `[name] type = …` in the config before any question was answered. |
| §2.1.7 — the logged auth link | `NOTICE: Please go to the following link: http://127.0.0.1:53682/auth?state=28PXJCSPZHXa3sbLXr3YTg`, with `config_auth_no_browser` suppressing the browser open. Port confirmed LISTENING while blocked. |
| §2.1.8 — a plain GET cancels it | `GET http://127.0.0.1:53682/` → HTTP 400, rclone unblocked immediately, listener gone. Error text is `config failed to refresh token: Error: Auth Error … Description: No code returned by remote server` — the string the UI must translate into "Sign-in cancelled". |
| §2.1.2 — `_async` on `config/create` | Returned `{"jobid": 1}`; `job/status` came back with `finished: true` and `output` carrying the full `State`/`Option`/`Error`. The FFI path is viable exactly as planned. |

**Smaller findings that affect the UI:**

- `client_secret` is **not** flagged `IsPassword` (nor `Sensitive`) by the Drive backend. Our field
  must obscure it anyway — trusting the flag would print a secret on screen.
- OneDrive's post-OAuth return state is `choose_type` (region / drive type), so its guided flow has a
  question *after* sign-in, unlike Dropbox and Box which return `*oauth-islocal,,,` and finish.
- A `--continue`/`continue: true` call **requires the section to already exist**; the RC form must
  keep sending `type` on every continue, which `add_remote_controller` already does.

### 2.3 Verification results — stderr capture, the FFI auth-URL path

Run 2026-09-20 against **librclone v1.75.1 built by the scripts we already ship**
(`dev/desktop/build-librclone.ps1` → `librclone.dll`; the Linux arm of `build-librclone.sh` →
`librclone.so`). Each probe drove a real `config/create` for `drive` with the questions pre-answered,
so rclone walked into the blocking OAuth wait and logged the link. No account, no credentials, no
browser, no provider network call.

**POSIX (Linux x86_64) — the stand-in for iOS and MAS.** Harness in C over `dlopen` plus libc
`pipe`/`dup2` — the same calls `dart:ffi` makes.

| Order | Result |
| :--- | :--- |
| `dup2` **before** `dlopen` | **PASS** — `NOTICE: Please go to the following link: http://127.0.0.1:53682/auth?state=…` read out of the pipe 100 ms after the call |
| `dup2` **after** `RcloneInitialize` | **PASS** — identical |

**Ordering does not matter on POSIX.** Go's `os.Stderr` wraps fd 2 itself and resolves it at every
write, so a later `dup2` simply re-points it. This is the result **iOS depends on**: there librclone
is statically linked (`librcloneIsStaticallyLinked`) and its runtime starts before any Dart code
runs, so a mechanism that demanded "before the library loads" would have been unusable.

Pipe capacity measured at **65536 bytes** (`F_GETPIPE_SZ`) — the plan's 64 KiB draining requirement
is the right number.

**Windows — the desktop-FFI engine.** Harness in **Dart over `dart:ffi`**, i.e. the production
mechanism, not a C stand-in.

| Mechanism | Result |
| :--- | :--- |
| CRT `_pipe` + `_dup2(w, 2)` before load — *the plan as originally written* | **FAIL**, and destructively so |
| `CreatePipe` + `SetStdHandle(STD_ERROR_HANDLE, w)` **before** `DynamicLibrary.open` | **PASS** — URL captured in 100 ms |
| `SetStdHandle` **after** the library is loaded | **FAIL** — nothing captured, log still on the console |

Go on Windows does not use the C runtime's file descriptors. `syscall.Stderr` is the **HANDLE** from
`GetStdHandle(STD_ERROR_HANDLE)`, captured once when the Go runtime initialises — which for a
`c-shared` DLL is at `DllMain`, i.e. at `DynamicLibrary.open`. Hence the third row.

**The first row is the finding that matters.** `_dup2` did not merely fail to capture anything:
instrumentation showed `STD_ERROR_HANDLE` unchanged at `392` before and after the call, while
`_dup2` **closed** the handle that fd 2 had been holding — handle `392` itself. Go then wrote every
NOTICE into a closed handle. A full-output capture found **zero** NOTICE lines anywhere: not in the
pipe, not on the console. So the naive port of the POSIX mechanism to Windows would have silently
destroyed engine logging while looking like nothing more than a capture that never fired.

**Consequences for Phase B:** the capture is platform-split, and on Windows it must run **inside the
worker isolate before it opens the library**. `SetStdHandle` is process-global, so the redirect is
scoped to the FFI engine and the original handle is restored on engine shutdown.

**Two further findings from the same runs:**

1. **Nothing is written to disk when the first call blocks in OAuth.** After five probe runs that
   each reached the blocking wait, **no config file existed at all** — on either platform. §2.1.9
   still holds as stated (the save happens when a call *returns* at a question), but the guided flow
   pre-answers the questions and so can go straight into OAuth on the opening call, with nothing
   persisted. Delete-on-cancel must therefore tolerate a section that was never written.
2. **`config/delete` cannot report failure.** `rcDelete` calls `DeleteRemote(name)`, which is `void`;
   `DeleteSection` on a missing section is a silent no-op, and `SaveConfig()` returns nothing —
   on repeated save failure it only logs `Failed to save config after N tries`. So `config/delete`
   answers `200` whether it deleted a remote, deleted nothing, or failed to write the file. The same
   swallow applies to a failed save after `config/create`. Phase A.5 cannot trust the status code:
   it must confirm with `config/listremotes` afterwards.

**A correction to the scope of §2.1.15:** `RCLONE_LOG_FILE` is dead under librclone because it is
read through `fs.GlobalOptionsInit()`, but **`RCLONE_CONFIG` is live** — `fs/config/config.go:258`
reads it directly with `os.LookupEnv`. The probe also confirmed the `config/setpath` RC method works
in-process, which is how these runs kept away from the real config. Not every `RCLONE_*` variable is
dead under librclone; only those routed through the global-options block.

**What this does not prove.** Linux stands in for Darwin — both are POSIX, both give Go `os.Stderr`
as fd 2 — but the iOS device path (static `c-archive`, `SFSafariViewController`, the app staying
foregrounded) is verified by proxy, not on a device. That stays a manual check in Phase E.

### 2.4 Verification results — rclone 1.75 exposes OAuth as RC methods (supersedes most of §2.3)

Found while implementing Phase B, verified live the same day against the same `librclone.dll`.
**rclone 1.75 added two RC methods that 1.74.4 does not have** — which is why reading 1.74.4 for
§2.1 missed them:

| Method | Returns |
| :--- | :--- |
| `config/oauthstatus` | `{"status": "running", "authUrl": "http://127.0.0.1:53682/auth?state=…"}` while a flow is blocked, `{"status": "stopped"}` otherwise |
| `config/oauthstop` | cancels the in-progress flow through its `context.CancelFunc` |

Observed, driving a real Drive `config/create`:

```
oauthstatus RUNNING after 200 ms
authUrl = http://127.0.0.1:53682/auth?state=5TrmzKXWLumDroMO3WZq8g
port 53682 is LISTENING
config/oauthstop -> 200 {}
job finished after stop, 0 ms
job error = config failed to refresh token: oauth authentication was cancelled
port 53682 released after stop (good)
oauthstop when idle -> 500 "no oauth authentication is in progress"
```

**What this replaces.** The auth URL is now *asked for*, not scraped out of a log line. That removes
the entire stderr-capture subsystem from the shipping design: no fd-2 pipe, no `SetStdHandle`, no
platform-split native code, no Go shim escape hatch, and none of the Windows hazard §2.3 found. It
also gives a real cancel: `config/oauthstop` ends the flow through rclone's own cancel function and
reports `oauth authentication was cancelled` — a far better string to translate than the loopback
GET's `No code returned by remote server`.

§2.3 stays in this document because it is a true record and because it is the reason we are glad not
to need it — shipping that mechanism on Windows would have silently destroyed engine logging.

**Where the old path is still needed.** `RcloneEngine.minRcloneVersion` is `1.73.5`, and on desktop
the user may point Airclone at their own rclone binary. So:

- **Both engines, rclone ≥ 1.75:** poll `config/oauthstatus`; cancel with `config/oauthstop`.
- **Desktop `rcd`, rclone 1.73.5–1.74.x:** fall back to the engine line reader (`AuthUrlObserver` +
  `parseAuthUrl`, §2.1.16) and the loopback-GET cancel (§2.1.8). Both already work there.
- **FFI engines are never old:** iOS, MAS and desktop-FFI all load a librclone *we* build (v1.75.1),
  and Android bundles its own rclone. So the case that needed stderr capture — an old engine behind
  FFI — cannot arise.

Detection is **behavioural, not version-string**: call `config/oauthstatus` once and fall back if it
errors. A version string tells you what rclone claims to be; a method call tells you what it has.

**Two behaviours the UI must handle:**

1. `config/oauthstop` answers **500 `no oauth authentication is in progress`** when nothing is
   running. Cancel must treat that as success, not as a failed cancel — it is the state we wanted.
2. `oauthURL` is a package-level global guarded by one mutex, and rclone binds a single fixed port,
   so **only one sign-in can be in flight per engine process**. The UI must not offer to start a
   second while one is running.

**One design change this enables.** With the URL reliably available on every platform, the flow now
always sends `config_auth_no_browser=true` and opens the URL itself through `url_launcher`, instead
of letting rclone open a browser on desktop and only self-opening on mobile (§3 Round 2 assumed the
split because the URL was not reliably in hand). One code path, same behaviour everywhere, and the
link is on screen to copy whatever happens.

## 3️⃣ Phase 3: User Clarification

All four rounds answered before any code. Answers are binding on Phase 4.

**Round 1 — flow shape**
- `[x]` Provider picker layout? → **Popular first, then all.** ~10 curated tiles, an "All storage
  types" expander, search across both.
- `[x]` Where does naming happen? → **Auto-named, editable on the final screen.** Suggested from the
  provider and deduped; nobody is stopped at step one to invent a name.
- `[x]` Where does Advanced appear? → **All three:** a link in the guided step header, a secondary
  action on each provider tile, and an automatic offer on the failure screen carrying values over.
- `[x]` After success? → **Verify, then a success screen** naming what was reached, with
  *Open it* / *Add another* / *Done*.

**Round 2 — sign-in behaviour**
- `[x]` Chooser every time? → **No. One primary *Sign in* button**, with *Other ways to sign in*
  revealing the rest — visible before anything fails.
- `[x]` Cancelled sign-in leaves a typed-but-unauthorized remote (§2.1.9)? → **Delete it on cancel.**
  Creates only; cancelling mid-OAuth while *editing* must never delete. A failed delete is reported,
  never silently swallowed.
- `[x]` Waiting screen? → **Wait indefinitely** with the link shown and Cancel available; at ~45 s a
  quiet *Taking a while? Try another way* reveals the other methods without cancelling.
- `[x]` Android TV? → **Nothing TV-specific.** Hide the methods that cannot work, explain why, and
  point at importing a config — which on TV must list candidates from the shared-storage `Airclone/`
  folder, because `OPEN_DOCUMENT` there is a framework stub.

**Round 3 — per-provider content**
- `[x]` Which providers get hand-written screens? → **s3, b2, sftp, webdav, ftp, smb, azureblob,
  crypt** — exactly the ones where rclone asks nothing.
- `[x]` S3-compatible brands? → **Own tiles** for Cloudflare R2, Wasabi, MinIO, Storj and DigitalOcean
  Spaces, pre-setting `type=s3` plus the right `provider`.
- `[x]` Step layout for those? → **One screen, all essentials together.**
- `[x]` Verification fails? → **Show what rclone returned, offer *Fix settings* (values intact) or
  *Keep anyway*.** The remote stays unless the user backs out.

**Round 4 — verification & rollout**
- `[x]` Test fixtures? → **Capture real transcripts from rclone 1.75.1** (§4 Verification).
- `[x]` Rollout? → **Guided is the default immediately.** No feature flag.
- `[x]` Sequencing? → **One feature release with everything** (Phases A–F together).
- `[x]` Review? → **Security-focused adversarial review before merge** over the loopback listener and
  its cancel, pasted tokens, the auth URL the app will open, and what can reach diagnostics or a screenshot.

**Round 5 — Google Drive's retiring client_id (raised by the §2.2 capture)**
- `[x]` What does the guided flow do with `config_shared_client_id`? → **Ask, recommending their own
  ID.** A real screen with two honest choices: *Set up your own sign-in (recommended)* → walkthrough,
  or *Use the shared one for now* → straight to OAuth with the expiry stated and a note that it can
  be changed later in Advanced. Mirrors rclone's own default without forcing a console errand on
  someone who just wants their files today.
- `[x]` Where does the walkthrough live? → **Both.** A short in-app summary of the four things they
  need, with the paste boxes, plus a *full instructions* link to rclone's own guide for anyone who
  wants detail.
- `[x]` Existing Drive remotes on the shared ID? → **Only when it breaks.** No proactive notice;
  recognise the authentication failure when it happens and offer the walkthrough from the failure
  screen. Migration is otherwise out of scope for this plan.

**Round 6 — surface and wording**
- `[x]` What is it called? → **"Add a cloud."** "Remote" stays in Advanced and the console, where
  rclone's vocabulary is what users expect.
- `[x]` Desktop surface? → **A dialog that grows to fit the step** — wider for the picker, taller for
  the walkthrough. The app stays visible behind it.
- `[x]` Popular tiles? → **Ten:** Google Drive, OneDrive, Dropbox, iCloud Drive, Google Photos,
  Amazon S3, Cloudflare R2, Backblaze B2, SFTP, WebDAV. Wasabi, MinIO, Storj and DigitalOcean Spaces
  resolve through **search aliases** that preset `provider`, not tiles.
- `[x]` Does Advanced change? → **A filter box over the options**, and nothing else. S3 has 95
  options; finding `endpoint` by scrolling is the current reality.

## 4️⃣ Phase 4: Detailed Execution Plan

### Architecture

Guided and Advanced are **two front ends over one driver**. The driver is the corrected state-machine
loop; the difference is only which `parameters` it opens with and which questions it renders itself.

```
picker (popular → all) ─┬─► GUIDED  ─► our screen(s) ─┐
                        └─► ADVANCED ─► option form  ─┴─► config/create (_async, no `all`)
                                                          │
                                        ┌─────────────────┴──────────────────┐
                                        ▼                                    ▼
                               question loop (continue)              finished → verify → success
                                        │
                         ┌──────────────┴───────────────┐
                         ▼                              ▼
               config_is_local → sign-in step      everything else → generic step UI
```

### Files to touch

> This is the list as planned. Two names and one file changed on the way in; the **Built**
> section at the end of Phase 4 records each difference and why.

**New**
- `app/lib/src/state/remote_setup_recipes.dart` → pure data + lookup: friendly name, category, search
  aliases, S3 brand presets, and for the eight recipe backends an ordered essentials list with our
  own copy. No Flutter imports; unit-tested.
- `app/lib/src/state/oauth_signin_controller.dart` → one sign-in attempt: chosen method, `_async` job
  id, captured auth URL, cancel, the 45 s nudge, diagnostics.
- `app/lib/src/ui/add_remote/provider_picker.dart` → popular tiles, "All storage types" expander,
  search across names and aliases, per-tile Advanced action.
- `app/lib/src/ui/add_remote/guided_steps.dart` → the stepper: our screens plus rclone's questions.
- `app/lib/src/ui/add_remote/sign_in_step.dart` → primary button, *Other ways*, waiting state,
  other-device screens.
- `app/lib/src/ui/add_remote/own_client_id_step.dart` → the `config_shared_client_id` screen and the
  summary-plus-link walkthrough with obscured paste boxes (§2.2, Phase C).
- `app/lib/src/ui/add_remote/advanced_form.dart` → today's form, moved as-is plus a filter box over
  the option list (the only change to the manual path).
- `packages/airclone_rc/lib/src/auth_url_observer.dart` → capability interface + pure
  `parseAuthUrl(String line)`.

**Changed**
- `app/lib/src/state/add_remote_controller.dart` → driver corrections (Phase A).
- `app/lib/src/ui/add_remote_dialog.dart` → thin router over the four UI files.
- `packages/airclone_rc/lib/src/http_rclone_client.dart` → implement `AuthUrlObserver` off the
  existing line reader.
(The FFI clients need no change at all: §2.4 replaced stderr capture with `config/oauthstatus`.)
- `app/macos/Runner/*.entitlements` (MAS variant) → `com.apple.security.network.server`.
- `app/pubspec.yaml` → `url_launcher` if not already present.

**Package boundary (AGENT.md §3.0):** `RcloneClient` gains **no** member. `AuthUrlObserver` is a
separate interface, exactly as `ObjectUploader` is, and the app checks `client is AuthUrlObserver`.
Engine lines still reach the host only through the filtered sink; the observer emits a **parsed
`Uri`**, never a raw line.

### Phase A — Fix the driver

1. **Drop `opt.all` everywhere.** Advanced already renders every option, so the form is the source of
   truth; unsent options keep rclone's defaults instead of being written as empty strings. This alone
   removes the double-ask (§2.1.6).
2. **Sticky ephemeral answers.** A `Map<String,String>` of non-secret `config_*` pre-answers merged
   into `parameters` on **every** call including `continue` (§2.1.5). Secrets are still never
   re-sent — the existing comment in `answer()` stays true and must be kept.
3. **Run `_async`.** Add `'_async': true`, take `jobid`, poll `job/status`, map both the RC error and
   the job's `error` field. Mandatory for FFI (§2.1.14); on rcd it buys cancel and progress.
4. **Cancel.** `config/oauthstop` ends the blocked wait cleanly and frees the port (§2.4), with the
   loopback `GET http://127.0.0.1:53682/` as the fallback for pre-1.75 engines (§2.1.8). Wired to
   both the Cancel button and dialog dismissal.
5. **Delete-on-cancel.** After cancelling a *create*, `config/delete` the half-written section
   (§2.1.9) — harmless when the flow never got far enough to write one, which §2.3 found is the
   common case for guided sign-in. Never on an edit. `config/delete` answers `200` even when it
   deleted nothing or failed to save the file (§2.3), so confirm with `config/listremotes` and
   report a survivor explicitly rather than trusting the status code.
6. **Bind-failure message.** Recognise `failed to start auth webserver` and explain that another
   rclone — or a previous abandoned attempt — holds 53682, with a Retry that cancels first.

### Phase B — Getting the auth URL, and cancelling

**Primary path (both engines, rclone ≥ 1.75 — §2.4):** once the `_async` create is running, poll
`config/oauthstatus` until it reports `running` and hands back `authUrl`. Cancel with
`config/oauthstop`. No log parsing, no native code, no platform split.

- Poll at 250 ms, which §2.4 measured as roughly one tick behind readiness.
- `config/oauthstop` answering **500 `no oauth authentication is in progress` is success** — it is
  the state cancel wanted.
- Only **one sign-in per engine** can be in flight (`oauthURL` is a global, and the port is fixed),
  so the UI must not offer to start a second.

**Fallback (desktop `rcd` only, rclone 1.73.5–1.74.x):** those builds have neither method, so keep
the engine-line route for them.

- `parseAuthUrl(line)` matches `http://127.0.0.1:53682/auth?state=…` and **nothing else**. Host,
  port and path are rclone constants (§2.1.7), and pinning all three is what stops a crafted log
  line from talking the app into opening an arbitrary URL. Covers all three NOTICE wordings.
- Hooked off the existing `_onEngineLine` drain. The raw line must **not** enter diagnostics — only
  the parsed `Uri` leaves the package, through the `AuthUrlObserver` capability interface.
- Cancel for these engines is the loopback `GET http://127.0.0.1:53682/` (§2.1.8).

**Which path is chosen is decided by calling, not by parsing a version string** (§2.4): try
`config/oauthstatus` once, fall back on error, remember the answer for the engine's lifetime.

**Timeout:** no URL from either path within 10 s ⇒ stop waiting, show the other-device methods, and
say why.

### Phase C — The sign-in step

Reaching the `config_is_local` question renders **our** screen, not rclone's Yes/No: one primary
*Sign in with <provider>* button, and an *Other ways to sign in* link. Each choice answers on the
user's behalf:

| Method | We send | Then |
| :--- | :--- | :--- |
| **Sign in on this device** *(primary)* | `config_is_local=true` (+ `config_auth_no_browser=true` on mobile) | Desktop: rclone opens the browser. Mobile: we open the captured URL — Android Custom Tab / iOS `SFSafariViewController`. **Never an embedded WebView** — Google blocks OAuth from those. |
| **Show me the link** | `config_is_local=true` + `config_auth_no_browser=true` | The captured URL + QR + copy, and the `ssh -L localhost:53682:localhost:53682 …` line, with a plain note that the link only works where that port reaches this device (§2.1.12). |
| **Authorize on another device** | `config_is_local=false` | rclone returns the `rclone authorize "drive" "<blob>"` text; rendered as a real screen — copy button, QR of the command so a phone can read it off a screen, paste box for the token. |
| **Set it up in Airclone elsewhere** | *(cancels, then deletes)* | Hands off to the existing encrypted QR/config transfer. Needs a single-remote export filter over `config/dump` plus the existing `mergeRemotes`. |

**Availability is detected, not hard-coded.** Paste-a-code appears only if the flow actually returns
`config_verification_code` (HiDrive today, §2.1.13); the authorize hand-off only if it returns
`config_token`. *Sign in on this device* is hidden where no browser exists (TV).

**Before sign-in, for Drive and Google Photos only** (`config_shared_client_id`, §2.2): a screen
stating plainly that Google is retiring rclone's shared sign-in during 2026, with

- *Set up your own sign-in (recommended)* → answers `false`, then a screen carrying a four-point
  summary (create a project, enable the API, configure consent, create a **Desktop** OAuth client),
  a *full instructions* link to rclone's guide, and paste boxes for `client_id` and `client_secret`.
  **Both boxes obscure**, because §2.2 found `client_secret` is not flagged `IsPassword` or
  `Sensitive` and trusting the flag would print a secret on screen.
- *Use the shared one for now* → answers `true`, states the expiry, and notes it can be changed later
  from Advanced.

The screen is driven by the question rclone asks, not by a hard-coded provider list — if rclone adds
the warning to another backend, or drops it, the flow follows automatically.

**When an existing Drive remote fails to authenticate**, recognise it on the error path and offer the
same walkthrough. No proactive scan, no banner, no migration tooling.

**Waiting state:** spinner, link visible and copyable, Cancel throughout, and at ~45 s the *Try
another way* nudge. No hard timeout.

### Phase D — Guided stepper and picker

- **Picker ("Add a cloud"):** ten tiles — Google Drive, OneDrive, Dropbox, iCloud Drive, Google
  Photos, Amazon S3, Cloudflare R2, Backblaze B2, SFTP, WebDAV. Wasabi, MinIO, Storj and DigitalOcean
  Spaces are **search aliases** that resolve to `type=s3` with `provider` preset, not tiles. An "All
  storage types" expander holds the other 59; search covers names, descriptions and aliases. Each
  tile carries a secondary Advanced action.
- **Surface:** one dialog whose size is per-step (wider for the picker, taller for the walkthrough),
  never a fixed box. Mobile uses the full-screen route as the shell already requires.
- **Name:** auto-suggested (`gdrive`, `gdrive-2`, …) via the existing `existingRemoteNames`
  uniqueness check and editable on the final screen — never a blocking first step.
- **Essentials screen:** from the recipe when there is one (all fields on **one** screen), else
  generically from the provider's non-advanced options filtered by `MatchProvider` against the
  chosen `provider` (§2.1.11), with rclone's help text.
- **rclone's questions** get real widgets: `Examples` + `Exclusive` → picker (this fixes the Shared
  Drive question, today a bare text field where you must type a drive ID), `IsPassword` → obscured,
  bool → Yes/No.
- **Finish:** run the existing connection test, then a success screen naming what was reached
  ("Connected — 14 items at the root") with *Open it* / *Add another* / *Done*. On failure, show
  rclone's actual error with *Fix settings* (values intact) and *Keep anyway*.

### Phase E — Mobile shells

- Every new dialog uses `DialogBody` (MediaQuery) and `Wrap` for action rows — the fixed-width
  clipping rule that previously made Android config import look broken.
- `+` FAB / bottom-sheet entry points get the guided flow; the header `⋯` must keep rendering.
- **MAS:** add `com.apple.security.network.server`, the same entitlement previews needed — without it
  rclone cannot bind 53682 and sign-in fails with a bind error.
- **iOS:** keep the app foregrounded during auth (`SFSafariViewController`), or iOS suspends the
  process and kills the listener mid-flow.
- **Android TV:** no TV-specific code. The chooser hides what cannot work, explains that remotes are
  added elsewhere and imported, and the import path lists candidates from the shared-storage
  `Airclone/` folder rather than opening a picker that does not exist there.

### Phase F — Docs

`wiki/features/` entry for the flow, a `wiki/logic/` note pointing at §2.1 as the reason the driver
looks the way it does, and the backlog line about the missing guided wizard flipped.

### Verification — DONE (see §2.2 and §2.3)

rclone v1.75.1 was built from the Go module cache and driven against scratch configs for drive,
googlephotos, googlecloudstorage, onedrive, dropbox, box, s3, b2, sftp and webdav, plus a live test
of the blocking OAuth wait, the loopback cancel, and `_async` over a throwaway `rcd`. No account, no
credentials, no browser, no provider network call. Results and corrections are in §2.2.

**Remaining verification work during implementation:** promote those transcripts into fixtures under
`app/test/fixtures/config_flows/`, promote the §2.3 probe harnesses to `dev/desktop/fd2-probe/`, and
re-run both whenever the rclone pin or the Go toolchain moves — the Drive finding in §2.2 is exactly
the kind of change a pin bump can introduce.

### Test Verification Plan

```
cd app && flutter analyze && dart format --set-exit-if-changed . && flutter test
cd packages/airclone_rc && dart analyze && dart format --set-exit-if-changed . && dart test
```

- `[ ]` `packages/airclone_rc/test/auth_url_parse_test.dart` — all three NOTICE variants, a line with
  no URL, a line carrying rc credentials (must not be echoed), a truncated line.
- `[ ]` `app/test/add_remote_request_test.dart` — bodies contain no `all`; sticky ephemerals re-sent
  on `continue`; passwords never re-sent; `_async` set; edit still routes to `config/update`.
- `[ ]` `app/test/guided_setup_steps_test.dart` — recipe hit, recipe miss falls back to generic,
  provider-gated filtering, S3 brand presets, name auto-suggest deduplication.
- `[ ]` `app/test/sign_in_step_test.dart` — replays the captured transcripts through a fake client;
  each method sends the right answer; availability follows the questions actually returned.
- `[ ]` `app/test/shared_client_id_test.dart` — both branches of the captured Drive transcript:
  accepting the shared ID reaches `*oauth-islocal`, declining reaches `client_id_set` then
  `client_secret_set`; the secret field obscures despite `IsPassword: false`; the screen appears for
  `googlephotos` and not for `googlecloudstorage`, driven by the question rather than a hard-coded
  list.
- `[ ]` `app/test/sign_in_cancel_test.dart` — cancel issues the loopback GET **and** deletes the
  half-created remote; cancelling before anything was written is a clean no-op (§2.3); an edit
  cancel deletes nothing; a survivor found by the post-delete `config/listremotes` check is
  reported, since the status code cannot say so (§2.3); a bind failure produces the explanatory
  error.
- `[ ]` Widget tests at real phone sizes for every new dialog (screen capture is impossible from a
  Claude Code desktop session — layout is verified by widget test, not screenshot).
- `[ ]` Manual: Google Drive end to end on Windows (rcd), Android (Custom Tab), and B2 on both.
- `[ ]` Manual: the desktop-FFI engine on Windows and macOS, plus iOS on a device — the one part of
  §2.3 verified only by proxy. The two probe harnesses are the reference; promote them to
  `dev/desktop/fd2-probe/` in Phase B so the check is repeatable on a pin bump.

### Review gate

Security-focused adversarial review before merge, scoped to: the loopback listener and its cancel;
pasted tokens; the auth URL the app is willing to open; what reaches diagnostics; and whether any auth URL or token can
land in a log, an export, or a screenshot.

### Risks

| Risk | Mitigation |
| :--- | :--- |
| Port 53682 already bound | Detect the bind error, explain it, offer Retry-after-cancel. |
| Abandoned flow holds the port | Cancel-on-dismiss via the loopback GET (§2.1.8). |
| Half-created remote left behind | Delete-on-cancel for creates; never for edits (§2.1.9). |
| rclone changes its log wording | Parser keyed on the constant port+path; timeout falls through to other-device methods; Go shim recorded as the escape hatch. |
| A user advanced `-q` flag hides the URL | Same timeout path, with a note naming the flag. |
| A crafted log line talks the app into opening a URL | The fallback parser pins host, port AND path to rclone constants; the primary path never parses text at all (§2.4). |
| An old user-supplied rclone has no `config/oauthstatus` | Detected by calling it, not by version string; falls back to the engine-line route, which those builds do support (§2.4). |
| Two sign-ins at once | rclone keeps one global `oauthURL` and one fixed port, so the UI refuses to start a second while one is running (§2.4). |
| iOS suspends the app mid-auth | In-app auth session keeps it foregrounded. |
| Google blocks OAuth in embedded WebViews | Custom Tabs / SFSafariViewController only — never a WebView. |
| §2.1 read at 1.74.4, shipping pin is 1.75.1 | Done — live capture in §2.2 confirmed it and found the Drive change. |
| Google retires the shared Drive client_id mid-release-cycle | The screen is driven by the question rclone asks, so the flow follows rclone's own change; failures on existing remotes route to the same walkthrough. |
| A pin bump silently changes a question sequence again | Re-run the §2.2 capture on every rclone pin bump and diff the fixtures — this is exactly how the Drive change was caught. |

### Built — what shipped, and where it differs from this plan

All of Phases A–F landed together, as Round 4 asked. `flutter analyze`, `dart analyze`,
`dart format --set-exit-if-changed` and both test suites are clean: **1771 app tests** (up from
1684) and **91 package tests**.

**Deviations, each with its reason:**

| Planned | Shipped | Why |
| :--- | :--- | :--- |
| `auth_url_observer.dart` | `oauth_flow.dart` | It holds the whole flow helper — the endpoint constants, the parser, the capability, `fetchAuthUrl` and `cancelOAuth` — not just an observer. |
| A separate `oauth_signin_controller.dart` | The driver plus `oauth_flow.dart` | The sign-in happens *inside* the blocking `config/create`, so a second Notifier would have competed for the same state rather than owning anything. The sign-in mechanics are free functions over a client; the state stays in one place. |
| Name editable **on the final screen** | Name settled on the one screen **before** creation, prefilled and editable | A post-hoc rename means copying the section and deleting the old one, and over RC that is `config/create` — which re-runs the backend's post-config and would **restart the sign-in**. The decision's intent (nobody is stopped at step one to invent a name) is met by prefilling. |
| Storj as an **s3 search alias** | Storj resolves to rclone's **native `storj` backend** | rclone ships a dedicated backend that speaks uplink directly; routing people to the S3 gateway would hand them the slower path for no reason. |
| FFI clients implement `AuthUrlObserver` off a stderr pipe | FFI clients unchanged | §2.4 — `config/oauthstatus` replaced the whole mechanism. |
| Desktop lets rclone open the browser; mobile opens it itself | **Always** `config_auth_no_browser`, and the app opens the link | §2.4 — the URL is reliably in hand on every platform now, so one code path serves all of them and the link is on screen whatever happens. |
| (not listed) | `ui/add_remote/fields.dart` | The input widgets are shared by the guided steps and the advanced form, so the rule about what is obscured lives in exactly one place. |
| (not listed) | `android/.../AndroidManifest.xml` `<queries>` | Under Android 11+ package visibility an app cannot see a browser it has not declared an intent for, so without `http`/`https` VIEW intents the Custom Tab never opens. |
| MAS entitlement to add | `com.apple.security.network.server` was **already there** for the preview bridge | Its comment is the App Review justification, so the comment now names the second use rather than the entitlement being added twice. |

**Found by the new tests, fixed in the same change:**

- The curated tile's row **overflowed by 73 px at phone width** — a text button plus a chevron does
  not fit beside two lines of label in ~295 dp. The action is a label where there is room and an
  icon where there is not.
- The select's "something else" escape sat **beside** the field and overflowed by 11 px; it sits
  below it now.
- A unicode-escape sentinel reached a source file as a **literal NUL byte** (AGENT.md rule 18,
  exactly). Replaced with index-based dropdown values, which cannot collide with a backend's own
  example string either way. Every touched file was then scanned for NUL and backspace bytes.

**Found by reviewing the new code before committing it:**

- **`copyWith` could not clear `createdName`.** It merges with `??`, so passing null KEPT the value
  — and a stale marker after a successful create would have had the dialog delete the remote it had
  just made. Now an explicit `clearCreatedName` flag.
- **Cleanup was keyed on being mid-sign-in**, but rclone writes the section as soon as a call
  returns at a *question* — so walking away from the shared-client_id screen left the same unusable
  remote behind. Keyed now on "is there a section this flow wrote and did not finish".
- **A half-created remote blocked its own retry.** The taken-name guard exists to stop
  `config/create` silently replacing someone else's remote; it was also refusing the stub this very
  attempt had written, dead-ending both *Try again* and *Enter details myself*.
- **A torn-down job could report over the screen the user had moved on to.** Replaced the cancelled
  flag with a generation token: every call takes a number and checks it again on the way out.
- **Errors and the success summary are redacted before they are painted.** rclone quotes what it
  failed on, which can include a URL carrying a credential — the same shape that once printed the
  live rc password onto a player error card. Redaction already ran at ingest for diagnostics; a
  screen needs it for the same reason.

## 5️⃣ Phase 5: Product Owner Review
* **Status:** `PENDING`

## 6️⃣ Phase 6: Senior Dev Hygiene Review
* **Status:** `PENDING`

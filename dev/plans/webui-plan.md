# 📦 Parcel Plan: Web UI

## 📊 State Dashboard
| Metric | Value |
| :--- | :--- |
| **Status** | `BUILT — awaiting a test build` |
| **Version** | `v1.0.0` |
| **Active Persona** | `Architect` |
| **Last Updated** | 2026-09-11 |

---

## 1️⃣ Phase 1: Expansion & Scoping

* **Intent:** Serve the *existing* Airclone interface over HTTP so a browser on any
  device drives an Airclone running on another machine — typically a headless
  server. The browser is a **remote display**, not a second implementation.

* **The load-bearing rule:** *nothing the user asks for happens in the browser.*
  A mount mounts on the host. A listing is read by the host's engine. A copy is
  performed host-side by rclone. The browser renders pixels and sends intent.
  This is what makes the Web UI Airclone rather than a new product: there is one
  set of widgets, one state layer, one `RcloneClient` seam — the transport under
  that seam is the only thing that changes.

* **In Scope:**
  - A `flutter build web` target that compiles and boots (today it does neither).
  - `WebUiServer`: static bundle + login + session auth + a fail-closed RC proxy
    + object bytes, all same-origin.
  - Credentials auto-generated on first launch, persisted to an env file, reused
    on later runs, regenerated when the file is gone.
  - Launch from the CLI (`--webui`) and from the desktop GUI (Settings).
  - Bind to `127.0.0.1` by default; opt in to another address or all addresses.
  - Access logging into the existing diagnostics channel.
  - The responsive shell already in the app decides desktop vs phone layout by
    viewport width — no new layout work.

* **Out of Scope (deliberate, stated so it is not mistaken for an oversight):**
  - **Any unauthenticated mode.** There is no `--no-auth`. Not a flag, not a
    setting. See §Security.
  - **Uploading from / downloading to the browser's own machine.** On the Web UI
    "local" means *the host's* disk, which is the whole point. Byte transfer
    between the viewer's device and the host is a separate feature with its own
    design (rclone offers `operations/uploadfile` and `--rc-serve` for it).
  - **Multi-user.** One credential pair, one operator. Sessions are per-browser,
    not per-person.
  - **TLS termination.** Bind to loopback and put a reverse proxy in front, or
    bind to a LAN address you trust. Shipping a certificate story is its own
    parcel; pretending to have one is worse than saying this.
  - **Mobile hosts.** A phone is not a headless server. The feature is desktop +
    headless only, which also keeps the web bundle out of the APK.

## 2️⃣ Phase 2: Requirements & Context

* **Relevant Docs:**
  - `wiki/core/08-core-architecture.md` → the `RcloneClient` seam is the entire
    reason this is tractable; the Web UI adds a third implementation beside the
    spawned-`rcd` and in-process-`librclone` ones.
  - `wiki/core/15-security.md` → existing security posture this must not weaken.
  - `wiki/core/19-enterprise-readiness.md` → customer-owned control plane, no
    phone-home. A self-hosted Web UI is squarely on that line.

* **Relevant Code:**
  - `app/lib/src/rclone/rclone_client.dart` → the seam. Already web-shaped:
    `rpc()` runs on `package:http`, `objectRef()` returns a URL + header pair.
  - `app/lib/src/state/engine_controller.dart` → owns engine lifecycle and
    publishes `EngineUi.client`. Needs a web branch that adopts a
    `WebRcloneClient` instead of provisioning an engine.
  - `app/lib/src/headless/headless_runner.dart` → the existing no-UI entrypoint
    and its flag-parsing idiom, which `--webui` follows.
  - `app/lib/src/state/diagnostics.dart` → the local, user-driven evidence
    channel every new failure path must log into.
  - `app/lib/main.dart` → hits `Platform.isWindows` before the first frame, which
    throws on web.

## 3️⃣ Phase 3: User Clarification
* **Answered:**
  - `[x]` Does work happen host-side or browser-side? → **Host-side, always.**
  - `[x]` Default bind? → **`127.0.0.1`**, with opt-in to a specific IP or all.
  - `[x]` Credential lifecycle? → **generate on first launch → env file → reuse;
    file missing ⇒ generate fresh.**
  - `[x]` Is there an unauthenticated escape hatch? → **No. Never.**

## 4️⃣ Phase 4: Detailed Execution Plan

### Architecture

```
Browser ── same origin ──▶ WebUiServer (host)      ──▶ RcloneClient ──▶ engine
  Flutter web build         GET  /                     (Http or Ffi)     (rcd /
  of this same app          POST /api/login                              librclone)
  WebRcloneClient           POST /api/rc      ← allowlist
                            GET  /api/object  ← session
```

Three transports now implement one interface:

| Build | `RcloneClient` | Engine lives |
| :--- | :--- | :--- |
| Desktop | `HttpRcloneClient` | spawned `rcd` child process |
| Mobile / MAS | `FfiRcloneClient` | in-process `librclone` |
| **Web** | **`WebRcloneClient`** | **on the host, reached over `/api/rc`** |

Everything above the seam — every widget, controller and provider — is unchanged.

### Stage A — make the web target compile

Two hard blockers, both measured rather than assumed:

1. **`dart:ffi` is a compile error on web** (`dart:io` is not — dart2js ships
   throwing stubs, so it compiles and only fails when touched). Six call sites in
   five files. Four are Windows `kernel32` probes, not the rclone engine.
   → Collect every `dart:ffi` call behind one conditional-import seam:
   `native/native_bindings.dart` → `_io.dart` / `_web.dart`.
   → `librclone_ffi.dart` keeps its own seam (it is large and engine-specific).

2. **`Platform.isX` throws at runtime on web.**
   → `state/host_platform.dart` exposes `HostPlatform.isWindows` etc. as
   `kIsWeb ? false : Platform.isWindows`. `kIsWeb` is a compile-time constant, so
   on desktop this const-folds to exactly today's expression — a provably
   behaviour-preserving refactor — and on web the `Platform` call is tree-shaken
   away before it can throw.

### Stage B — the server

`webui/` module, each piece small enough to test on its own:

| File | Responsibility |
| :--- | :--- |
| `webui_options.dart` | bind/port/flag parsing. Pure. |
| `webui_credentials.dart` | env file read/generate/persist, constant-time verify. |
| `webui_sessions.dart` | session issue/validate/expire + login throttling. Pure. |
| `webui_rc_policy.dart` | the fail-closed RC method allowlist. Pure. |
| `webui_assets.dart` | locate the packaged web bundle beside the executable. |
| `webui_server.dart` | `HttpServer`, routing, access log. The only `dart:io` part. |
| `webui_controller.dart` | Riverpod controller so the GUI can start/stop it. |

### Security

The decisive constraint, in rclone's own words: **"Access to the rc API is
equivalent to shell access as the user running rclone."** The Web UI therefore
never proxies the RC transparently.

- **Allowlist, not denylist.** `webui_rc_policy.dart` names the ~40 methods the
  app actually calls. Anything else is refused before it reaches the engine —
  including `core/command` (arbitrary rclone execution) and `core/quit`
  (a browser must not be able to kill the host's engine). Unknown ⇒ denied.
- **No unauthenticated mode.** Every `/api/*` route requires a valid session.
  There is no flag to turn this off, because the failure mode is handing shell
  access to whoever finds the port.
- **Sessions, not credentials, on the wire after login.** The password is sent
  once to `/api/login`; everything after that carries an opaque random token in
  an `HttpOnly; SameSite=Strict` cookie. Tokens live in memory and die with the
  process — a restart logs everyone out, which is the safe default.
- **CSRF:** `SameSite=Strict` plus a required `X-Airclone-WebUI` header on state
  changing calls. A cross-origin form cannot set a custom header without a
  preflight the server refuses.
- **Login throttling** with a per-address backoff, because the whole point of
  this feature is that the port may face a network.
- **Constant-time password comparison**, so a network attacker learns nothing
  from response timing.
- **Loud about exposure:** binding anywhere but loopback logs a warning to
  diagnostics and says so in the GUI.

On the env file holding a plaintext password: it sits in the app-support
directory **beside `rclone.conf`**, which already holds live cloud credentials
and is strictly more valuable to anyone who can read it. The marginal risk is
near zero, and the alternative — a hash the operator can never read back — makes
a headless install unusable. It is written `0600` on POSIX, and any value in the
process environment wins over the file so a serious deployment need never write
one.

### Logging

Every one of these goes through `diagnostics.dart`, which redacts at ingest:
server start/stop with the resolved bind address; **failed** logins with the peer
address (never the attempted password); session issue/expiry; **every RC method
refused by the allowlist** — that is the signal that something is wrong; engine
errors surfaced through the proxy; asset-bundle-missing. Successful RC calls are
logged only at the existing verbose level: a working file browser would otherwise
bury everything else.

### Test Verification Plan
* `cd app && flutter test`
* `cd app && flutter analyze` (must be clean — CI fails on any info-level lint)
* `cd app && dart format --set-exit-if-changed lib test`
* `cd app && flutter build web` must succeed.
* `[ ]` allowlist refuses `core/command`, `core/quit` and unknown methods
* `[ ]` credentials round-trip through the env file; a missing file regenerates
* `[ ]` env-var override wins over the file and writes nothing
* `[ ]` session validate/expire; throttle opens after the window
* `[ ]` password comparison is length-independent
* `[ ]` `--webui` flag parsing incl. `=`-joined forms and bad ports

## 5️⃣ Phase 5: Product Owner Review
* **Status:** `BUILT, VERIFIED ON WINDOWS, NOT YET RELEASED`

### What was proven by running it, not by reasoning about it

A Windows release build hosting `--webui`, driven from a browser:

* the sign-in page is what an unauthenticated visitor gets, and `/` redirects to it;
* after signing in, the real Airclone UI renders — the host's own remotes, read
  through `config/dump` over `/api/rc`;
* browsing the host's `D:` drive lists the host's files and reports the host's
  free space, which is the whole claim of this feature;
* a narrow viewport gets the phone shell, the same URL, no separate build;
* zero console errors and **zero requests to any third party**.

### Three bugs only real execution found

1. **The CSP blocked the sign-in page's own script.** `script-src 'self'` does
   not cover inline script, so the form fell back to a native POST and the CSRF
   check refused it — "sign in does nothing". Fixed with a per-response nonce,
   and pinned by a test that checks the header and the page agree.
2. **`flutter build web` phones home to Google on every page load** for CanvasKit
   and the Roboto font. That is a hard failure on the air-gapped and LAN-only
   servers this feature exists for, and contrary to the product's own posture.
   `--no-web-resources-cdn` is now load-bearing in CI, with the reason written
   next to it.
3. **The phone shell headed the host's disks "This phone".** True on a phone,
   false in a browser, and precisely backwards about where the user's files are.

### Known gaps, stated rather than discovered later

* No byte transfer between the viewer's device and the host (`operations/uploadfile`
  and `--rc-serve` are the route when it is built).
* One account. Sessions are per-browser, not per-person.
* No TLS of its own; a reverse proxy is the answer and the docs say so.
* macOS and Linux packaging is written but **unverified** — only the Windows
  path has been run end to end.

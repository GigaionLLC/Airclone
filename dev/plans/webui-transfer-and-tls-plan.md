# 📦 Parcel Plan: Web UI file transfer, over HTTPS only

## 📊 State Dashboard
| Metric | Value |
| :--- | :--- |
| **Status** | `PROPOSED` |
| **Version** | `v1.0.0` |
| **Active Persona** | `Architect` |
| **Last Updated** | 2026-09-12 |

---

## 1️⃣ Phase 1: Expansion & Scoping

* **Intent:** Move files between the browser and the device through the Web UI, and serve that UI
  over HTTPS only.

* **In Scope:**
  - Download an object from a remote to the browser (`Content-Disposition: attachment`).
  - Upload a file from the browser to the currently-browsed remote.
  - HTTPS only, with a persistent self-signed certificate generated on first start.
  - An import directory for an operator-supplied certificate, for automation.
  - Detect a changed certificate and reload it when the server is idle.

* **Out of Scope (deliberately, each for a reason):**
  - Folder / multi-select download. That is zip-streaming, a different feature with its own
    memory and cancellation story.
  - Uploading to the device's local filesystem rather than to a remote. "Upload" in a cloud file
    manager means "into the thing I am browsing"; local is a separate ask.
  - Obtaining a CA-signed certificate (ACME/Let's Encrypt). The import directory is the seam that
    makes it somebody's automation rather than our code.
  - Widening `kAllowedRcMethods`. See Phase 4 — the design exists partly to avoid it.

## 2️⃣ Phase 2: Requirements & Context

* **Relevant Code Found (audited 2026-09-12, read-only):**
  - `app/lib/src/webui/webui_server.dart:189` (`_handle`) -> routing, auth, CSRF order.
  - `app/lib/src/webui/webui_server.dart:465` (`_handleObject`) -> **download is 90% built**: a
    reverse proxy to `objectRef` that already forwards `Range` both ways and copies six headers.
    `Content-Disposition` is not among them and appears nowhere in `app/lib`.
  - `app/lib/src/webui/webui_server.dart:586` (`_readBody`) -> the ONLY body reader, accumulates
    into a `List<int>` capped at `kMaxRcBodyBytes` (1 MiB). Streaming a body to disk has **no
    precedent here**; there is no `MimeMultipartTransformer` or `package:mime` anywhere.
  - `app/lib/src/webui/webui_server.dart:271` (`_requireCsrf`) -> requires only the PRESENCE of a
    non-empty `x-airclone-webui` header. Content-type-agnostic, so a scripted multipart upload
    passes; a plain `<form>` cannot set the header and is refused. That is a useful property.
  - `app/lib/src/webui/webui_assets.dart:77` (`resolveStaticFile`) -> the traversal defence to
    REUSE rather than reinvent: URL-decode, reject NUL by code unit, canonicalize with
    `resolveSymbolicLinksSync`, then require root-equality or a root-plus-separator prefix.
  - `app/lib/src/webui/webui_rc_policy.dart` -> fail-closed allowlist. rclone's own docs: RC access
    is "equivalent to shell access as the user running rclone."
  - `app/lib/src/webui/webui_controller.dart:70` -> `exposed = running && !options.isLoopback`.
    Presentational only today; **no route, check or policy consults it.**
  - `app/lib/src/webui/webui_server.dart:99` -> `HttpServer.bind(...)`, `autoCompress = true`, no
    `idleTimeout`, no request timeout, no max connections.
  - `app/lib/src/rclone/librclone_object_server.dart` -> the in-process engine has no HTTP server;
    it materializes an object to cache via `operations/copyfile` and serves that. Upload mirrors
    this exactly.

* **The engine asymmetry that shapes everything:**

  | | Download | Upload |
  | :--- | :--- | :--- |
  | spawned `rcd` | `--rc-serve` streams. No temp file. | `operations/uploadfile` takes multipart; stream the body straight through. |
  | in-process `librclone` | must materialize to cache first (`RcloneRPC` returns JSON only) | must land on disk first, then `operations/copyfile` |

## 3️⃣ Phase 3: User Clarification

* **Answered:**
  - `[x]` Staging area, or stream? -> **Both, per engine.** Staging is forced on the FFI path and
    would be actively harmful on the rcd path (a 40 GB file would double disk use and delay the
    first byte). Put the difference behind the `RcloneClient` seam.
  - `[x]` HTTPS or HTTP? -> **HTTPS only.** User: *"Some browsers started auto forwarding to https,
    so it's kind of a must regardless now a days."* Correct — Chrome's HTTPS-First upgrades or
    interstitials plain HTTP, so an HTTP-only LAN service is already degraded.
  - `[x]` Is the self-signed trust warning acceptable? -> **Yes**, user confirmed. So the UI should
    EXPLAIN it and show the fingerprint rather than hide it: training people to click through
    browser warnings is worse than the warning itself.

  - `[x]` Chunked upload: in, but **chosen by size, not by a switch.** User asked whether it should
    be an advanced setting that can be turned off, not being sure what the negatives were. There is
    a real one, and it is specific: **chunking forces staging on the `rcd` engine.** A single
    streamed `POST` goes straight through to `operations/uploadfile` with no temp file, but chunks
    cannot — one rclone upload cannot be held open across N HTTP requests, so chunks must land on
    disk and be assembled first. That is double the disk I/O, free space equal to the file, and a
    slower common case: the same argument made against staging for downloads, applied consistently.
    Smaller costs: abandoned partial uploads need a janitor, and small files pay round-trips for
    nothing.

    It is **free on the FFI engine**, where staging is forced anyway, so the trade-off exists only
    on desktop with the binary engine.

    The fact that most changes the calculus: chunking protects the **browser -> device** hop only.
    Once bytes are on the device, rclone's own retry covers device -> cloud. So it is for phones on
    patchy wifi and WAN uploads into a home server, and close to pure overhead on a LAN.

    **Decision:** single streamed POST below a size threshold, chunked and resumable above it. The
    ADVANCED SETTING IS THE THRESHOLD, not a boolean — "upload files larger than ___ in resumable
    pieces" explains itself, where "use chunked uploads" asks the user to evaluate something they
    have no way to judge. Zero disables chunking entirely, so the off switch still exists. Default
    ~256 MB.

* **Open:**
  - `[ ]` None.

## 4️⃣ Phase 4: Detailed Execution Plan

### A. Download (smallest, ship first)
* `webui_server.dart:_handleObject` -> accept `?download=1`; when present, add
  `Content-Disposition: attachment; filename*=UTF-8''<pct-encoded basename>`. Use RFC 5987 form so
  non-ASCII names survive; never interpolate a raw filename into the header.
* **Must consult `wouldHydrateOnRead`** before serving. A download is a CONTENT read, and this repo
  has a standing rule that every new content-read path checks it (4 existing call sites). Serving an
  online-only OneDrive/iCloud placeholder would silently hydrate it — the user's bandwidth, possibly
  their money.
* `autoCompress = true` is already worked around at `:515`; keep `chunkedTransferEncoding = false`.

### B. Upload (the new part)
* Add to the `RcloneClient` seam, NOT the Web UI:
  `Future<void> putObject(String fs, String remote, Stream<List<int>> bytes, {int? length})`.
  - `HttpRcloneClient` -> stream the multipart body to `operations/uploadfile` on the engine.
  - `FfiRcloneClient` -> write to a staging file under the existing cache dir, then
    `operations/copyfile` local -> remote; **delete the staging file on success AND on failure**
    (unlike preview temp files, which are left to cache policy — an aborted upload is user data and
    potentially huge).
  - Free-space preflight before accepting bytes on the staging path.
* `webui_server.dart` -> new `POST /api/upload`, session + CSRF as usual, body streamed to the seam.
  **Do not extend `_readBody`** — it is an in-memory accumulator by design and must stay that way.
* **`operations/uploadfile` is NOT added to `kAllowedRcMethods`.** The browser calls an app
  endpoint; the app talks to the engine. The allowlist stays exactly as tight as it is.
* Reuse `resolveStaticFile`'s containment approach for the destination path rather than writing a
  second traversal check.

### C. HTTPS only
* `HttpServer.bindSecure` with a `SecurityContext`. No HTTP listener at all.
* Certificate store: `<app support>/webui/cert.pem` + `key.pem`, 0600.
* First start with no cert -> generate a self-signed one, valid ~2 years, CN/SAN covering
  `localhost`, `127.0.0.1`, `::1` and the configured bind address. **Dart cannot mint X.509
  itself**; build on `pointycastle` (already in the tree via `cryptography`) rather than adding a
  second crypto dependency to a security-sensitive path.
* Import directory: `<app support>/webui/imported/` holding `cert.pem` + `key.pem`. Present at start
  -> use instead of the generated pair.
* Reload on change: poll/watch the import dir; when the pair changes, reload **when idle** — defined
  as *no in-flight requests and no active sessions*, with a hard ceiling (e.g. 30 min) so a busy
  server still picks up a new certificate rather than never.
* Settings panel: show the fingerprint, and say plainly that the first visit shows a browser warning
  and why. This is the honesty that makes the warning safe.

### Test Verification Plan
* `cd app && flutter test`
* `[ ]` `Content-Disposition` present with `?download=1`, absent without, and correct for a
  non-ASCII filename.
* `[ ]` A download of a cloud placeholder is refused rather than hydrating it.
* `[ ]` Upload streams to disk without buffering (assert peak memory / that `_readBody` is not on
  the path).
* `[ ]` Staging file is deleted on both success and failure.
* `[ ]` `operations/uploadfile` is still NOT in `kAllowedRcMethods` (a guard test).
* `[ ]` Traversal attempts on the upload destination are refused.
* `[ ]` Generated certificate is reused across restarts, not regenerated.
* `[ ]` A changed imported certificate is picked up; an unchanged one does not trigger a reload.
* `[ ]` No plain-HTTP listener exists.

## 5️⃣ Phase 5: Product Owner Review
* **Status:** `PENDING`

## 6️⃣ Phase 6: Senior Dev Hygiene Review
* **Status:** `PENDING`

## 7️⃣ Phase 7: Implementation Checklist (Execution)
- `[ ]` A. Download: `?download=1` + `Content-Disposition` + hydration guard
- `[ ]` B1. `putObject` on the `RcloneClient` seam, both engines
- `[ ]` B2. `POST /api/upload` streaming to the seam
- `[ ]` C1. Self-signed generation + persistent store
- `[ ]` C2. Import directory
- `[ ]` C3. Idle reload watcher
- `[ ]` C4. Settings: fingerprint + honest warning copy
- `[ ]` Docs: `docs/guide/web-ui.md`

## 8️⃣ Phase 8: Verification Dashboard
* **Verification Status:** `PENDING`

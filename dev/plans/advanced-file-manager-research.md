# 📦 Parcel Plan: advanced file manager — bulk transfers, multi-user, federation

## 📊 State Dashboard
| Metric | Value |
| :--- | :--- |
| **Status** | `RESEARCH ONLY — nothing here is approved to build` |
| **Version** | `v1.0.0` |
| **Active Persona** | `Architect` |
| **Last Updated** | 2026-09-13 |

---

## 1️⃣ Phase 1: Expansion & Scoping

Three features raised together, as the shape of "people want to use Airclone as an advanced file
manager":

* **(A) Bulk and parallel uploads/downloads**, like a web hosting file manager.
* **(B) Multi-user accounts** with an admin page, and per-remote access control from the Web UI.
  Local users by default; LDAP and SSO someday.
* **(C) Airclone connecting to another Airclone** over its API or Web UI, with login.

**In scope for this document:** what exists, what each would actually cost, and what order they have
to happen in. **Out of scope:** building any of it.

## 2️⃣ Phase 2: Requirements & Context

### The two findings that change the brief

**1. Transfers are ALREADY parallel — and unbounded.** The expected blocker, a loop awaiting each
file, is not one: `transfer()` (`transfer_service.dart:27`) only enqueues and returns, so
`paste_action.dart:150-159` creates N independent jobs that all dispatch at once. The default
concurrency limit is `0`, meaning **unlimited** (`jobs_controller.dart:308`).

So (A) is not "add parallelism". It is **survive the parallelism already here**.

**2. Airclone-to-Airclone already works, with zero new code.** Airclone serves WebDAV
(`serve_controller.dart:14`), rclone has a `webdav` backend, and remote creation is generic. Instance
B can add a `webdav` remote pointing at instance A today. (C) is therefore not build-or-not, but
**is-WebDAV-good-enough**.

### What actually breaks first

`jobs_controller.dart:219-274` polls **two RC round-trips per running job, serially, every second**.
Fifty concurrent items is a hundred serial HTTP calls inside a one-second tick. Ticks pile up,
progress goes stale, and each rpc carries a 30s timeout. Every update rebuilds the whole job list
immutably into a `ListView`.

**This is the load-bearing defect for (A).** Not throughput — bookkeeping.

### The second-order problem

Airclone creates **one rclone job per file**. rclone's own `--transfers` inside a *single*
`sync/copy` already parallelises N files with one job, one group, one status poll. Fanning out
bypasses the engine's own batching and manufactures the N that then melts the poller.

Not free to change: `planPaste` (`state/name_conflict.dart:22`) resolves per-name rename decisions
that a single fs-level sync cannot express.

### Prior art that must be read first

* **[`transfer-coordinator-plan.md`](transfer-coordinator-plan.md)** — `proposed (design)`, unbuilt.
  Already specifies `TransferOutcome` with **per-item results** ("so the jobs panel can render them
  instead of one opaque row"), "one prompt per batch, never per item", and a required adversarial
  test that item 3 of 5 failing must not abort the batch. **This is already (A)'s data model.** Do
  not redesign it.
* [`hardening-audit-2026-07-15.md`](../backlog/hardening-audit-2026-07-15.md) H-07 — queued closures
  capture an obsolete client across an engine restart. Relevant to any larger queue.
* [`settings-ux-improvements.md`](../backlog/settings-ux-improvements.md) item 6 — concurrency is
  gated behind Advanced mode "despite being safe + common".

## 3️⃣ Phase 3: User Clarification

* **Open — (B):** "local users by default" contradicts a settled principle.
  [`19-enterprise-readiness.md`](../../wiki/core/19-enterprise-readiness.md) says Airclone is *"an
  OIDC relying party … never an IdP and never holds the user's primary credential."* Local accounts
  mean Airclone **does** hold primary credentials. That is a reversal, not a detail, and is better
  resolved before design than discovered during it.
* **Open — (C):** are per-user access and TLS worth a bespoke API, when WebDAV works today?
* **Open — (A):** batch-as-one-job, or keep per-file jobs and fix the poller? They produce different
  products — one progress row, or fifty.

## 4️⃣ Phase 4: Detailed Execution Plan (sketch, not committed)

### (A) Bulk transfers — three pieces, in this order

1. **Make progress O(1).** One `core/stats` rollup, or `job/list` batching, instead of two RPCs per
   job per second. Nothing else in (A) is safe until this lands.
2. **Bound the default.** `0` = unlimited is indefensible once bulk is a headline feature. Pick a
   default and un-gate the setting from Advanced mode.
3. **Batch abstraction**, using the transfer coordinator's `TransferOutcome`: one queue entry with
   per-item results, one prompt per batch, no silent mid-batch abort.

**Also broken today, same family:** bulk *delete* genuinely is a serial loop that throws out on the
first failure (`selection_actions.dart:58-62`), already logged in the beta quality review.

**Web UI specifically:** `openFile()` is **singular** (`browser_transfer_actions.dart:71`) — a user
cannot select two files to upload. Download is N browser navigations, which popup blockers stop at
about three. Multi-file download means zip-streaming, deliberately scoped out in the Web UI transfer
plan, where chunked upload is also designed but unbuilt.

### (B) Multi-user — the honest cost

The session is a bare boolean: token to last-seen (`webui_sessions.dart:47`), and `/api/whoami`
echoes the one global username without reading it. Adding a principal is mechanical. **Everything
after that is not.**

* **The allowlist is a METHOD allowlist, not a RESOURCE one.** `rcPolicyFor` never sees `params`
  (`webui_rc_policy.dart:146`), so it cannot scope to a remote. Per-user scoping is a new layer at
  three endpoints — `/api/rc`, `/api/object`, `/api/upload` — and one missed `fs` is a full bypass.
* **`config/create` is the bypass.** Any session can define a `local:` remote at `/`. Multi-user
  requires demoting config writes to admin-only — so a non-admin cannot add a remote. That is a
  product consequence, not only a security one.
* **`config/dump` returns every remote's secrets**, and is also the enumeration chokepoint
  (`remotes_provider.dart:35`). Filtering must be server-side: `remotesProvider` runs in the browser,
  where filtering is decoration.
* **Credentials are stored in plaintext** (`webui_credentials.dart:153`). One generated 138-bit
  password in a `chmod 600` file is defensible; a table of user-chosen passwords needs a real KDF.
* **Logs record peers, not people** (`webui_server.dart:416`).

**The thing to say out loud:** `webui_rc_policy.dart` states the allowlist "is not there to restrain"
the operator — it is defence in depth for a stolen session. Multi-user makes it **primary access
control between mutually distrusting humans**. Same file, different job, different standard: a gap
that is a hardening item today becomes a vulnerability.

### (C) Federation — the trade, stated plainly

| | WebDAV over `serve` (works today) | Bespoke `/api/rc` client |
| :--- | :--- | :--- |
| Code needed | **none** | client, auth, cross-origin story |
| Scope | one `fs` per serve process | every remote on the far instance |
| Transport | **plaintext — serve has no TLS** | HTTPS already |
| Credentials | one shared serve user | per-user, if (B) exists |
| Durability | serve dies with the process | persistent |
| Blast radius | one folder | **the whole host — `/api/rc` is the shell-access surface** |

`WebRcloneClient` (`web_rclone_client.dart:34`) is already most of the bespoke client: it is
hardcoded same-origin, navigates to a login page on 401 rather than re-authenticating, and its CSRF
header is browser-shaped.

**Recommendation:** try WebDAV first and find out whether it is genuinely insufficient. If the answer
is "it works, but it is plaintext", the cheaper fix is **TLS on serve**, not a new protocol.

### Sequencing

**(B) gates the other two.** Per-user remote access has to exist before federation means anything
beyond one shared password, and before shared bulk transfers have an owner.

But **(A)'s first piece — the O(1) poller — is independent, small, and worth doing regardless**,
because the current poller is already a defect at fifty items whether or not any of this is built.

## 5️⃣ Phase 5: Product Owner Review
* **Status:** `PENDING`

## 6️⃣ Phase 6: Senior Dev Hygiene Review
* **Status:** `PENDING`

## 7️⃣ Phase 7: Implementation Checklist (Execution)
- `[ ]` Nothing. This document is research; no work is authorised from it.

## 8️⃣ Phase 8: Verification Dashboard
* **Verification Status:** `N/A — research`

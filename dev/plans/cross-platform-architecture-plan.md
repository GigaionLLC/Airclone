# 📦 Plan: Cross-Platform Architecture & Modernization Roadmap

## 📊 State Dashboard
| Metric | Value |
| :--- | :--- |
| **Status** | `PARTLY BUILT` — Phase 0 and Phase 1 shipped; Phase 2 and Phase 3 are each part-done (see the roadmap) |
| **Version** | `v1.0.0` |
| **Active Persona** | `Architect` |
| **Last Updated** | 2026-09-06 |

> Architectural source of truth for the build sequence. The *what/why* of the architecture lives in
> [wiki/core/08-core-architecture.md](../../wiki/core/08-core-architecture.md); this plan is the
> *when/in-what-order*, with the riskiest unknowns spiked first.

---

## 1️⃣ Intent & Scope

* **Intent:** Ship a modern, intuitive rclone GUI on desktop (Windows/macOS/Linux) and mobile
  (Android/iOS) from one codebase, where a remote can appear as a drive (desktop) or in the system
  Files app (mobile).
* **In scope:** UI, the `RcloneClient` abstraction, both engine transports, native storage bridges,
  packaging.
* **Out of scope (v1):** team/multi-user sharing & RBAC; FUSE mount on mobile (needs root); an
  Xvfb-wrapped headless mode (architectural dead-end — a clean server binary is a later option).

## 2️⃣ Framework Decision (settled)

**Primary: Flutter (Dart).** Only option covering all five OSes from one codebase with proven prior
art for embedding the rclone library in-process on mobile + a polished Files integration. **Runner-up:
Tauri 2**, adopted only if mobile is deferred or the iOS in-process path proves blocking in Phase 0.
Full rationale + rejected options: [08-core-architecture.md §1](../../wiki/core/08-core-architecture.md).

---

## 3️⃣ Phased Build Roadmap

> **Spike the riskiest unknowns first.** All four are engine/platform-seam issues, not UI.

### Phase 0 — Spike (de-risk the keystone) · **DONE**, though not as written
S0.1's `gomobile bind` guess was wrong — gomobile's rclone binding is Android-only, and iOS wants a
`c-archive` static link instead; the whole recipe is in
[`dual-engine-plan.md`](../archive-plans/dual-engine-plan.md) Phase 5. S0.2 and S0.4 shipped. **S0.3 was never
built** — see Phase 2.

*Original text:*
Prove the load-bearing assumptions before committing to UI.
- **S0.1 (HIGHEST RISK):** `gomobile bind -target=ios` → `rclone.xcframework`; call `RcloneRPC` from
  Swift in a trivial Flutter app. (iOS in-process rclone is officially "untested"; prior art exists —
  prove it in week 1.)
- **S0.2:** The `RcloneClient` abstraction with **both** transports — `HttpRcloneClient` (spawn `rcd`,
  POST) and `FfiRcloneClient` (`dart:ffi` → `librclone`) — running the *same* `operations/list` on
  desktop and an emulator.
- **S0.3:** Android `DocumentsProvider` (Kotlin) backed by `librclone.aar`, showing one remote in the
  system Files app; verify `queryRoots` speed + `openDocument` streaming.
- **S0.4:** Engine **restart** as a first-class op + out-of-band encrypted-config detection (never
  `--ask-password=false`).
- **Exit criteria:** identical RC JSON drives both transports; a remote is browsable in Android Files;
  the iOS xcframework executes an RPC.

### Phase 1 — Desktop MVP · **DONE**, except the tray (shipped through the alpha run to v0.1.0-beta.1 and since)
There is **no system tray and no minimize-to-keep-running** — verified absent, no tray package and
no tray code ([`feature-backlog.md`](../backlog/feature-backlog.md), MUST / App shell). First-run
onboarding shipped as a zero-remotes empty state, not the guided wizard the bullet below implies.
- Spawn/supervise `rcd` (loopback + socket, transient creds); binary provisioning + SHA256 +
  min-version + `"system"`/PATH fallback.
- Dynamic add-remote wizard from `config/providers` + interactive/OAuth state machine.
- **Dual-pane browser** + drag-and-drop (copy default; move/sync via modifier/right-click) +
  multi-select.
- Stat-then-dispatch transfer engine; **single shared poller**; aggregate progress/ETA; cancel;
  `core/bwlimit` slider.
- Safety layer: dry-run previews + compare-before-sync + destructive confirms at the store layer.
- Mount Manager with VFS options + **FUSE driver auto-detect/install**.
- Tray + minimize-to-keep-running; settings; first-run onboarding.
- **Exit criteria:** browse/transfer/sync/mount on all three desktop OSes; safe destructive ops; clean
  engine lifecycle.

### Phase 2 — Mobile · **PART DONE**
Android ships from alpha.84 (bundled engine, phone-first shell) and iOS from 2026-08-28 (statically
linked `librclone`), sharing the whole Dart layer; background transfers hold the engine alive through
a `dataSync` foreground service (alpha.86), and `rclone serve` is offered on mobile like everywhere
but the Mac App Store build. **WorkManager-driven background scheduling shipped in v0.8**
(`app/android/.../DueTasksWorker.kt`, registered from `state/android_work_registration.dart`), with
the camera-roll photo backup on top of it (`state/photo_backup.dart`) — so the "background sync"
bullet below is done for Android, minus boot-resume, which WorkManager handles itself.
**The two OS Files integrations were never built** — there is no Android
`DocumentsProvider` and no iOS File Provider extension, so a remote does not appear in the system
file picker. That is the single largest gap left in this phase.

*Original text:*
- `FfiRcloneClient` in production; share the entire Dart domain/UI layer; touch-first layouts.
- **Android `DocumentsProvider`** (full CRUD, thumbnails, VFS cache, instant `queryRoots`, async file
  close off the binder thread).
- **iOS File Provider extension** (App Group shared config, ~20 MB-aware chunked-to-disk, whole-file
  up/down).
- Background sync: WorkManager (Android, foreground service + boot-resume) + BGTaskScheduler (iOS,
  best-effort).
- Mobile OAuth (system browser + deep-link callback).
- Optional in-app `rclone serve` (WebDAV/HTTP) for media range-streaming + LAN.
- **Exit criteria:** remotes appear in Android Files & iOS Files; browse/transfer/sync; reliable
  user-initiated background transfers.

### Phase 3 — Advanced · **PART DONE**
bisync, the crypt wrap wizard, the scheduler (with desktop background execution), filter UI,
bandwidth limits and public-link sharing all ship. Still open, and tracked in
[`phase3-continuation-plan.md`](phase3-continuation-plan.md): background execution on macOS and
Linux, crypt reattach/rotation, the bisync reliability surface, and the engine test harness. Real-time FS
watchers, remote-`rcd` "mobile drives desktop", and full i18n are untouched.

*Original text:*
- **bisync** "two-way sync pair" (guided one-time `--resync`, dry-run preview, conflict strategy —
  never auto-resync) with conflict-rename.
- **crypt** "wrap an existing remote" wizard with live filename-transform preview.
- Scheduler/automation: cron + real-time FS watchers (debounced) on desktop; alerts (OS toast +
  webhook).
- Multi-backend / profiles incl. **mobile-drives-desktop** remote-`rcd` mode (TLS + auth).
- Performance presets (OS × provider × base); filter-builder UI → `_filter` JSON; time-aware
  bandwidth schedules; public-link sharing.
- Clean headless/server persona; full i18n; automated e2e/unit suite for the engine lifecycle.

### Enterprise track (parallel) · *never phone home; never SSO-tax security*

Full design: [wiki/core/19-enterprise-readiness.md](../../wiki/core/19-enterprise-readiness.md). Folds
into the phases — the foundational primitives ship **early** (with Phase 1–2), centralization ships
**later** (post-design-partner).

- **Phase 0 hooks:** design the `RcloneClient` seam with clean **policy-enforcement + audit-emission**
  hook points; author `policy.schema.yaml` + codegen skeleton; adopt **GNU AGPLv3**;
  stand up signing + reproducible-build CI.
- **Early (v1-ent, with Phase 1–2):** Policy Engine (OS-native managed config → enforced in the seam);
  local hash-chained audit log; `SecretStore` (OS keychain; Vault/KMS refs); opt-in SIEM export; DLP
  policy keys; harden `rcd` (loopback, per-session creds, TLS); pinned+verified bundled rclone
  (fail-closed) + disable `selfupdate`; SBOM + sign/notarize + SLSA L3; air-gapped install + mirror.
- **Later (post-design-partner):** OIDC SSO (free) + SCIM; **self-hosted control plane**
  (`airclone-server`: admin console + fleet + RBAC + signed-bundle distribution + audit aggregation,
  enrolled only via admin-supplied `controlPlaneUrl`); headless HA (active/passive); FIPS build; SOC 2
  for the control plane; LTS.

> **Open product decisions (need sign-off):** (1) **hybrid open-core** model (free OSS client incl.
> all security; paid self-hosted control plane); (2) **defer** the management plane until a design
> partner commits. **License decided: GNU AGPLv3** (2026-06-28). See
> [19-enterprise-readiness.md §4](../../wiki/core/19-enterprise-readiness.md).

---

## 4️⃣ Risk Register

| # | Risk | Impact | Likelihood | Mitigation |
|---|---|---|---|---|
| 1 | iOS in-process rclone officially "untested" | iOS unshippable | Low | Phase-0 week-1 xcframework spike; proven prior art exists |
| 2 | Storage bridges (`DocumentsProvider`/File Provider) are native, not Dart | Mobile "appears in Files" blocked | Medium | Follow the proven SAF (Kotlin) + File Provider (Swift) blueprints; native bridge + Flutter UI share one engine config/cache |
| 3 | librclone has no crash isolation; can't hot-swap | App crash on rclone fatal; slow mobile updates | Medium | Pin known-good tag; structure/catch RPC errors; keep swappable binary on desktop; bake mobile upgrade into release eng |
| 4 | RC limits force engine restarts (cache path, global flags, VFS filters; no `core/restart`) | State desync, frozen RC | High | Make restart first-class & tested; detect encryption out-of-band; never `--ask-password=false`; `RCLONE_CONFIG_PASS` via env |
| 5 | Locked-config deadlock (`config/get` hangs) | Engine freeze at startup | Medium | Out-of-band encryption probe + password prompt before any RC call |
| 6 | `operations/uploadfile`/`core/command` missing from librclone | Mobile uploads/commands break | High if unhandled | Use `operations/copyfile`/`sync/copy` from local path on mobile; never `core/command` |
| 7 | SAF `queryRoots` slowness stalls all of system Files UI | System file UI hangs | Medium | Return cached remotes synchronously; empty cursor pre-setup; `notifyChange` on config change |
| 8 | iOS File Provider ~20 MB memory cap; no true streaming | Crashes on large media | High | Chunk-to-disk; range streaming only via a separate in-app `rcd` HTTP server |
| 9 | Mobile background-execution limits | Sync stops mid-transfer | High | WorkManager + foreground service + boot-resume + battery exemption (Android); BGTaskScheduler best-effort (iOS); design for on-demand materialization |
| 10 | Whole-file download-modify-reupload on edit | Pull file mid-upload → data loss | Medium | Async close off binder thread; surface "still uploading"; resumable uploads if killed |
| 11 | Desktop FUSE driver install friction | Mount onboarding cliff | High | Auto-detect via `mount/types`; one-click guided install |
| 12 | Flutter desktop "native file-manager polish" | Feels non-native | Medium | Custom dual-pane widget over `operations/*`; `super_drag_and_drop` for real OS payloads; Tauri 2 fallback documented |
| 13 | bisync reliability (rclone marks it beta) | Two-way sync data issues | Medium | Sync-pair object; mandatory first-run `--resync` gate; dry-run; `--max-delete`/`--check-access`; conflict-rename |
| 14 | Loopback RC port hijack (localhost CSRF/DNS-rebind) | Local apps issue rclone commands | Low–Med | Prefer unix socket/named pipe; always `--rc-user`/`--rc-pass`; never `--rc-no-auth` on TCP; mobile in-process removes this surface |
| 15 | Destructive ops with no undo | Data loss | Medium | Dry-run + compare before sync; store-layer confirm; recoverable-delete tier where supported; `--max-delete` |
| 16 | macOS notarization / iOS account cost | Distribution blocked / scary warnings | Low | Budget code-signing + notarization; transparent docs on any unsigned fallback |
| 17 | rclone version drift breaking RC surface | Runtime failures on upgrade | Low–Med | Pin tested version; probe `core/version`/`fsinfo`; enforce minimum version |
| 18 | Two transports to maintain | Divergence/bugs | Low | The single `RcloneClient` interface — identical JSON in/out; transport-specific code confined to two classes + native bridges |
| 19 | **Unauthenticated localhost RC port** (local exfil / priv-esc) | High | Medium | **P0.** Loopback/unix-socket + per-session creds + TLS ≥ 1.2; mobile in-process has no port |
| 20 | **Policy bypass** by running `rclone` directly with the same config | Medium | High | Enforce kill-switches in the seam; gate credential release on policy; pair with OS egress controls; state the guardrail boundary honestly |
| 21 | **`selfupdate`** breaks air-gap / pinning / supply-chain integrity | High | Medium | Hard-disable by policy; pin + **fail-closed** verify rclone; internal mirror spec |
| 22 | **Secrets leakage** (plaintext conf / obscure-only / iOS AppConfig) | High | Medium | Default encrypted config + keystore; external refs at spawn; never push secrets via AppConfig; biometric gate |
| 23 | **Control plane = breach/compliance surface** if built early | High | Medium | Defer until a design partner commits; self-hosted-first/opt-in; SOC 2 scoped to the plane only |
| 24 | **Accidental phone-home** (default-on update/telemetry/crash endpoints) | High | Low | All egress default-OFF; no hardcoded endpoints; CI asserts zero outbound on clean config |
| 25 | **SSO-tax / brand damage** from paywalling basic security | High | Medium | Keep SSO/MFA/encryption/on-device audit/MDM **free**; paywall only fleet scale + export + assurance |
| 26 | **Headless HA** misconfig — two servers share a state/VFS dir → corruption (rclone is single-writer) | High | Medium | Default **active/passive** (replicas=1, RWO, leader-election); partition jobs per sync-pair; durable job store |

---

## ✅ Completion Note
<!-- Added during wrap-up. Describe actual outcome and any deviations from the original plan. -->
_This is a living roadmap, not a one-shot task. Update phase status as spikes/phases complete; move to
`archive-plans/` only when superseded by a more detailed per-phase plan._

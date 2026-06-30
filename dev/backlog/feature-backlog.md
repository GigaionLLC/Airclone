---
type: "backlog"
name: "Feature Backlog & Roadmap"
status: "stable"
description: "Prioritized (MoSCoW) feature roadmap for Airclone, desktop + mobile, v1 → v2."
---

# 📋 Feature Backlog & Roadmap

Prioritized roadmap distilled from competitive + engine research. Tags: `[D]` desktop · `[M]` mobile ·
`[D+M]` both. (The full cross-product feature comparison lives in gitignored
`reference/research/synthesis-feature-matrix.md`.)

---

## 🧭 EXPLORER-NATIVE UX TRACK (ACTIVE) — desktop-first

> **Goal:** make Airclone feel like the host OS's native file manager — Windows Explorer on Windows,
> macOS Finder on macOS, the native paradigm on Linux — with a **switchable skin** (use any look on any
> OS). Default to **easy "native" mode**; expose rclone's power behind an optional **advanced mode**
> (custom flags, queue, stats). This is the live tracking list for the current wave of work. Detailed UX
> research from other rclone GUIs lives gitignored under `reference/`.

### ✅ Shipped (recent alphas)
- [x] Grid / Media-gallery / List views + tabbed **Inspector** + **Quick Look** (Space, ←/→) — a7/a8
- [x] **Local-filesystem browsing** + grouped, collapsible sidebar (**Locations / Disks / Cloud**) — a9/a11
- [x] **Single-pane explorer default** + dual-pane (commander) toggle — a9
- [x] **Auto thumbnails** for images **and** videos; local always on, per-remote disable for bandwidth — a12
- [x] **Editable Locations** — + folder picker, drag-drop a folder to add, remove from sidebar — a11
- [x] **Instant** right-click context menu (no fetch-blocking, no scale-in) — a13
- [x] **Resizable + hideable** sidebar — a13
- [x] **Explorer two-row header** — address row + **command bar** (New · Cut/Copy/Paste · Rename · Delete ·
  **Sort ▾** · **View ▾** with icon-size presets) — a14
- [x] **Advanced transfer dialog** (Copy/Move/Sync · skip rules · compare · Include/Exclude/Filter · cmd
  preview · Dry-run) + **live statistics strip** (`core/stats`) — a15
- [x] **Folder previews** (composite of first images) + **orphaned-engine reap** — a16
- [x] **Tabs per pane** (independent sessions + history; Ctrl+T/W) — a17
- [x] **Video thumbnails fixed** (libmpv headless keyframe) — a18
- [x] **Encrypted preview cache** (AES-256-GCM; PBKDF2/config-pw or remote-name key) + **Clear cache** +
  **memory-only** mode — a19
- [x] **Download-to-chosen-folder** (prompt/remember/always-ask) · **type-to-navigate** · **rich status bar**
  (count · selection size · free/total via `operations/about`) — a20
- [x] **Double-context-menu bug fixed** (onSecondaryTapUp) — a21
- [x] **Easy/Advanced mode** toggle + **Saved transfer tasks** (run/delete) — a22
- [x] **Morphing breadcrumb path bar** (breadcrumbs ⇄ editable) · **resizable Details columns** ·
  **global engine flags** (Apply & restart) — a23
- [x] **Transfer concurrency queue** (limit · Queued state · auto-dispatch) — a24
- [x] **Native window backdrop (opt-in)** — Mica/Acrylic via flutter_acrylic, persisted — a25

### 🔜 Layout & chrome
- [x] **Command toolbar** below the address/path bar (New · Cut/Copy/Paste · Rename · Delete · Sort ·
  View · Filter) — Explorer-style two-row header — a14.
- [x] **Tabs** — multiple open locations per pane, each its own path history + view mode + selection — a17.
- [x] **View presets** — Extra-large / Large / Medium / Small icons · List · Media (via View ▾) — a14.
  (Tiles / Content + Details/Preview-pane toggles still open.)
- [ ] **Native per-OS look** as default (Explorer / Finder / Linux) + a **skin selector** to switch.
- [~] **Native window chrome** — **Mica/Acrylic backdrop shipped (opt-in)** a25; tabs-in-titlebar +
  macOS traffic-light insets/vibrancy + per-surface translucency tuning still open.

### 🖼️ Previews & icons
- [x] **Folder previews** — folder thumbnail composited from the folder's first few images — a16.
- [x] **Icon/preview sizing** wired to the view presets — a14.
- [ ] PDF / document **first-page thumbnails** (extend the image+video thumbnail pipeline).

### ⚙️ Advanced power (optional "advanced mode")
- [x] **Advanced transfer dialog** — Copy/Move/Sync · skip rules · compare · Include/Exclude/Filter tabs ·
  rclone-cmd preview · Dry-run/Run — a15 (gated behind advanced mode a22).
- [x] **Transfer queue** (a24) + "**save as task**" (a22) + **scheduler** (a50 — interval/daily/weekly, in-app,
  app-open-only). OS-level background execution still open.
- [x] **Statistics** strip — live transfer stats (`core/stats`), per-job + aggregate, speeds/ETA — a15.
- [~] **Global settings** — custom rclone **engine flags** shipped a23; VFS · bandwidth · performance
  presets still open.
- [x] **Easy ⇄ Advanced mode** toggle (progressive disclosure) — a22.

### 🔒 Cache & privacy
- [x] **Clear cache** — one-click in Settings (deletes `airclone_thumbs` + `airclone_folderthumbs`); shows
  cache size — a19.
- [x] **Encrypt the on-disk cache at rest** (thumbnails now; file/VFS cache later). AES-256-GCM per blob.
  Key derivation: **PBKDF2 from the rclone config password** when the config is encrypted (so no config
  password ⇒ no remotes ⇒ no cache — coherent). **Fallback when the config is NOT password-encrypted:**
  a random key sealed in the **OS secure store** (Windows DPAPI / macOS Keychain / Linux Secret Service)
  — *stronger than a remote-name hash, which is not secret and gives only obfuscation*. Also offer a
  **memory-only / no-disk-cache** mode for the paranoid.

### 🐞 Known robustness bugs
- [x] **Orphaned engine processes** — a16 records the spawned `rcd` PID and reaps that exact child on next
  launch (targeted; never the user's other rclone). Original report: force-killing `airclone.exe` left its
  `rcd` child running (15+ stray accumulating). Remaining belt-and-suspenders: tie `rcd`'s lifetime to the
  app at the OS level (Windows Job Object / `CREATE_BREAKAWAY` off; POSIX `PR_SET_PDEATHSIG`).

### 💡 Recommended additions (proposed)
- [x] **Type-to-navigate** (typeahead) — a20; **keyboard map** F2 · Del · Enter · Ctrl+A · Esc — a26
  (Ctrl+C/X/V clipboard keys still to wire to the existing cut/copy/paste).
- [x] **Morphing breadcrumb path bar** (breadcrumbs ⇄ editable type-to-go) — a23.
- [x] **OS interop for local files** (replaces drag-out) — a30. Right-click + Details pills: **Open with
  default app** (url_launcher), **Show in File Explorer/Finder** (documented OS commands via a pure,
  unit-tested per-OS argv builder), **Copy path** (Clipboard). Download remains for cloud. Chosen because a
  verified research pass found **Flutter has NO official drag-out** (its docs redirect to the community
  `super_drag_and_drop`, which needs a Rust build and whose drag can't be agent-verified). The earlier a28
  native drag-out was **removed** (Rust toolchain dropped). Still open if ever wanted: true OS drag-out
  (community-only, unverifiable) and cloud→OS via the existing Download.
- [x] **Resizable + sortable columns** in Details view — sortable since a6, resizable a23.
- [x] **Status bar** — item count + selection size + free/used space (`operations/about`) — a20.
- [x] **Per-remote view memory** (remember view mode + sort + density per remote, restored on open) — a26.
  (Per-*tab* state is already inherent — each tab is its own session.)

---

## 🟥 MUST — v1 foundation

**Engine & architecture**
- `[D+M]` Single `RcloneClient` abstraction: `rpc(method, params) → json`, two transports (HTTP→`rcd`
  desktop, librclone FFI mobile).
- `[D]` Spawn `rclone rcd` loopback-only, random port + `--rc-user`/`--rc-pass` per session; prefer
  unix socket/named pipe.
- `[M]` Bundle `librclone.aar` (gomobile Android) + `xcframework` (iOS); pin rclone tag; build per-arch
  in CI.
- `[D]` Auto-provision rclone binary: download, SHA256-verify, enforce min-version, `"system"`/PATH
  fallback.
- `[D+M]` Engine **restart** as a first-class operation (config path, cache dir, global flags, VFS
  filters).
- `[D+M]` Async job engine: `_async` + `_group`, **single shared poller** (`core/stats`/`job/status`),
  raised `--rc-job-expire-duration`.
- `[D+M]` Detect config encryption safely **before** any RC call; never `--ask-password=false`; pass
  `RCLONE_CONFIG_PASS` via env.

**Remote / config**
- `[D+M]` Dynamic remote forms from cached `config/providers` (Type→widget, `Examples`/`Exclusive`,
  `Provider` conditionals, Advanced expander, `IsPassword`/`Sensitive`).
- `[D+M]` Interactive config state machine (`opt.nonInteractive` + continue/state/result) — covers
  OAuth and team drives.
- `[D+M]` Full remote CRUD incl. **atomic edit**.
- `[D+M]` Capability-gating from `operations/fsinfo` (publiclink / about / empty-dirs).

**Browser & transfer**
- `[D]` **Rebuilt rclone file explorer = hero surface.** Dual-pane on `operations/list` with **tabs
  per pane** (many remotes open at once); inline add/edit remote; `[M]` single-pane.
- `[D+M]` Multi-select from day 1.
- `[D]` **In-app, target-aware drag-and-drop:** OS file → folder row (upload *into* folder), row →
  folder row, pane/tab ↔ pane/tab, and drag-out to OS — with real OS in/out payloads (default copy,
  modifier move/sync). Not dependent on the OS mount.
- `[D+M]` Stat-then-dispatch copy/move/sync engine; **server-side** `copyfile`/`movefile` within a
  remote (no VFS round-trip), streamed `sync/copy` cross-remote.
- `[D+M]` **Dry-run preview mandatory** before any destructive sync/move/delete; `--max-delete` guard.
- `[D+M]` Always-visible transfer panel: live speed/ETA/per-file + aggregate; doubles as searchable
  history; cancel via `job/stop`.

**Mobile storage**
- `[M]` Android `DocumentsProvider`: `DOCUMENTS_PROVIDER` intent filter, **fast `queryRoots`**,
  VFS-cache-backed FDs, async file-close off the binder thread.
- `[M]` iOS File Provider extension (`NSFileProviderReplicatedExtension`), App Group shared config,
  bounded chunked disk streaming (~20 MB cap).
- `[M]` Foreground-service / WorkManager + boot-resume for transfers with a progress notification.

**App shell**
- `[D]` System tray + pinned quick actions.
- `[D]` Desktop mount (**secondary convenience**, for interop with other apps — not the primary file
  surface): VFS options panel, default `--vfs-cache-mode writes`, FUSE detect via `mount/types` +
  guided install.
- `[D+M]` Themes (light/dark/system) on a real design system: semantic palette, type scale,
  empty/loading/skeleton/error states.
- `[D+M]` First-run onboarding: bundled rclone + guided "add your first remote" with OAuth.
- `[D+M]` i18n-first; automated test suite for engine lifecycle + RC integration.

## 🟧 SHOULD — v1.x / early v2
- `[D+M]` Bisync as a "sync pair" object: guided one-time `--resync`, dry-run, conflict-strategy
  dropdown.
- `[D+M]` Crypt "wrap an existing remote" wizard with live filename-transform preview.
- `[D+M]` Filter builder (size/age/depth + include/exclude chips) → `_filter` JSON with live match
  preview.
- `[D+M]` Live bandwidth slider (`core/bwlimit`) + time-window / asymmetric schedule editor.
- `[D]` Serve management (WebDAV/SFTP/HTTP/FTP/DLNA) via `serve/start`; TLS+auth mandatory off-loopback.
- `[M]` Serve-WebDAV escape hatch for media players.
- `[D]` Performance presets system (OS × provider × base), editable.
- `[D+M]` Public/share links (capability-gated).
- `[D+M]` Code/markdown viewer; richer preview.
- `[M]` Media-picker visibility (Android Photo Picker/MediaStore, iOS FP domain) so remotes show in
  other apps' pickers.
- `[M]` Per-remote VFS-cache + thumbnail toggles.
- `[D+M]` **Cross-device profile sync — serverless, E2E-encrypted.** Sync `rclone.conf`/remotes
  across the user's devices by storing a client-side-encrypted blob on **one of their own rclone
  remotes** (passphrase-derived key; zero-knowledge — the cloud sees only ciphertext). Opt-in,
  per-remote selectable, versioned for conflicts. **No server required** (dogfoods the engine).
  Complements: LAN P2P (mDNS) and encrypted export/QR for new-device onboarding. A self-hosted server
  is only an optional org/fleet target, never required.

## 🟨 COULD — v2
- `[D+M]` Scheduling: **interval/daily/weekly shipped a50** (in-app scheduler, honest app-open-only + missed-slot
  catch-up). Still open: cron (5-field, prose-rendered), run history/logs, OS-level background execution.
- `[D]` Real-time FS watcher with net-change debounce.
- `[D+M]` Dynamic-path macros (`$(date)`, `$(hostname)` — resolved internally, no shell).
- `[D+M]` Multi-backend / remote-`rcd` profiles (manage a NAS/remote rclone from one UI).
- `[D]` Folder compare (color diff) before sync; 1:N multi-destination.
- `[D+M]` Reusable filter profiles; alert channels beyond toast (webhook → email/Telegram/MQTT).
- `[D]` Clean headless/server mode (real server binary) with SSE + Basic-auth + TLS.
- `[M]` Media auto-backup; `[D+M]` recoverable-delete/trash tier where the backend supports it.

## 🛠️ RC-GROUNDED BUILD QUEUE — engine capability mining (2026-06-29)

> Distilled from a deep-dive feature-mining pass (rclone core/backends/RC-API/serve-mount + competitive scan).
> Every item is confirmed reachable through the existing `RcloneClient.rpc()` seam (pure RC pass-through, so
> anything on rclone.org/rc is callable). Ordered by value ÷ effort. Mechanisms are exact so a build can start
> from here. (Generic capability framing only — research notes live gitignored under `reference/`.)

1. **Recoverable transfers — "Keep replaced files"** `[D+M]` · **S** · *shipping a52.* A toggle in the transfer
   dialog so a sync/move never silently loses data: overwritten/deleted files are preserved. Mechanism:
   `_config.Suffix` + `_config.SuffixKeepExtension` (robust across cloud + local; no path math). Optional later:
   `_config.BackupDir` to a separate versions folder for remotes.
2. **Verify / compare two locations** `[D]` · **M**. Compare src vs dst by size/hash → match / differ / missing
   buckets without copying; pairs with commander mode. Mechanism: `operations/check {srcFs,dstFs,oneWay}`;
   `download:true` fallback for hashless backends (detect via `operations/fsinfo` Hashes — warn, it streams
   bytes); `operations/hashsum` for on-demand checksums of a selection.
3. **Two-way sync (bisync)** `[D+M]` · **L** — *marquee gap.* A "sync pair" object with a guarded one-time
   **Resync (establish baseline)**, conflict handling, and the `--max-delete` safety abort surfaced. Mechanism:
   `sync/bisync` (RC-exposed) with `_config` conflict-resolve `newer|older|larger|smaller|path1|path2`,
   conflict-suffix/loser, `MaxDelete`. **Resync is destructive on misuse → one-time + guarded.**
4. **Structured filter / include-exclude builder** `[D+M]` · **M**. A chip-based rule editor reused across
   copy/move/sync/bisync/check. Mechanism: the `_filter` object (`IncludeRule/ExcludeRule/FilterRule`,
   `MinSize/MaxSize/MinAge/MaxAge`) — already partially passed today; this makes it a first-class builder.
5. **Empty trash / reclaim space** `[D+M]` · **S**. Capability-gated (`operations/fsinfo` Features.CleanUp).
   Mechanism: `operations/cleanup {fs}` (empties backend trash / aborts incomplete S3 multipart) +
   `operations/rmdirs` (remove empty dirs). Feeds off the already-shipped quota/`about` view.
6. **Advanced performance & safety controls** `[D]` · **S–M**. An "Advanced" section of per-call `_config`
   keys: `Transfers`, `Checkers`, `MaxTransfer`+`CutoffMode`, `MaxDuration`, `Order` (--order-by),
   `IgnoreExisting/UpdateOlder/Immutable/NoTraverse/FastList`. Cheap, broadly useful (overlaps SHOULD presets).
7. **Encrypt-a-remote (crypt) wizard** `[D+M]` · **M** · *security-gated.* Wrap any existing remote with
   client-side encryption. Mechanism: `config/create type=crypt` (remote=`<existing>:subdir`,
   filename/dir encryption, password via `core/obscure`); verify with cryptcheck. **Never persist the crypt
   password; require/encourage config encryption (`RCLONE_CONFIG_PASS`).**
8. **Bandwidth schedule (timetable)** `[D+M]` · **M**. Extend the shipped live `core/bwlimit` cap with a
   time-window editor. Mechanism: a clock that re-issues `core/bwlimit` at slot boundaries (live RC takes one
   rate), or a `--bwlimit` timetable string on restart. (Not S — needs a clock.)
9. **Import from URL + browser uploads** `[D+M]` · **S**. Paste a link → rclone streams it straight into the
   remote (no local round-trip). Mechanism: `operations/copyurl {fs,remote,url,autoFilename}` /
   `operations/uploadfile`. *(copyurl fetches server-side — fine for a user-driven desktop app; gate in any
   future headless mode.)*
10. **Edit / duplicate a remote** `[D+M]` · **S**. Today config is create + delete only. Mechanism:
    `config/get` + `config/update` for an Edit/Clone flow.
11. **Storage analysis (folder sizes)** `[D]` · **S–M**. "What's using space?" — sizes/object counts per
    folder, a size column or treemap. Mechanism: `operations/size {fs}` (+ local `core/du`/`core/disks`).
12. **Find & resolve duplicates** `[D]` · **M** · *core/command*. Duplicate scan + per-group resolution.
    Mechanism: `dedupe` via `core/command` (no `operations/dedupe`); `--by-hash` for hashed backends.
    Capability-gate (no-op where duplicate names aren't allowed).
13. **Storage-tier / archive class** `[D]` · **M**. Move objects to/from cold tiers for cost control.
    Mechanism: `operations/settier`/`settierfile`; gate on fsinfo Features.SetTier; tier list is
    **backend-specific** (enumerate per backend — no universal list).
14. **Serve a remote on the LAN** `[D]` · **M–L** · *security-sensitive.* Turn a remote into a local server
    (DLNA cast / WebDAV / SFTP …). Mechanism: `serve/start|list|stop`, `serve/types`. **Binds a network
    listener → default loopback, require auth off-loopback, never auto-start, clear "reachable on your
    network" warning, honor enterprise kill-switches.**
15. **Mounts manager (over RC)** `[D]` · **M+** · WinFsp dep. Mount any remote as a drive/folder with a VFS
    cache-mode preset (off/minimal/writes/full). Mechanism: `mount/mount|listmounts|unmount|types`, shared
    `vfsOpt` with Serve. **Never share a VFS cache dir between engines (corruption).**
16. **Transfer history / recent activity** `[D+M]` · **S**. A "recently completed / failed items" view.
    Mechanism: `core/transferred` (last-100 with per-file errors) + `core/stats-reset`/`job/stopgroup`.

**Cross-cutting:** keep every long action `_async` (drops into the existing Jobs panel); use `core/obscure`
for any password we hand to `config/create`. **Security invariants to preserve:** loopback-only `rcd` +
per-session `--rc-user`/`--rc-pass`; `RCLONE_CONFIG_PASS` env-only (never logged/persisted); `core/command`
and `options/set` must use a GUI-built allow-list (never free-form user input) — that's the surface of the
published rclone RC CVEs; pin rclone ≥ 1.73.5.

## ⬜ WON'T (v1)
- `[M]` FUSE mount on mobile (needs root — steer to SAF/File Provider; document the rooted path only).
- `[D+M]` Team/multi-user sharing, RBAC, cloud account sync.
- `[D]` Xvfb-wrapped headless (architectural dead-end — defer to a clean server binary).
- `[M]` `operations/uploadfile` / `core/command` on mobile (unsupported in librclone — use
  `copyfile`/`sync/copy`).
- `[D]` Bundling rclone's own web-GUI — Airclone ships its own UI.

---

## 🏢 ENTERPRISE TRACK (parallel to the phases)

Full design in [wiki/core/19-enterprise-readiness.md](../../wiki/core/19-enterprise-readiness.md).
Principle: **never phone home; never SSO-tax security.** Tags: `v1-ent` = first enterprise-ready
release · `later` = post-design-partner.

**Early (build alongside Phase 1–2)**
- `v1-ent` `[D+M]` **Policy Engine**: one `policy.schema.yaml` → codegen for ADMX/Intune, macOS
  `.mobileconfig`, Linux `/etc/airclone/policy.json`, Android `app_restrictions.xml`, iOS AppConfig;
  `PolicyService` with `isForced`; **kill-switches enforced in the `RcloneClient` seam** (disable
  public links/serve/mount/config-edit/add-remotes/update-check; backend allow/deny).
- `v1-ent` `[D+M]` **Audit event bus** → local append-only, **hash-chained** JSON log (default sink).
- `v1-ent` `[D+M]` **Secrets provider interface** (`SecretStore`): OS keychain first; Vault/KMS via
  external refs + `--password-command`; never plaintext in `rclone.conf`.
- `v1-ent` `[D+M]` **Opt-in SIEM export** (syslog RFC 5424 / CEF / LEEF / OTLP) + drop-in OTel
  Collector config; default empty (zero egress).
- `v1-ent` `[D+M]` **DLP policy keys**: `allowed_remote_pairs`, `block_public_links`,
  `require_encrypted_destination`, `read_only_remotes`, `data_residency`.
- `v1-ent` `[D]` **Harden `rcd`**: loopback/unix-socket, per-session creds, TLS ≥ 1.2, never
  `--rc-no-auth` on TCP.
- `v1-ent` `[all]` **Supply chain**: sign+notarize+staple incl. bundled rclone; pinned+verified rclone
  (**fail-closed**); disable `selfupdate` by policy; CycloneDX SBOM + scanning; SLSA L3 attestations;
  OpenVEX; `security.txt` + CVD/CVE process.
- `v1-ent` `[all]` **Air-gapped**: offline install; `AIRCLONE_RCLONE_PATH` + internal mirror spec;
  self-hosted/static update manifest.

**Later (post-design-partner)**
- `later` `[D+M]` **SSO**: OIDC Auth-Code + PKCE (desktop loopback / mobile AppAuth); Device Grant for
  headless; relying party to Entra/Okta/Ping/Google/Keycloak. **Free, never paywalled.**
- `later` `[server]` **Self-hosted control plane** (`airclone-server`): admin console + fleet + RBAC +
  SCIM 2.0 + signed-policy-bundle distribution + audit aggregation; clients enroll only via
  admin-supplied `controlPlaneUrl`. **Paid (self-host).**
- `later` `[server]` **Headless/HA**: single binary supervising `rcd` + served web UI; Helm + systemd;
  durable job store; **active/passive only** (rclone is single-writer per state dir); declarative
  GitOps apply; `/metrics` + `/healthz` + Grafana/alerts.
- `later` `[D]` **FIPS build** (force TLS ≥ 1.2; label `crypt` non-FIPS); SOC 2 for the control plane;
  LTS line; commercial MSA/indemnification.

> **Open decisions (need sign-off):** (1) commercial model — recommended **hybrid open-core**
> (free OSS client incl. all security; paid self-hosted control plane); (2) **defer** the management
> plane until a design partner commits. **License decided: GNU AGPLv3** (2026-06-28). See
> [19-enterprise-readiness.md §4](../../wiki/core/19-enterprise-readiness.md).

## ⌨️ REM wishlist parity (user-requested)

From the user's own REM feature requests:
- ✅ **Multi-select** files/folders for bulk copy/move/delete (REM #20) — *done in Airclone*.
- ✅ **Folders shown first** in listings (REM #10) — *done in Airclone*.
- ✅ **Keyboard shortcuts + navigation** (REM #9): back/forward **history** (Alt+← / Alt+→), up (Alt+↑),
  **filter box** via **Ctrl+F** — *done a5*; plus tabs (Ctrl+T/W a17) + type-to-navigate (a20).

## 🏆 Differentiators — Airclone's edge

1. **True cross-platform incl. mobile, one codebase** (Flutter) — desktop + Android/iOS with a shared
   `RcloneClient`.
2. **Best-in-class mobile "appears in system Files"** — SAF-grade `DocumentsProvider` + iOS File
   Provider, plus media-picker visibility so remotes show in other apps' pickers.
3. **In-process librclone, hybrid by design** — no subprocess on mobile (the only iOS-legal path), no
   RC port to secure; desktop keeps the swappable binary for crash isolation + independent upgrades.
4. **Modern UX with progressive disclosure** — a real design system; sane presets up front, advanced
   rclone flags one disclosure away.
5. **Safety-first transfers** — mandatory dry-run, `--max-delete` guard, color compare-before-sync,
   recoverable-delete tier.
6. **Open-source + privacy headline** — local-only, no telemetry.
7. **Engineering rigor** — automated tests for the engine lifecycle + RC integration, restart as a
   first-class tested op, robust structured OAuth, i18n from day one.
8. **Free where it matters** — all manual power (dual-pane, drag-drop, mount, compare, dry-run) free;
   the premium story is mobile + cleaner UX, not gating basics.

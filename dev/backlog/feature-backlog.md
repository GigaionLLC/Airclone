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

### 🔜 Layout & chrome
- [ ] **Command toolbar** below the address/path bar (New · Cut/Copy/Paste · Rename · Delete · Sort ·
  View · Filter · overflow ⋯) — Explorer-style two-row header.
- [ ] **Tabs** — multiple open locations per window (Explorer-style), each tab its own path history +
  view mode + selection. (Structural: per-tab browser state.)
- [ ] **View presets** — Extra-large / Large / Medium / Small icons · List · Details · Tiles · Content;
  plus **Details pane** / **Preview pane** toggles.
- [ ] **Native per-OS look** as default (Explorer / Finder / Linux) + a **skin selector** to switch.
- [ ] **Native window chrome** — tabs-in-titlebar + Mica (Windows); traffic-light insets + vibrancy (macOS).

### 🖼️ Previews & icons
- [ ] **Folder previews** — folder thumbnail composited from the folder's first few images.
- [ ] **Icon/preview sizing** wired to the view presets (slider + presets).
- [ ] PDF / document **first-page thumbnails** (extend the image+video thumbnail pipeline).

### ⚙️ Advanced power (optional "advanced mode")
- [ ] **Advanced transfer dialog** — Copy/Move/Sync · skip-existing / skip-newer · compare
  (size / mod-time / checksum) · **Extra Options · Include · Exclude · Filter** tabs · raw **rclone-cmd
  preview** · **Dry-run** / Run.
- [ ] **Transfer queue** + "**save as task**" + **scheduler**.
- [ ] **Statistics** panel — live + historical transfer stats (`core/stats`), per-job + aggregate, speeds/ETA.
- [ ] **Global settings window** — custom rclone flags · VFS · bandwidth · performance presets.
- [ ] **Easy ⇄ Advanced mode** toggle (progressive disclosure of the above).

### 🐞 Known robustness bugs
- [ ] **Orphaned engine processes** — force-killing `airclone.exe` leaves its spawned `rclone rcd`
  child running (observed 15+ stray `rcd` accumulating). On desktop, tie `rcd`'s lifetime to the app
  (Windows Job Object / `CREATE_BREAKAWAY` off; POSIX prctl/`PR_SET_PDEATHSIG`) and reap any orphaned
  `rcd` on startup before spawning a new one.

### 💡 Recommended additions (proposed)
- [ ] **Type-to-navigate** (typeahead) + full keyboard map (F2 rename · Del · Ctrl+C/X/V/A · Enter).
- [ ] **Morphing breadcrumb path bar** (collapsed → breadcrumbs → editable type-to-go).
- [ ] **Drag-out to OS** — drag a remote file to Explorer/Finder to download it there.
- [ ] **Resizable + sortable columns** in Details view.
- [ ] **Status bar** — item count + selection size + free/used space (`operations/about`).
- [ ] **Per-tab / per-remote view memory** (remember view mode + sort per location).

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
- `[D+M]` Scheduling: named jobs, cron (5-field, prose-rendered) + intervals, run history/logs.
- `[D]` Real-time FS watcher with net-change debounce.
- `[D+M]` Dynamic-path macros (`$(date)`, `$(hostname)` — resolved internally, no shell).
- `[D+M]` Multi-backend / remote-`rcd` profiles (manage a NAS/remote rclone from one UI).
- `[D]` Folder compare (color diff) before sync; 1:N multi-destination.
- `[D+M]` Reusable filter profiles; alert channels beyond toast (webhook → email/Telegram/MQTT).
- `[D]` Clean headless/server mode (real server binary) with SSE + Basic-auth + TLS.
- `[M]` Media auto-backup; `[D+M]` recoverable-delete/trash tier where the backend supports it.

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
- `[D]` **Keyboard shortcuts + navigation** (REM #9): back/forward **history** (Alt+← / Alt+→), up
  (Alt+↑), and a **filter box** focused by **Ctrl+F**; plus arrow-key row navigation.

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

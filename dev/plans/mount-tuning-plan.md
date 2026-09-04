# 📦 Parcel Plan: Mount tuning — good defaults, and one place to change them

## 📊 State Dashboard
| Metric | Value |
| :--- | :--- |
| **Status** | `PROPOSED` |
| **Version** | `v1.0.0` |
| **Active Persona** | `Architect` |
| **Last Updated** | 2026-09-04 |

---

## 1️⃣ Phase 1: Expansion & Scoping

* **Intent:** A mounted drive stalls Explorer — other folders won't list and
  thumbnails won't render — whenever the mount is uploading. Airclone sends
  rclone exactly ONE mount option (`CacheMode`) and takes stock defaults for
  everything else, and several of those defaults are wrong for a Windows
  Explorer workload. Ship defaults that suit that workload, and let a user see
  and change them — per mount, and as the default for new ones.

* **In Scope:**
  - A `MountOptions` value object covering the VFS/mount knobs that matter, with
    the single mapping to rclone's `vfsOpt` / `mountOpt` wire format.
  - Better shipped defaults (below), replacing "`writes` and rclone's stock".
  - One reusable editor widget, used in TWO places: the mount dialog (this
    mount) and Settings (defaults for new mounts).
  - Persistence of the defaults; per-mount edits are transient by design.
  - Verifying the options actually took effect on a live engine.

* **Out of Scope:**
  - Changing how mounts are created (still `mount/mount` on the shared `rcd`).
  - Persisting/restoring mounts across restarts — deliberately still never.
  - Per-remote profiles ("always mount Drive like this"). Possible follow-up;
    two levels (global default + per-mount override) is enough to fix this.
  - Any change to the app's own transfer engine. `--transfers` is NOT the lever
    here (see Phase 2) and is not touched.

## 2️⃣ Phase 2: Requirements & Context

* **Relevant Docs Found:**
  - `wiki/core/14-performance-standards.md` -> §6 spawned-process rules; this
    adds no new process, but the "verify by artifact" rule drives Phase 4's
    read-back step.
  - `wiki/core/06-design-system.md` / `DESIGN.md` -> tokens only, no ad-hoc
    styling; the disclosure must reuse the existing idiom, not invent one.
  - `dev/releases/v0.7.1.md` -> the mount FREEZE (unread engine log pipe) is a
    different, already-fixed bug. This plan is about contention, not deadlock.

* **Relevant Code Found:**
  - `app/lib/src/state/mount_controller.dart:66-70` -> the whole surface today:
    `rpc('mount/mount', {fs, mountPoint, vfsOpt: {CacheMode: …}})`. Gains a
    `MountOptions` parameter.
  - `app/lib/src/rclone/models/mount_info.dart:5-6` -> `mountCacheModes` +
    `cacheModeValue`. Natural home for `MountOptions`.
  - `app/lib/src/ui/mount_panel.dart:22-28,195-212` -> `_cacheMode` field and
    the front-door "Cache mode" dropdown, which moves into the disclosure.
  - `app/lib/src/ui/add_remote_dialog.dart:685-728` -> `_AdvancedSection`, the
    disclosure idiom this app already has. **Promote to a shared widget** rather
    than writing a second one.
  - `app/lib/src/state/settings_controller.dart:70-100` -> the persistence idiom
    (Notifier + SharedPreferences + `ensureLoaded`) the defaults follow.
  - `app/lib/src/state/mount_policy.dart` -> `mountEnabledProvider`; the new
    Settings section must hide behind it (a MAS build has no mounting at all).

* **Why `--transfers` is not the fix.** The instinct that prompted this was
  "parallel transfers". Raising it would make contention WORSE: the VFS
  writeback queue already runs `--transfers` (4) uploads concurrently, and each
  gets up to `--buffer-size` (16Mi). The stall is on the READ side. Verified
  against the bundled rclone v1.75.0:

  | Default | Effect on this workload |
  | :--- | :--- |
  | `--vfs-cache-mode writes` (ours) | rclone: *"files opened for read only are still read directly from the remote"* — every thumbnail is an uncached network read, **every time**. |
  | `--vfs-read-chunk-size 128Mi`, limit `off` | Reading a thumbnail's first few KB starts a 128 MiB chunk request, doubling without limit. |
  | `--attr-timeout 1s` | Explorer re-stats constantly against an already-busy VFS. |
  | fixed disk (Windows default) | Search Indexer and the shell thumbnail cache treat it as local storage and crawl it. |

* **Shipped defaults this plan adopts** (each a `MountOptions` field):

  | Option | Wire key | New default | rclone default | Why |
  | :--- | :--- | :--- | :--- | :--- |
  | Cache mode | `vfsOpt.CacheMode` | `full` (3) | `off` | Reads get cached; the second visit to a folder is local. |
  | Cache max size | `vfsOpt.CacheMaxSize` | `10Gi` | `off` | `full` without a cap can fill a disk. **Per mount.** |
  | Cache max age | `vfsOpt.CacheMaxAge` | `24h` | `1h` | A thumbnail cache that evicts hourly defeats the point. |
  | Read chunk | `vfsOpt.ChunkSize` | `32Mi` | `128Mi` | Cheap small reads. |
  | Chunk limit | `vfsOpt.ChunkSizeLimit` | `1Gi` | `off` | Still full speed on big sequential reads; bounded. |
  | Fast fingerprint | `vfsOpt.FastFingerprint` | `true` | `false` | Fewer metadata round-trips on change detection. |
  | Dir cache | `vfsOpt.DirCacheTime` | `5m` | `5m` | Unchanged; exposed because it is the first thing to raise on a slow remote. |
  | Attr timeout | `mountOpt.AttrTimeout` | `5s` | `1s` | Fewer redundant stats from Explorer. |
  | Network drive | `mountOpt.NetworkMode` | `false` | `false` | User decision: default stays a normal Windows mount, exposed as an option. |

## 3️⃣ Phase 3: User Clarification
* **Open Questions:**
  - `[x]` Default cache mode? -> **Answer:** `full`, with the size/age caps, and
    the settings changeable both in Settings and at mount time via an
    unhide/dropdown affordance.
  - `[x]` Windows `--network-mode` on by default? -> **Answer:** no — keep the
    default Windows mount, but expose it as an option the user can set when
    mounting.
  - `[ ]` Should a per-remote profile ("always mount `drive:` like this") follow?
    -> **Answer:** deferred, out of scope above.

## 4️⃣ Phase 4: Detailed Execution Plan

* **Architecture & Files to Touch:**
  - `app/lib/src/rclone/models/mount_options.dart` (new) -> immutable
    `MountOptions` + `copyWith` + `toVfsOpt()` / `toMountOpt()` + `defaults` +
    `changedFrom(other)`. **Pure** — no Flutter, no Riverpod — so the wire
    format is unit-testable in isolation, which is the point (see risk below).
  - `app/lib/src/state/mount_defaults.dart` (new) -> `mountDefaultsProvider`, a
    `Notifier<MountOptions>` persisted to SharedPreferences under one JSON key,
    following the `SettingsController` idiom.
  - `app/lib/src/state/mount_controller.dart` -> `mount()` takes
    `MountOptions options` instead of `String cacheMode`; sends
    `{'vfsOpt': options.toVfsOpt(), 'mountOpt': options.toMountOpt()}`.
  - `app/lib/src/ui/mount_options_editor.dart` (new) -> the ONE editor widget:
    `MountOptionsEditor(value, onChanged)`. Used by both surfaces so they cannot
    drift.
  - `app/lib/src/ui/disclosure.dart` (new) -> `Disclosure`, promoted verbatim
    from `add_remote_dialog.dart`'s `_AdvancedSection`, with an optional
    `summary` line. `add_remote_dialog.dart` switches to it (deleting its
    private copy — see Phase 6 DRY).
  - `app/lib/src/ui/mount_panel.dart` -> `_cacheMode` becomes
    `MountOptions _options`, seeded from `mountDefaultsProvider`; the front-door
    "Cache mode" dropdown is replaced by the disclosure.
  - `app/lib/src/ui/settings_screen.dart` -> a `MOUNTS` section, gated on
    `mountEnabledProvider`, hosting the same editor over the defaults.

* **The intuitive shape (this is the part worth getting right).**
  The mount form stays a two-field, one-button job — Remote, Subfolder, Drive,
  **Mount**. Under it sits a single collapsed line that is BOTH the summary and
  the toggle:

  ```
  ▸ Cache: full · 10 GiB · 24h · network drive off        Reset to defaults
  ```

  Two properties make this better than a bare "Advanced" header. The current
  state is readable without opening it, so a user who only wants to check what
  they are about to get never expands anything. And when a value differs from
  the saved defaults, the line says so — `▸ Cache: full · 20 GiB · … (2 changed)`
  — with the reset link only shown then. That is what stops the classic
  two-places-to-set-a-thing confusion: the dialog always tells you whether you
  are looking at your defaults or a deviation from them.

  Settings hosts the identical editor, always expanded, under the heading
  **"Defaults for new mounts"** with the subtitle *"Changing these does not
  affect a mount that is already running."* — because it does not, and a user
  should not have to discover that.

* **Code Snippets & Instructions:**
  - Wire format. rclone reshapes `vfsOpt`/`mountOpt` by marshalling JSON into
    its Go options struct, so keys are the **Go field names** and durations /
    sizes go as **strings**:
    ```dart
    Map<String, Object?> toVfsOpt() => {
      'CacheMode': cacheModeValue(cacheMode),   // int, as today
      'CacheMaxSize': cacheMaxSize,             // '10Gi'
      'CacheMaxAge': cacheMaxAge,               // '24h'
      'ChunkSize': chunkSize,                   // '32Mi'
      'ChunkSizeLimit': chunkSizeLimit,         // '1Gi'
      'DirCacheTime': dirCacheTime,             // '5m'
      'FastFingerprint': fastFingerprint,       // bool
    };
    Map<String, Object?> toMountOpt() => {
      'AttrTimeout': attrTimeout,               // '5s'
      if (Platform.isWindows) 'NetworkMode': networkMode,
    };
    ```
  - **`Platform` in a pure model is not acceptable** — pass a `bool windows`
    into `toMountOpt()` from the caller instead, keeping the file dart:io-free
    and testable on any host.
  - Sending an option rclone does not recognise is **silently ignored**
    (encoding/json drops unknown fields). "No error" therefore proves nothing;
    see the read-back step below.

* **Test Verification Plan:**
  - `flutter analyze` · `dart format --set-exit-if-changed lib test` · `flutter test`
  - `[ ]` `mount_options_test.dart` — `toVfsOpt()`/`toMountOpt()` emit exactly
    the expected keys and string forms; `CacheMode` stays an int; `NetworkMode`
    is absent off Windows; `changedFrom` counts only real differences.
  - `[ ]` Defaults round-trip through SharedPreferences; an absent key yields
    the shipped defaults; a corrupt value falls back rather than throwing.
  - `[ ]` Widget: editing in the mount dialog does NOT mutate the saved
    defaults; the summary line reports the changed count; "Reset to defaults"
    restores.
  - `[ ]` Widget: the Settings section is absent when `mountEnabledProvider` is
    false.
  - `[ ]` **Live read-back (the one that matters).** Against a real `rcd`:
    mount, then ask the engine what the VFS actually holds and assert the values
    arrived. `vfs/stats` is the candidate RC method — **confirm it reports the
    options before relying on it**; if it does not, fall back to asserting
    observable behaviour (a cache directory appears and grows under
    `full`, which `writes` would never produce for a read-only open).
  - `[ ]` Before/after on one real mount: browse a folder of images twice with
    an upload running. Second visit should be local under `full`. Capture the
    numbers into the release notes rather than claiming an improvement.

## 5️⃣ Phase 5: Product Owner Review
* **Status:** `PENDING`
* **Findings:**
  - [✅] **Vision & Scope** — the OS mount is explicitly the *secondary*
    convenience surface (`wiki/features/feat-file-browser.md`); this makes it
    behave, without pulling effort from the in-app explorer.
  - [⚠️] **Business Logic & Edge Cases** — `full` writes to disk where `writes`
    largely did not. The caps bound it, but the caps are **per mount**: three
    mounts is 30 GiB. The editor must say "per mount" next to the size.
  - [⚠️] **Dependency & Functional Risk** — unknown option keys are silently
    dropped by rclone, so a typo ships as a no-op that looks like success. This
    is exactly the failure mode Core Rule 9 exists for; the live read-back is
    not optional.
  - [✅] **Completeness & User Intent** — both asks are covered: better defaults,
    and changeable in Settings *and* at mount time behind a disclosure.

## 6️⃣ Phase 6: Senior Dev Hygiene Review
* **Status:** `PENDING`
* **Findings:**
  - [⚠️] **DRY Scan** — `_AdvancedSection` already exists privately in
    `add_remote_dialog.dart`. Promote it to `ui/disclosure.dart` and delete the
    private copy; do not write a second disclosure.
  - [✅] **Abstraction & Architecture** — one pure model owns the wire format;
    one widget owns the editing; the two surfaces differ only in what they bind
    to. No mount-option knowledge leaks into `mount_panel.dart`.
  - [✅] **State Management & Data Flow** — defaults are a persisted Notifier;
    the dialog holds a transient copy. One direction, no write-back from the
    dialog to the defaults.
  - [✅] **Technical Debt & Deletion** — `mount(cacheMode: String)` and the
    `_cacheMode` field are REPLACED, not left beside the new path.
  - [✅] **Secret Management** — no secrets; mount options are not sensitive.
  - [✅] **Error Handling** — a rejected `mount/mount` already surfaces inline in
    the dialog; new options widen what can be rejected, so keep that path and
    do not swallow.

## 7️⃣ Phase 7: Implementation Checklist (Execution)
- `[ ]` `models/mount_options.dart` + unit tests (wire format first — everything
  else depends on it being right).
- `[ ]` `state/mount_defaults.dart` + persistence tests.
- `[ ]` `mount_controller.mount()` takes `MountOptions`.
- `[ ]` `ui/disclosure.dart`; migrate `add_remote_dialog.dart` onto it.
- `[ ]` `ui/mount_options_editor.dart`.
- `[ ]` Mount dialog: summary line + disclosure + reset.
- `[ ]` Settings: MOUNTS section behind `mountEnabledProvider`.
- `[ ]` Live read-back against a real `rcd`; record what was actually observed.
- `[ ]` Docs: `wiki/core/14-performance-standards.md` (why the mount read path
  is tuned), `dev/logs/agent-changelog.md`, release notes.

## 8️⃣ Phase 8: Verification Dashboard
* **Verification Status:** `PENDING`
* **Report:**
  - `[ ]` Test suite runs clean
  - `[ ]` Options confirmed to have taken effect on a live engine (not merely sent)
  - `[ ]` Before/after measured on one real mount with an upload running

## 9️⃣ Phase 9: User Verification
* **Status:** `PENDING`
* **User Feedback:** —

## 🔟 Phase 10: Wrap Up & Archival
* **System Context Updates:** record in `wiki/core/14-performance-standards.md`
  that a mount's read path is tuned deliberately and why; and the rule that an
  unknown `vfsOpt`/`mountOpt` key is silently dropped, so mount options must be
  read back rather than assumed.

## ✅ Completion Note
<!-- Added during wrap-up. -->

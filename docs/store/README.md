# Store submissions — index

Airclone is distributed **free** via [GitHub Releases](https://github.com/GigaionLLC/Airclone/releases)
and self-build. The three app stores are an optional *convenience* channel: each store listing
carries a **small fee** that funds only code-signing certificates / developer-program memberships —
"the fee buys convenience, never features." Because of that, **store listing copy must NOT claim the
app is free or that nothing is behind a paywall** (only a required license-terms field states AGPLv3).
That rule is the one thing every platform below shares.

## Platforms at a glance

| Platform | Status | Listing copy | Assets | Per-release runbook |
| :--- | :--- | :--- | :--- | :--- |
| **Microsoft Store** | **LIVE** — manual per-release; unpackaged Win32 **EXE** app (not MSIX) | `docs/store/windows/listing-en-US.md` | `docs/store/windows/` | `dev/windows-signing-and-store.md` §2 |
| **Google Play** | **LIVE listing** — manual/internal today; CI auto-submit **wired but dormant** (secret unset) | `docs/store/play/listing-en-US.md` | `docs/store/play/store-ready/` (+ `MANIFEST.md`) | `dev/google-play-store.md` |
| **Apple App Store (MAS / iOS)** | **FUTURE** — not submitted; blocked on the librclone dual-engine FFI work | — | — | `dev/apple-appstore-and-macos.md` §2 |
| **macOS (direct download)** | **LIVE** — Developer-ID signed + notarized DMG/zip on GitHub Releases (NOT a store) | — | — | `dev/apple-appstore-and-macos.md` §1 |

**Windows code signing** (Azure Artifact Signing, subject "Gigaion, LLC") is **LIVE since v0.5.1** and
runs automatically on every tagged release — see the signing half of `dev/windows-signing-and-store.md`.
The automation state for every platform is captured in `dev/plans/store-automation-plan.md`.

## Pre-submission truth audit — run before EVERY store submission

Per `dev/backlog/hardening-audit-2026-07-15.md` **H-17**, never ship listing copy that describes
capability the tagged build doesn't actually have. On any platform, before submitting:

- [ ] Re-read that platform's `listing-en-US.md` against what the build actually does — remove or
      soften any feature that is planned/partial/desktop-only for that platform.
- [ ] Confirm the copy does **not** claim "free" / "no paywall" (store-fee policy above).
- [ ] Confirm the rclone **non-affiliation** line is present (avoids trademark/impersonation rejection).
- [ ] Confirm the **privacy-policy URL** resolves:
      `https://github.com/GigaionLLC/Airclone/blob/main/PRIVACY.md`.
- [ ] Confirm screenshots/assets match the shipped UI (no stale skins, no placeholder thumbnails — see
      each platform's asset manifest).
- [ ] Confirm the **version / versionCode** was bumped (every store rejects a non-increasing version).
- [ ] **Microsoft Store only** — the two things certification actually failed us on (report
      2026-07-29, fixed in v0.5.5; details in `dev/windows-signing-and-store.md` §2):
      the first **two lines** of the Description must still disclose the bundled Visual C++
      runtime (policy **10.2.4.1**), and the build must still bundle it — CI hard-fails if not.
      Install → run → uninstall on a **clean VM with no VC++ Redistributable** and confirm
      `C:\Program Files\Airclone` is gone afterwards (policy **10.2.7**).
- [ ] On a **failed** certification, expand **every** collapsed row in the report and download the
      **Supporting files ZIP** before starting work — the collapsed summary has no detail.

## PII / public-repo reminder

This repo is **PUBLIC**. Never commit D-U-N-S numbers, physical addresses, personal emails, or
seller/tenant/app/subscription GUIDs. Use placeholders in these docs; keep real values in private notes
only.

## See also

- CI/automation verdicts + one-time setup: `dev/plans/store-automation-plan.md`
- Release pipeline: `.github/workflows/release.yml` (tag `vX.Y.Z` builds + signs every platform)

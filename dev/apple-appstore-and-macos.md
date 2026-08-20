# Apple — macOS distribution + App Store (future)

Companion to `dev/windows-signing-and-store.md` and `dev/google-play-store.md`. Two very different
things live under "Apple":

1. **macOS direct download — LIVE.** Developer-ID signed + notarized DMG/zip on GitHub Releases.
2. **Apple App Store (Mac App Store / iOS) — FUTURE**, blocked on the in-process **librclone** engine.

## 1. macOS direct download (LIVE — not a store)

macOS ships the same way as Windows/Linux: a signed binary on the
[Releases](https://github.com/GigaionLLC/Airclone/releases) page. It is **NOT** the Mac App Store — it
passes Gatekeeper via Developer-ID signing + Apple notarization, with no sandbox and no store review.

| Thing | Value |
| :--- | :--- |
| Signing | **Developer ID Application** (org `APPLE_*` secrets; identity auto-discovered by SHA-1 — no identity secret) |
| Hardening | Hardened Runtime **ON**, App Sandbox **OFF**, `Release.entitlements` |
| Notarization | best-effort + **bounded** (`.github/scripts/notarize.sh`: `NOTARY_TIMEOUT=20m`, `NOTARY_RETRIES=2`; never a naked `--wait`) |
| Artifacts | signed **zip** (always) + **DMG** (only if notarize succeeded) |
| Secrets (org-level) | `APPLE_DEVELOPER_ID_APPLICATION_P12_BASE64`, `APPLE_ID`, `APPLE_APP_SPECIFIC_PASSWORD`, `APPLE_TEAM_ID` |

**CI behavior (`release.yml` `macos` job):**
- **Hard gate:** a tag push **fails the job** if the signing-cert secret is absent — never ships an
  unsigned "release."
- The signed zip is uploaded **before** notarization is attempted, so an Apple notary outage/timeout
  can never block a release. On notarize success the zip is re-stapled + re-uploaded (`--clobber`) and
  the DMG gets its own notarize+staple pass.
- If notarization never lands, a `::warning::` fires and the release stays **Developer-ID-signed-only**
  (re-runnable later).

There is **no per-release manual runbook** for macOS direct — it is fully automated by the tag. The
only recurring human step is confirming the notarized zip/DMG replaced the pre-notarization zip on the
release.

## 2. Apple App Store — macOS IN PROGRESS, iOS still blocked

**This section was rewritten on 2026-08-20.** It previously said "FUTURE (do not
attempt yet)" and "There is no MAS or TestFlight CI, and none should be added yet."
Both are now wrong for macOS. The account work is done and a sandboxed build runs.

### Mac App Store — in progress

The old blocker was the **subprocess** engine. That is gone: `FfiRcloneClient` runs
librclone in-process and ships on macOS today, and in-process I/O holds the host's
security-scoped grants, which is what dissolved the original objection.

Proven on real hardware, by [`mas-verify.yml`](../.github/workflows/mas-verify.yml)
on a GitHub `macos-latest` runner — nobody on this project owns a Mac:

- a sandboxed build **launches and runs**, with `engine ok · rclone v1.75.0`
- the `app-sandbox` entitlement is asserted present, so the run proves something
- **zero** sandbox denials from Airclone itself

The trick worth remembering: **the App Sandbox is enforced by the code signature
plus the entitlement, not by the App Store.** An ad-hoc signature with
`MacAppStore.entitlements` gives CI the same sandbox a customer gets, so "what
breaks under the sandbox?" is answerable without hardware. That workflow is also
the only compiler this project has for Swift.

| Piece | State |
| :--- | :--- |
| `AIRCLONE_MAS` compile-time flavour ([`build_flavor.dart`](../app/lib/src/state/build_flavor.dart)) | done |
| `MacAppStore.entitlements` (sandbox, 6 keys) | done |
| Mount / Serve / Archive / Reveal gated off | done |
| App-private config path | done |
| Security-scoped bookmarks (Swift + Dart + schema) | done |
| Build + upload lane ([`mas-release.yml`](../.github/workflows/mas-release.yml)) | written, **unproven** |
| Listing copy + screenshots | not started |

**Feature parity, stated plainly:** the MAS build is a *strictly smaller* app than
the DMG — no OS mount, no archive create/extract, no "Show in Finder". That is
the sandbox, not a shortcut, and the listing copy must say so. "Open with default
app" DOES survive: it goes through `url_launcher`/NSWorkspace rather than a spawn.

Two entitlement facts that are easy to get wrong:

- **`com.apple.security.network.server` is required, and not for Serve.**
  `librclone_object_server.dart` binds a loopback socket and is the ONLY source of
  preview, thumbnail, video, audio and PDF bytes under the in-process engine.
  Omitting it ships a build with no media at all.
- Under the sandbox `$HOME` is redirected into the container, and macOS
  pre-creates `Desktop`/`Documents`/`Downloads` there. Seeded Locations therefore
  do NOT vanish — they render and point at empty folders, which is worse. A MAS
  build seeds nothing and asks for the first folder.

### iOS — still blocked, but no longer unknown

Off-road but **proven by others**: two apps ship rclone embedded on iOS today, one
of them Flutter + librclone like us, and one publishes its whole build script.
Upstream rclone does NOT support it — iOS builds were disabled in 2021 and the
iOS-support PR was closed unmerged in June 2026.

Full detail, including the linker flags that cost people the most time, lives in
[`dev/plans/apple-appstore-plan.md`](plans/apple-appstore-plan.md) Gate C2. The
short version: `c-archive` only (`c-shared` is unsupported on iOS), a trimmed
wrapper package to avoid `cmd/mount2` on the simulator slice, and the Xcode target
must supply `-framework CoreFoundation -framework Security -lresolv` because Go
does not apply its own `//go:cgo_ldflag`s for `c-archive`.

Prerequisites still open for iOS: the librclone build, the FFI process-linkage
branch, and the local-file-access redesign (iOS has no arbitrary filesystem).

## See also

- Windows Store per-release runbook: `dev/windows-signing-and-store.md` §2.
- Google Play per-release runbook: `dev/google-play-store.md`.
- Index + pricing policy + pre-submission truth audit: `docs/store/README.md`.
- Automation verdicts + one-time setup: `dev/plans/store-automation-plan.md`.

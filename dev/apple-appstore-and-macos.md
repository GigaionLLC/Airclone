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

## 2. Apple App Store (MAS / iOS) — FUTURE (do not attempt yet)

**There is no MAS or TestFlight CI, and none should be added yet.** The Mac App Store is structurally
incompatible with today's **subprocess** engine: a sandboxed MAS app may only exec code bundled +
signed at build time; an inherit-sandboxed child cannot hold the parent's security-scoped folder
grants; and OS mount is impossible in the sandbox. rclone is the process doing all local file I/O, so
those are hard blockers, not CI problems.

**The unblock is already decided:** a **dual-engine backend** behind the existing `RcloneClient` seam —
`HttpRcloneClient` (spawn `rclone rcd`; today's default, full features incl. mount) **plus** a new
`LibRcloneClient` (in-process **librclone** over `dart:ffi`). In-process I/O holds the host's
security-scoped grants, which dissolves the MAS blocker. The MAS build would be **librclone-only**
(spawn path compile-disabled, mount hidden). **iOS** needs the same work regardless (iOS cannot spawn
subprocesses at all), so librclone is a hard prerequisite for any Apple App Store target.

See `dev/plans/dual-engine-plan.md` and the **REVISED** section of
`dev/plans/store-automation-plan.md` (which supersedes that file's stale "VERDICT: SKIP" heading) for
the full rationale and build order. The iOS/App-Store submission **lanes** (App Store Connect API key
auth, `apple-actions/upload-testflight-build`) are pre-scoped in that same plan and get wired only once
an iOS/MAS target actually builds and archives.

### Prerequisites, when MAS/iOS becomes real

- [ ] `LibRcloneClient` (dart:ffi) shipping + cgo librclone builds (the FFI spike is already proven on
      Windows).
- [ ] Security-scoped bookmark plumbing for macOS local paths.
- [ ] MAS target + `app-sandbox`/`inherit` entitlements; an iOS Runner target that `flutter build ipa`
      archives.
- [ ] App Store Connect app record + API-key secrets (`APPSTORE_ISSUER_ID`, `APPSTORE_API_KEY_ID`,
      `APPSTORE_API_PRIVATE_KEY` — see `dev/plans/store-automation-plan.md`).

## See also

- Windows Store per-release runbook: `dev/windows-signing-and-store.md` §2.
- Google Play per-release runbook: `dev/google-play-store.md`.
- Index + pricing policy + pre-submission truth audit: `docs/store/README.md`.
- Automation verdicts + one-time setup: `dev/plans/store-automation-plan.md`.

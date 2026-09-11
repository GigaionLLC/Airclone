Upstream rclone is now **__LATEST__**; this repo pinned **__CURRENT__**.

All four pin sites are updated together, because the bundled binary and the
in-process librclone must come from the same rclone version:

- `.github/workflows/release.yml` — the bundled binary and the Android jniLib
- `dev/android/build-rclone.ps1`
- `dev/desktop/build-librclone.ps1`
- `dev/desktop/build-librclone.sh`

**Two things this automation cannot do for you, before merging:**

1. **Read the changelog.** Security fixes ship in patch releases, and a release
   that touches the VFS or a backend Airclone leans on deserves a look before it
   moves users' files — <https://rclone.org/changelog/>
2. **Update the prose comment above `RCLONE_VERSION` in `release.yml`.** It
   records *why* a version was chosen and what was verified against a real
   binary. It still describes __CURRENT__ and is deliberately left alone: that
   reasoning has to be redone by a person, not rewritten by a script.

Opened automatically by `.github/workflows/rclone-bump.yml`. This is a proposal,
not a decision — nothing ships until someone merges it.

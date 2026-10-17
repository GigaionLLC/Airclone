# Google Drive / Photos: rclone's shared client_id is being retired

**Watch this thread:** [rclone forum — "Google Drive and Google Photos users - ACTION REQUIRED"](https://forum.rclone.org/t/google-drive-and-google-photos-users-action-required/54005)
(announcement by ncw, 2026-07-06; last checked 2026-10-16, 25 posts).

## What upstream said

- Google told rclone it will **start charging for API requests made with rclone's built-in default client_id**
  for Google Drive and Google Photos, "later in 2026, following 90 days of notice". rclone is hundreds of times
  over the free quota, so the cost would be very high. ncw estimates millions of dollars a year.
- rclone's plan:
  1. Warn in the next point release when a remote uses the shared id (`NOTICE: This remote uses rclone's shared
     Google Drive client_id, which is being retired…`).
  2. Post an update when the 90-day clock starts.
  3. Disable the default id before the 90 days end.
  4. Remove the default id in the next release.
- What users must do:
  1. Set their own `client_id` / `client_secret` ([guide](https://rclone.org/drive/#making-your-own-client-id)).
  2. Run `rclone config reconnect <remote>:` and answer **Y** to "refresh?". Without the reconnect, the old
     token keeps using the shared id.
  3. Service-account remotes are unaffected.

## Status timeline

| Date | Status |
| :--- | :--- |
| 2026-07-06 | Announced. No start date for the 90 days yet. |
| 2026-07-19 | Accounts in Google's **Advanced Protection Program** can't use a personal client_id. ncw passed this on to Google. |
| 2026-09-01 | Google Cloud consent screen now wants a **homepage URL and privacy policy** before "Publish app" works. Users got around it with any URL (2026-10-03: even `example.com`). The app then shows as "published, unverified", and sign-in shows a "not verified → continue" warning but works. |
| 2026-09-19 | ncw: "Google have gone silent… I think they are revising their plan". |
| 2026-10-16 | **No 90-day notice posted yet.** The shared id still works. |

## What it means for Airclone

- Airclone already asks before using the shared id. The step is
  [`own_client_id_step.dart`](../app/lib/src/ui/add_remote/own_client_id_step.dart): "set up your own sign-in" or
  "use the shared one for now". It is tested in `app/test/shared_client_id_test.dart`. Reconnect logic is in
  `app/lib/src/state/reconnect.dart`.
- **When the 90-day notice is posted** (watch the thread), do these:
  - Update the step's wording with the real cut-off date.
  - Consider making "own client_id" the only path for new Drive/Photos remotes.
  - Make sure existing remotes on the shared id get a clear prompt to switch, and that the prompt runs a
    **reconnect**, not just a config edit.
  - Put a line in the release notes and `docs/guide/` (troubleshooting).
- **When rclone removes the id** (a release after the cut-off), bumping our bundled rclone/librclone will break every
  remote still on the shared id. Ship the migration prompt **before** that bump.
- Not an option: Airclone shipping its own shared Google client_id. It hits the same quota and pricing problem, and it
  needs Google verification. Per ncw, the last verification took 3 months and $600. It also falls under the brain
  repo's cost-approval rule.

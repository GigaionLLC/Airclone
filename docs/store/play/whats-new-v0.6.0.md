# Google Play — "What's new" (en-US) — v0.6.0

Paste-ready copy for the Play Console release notes field.

Still current for the **v0.6.1** build: v0.6.1 changed only the Microsoft Store
package identity, so the Android app is byte-for-byte the same feature set and
these notes describe it accurately whichever of the two AABs is uploaded.

**Limit: 500 characters per language.** Play counts every character including
newlines and the `•` bullets. Keep a version under the limit *before* pasting —
the Console truncates silently in some browsers.

Android-only: desktop-only changes from `dev/releases/v0.6.0.md` (the close-with-
mounts warning, the resizable desktop preview, the "Update engine" fix) are
deliberately left out — the Android engine ships inside the app and is never
updated in-app.

---

## Recommended (fits the limit)

```
Better previews, and files that open anywhere.

• A video that can't play now tells you why, with Try again or Open in another app.
• Photos and videos open full screen. Swipe between them, tap to hide controls.
• Open any file in another app, or send it with the share sheet.
• Thumbnails no longer stutter the video you're watching.
• Every desktop tool is now on your phone, under ⋯ → Advanced.
• Fixed the tablet toolbar overlapping the status bar.
• Built-in rclone engine updated to v1.75.0.
```

## Shorter alternative

If you'd rather lead with the review that prompted this release:

```
You told us video previews often didn't work. Fixed — and then some.

• A failed video now says why, with Try again or Open in another app.
• Photos and videos open full screen, swipe to move between them.
• Open any file in another app, or share it.
• Thumbnails no longer stutter playback.
• All the desktop tools, now on phone (⋯ → Advanced).
• Fixed the tablet toolbar overlapping the status bar.
• rclone engine updated to v1.75.0.
```

---

## Notes

- Both versions avoid claiming video playback is *fixed on all devices*. The
  failure paths are verified on Android; the success path could not be verified
  on hardware (see `dev/releases/v0.6.0.md`). Saying "a video that can't play now
  tells you why" is true and is the actual change.
- Don't add pricing or "free" claims here — same rule as the listing.

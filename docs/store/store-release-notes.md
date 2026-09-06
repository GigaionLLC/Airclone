# Store release notes are deliberately generic

Google Play and the App Store get the same short text, release after release:

```
Bug fixes and improvements.

Full release notes: https://github.com/GigaionLLC/Airclone/releases
```

That exact text lives in `store-release-notes.txt`, and **two** pipelines read it:

- `release.yml` copies it to `distribution/whatsnew/whatsnew-en-US` on a tagged
  release, for Play. Play truncates past **500 bytes** silently, so the job
  hard-fails above that rather than shipping a fragment.
- `tool/asc_listing.py` sends it as Apple's `whatsNew` (limit 4,000). Apple
  **requires** that field on every update and it is per-*version*, not
  per-listing: it starts empty each release and nothing carries it forward.
  `asc-submit-review.yml` writes it, pinned to the version the operator
  confirmed, immediately before it audits and submits.

**The Microsoft Store is not wired to this file.** `tool/store_submit.py` creates
a submission by cloning the last published one, so listing copy — including
"What's new" — carries over untouched, and the previous release's text stays
there until a human replaces it in Partner Center. Microsoft's copy therefore
lives in [`windows/listing-en-US.md`](windows/listing-en-US.md) and is pasted by
hand each release.

## Why

Play allows 500 bytes per locale and truncates past it **silently**. The
pipeline used to build that text by taking `dev/releases/<tag>.md`, stripping
its headings, and cutting the result at 480 characters — so each release shipped
a mid-sentence fragment of notes written for a completely different reader, and
someone had to check by hand what had survived the cut.

Curated per-version store copy is worse than useless at this cadence. A patch
release that fixes one thing does not need its own marketing paragraph in three
stores, and writing one every time is how the copy goes stale or contradicts the
GitHub notes.

Anyone who actually wants to know what changed follows the link. That page is
generated from `dev/releases/<tag>.md`, which stays as detailed as it needs to
be — this decision does not shorten those, it stops them being mangled into a
store field they were never written for.

## When to break the rule

A release that changes something a user must act on — a permission that now
behaves differently, a removed feature, a migration — deserves real store copy
for that version. Edit `store-release-notes.txt` for that release, ship it, and
put it back afterwards. The generic line is the default, not a law.

Two things about that, both consequences of Apple being wired up to the same
file. Editing it now changes **two** stores at once, and the tighter limit
governs: stay under Play's 500 bytes even though Apple would take 4,000. And
Apple's copy is written at *submit* time by `asc-submit-review.yml`, so putting
the file back afterwards does not revert a version already submitted — that
version keeps whatever the file said when it went in. Microsoft, as always,
needs the paste.

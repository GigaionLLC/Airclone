# Store release notes are deliberately generic

Every store listing — Google Play, the App Store, the Microsoft Store — gets the
same short text, release after release:

```
Bug fixes and improvements.

Full release notes: https://github.com/GigaionLLC/Airclone/releases
```

That exact text lives in `store-release-notes.txt`, which `release.yml` copies
into Play's `whatsnew` directory on a tagged release.

## Why

Play allows 500 characters per locale and truncates past it **silently**. The
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

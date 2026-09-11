# 🐞 Responding to bug reports

How to write the reply that goes on a GitHub issue. Short version: **plain and
simple.** The person reading it wants to know whether their problem is fixed and
what to download. Anyone who wants the mechanism can read the code, the commit
message, or the release notes, all of which are public and none of which the
reply has to duplicate.

This exists because the temptation runs the other way. The work of diagnosing a
bug is interesting, and a reply written straight after that work tends to be
written *about the diagnosis* — provider semantics, stack frames, why the
failure was invisible. That is a fine commit message and a poor reply. It asks a
user to care about our internals to find out whether their app works.

---

## What a reply contains

Four things, in this order, and usually in under 150 words.

| | | |
| :--- | :--- | :--- |
| 1 | **It's fixed, and in which version** | The first line. Not the last. |
| 2 | **What went wrong, in their terms** | One short paragraph. Name the thing in the real world, not the code path: *"a drive that is present but empty"*, not *"a synchronous provider rethrows into its watchers"*. |
| 3 | **What they have to do** | Usually nothing beyond updating. Say so explicitly if their hardware or setup can stay exactly as it is — that is the reassurance they actually came for. |
| 4 | **The download, named exactly** | The asset filename and a link to the release. Verify the asset exists on the release before posting; a wrong filename is the one part of the message that wastes their time. |

If they attached a log, diagnostics report or stack trace, **quote the one line
that identified the cause** and thank them for it. It costs two lines, it proves
their effort was used rather than filed, and it is the single best thing we can
do to make the next reporter attach one too.

## What to leave out

- Stack frames, provider/widget names, file paths, line numbers.
- Why the bug was hard to find, or how long it took.
- Our internal process: what got refactored, which tests were added, which
  release lane it went down.
- Apology paragraphs. Fixing it promptly is the apology.

None of this is hidden by omitting it. The commit message carries the full
account, [`releases/`](releases/) carries the user-facing version, and the repo
is public. A reply that links a release is already a link to all three.

## Closing

**Close the issue with the reply**, and invite them to comment or reopen if it
persists. Do not hold an issue open waiting for a reporter to confirm — most
never come back, and the issue then sits open describing a bug that no longer
exists. Reopening is one click and costs them nothing.

---

## Worked example — issue #3, "Airclone is blank"

The reporter attached a diagnostics report. The cause was an empty card reader:
stat'ing `E:/` threw `errno 21` (`ERROR_NOT_READY`) inside the drive sweep, and
because the drive list is watched by the sidebar and both file panes, all three
became Flutter's release error box. What shipped in v0.8.3 was posted as:

> Hi @reporter, this is fixed and released as **v0.8.3**.
>
> Your diagnostics report is what pinned it exactly, so thank you for attaching it:
>
> ```
> FileSystemException: Exists failed, path = 'E:/' (OS Error: The device is not ready, errno = 21)
> ```
>
> `errno 21` means a drive that is present but empty, typically a card reader or
> optical drive with nothing in it. At startup Airclone checks each drive letter,
> and that one refused the check instead of answering "no". The drive list feeds
> the sidebar and both file panes, so all three went blank at once.
>
> Unreadable drive letters are now skipped, and there is nothing to change on
> your machine. The reader can stay empty.
>
> Grab `airclone-setup-x64.exe` from the v0.8.3 release. It will update in place.
>
> Closing this out, but please comment or reopen if it persists.

Note what is *not* in it, all of which is true and all of which belongs
elsewhere: that a synchronous Riverpod provider has no `AsyncValue` to park an
error in, that `Directory.existsSync()` is not total on Windows, that the release
error box paints `Color(0xF0C0C0C0)` with no text because its message lives
inside an `assert`, and that the fix shipped with a regression suite whose seam
had to be rebuilt to test the guard rather than bypass it.

---

## Related

- [`AGENT.md`](../AGENT.md) — the development rules the fix itself follows.
- [`releases/`](releases/) — the user-facing note for the version you are naming.
- [`logs/agent-changelog.md`](logs/agent-changelog.md) — where the internal account goes.

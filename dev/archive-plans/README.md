# 🗄️ Plan Archive

Completed and closed implementation plans are moved here from [`dev/plans/`](../plans/) during the
[Wrap-Up Protocol](../../AGENT.md), so the active plans directory reads as live work — apart from
the two plans named below, which stay there on purpose. That is why [`dev/README.md`](../README.md)
still describes `dev/plans/` as holding plans "live and shipped alike": check a plan's own status
line rather than trusting the directory it sits in.

The seven plans below moved here on 2026-09-06, in one commit with their inbound references. Before
that the directory had said "none yet" since it was created, while `dev/plans/` presented shipped
work as unstarted design. An agent asking "what is in flight?" got a wrong answer in every direction
at once: four still read `planned` or `proposed (design)`, `mount-tuning-plan.md` read `IMPLEMENTED`,
`dual-engine-plan.md` read `in progress (Phase 0 spike)`, and `config-transfer-simplify-plan.md`
carried no status line at all — while every one of the seven had shipped.

**A move is never just a `git mv`.** Source files and CI cite these plans by path, and six cite them
by *section* — `offline_qr.dart` at `config-portability-plan.md §5`, `config_io.dart` and
`config_transfer_controller.dart` at its `§3/§4`, `config_backups.dart` and its test at its `§2`,
and `librclone_object_server.dart` at `dual-engine-plan.md §"objectRef under FFI"`, a section named
rather than numbered — so renumbering or retitling a section breaks a pointer as surely as moving
the file does. Sweep every inbound reference in the same commit:

```
grep -rn "<plan-file>" app/ dev/ docs/ wiki/ .github/ tool/ *.md
```

`tool/check-docs.py` only reads `.md` files, so a citation in code or config is yours to catch by
hand — `app/pubspec.yaml` carries one, on the `ffi` dependency.

**Two plans stay in [`dev/plans/`](../plans/) whatever their status line says.**
[`apple-appstore-plan.md`](../plans/apple-appstore-plan.md) is `SHIPPED`, but eight workflows, three
Dart files, the iOS/macOS `Info.plist` pair and several docs name it, and some of those are CI
failure messages that print the path and a Gate letter at a maintainer.
[`store-automation-plan.md`](../plans/store-automation-plan.md) is `superseded`, but it holds the
from-nothing Google Cloud and Play Console walkthrough — account re-setup knowledge that has to stay
alongside the other store docs.

Fill one row per plan as it lands here.

| Plan | Shipped in | Summary |
| :--- | :--- | :--- |
| [`config-portability-plan.md`](config-portability-plan.md) | v0.2.0-beta.1 → v0.5.0 | Config path control, native encryption, encrypted import/export, offline QR. The LAN handoff half was removed in v0.4.0 and QR *import* became phone-camera-only in v0.5.0 — read §3/§4/§5 as the reasoning that produced the code, not as current design. |
| [`config-transfer-simplify-plan.md`](config-transfer-simplify-plan.md) | v0.4.0 | Cut config transfer to four actions and fixed three QR bugs. Its desktop QR-image decoder was itself deleted in v0.5.0. |
| [`command-console-plan.md`](command-console-plan.md) | v0.2.0-beta.3 (FFI path beta.5) | The rclone command console: fail-closed argv→RC translation, allowlist, secret redaction. |
| [`dual-engine-plan.md`](dual-engine-plan.md) | v0.2.0-beta.1 → 2026-08-28 | In-process `librclone` over dart:ffi behind the `RcloneClient` seam. All five phases. This is what unblocked both Apple stores, so the *reasoning* here is still load-bearing even though the work is done. |
| [`popout-image-viewer-plan.md`](popout-image-viewer-plan.md) | v0.2.0-beta.1 | Separate OS windows per image with independent zoom. Video and PDF pop-outs remain deferred. |
| [`readme-screenshots-plan.md`](readme-screenshots-plan.md) | 2026-07-09 | Shot list, README markup and the capture workflow; nine shots captured and committed. |
| [`mount-tuning-plan.md`](mount-tuning-plan.md) | v0.7.2 | Mount defaults (`MountOptions`, cache mode `full`) and one editor for every knob. One caveat outstanding: the performance claim was never measured — see its Completion Note. |

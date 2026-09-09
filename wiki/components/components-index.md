---
type: "index"
name: "Components Index"
status: "seed"
description: "Catalog of Airclone design-system component specifications."
---

# 🧩 Components Index

Catalog of reusable UI primitives and composites. Build from these — never hardcode one-off styles.
All components consume the tokens in [`wiki/core/06-design-system.md`](../core/06-design-system.md).

## 🧱 Planned Component Catalog (seed)

| Component | Doc | Purpose |
| :--- | :--- | :--- |
| Remote card | `ui-remote-card.md` | Remote entry in the sidebar/home (provider icon, name, status, quick actions). |
| File row / grid cell | `ui-file-item.md` | A file/folder in list or grid view (icon, name, size, modified, selection). |
| Toolbar | `ui-toolbar.md` | Path/breadcrumb, view toggle, sort, search, primary actions. |
| Transfer row | `ui-transfer-row.md` | A single transfer/job (progress, rate, ETA, controls). |
| Job panel | `ui-job-panel.md` | The transfer/job manager surface (desktop dock / mobile sheet). |
| Status bar | `ui-statusbar.md` | Aggregate stats, bandwidth, mount/serve indicators. |
| Sync dialog | `ui-sync-dialog.md` | Source/target pickers, direction, filters, schedule. |
| Mount manager | `ui-mount-manager.md` | Mount/unmount controls and mount status (desktop). |
| Provider form | `ui-provider-form.md` | Dynamic remote-config form generated from `/config/providers`. |
| Bottom nav | `ui-bottom-nav.md` | Mobile primary navigation. |

## ✅ In the tree already (ahead of their catalogue entry)

Several composites shipped before this catalogue was written. Reuse them rather than building a
second one — especially the dialogs, where the *wording* is as load-bearing as the layout.

| In the app | Source | What it is for |
| :--- | :--- | :--- |
| Dialog body | [`dialog_body.dart`](../../app/lib/src/ui/dialog_body.dart) | **Every** dialog's width. A `SizedBox(width: 520)` is a hard constraint that clips the primary button off a phone screen; this shrinks to fit, sized from `MediaQuery` (never a `LayoutBuilder` — `AlertDialog` asks for an intrinsic width, which a `LayoutBuilder` cannot answer). |
| Collision prompt | [`copy_conflict_dialog.dart`](../../app/lib/src/ui/copy_conflict_dialog.dart) | *"N of M already exist here"*, the colliding names listed, and four answers: Cancel · Skip these · **Replace** (error-coloured) · **Keep both** (the default action). |
| Change-set preview | [`sync_preview_dialog.dart`](../../app/lib/src/ui/sync_preview_dialog.dart) | What a transfer would do, deletions first and alone in the error colour, each bucket's file list one click away (at most one open, so a plan with thousands of changes cannot outgrow the screen), committing as "Run it, deleting N". |
| Acknowledged destructive confirm | [`remove_all_remotes.dart`](../../app/lib/src/ui/remove_all_remotes.dart) | The pattern for an action with no small version: name what goes, say the backup is taken first, and keep the red button **inert until an acknowledgement is ticked**. |
| Refusal dialog | [`sync_here_action.dart`](../../app/lib/src/ui/sync_here_action.dart) | "Nothing was synced", and why. A refusal is a dialog, not a snackbar: each one means the action would have destroyed something. |
| Disclosure | [`disclosure.dart`](../../app/lib/src/ui/disclosure.dart) | Label + summary + expandable detail — the "counts answer *is this what I expected*, names answer *which ones*" split. |
| Overflowing name | [`overflow_name.dart`](../../app/lib/src/ui/overflow_name.dart) | Line one at full size, and only the *tail* that did not fit continues underneath in smaller text. The sidebar problem was never that long names truncate, it was **where**: three remotes differing in their last two characters rendered as three identical rows. A name that fits is a plain `Text`, untouched. |

> **Before adding a component:** find the provider it should watch in
> [State & Context](../core/07-state-context.md), and reuse the existing formatters listed in
> [Utility Standards](../core/12-utility-standards.md) rather than writing a new one.

---
type: "index"
name: "Components Index"
status: "seed"
description: "Catalog of Airclone design-system component specifications."
---

# 🧩 Components Index

Catalog of reusable UI primitives and composites. Build from these — never hardcode one-off styles.
All components consume the tokens in [`wiki/core/06-design-system.md`](../core/06-design-system.md).

## 🧱 The component catalog

The reusable pieces every screen is assembled from. All of them shipped, and none has a `ui-*.md`
spec of its own — until one is written, **the source file is the specification**.

| Component | In the app | Purpose |
| :--- | :--- | :--- |
| Remote card | [`home_screen.dart`](../../app/lib/src/ui/home_screen.dart) `_RemoteTile` · [`home_view.dart`](../../app/lib/src/ui/home_view.dart) `_Tile` | Remote entry in the sidebar and on the Home start page: backend icon, name, and the `remote.type` subtitle the skin may suppress. |
| File row | [`file_row.dart`](../../app/lib/src/ui/file_row.dart) | One Details row — icon · name · size · modified · ⋯. Shared by the flat list and the tree so the two cannot drift; it knows nothing about *where* the file lives, which is what keeps the v0.5.0 stale-listing bug from coming back. |
| Grid cell & media tile | [`file_grid.dart`](../../app/lib/src/ui/file_grid.dart) · [`media_gallery.dart`](../../app/lib/src/ui/media_gallery.dart) | The same entry as an icon/thumbnail card, and as a square date-grouped gallery tile. Both take the parent's `thumbRequestFor` builder rather than an rclone client. |
| Icon & thumbnail | [`file_icon.dart`](../../app/lib/src/ui/file_icon.dart) · [`thumbnail_image.dart`](../../app/lib/src/ui/thumbnail_image.dart) | Extension→kind→icon+tint resolution, and the lazy tile that shows the kind icon until bytes resolve and then fades the decoded image in. |
| Tab strip | [`tab_strip.dart`](../../app/lib/src/ui/tab_strip.dart) | A pane's open tabs: switch, `✕` to close, `+` to open. One widget for the desktop pane header and the touch-sized phone header. |
| Toolbar & address bar | [`browser_pane.dart`](../../app/lib/src/ui/browser_pane.dart) `PaneToolbar` · [`path_bar.dart`](../../app/lib/src/ui/path_bar.dart) | Breadcrumb that morphs into an editable path, view menu, sort, filter, primary actions — collapsing by priority as the pane narrows, and hoisted above the sidebar by the OS skins. |
| Transfer row | [`jobs_panel.dart`](../../app/lib/src/ui/jobs_panel.dart) `_JobRow`, `_StatusChip` | A single transfer/job: progress, rate, ETA, controls, status chip. |
| Status bar | [`home_screen.dart`](../../app/lib/src/ui/home_screen.dart) `_StatusBar` | Engine phase + rclone version, then the active pane's item count, selection + size, and free/total where the backend exposes it. |
| Provider form | [`add_remote_dialog.dart`](../../app/lib/src/ui/add_remote_dialog.dart), fed by [`providers_provider.dart`](../../app/lib/src/state/providers_provider.dart) | Remote-config form generated from `config/providers` — the field list is rclone's, never ours. |
| Bottom nav | [`mobile_home.dart`](../../app/lib/src/ui/mobile_home.dart) | The phone shell's primary navigation: Files · Transfers · Settings. |

## 🗺️ Major surfaces

The screens and panels those components sit in. `app/lib/src/ui/` holds around eighty files; these
are the ones to read first when a change lands near them.

| Surface | Source | What it owns |
| :--- | :--- | :--- |
| Browser pane | [`browser_pane.dart`](../../app/lib/src/ui/browser_pane.dart) | One of the two panes: toolbar, tab strip, view switching, selection, context menus, drop targets, thumbnail pre-warm. Delegates the body to the list, grid, gallery or tree. |
| Tree view | [`tree_view.dart`](../../app/lib/src/ui/tree_view.dart) | The desktop-only hierarchical view: one flat `ListView` over a flattened forest, lazy per-expand listings, and the only view with an arrow-key cursor. |
| Inspector | [`inspector_panel.dart`](../../app/lib/src/ui/inspector_panel.dart) | The right rail reflecting the active pane's selection — single-file detail card, multi-select summary, empty/folder states. |
| Quick Look | [`quick_look.dart`](../../app/lib/src/ui/quick_look.dart) | The immersive overlay preview: dimmed full-window on desktop, edge-to-edge on touch. Reuses `PreviewContent` from [`preview_dialog.dart`](../../app/lib/src/ui/preview_dialog.dart). |
| Jobs dock | [`jobs_dock.dart`](../../app/lib/src/ui/jobs_dock.dart) · [`jobs_panel.dart`](../../app/lib/src/ui/jobs_panel.dart) · [`stats_panel.dart`](../../app/lib/src/ui/stats_panel.dart) | The always-visible transfer surface: live stats strip over the job list, plus a Recent activity tab. Shared by the desktop dock and the phone/TV Transfers tab. |
| Transfer options | [`transfer_options_dialog.dart`](../../app/lib/src/ui/transfer_options_dialog.dart) | The advanced Copy/Move/Sync power path — direction, filters, limits, dry run. It commits through the change-set preview in the table below. |
| Scheduled tasks | [`tasks_panel.dart`](../../app/lib/src/ui/tasks_panel.dart) | Saved tasks (list · run · delete · new) and the Settings → Automation face of scheduling. |
| Backup wizard | [`backup_wizard.dart`](../../app/lib/src/ui/backup_wizard.dart) | "Back up a folder" in three answers. Deliberately not a door to the transfer dialog — the destructive options are unreachable from here. |
| Mount & serve | [`mount_panel.dart`](../../app/lib/src/ui/mount_panel.dart) · [`mount_options_editor.dart`](../../app/lib/src/ui/mount_options_editor.dart) · [`serve_panel.dart`](../../app/lib/src/ui/serve_panel.dart) | Mount remotes as drives, and start/stop the share servers; both list what is running. |
| Command console | [`console_pane.dart`](../../app/lib/src/ui/console_pane.dart) | A pane that runs an rclone command instead of showing a folder, with token-aware autocomplete and secret redaction. Reached as a tab (`PaneKind.console`). |
| Command palette | [`command_palette.dart`](../../app/lib/src/ui/command_palette.dart) | `Ctrl+K`: fuzzy-filter every app action and jump to any remote. |
| Phone shell | [`mobile_home.dart`](../../app/lib/src/ui/mobile_home.dart) · [`mobile_action_sheets.dart`](../../app/lib/src/ui/mobile_action_sheets.dart) | The `<700px` shell and its bottom sheets — the phone's answer to the desktop's anchored dropdowns. |
| TV shell | [`tv.dart`](../../app/lib/src/ui/tv.dart) | Everything specific to a television, in one file on purpose. Nothing in it may run off a TV. |
| Settings | [`settings_screen.dart`](../../app/lib/src/ui/settings_screen.dart) | The desktop dialog and the phone's Settings tab, sharing one section list. |

## ✅ Shared dialogs & primitives

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

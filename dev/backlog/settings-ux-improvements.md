---
type: "backlog"
name: "Settings & Advanced-Config UX Improvements"
status: "proposed"
description: "Prioritized findings from the 2026-07-09 settings/advanced-settings UX review — make power features discoverable and advanced options self-explanatory."
---

# ⚙️ Settings & Advanced-Config UX Improvements

From a deep UX review (2026-07-09, beta.1 prep) of how settings and advanced rclone options are
reached and understood. Overall verdict: the individual surfaces are strong — the Transfer Options
dialog (Settings/Filters/rclone-cmd tabs, inline flag help, dry-run, copy-as-command) is
best-in-class — but they are **fragmented and under-discoverable**. Three dominant problems:

1. Flagship power features (Mount, Serve, Saved tasks, bisync, concurrency, engine flags) hide
   behind one opaque **"Advanced mode"** toggle the user must first discover — no ghosted buttons,
   no hint, and the toggle's description doesn't even mention Mount/Serve.
2. The **Add/Edit-remote form** — the most important advanced surface — throws away rclone's
   multi-line help and shows raw option keys (`access_key_id`, `chunk_size`).
3. **Settings itself** is one long 480px scroll: no search, no reset-to-default, no deep links;
   bandwidth is unreachable on mobile entirely.

## Findings (P0 = intuitiveness blocker … P3 = polish)

| # | P | Finding | Where | Fix |
|---|---|---------|-------|-----|
| 1 | P0 | Mount/Serve/Saved-tasks invisible until "Advanced mode" is found; its description omits Mount+Serve | `home_screen.dart:923-945,543-563`, `settings_screen.dart:174` | Always-visible "Mount as a drive…" / "Serve on LAN…" in the remote tile menu (`home_screen.dart:1395`); ghost the top-bar icons with an "Enable Advanced mode" affordance; enumerate everything the toggle reveals |
| 2 | P0 | Remote form drops rclone's real help; raw option keys as labels; `OptionExample.help` never shown | `add_remote_dialog.dart:322,515,534`, `provider.dart:76` | Info icon/tooltip revealing full `o.help`; example help as dropdown subtitles; humanized labels with the raw key as a mono hint (pattern from `transfer_options_dialog.dart:698`) |
| 3 | P1 | No search within Settings | `settings_screen.dart:69,107` | Reuse the Add-remote provider search pattern (`add_remote_dialog.dart:107`) to filter sections |
| 4 | P1 | No "Reset to default" anywhere — bad engine flags are an unrecoverable footgun | `settings_screen.dart:660,605`, `transfer_options_dialog.dart:180` | Reset buttons on Engine flags / Concurrency / rclone path; "Reset to defaults" in the transfer dialog footer |
| 5 | P1 | Bandwidth limit + schedule absent from Settings; unreachable on mobile | `bandwidth_control.dart:12`, `home_screen.dart:892`, `mobile_home.dart:557` | Add a Bandwidth section to the Transfers group in `SettingsContent` (presets + Schedule…), keep the top-bar popup as a shortcut |
| 6 | P1 | Concurrent transfers gated behind Advanced mode despite being safe + common | `settings_screen.dart:93,605` | Move to the basic Transfers group (desktop + mobile) |
| 7 | P1 | Engine flags: free text, no validation, silent restart, errors surface only later | `settings_screen.dart:660,678`, `engine_flags.dart:83` | Validate tokens on Apply with inline pass/fail; Reset button; doc link; more preset chips |
| 8 | P2 | Command palette can't deep-link to a setting | `home_screen.dart:500`, `command_palette.dart:8` | Discrete `PaletteAction`s ("Set theme: Dark", "Engine flags…") opening Settings anchored to the section |
| 9 | P2 | Copy-as-rclone-command only exists in the Transfer dialog | `transfer_options_dialog.dart:731`, `mount_panel.dart:39`, `serve_panel.dart:65` | Reuse the `_CmdTab` pattern: command preview + Copy in Mount and Serve; "Copy config" in remote Edit |
| 10 | P2 | Mount/Serve expose few options (no VFS cache size/age, read-ahead, allow-other, bind addr, TLS) | `mount_panel.dart:129`, `serve_panel.dart:168` | "Advanced" disclosure per dialog reusing `_AdvancedSection` (`add_remote_dialog.dart:602`) with inline help |
| 11 | P2 | rclone-path saves silently per keystroke while Engine flags has explicit Apply&restart — inconsistent | `settings_screen.dart:588,743` | Give rclone-path the same deferred Apply & restart affordance |
| 12 | P3 | Settings is one fixed 480px column; advanced sections buried at bottom | `settings_screen.dart:37,69` | Two-pane layout (category rail) or a TabBar at desktop widths |
| 13 | P3 | "Advanced mode" is an opaque grab-bag with mixed risk profiles | `settings_screen.dart:142`, `advanced_mode.dart:6` | Rename ("Power-user features"), enumerate its reveals, split dangerous (bisync) from harmless (concurrency) |
| 14 | P3 | All 40+ provider tiles share one generic cloud icon | `add_remote_dialog.dart:155` | Map common providers to distinct icons/monogram badges |

## Suggested batches

- **Batch A (discoverability, P0s + 6):** remote-tile Mount/Serve entries, ghosted top-bar icons,
  honest Advanced-mode description, un-gate concurrency.
- **Batch B (explain the options, 2 + 10 + 9):** full help in remote form, Advanced disclosures in
  Mount/Serve, copy-as-command everywhere.
- **Batch C (settings shell, 3 + 4 + 5 + 7 + 11):** search, resets, bandwidth section, flag validation.
- **Batch D (polish, 8 + 12 + 13 + 14).**

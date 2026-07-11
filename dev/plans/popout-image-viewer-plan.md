---
type: "plan"
name: "Pop-out Image Viewer (desktop)"
status: "planned"
description: "Separate, independently-resizable OS windows per image (multi-window) with their own zoom — desktop only, via desktop_multi_window 0.3.x."
---

# 🪟 Pop-out Image Viewer (desktop)

User ask: on desktop, pop an image out into its own OS window — resize freely, zoom independently,
open several at once, all decoupled from the main Airclone window.

## Approach (verified 2026-07-10)

**`desktop_multi_window` ^0.3.x**, desktop-only. Official Flutter multi-window (`RegularWindow` /
`runWidget`, `--enable-windowing`) is **main-channel-only + experimental** in stable 3.44 — we ship
on `stable`, so it's out until it lands (revisit then: it would drop the plugin *and* the
arg-passing since one engine could read Riverpod directly). `window_manager` can't spawn new
top-level windows; a second app process is heavier and messier. Plugin wins.

Key fit: each pop-out runs its **own FlutterEngine (no shared Riverpod)**, but an image viewer needs
only three strings we already compute in `PreviewContent` — `ObjectRef.url`, the `Authorization`
header, the file name — passed as JSON at window creation. And because the viewer is just
`Image.network` + `InteractiveViewer`, the sub-engine needs **no other plugins** (no
media_kit/pdfrx/super_native_extensions) — sidestepping the plugin-registration-in-secondary-engine
minefield almost entirely.

## Integration

1. **pubspec**: `desktop_multi_window: ^0.3.0` (pin; re-test on every Flutter stable bump).
2. **main.dart dispatch** — three-way, headless check STAYS FIRST and unchanged (it's argv-based, a
   real separate process; the pop-out branch is engine-argument-based, same process — they can't
   collide):
   - `isHeadlessInvocation(args)` → `runHeadless` (unchanged)
   - else, on desktop: `WindowController.fromCurrentEngine()` → if its arguments parse as
     `PopoutImageArgs`, `runApp(PopoutImageApp(...))` and RETURN (skip MediaKit/backdrop/ProviderScope)
   - else normal `runApp(ProviderScope(AircloneApp))`
3. **Shared viewer widget**: lift the existing `_ImageBody` (preview_dialog.dart — `InteractiveViewer(maxScale:8)` +
   `Image.network(url, headers)`) into a small public widget; reuse verbatim in both the in-app
   overlay and `PopoutImageApp` (a minimal `MaterialApp` + `AircloneTheme`). Identical zoom for free.
4. **Trigger**: a "Pop out ⧉" button in Quick Look / inspector preview, rendered only on
   Windows/macOS/Linux → `WindowController.create(WindowConfiguration(arguments: jsonEncode(...)))` +
   `.show()` instead of the in-app dialog. Mobile keeps the in-app overlay. Optionally pass sibling
   image URLs for prev/next inside the pop-out.
5. **Per-platform runner registration** (mandatory so the plugin's channel loads in each engine):
   - `windows/runner/flutter_window.cpp`: `DesktopMultiWindowSetWindowCreatedCallback(... RegisterPlugins(engine))`
   - `macos/Runner/MainFlutterWindow.swift`: `FlutterMultiWindowPlugin.setOnWindowCreatedCallback { RegisterGeneratedPlugins(registry: $0) }`
   - `linux/runner/my_application.cc`: `desktop_multi_window_plugin_set_window_created_callback(... fl_register_plugins(r))`
   A minimal registration is fine (viewer uses only built-in Image.network).
6. **Lifecycle**: per-window close destroys only that engine — NEVER `exit()` / `RcloneClient.quit()`
   from a pop-out (that's the trap in the official example). Only the primary window's close quits.

## Notes / risks

- All pop-outs share the app's one process → the same rcd child + per-session Basic-auth token stay
  valid app-lifetime. **Caveat:** an engine restart rotates the token, so an *already-open* pop-out
  that tries to RELOAD would 401 (the decoded image already shown is fine). Acceptable for MVP; a
  `WindowMethodChannel` refresh can be added later.
- Video (media_kit) / PDF (pdfrx) pop-outs would need those plugins + native libs registered in the
  sub-engine — real work; DEFER. Image-only first.
- macOS: watch window-shows-before-content / focus quirks; test on the notarized hardened-runtime
  build. Not App-Store-sandboxed (we spawn rcd), so one fewer constraint.
- Effort ~1–2 days for the image MVP; no showstoppers. Fallbacks if upstream stalls: the Devolutions
  fork, or `flutter_multi_window` (older separate-entrypoint model).

## Sequencing
After config batch B commits — batch B also edits `main.dart` + `pubspec.yaml`; land it first to
avoid conflicts. Then: mobile tabs+split → this.

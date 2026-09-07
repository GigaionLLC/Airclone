# Airclone — Design & Frontend Guidelines 🎨

To keep Airclone visually consistent across desktop and mobile, all UI work **MUST** follow the
master design system.

> [!IMPORTANT]
> Before creating or modifying any UI, read the full specification —
> ➡️ **[wiki/core/06-design-system.md](wiki/core/06-design-system.md)** for design intent and
> component behavior, and **[wiki/core/05-app-structure.md](wiki/core/05-app-structure.md)** for the
> layouts and wireframes. The token *names and values* are not prose: they live in
> [`tokens.dart`](app/lib/src/ui/theme/tokens.dart), quick-referenced below.

## 🎨 Creative North Star

Calm, confident, quietly powerful. Airclone treats 70+ cloud backends as if they were folders on your
own disk, hides rclone's flag soup behind sane defaults, and keeps every advanced control one
disclosure away. Principles: *every cloud feels local · direct manipulation first · safe by default,
powerful on demand · progressive disclosure · always-on observability.*

## ⚙️ Core design tokens (quick reference)

The tokens are **Dart, not CSS**. [`app/lib/src/ui/theme/tokens.dart`](app/lib/src/ui/theme/tokens.dart)
is the source of truth: it defines the scales, the palettes, and the `AircloneTheme` `ThemeExtension`
that carries them. [`AppTheme.build(skin, brightness)`](app/lib/src/ui/theme/app_theme.dart) installs
that extension on `ThemeData`, and 56 files under `app/lib/src/ui/` already read tokens back out of it.
Where a prose doc and `tokens.dart` disagree, the code wins.

| Token group | How a widget reads it | Values |
| :--- | :--- | :--- |
| Spacing (4px base) | `Space.x1 … x8` | 4 · 8 · 12 · 16 · 24 · 32 · 48 — **there is no `x7`** |
| Corner radius | `Radii.sm / md / lg / full` | 4 · 8 · 12 · 999 (pill) |
| Semantic colors | `AircloneTheme.of(context)` → `AircloneColors` | `surface` `surfaceRaised` `surfaceSunken` · `border` `borderStrong` · `text` `textMuted` `textFaint` · `primary` `primaryHover` `onPrimary` · `secondary` · `success` `successBg` · `warning` `warningBg` · `error` `errorBg` · `info` |
| Skin typography & density | `AircloneTheme.tokensOf(context)` → `SkinTokens` | font family + fallbacks, `bodySize`, `rowHeight`, `VisualDensity`, selection radius, row dividers |
| Skin chrome decisions | `AircloneTheme.chromeOf(context)` → `SkinChrome` | the per-skin layout switches: sidebar selection style, colored folder icons, always-visible search, hoisted/unified toolbar, compact branding, segmented view switcher |

```dart
final c = AircloneTheme.of(context);            // the common lookup — c.primary, c.textMuted
Padding(
  padding: const EdgeInsets.all(Space.x4),
  child: DecoratedBox(
    decoration: BoxDecoration(
      color: c.surfaceRaised,
      borderRadius: BorderRadius.circular(Radii.md),
      border: Border.all(color: c.border),
    ),
    child: Text('…', style: TextStyle(color: c.text)),
  ),
);
```

**What deliberately does not exist**, so do not reach for it: there is no type scale, no elevation
scale, and no compare/diff palette. Font sizes are written inline (11, 12 and 13 carry almost
everything) and the one size that *is* a token is the file-list body text, `SkinTokens.bodySize`,
because skins disagree about it. If a widget needs a value that is not in the table above, add it to `tokens.dart`
and use it everywhere — never invent a local constant or a raw hex.

## 🖥️ Skins

Airclone ships four skins — `Skin.airclone`, `.windows`, `.macos`, `.gnome` — each in light and dark,
so the app can read like the file manager the user already knows. `Skin.forHost()` picks the default:
Windows → `windows`, macOS → `macos`, Linux → `gnome`, everything else (Android, iOS) → `airclone`,
because the phone shell has its own Material grammar. The user can override it in Settings
(`skinProvider`, `app/lib/src/state/skin.dart`), and light/dark defaults to `ThemeMode.system`.

A skin is three things at once — `AircloneColors.forSkin(skin, brightness)`, `SkinTokens.of(skin)`
and `SkinChrome.of(skin)` — and `AppTheme.build` installs all three. So:

- **Never name a palette directly.** `AircloneColors.light`, `.dark`, `.windowsDark` and friends exist
  for `AppTheme` to select between; a widget that references one has pinned itself to one skin and
  will look wrong in the other seven combinations. Always go through `AircloneTheme.of(context)`.
- **Never branch on `Platform.isWindows` for looks.** The host OS only chooses the *default* skin; the
  active skin is a setting. Branch on `SkinChrome` instead, and add a field to it if the decision you
  need is not there yet.

## ✅ Rules

1. **Never hardcode** colors, spacing, or component styles — use the tokens above and the shared
   component primitives.
2. **Status is never color-only** — pair every dot/chip with an icon + text label.
3. **Destructive actions** show a one-line "what's about to happen" explainer and require confirmation.
4. **Plain language over jargon** — "Two-way sync" not "bisync"; "Mirror →" not `--delete-dest`.
5. **Responsive + accessible** — meet WCAG AA against the *active* skin's palette; full keyboard
   operability on desktop; 44px touch targets on mobile; honor the platform light/dark setting, and
   consult `MediaQuery.disableAnimationsOf(context)` before adding motion that matters.

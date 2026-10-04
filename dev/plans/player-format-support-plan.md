# 📦 Parcel Plan: Player — play what people actually have, natively (no transcoding)

## 📊 State Dashboard
| Metric | Value |
| :--- | :--- |
| **Status** | `PLANNED` — research done, direction set by Jake, no code written. Two empirical spikes (A0) gate the build. |
| **Version** | `v1.0.0` |
| **Active Persona** | `Architect` |
| **Last Updated** | 2026-10-04 |

Branch: `plan/search-scope-and-player-formats` (plan only). Sister plan, same customer email:
[search-scope-plan.md](search-scope-plan.md). Follows on from
[tv-playback-plan.md](tv-playback-plan.md), whose Out of Scope named the track pickers as "the
following iteration".

---

## 1️⃣ Phase 1: Expansion & Scoping

* **The ask (customer email, Android TV user, 2026-10-04):**
  > "Do you think in the future that it will be possible in the future to stream videos with real-time
  > transcoding or Adaptive Bitrate Streaming?"

* **Jake's direction (2026-10-04):** **No ffmpeg / no transcoding will be added.** On desktop, people
  open videos the player cannot handle in another app (VLC etc.). The work is the **built-in player
  supporting formats natively**.

* **What the code says.** The player is media_kit → libmpv, which already carries ffmpeg's *decoders*
  (decode only — "no ffmpeg" here means no transcoding, no CLI, no encoders). A string scan of the
  shipped Windows and Android libmpv found HEVC, AV1, VP9, VC-1, MPEG-2, AC-3/E-AC-3, DTS, TrueHD, FLAC,
  ALAC, PGS/VobSub/DVB subtitle decoders, libass, and the mpegts/mpeg-PS/asf/rm/mxf demuxers. So the
  gaps are **ours**, not the decoder's:
  1. **No audio-track or subtitle-track choice anywhere** — zero references to the tracks API in
     `app/lib` or the package. A film MKV with three languages plays whatever mpv picks.
  2. **Image subtitles (PGS/VobSub/DVB) never display.** media_kit's default `libass: false` sets mpv
     `sub-visibility=no` and renders only `sub-text` through a Flutter `SubtitleView`. Bitmap subs
     produce no text → nothing on screen, no message. ASS styling is flattened to plain text. And mpv
     auto-selects the first/default subtitle track, so a PGS default track = silent blank.
  3. **Sidecar subtitles never load.** mpv's `sub-auto` only scans local directories; we play an
     `http://127.0.0.1` object URL. `movie.srt` next to `movie.mkv` is ignored.
  4. **The recognised extension list is narrow** (`kVideoExts` = 10, `kAudioExts` = 8). `.m2ts`,
     `.vob`, `.3gp`, `.mka`, `.ape`… show "No preview available" though libmpv plays them. `ogv` is
     listed as browser-playable but in neither app list.
  5. **Nobody has ever written down what each platform's libmpv can do.** The "verified against the
     binaries" comment in `media_formats.dart` was an ad-hoc scan (commit `21c7bfb`, Android + Windows
     only, no script kept). macOS/iOS were never inspected; Linux uses the distro's libmpv.
  6. **Desktop hand-off to VLC downloads the whole file first** — `Open in another app` stages the
     object into the cache before launching, even when that remote is already mounted.

* **Intent:** A film from a cloud remote plays in Airclone with the right audio language and
  subtitles — embedded text, embedded image, or a sidecar file — on desktop, phone and Android TV; the
  file types libmpv can open are recognised as media; and when Airclone still can't play something on
  desktop, handing it to VLC is instant if the remote is mounted.

* **In Scope:**
  - Audio-track and subtitle-track pickers: desktop/phone controls and the TV transport row.
  - Subtitle rendering via libass (makes PGS/VobSub/DVB display and keeps ASS styling) — gated by spike A0.
  - Sidecar text subtitles (`.srt .ass .ssa .vtt`) found in the same folder and offered in the picker.
  - Preferred audio / subtitle language (remembered), applied through mpv `alang` / `slang`.
  - Widened extension tables, with a thumbnail opt-out for heavy containers.
  - A per-platform **capability matrix** produced by a debug tool, plus a small test-media set.
  - Desktop `Open in another app` uses the active mount path when one exists (no staging).
* **Out of Scope:**
  - Transcoding, adaptive bitrate generation, bundling ffmpeg/encoders (Jake: will not be added).
    Existing HLS/DASH manifests already play (libmpv picks the variant).
  - Track pickers in the **Web UI** (browser `<video>`: media_kit web never populates tracks; `<track>`
    only accepts WebVTT). Pickers are hidden on web.
  - Bitmap sidecars (`.sup`, `.idx/.sub`) in v1 — binary, attacker-authored, and VobSub needs the
    `.idx`→`.sub` nested open to inherit auth; revisit after A0.
  - Audio passthrough (AC-3/DTS bitstream to an AVR), Dolby Vision/HDR tone-mapping tuning, MediaSession.
  - Subtitles inside `Subs/` subfolders (needs an extra listing) — v2.
  - Two pre-existing defects found during research, tracked separately (§2 "Side findings").

## 2️⃣ Phase 2: Requirements & Context

Line numbers at `97fd8fb` (v0.22.2); `APP` = `app/lib/src/`, `RC` = `packages/airclone_rc/lib/src/`.
media_kit 1.2.6, media_kit_video 1.3.1, libs: android_video 1.3.8, windows_video 1.0.11,
macos_video/ios_video 1.1.4, linux 1.2.1 (system libmpv).

* **Relevant Docs Found:**
  - [`wiki/features/feat-media-playback.md`](../../wiki/features/feat-media-playback.md) — surfaces
    table, "When it cannot play". Gains a "Subtitles and audio tracks" section.
  - [`docs/guide/browsing.md`](../../docs/guide/browsing.md) — preview format table (~L240-250),
    `Open in another app` mentions.
  - [`docs/guide/mount-and-share.md`](../../docs/guide/mount-and-share.md) — where mounting works (~L40-47).
  - [`dev/android-tv.md`](../android-tv.md) — "Playback with a remote" (~L238-362), key table.
  - [`wiki/core/20-explorer-design.md`](../../wiki/core/20-explorer-design.md) L131 — "no ffmpeg" note
    and the thumbnail design.

* **Relevant Code Found:**
  - **Player** — [`ui/media_preview.dart`](../../app/lib/src/ui/media_preview.dart):
    `Player(PlayerConfiguration(protocolWhitelist: …))` L212-218 (nothing else set),
    `VideoController(player)` L230-233, `Media` open L285-307 (`loopbackUrlWithCredentials` /
    `ObjectRef.sendableHeaders`, [`rclone_client.dart`](../../packages/airclone_rc/lib/src/rclone_client.dart)
    L72-150), `_markStarted` ~L330, error/watchdog L240-283, `_teardown`/`_retry` L361-394 (**Retry
    builds a new Player — chosen tracks and added sidecars must be re-applied**), `_surface` L436-494:
    TV → `Video(controls: TvVideoControls)` L449-454; everything else → `AdaptiveVideoControls` with
    the repeat button appended via `_MaterialRepeatButton` (touch, ~L681) and
    `_MaterialDesktopRepeatButton` (~L703) inserted by `_withDesktopRepeat` L500-512. Track buttons go
    exactly beside the repeat button in both lists. No `SubtitleViewConfiguration` anywhere (L450, L491).
  - **TV** — [`ui/tv_video_controls.dart`](../../app/lib/src/ui/tv_video_controls.dart):
    `TvTransportRow` L408-496 (prev · rew · play/pause · ff · next); insert after `next` (L491) as
    `_TvControlButton`s (L561, 64 dp target). Overlay auto-hides after 5 s unless paused/pending
    ([`ui/tv_player_keys.dart`](../../app/lib/src/ui/tv_player_keys.dart) ~L187, L597-605) — a picker
    must hold the overlay open. `TvPlaybackTarget` (L45-69) has **no track API**; any new member must
    also land in `FakeTarget` (`app/test/tv_playback_fake.dart`). Key rules L281-405 (D-pad UP/DOWN
    into the row, LEFT/RIGHT traverse while browsing, OK activates, Back hides overlay first).
    [`ui/tv_now_playing.dart`](../../app/lib/src/ui/tv_now_playing.dart) has a `trailing:` slot (audio screen).
  - **media_kit internals (pub cache)** — `player/native/player/real.dart`: L2434-2436 `sub-ass`,
    `sub-visibility`, `secondary-sub-visibility` = libass ? yes : no; L2414-2415 `subs-fallback`,
    `subs-with-matching-audio` yes; L2326-2358 Android libass font loading (needs **both**
    `libassAndroidFont` asset path and `libassAndroidFontName`; the libs package ships **no** font);
    L1010-1056 `setAudioTrack` (`aid` or `audio-add`); L1086-1155 `setSubtitleTrack` (`sid`, or
    `sub-add <url> select <title> <lang>` for `.uri`); L1707-1883 `track-list` → `Tracks` (lists start
    with `auto`, `no`). `models/track.dart`: `id, title, language, codec, isDefault, channels…`.
    media_kit_video `subtitle/subtitle_view.dart` default text scales by √(area/1080p) → ~16 dp on a TV.
  - **Formats** — [`state/media_formats.dart`](../../app/lib/src/state/media_formats.dart):
    `kVideoExts` L29-40, `kAudioExts` L43-52, `isVideoLikeExt` L86, `isAudioExt` L90,
    `kBrowserPlayableExts` L109-126, `kPreviewProtocols` L157 (http, tcp, https, tls, crypto, data —
    **no `file`**, keep it that way), header comment L65-66 ("verified against the binaries").
    Consumers: `ui/file_icon.dart` `kindOf` L84-104 (ext first, then MIME), `isVideoThumbnailable`
    L117-118, `isGalleryMedia` L136; `ui/preview_dialog.dart` `_kindFor` L94-118 (`ts` is in
    `_textExts`), web guard L337; `ui/quick_look.dart` `sameKindNeighbour` L112-140;
    `state/open_external.dart` `_mimeByExt` (lacks flv, ts, m2ts, ogv, mka…).
  - **Thumbnails** — [`state/thumbnail_service.dart`](../../app/lib/src/state/thumbnail_service.dart):
    desktop/iOS start one libmpv per video (12 s desktop / 30 s mobile timeout, L124-126, L312-370);
    timeouts are **not** negative-cached (only blank frames, L142-148). Android uses
    MediaMetadataRetriever (cheap failure). Every new video ext joins the gallery + thumbnailer.
  - **Sidecar inputs** — Quick Look gets `loc.visibleSiblings` (name-filtered!) from
    `browser_pane.dart` `_preview()` L1394-1417; the **full** listing is `_EntryLoc.siblings` (L1352).
    `home_screen.dart` `_quickLookActive` L228-240 also passes `visibleEntries`. The preview dialog
    (inspector pill, `inspector_panel.dart` L305) has **no** sibling list. Sibling URL:
    `client.objectRef(remote.fs, joinPath(parentPath, name))` (pattern in `preview_dialog.dart`
    L268-291, incl. the `wouldHydrateOnRead` guard).
  - **Open externally** — [`ui/open_external_action.dart`](../../app/lib/src/ui/open_external_action.dart)
    L22-67 (local → direct; else `_StagingDialog` full download), `state/open_external.dart`
    (`canOpenExternally`, `stageForExternalOpen`, `handOffToOs` → desktop `launchUrl(Uri.file(path))`).
    Mounts: [`state/mount_controller.dart`](../../app/lib/src/state/mount_controller.dart)
    `mountControllerProvider` (polls `mount/listmounts` every 2 s) → `MountInfo{mountPoint, fs}`.
    Mounts exist on Windows, Linux, macOS DMG — never Mac App Store, iOS, Android, in-process engine.

* **libmpv builds per platform** (from the libs packages' build files; flavour "default" = reduced
  ffmpeg, no encoders):

  | Platform | Source | Notes |
  | :--- | :--- | :--- |
  | Android | `media-kit/libmpv-android-video-build` v1.1.7 `default-<abi>.jar` | + MediaCodec hw decoders; `hwdec=auto-safe`, `hwdec-codecs=h264,hevc,mpeg4,mpeg2video,vp8,vp9,av1`; emulator forces software |
  | Windows | `media-kit/libmpv-win32-video-build` 2023-09-24 (mpv `652a1dd`) | x86_64 only; d3d11va/dxva2/nvdec present |
  | macOS / iOS | `media-kit/libmpv-darwin-build` v0.6.0 `*-video-default` | **never inspected** |
  | Linux | system `libmpv.so.2` | distro ffmpeg (usually broader); Flatpak = runtime's |

  Scan (Android + Windows): **present** — demuxers mov/mp4, matroska/webm, avi, asf, flv, mpegts, mpeg
  (PS/VOB), ogg, rm, mxf, nut, dsf, hls, dash, vobsub, sup; video h264, hevc, av1, vp8/9, mpeg1/2/4,
  wmv1-3, vc1, theora, prores, rv10-40; audio ac3, eac3, dts, truehd, aac, flac, alac, vorbis, opus,
  wma, ape, wavpack, tta, mp1-3, cook, amr_nb (decoder); subs srt, ass/ssa, webvtt, mov_text, microdvd,
  PGS, dvd_subtitle, dvb_subtitle; libass. **Absent** — demuxers caf, w64, amr, voc, swf, wtv, ivf,
  dff. (String presence is a strong signal, not proof — A0 replaces it with mpv's own lists.)

* **Side findings (not this plan — separate tasks):**
  - In-process engine (iOS, Mac App Store, desktop opt-in): the loopback bridge copies the **whole
    object** into cache (`librclone_object_server.dart` `_materialize`) before byte one — a 4 GB film
    waits for 4 GB on iOS.
  - Remote-engine clients (`RemoteRcloneClient`): `sendableHeaders` returns `{}` for a non-loopback
    URL, so media behind an authenticated `--rc-serve` cannot play.

## 3️⃣ Phase 3: User Clarification

* `[x]` Transcoding / ffmpeg? → **Answer (Jake):** no. Desktop users open unsupported files in VLC etc.
* `[x]` Focus? → **Answer (Jake):** the built-in player natively supporting the formats.
* `[x]` **Q1. Turn libass on?** → **Answer (coordinator, 2026-10-04): not in this build.** A0.2
  needs a real Android TV, which the build agent does not have, so libass stays OFF behind one
  constant (`kLibassSubtitles` in `media_preview.dart`, default `false`) and the 4.B fallback ships:
  a TV-sized `SubtitleViewConfiguration` plus the Q3 image-track rule. Flip the constant (and add
  the Q2 font) only after A0.2 passes. Original default kept below for that decision:
  **yes, on every native platform**, if spike A0.2 passes on a real Android TV. It is the only way PGS/VobSub (Blu-ray / DVD rips) display, and ASS keeps its
  styling. Cost: Flutter-styled subtitles are replaced by mpv's (we set size/outline via mpv
  `sub-font-size`, `sub-border-size`, `sub-margin-y`), and Android needs a bundled font.
* `[x]` **Q2. Android subtitle font.** → **Answer (coordinator): plan default stands, but no font
  asset is added in this build** (libass is off, and no downloads). Default when A0.2 passes: **Default: Noto Sans (Latin, Greek, Cyrillic; ~0.6 MB).**
  Full CJK coverage (Noto Sans CJK / Droid Sans Fallback) costs 4-16 MB of APK. Desktop/iOS use
  system fonts. If the customer base needs CJK on Android, decide then.
* `[x]` **Q3. Subtitle default.** → **Answer (coordinator): the default below, as written.** **Default: respect the file** — mpv picks the default/forced track
  as today, but **if the auto-picked track is an image track and libass is unavailable** (web, or A0
  fails), select `no` and show `Image subtitles can't be shown here` in the picker. Once the user picks
  a language, remember it (Q4).
* `[x]` **Q4. Remember language choices?** → **Answer (coordinator): the default below.** **Default: yes** — `preferredAudioLanguage` and
  `preferredSubtitleLanguage` (`off` allowed) in `state/media_prefs.dart`, applied as mpv
  `alang`/`slang` before `open`. Global, not per file.
* `[x]` **Q5. `.ts` files.** → **Answer (coordinator): the default below.** **Default: stay code/text** (it is also TypeScript; Drive and Linux label
  TypeScript `video/mp2t`). Only `.m2ts .mts .m2t` become video. Revisit with a size + MIME heuristic
  only if someone asks.

## 4️⃣ Phase 4: Detailed Execution Plan

### 4.A0 Spikes — run first, record results here before building A1+

* **A0.1 Capability dump (all 5 platforms).** A debug-only action (Settings → About → Diagnostics,
  behind the existing diagnostics surface, not visible in release UI unless advanced mode) that creates
  a `Player`, reads mpv properties `demuxer-lavf-list`, `decoder-list`, `protocol-list`, `hwdec-current`
  (after opening a sample) via `NativePlayer.getProperty`, and writes them to the diagnostics log /
  copyable text. Run on Windows, macOS DMG, Linux AppImage + Flatpak, Android phone, Android TV, iPhone.
  Output → new `dev/media-support-matrix.md` (one table: container/codec/subtitle × platform), and
  `media_formats.dart` L65-66 points at it instead of "verified against the binaries".
* **A0.2 libass on Android TV.** Branch build with `libass: true` + Noto Sans asset: play (a) MKV with
  SRT + PGS tracks, (b) heavy ASS (anime typesetting), (c) 4K HEVC 10-bit with PGS. Check: PGS
  displays; ASS styling; no dropped frames vs libass off (mpv `frame-drop-count`); text readable from a
  sofa at chosen `sub-font-size`. **Pass → Q1 yes. Fail → keep Flutter SubtitleView for text subs and
  ship pickers with image tracks labelled "can't be shown".**
* **A0.3 sub-add over the loopback URL** on all three engine shapes: spawned rcd (Basic auth in
  userinfo), in-process librclone (Bearer via `http-header-fields` — does `sub-add` inherit it?),
  Android jniLib rcd. Confirm the external track appears in `track-list` with our title/lang, and that
  `sub-add` before file-loaded fails (so we add after `_markStarted`).
* **Test media** (generated, never committed — `tool/make-test-media.sh` runs ffmpeg in the existing
  Docker image on the *dev machine*; the app gains nothing): ~15 short clips: H.264/AAC MP4; HEVC 10-bit
  MKV with 2 audio (eng AC-3 5.1, deu AAC) + SRT + PGS (default) tracks; AV1 WebM; VP9 WebM; MPEG-2 in
  `.vob` and `.m2ts`; VC-1 `.wmv`; Theora `.ogv`; `.3gp`; MKV with ASS; `movie.mkv` + `movie.en.srt` +
  `movie.de.forced.srt` + `movie.ass`; audio `.mka .ape .wv .dsf .aiff .ac3 .m4b .oga`; negative cases
  `.caf .amr`. Upload to a test remote; the A0.1 table gets a row per file × platform.

### 4.A Track model and picker (shared)

* New `state/media_tracks.dart` (pure, unit-tested — no Flutter):

```dart
enum SubKind { text, image, unknown }

const kImageSubCodecs = {'hdmv_pgs_subtitle', 'dvd_subtitle', 'dvb_subtitle', 'xsub', 'dvb_teletext'};
SubKind subKindOf(SubtitleTrack t);

/// Human label, never the track id (a sub-added .uri track's id is the URL, which can carry
/// Basic-auth credentials in userinfo).
String trackLabel({String? title, String? language, String? codec, int? channels, bool isDefault,
    bool isForced, bool external});
// e.g. "English · 5.1 · AC-3 (default)", "Deutsch · forced", "English · SDH · external",
//      "Japanese · image" — language names from a small ISO-639 table (639-1 + 639-2/B).

class TrackChoice { … }   // what the picker lists: real tracks minus `auto`; `no` shown as "Off"
List<TrackChoice> audioChoices(Tracks t);
List<TrackChoice> subtitleChoices(Tracks t, {required bool imageSubsRenderable});
```

* `TvPlaybackTarget` gains `Stream<Tracks> get tracksStream`, `Tracks get tracks`,
  `Track get current`, `Future<void> setAudio(AudioTrack)`, `Future<void> setSubtitle(SubtitleTrack)`;
  `MediaKitPlaybackTarget` wraps the player (try/catch like the rest); `FakeTarget` mirrors it.
  This keeps one seam for TV, desktop and touch.
* **Picker UI** — `ui/track_picker.dart`: `showTrackPicker(context, target, kind)`:
  - Desktop/phone: a menu (desktop) / bottom sheet (touch) with radio rows; buttons
    `Icons.subtitles_outlined` + `Icons.audiotrack_outlined`, added beside the repeat button in **both**
    `_withDesktopRepeat` and the touch `bottomButtonBar`. Hidden when there is ≤ 1 audio track /
    0 subtitle tracks (subtitle button also visible when sidecars were found).
  - TV: two more `_TvControlButton`s after `next` in `TvTransportRow`; OK opens a focus-trapping
    full-height side panel (right edge, 10-foot type) — list with D-pad, OK selects and closes, Back
    closes. While open: controller `holdControls()` (new) so the 5 s auto-hide is suspended; on close
    focus returns to the button that opened it. Media keys keep working underneath.
  - Image tracks with libass unavailable: listed, disabled, suffix `· can't be shown here`.
  - Web: buttons not built (`HostPlatform.isWeb`).
* **Preferences** — `state/media_prefs.dart` gains `preferredAudioLanguage`,
  `preferredSubtitleLanguage` (ISO 639-2 or `off`), written when the user picks; `_start()` sets mpv
  `alang`/`slang` (and `sid=no` when `off`) through `(player.platform as NativePlayer).setProperty`
  **before** `open`. Retry re-applies the user's in-session picks after the new Player starts.

### 4.B Subtitle rendering (after A0.2)

* `PlayerConfiguration(libass: true, libassAndroidFont: 'assets/fonts/NotoSans-Regular.ttf',
  libassAndroidFontName: 'Noto Sans', protocolWhitelist: …)` on native platforms; asset added to
  `app/pubspec.yaml` (Android only needs it, but Flutter assets are global — acceptable at ~0.6 MB, or
  split via a deferred/Android-only asset if the size matters).
* Style via mpv properties after creation: `sub-font-size` (TV larger: 52 vs 44), `sub-border-size 3`,
  `sub-shadow-offset 1`, `sub-margin-y` (TV: overscan-aware), `sub-ass-override=scale` so ASS keeps
  styling but scales with our size choice. One helper `applySubtitleStyle(player, {required bool tv})`.
* If A0.2 fails: leave libass off; pass a `SubtitleViewConfiguration` with a TV-sized `TextStyle`
  (fixes the ~16 dp TV text either way) and rely on Q3's image-track rule.

### 4.C Sidecar subtitles

* New pure `state/sidecar_subs.dart`:

```dart
const kSidecarSubExts = {'srt', 'ass', 'ssa', 'vtt'};
const kSidecarMaxBytes = 2 * 1024 * 1024;

class Sidecar { final RcloneFile file; final String? language; final bool forced, sdh; }

/// Same folder, case-insensitive. "<stem>.<ext>" or "<stem>.<tag>[.<tag>…].<ext>" where tags are a
/// language (en, eng, english, pt-BR…), forced, sdh, cc, hi. Ignores directories, oversize files,
/// and anything that would hydrate a cloud placeholder (caller passes the predicate).
List<Sidecar> findSidecars(RcloneFile video, List<RcloneFile> siblings);
```

* Inputs: Quick Look must receive the **full** listing for sidecars — add `allSiblings`
  (`_EntryLoc.siblings`) next to the existing `visibleSiblings` in `browser_pane.dart` `_preview()` and
  `home_screen.dart` `_quickLookActive`; `PreviewContent`/`MediaPreviewBody` gain `sidecars:
  List<Sidecar>` resolved by the host (it has `client` + `remote`). The preview dialog (no sibling
  list) runs one `operations/list` of the parent (`noModTime`, `noMimeType`) — only for video files.
* Loading: after `_markStarted`, for each sidecar: `client.objectRef(remote.fs, path)` →
  `loopbackUrlWithCredentials` (same as the video) → `NativePlayer.command(['sub-add', url, 'auto',
  title, lang])` — **`auto`, not media_kit's `select`**, so the embedded/default choice (Q3/Q4) still
  wins and sidecars simply appear in the picker. If the file has **no** subtitle tracks at all and a
  sidecar matches the preferred language (or there is exactly one sidecar and no preference is
  `off`), select it.
* Security: only URLs from `client.objectRef` (never a `file://`, never a string built from a remote
  name); extension allowlist; size cap; titles shown from our `Sidecar` data, never from `track.id` /
  `external-filename` (credentials); log lines go through `redactSensitive`.
* Retry and Quick Look paging rebuild the player → `_start()` re-adds sidecars every time.

### 4.D Extension tables

* `kVideoExts` += `ogv, 3gp, 3g2, m2ts, mts, m2t, vob, divx, asf, f4v, rm, rmvb, mxf, mk3d`.
* `kAudioExts` += `mka, oga, spx, m4b, aiff, aif, ape, wv, tta, dsf, ac3, eac3, dts, mpc`
  (`mpc` only if A0.1 lists the `mpc`/`mpc8` demuxer — drop otherwise).
* **Not added** (demuxer absent in shipped builds): `caf, amr, w64, voc, wtv, dff, ivf, swf`. `.ts`
  stays code (Q5).
* New `kNoThumbVideoExts = {vob, m2ts, mts, m2t, mxf, rm, rmvb, asf}` honoured in
  `isVideoThumbnailable` (`file_icon.dart` L117) — big, slow-to-probe containers get the film icon, not
  a 12 s libmpv probe per tile. Plus: thumbnailer **negative-caches a timeout** for the session
  (`thumbnail_service.dart` L142-148) so a failed tile is not retried on every scroll.
* `open_external.dart` `_mimeByExt` gains the same extensions (correct MIME → Android chooser finds a
  player): `video/mp2t` (m2ts/mts), `video/x-ms-asf`, `video/ogg`, `video/3gpp`, `audio/x-matroska`, …
* `kBrowserPlayableExts` unchanged (now `ogv` is consistently video in-app too).
* Tests: `media_formats_test.dart` (incl. `.ts` stays code, `.m2ts` is video, `caf` is not),
  `browser_playable_test.dart`, `gallery_media_test.dart`, a new thumbnail opt-out test.

### 4.E Desktop: open in another app from the mount

* New pure helper `mountedOsPath({required List<MountInfo> mounts, required String fs, required String
  path, required bool windows}) → String?` in `state/open_external.dart`:
  - match `m.fs == remote.fs`, or a sub-root mount (`gdrive:work` mounting `work/…` → strip prefix);
    normalise trailing `:` and `/`;
  - reject any `..` / empty segment; join with the platform separator; result must start with the mount point.
* `openFileInAnotherApp`: on desktop, before staging, `mountedOsPath(...)`; if non-null and
  `File(p).exists()` answers within 2 s → `_handOff` directly (the OS default app — VLC if that's the
  user's default — streams through the VFS cache). Otherwise the current staging flow, unchanged.
  Never auto-mount. Android/iOS/MAS unchanged.
* The video error card's `Open in another app` therefore becomes instant for mounted remotes. Copy
  unchanged; optional tooltip `Opens from <mountPoint>`.
* Tests: `mounted_os_path_test.dart` (Windows drive letter `X:` vs `X:\`, Linux folder, sub-root mount,
  `..` rejection, no match).

### 4.F Test Verification Plan

* `flutter analyze`, `flutter test`, `dart format` (via `tool/flutter.sh`); `python tool/check-docs.py`.
* `[ ]` `media_tracks_test.dart` — labels (language names, channels, default/forced/external), image
  codec detection, choices with/without libass, `auto` hidden, never exposes `id`.
* `[ ]` `sidecar_subs_test.dart` — stem matching incl. dots in stems, language/forced/sdh tags, case,
  size cap, non-sub extensions ignored, directories ignored.
* `[ ]` `tv_video_controls_test.dart` / `tv_player_keys_test.dart` — new buttons reachable with
  LEFT/RIGHT from play/pause, OK opens the panel, auto-hide suspended while open, Back closes it and
  focus returns to the button; `FakeTarget` track members.
* `[ ]` `media_preview` widget test — buttons hidden with one audio + no subs; shown with tracks;
  hidden on web.
* `[ ]` `media_prefs_test.dart` — language prefs round-trip; `off`.
* `[ ]` Extension + thumbnail opt-out tests (4.D); `mounted_os_path_test.dart` (4.E).
* `[ ]` Manual, per A0 test media, on Windows, macOS, Linux, Android phone, **real Google TV**, iPhone:
  every row of `dev/media-support-matrix.md` filled in; pickers switch audio/subs live; sidecars appear;
  PGS displays (if libass); preferred language applied on the next file.

## 5️⃣ Phase 5: Product Owner Review
* **Status:** `PENDING` (planner self-check below; formal pass at build time)
* **Findings:**
  - ✅ **Vision & Scope** — answers the customer honestly (no transcoding) and fixes what film watchers hit first.
  - ⚠️ **Business Logic & Edge Cases** — libass decision rests on A0.2; image-sub fallback defined.
  - ⚠️ **Dependency & Functional Risk** — Android font asset adds APK size; macOS/iOS libmpv capabilities unknown until A0.1.
  - ✅ **Completeness & User Intent** — desktop VLC path made instant where possible, as Jake described.
* **Required Fixes:** None yet.

## 6️⃣ Phase 6: Senior Dev Hygiene Review
* **Status:** `PENDING`
* **Findings (planner self-check):**
  - ✅ **DRY Scan** — one track seam (`TvPlaybackTarget`) for TV + desktop + touch; one extension table file.
  - ✅ **Abstraction & Architecture** — `RcloneClient` unchanged; sidecar URLs via `objectRef` only.
  - ✅ **State Management & Data Flow** — prefs in `media_prefs`, per-session picks re-applied on Retry.
  - ✅ **Technical Debt & Deletion** — replaces the unverifiable "verified against the binaries" claim with a matrix doc.
  - ✅ **Secret Management** — never display/log a uri track id (Basic-auth userinfo).
  - ✅ **Data Security** — no `file` in the whitelist; no `file://` to `sub-add`; sidecar size + ext allowlist.
  - ✅ **Rate Limiting** — no new listing in Quick Look; one parent listing only in the preview dialog.
  - ✅ **Error Handling** — failed `sub-add` is logged (redacted) and skipped; playback never fails because a sidecar did.
* **Required Fixes:** None yet.

## 7️⃣ Phase 7: Implementation Checklist (Execution)
- `[x]` A0.1 capability dump action + `dev/media-support-matrix.md` (all platforms).
  - Built: Settings → Diagnostics → **Media capabilities** (Advanced mode, not web) →
    `ui/media_capabilities_dialog.dart` reads `mpv-version`, `ffmpeg-version`, `hwdec`,
    `hwdec-current`, `demuxer-lavf-list`, `decoder-list`, `protocol-list` via
    `NativePlayer.getProperty`; parsing/report pure in `state/media_capabilities.dart` (+ test).
    `hwdec-current` reads empty because no file is opened — said so in the report.
    `dev/media-support-matrix.md` created from the Android+Windows scan, marked PROVISIONAL;
    `media_formats.dart` header points at it. `tool/make-test-media.sh` written, NOT run.
    **Still open: running the dump on all 5 platforms (needs devices).**
- `[ ]` A0.2 libass spike on a real Google TV → answer Q1/Q2 here.
- `[ ]` A0.3 `sub-add` over loopback on the three engine shapes.
- `[x]` A1 `state/media_tracks.dart` + tests; `TvPlaybackTarget` track members + `FakeTarget`.
  - `TvPlaybackTarget` gained `tracks`, `tracksStream`, `selection()` (reads mpv `aid`/`sid` —
    media_kit's `state.track` only echoes what was set through it), `setAudio`, `setSubtitle`.
    Controller gained `selectTrack`, `onTrackPicked`, `holdControls`/`releaseControls`,
    `imageSubsRenderable`, `externalSubtitleTitles`, `expectedSidecars`. English language names
    (not endonyms); `mpvLanguageList` gives mpv every alias (`ger,deu,de`). 21 new tests.
- `[x]` A2 `ui/track_picker.dart`; desktop/touch buttons; TV buttons + side panel + `holdControls`.
  - `TrackPickerButton` (media_kit bars, before repeat; menu on desktop, bottom sheet on touch,
    nothing on web), `TvTrackPanel` (right-edge `FocusScope`, BACK consumed, OK picks + closes,
    focus returns to the opening button). TV buttons appear after `next` only in the video
    overlay (`onTrackPicker`), not on the audio now-playing screen. The "media_preview widget
    test" is `track_picker_test.dart` on the button itself — `MediaPreviewBody` constructs libmpv
    and cannot be pumped. 12 new widget tests (7 picker, 5 TV).
- `[x]` A3 Language prefs (`media_prefs`) + `alang`/`slang` before open; re-apply on Retry.
  - `preferredAudioLanguageProvider` / `preferredSubtitleLanguageProvider` (SharedPreferences keys
    `media_audio_language`, `media_subtitle_language`; ISO 639-2/B or `off`). `languageOptions()`
    (pure) → `alang`/`slang` with all aliases, `sid=no` for off; set via
    `NativePlayer.setProperty` before `open`. Picks are kept per preview (`_sessionPicks`) and
    re-applied in `_afterStart` after a Retry's new player starts. 7 new tests.
- `[ ]` A4 Subtitle rendering per A0.2 outcome (libass + font + style helper, or TV `SubtitleViewConfiguration`).
- `[ ]` A5 `state/sidecar_subs.dart` + full-sibling plumbing + `sub-add … auto` after start.
- `[ ]` A6 Extension tables, `kNoThumbVideoExts`, thumbnail timeout negative cache, `_mimeByExt`.
- `[ ]` A7 `mountedOsPath` + desktop open-from-mount.
- `[ ]` A8 Docs: feat-media-playback.md, browsing.md table, mount-and-share.md, platforms.md, dev/android-tv.md key/where-it-lives, tv-playback-plan.md out-of-scope note → link here, media_formats.dart header.
- `[ ]` A9 Real-device pass (matrix) + changelog entry.

## 8️⃣ Phase 8: Verification Dashboard
* **Verification Status:** `PENDING`

## 9️⃣ Phase 9: User Verification
* **Status:** `PENDING` — reply to the customer (Google TV) once on Play.

## 🔟 Phase 10: Wrap Up & Archival
* **System Context Updates:** `dev/media-support-matrix.md` becomes the source of truth for "what
  plays where"; `wiki/features/feat-media-playback.md` owns the track/subtitle model.

## ✅ Completion Note
<!-- Added during wrap-up. -->

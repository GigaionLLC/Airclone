# Media support matrix — what the built-in player opens, per platform

> **PARTLY PROVISIONAL.** The **Android** column is a real capability dump
> (Settings → Diagnostics → Media capabilities on the API 36 Android TV
> emulator, x86_64, 2026-10-04: mpv v0.36.0-549, ffmpeg n6.0; the same
> `libmpv-android-video-build` the phone and TV APKs ship), checked against
> playback where noted. The **Windows** column is still a crude string scan of
> the shipped DLL (2026-10-04, plan research) — it said MXF and TrueHD were
> present on Android too, and both were wrong. macOS, iOS and Linux have not
> been looked at. Replace each remaining `?` and scanned cell from that
> platform's dump.

This file is the source of truth for "what plays where". The extension tables in
[`media_formats.dart`](../app/lib/src/state/media_formats.dart) (`kVideoExts`,
`kAudioExts`) must not list a container whose demuxer is missing here: it would
turn a clear "No preview available" into a player that fails. The plan behind
it is [player-format-support-plan.md](plans/player-format-support-plan.md) §4.A0.

## Where each platform's libmpv comes from

| Platform | Source | Notes |
| :--- | :--- | :--- |
| Android (phone, TV) | `libmpv-android-video-build` v1.1.7, `default` flavour | + MediaCodec hardware decoders for h264, hevc, mpeg2/4, vp8, vp9, av1, which media_kit's video output turns on while a film plays (a bare player reports `hwdec=no`); the emulator forces software |
| Windows | `libmpv-win32-video-build` 2023-09-24 (mpv `652a1dd`) | x86_64 only; d3d11va / dxva2 / nvdec present |
| macOS DMG, Mac App Store, iOS | `libmpv-darwin-build` v0.6.0, `video-default` | **never inspected** |
| Linux AppImage / tar.gz | the system `libmpv.so.2` | the distro's ffmpeg, usually broader than the bundled builds |
| Linux Flatpak | the runtime's libmpv | not inspected |

"default" flavour means a reduced ffmpeg: decoders and demuxers only, no
encoders. Airclone never transcodes.

## Containers (demuxers)

Android: `yes` / `missing` = dump. Windows: string scan. `?` = not yet looked at.

| Container | Extensions | Android | Windows | macOS | iOS | Linux |
| :--- | :--- | :---: | :---: | :---: | :---: | :---: |
| Matroska / WebM | mkv mk3d mka webm | yes | yes | ? | ? | ? |
| MP4 / QuickTime | mp4 m4v mov 3gp 3g2 f4v m4a m4b | yes | yes | ? | ? | ? |
| AVI | avi divx | yes | yes | ? | ? | ? |
| ASF / WMV | asf wmv wma | yes | yes | ? | ? | ? |
| FLV | flv | yes | yes | ? | ? | ? |
| MPEG-TS | m2ts mts m2t | yes | yes | ? | ? | ? |
| MPEG-PS / VOB | mpg mpeg vob | yes | yes | ? | ? | ? |
| Ogg | ogg ogv oga opus spx | yes | yes | ? | ? | ? |
| RealMedia | rm rmvb | yes | yes | ? | ? | ? |
| MXF | mxf | **missing** | yes | ? | ? | ? |
| HLS / DASH | m3u8 m3u mpd | yes | yes | ? | ? | ? |
| Monkey's Audio | ape | yes | ?* | ? | ? | ? |
| WavPack | wv | yes | ?* | ? | ? | ? |
| TTA | tta | yes | ?* | ? | ? | ? |
| DSD (DSF) | dsf | yes | yes | ? | ? | ? |
| AIFF | aiff aif | yes | ?* | ? | ? | ? |
| Raw AC-3 / DTS | ac3 dts | yes | ?* |
| Raw E-AC-3 | eac3 | **missing** | ?* | ? | ? | ? |
| Musepack | mpc | yes (mpc, mpc8) | ? | ? | ? | ? |
| CAF | caf | missing | missing | ? | ? | ? |
| AMR | amr | missing | missing | ? | ? | ? |
| Wave64 | w64 | missing | missing | ? | ? | ? |
| VOC | voc | missing | missing | ? | ? | ? |
| WTV | wtv | missing | missing | ? | ? | ? |
| IVF | ivf | missing | missing | ? | ? | ? |
| DSDIFF | dff | missing | missing | ? | ? | ? |
| SWF | swf | missing | missing | ? | ? | ? |

`?*` = the Windows scan found the DECODER but did not record the demuxer either
way. The Android dump confirmed ape, wv, tta, aiff, ac3, dts and mpc, so
`.mpc` joined `kAudioExts`. It also showed **no MXF demuxer and no raw E-AC-3
demuxer**, so `.mxf` and `.eac3` left the tables (E-AC-3 inside MKV / MP4 is a
different thing and plays: verified on the TV emulator). RealMedia's demuxer is
there but its codecs are not (below), so `.rm` / `.rmvb` left as well. The
rows marked `missing` are why those extensions are absent. `.ts` is absent for
a different reason: it is also TypeScript (plan Q5).

## Codecs (decoders)

| Codec | Android | Windows | macOS | iOS | Linux |
| :--- | :---: | :---: | :---: | :---: | :---: |
| H.264, HEVC, AV1 (dav1d), VP8, VP9 | yes (+ MediaCodec) | yes | ? | ? | ? |
| MPEG-1/2/4, H.263, VC-1, WMV1-3, Theora, VP6, MJPEG | yes | yes | ? | ? | ? |
| ProRes | **missing** | yes (scan) | ? | ? | ? |
| RealVideo 1-4, Cook | **missing** (only ra_144 / ra_288) | yes (scan) | ? | ? | ? |
| AAC, MP3, FLAC, ALAC, Vorbis, Opus, WMA (incl. Pro / Lossless) | yes | yes | ? | ? | ? |
| AC-3, E-AC-3, DTS | yes (each played live on the TV emulator) | yes | ? | ? | ? |
| TrueHD | **missing** | yes (scan) | ? | ? | ? |
| APE, WavPack, TTA, Musepack 7/8, DSD | yes | yes | ? | ? | ? |
| AMR-NB / WB | **missing** | yes (scan) | ? | ? | ? |

TrueHD missing on Android is handled at playback: a film whose default audio
track is TrueHD switches to the next audio track with another codec and says so,
instead of failing (`fallbackAudioTrack` in `media_tracks.dart`; verified on the
TV emulator with `long-truehd-default.mkv`). A ProRes `.mov` fails to play on
Android; there is no extension to drop for it.

## Subtitles

mpv's `decoder-list` holds only audio and video decoders, so a dump cannot
answer for subtitles (it used to print `subrip: missing` beside a film whose
`.srt` was on screen; the report now lists subtitle codecs without a verdict).
The Android cells below come from playback on the TV emulator.

| Kind | Codecs | Android | Shown by Airclone today |
| :--- | :--- | :--- | :--- |
| Text, embedded | SubRip (in MKV) | plays (English / French switched live) | yes, as plain text (ASS styling is flattened) |
| Text, sidecar | `.srt` next to the video | plays (en / de listed as "external") | yes |
| Text, styled | ASS/SSA | not yet tested | flattened to plain text |
| Image | PGS (Blu-ray), VobSub (DVD), DVB | not tested | **no**: listed in the picker as "can't be shown here" |
| libass renderer | | | off until spike A0.2 passes on a real TV |

Image subtitles need libass rendering turned on (`kLibassSubtitles` in
`media_preview.dart`), which waits for plan spike A0.2 on a real Android TV.
Sidecar files (`.srt .ass .ssa .vtt` next to the video) are text and load on
every native platform.

## How to fill in a column

1. On the platform, turn on Advanced mode, open **Settings → Diagnostics →
   Media capabilities**, and press **Copy**.
2. Replace that column's cells from the "Matrix rows" section of the report.
3. Optionally, play each file from the test set (`tool/make-test-media.sh`) and
   note anything that is listed but still fails.
4. Remove the provisional banner once all five columns come from dumps.

# Media support matrix — what the built-in player opens, per platform

> **PROVISIONAL — replace with A0.1 dumps per platform.** Every "yes" and
> "missing" below comes from a crude string scan of the shipped Android and
> Windows libmpv (2026-10-04, plan research), not from libmpv itself. A string
> being present in a binary is a strong hint, not proof. Nobody has yet looked
> at macOS, iOS, or the Linux builds at all. Each `?` cell, and each scanned
> cell, is to be replaced by the output of **Settings → Diagnostics → Media
> capabilities** (Advanced mode on) run on that platform. That dialog asks
> libmpv for `demuxer-lavf-list`, `decoder-list` and `protocol-list`, and its
> "Matrix rows" section maps one to one onto the tables below.

This file is the source of truth for "what plays where". The extension tables in
[`media_formats.dart`](../app/lib/src/state/media_formats.dart) (`kVideoExts`,
`kAudioExts`) must not list a container whose demuxer is missing here: it would
turn a clear "No preview available" into a player that fails. The plan behind
it is [player-format-support-plan.md](plans/player-format-support-plan.md) §4.A0.

## Where each platform's libmpv comes from

| Platform | Source | Notes |
| :--- | :--- | :--- |
| Android (phone, TV) | `libmpv-android-video-build` v1.1.7, `default` flavour | + MediaCodec hardware decoders, `hwdec=auto-safe`; the emulator forces software |
| Windows | `libmpv-win32-video-build` 2023-09-24 (mpv `652a1dd`) | x86_64 only; d3d11va / dxva2 / nvdec present |
| macOS DMG, Mac App Store, iOS | `libmpv-darwin-build` v0.6.0, `video-default` | **never inspected** |
| Linux AppImage / tar.gz | the system `libmpv.so.2` | the distro's ffmpeg, usually broader than the bundled builds |
| Linux Flatpak | the runtime's libmpv | not inspected |

"default" flavour means a reduced ffmpeg: decoders and demuxers only, no
encoders. Airclone never transcodes.

## Containers (demuxers)

`yes` / `missing` = string scan; `?` = not yet dumped.

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
| MXF | mxf | yes | yes | ? | ? | ? |
| HLS / DASH | m3u8 m3u mpd | yes | yes | ? | ? | ? |
| Monkey's Audio | ape | ?* | ?* | ? | ? | ? |
| WavPack | wv | ?* | ?* | ? | ? | ? |
| TTA | tta | ?* | ?* | ? | ? | ? |
| DSD (DSF) | dsf | yes | yes | ? | ? | ? |
| AIFF | aiff aif | ?* | ?* | ? | ? | ? |
| Raw AC-3 / E-AC-3 / DTS | ac3 eac3 dts | ?* | ?* | ? | ? | ? |
| Musepack | mpc | ? | ? | ? | ? | ? |
| CAF | caf | missing | missing | ? | ? | ? |
| AMR | amr | missing | missing | ? | ? | ? |
| Wave64 | w64 | missing | missing | ? | ? | ? |
| VOC | voc | missing | missing | ? | ? | ? |
| WTV | wtv | missing | missing | ? | ? | ? |
| IVF | ivf | missing | missing | ? | ? | ? |
| DSDIFF | dff | missing | missing | ? | ? | ? |
| SWF | swf | missing | missing | ? | ? | ? |

`?*` = the scan found the DECODER but did not record the demuxer either way.
These extensions are in `kAudioExts` on the plan's judgement (ffmpeg ships the
demuxer beside the decoder in every build flavour we know of); a dump that
says `missing` removes them again.

Musepack was not in the scan's results either way, so `.mpc` is **not** in
`kAudioExts` until a dump shows the `mpc` / `mpc8` demuxer. The rows marked
`missing` are the reason those extensions are deliberately absent from the
tables. `.ts` is absent for a different reason: it is also TypeScript (plan Q5).

## Codecs (decoders)

| Codec | Android | Windows | macOS | iOS | Linux |
| :--- | :---: | :---: | :---: | :---: | :---: |
| H.264, HEVC (incl. 10-bit), AV1, VP8, VP9 | yes | yes | ? | ? | ? |
| MPEG-1/2/4, VC-1, WMV1-3, Theora, ProRes, RealVideo 1-4 | yes | yes | ? | ? | ? |
| AAC, MP3, FLAC, ALAC, Vorbis, Opus, WMA | yes | yes | ? | ? | ? |
| AC-3, E-AC-3, DTS, TrueHD | yes | yes | ? | ? | ? |
| APE, WavPack, TTA, Cook, AMR-NB | yes | yes | ? | ? | ? |

## Subtitles

| Kind | Codecs | Decoder present (Android / Windows) | Shown by Airclone today |
| :--- | :--- | :---: | :--- |
| Text | SubRip, ASS/SSA, WebVTT, mov_text, MicroDVD | yes / yes | yes, as plain text (ASS styling is flattened) |
| Image | PGS (Blu-ray), VobSub (DVD), DVB | yes / yes | **no**: listed in the picker as "can't be shown here" |
| libass renderer | | yes / yes | off until spike A0.2 passes on a real TV |

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

#!/usr/bin/env bash
# Generate the player test-media set (player format plan, A0 "Test media").
#
# Runs ffmpeg inside a container on the DEV MACHINE. The app gains nothing from
# this script and its output is never committed: upload the folder to a test
# remote, play each file on each platform, and fill in
# dev/media-support-matrix.md.
#
# Usage:
#   ./tool/make-test-media.sh [OUTPUT_DIR]       (default: ./build/test-media)
#   FFMPEG_IMAGE=<image> ./tool/make-test-media.sh
#
# FFMPEG_IMAGE must provide an `ffmpeg` entrypoint built with libx264, libx265,
# libvpx, libaom (or libsvtav1), libtheora, libvorbis, libopus and libmp3lame.
# Pin it by digest before relying on the output.
#
# What this CANNOT make: image subtitles (PGS / VobSub / DVB). ffmpeg does not
# convert text subtitles into bitmaps, so test those with a real Blu-ray or DVD
# rip. Everything printed here is ASCII on purpose (repo rule 12).
set -euo pipefail

OUT="${1:-build/test-media}"
IMAGE="${FFMPEG_IMAGE:-jrottenberg/ffmpeg:6.1-ubuntu}"
SECONDS_LONG=8

mkdir -p "$OUT"
OUT_ABS="$(cd "$OUT" && pwd)"

ff() {
  docker run --rm -v "$OUT_ABS:/out" -w /out "$IMAGE" -hide_banner -loglevel error -y "$@"
}

say() { printf '%s\n' "$*"; }

V="testsrc2=size=1280x720:rate=25:duration=$SECONDS_LONG"
A="sine=frequency=440:sample_rate=48000:duration=$SECONDS_LONG"
A2="sine=frequency=660:sample_rate=48000:duration=$SECONDS_LONG"

# Plain-text sidecars and an embedded-subtitle source, written on the host.
cat > "$OUT_ABS/movie.en.srt" <<'EOF'
1
00:00:00,500 --> 00:00:03,000
English sidecar line one

2
00:00:03,500 --> 00:00:07,000
English sidecar line two
EOF
cat > "$OUT_ABS/movie.de.forced.srt" <<'EOF'
1
00:00:01,000 --> 00:00:04,000
Deutsch forced line
EOF
cat > "$OUT_ABS/movie.ass" <<'EOF'
[Script Info]
ScriptType: v4.00+
PlayResX: 1280
PlayResY: 720

[V4+ Styles]
Format: Name, Fontname, Fontsize, PrimaryColour, OutlineColour, BackColour, Bold, Italic, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV
Style: Default,Arial,48,&H0000FFFF,&H00000000,&H00000000,0,0,1,3,0,8,20,20,40

[Events]
Format: Layer, Start, End, Style, Text
Dialogue: 0,0:00:00.50,0:00:07.00,Default,{\an8}ASS styled, top, yellow
EOF
cp "$OUT_ABS/movie.en.srt" "$OUT_ABS/embedded.srt"

say "Video containers and codecs"
ff -f lavfi -i "$V" -f lavfi -i "$A" -c:v libx264 -pix_fmt yuv420p -c:a aac h264-aac.mp4
ff -f lavfi -i "$V" -f lavfi -i "$A" -f lavfi -i "$A2" -i embedded.srt \
  -map 0:v -map 1:a -map 2:a -map 3:s \
  -c:v libx265 -pix_fmt yuv420p10le -c:a:0 ac3 -ac:a:0 6 -c:a:1 aac -c:s srt \
  -metadata:s:a:0 language=eng -metadata:s:a:1 language=deu \
  -metadata:s:s:0 language=eng -disposition:s:0 default \
  hevc10-2audio-srt.mkv
ff -f lavfi -i "$V" -f lavfi -i "$A" -c:v libaom-av1 -cpu-used 8 -c:a libopus av1.webm
ff -f lavfi -i "$V" -f lavfi -i "$A" -c:v libvpx-vp9 -deadline realtime -c:a libopus vp9.webm
ff -f lavfi -i "$V" -f lavfi -i "$A" -c:v mpeg2video -c:a mp2 -f vob mpeg2.vob
ff -f lavfi -i "$V" -f lavfi -i "$A" -c:v mpeg2video -c:a ac3 -f mpegts mpeg2.m2ts
ff -f lavfi -i "$V" -f lavfi -i "$A" -c:v wmv2 -c:a wmav2 wmv2.wmv
ff -f lavfi -i "$V" -f lavfi -i "$A" -c:v libtheora -c:a libvorbis theora.ogv
ff -f lavfi -i "testsrc2=size=352x288:rate=15:duration=$SECONDS_LONG" -f lavfi -i "sine=frequency=440:sample_rate=8000:duration=$SECONDS_LONG" \
  -c:v mpeg4 -c:a aac -ar 8000 -ac 1 phone.3gp
ff -f lavfi -i "$V" -f lavfi -i "$A" -i movie.ass -map 0:v -map 1:a -map 2:s \
  -c:v libx264 -pix_fmt yuv420p -c:a aac -c:s ass styled-ass.mkv

say "Sidecar set (movie.mkv + movie.en.srt + movie.de.forced.srt + movie.ass)"
ff -f lavfi -i "$V" -f lavfi -i "$A" -c:v libx264 -pix_fmt yuv420p -c:a aac movie.mkv

say "Audio containers"
ff -f lavfi -i "$A" -c:a libvorbis -f matroska tone.mka
ff -f lavfi -i "$A" -c:a wavpack tone.wv
ff -f lavfi -i "$A" -c:a pcm_s16be tone.aiff
ff -f lavfi -i "$A" -c:a ac3 tone.ac3
ff -f lavfi -i "$A" -c:a aac -f ipod tone.m4b
ff -f lavfi -i "$A" -c:a libvorbis -f ogg tone.oga
ff -f lavfi -i "$A" -c:a tta tone.tta

say "Negative cases (expected NOT to play: demuxer missing in shipped builds)"
ff -f lavfi -i "$A" -c:a pcm_s16le -f caf tone.caf
ff -f lavfi -i "sine=frequency=440:sample_rate=8000:duration=$SECONDS_LONG" -c:a pcm_s16le -f w64 tone.w64

rm -f "$OUT_ABS/embedded.srt"
say "Not generated (no encoder in ffmpeg): .ape .dsf .amr, PGS / VobSub subtitles."
say "Done: $OUT_ABS"

#!/usr/bin/env python3
"""Play one file through a given libmpv and report whether it finishes or hangs.

Used by appimage-media-probe.yml to test the AppImage's bundled libmpv against
a distro's own audio stack (the Arch "freezes when I open a video" report). It
loads the library with ctypes, so no mpv binary and no Flutter are involved:
what is measured is libmpv and the libraries it resolves.

    python3 mpv-probe.py <path/to/libmpv.so.2> <media file> [--ao=...]

Exit 0 when playback reaches the end of the file; 3 when mpv reported an
error; a hang is caught by the caller's `timeout`.
"""
import ctypes
import sys
import time

lib_path, media = sys.argv[1], sys.argv[2]
extra = [a for a in sys.argv[3:] if a.startswith("--")]

mpv = ctypes.CDLL(lib_path)
mpv.mpv_create.restype = ctypes.c_void_p
mpv.mpv_set_option_string.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_char_p]
mpv.mpv_initialize.argtypes = [ctypes.c_void_p]
mpv.mpv_command.argtypes = [ctypes.c_void_p, ctypes.POINTER(ctypes.c_char_p)]
mpv.mpv_get_property_string.argtypes = [ctypes.c_void_p, ctypes.c_char_p]
mpv.mpv_get_property_string.restype = ctypes.c_void_p
mpv.mpv_free.argtypes = [ctypes.c_void_p]
mpv.mpv_error_string.restype = ctypes.c_char_p
mpv.mpv_terminate_destroy.argtypes = [ctypes.c_void_p]


class Event(ctypes.Structure):
    _fields_ = [("event_id", ctypes.c_int), ("error", ctypes.c_int),
                ("reply_userdata", ctypes.c_uint64), ("data", ctypes.c_void_p)]


mpv.mpv_wait_event.argtypes = [ctypes.c_void_p, ctypes.c_double]
mpv.mpv_wait_event.restype = ctypes.POINTER(Event)

NAMES = {1: "SHUTDOWN", 6: "START_FILE", 7: "END_FILE", 8: "FILE_LOADED",
         11: "IDLE", 16: "VIDEO_RECONFIG", 17: "AUDIO_RECONFIG",
         20: "SEEK", 21: "PLAYBACK_RESTART"}


def say(msg):
    print("[%6.2fs] %s" % (time.monotonic() - T0, msg), flush=True)


def prop(h, name):
    p = mpv.mpv_get_property_string(h, name.encode())
    if not p:
        return None
    v = ctypes.cast(p, ctypes.c_char_p).value.decode()
    mpv.mpv_free(p)
    return v


T0 = time.monotonic()
h = mpv.mpv_create()
for k, v in [("vo", "null"), ("terminal", "yes"), ("msg-level", "all=warn,ao=v")]:
    mpv.mpv_set_option_string(h, k.encode(), v.encode())
for a in extra:
    k, _, v = a[2:].partition("=")
    mpv.mpv_set_option_string(h, k.encode(), v.encode())
say("mpv_initialize ...")
rc = mpv.mpv_initialize(h)
say("mpv_initialize -> %d" % rc)
args = (ctypes.c_char_p * 3)(b"loadfile", media.encode(), None)
say("loadfile -> %d" % mpv.mpv_command(h, args))
ok = False
while True:
    ev = mpv.mpv_wait_event(h, 1.0).contents
    if ev.event_id == 0:
        continue
    name = NAMES.get(ev.event_id, str(ev.event_id))
    if ev.event_id == 17:
        name += " (ao=%s)" % prop(h, "current-ao")
    say("event %s%s" % (name, "" if ev.error >= 0 else
                        " error=%s" % mpv.mpv_error_string(ev.error).decode()))
    if ev.event_id == 7:
        # mpv_event_end_file: int reason (0 = EOF, 4 = ERROR), int error.
        reason, err = ctypes.cast(ev.data, ctypes.POINTER(ctypes.c_int * 2)).contents
        say("end-file reason=%d error=%s" % (
            reason, mpv.mpv_error_string(err).decode() if err < 0 else "none"))
        ok = reason == 0
        break
say("done, ao was %s" % prop(h, "current-ao"))
mpv.mpv_terminate_destroy(h)
sys.exit(0 if ok else 3)

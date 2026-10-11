#!/usr/bin/env python3
"""List the bundled libraries that must be able to come from the system.

Used by build-appimage.sh. Prints one soname per line.

A library a system plugin also links (libwayland, libpipewire, GLib...) must
come from the system when the system's copy is newer (see #38 and #42). But a
library never travels alone: when the system's libpangoft2 was used beside our
bundled libpango, the AppImage died at startup with "undefined symbol:
pango_font_description_set_features". A system library was built against the
system's copies of what it links, so every bundled library in a seed's
dependency closure gets the same per-library rule (the newer copy wins). Then
whenever a newer system library is used, its dependencies are the system's
too, and whenever ours is used it is because the system's is older or absent,
which our newer copy satisfies.

    python3 prefer-system-groups.py <usr/lib> <seed soname>...
"""
import os
import re
import subprocess
import sys

LIBDIR = sys.argv[1]
SEEDS = sys.argv[2:]

bundled = {f for f in os.listdir(LIBDIR)
           if ".so" in f and os.path.isfile(os.path.join(LIBDIR, f))}


def needed(name):
    out = subprocess.run(["readelf", "-d", os.path.join(LIBDIR, name)],
                         capture_output=True, text=True).stdout
    return [n for n in re.findall(r"\(NEEDED\)\s+Shared library: \[([^\]]+)\]", out)
            if n in bundled]


seen, todo = set(), [s for s in SEEDS if s in bundled]
while todo:
    n = todo.pop()
    if n in seen:
        continue
    seen.add(n)
    todo.extend(needed(n))
for n in sorted(seen):
    print(n)

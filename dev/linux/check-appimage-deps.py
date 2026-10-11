#!/usr/bin/env python3
"""Audit an extracted AppImage (or the tar.gz bundle) against THIS system.

Two ways a package built on Ubuntu breaks on another distro, besides the
plugin shadowing check-shadowing.py covers:

  missing  a library some ELF in the package NEEDs that is neither bundled
           nor installed here. linuxdeploy leaves "system" libraries out
           (libusb, libgpg-error, fontconfig...), and a distro may lack one or
           name it differently (libbz2.so.1.0 on Debian is libbz2.so.1 on
           Fedora and Arch).
  paths    absolute Ubuntu paths compiled into a bundled library that is
           still first on the search path (a plugin directory, a certificate
           store), which do not exist here, so the feature silently finds
           nothing.

    python3 check-appimage-deps.py <root> [--strict]

<root> is an extracted AppImage (squashfs-root) or an unpacked tar.gz bundle.
With --strict, exits 1 when a library is missing. Paths are reported, never
fatal: most compiled-in paths are for features Airclone does not use.
Needs binutils (readelf, strings).
"""
import os
import re
import subprocess
import sys

ROOT = sys.argv[1]
STRICT = "--strict" in sys.argv


def run(*cmd):
    return subprocess.run(cmd, capture_output=True, text=True).stdout


def is_elf(path):
    try:
        with open(path, "rb") as f:
            return f.read(4) == b"\x7fELF"
    except OSError:
        return False


elfs = []
for d, _, files in os.walk(ROOT):
    for f in files:
        p = os.path.join(d, f)
        if os.path.isfile(p) and not os.path.islink(p) and is_elf(p):
            elfs.append(p)

packaged = {os.path.basename(p) for p in elfs}
system = set()
for line in run("/sbin/ldconfig", "-p").splitlines()[1:]:
    name = line.strip().split(" ", 1)[0]
    if name:
        system.add(name)

print("== Libraries the package needs that are neither bundled nor installed")
missing = {}
for p in elfs:
    out = run("readelf", "-d", p)
    for need in re.findall(r"\(NEEDED\)\s+Shared library: \[([^\]]+)\]", out):
        if need in packaged or need in system:
            continue
        # The dynamic loader and libc's own pieces are always there.
        if need.startswith(("ld-linux", "linux-vdso")):
            continue
        missing.setdefault(need, []).append(os.path.relpath(p, ROOT))
for need, users in sorted(missing.items()):
    print("  MISSING %-28s needed by %s%s" % (need, ", ".join(users[:3]),
                                             " (+%d more)" % (len(users) - 3)
                                             if len(users) > 3 else ""))
if not missing:
    print("  none")
print()

print("== Absolute paths compiled into libraries on the search path, absent here")
# Only what is first on the search path: usr/lib itself for an AppImage, lib/
# for the tar.gz. prefer-system and fallback copies are used only where the
# system's is older or missing, so their paths match a system like ours.
search = [p for p in elfs
          if os.path.dirname(p).endswith(("/usr/lib", "/lib"))
          and "/prefer-system/" not in p and "/fallback" not in p]
pat = re.compile(r"^(/usr/(lib|lib64|share|libexec)/[A-Za-z0-9_.+/-]{3,}|/etc/[A-Za-z0-9_.+/-]{3,})$")
absent = {}
for p in search:
    for s in run("strings", "-n", "8", p).splitlines():
        s = s.strip()
        if not pat.match(s) or "%" in s or s.endswith("/"):
            continue
        # A path only matters if its directory part is missing here.
        probe = s if "." not in os.path.basename(s) else os.path.dirname(s)
        if "x86_64-linux-gnu" in s or "aarch64-linux-gnu" in s:
            if not os.path.exists(probe):
                absent.setdefault(s, set()).add(os.path.basename(p))
for s, libs in sorted(absent.items()):
    print("  %-64s in %s" % (s, ", ".join(sorted(libs)[:3])))
if not absent:
    print("  none")
print()
print("%d missing librar%s; %d Debian-style path%s absent here."
      % (len(missing), "y" if len(missing) == 1 else "ies",
         len(absent), "" if len(absent) == 1 else "s"))
sys.exit(1 if (STRICT and missing) else 0)

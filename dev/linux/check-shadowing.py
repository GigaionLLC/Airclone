#!/usr/bin/env python3
"""Find every system plugin or driver that a bundled AppImage library would break.

The class of bug (#38, and the Arch video report): an AppImage puts its own
copy of a library on the search path, and a plugin or driver that the SYSTEM
loads into the same process (Mesa's EGL driver, the ALSA PipeWire plugin, a
VA-API driver, a Vulkan ICD...) was built against the system's newer copy. The
plugin then resolves its imports against our older copy, and fails to load, or
loads and misbehaves.

For each system plugin found under the usual plugin directories, this takes the
libraries it NEEDs, keeps those the AppImage bundles on its search path (that
is, would shadow), and checks every symbol the plugin imports from them is
defined in our copy. A missing symbol is a plugin that cannot load inside the
AppImage on this system.

    python3 check-shadowing.py <extracted AppImage usr/lib> [--strict]

Prints a report; with --strict, exits 1 when anything is broken.
Needs binutils (readelf, nm).
"""
import glob
import os
import re
import subprocess
import sys

BUNDLED_DIR = sys.argv[1]
STRICT = "--strict" in sys.argv

# Directories (globs) holding things the SYSTEM loads into an app's process.
PLUGIN_GLOBS = [
    "/usr/lib*/**/libEGL_*.so*", "/usr/lib*/**/libGLX_*.so*",
    "/usr/lib*/**/dri/*.so", "/usr/lib*/**/gbm/*.so",
    "/usr/lib*/**/*_drv_video.so", "/usr/lib*/**/vdpau/*.so*",
    "/usr/lib*/**/libvulkan_*.so", "/usr/lib*/**/alsa-lib/*.so",
    "/usr/lib*/**/spa-0.2/**/*.so", "/usr/lib*/**/pipewire-0.3/*.so",
    "/usr/lib*/**/pipewire-0.3/jack/*.so*", "/usr/lib*/**/pulseaudio/*.so",
    "/usr/lib*/**/gdk-pixbuf-2.0/*/loaders/*.so", "/usr/lib*/**/gio/modules/*.so",
    "/usr/lib*/**/gtk-3.0/*/immodules/*.so", "/usr/lib*/**/gtk-3.0/modules/*.so",
    "/usr/lib*/**/gvfs/*.so", "/usr/lib*/**/libproxy/*.so",
    "/usr/lib*/**/pkcs11/*.so", "/usr/lib*/**/sasl2/*.so",
]


def run(*cmd):
    return subprocess.run(cmd, capture_output=True, text=True).stdout


def needed(path):
    return re.findall(r"\(NEEDED\)\s+Shared library: \[([^\]]+)\]",
                      run("readelf", "-d", path))


def undefined(path):
    out = set()
    for line in run("nm", "-D", "--undefined-only", path).splitlines():
        sym = line.split()[-1] if line.split() else ""
        if sym:
            out.add(sym.split("@")[0])
    return out


def defined(path):
    out = set()
    for line in run("nm", "-D", "--defined-only", path).splitlines():
        parts = line.split()
        if parts:
            out.add(parts[-1].split("@")[0])
    return out


def system_lib(soname):
    for line in run("/sbin/ldconfig", "-p").splitlines():
        line = line.strip()
        if line.startswith(soname + " ") and "x86-64" in line or (
                line.startswith(soname + " ") and "AArch64" in line):
            return line.split("=>")[-1].strip()
    return None


# What the AppImage puts on the search path: usr/lib itself, never the fallback
# directories (AppRun adds those only when the system lacks or has an older copy).
bundled = {os.path.basename(p): p for p in glob.glob(os.path.join(BUNDLED_DIR, "*.so*"))
           if os.path.isfile(p)}

print("Bundled on the search path: %d libraries" % len(bundled))
print()
print("== Bundled libraries that are OLDER than the system's copy")
older = []
for soname in sorted(bundled):
    sys_path = system_lib(soname)
    if not sys_path:
        continue
    real = os.path.basename(os.path.realpath(sys_path))
    sys_ver = real[len(soname):].lstrip(".") if real.startswith(soname) else ""
    ours_def = defined(bundled[soname])
    sys_def = defined(sys_path)
    missing = sorted(sys_def - ours_def)
    if missing:
        older.append(soname)
        print("  %-32s system %-14s ours lacks %4d of the system's symbols, e.g. %s"
              % (soname, sys_ver or "?", len(missing), ", ".join(missing[:3])))
print()

print("== System plugins and drivers that cannot load against the bundled copies")
plugins = set()
for g in PLUGIN_GLOBS:
    plugins.update(p for p in glob.glob(g, recursive=True) if os.path.isfile(p))
defined_cache = {}
broken = 0
for plugin in sorted(plugins):
    shadowed = [n for n in needed(plugin) if n in bundled]
    if not shadowed:
        continue
    imports = undefined(plugin)
    problems = []
    for n in shadowed:
        if n not in defined_cache:
            defined_cache[n] = defined(bundled[n])
        sys_path = system_lib(n)
        # Only symbols the system copy provides and ours does not: a symbol the
        # plugin takes from some OTHER library is not this library's problem.
        sys_def = defined(sys_path) if sys_path else set()
        lacking = sorted((imports & sys_def) - defined_cache[n])
        if lacking:
            problems.append("%s lacks %s" % (n, ", ".join(lacking[:4])
                                             + (" (+%d more)" % (len(lacking) - 4)
                                                if len(lacking) > 4 else "")))
    if problems:
        broken += 1
        print("  BROKEN %s\n         %s" % (plugin, "\n         ".join(problems)))
print()
print("%d system plugin(s) would fail to load; %d bundled librar%s older than the system's."
      % (broken, len(older), "y is" if len(older) == 1 else "ies are"))
sys.exit(1 if (STRICT and broken) else 0)

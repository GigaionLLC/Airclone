"""Regenerates the desktop tray icons in app/assets/tray from docs/brand (#54).

    python -m pip install pillow
    python dev/desktop/make-tray-icons.py

Outputs:
  tray_windows.ico          full-colour app icon, 16-64 px frames. Windows
                            picks the small-icon frame for the DPI. A
                            full-colour icon reads on both light and dark
                            taskbars, so there is no light/dark pair.
  tray_linux.png            full-colour 64 px; indicator hosts scale it.
                            Flatpak/Snap use the installed icon NAME instead.
  tray_macos_template.png   black-on-transparent silhouette of the adaptive
                            foreground, used as an NSImage template so the menu
                            bar tints it for light/dark and the highlight.
"""

import os
import sys

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SRC = os.path.join(ROOT, "docs", "brand", "airclone-icon-1024.png")
FG = os.path.join(ROOT, "docs", "brand", "airclone-icon-adaptive-fg.png")
OUT = os.path.join(ROOT, "app", "assets", "tray")


def main() -> int:
    os.makedirs(OUT, exist_ok=True)
    color = Image.open(SRC).convert("RGBA")
    color.resize((64, 64), Image.LANCZOS).save(
        os.path.join(OUT, "tray_linux.png"), optimize=True
    )
    color.save(
        os.path.join(OUT, "tray_windows.ico"),
        sizes=[(16, 16), (20, 20), (24, 24), (32, 32), (40, 40), (48, 48), (64, 64)],
    )

    fg = Image.open(FG).convert("RGBA")
    fg = fg.crop(fg.getbbox())
    side = max(fg.size)
    square = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    square.paste(fg, ((side - fg.size[0]) // 2, (side - fg.size[1]) // 2))
    black = Image.new("RGBA", square.size, (0, 0, 0, 255))
    black.putalpha(square.getchannel("A"))
    padded_side = int(side * 1.1)
    padded = Image.new("RGBA", (padded_side, padded_side), (0, 0, 0, 0))
    offset = (padded_side - side) // 2
    padded.paste(black, (offset, offset))
    padded.resize((64, 64), Image.LANCZOS).save(
        os.path.join(OUT, "tray_macos_template.png"), optimize=True
    )
    print("wrote tray icons to " + OUT)
    return 0


if __name__ == "__main__":
    sys.exit(main())

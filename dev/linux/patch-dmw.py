"""Remove the line in desktop_multi_window that takes the app down with a window.

Its window-`destroy` handler pulls the FlView out of the closing window:

    GtkWidget* child = gtk_bin_get_child(GTK_BIN(widget));
    if (child && FL_IS_VIEW(child)) {
      gtk_container_remove(GTK_CONTAINER(widget), child);
    }

Every window the plugin creates has its OWN engine, so that view is that
engine's implicit view - and the embedder refuses to remove an implicit view.
What follows is a half-torn-down engine and, on a real desktop, a segfault that
takes the main window and every transfer in it.

Letting GTK tear the hierarchy down by itself is the smallest change that could
work. Whether it DOES work is the question dev/linux/test-popout.sh answers, and
the answer decides between waiting for upstream and shipping a patched copy.

    python dev/linux/patch-dmw.py <copy-of-the-plugin>
"""

from __future__ import annotations

import io
import sys

TARGET = """        GtkWidget* child = gtk_bin_get_child(GTK_BIN(widget));
        if (child && FL_IS_VIEW(child)) {
          gtk_container_remove(GTK_CONTAINER(widget), child);
        }

"""


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit("usage: patch-dmw.py <plugin-dir>")
    path = sys.argv[1] + "/linux/multi_window_manager.cc"
    src = io.open(path, encoding="utf-8").read()
    if TARGET not in src:
        raise SystemExit(
            "the plugin's destroy handler has changed shape - re-read it before "
            "trusting this patch: " + path
        )
    io.open(path, "w", encoding="utf-8", newline="\n").write(src.replace(TARGET, ""))
    print("  patched: the view is no longer removed from the closing window")


if __name__ == "__main__":
    main()

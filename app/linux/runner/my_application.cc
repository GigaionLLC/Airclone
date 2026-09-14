#include "my_application.h"

#include <dlfcn.h>
#include <string.h>

#include <flutter_linux/flutter_linux.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include "flutter/generated_plugin_registrant.h"
// desktop_multi_window: register plugins into each pop-out window's engine too.
#include "desktop_multi_window/desktop_multi_window_plugin.h"

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
};

// `--version` / `--help`, answered HERE in C++, before GTK or GL exist at all.
//
// THE BUG THIS FIXES: `./Airclone-x86_64.AppImage --version` aborted with
//
//   Couldn't open libGLESv2.so.2: cannot open shared object file
//
// because the flag did not exist and fell through to the normal launch, which
// builds a window. Dart cannot answer it on Linux without a GL context: the
// public flutter_linux API has no way to START an engine without realizing an
// FlView (fl_engine_new_headless creates one, but only the private
// fl_engine_start runs it, and FlView calls that from its realize callback,
// after the OpenGL manager is set up). So these two are handled before
// g_application_register, which is where GTK opens the display.
//
// The Dart side answers the same flags on Windows and macOS - see
// lib/src/headless/cli_info.dart. cli_info_test.dart reads this file and fails
// if the two stop listing the same options.
static bool HasArg(char** args, const char* want) {
  if (args == nullptr) return false;
  for (char** a = args; *a != nullptr; a++) {
    if (g_strcmp0(*a, want) == 0) return true;
  }
  return false;
}

static bool WantsCliInfo(char** args) {
  return HasArg(args, "--version") || HasArg(args, "--help") ||
         HasArg(args, "-h");
}

// The version from pubspec.yaml, without the build number, to match what the
// app reports everywhere else. Supplied by runner/CMakeLists.txt from the
// FLUTTER_VERSION that flutter_tools generates at build time.
static void PrintVersion() {
#ifdef AIRCLONE_VERSION
  g_autofree gchar* version = g_strdup(AIRCLONE_VERSION);
  gchar* plus = strchr(version, '+');
  if (plus != nullptr) *plus = '\0';
  g_print("Airclone %s\n", version);
#else
  g_print("Airclone (version unknown)\n");
#endif
}

static void PrintHelp() {
  PrintVersion();
  g_print(
      "\n"
      "Usage: airclone [options]\n"
      "\n"
      "With no options, Airclone opens its window.\n"
      "\n"
      "Options:\n"
      "  --webui                 Serve the interface to browsers instead of\n"
      "                          opening a window. Prints its URL and the\n"
      "                          generated password on first run.\n"
      "  --webui-bind ADDRESS    Address for --webui. Default 127.0.0.1\n"
      "                          (loopback only).\n"
      "  --webui-port PORT       Port for --webui. Default 5799.\n"
      "\n"
      "  --run-due               Run every scheduled task that is due, then exit.\n"
      "  --run-task ID           Run one saved task by id, then exit.\n"
      "\n"
      "  --log-input             Print one line per key event, and whether a\n"
      "                          text field had focus to receive it. For\n"
      "                          working out why a machine will not type.\n"
      "\n"
      "  --version               Print the version and exit.\n"
      "  --help, -h              Print this and exit.\n"
      "\n"
      "On Linux these open no window, but the app's engine still starts\n"
      "against a display and OpenGL ES. On a machine with neither, install\n"
      "Mesa GLES (sudo apt install libgles2) and run against a virtual\n"
      "display:\n"
      "\n"
      "  xvfb-run -a airclone --webui\n");
}

// Flags that run Dart without wanting a window. Dart branches on these before
// runApp, but on Linux the engine still needs a GL context to start at all, so
// they cannot skip GTK the way --version can. What they CAN do is fail with a
// useful message instead of aborting.
static bool WantsWindowlessDart(char** args) {
  if (args == nullptr) return false;
  for (char** a = args; *a != nullptr; a++) {
    if (g_strcmp0(*a, "--webui") == 0) return true;
    if (g_strcmp0(*a, "--run-due") == 0) return true;
    if (g_strcmp0(*a, "--run-task") == 0) return true;
    if (g_str_has_prefix(*a, "--run-task=")) return true;
  }
  return false;
}

// Whether the OpenGL ES library the Flutter engine loads is present.
//
// The reporter's machine (WSL) HAD a display - libEGL loaded and warned about
// DRI3 - and was missing only libGLESv2. libepoxy, which Flutter uses, opens
// exactly "libGLESv2.so.2" and aborts the process when it cannot. Checking the
// same name first turns a core dump into a message saying what to install.
static bool GlesAvailable() {
  void* handle = dlopen("libGLESv2.so.2", RTLD_LAZY | RTLD_LOCAL);
  if (handle == nullptr) return false;
  dlclose(handle);
  return true;
}

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

// Called when first Flutter frame received.
static void first_frame_cb(MyApplication* self, FlView* view) {
  gtk_widget_show(gtk_widget_get_toplevel(GTK_WIDGET(view)));
}


// The window's own chrome, rather than whatever GTK theme happened to resolve.
//
// THE BUG THIS FIXES: a thick pale frame around the window on Ubuntu 24.04,
// reported against the AppImage and present on BOTH X11 and Wayland — which is
// the clue that it is not a display-server problem. linuxdeploy bundles
// libgtk-3.so.0 into the AppImage but not GTK's theme data, GSettings schemas
// or icon themes, so the bundled GTK cannot resolve the desktop's real theme
// and falls back toward its compiled-in default. GTK draws client-side
// decorations — the rounded corners and the drop shadow — into a margin it
// allocates AROUND the window, and it paints that margin from the theme. With
// the wrong theme, and with no alpha channel to make a shadow translucent, the
// margin renders as a hard opaque frame in a colour that belongs to no part of
// this app.
//
// Two defences, because they cover different halves and neither is conditional
// on X11 vs Wayland:
//
//  1. Ask for an RGBA visual when the session is composited. That gives the
//     window an alpha channel, which is what lets GTK draw the shadow as a
//     shadow instead of as a solid block. This is the good path and keeps the
//     rounded corners a GNOME user expects.
//
//  2. When there is no alpha to be had — no compositor, or no RGBA visual —
//     collapse the decoration margin entirely. No margin, no frame. A square
//     window without a drop shadow is a cosmetic loss; a white border around
//     every window is a bug.
static void apply_window_chrome(GtkWindow* window) {
  GdkScreen* screen = gtk_widget_get_screen(GTK_WIDGET(window));
  GdkVisual* rgba = gdk_screen_get_rgba_visual(screen);
  if (rgba != nullptr && gdk_screen_is_composited(screen)) {
    gtk_widget_set_visual(GTK_WIDGET(window), rgba);
    return;
  }

  GtkCssProvider* css = gtk_css_provider_new();
  gtk_css_provider_load_from_data(
      css, "decoration { box-shadow: none; margin: 0; border-radius: 0; }",
      -1, nullptr);
  gtk_style_context_add_provider_for_screen(
      screen, GTK_STYLE_PROVIDER(css),
      GTK_STYLE_PROVIDER_PRIORITY_APPLICATION);
  g_object_unref(css);
}

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);

  // A windowless run (--webui, --run-due, --run-task) still BUILDS a window,
  // because realizing an FlView is the only public way to start the engine on
  // Linux - but it must never SHOW one.
  //
  // THE BUG THIS FIXES: `airclone --webui` opened an empty window titled
  // "airclone" and left it there for as long as the server ran. Dart never
  // calls runApp on that path, but binding init still schedules a warm-up
  // frame, so "first-frame" fired and first_frame_cb showed the toplevel. Our
  // own --help said "no window is shown", and someone serving the Web UI from a
  // spare machine had a dead window sitting in their session.
  const gboolean windowless =
      WantsWindowlessDart(self->dart_entrypoint_arguments);

  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));

  // Use a header bar when running in GNOME as this is the common style used
  // by applications and is the setup most users will be using (e.g. Ubuntu
  // desktop).
  // If running on X and not using GNOME then just use a traditional title bar
  // in case the window manager does more exotic layout, e.g. tiling.
  // If running on Wayland assume the header bar will work (may need changing
  // if future cases occur).
  gboolean use_header_bar = !windowless;
#ifdef GDK_WINDOWING_X11
  GdkScreen* screen = gtk_window_get_screen(window);
  if (GDK_IS_X11_SCREEN(screen)) {
    const gchar* wm_name = gdk_x11_screen_get_window_manager_name(screen);
    if (g_strcmp0(wm_name, "GNOME Shell") != 0) {
      use_header_bar = FALSE;
    }
  }
#endif
  if (use_header_bar) {
    GtkHeaderBar* header_bar = GTK_HEADER_BAR(gtk_header_bar_new());
    gtk_widget_show(GTK_WIDGET(header_bar));
    gtk_header_bar_set_title(header_bar, "airclone");
    gtk_header_bar_set_show_close_button(header_bar, TRUE);
    gtk_window_set_titlebar(window, GTK_WIDGET(header_bar));
  } else {
    gtk_window_set_title(window, "airclone");
  }

  // Must run BEFORE the window is realized: setting the visual on an
  // already-realized window has no effect.
  apply_window_chrome(window);

  gtk_window_set_default_size(window, 1280, 720);

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(
      project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  GdkRGBA background_color;
  // Background defaults to black, override it here if necessary, e.g. #00000000
  // for transparent.
  gdk_rgba_parse(&background_color, "#000000");
  fl_view_set_background_color(view, &background_color);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  // Show the window when Flutter renders - unless this run wants none, in which
  // case nothing ever maps the toplevel and it stays invisible. Realizing still
  // happens either way: that is what creates the GL context the engine starts
  // on.
  if (!windowless) {
    g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_cb),
                             self);
  }
  gtk_widget_realize(GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));

  // Every window desktop_multi_window creates (each pop-out image viewer) gets
  // the generated plugins registered on its own engine.
  desktop_multi_window_plugin_set_window_created_callback(
      [](FlPluginRegistry* registry) { fl_register_plugins(registry); });

  // fl_register_plugins SHOWS THE WINDOW. flutter_acrylic's Linux registrar
  // ends with gtk_widget_show() on the toplevel - see its
  // flutter_acrylic_plugin_register_with_registrar - so registering plugins
  // maps a window whatever this runner intended. Not connecting "first-frame"
  // is therefore not enough on its own; CI caught exactly that
  // ("--webui mapped a window"). Hide it again in the same turn of the loop,
  // before the main loop runs and X flushes.
  if (windowless) {
    gtk_widget_hide(GTK_WIDGET(window));
  } else {
    gtk_widget_grab_focus(GTK_WIDGET(view));
  }
}

// Implements GApplication::local_command_line.
static gboolean my_application_local_command_line(GApplication* application,
                                                  gchar*** arguments,
                                                  int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  // Strip out the first argument as it is the binary name.
  self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);

  // Before g_application_register: that is where GTK initialises and opens
  // the display, and --version must not need one.
  if (WantsCliInfo(self->dart_entrypoint_arguments)) {
    if (HasArg(self->dart_entrypoint_arguments, "--help") ||
        HasArg(self->dart_entrypoint_arguments, "-h")) {
      PrintHelp();
    } else {
      PrintVersion();
    }
    *exit_status = 0;
    return TRUE;
  }

  if (WantsWindowlessDart(self->dart_entrypoint_arguments) &&
      !GlesAvailable()) {
    g_printerr(
        "Airclone could not start: libGLESv2.so.2 (OpenGL ES) is not "
        "installed.\n"
        "\n"
        "On Linux the app's engine needs it to start, even for --webui, where\n"
        "no window is shown. Install your distribution's Mesa GLES package, for\n"
        "example:\n"
        "\n"
        "  sudo apt install libgles2      (Debian, Ubuntu, WSL)\n"
        "  sudo dnf install mesa-libGLES  (Fedora)\n"
        "\n"
        "then run the same command again.\n");
    *exit_status = 1;
    return TRUE;
  }

  // Windowless does not mean display-free, however much it should. The public
  // flutter_linux API starts an engine only by realizing an FlView, and that
  // needs a GdkWindow, so GTK must be able to open a display even though
  // nothing is ever shown on it. Say so plainly: without this the user meets
  // GTK's own "cannot open display" and has no idea what to do about it.
  if (WantsWindowlessDart(self->dart_entrypoint_arguments) &&
      g_getenv("DISPLAY") == nullptr &&
      g_getenv("WAYLAND_DISPLAY") == nullptr) {
    g_printerr(
        "Airclone could not start: no display.\n"
        "\n"
        "This command shows no window, but the app's engine can only be\n"
        "started against a display server. On a machine that has none, run it\n"
        "against a virtual one:\n"
        "\n"
        "  sudo apt install xvfb          (Debian, Ubuntu, WSL)\n"
        "  xvfb-run -a airclone --webui\n"
        "\n"
        "Over SSH, `ssh -X` also works.\n");
    *exit_status = 1;
    return TRUE;
  }

  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
    g_warning("Failed to register: %s", error->message);
    *exit_status = 1;
    return TRUE;
  }

  g_application_activate(application);
  *exit_status = 0;

  return TRUE;
}

// Implements GApplication::startup.
static void my_application_startup(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application startup.

  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
}

// Implements GApplication::shutdown.
static void my_application_shutdown(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application shutdown.

  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

// Implements GObject::dispose.
static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->local_command_line =
      my_application_local_command_line;
  G_APPLICATION_CLASS(klass)->startup = my_application_startup;
  G_APPLICATION_CLASS(klass)->shutdown = my_application_shutdown;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {}

MyApplication* my_application_new() {
  // Set the program name to the application ID, which helps various systems
  // like GTK and desktop environments map this running application to its
  // corresponding .desktop file. This ensures better integration by allowing
  // the application to be recognized beyond its binary name.
  g_set_prgname(APPLICATION_ID);

  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID, "flags",
                                     G_APPLICATION_NON_UNIQUE, nullptr));
}

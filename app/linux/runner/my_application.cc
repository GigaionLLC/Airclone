#include "my_application.h"

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
  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));

  // Use a header bar when running in GNOME as this is the common style used
  // by applications and is the setup most users will be using (e.g. Ubuntu
  // desktop).
  // If running on X and not using GNOME then just use a traditional title bar
  // in case the window manager does more exotic layout, e.g. tiling.
  // If running on Wayland assume the header bar will work (may need changing
  // if future cases occur).
  gboolean use_header_bar = TRUE;
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

  // Show the window when Flutter renders.
  // Requires the view to be realized so we can start rendering.
  g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_cb),
                           self);
  gtk_widget_realize(GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));

  // Every window desktop_multi_window creates (each pop-out image viewer) gets
  // the generated plugins registered on its own engine.
  desktop_multi_window_plugin_set_window_created_callback(
      [](FlPluginRegistry* registry) { fl_register_plugins(registry); });

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// Implements GApplication::local_command_line.
static gboolean my_application_local_command_line(GApplication* application,
                                                  gchar*** arguments,
                                                  int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  // Strip out the first argument as it is the binary name.
  self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);

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

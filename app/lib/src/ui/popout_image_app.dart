import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'popout_image_args.dart';
import 'theme/app_theme.dart';
import 'theme/tokens.dart';
import 'zoomable_network_image.dart';

/// The ONLY file that references `desktop_multi_window`. Everything here is
/// desktop-only and reached solely behind Platform gates (main.dart's dispatch
/// and quick_look.dart's trigger), so mobile builds — where the plugin has no
/// native implementation — never invoke the channel. The Dart layer is pure
/// MethodChannel, so importing it does not break the mobile compile.

/// Opens [args] in a NEW, independent native OS window via desktop_multi_window
/// (0.3.x). Each call spins up its own FlutterEngine (which re-runs `main`,
/// dispatching to [PopoutImageApp] — see main.dart) inside THIS process, so all
/// pop-outs share the one rcd child + its auth token. The JSON payload rides on
/// `WindowConfiguration.arguments` and is read back in the new engine via
/// [readPopoutImageArgs]. Desktop-only: callers gate on platform first.
Future<void> openPopoutImageWindow(PopoutImageArgs args) async {
  try {
    // hiddenAtLaunch defaults true, so the window stays invisible until show(),
    // avoiding a flash of an empty frame before the image paints.
    final controller = await WindowController.create(
      WindowConfiguration(arguments: args.encode()),
    );
    await controller.show();
  } catch (e) {
    // Best-effort: a failed spawn must never take down the caller (the in-app
    // overlay stays usable). Callers fire-and-forget, so swallow here.
    debugPrint('Airclone: pop-out window failed to open: $e');
  }
}

/// Reads THIS engine's pop-out payload, or null when this is not a pop-out
/// window. The PRIMARY window's arguments are empty -> null -> main() launches
/// the full app; a channel error (older engine / plugin absent) is also treated
/// as "not a pop-out". Called from `main()` on desktop only.
Future<PopoutImageArgs?> readPopoutImageArgs() async {
  try {
    // Runs on EVERY desktop launch before the primary window's normal init, so
    // cap it: a MissingPluginException/error already returns null via the catch,
    // and the timeout guards against a pathological channel hang bricking start.
    final controller = await WindowController.fromCurrentEngine().timeout(
      const Duration(seconds: 3),
    );
    return PopoutImageArgs.tryDecode(controller.arguments);
  } catch (_) {
    return null;
  }
}

/// Root of a pop-out image window: a minimal dark [MaterialApp] hosting the
/// shared [ZoomableNetworkImage] with a slim title/counter bar and, when the
/// pop-out carries siblings, prev/next (keyboard left/right + on-screen
/// chevrons). It deliberately has NO ProviderScope / engine / MediaKit — it
/// renders bytes the main window already authenticated.
///
/// CRITICAL: it must NEVER call `exit()` / `RcloneClient.quit()`. Closing this
/// OS window tears down only THIS engine (the official-example trap is quitting
/// the whole app from a secondary window); the main app keeps running and the
/// shared rcd stays up for the other windows.
class PopoutImageApp extends StatelessWidget {
  const PopoutImageApp({super.key, required this.args});

  final PopoutImageArgs args;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      // OS window title = the first image (paging updates the in-window bar,
      // not the native chrome title, which is fine for a viewer).
      title: args.initialName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      home: _PopoutImageWindow(args: args),
    );
  }
}

/// The window body: the current image plus paging chrome. Stateful only to track
/// which sibling is shown; each swap re-keys [ZoomableNetworkImage] so the decode
/// refreshes and zoom resets, matching Quick Look.
class _PopoutImageWindow extends StatefulWidget {
  const _PopoutImageWindow({required this.args});

  final PopoutImageArgs args;

  @override
  State<_PopoutImageWindow> createState() => _PopoutImageWindowState();
}

class _PopoutImageWindowState extends State<_PopoutImageWindow> {
  late int _i = widget.args.index;

  List<PopoutImageEntry> get _images => widget.args.images;

  Map<String, String> get _headers => widget.args.authorization.isEmpty
      ? const <String, String>{}
      : {'Authorization': widget.args.authorization};

  /// Move by [delta] within the sibling set, clamped to the ends.
  void _go(int delta) {
    final next = (_i + delta).clamp(0, _images.length - 1);
    if (next != _i) setState(() => _i = next);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowRight) {
      _go(1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      _go(-1);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final c = AircloneTheme.of(context);
    final entry = _images[_i];
    final many = _images.length > 1;

    return Scaffold(
      backgroundColor: c.surfaceSunken,
      body: Focus(
        autofocus: true,
        onKeyEvent: _onKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Slim in-window title bar: type glyph, file name, and — when
            // paging — an N/M counter (the OS chrome supplies the close button).
            Container(
              color: c.surface,
              padding: const EdgeInsets.symmetric(
                horizontal: Space.x4,
                vertical: Space.x2,
              ),
              child: Row(
                children: [
                  Icon(Icons.image_outlined, size: 18, color: c.textMuted),
                  const SizedBox(width: Space.x3),
                  Expanded(
                    child: Text(
                      entry.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: c.text,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (many) ...[
                    const SizedBox(width: Space.x3),
                    Text(
                      '${_i + 1} / ${_images.length}',
                      style: TextStyle(color: c.textFaint, fontSize: 12),
                    ),
                  ],
                ],
              ),
            ),
            Divider(height: 1, thickness: 1, color: c.border),
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: ZoomableNetworkImage(
                      // Re-key per URL so paging swaps the decode + resets zoom.
                      key: ValueKey(entry.url),
                      url: entry.url,
                      headers: _headers,
                      backgroundColor: c.surfaceSunken,
                    ),
                  ),
                  // On-screen chevrons for pointer users (keyboard arrows too).
                  if (many) ...[
                    Positioned(
                      left: Space.x3,
                      top: 0,
                      bottom: 0,
                      child: Center(
                        child: _PopoutNavButton(
                          icon: Icons.chevron_left,
                          onPressed: _i > 0 ? () => _go(-1) : null,
                        ),
                      ),
                    ),
                    Positioned(
                      right: Space.x3,
                      top: 0,
                      bottom: 0,
                      child: Center(
                        child: _PopoutNavButton(
                          icon: Icons.chevron_right,
                          onPressed: _i < _images.length - 1
                              ? () => _go(1)
                              : null,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A large translucent-circle nav chevron (greyed when [onPressed] is null) —
/// the same treatment as Quick Look's on-screen chevrons.
class _PopoutNavButton extends StatelessWidget {
  const _PopoutNavButton({required this.icon, this.onPressed});

  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Material(
      color: Colors.black.withValues(alpha: enabled ? 0.45 : 0.2),
      shape: const CircleBorder(),
      child: IconButton(
        icon: Icon(icon, size: 34),
        color: Colors.white,
        disabledColor: Colors.white24,
        onPressed: onPressed,
      ),
    );
  }
}

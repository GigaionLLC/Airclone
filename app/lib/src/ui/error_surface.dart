import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Replaces Flutter's release error box with something a user can act on.
///
/// **Why this exists.** When a widget's build throws, Flutter swaps the subtree
/// for `ErrorWidget.builder`. In DEBUG that is the red-and-yellow screen
/// everyone recognises. In a RELEASE build it is `RenderErrorBox`, which paints
/// a flat `Color(0xF0C0C0C0)` rectangle **with no text at all** — the message is
/// assembled inside an `assert`, so a release binary has none to draw.
///
/// A user hit exactly this: an unreadable Windows drive letter threw inside a
/// synchronous provider, and because three separate widgets watched it, the
/// sidebar and both file panes turned into grey rectangles. The app looked
/// "completely blank". Nothing on screen said an error had happened, named a
/// cause, or hinted where to look — so the report that reached us could only be
/// "nothing shows up", and the cause had to be inferred from a screenshot.
///
/// The underlying throw is fixed, but the failure MODE is the real defect: any
/// future build error would be equally invisible. This makes the next one say so
/// and point at the problem report, which is already captured locally
/// (`FlutterError.onError` feeds `state/diagnostics.dart` before this widget is
/// ever built).
///
/// Deliberately primitive. It renders during an error, so it uses only
/// `package:flutter/widgets.dart` with explicit colours and no `Theme`,
/// `Material`, `MediaQuery` or provider lookup — anything it depended on could
/// be the very thing that just failed. It must never throw itself.
void installVisibleErrorWidget() {
  // Debug keeps Flutter's own red screen: it carries the exception and stack,
  // which is strictly more useful to a developer than this is.
  if (kDebugMode) return;
  ErrorWidget.builder = (FlutterErrorDetails details) =>
      AircloneErrorSurface(details: details);
}

/// The surface [installVisibleErrorWidget] installs.
///
/// Public so it can be tested directly: the installer is deliberately a no-op in
/// debug (Flutter's own red screen is more useful to a developer), which would
/// otherwise leave the thing that actually ships with no coverage at all.
class AircloneErrorSurface extends StatelessWidget {
  const AircloneErrorSurface({super.key, required this.details});

  final FlutterErrorDetails details;

  @override
  Widget build(BuildContext context) {
    // One line, because this box is often small — a sidebar, a pane, a row —
    // and a wall of text in a 240px column communicates less than a sentence.
    final summary = details.exception.toString();
    return Container(
      color: const Color(0xFF2B1B1B),
      padding: const EdgeInsets.all(12),
      child: Center(
        child: DefaultTextStyle(
          style: const TextStyle(
            color: Color(0xFFFFD7D7),
            fontSize: 12,
            height: 1.35,
            decoration: TextDecoration.none,
            fontFamily: 'monospace',
            fontFamilyFallback: ['Courier New', 'monospace'],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "This part of Airclone couldn't be drawn.",
                style: TextStyle(
                  color: Color(0xFFFFFFFF),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  decoration: TextDecoration.none,
                ),
              ),
              const SizedBox(height: 6),
              Text(summary, maxLines: 6, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 8),
              const Text(
                'The rest of the app still works. Settings → Diagnostics → '
                'Problem report has the details, and is safe to share.',
                style: TextStyle(
                  color: Color(0xFFE0B4B4),
                  fontSize: 11,
                  decoration: TextDecoration.none,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

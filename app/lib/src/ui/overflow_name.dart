import 'package:flutter/material.dart';

/// A name that keeps its full size for as long as it fits, then continues on
/// further lines in smaller text instead of being cut off.
///
/// The sidebar's problem is not that long names are truncated — it is WHERE.
/// `S3-LONGREMOTENAME_RC-DISK-C1`, `-M1` and `-O1` differ only in their last two
/// characters, so a trailing ellipsis renders three different remotes as three
/// identical rows and the only way to tell them apart is to widen the sidebar.
///
/// Shrinking the whole label would make every row smaller to fix a few; wrapping
/// both lines at full size costs a lot of vertical space in a list meant for
/// scanning. So: line one stays exactly as it was, and only the overflow —
/// usually the distinguishing tail — drops to [overflowStyle].
///
/// A name that already fits renders as a single [Text] and is untouched, which
/// is nearly every row.
class OverflowName extends StatelessWidget {
  const OverflowName(
    this.text, {
    required this.style,
    required this.overflowStyle,
    super.key,
  });

  final String text;

  /// Line one, and the whole name whenever it fits.
  final TextStyle style;

  /// The remainder that did not fit, in smaller text. It WRAPS: at a narrow
  /// sidebar width the tail is itself too long for one line, and capping it at
  /// one produced the very truncation this widget exists to avoid - reported as
  /// the name being cut instead of continuing onto a third row.
  final TextStyle overflowStyle;

  /// How many lines the remainder may use before it really is ellipsized. A
  /// bound rather than none, so one absurd name cannot push every other row off
  /// a short sidebar.
  static const int maxTailLines = 3;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth;
      // Unbounded width (a Row that has not been given a share yet) has no
      // break point to find — behave exactly as the plain Text did.
      if (!width.isFinite || width <= 0) return _single(text, style);

      // Measure with the style that will actually paint: the row passes a
      // PARTIAL TextStyle which Flutter merges onto the inherited one, and the
      // font family differs per skin — measuring a bare TextStyle would be
      // measuring a font nobody is using. The viewer's text scale matters for
      // the same reason.
      final resolved = DefaultTextStyle.of(context).style.merge(style);
      final scaler = MediaQuery.textScalerOf(context);
      final direction = Directionality.of(context);
      TextPainter measure(String s) => TextPainter(
        text: TextSpan(text: s, style: resolved),
        textDirection: direction,
        textScaler: scaler,
      )..layout();

      // Laid out UNBOUNDED, so this is the name's natural single-line width.
      final full = measure(text);
      final fits = full.width <= width;
      // Where the line runs out, by CHARACTER — not by word. Letting the line
      // breaker choose would break at the last `-`, which for a name like
      // `S3-PX1_braunsynology1-backup` can leave line one holding just `S3-`.
      // Filling line one and letting the remainder fall through is both what
      // was asked for and the more legible of the two.
      var split = fits
          ? -1
          : full.getPositionForOffset(Offset(width, full.height / 2)).offset;
      full.dispose();
      if (fits) return _single(text, style);

      // getPositionForOffset snaps to the NEAREST boundary, so it can land half
      // a glyph past the edge; step back until line one genuinely fits, or the
      // ellipsis would eat the character we just moved to line two.
      split = split.clamp(0, text.length);
      while (split > 1) {
        final head = measure(text.substring(0, split));
        final over = head.width > width;
        head.dispose();
        if (!over) break;
        split--;
      }

      final head = text.substring(0, split);
      final tail = text.substring(split);
      // Nothing fit on line one (a width narrower than one glyph), or the break
      // consumed the whole string: there is no useful two-line form, so fall
      // back rather than render an empty line.
      if (head.isEmpty || tail.isEmpty) return _single(text, style);

      // The fragments are presentation only — a screen reader must still hear
      // one name, not two halves of one.
      return Semantics(
        label: text,
        child: ExcludeSemantics(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [_single(head, style), _tail(tail, overflowStyle)],
          ),
        ),
      );
    },
  );

  /// One line, never wrapping. Line one is by construction exactly what fits, but
  /// rounding between measurement and paint can leave it a hair over — an
  /// ellipsis is a better answer to that than an overflow stripe.
  static Widget _single(String s, TextStyle style) => Text(
    s,
    maxLines: 1,
    softWrap: false,
    overflow: TextOverflow.ellipsis,
    style: style,
  );

  /// The remainder, wrapping over up to [maxTailLines]. Line one is measured to
  /// fill the width exactly; the tail has no such guarantee and at a narrow
  /// width routinely needs more than one line of its own.
  static Widget _tail(String s, TextStyle style) => Text(
    s,
    maxLines: maxTailLines,
    softWrap: true,
    overflow: TextOverflow.ellipsis,
    style: style,
  );
}

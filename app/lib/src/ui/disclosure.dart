import 'package:flutter/material.dart';

import 'theme/tokens.dart';

/// A collapsed row that expands to reveal secondary controls.
///
/// Promoted from the private `_AdvancedSection` that lived in
/// `add_remote_dialog.dart`, because the mount dialog needed the same thing and
/// a second copy would have been the start of two that drift.
///
/// The addition over the original is [summary]: a short line describing the
/// state INSIDE, rendered on the collapsed row. A bare "Advanced" header makes
/// a user open it just to find out what they are about to get; a summary lets
/// them decide not to. [trailing] is for an action that only makes sense when
/// the state has been changed — the mount dialog puts "Reset to defaults"
/// there, and shows it only when there is something to reset.
class Disclosure extends StatelessWidget {
  const Disclosure({
    super.key,
    required this.label,
    required this.expanded,
    required this.onToggle,
    required this.children,
    this.summary,
    this.trailing,
  });

  /// The always-visible name, e.g. 'Advanced'.
  final String label;

  /// Optional one-line state, shown after [label] while collapsed AND while
  /// expanded — it is the answer to "what is this set to", which stays useful
  /// once the section is open.
  final String? summary;

  /// Optional action rendered at the end of the header row.
  final Widget? trailing;

  final bool expanded;
  final VoidCallback onToggle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = AircloneTheme.of(context);
    final sum = summary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: InkWell(
                onTap: onToggle,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: Space.x2),
                  child: Row(
                    children: [
                      Icon(
                        expanded ? Icons.expand_less : Icons.expand_more,
                        size: 18,
                        color: c.textMuted,
                      ),
                      const SizedBox(width: Space.x1),
                      Text(
                        label,
                        style: TextStyle(
                          color: c.textMuted,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (sum != null) ...[
                        const SizedBox(width: Space.x2),
                        Expanded(
                          child: Text(
                            sum,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: c.textFaint, fontSize: 12),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            ?trailing,
          ],
        ),
        if (expanded) ...children,
      ],
    );
  }
}

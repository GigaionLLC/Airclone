import 'console_command.dart';
import 'rclone_commands.dart';

/// Builds deep links into the rclone.org docs for a command or flag, so the
/// console can offer a "docs ↗" shortcut on suggestions and preview tokens.
/// URL patterns verified against rclone.org.
class RcloneDocs {
  RcloneDocs._();

  static const String commandsIndex = 'https://rclone.org/commands/';
  static const String flagsIndex = 'https://rclone.org/flags/';

  /// The docs page for a known subcommand: `rclone copy` →
  /// `https://rclone.org/commands/rclone_copy/`. Null for an unknown verb.
  static String? commandUrl(String verb) => kRcloneCommands.containsKey(verb)
      ? 'https://rclone.org/commands/rclone_$verb/'
      : null;

  /// The docs anchor for a global flag: `--transfers` →
  /// `https://rclone.org/flags/#transfers`.
  static String flagUrl(String flag) {
    final name = flagName(flag).replaceFirst(RegExp(r'^-+'), '');
    return '$flagsIndex#$name';
  }

  /// The best doc URL for a single token (a verb → its command page; a flag →
  /// the flags anchor). Null for a plain path/argument token.
  static String? forToken(String token, {required bool isFirst}) {
    if (token.startsWith('-')) return flagUrl(token);
    if (isFirst) return commandUrl(token);
    return null;
  }
}

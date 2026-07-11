/// The bundled catalog of rclone subcommands + their safety tier, plus the
/// destructive-flag set. This is the allowlist that gates the command console:
/// an unknown verb is treated as [CommandTier.blocked] and refused.
///
/// The list is curated from `rclone`'s command tree (v1.74.4); it changes only
/// when the pinned rclone bumps. Phase 2 layers autocomplete/help on top of the
/// same table. Classification is ALWAYS on parsed tokens, never a substring
/// match of the raw line (see [console_command.dart]).
library;

/// How dangerous a command is, which drives the console's guardrails.
enum CommandTier {
  /// Read-only or additive — runs freely (`ls`, `lsjson`, `size`, `cat`, `copy`…).
  safe,

  /// Can delete or overwrite data — requires a dry-run preview + typed confirm
  /// (`delete`, `purge`, `sync`, `move`, `dedupe`, `cleanup`…).
  destructive,

  /// Refused outright: leaks secrets, mutates config, or spawns long-lived
  /// servers that live outside Airclone's own lifecycle managers
  /// (`config*`, `mount`, `serve`, `rc`, `authorize`, `reveal`…). Unknown verbs
  /// also land here (allowlist by construction).
  blocked,
}

/// One catalog entry: the CLI verb, its tier, and a one-line description.
class RcloneCommandInfo {
  const RcloneCommandInfo(this.name, this.tier, this.help);
  final String name;
  final CommandTier tier;
  final String help;
}

RcloneCommandInfo _s(String n, String h) =>
    RcloneCommandInfo(n, CommandTier.safe, h);
RcloneCommandInfo _d(String n, String h) =>
    RcloneCommandInfo(n, CommandTier.destructive, h);
RcloneCommandInfo _b(String n, String h) =>
    RcloneCommandInfo(n, CommandTier.blocked, h);

/// The catalog, keyed by the leading verb (`token[0]`).
final Map<String, RcloneCommandInfo> kRcloneCommands = {
  for (final c in <RcloneCommandInfo>[
    // ── safe: read / info / additive (no data loss) ──────────────────────────
    _s('ls', 'List the objects in the path with size and path'),
    _s('lsd', 'List all directories/containers/buckets in the path'),
    _s('lsl', 'List the objects in path with modification time, size and path'),
    _s('lsf', 'List directories and objects in a parsing-friendly format'),
    _s('lsjson', 'List directories and objects in the path in JSON format'),
    _s('size', 'Count objects and their total size'),
    _s('cat', 'Concatenate any files and send them to stdout'),
    _s('tree', 'List the contents of the remote in a tree-like fashion'),
    _s('about', 'Get quota information from the remote'),
    _s('md5sum', 'Produce an md5sum file for all the objects in the path'),
    _s('sha1sum', 'Produce a sha1sum file for all the objects in the path'),
    _s('hashsum', 'Produce a hashsum file for all the objects in the path'),
    _s('check', 'Check if the files in the source and destination match'),
    _s('checksum', 'Check if the files match a SUM file'),
    _s('cryptcheck', 'Check the integrity of an encrypted remote'),
    _s('cryptdecode', 'Show forward/reverse mapping of encrypted filenames'),
    _s('listremotes', 'List all the remotes in the config file'),
    _s('mkdir', 'Make the path if it does not already exist'),
    _s('touch', 'Create new file or change file modification time'),
    _s('copy', 'Copy files from source to dest, skipping identical files'),
    _s('copyto', 'Copy files from source to dest, skipping identical files'),
    _s('copyurl', 'Copy the contents of the URL supplied to dest:path'),
    _s('rcat', 'Copies standard input to file on remote'),
    _s('link', 'Generate public link to file/folder'),
    _s('settier', 'Change storage class/tier of objects in remote'),
    _s('version', 'Show the version number'),
    // `backend <cmd>` can invoke destructive backend subcommands (cleanup,
    // cleanup-hidden, drop…) with no way to see the subcommand from the verb —
    // gate it behind the destructive confirm.
    _d('backend', 'Run a backend-specific command (some are destructive)'),
    // ── destructive: deletes or overwrites data ──────────────────────────────
    _d('delete', 'Remove the files in path'),
    _d('deletefile', 'Remove a single file from remote'),
    _d('purge', 'Remove the path and all of its contents'),
    _d('rmdir', 'Remove the empty directory at path'),
    _d('rmdirs', 'Remove empty directories under the path'),
    _d('cleanup', 'Clean up the remote if possible'),
    _d(
      'dedupe',
      'Interactively find duplicate filenames and delete/rename them',
    ),
    _d('sync', 'Make source and dest identical, modifying destination only'),
    _d('move', 'Move files from source to dest'),
    _d('moveto', 'Move file or directory from source to dest'),
    _d('bisync', 'Perform bidirectional synchronization between two paths'),
    _d('convmv', 'Convert file and directory names (renames in place)'),
    // ── blocked: secret exfil / config mutation / long-lived servers / meta ───
    _b(
      'config',
      'Manage config file (secrets) — use Airclone\'s config screens',
    ),
    _b('reveal', 'Reveal obscured password (secret exfil)'),
    // Its argument is a PLAINTEXT password (a positional we can't redact by flag
    // rule); keep it out of the console — use the config screens.
    _b('obscure', 'Obscure a password — use the config screens instead'),
    _b('authorize', 'Remote authorization (interactive OAuth)'),
    _b('reconnect', 'Re-authenticate a remote (interactive)'),
    _b('mount', 'Mount the remote — use Airclone\'s Mount manager'),
    _b('serve', 'Serve a remote — use Airclone\'s Serve manager'),
    _b('rc', 'Run a command against a running rclone'),
    _b('rcd', 'Run rclone listening to remote control commands'),
    _b('selfupdate', 'Update the rclone binary — managed by Airclone'),
    _b('gendocs', 'Output markdown docs for rclone to the directory supplied'),
    _b('gitannex', 'Speaks with git-annex over stdin/stdout'),
  ])
    c.name: c,
};

/// Flags that turn an otherwise-safe verb destructive (they delete on the
/// destination). Matched on the flag NAME (before any `=value`).
const Set<String> kDestructiveFlags = {
  '--delete-during',
  '--delete-before',
  '--delete-after',
  '--delete-excluded',
  '--rmdirs',
};

/// Global flags that must NEVER run via the console on ANY verb — they turn a
/// harmless command into a secret-exfil or long-lived-server vector inside the
/// child process `core/command` spawns:
///  - `--rc` / `--rc-*` start rclone's remote-control HTTP server (a
///    `--rc-no-auth --rc-addr :0` exposes config/dump to the LAN),
///  - `--config` / `--config-*` could point at or mutate another config,
///  - `--dump` / `--dump-*` echo auth headers/bodies.
/// (Airclone still passes its OWN `--config` for a config-file override — that is
/// appended internally, after classification, never typed by the user.)
bool isBlockedGlobalFlag(String name) =>
    name == '--rc' ||
    name.startsWith('--rc-') ||
    name == '--config' ||
    name.startsWith('--config-') ||
    name == '--dump' ||
    name.startsWith('--dump-');

/// The safety tier of a command, considering both the verb and its flags.
///
/// - Unknown verb → [CommandTier.blocked] (allowlist).
/// - A blocked verb, or ANY verb carrying a blocked global flag (`--rc*`,
///   `--config*`, `--dump*`) → [CommandTier.blocked].
/// - A safe verb carrying a destructive flag (e.g. `copy --delete-excluded`)
///   is promoted to [CommandTier.destructive].
CommandTier classifyTier(String verb, List<String> flags) {
  final info = kRcloneCommands[verb];
  if (info == null) return CommandTier.blocked;
  if (info.tier == CommandTier.blocked) return CommandTier.blocked;
  if (flags.any((f) => isBlockedGlobalFlag(_flagName(f)))) {
    return CommandTier.blocked;
  }
  final hasDestructiveFlag = flags.any(
    (f) => kDestructiveFlags.contains(_flagName(f)),
  );
  if (hasDestructiveFlag) return CommandTier.destructive;
  return info.tier;
}

/// The flag name without any `=value` suffix (`--delete-excluded=x` → `--delete-excluded`).
String _flagName(String flag) {
  final eq = flag.indexOf('=');
  return eq < 0 ? flag : flag.substring(0, eq);
}

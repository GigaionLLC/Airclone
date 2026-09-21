/// Hand-written knowledge about the clouds people actually add, and nothing
/// else.
///
/// rclone describes 69 backends and, for something like s3, 78 options that are
/// the union of every S3-compatible service in existence. That is a complete
/// description and a hostile first screen. This file is the opposite: a short,
/// opinionated list of what to show first, what to call it in plain words, and —
/// for the backends where rclone asks nothing at all — which handful of fields
/// actually have to be filled in.
///
/// **Pure data, no Flutter and no rclone client.** It is a lookup table, so it
/// is unit-tested against a real `config/providers` capture
/// (`app/test/fixtures/config_flows/provider_options.json`) which proves every
/// option named here still exists. Inventing an option name is the obvious way
/// for this file to rot, and that test is what stops it.
library;

/// How a field should be presented.
///
/// rclone's own type is not enough: it marks `access_key_id` and
/// `secret_access_key` as plain `string`, and flags them `Sensitive` rather than
/// `IsPassword`, so trusting its flags would print secrets on screen (plan
/// §2.2). Whether something is obscured is decided here, by us.
enum FieldKind {
  /// Ordinary single-line text.
  text,

  /// Obscured. Chosen by US, never inferred from rclone's flags.
  secret,

  /// Numeric (port numbers and the like).
  number,

  /// Yes/no.
  boolean,

  /// One of the option's own `Examples`, rendered as a picker.
  choice,

  /// The name of another remote already configured in this app.
  remote,
}

/// One field on a guided setup screen.
class RecipeField {
  const RecipeField(
    this.option,
    this.label, {
    this.kind = FieldKind.text,
    this.hint = '',
    this.help = '',
    this.required = false,
  });

  /// The rclone option name this writes. Must exist on the backend — the
  /// fixture test is what enforces that.
  final String option;

  /// What we call it, in words a person recognises.
  final String label;

  final FieldKind kind;
  final String hint;

  /// Our own help, shown instead of rclone's when set. rclone's help is written
  /// for someone reading `rclone config` in a terminal.
  final String help;

  final bool required;
}

/// A guided setup screen for a backend that rclone asks nothing about.
///
/// 46 of rclone's 69 backends have no interactive config at all (plan §2.1.10):
/// with `opt.all` off they return immediately, having written only
/// `type = <backend>` — a remote that exists and cannot reach anything. These
/// recipes stand in for the questions rclone never asks.
class SetupRecipe {
  const SetupRecipe({
    required this.type,
    required this.title,
    required this.fields,
    this.intro = '',
  });

  final String type;
  final String title;
  final String intro;
  final List<RecipeField> fields;
}

/// A choice in the "Add a cloud" picker.
class CloudChoice {
  const CloudChoice({
    required this.id,
    required this.label,
    required this.type,
    this.blurb = '',
    this.preset = const <String, String>{},
    this.aliases = const <String>[],
    this.popular = false,
  });

  /// Stable key — used by tests and as a widget key, never shown.
  final String id;

  /// The name on the tile.
  final String label;

  /// rclone's backend name. Note the ones containing spaces: `google photos`
  /// and `google cloud storage`.
  final String type;

  final String blurb;

  /// Option values applied before anything else — how one backend serves
  /// several brands. `provider` is the s3 case.
  final Map<String, String> preset;

  /// Extra words that should find this choice: brand names people search for
  /// that are not the backend's own name.
  final List<String> aliases;

  /// Shown as a tile rather than only through search.
  final bool popular;
}

/// The ten tiles, in the order they appear.
///
/// Ten is a deliberate ceiling: the list is meant to be scanned, not read. The
/// other backends are one tap away behind "All storage types", and search
/// covers everything either way.
const List<CloudChoice> kPopularClouds = <CloudChoice>[
  CloudChoice(
    id: 'drive',
    label: 'Google Drive',
    type: 'drive',
    blurb: 'Files from your Google account',
    aliases: <String>['google', 'gdrive', 'google drive'],
    popular: true,
  ),
  CloudChoice(
    id: 'onedrive',
    label: 'OneDrive',
    type: 'onedrive',
    blurb: 'Microsoft 365 and personal OneDrive',
    aliases: <String>['microsoft', 'sharepoint', 'office'],
    popular: true,
  ),
  CloudChoice(
    id: 'dropbox',
    label: 'Dropbox',
    type: 'dropbox',
    blurb: 'Dropbox personal or business',
    popular: true,
  ),
  CloudChoice(
    id: 'iclouddrive',
    label: 'iCloud Drive',
    type: 'iclouddrive',
    blurb: 'Apple iCloud Drive',
    aliases: <String>['apple', 'icloud'],
    popular: true,
  ),
  CloudChoice(
    id: 'googlephotos',
    label: 'Google Photos',
    type: 'google photos',
    blurb: 'Photos and albums from your Google account',
    aliases: <String>['photos', 'gphotos'],
    popular: true,
  ),
  CloudChoice(
    id: 's3',
    label: 'Amazon S3',
    type: 's3',
    blurb: 'S3 buckets on AWS',
    preset: <String, String>{'provider': 'AWS'},
    aliases: <String>['aws', 'bucket'],
    popular: true,
  ),
  CloudChoice(
    id: 'r2',
    label: 'Cloudflare R2',
    type: 's3',
    blurb: 'Cloudflare object storage',
    preset: <String, String>{'provider': 'Cloudflare'},
    aliases: <String>['cloudflare'],
    popular: true,
  ),
  CloudChoice(
    id: 'b2',
    label: 'Backblaze B2',
    type: 'b2',
    blurb: 'Backblaze object storage',
    aliases: <String>['backblaze'],
    popular: true,
  ),
  CloudChoice(
    id: 'sftp',
    label: 'SFTP',
    type: 'sftp',
    blurb: 'Any server you can reach over SSH',
    aliases: <String>['ssh', 'scp', 'server'],
    popular: true,
  ),
  CloudChoice(
    id: 'webdav',
    label: 'WebDAV',
    type: 'webdav',
    blurb: 'Nextcloud, ownCloud, Fastmail and others',
    aliases: <String>['nextcloud', 'owncloud', 'fastmail', 'dav'],
    popular: true,
  ),
];

/// Brands that are not tiles but must still be findable by name.
///
/// Searching "Wasabi" and getting nothing would be a wrong answer — it IS
/// supported, as one of s3's providers. These resolve straight to the right
/// backend with `provider` already set, so nobody has to know that Wasabi is
/// spelled "s3" in rclone.
///
/// **Storj is its own backend here, not s3.** rclone ships a dedicated `storj`
/// backend that speaks uplink directly; sending people to the S3 gateway
/// instead would hand them the slower path for no reason.
const List<CloudChoice> kSearchOnlyClouds = <CloudChoice>[
  CloudChoice(
    id: 'wasabi',
    label: 'Wasabi',
    type: 's3',
    blurb: 'Wasabi hot cloud storage (S3)',
    preset: <String, String>{'provider': 'Wasabi'},
  ),
  CloudChoice(
    id: 'minio',
    label: 'MinIO',
    type: 's3',
    blurb: 'Self-hosted MinIO (S3)',
    preset: <String, String>{'provider': 'Minio'},
  ),
  CloudChoice(
    id: 'spaces',
    label: 'DigitalOcean Spaces',
    type: 's3',
    blurb: 'DigitalOcean object storage (S3)',
    preset: <String, String>{'provider': 'DigitalOcean'},
    aliases: <String>['digitalocean'],
  ),
  CloudChoice(
    id: 'storj',
    label: 'Storj',
    type: 'storj',
    blurb: 'Storj decentralised storage',
  ),
];

/// Everything the picker can match on, tiles first.
const List<CloudChoice> kCuratedClouds = <CloudChoice>[
  ...kPopularClouds,
  ...kSearchOnlyClouds,
];

/// The curated entry for a backend type, or null.
///
/// When several choices share a type — s3 backs three of them — the one whose
/// [CloudChoice.preset] matches [values] wins, so an existing Cloudflare remote
/// is recognised as R2 rather than as generic S3.
CloudChoice? cloudChoiceFor(
  String type, {
  Map<String, String> values = const <String, String>{},
}) {
  CloudChoice? fallback;
  for (final c in kCuratedClouds) {
    if (c.type != type) continue;
    if (c.preset.isEmpty) {
      fallback ??= c;
      continue;
    }
    if (c.preset.entries.every((e) => values[e.key] == e.value)) return c;
  }
  return fallback;
}

/// Whether [choice] matches a search [query]. Case-insensitive, substring.
bool cloudMatches(CloudChoice choice, String query) {
  if (query.isEmpty) return true;
  final q = query.toLowerCase();
  if (choice.label.toLowerCase().contains(q)) return true;
  if (choice.type.toLowerCase().contains(q)) return true;
  if (choice.blurb.toLowerCase().contains(q)) return true;
  return choice.aliases.any((a) => a.toLowerCase().contains(q));
}

/// The hand-written screens, for the backends where rclone asks nothing.
///
/// Option names are rclone's and are verified against a real `config/providers`
/// capture. Labels, ordering and help are ours.
const Map<String, SetupRecipe> kSetupRecipes = <String, SetupRecipe>{
  's3': SetupRecipe(
    type: 's3',
    title: 'Connect S3 storage',
    intro: 'Use the access key pair from your provider console.',
    fields: <RecipeField>[
      RecipeField(
        'provider',
        'Service',
        kind: FieldKind.choice,
        help: 'Which S3-compatible service this bucket lives on.',
      ),
      RecipeField(
        'access_key_id',
        'Access key ID',
        kind: FieldKind.secret,
        required: true,
      ),
      RecipeField(
        'secret_access_key',
        'Secret access key',
        kind: FieldKind.secret,
        required: true,
      ),
      RecipeField(
        'region',
        'Region',
        kind: FieldKind.choice,
        help: 'Leave as it is if you are not sure.',
      ),
      RecipeField(
        'endpoint',
        'Endpoint',
        kind: FieldKind.choice,
        help: 'The service URL. Most providers other than AWS need one.',
      ),
    ],
  ),
  'b2': SetupRecipe(
    type: 'b2',
    title: 'Connect Backblaze B2',
    intro:
        'Create an application key in the Backblaze console, then paste both '
        'halves of it here.',
    fields: <RecipeField>[
      RecipeField('account', 'Key ID', required: true),
      RecipeField(
        'key',
        'Application key',
        kind: FieldKind.secret,
        required: true,
      ),
    ],
  ),
  'sftp': SetupRecipe(
    type: 'sftp',
    title: 'Connect over SSH',
    intro: 'Anything you can reach with ssh, you can browse here.',
    fields: <RecipeField>[
      RecipeField('host', 'Host', hint: 'example.com', required: true),
      RecipeField('user', 'Username'),
      RecipeField('port', 'Port', kind: FieldKind.number, hint: '22'),
      RecipeField(
        'pass',
        'Password',
        kind: FieldKind.secret,
        help: 'Leave blank if you sign in with a key file.',
      ),
      RecipeField(
        'key_file',
        'Private key file',
        help: 'Path to a private key, if you use one.',
      ),
    ],
  ),
  'webdav': SetupRecipe(
    type: 'webdav',
    title: 'Connect WebDAV',
    fields: <RecipeField>[
      RecipeField(
        'url',
        'Server URL',
        hint: 'https://cloud.example.com/remote.php/dav/files/me/',
        required: true,
      ),
      RecipeField(
        'vendor',
        'Server type',
        kind: FieldKind.choice,
        help:
            'Nextcloud, ownCloud, Fastmail and the rest behave slightly '
            'differently. Choose "other" if yours is not listed.',
      ),
      RecipeField('user', 'Username'),
      RecipeField('pass', 'Password', kind: FieldKind.secret),
    ],
  ),
  'ftp': SetupRecipe(
    type: 'ftp',
    title: 'Connect FTP',
    fields: <RecipeField>[
      RecipeField('host', 'Host', hint: 'ftp.example.com', required: true),
      RecipeField('user', 'Username'),
      RecipeField('port', 'Port', kind: FieldKind.number, hint: '21'),
      RecipeField('pass', 'Password', kind: FieldKind.secret),
      RecipeField(
        'tls',
        'Use TLS',
        kind: FieldKind.boolean,
        help:
            'Encrypts the connection. Turn this on unless the server cannot '
            'do it.',
      ),
    ],
  ),
  'smb': SetupRecipe(
    type: 'smb',
    title: 'Connect a Windows share',
    fields: <RecipeField>[
      RecipeField('host', 'Host', hint: 'nas.local', required: true),
      RecipeField('user', 'Username'),
      RecipeField('pass', 'Password', kind: FieldKind.secret),
      RecipeField('domain', 'Domain', help: 'Usually left blank at home.'),
    ],
  ),
  'azureblob': SetupRecipe(
    type: 'azureblob',
    title: 'Connect Azure Blob Storage',
    fields: <RecipeField>[
      RecipeField('account', 'Storage account', required: true),
      RecipeField('key', 'Account key', kind: FieldKind.secret),
      RecipeField(
        'sas_url',
        'SAS URL',
        kind: FieldKind.secret,
        help: 'An alternative to the account key — fill in one or the other.',
      ),
    ],
  ),
  'crypt': SetupRecipe(
    type: 'crypt',
    title: 'Encrypt an existing remote',
    intro:
        'This wraps storage you have already added. Files are encrypted on '
        'this device before they are uploaded.',
    fields: <RecipeField>[
      RecipeField(
        'remote',
        'Storage to encrypt',
        kind: FieldKind.remote,
        required: true,
        help: 'An existing remote, and optionally a folder inside it.',
      ),
      RecipeField(
        'password',
        'Password',
        kind: FieldKind.secret,
        required: true,
        help: 'If this is lost the files cannot be recovered by anyone.',
      ),
      RecipeField(
        'password2',
        'Salt',
        kind: FieldKind.secret,
        help:
            'Optional, and it has to be remembered too — a wrong salt makes '
            'the folder look empty rather than reporting an error.',
      ),
      RecipeField(
        'filename_encryption',
        'Encrypt file names',
        kind: FieldKind.choice,
      ),
    ],
  ),
};

/// The recipe for [type], or null when rclone drives that backend itself.
SetupRecipe? recipeFor(String type) => kSetupRecipes[type];

/// A short, unique remote name suggested from the backend type.
///
/// Nobody should be stopped at step one to invent a name, so the suggestion
/// arrives already filled in and stays editable. It is settled BEFORE the
/// remote is created on purpose: for an OAuth backend the config section exists
/// from the moment sign-in starts, and renaming afterwards would mean
/// re-running `config/create`, which re-runs the backend's post-config and
/// would start the sign-in over.
String suggestRemoteName(String type, Set<String> taken, {String? preferred}) {
  final base = _sanitizeName(preferred ?? _baseNames[type] ?? type);
  if (!taken.contains(base)) return base;
  for (var i = 2; i < 1000; i++) {
    final candidate = '$base-$i';
    if (!taken.contains(candidate)) return candidate;
  }
  return '$base-${DateTime.now().millisecondsSinceEpoch}';
}

/// Friendlier stems than the backend name, for the few where it matters.
const Map<String, String> _baseNames = <String, String>{
  'drive': 'gdrive',
  'google photos': 'gphotos',
  'google cloud storage': 'gcs',
  'iclouddrive': 'icloud',
  'azureblob': 'azure',
};

/// Keeps a suggestion to characters that are unambiguous both in a config file
/// and inside a `remote:path` string.
String _sanitizeName(String raw) {
  final cleaned = raw
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9-]+'), '-')
      .replaceAll(RegExp(r'-+'), '-')
      .replaceAll(RegExp(r'^-|-$'), '');
  return cleaned.isEmpty ? 'remote' : cleaned;
}

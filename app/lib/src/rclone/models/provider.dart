import 'package:flutter/foundation.dart';

/// A backend type from rclone's `config/providers` (e.g. `s3`, `drive`, `sftp`).
/// Named `RcloneProvider` to avoid clashing with Riverpod's `Provider`.
@immutable
class RcloneProvider {
  const RcloneProvider({
    required this.name,
    required this.description,
    required this.options,
  });

  final String name;
  final String description;
  final List<ProviderOption> options;

  /// Options shown by default (not hidden, not advanced).
  List<ProviderOption> get standardOptions =>
      options.where((o) => !o.hide && !o.advanced).toList();

  /// Advanced options (collapsed behind a disclosure).
  List<ProviderOption> get advancedOptions =>
      options.where((o) => !o.hide && o.advanced).toList();

  factory RcloneProvider.fromJson(Map<String, dynamic> json) {
    final opts = (json['Options'] as List? ?? const [])
        .cast<Map<String, dynamic>>()
        .map(ProviderOption.fromJson)
        .toList();
    return RcloneProvider(
      name: (json['Name'] ?? '') as String,
      description: (json['Description'] ?? '') as String,
      options: opts,
    );
  }
}

/// One configurable field of a provider (or an interactive config question).
@immutable
class ProviderOption {
  const ProviderOption({
    required this.name,
    this.help = '',
    this.type = 'string',
    this.defaultStr = '',
    this.examples = const [],
    this.required = false,
    this.isPassword = false,
    this.sensitive = false,
    this.advanced = false,
    this.hide = false,
    this.exclusive = false,
  });

  final String name;
  final String help;

  /// rclone option type: `string`, `int`, `bool`, `SizeSuffix`, `Duration`, …
  final String type;
  final String defaultStr;
  final List<OptionExample> examples;
  final bool required;
  final bool isPassword;
  final bool sensitive;
  final bool advanced;
  final bool hide;

  /// When true with [examples], the value must be one of the examples (a select).
  final bool exclusive;

  bool get isBool => type == 'bool';
  bool get isInt => type == 'int' || type == 'SizeSuffix' || type == 'Duration';
  bool get isSelect => examples.isNotEmpty;

  /// First line of [help] — used as the field label/hint.
  String get summary => help.split('\n').first.trim();

  factory ProviderOption.fromJson(Map<String, dynamic> json) {
    final examples = (json['Examples'] as List? ?? const [])
        .cast<Map<String, dynamic>>()
        .map(OptionExample.fromJson)
        .toList();
    return ProviderOption(
      name: (json['Name'] ?? '') as String,
      help: (json['Help'] ?? '') as String,
      type: (json['Type'] ?? 'string') as String,
      defaultStr:
          (json['DefaultStr'] ?? json['Default']?.toString() ?? '') as String,
      examples: examples,
      required: (json['Required'] ?? false) as bool,
      isPassword: (json['IsPassword'] ?? false) as bool,
      sensitive: (json['Sensitive'] ?? false) as bool,
      advanced: (json['Advanced'] ?? false) as bool,
      hide: ((json['Hide'] ?? 0) as num) != 0,
      exclusive: (json['Exclusive'] ?? false) as bool,
    );
  }
}

@immutable
class OptionExample {
  const OptionExample({required this.value, this.help = ''});
  final String value;
  final String help;

  factory OptionExample.fromJson(Map<String, dynamic> json) => OptionExample(
    value: (json['Value'] ?? '').toString(),
    help: (json['Help'] ?? '') as String,
  );
}

/// The underscore-prefixed parameters rclone's rc API accepts on any call.
///
/// They are not part of a method's own parameters — they change how the engine
/// RUNS the call — so they live here rather than being repeated on every typed
/// method. See https://rclone.org/rc/#special-parameters.
library;

import 'package:meta/meta.dart';

/// How a call should run, independent of what it does.
@immutable
class RcOptions {
  const RcOptions({this.async = false, this.group, this.config, this.filter});

  /// Run as a background job: the call returns a `jobid` immediately instead of
  /// waiting. Poll it with [RcApi.job].status, or watch the [group]'s stats.
  final bool async;

  /// Names a stats group, so this call's progress can be read back on its own
  /// rather than mixed into the engine's global counters.
  final String? group;

  /// Per-call overrides of rclone's global config (`_config`): transfers,
  /// checkers, bandwidth, and the rest of `rclone config` global flags.
  final Map<String, Object?>? config;

  /// Per-call filter rules (`_filter`): includes, excludes, min/max age.
  final Map<String, Object?>? filter;

  /// Whether this carries anything at all — so a caller can skip the merge.
  bool get isEmpty =>
      !async && group == null && config == null && filter == null;

  /// Merges these onto [params].
  ///
  /// Deliberately LAST in the merge order used by every typed method, because
  /// `_async` decides whether the caller gets a result or a job id, and a
  /// method's own parameters must not be able to flip that by accident.
  Map<String, dynamic> apply(Map<String, dynamic> params) => <String, dynamic>{
    ...params,
    if (async) '_async': true,
    if (group != null) '_group': group,
    if (config != null) '_config': config,
    if (filter != null) '_filter': filter,
  };

  static const RcOptions none = RcOptions();
}

/// What an `_async` call returns: the id to ask about later.
@immutable
class AsyncJob {
  const AsyncJob(this.id);

  /// rclone's `jobid`.
  final int id;

  @override
  String toString() => 'AsyncJob($id)';

  @override
  bool operator ==(Object other) => other is AsyncJob && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

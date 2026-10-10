/// "Sign in again": which remotes can do it, and which failures call for it.
///
/// A remote's OAuth token can stop working long after the remote was added —
/// revoked by the user, expired by the provider, or retired with the client_id
/// that issued it. rclone's own answer is `rclone config reconnect`; Airclone's
/// is the "Sign in again" action, driven by `AddRemoteController.startReconnect`.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:airclone_rc/airclone_rc.dart';
import 'providers_provider.dart';

/// The `config_*` answer that makes rclone replace an existing token rather
/// than ask "Token already configured - replace it?". Ephemeral (the `config_`
/// prefix), so rclone never writes it to the config.
const kRefreshTokenAnswer = 'config_refresh_token';

/// Whether rclone runs an OAuth sign-in for this backend.
///
/// Detected from the backend's own options — every OAuth backend carries a
/// `token` — rather than from a list of provider names we would have to keep
/// in step with rclone.
bool providerUsesSignIn(RcloneProvider? p) =>
    p != null && p.options.any((o) => o.name == 'token');

/// Whether a remote of backend [type] can "Sign in again".
///
/// False while the provider list is still loading, so the action appears once
/// it is known to apply rather than being offered and then refused.
final remoteUsesSignInProvider = Provider.family<bool, String>((ref, type) {
  final list = ref.watch(providersProvider).valueOrNull;
  if (list == null) return false;
  for (final p in list) {
    if (p.name == type) return providerUsesSignIn(p);
  }
  return false;
});

/// Phrases rclone and the OAuth providers use when a token no longer works.
///
/// Matched case-insensitively against an error already shown to the user. Only
/// ever consulted for a remote that uses a sign-in, which is what makes a broad
/// entry like `401` safe: on an OAuth backend that is the token talking.
const _expiredSignInPhrases = [
  'invalid_grant',
  'cannot fetch token',
  "couldn't fetch token",
  'failed to refresh token',
  'token expired',
  'expired or revoked',
  'empty token found',
  'config reconnect',
  'invalid_token',
  'invalidauthenticationtoken',
  'unauthenticated',
  'unauthorized',
  '401',
];

/// True when [message] reads like a sign-in that has stopped working.
bool looksLikeExpiredSignIn(String? message) {
  if (message == null || message.isEmpty) return false;
  final m = message.toLowerCase();
  return _expiredSignInPhrases.any(m.contains);
}

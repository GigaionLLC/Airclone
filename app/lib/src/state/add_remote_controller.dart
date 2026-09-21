import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:airclone_rc/airclone_rc.dart';
import '../rclone/models/remote.dart';
import '../ui/connection_test_dialog.dart' show testRemoteConnection;
import 'diagnostics.dart';
import 'engine_controller.dart';
import 'providers_provider.dart';
import 'remote_setup_recipes.dart';
import 'remotes_provider.dart';

/// Where the add-a-cloud flow currently is.
enum AddPhase {
  /// Choosing what to connect.
  pickProvider,

  /// Our screen: a name plus whatever that backend actually needs.
  setup,

  /// A config call is in flight and has told us nothing yet.
  busy,

  /// rclone asked something we are putting to the user.
  question,

  /// A sign-in is waiting on the person, at [AddRemoteState.authUrl].
  signingIn,

  /// Created; checking it can actually be reached.
  verifying,

  /// Finished, with [AddRemoteState.successSummary].
  done,

  /// Stopped, with [AddRemoteState.error].
  error,
}

/// Guided is the default; advanced is every option, as it has always been.
enum AddMode { guided, advanced }

/// How the person wants to complete an OAuth sign-in.
///
/// Each maps onto an answer rclone already understands (plan §2.1.12, Phase C);
/// none of them is a parallel implementation of anything.
enum SignInMethod {
  /// Sign in here. We open the link ourselves.
  thisDevice,

  /// Show the link so it can be carried to a browser that can reach this
  /// machine — another window, or an SSH tunnel to this port.
  showLink,

  /// Do the sign-in on a machine that has rclone, and paste the token back.
  otherDevice,
}

@immutable
class AddRemoteState {
  const AddRemoteState({
    this.phase = AddPhase.pickProvider,
    this.mode = AddMode.guided,
    this.provider,
    this.choice,
    this.name = '',
    this.values = const {},
    this.sticky = const {},
    this.showAdvanced = false,
    this.optionFilter = '',
    this.isEdit = false,
    this.editName,
    this.question,
    this.questionState,
    this.signInMethod = SignInMethod.thisDevice,
    this.authUrl,
    this.authUrlUnavailable = false,
    this.signInSlow = false,
    this.createdName,
    this.successSummary,
    this.verifyFailed = false,
    this.error,
  });

  final AddPhase phase;
  final AddMode mode;

  /// The rclone backend being configured.
  final RcloneProvider? provider;

  /// The curated tile it was reached through, when there was one. Carries the
  /// friendly name and any `provider` preset.
  final CloudChoice? choice;

  final String name;

  /// Option name -> raw string value.
  final Map<String, String> values;

  /// Ephemeral `config_*` answers that must ride along on EVERY call.
  ///
  /// rclone never persists these (`fs.ConfigKeyEphemeralPrefix`) and rebuilds
  /// its answer map from `parameters` each time, so an answer sent only on the
  /// opening call is forgotten by the next one and the question comes back.
  /// Plan §2.1.5.
  final Map<String, String> sticky;

  final bool showAdvanced;

  /// Narrows the advanced option list. s3 has 78 options; finding `endpoint`
  /// by scrolling is the current reality.
  final String optionFilter;

  /// True when editing an existing remote (config/update) vs. creating one.
  final bool isEdit;

  /// The remote being edited (its name is immutable in edit mode).
  final String? editName;

  /// The current interactive question, if any.
  final ProviderOption? question;

  /// rclone `State` token to continue the flow.
  final String? questionState;

  final SignInMethod signInMethod;

  /// The sign-in link, once rclone is waiting on one.
  final Uri? authUrl;

  /// We know a sign-in is waiting but could not learn its link — an old engine
  /// whose log we could not read. The other ways still work.
  final bool authUrlUnavailable;

  /// Set after ~45 s of waiting, to offer another way without cancelling.
  final bool signInSlow;

  /// The config section a cancel would have to clean up. Null while editing:
  /// cancelling an edit must never delete the remote being edited.
  final String? createdName;

  final String? successSummary;

  /// The remote was created but could not be reached.
  final bool verifyFailed;

  final String? error;

  /// The friendly name if we have one, else rclone's backend name.
  String get providerLabel =>
      choice?.label ?? provider?.name ?? provider?.description ?? '';

  /// The value of the `provider` option, which gates which other options apply.
  String get providerValue => values['provider'] ?? '';

  /// Fields shown on the guided setup screen, or empty when rclone drives this
  /// backend itself (an OAuth one, typically).
  List<RecipeField> get recipeFields =>
      recipeFor(provider?.name ?? '')?.fields ?? const [];

  /// Transient fields — [question], [questionState], [authUrl], [error] and
  /// [successSummary] — are REPLACED, not merged, so a caller that does not
  /// mention them clears them. That is deliberate: a stale question surviving
  /// into the next step is how this flow used to show the wrong screen.
  AddRemoteState copyWith({
    AddPhase? phase,
    AddMode? mode,
    RcloneProvider? provider,
    CloudChoice? choice,
    String? name,
    Map<String, String>? values,
    Map<String, String>? sticky,
    bool? showAdvanced,
    String? optionFilter,
    bool? isEdit,
    String? editName,
    ProviderOption? question,
    String? questionState,
    SignInMethod? signInMethod,
    Uri? authUrl,
    bool? authUrlUnavailable,
    bool? signInSlow,
    String? createdName,

    /// Clears [createdName]. A plain `createdName: null` cannot: the field is
    /// merged with `??`, so passing null KEEPS the old value — and a stale one
    /// means a finished remote still looks like something a cancel should
    /// delete.
    bool clearCreatedName = false,
    String? successSummary,
    bool? verifyFailed,
    String? error,
  }) => AddRemoteState(
    phase: phase ?? this.phase,
    mode: mode ?? this.mode,
    provider: provider ?? this.provider,
    choice: choice ?? this.choice,
    name: name ?? this.name,
    values: values ?? this.values,
    sticky: sticky ?? this.sticky,
    showAdvanced: showAdvanced ?? this.showAdvanced,
    optionFilter: optionFilter ?? this.optionFilter,
    isEdit: isEdit ?? this.isEdit,
    editName: editName ?? this.editName,
    question: question,
    questionState: questionState,
    signInMethod: signInMethod ?? this.signInMethod,
    authUrl: authUrl,
    authUrlUnavailable: authUrlUnavailable ?? this.authUrlUnavailable,
    signInSlow: signInSlow ?? this.signInSlow,
    createdName: clearCreatedName ? null : (createdName ?? this.createdName),
    successSummary: successSummary,
    verifyFailed: verifyFailed ?? this.verifyFailed,
    error: error,
  );
}

/// Opens a URL outside the app.
///
/// Injected so tests can watch what would have been opened without a plugin,
/// and so there is exactly one place that decides HOW a sign-in link opens.
typedef UrlOpener = Future<bool> Function(Uri url);

/// **Never an embedded WebView.** Google refuses OAuth from one, and the others
/// are heading the same way. `inAppBrowserView` is a Custom Tab on Android and
/// an `SFSafariViewController` on iOS — real browsers, with the user's existing
/// session and a visible address bar. Desktop hands off to the system browser.
final urlOpenerProvider = Provider<UrlOpener>((ref) {
  return (Uri url) => launchUrl(
    url,
    mode: (Platform.isAndroid || Platform.isIOS)
        ? LaunchMode.inAppBrowserView
        : LaunchMode.externalApplication,
  );
});

/// Drives rclone's own interactive config state machine — the same one
/// `rclone config` drives — for both the guided flow and the advanced form.
///
/// The two are one driver with two front ends. What differs is only which
/// `parameters` the opening call carries and which questions we answer on the
/// user's behalf; everything after that is rclone deciding what to ask next.
class AddRemoteController extends Notifier<AddRemoteState> {
  Timer? _nudgeTimer;
  StreamSubscription<Uri>? _authSub;

  /// Whether this engine has `config/oauthstatus` (rclone 1.75+). Learned by
  /// calling it, not by comparing version strings: a version says what rclone
  /// claims to be, a call says what it has. Plan §2.4.
  bool _oauthStatusSupported = true;

  /// Which attempt is current.
  ///
  /// Every config call takes a number on the way in and checks it again on the
  /// way out; a cancel or a retry bumps it. An attempt whose number is no
  /// longer current simply stops, which is what stops a torn-down job from
  /// reporting "Sign-in was cancelled" over the screen the user has already
  /// moved on to — and what lets Retry start a new attempt while the old one
  /// is still unwinding.
  int _generation = 0;

  bool _disposed = false;

  @override
  AddRemoteState build() {
    ref.onDispose(() {
      _disposed = true;
      _nudgeTimer?.cancel();
      _authSub?.cancel();
    });
    return const AddRemoteState();
  }

  // --- picking ---------------------------------------------------------------

  void reset() {
    _stopWaiting();
    state = const AddRemoteState();
  }

  void backToProviders() {
    _stopWaiting();
    state = const AddRemoteState();
  }

  /// Guided entry: a curated tile (or a search hit) was chosen.
  Future<void> pickCloud(CloudChoice choice) async {
    final provider = await _providerNamed(choice.type);
    if (provider == null) return;
    _beginSetup(provider, AddMode.guided, choice: choice);
  }

  /// Advanced entry: a raw rclone backend was chosen from the full list.
  void pickProvider(RcloneProvider p) => _beginSetup(p, AddMode.advanced);

  /// Guided entry for a backend with no curated tile.
  void pickProviderGuided(RcloneProvider p) => _beginSetup(p, AddMode.guided);

  /// Moves the current attempt to the advanced form, carrying values over.
  ///
  /// Reachable from the tile, from the guided step header, and automatically
  /// from a failure — all three land here, so values are never retyped.
  void switchToAdvanced() {
    _stopWaiting();
    state = state.copyWith(
      phase: AddPhase.setup,
      mode: AddMode.advanced,
      error: null,
      question: null,
      questionState: null,
      authUrl: null,
    );
  }

  void _beginSetup(RcloneProvider p, AddMode mode, {CloudChoice? choice}) {
    final values = <String, String>{
      for (final o in p.options)
        if (o.defaultStr.isNotEmpty) o.name: o.defaultStr,
      ...?choice?.preset,
    };
    state = AddRemoteState(
      phase: AddPhase.setup,
      mode: mode,
      provider: p,
      choice: choice,
      values: values,
      name: suggestRemoteName(p.name, _takenNames()),
    );
  }

  Future<RcloneProvider?> _providerNamed(String type) async {
    try {
      final list = await ref.read(providersProvider.future);
      for (final p in list) {
        if (p.name == type) return p;
      }
      state = AddRemoteState(
        phase: AddPhase.error,
        error:
            'This build of rclone does not offer "$type". Update the engine, '
            'or add it from Advanced.',
      );
      return null;
    } catch (e) {
      state = AddRemoteState(
        phase: AddPhase.error,
        error: redactSensitive('$e'),
      );
      return null;
    }
  }

  Set<String> _takenNames() {
    final remotes = ref.read(remotesProvider).valueOrNull ?? const <Remote>[];
    return {for (final r in remotes) r.name};
  }

  // --- editing the form ------------------------------------------------------

  void setName(String s) => state = state.copyWith(
    name: s,
    question: state.question,
    questionState: state.questionState,
    error: state.error,
  );

  void setValue(String option, String value) {
    final next = Map<String, String>.from(state.values)..[option] = value;
    state = state.copyWith(
      values: next,
      question: state.question,
      questionState: state.questionState,
      error: state.error,
    );
  }

  void setOptionFilter(String s) => state = state.copyWith(
    optionFilter: s,
    question: state.question,
    questionState: state.questionState,
    error: state.error,
  );

  void toggleAdvanced() => state = state.copyWith(
    showAdvanced: !state.showAdvanced,
    question: state.question,
    questionState: state.questionState,
    error: state.error,
  );

  // --- creating --------------------------------------------------------------

  /// Starts a guided sign-in with the chosen method, then creates.
  Future<void> signIn(SignInMethod method) async {
    final sticky = <String, String>{...state.sticky};
    switch (method) {
      case SignInMethod.thisDevice:
      case SignInMethod.showLink:
        // rclone must NOT open a browser itself: we have the link either way
        // (plan §2.4) and opening it ourselves is one code path on every
        // platform, with the link on screen whatever happens.
        sticky['config_is_local'] = 'true';
        sticky['config_auth_no_browser'] = 'true';
      case SignInMethod.otherDevice:
        // rclone answers with the `rclone authorize` command to run elsewhere,
        // and then waits for the token to be pasted back.
        sticky['config_is_local'] = 'false';
    }
    assert(
      sticky.keys.every(_isEphemeral),
      'sticky answers are re-sent without obscure and must be ephemeral: '
      '${sticky.keys.where((k) => !_isEphemeral(k))}',
    );
    state = state.copyWith(
      sticky: sticky,
      signInMethod: method,
      question: null,
      questionState: null,
      error: null,
    );
    await submit();
  }

  Future<void> submit() async {
    final p = state.provider;
    if (p == null) return;
    final wanted = state.name.trim();
    if (wanted.isEmpty) {
      _fail('Enter a name for this cloud.', phase: AddPhase.setup);
      return;
    }
    final client = ref.read(engineControllerProvider).client;
    if (client == null) {
      _fail('Engine not ready', phase: AddPhase.setup);
      return;
    }
    // Refuse a name that is already taken. config/create would REPLACE that
    // remote silently — see existingRemoteNames. Editing an existing remote is
    // a separate, explicit action (isEdit -> config/update).
    final taken = await existingRemoteNames(client);
    if (taken == null) {
      _fail(
        "Couldn't read the existing remotes, so nothing was created. "
        'Check the engine and try again.',
        phase: AddPhase.setup,
      );
      return;
    }
    // A stub this flow wrote under a DIFFERENT name is now orphaned: the user
    // reached the failure screen, chose "enter the details myself", and typed
    // a new name. Nothing else will ever clean it up, because cancel only
    // knows about the current one.
    final orphan = state.createdName;
    if (!state.isEdit && orphan != null && orphan != wanted) {
      await _deleteRemote(client, orphan);
    }
    if (taken.contains(wanted)) {
      // ...unless it is the stub THIS attempt wrote a moment ago. rclone
      // creates the section as soon as a call returns at a question, so a
      // failed or abandoned attempt leaves one behind — and without this,
      // Retry and "enter the details myself" would both be refused by the
      // guard protecting against overwriting somebody else's remote.
      if (state.createdName == wanted) {
        await _deleteRemote(client, wanted);
      } else {
        _fail(
          'A cloud called "$wanted" already exists. Choose another name, or '
          'edit that one instead — creating over it would replace its '
          'settings.',
          phase: AddPhase.setup,
        );
        return;
      }
    }
    state = state.copyWith(
      phase: AddPhase.busy,
      createdName: wanted,
      error: null,
      question: null,
      questionState: null,
      authUrl: null,
      authUrlUnavailable: false,
      signInSlow: false,
    );
    await _call(
      method: 'config/create',
      body: {
        'name': wanted,
        'type': p.name,
        'parameters': _parameters(),
        // No `all`. With it rclone walks EVERY option one question at a time,
        // and since only non-empty values are pre-answered, every field left
        // blank came straight back as a question — which is what made adding a
        // remote feel like an interrogation. Plan §2.1.6.
        'opt': {'nonInteractive': true, 'obscure': true},
      },
    );
  }

  /// The values to send: what the user filled in, plus the sticky ephemeral
  /// answers that rclone forgets between calls.
  Map<String, dynamic> _parameters() => <String, dynamic>{
    for (final e in state.values.entries)
      if (e.value.isNotEmpty) e.key: e.value,
    ...state.sticky,
  };

  /// Every sticky key must be one rclone treats as ephemeral.
  ///
  /// **This is a secret-handling rule, not tidiness.** Sticky values are
  /// re-sent on every `continue`, and a continue carries no `opt.obscure` — so
  /// a secret placed here would be written to the config in the clear, and a
  /// key without the `config_` prefix would be PERSISTED rather than stripped.
  /// The two keys used today are both ephemeral; this stops the third from
  /// quietly not being.
  static bool _isEphemeral(String key) => key.startsWith('config_');

  /// Answer the current interactive [question] and continue the flow. Routes to
  /// config/update during an edit (never config/create, which would recreate).
  Future<void> answer(String result) async {
    final p = state.provider;
    final st = state.questionState;
    if (p == null || st == null) return;
    state = state.copyWith(
      phase: AddPhase.busy,
      error: null,
      question: null,
      questionState: null,
      authUrl: state.authUrl,
    );
    await _call(
      method: state.isEdit ? 'config/update' : 'config/create',
      body: {
        'name': state.isEdit ? state.editName! : state.name.trim(),
        if (!state.isEdit) 'type': p.name,
        // REQUIRED even on a `continue` step: rclone's rc argument parser
        // rejects config/create and config/update with HTTP 400 "Didn't find
        // key \"parameters\" in input" when it is absent, so every answer to an
        // interactive question used to fail.
        //
        // It carries the STICKY ephemeral answers only — never the form values.
        // Those are already persisted, and re-sending them here (without
        // `obscure`) would write any password back in the clear.
        'parameters': <String, dynamic>{...state.sticky},
        'opt': {
          'nonInteractive': true,
          'continue': true,
          'state': st,
          'result': result,
        },
      },
    );
  }

  // --- the call itself -------------------------------------------------------

  Future<void> _call({
    required String method,
    required Map<String, dynamic> body,
  }) async {
    final client = ref.read(engineControllerProvider).client;
    if (client == null) {
      _fail('Engine not ready');
      return;
    }
    final gen = ++_generation;
    _watchAuthUrls(client, gen);
    try {
      final res = await _runJob(client, method, body, gen);
      // A cancel or a retry that landed while this was in flight owns the
      // outcome. The job reports its own end a moment later ("oauth
      // authentication was cancelled"), and handling it here would paint an
      // error over the screen the user has already moved on to.
      if (_disposed || gen != _generation) return;
      final nextState = res['State'] as String?;
      final option = res['Option'] as Map<String, dynamic>?;
      final err = (res['Error'] as String?) ?? '';
      if (err.isNotEmpty) {
        _fail(_explain(err));
        return;
      }
      if (nextState != null && nextState.isNotEmpty && option != null) {
        _stopWaiting();
        state = state.copyWith(
          phase: AddPhase.question,
          question: ProviderOption.fromJson(option),
          questionState: nextState,
          authUrl: null,
        );
        return;
      }
      await _finish();
    } on RcloneException catch (e) {
      if (!_disposed && gen == _generation) _fail(_explain(e.message));
    } catch (e) {
      if (!_disposed && gen == _generation) _fail('$e');
    } finally {
      _authSub?.cancel();
      _authSub = null;
    }
  }

  /// Runs a config call as an async job and polls it, watching for a sign-in
  /// along the way.
  ///
  /// **`_async` is not an optimisation here.** `config/create` blocks for as
  /// long as an OAuth sign-in takes, and the in-process engine serialises every
  /// RPC through one worker isolate — so a blocking create freezes every other
  /// call the app makes, app-wide, until the user finishes signing in. Plan
  /// §2.1.14.
  Future<Map<String, dynamic>> _runJob(
    RcloneClient client,
    String method,
    Map<String, dynamic> body,
    int gen,
  ) async {
    final started = await client.rpc(method, {...body, '_async': true});
    final jobId = (started['jobid'] as num?)?.toInt();
    // An engine that ran it inline answered with the result itself.
    if (jobId == null) return started;

    final urlDeadline = DateTime.now().add(const Duration(seconds: 10));
    while (!_disposed && gen == _generation) {
      final status = await client.rpc('job/status', {'jobid': jobId});
      if (status['finished'] == true) {
        final err = (status['error'] as String?) ?? '';
        if (err.isNotEmpty) throw RcloneException(method, err);
        final out = status['output'];
        return out is Map<String, dynamic> ? out : <String, dynamic>{};
      }
      await _pollForSignIn(client, urlDeadline);
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    return const <String, dynamic>{};
  }

  /// Looks for a sign-in waiting on the user, by whichever route this engine
  /// supports.
  Future<void> _pollForSignIn(RcloneClient client, DateTime urlDeadline) async {
    if (state.authUrl != null) return;
    if (_oauthStatusSupported) {
      final res = await fetchAuthUrl(client);
      _oauthStatusSupported = res.supported;
      final url = res.url;
      if (url != null) {
        _enterSignIn(url);
        return;
      }
      if (res.supported) return; // nothing waiting yet
    }
    // Older engines: the link only ever appeared in the log, which the rcd
    // client watches for us. If nothing has arrived by the deadline the job is
    // blocked on something we cannot see — say so rather than spin forever on
    // a spinner that will never move.
    if (!state.authUrlUnavailable && DateTime.now().isAfter(urlDeadline)) {
      _stopWaiting();
      _nudgeAfter45s();
      state = state.copyWith(
        phase: AddPhase.signingIn,
        authUrl: null,
        authUrlUnavailable: true,
        question: null,
        questionState: null,
      );
      logDiagnostic(
        DiagLevel.warning,
        'add-remote',
        'A sign-in is waiting but this engine did not report its link '
            '(rclone older than 1.75, or started with -q).',
      );
    }
  }

  void _watchAuthUrls(RcloneClient client, int gen) {
    _authSub?.cancel();
    _authSub = null;
    if (client is! AuthUrlObserver) return;
    final observer = client as AuthUrlObserver;
    // Subscribed BEFORE the call, because the stream is broadcast: a link
    // logged while nothing is listening is simply gone.
    _authSub = observer.authUrls.listen((uri) {
      if (_disposed || gen != _generation) return;
      if (state.phase == AddPhase.busy || state.phase == AddPhase.signingIn) {
        _enterSignIn(uri);
      }
    });
  }

  void _enterSignIn(Uri url) {
    if (state.authUrl == url) return;
    _nudgeAfter45s();
    state = state.copyWith(
      phase: AddPhase.signingIn,
      authUrl: url,
      authUrlUnavailable: false,
      question: null,
      questionState: null,
      error: null,
    );
    if (state.signInMethod == SignInMethod.thisDevice) {
      unawaited(_open(url));
    }
  }

  /// Opens the sign-in link, and reports rather than swallows a failure —
  /// the link is on screen to copy either way.
  Future<void> _open(Uri url) async {
    try {
      final ok = await ref.read(urlOpenerProvider)(url);
      if (!ok) {
        logDiagnostic(
          DiagLevel.warning,
          'add-remote',
          'No browser could be opened for the sign-in link.',
        );
      }
    } catch (e) {
      logDiagnostic(
        DiagLevel.warning,
        'add-remote',
        'Opening the sign-in link failed.',
        detail: e,
      );
    }
  }

  /// Re-opens the sign-in link on request (the "Open it again" action).
  Future<void> openAuthUrl() async {
    final url = state.authUrl;
    if (url != null) await _open(url);
  }

  void _nudgeAfter45s() {
    _nudgeTimer?.cancel();
    _nudgeTimer = Timer(const Duration(seconds: 45), () {
      if (_disposed || state.phase != AddPhase.signingIn) return;
      state = state.copyWith(
        signInSlow: true,
        question: state.question,
        questionState: state.questionState,
        authUrl: state.authUrl,
      );
    });
  }

  void _stopWaiting() {
    _nudgeTimer?.cancel();
    _nudgeTimer = null;
  }

  // --- cancelling ------------------------------------------------------------

  /// Ends a sign-in in progress and cleans up after it.
  ///
  /// Two things have to happen and neither is optional: the blocked flow has to
  /// be released — it holds port 53682, so a second attempt would fail to bind
  /// — and, for a CREATE, the half-written config section has to go. rclone
  /// writes `[name] type = …` as soon as a call returns at a question, so an
  /// abandoned sign-in can leave behind a remote that exists and cannot
  /// connect to anything (plan §2.1.9).
  ///
  /// Cancelling an EDIT deletes nothing, ever.
  Future<void> cancelSignIn() async {
    // Retires whatever is in flight before anything else happens.
    _generation++;
    _stopWaiting();
    final client = ref.read(engineControllerProvider).client;
    if (client == null) return;
    final stopped = await cancelOAuth(client);
    final created = state.createdName;
    String? cleanupError;
    if (!state.isEdit && created != null) {
      cleanupError = await _deleteRemote(client, created);
    }
    ref.invalidate(remotesProvider);
    if (_disposed) return;
    if (!stopped) {
      logDiagnostic(
        DiagLevel.warning,
        'add-remote',
        'The sign-in could not be cancelled cleanly; port $kOAuthPort may '
            'still be held.',
      );
    }
    state = state.copyWith(
      phase: cleanupError == null ? AddPhase.pickProvider : AddPhase.error,
      error: cleanupError,
      question: null,
      questionState: null,
      authUrl: null,
      clearCreatedName: true,
    );
  }

  /// Deletes a half-created remote, returning a message if it survived.
  ///
  /// **The status code cannot be trusted here.** `config/delete` calls rclone's
  /// `DeleteRemote`, which is `void`: deleting a section that does not exist is
  /// a silent no-op, and `SaveConfig()` swallows its own error after retrying,
  /// logging `Failed to save config after N tries` and returning nothing. So
  /// the call answers 200 whether it deleted the remote, deleted nothing, or
  /// failed to write the file — and the only way to know is to look. Plan §2.3.
  Future<String?> _deleteRemote(RcloneClient client, String name) async {
    try {
      await client.rpc('config/delete', {'name': name});
    } on RcloneException catch (e) {
      return 'The half-finished cloud "$name" could not be removed: '
          '${e.message}';
    }
    final names = await existingRemoteNames(client);
    if (names != null && names.contains(name)) {
      return 'The half-finished cloud "$name" is still in your config and '
          'will not connect. Remove it from the remotes list.';
    }
    return null;
  }

  /// Cancels whatever is holding the port, then starts over — the action
  /// offered when a bind failure says something else already has it.
  Future<void> retryAfterCancel() async {
    _generation++;
    final client = ref.read(engineControllerProvider).client;
    if (client != null) await cancelOAuth(client);
    if (_disposed) return;
    // submit() removes the stub this flow left behind before recreating it.
    await submit();
  }

  // --- finishing -------------------------------------------------------------

  /// The remote exists. Prove it can be reached before calling it a success.
  Future<void> _finish() async {
    ref.invalidate(remotesProvider);
    final p = state.provider;
    final name = state.isEdit ? state.editName : state.name.trim();
    if (p == null || name == null || name.isEmpty) {
      state = state.copyWith(phase: AddPhase.done, clearCreatedName: true);
      return;
    }
    _stopWaiting();
    state = state.copyWith(
      phase: AddPhase.verifying,
      question: null,
      questionState: null,
      authUrl: null,
    );
    final client = ref.read(engineControllerProvider).client;
    if (client == null) {
      state = state.copyWith(phase: AddPhase.done, clearCreatedName: true);
      return;
    }
    final result = await testRemoteConnection(
      client,
      Remote(name: name, type: p.name, fs: '$name:'),
    );
    if (_disposed) return;
    if (!result.ok) {
      logDiagnostic(
        DiagLevel.warning,
        'add-remote',
        'Created "$name" but could not reach it.',
        detail: result.message,
      );
    }
    state = state.copyWith(
      phase: AddPhase.done,
      verifyFailed: !result.ok,
      // Redacted before it is painted. This is rclone's own error text and it
      // can quote the URL it failed on — which is how a live credential ends
      // up on a screen, and a screenshot is a publishing channel.
      successSummary: redactSensitive(result.message),
      clearCreatedName: true,
      question: null,
      questionState: null,
      authUrl: null,
    );
  }

  /// Keeps a remote that was created but did not answer — the user may know
  /// something we do not (a server that is down right now, say).
  void keepUnverified() => state = state.copyWith(
    phase: AddPhase.done,
    verifyFailed: false,
    successSummary: state.successSummary,
    question: null,
    questionState: null,
    authUrl: null,
  );

  // --- editing an existing remote -------------------------------------------

  /// Loads an existing remote into the form for editing. Non-password fields are
  /// prefilled; password fields are left BLANK ("leave blank to keep current").
  Future<void> startEdit(Remote remote) async {
    state = const AddRemoteState(phase: AddPhase.busy, mode: AddMode.advanced);
    try {
      final providers = await ref.read(providersProvider.future);
      RcloneProvider? p;
      for (final x in providers) {
        if (x.name == remote.type) {
          p = x;
          break;
        }
      }
      if (p == null) {
        state = AddRemoteState(
          phase: AddPhase.error,
          error: "This remote's type (${remote.type}) can't be edited here.",
        );
        return;
      }
      final client = ref.read(engineControllerProvider).client;
      if (client == null) {
        state = const AddRemoteState(
          phase: AddPhase.error,
          error: 'Engine not ready',
        );
        return;
      }
      final cfg = await RcApi(client).config.get(remote.name);
      final pwKeys = {
        for (final o in p.options)
          if (o.isPassword) o.name,
      };
      final values = <String, String>{};
      cfg.forEach((k, v) {
        if (k == 'type') return;
        // Never surface an obscured password token; blank => keep current.
        values[k] = pwKeys.contains(k) ? '' : (v?.toString() ?? '');
      });
      state = AddRemoteState(
        phase: AddPhase.setup,
        mode: AddMode.advanced,
        provider: p,
        choice: cloudChoiceFor(p.name, values: values),
        name: remote.name,
        isEdit: true,
        editName: remote.name,
        values: values,
      );
    } on RcloneException catch (e) {
      // Redacted for the same reason _fail redacts: the ring sanitises at
      // ingest, a screen does not, and rclone quotes what it failed on.
      state = AddRemoteState(
        phase: AddPhase.error,
        error: redactSensitive(e.message),
      );
    } catch (e) {
      state = AddRemoteState(
        phase: AddPhase.error,
        error: redactSensitive('$e'),
      );
    }
  }

  /// Saves edits via config/update (MERGE: omitted keys keep their value, so a
  /// blank password is preserved). Only typed (plaintext) passwords are sent,
  /// with obscure:true — so an existing obscured value is never double-obscured.
  Future<void> submitEdit() async {
    final editName = state.editName;
    if (editName == null) return;
    state = state.copyWith(
      phase: AddPhase.busy,
      error: null,
      question: null,
      questionState: null,
    );
    await _call(
      method: 'config/update',
      body: {
        'name': editName,
        'parameters': _parameters(),
        'opt': {'nonInteractive': true, 'obscure': true},
      },
    );
  }

  // --- failures --------------------------------------------------------------

  void _fail(String message, {AddPhase phase = AddPhase.error}) {
    _stopWaiting();
    state = state.copyWith(
      phase: phase,
      // rclone quotes what it failed on, which can include a URL carrying a
      // credential. Redaction happens at ingest for diagnostics; the screen
      // needs the same treatment, for the same reason.
      error: redactSensitive(message),
      question: null,
      questionState: null,
      authUrl: null,
    );
  }

  /// Turns rclone's wording into something a person can act on, leaving the
  /// original visible when we have nothing better to say.
  String _explain(String raw) {
    if (raw.contains('oauth authentication was cancelled') ||
        raw.contains('No code returned by remote server')) {
      return 'Sign-in was cancelled.';
    }
    if (raw.contains('failed to start auth webserver') ||
        raw.contains('address already in use') ||
        raw.contains('Only one usage of each socket address')) {
      return 'Port $kOAuthPort is already in use, which is where the sign-in '
          'has to come back to. Another rclone — or an abandoned sign-in — is '
          'holding it. Try again to take it back.';
    }
    return raw;
  }
}

final addRemoteControllerProvider =
    NotifierProvider<AddRemoteController, AddRemoteState>(
      AddRemoteController.new,
    );

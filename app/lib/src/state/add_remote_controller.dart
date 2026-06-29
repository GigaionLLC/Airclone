import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../rclone/models/provider.dart';
import '../rclone/rclone_client.dart';
import 'engine_controller.dart';
import 'remotes_provider.dart';

enum AddPhase { pickProvider, form, question, creating, done, error }

@immutable
class AddRemoteState {
  const AddRemoteState({
    this.phase = AddPhase.pickProvider,
    this.provider,
    this.name = '',
    this.values = const {},
    this.showAdvanced = false,
    this.question,
    this.questionState,
    this.error,
  });

  final AddPhase phase;
  final RcloneProvider? provider;
  final String name;
  final Map<String, String> values; // option name -> raw string value
  final bool showAdvanced;

  /// The current interactive question (e.g. OAuth / team-drive picker), if any.
  final ProviderOption? question;
  final String? questionState; // rclone `State` token to continue the flow
  final String? error;

  AddRemoteState copyWith({
    AddPhase? phase,
    RcloneProvider? provider,
    String? name,
    Map<String, String>? values,
    bool? showAdvanced,
    ProviderOption? question,
    String? questionState,
    String? error,
  }) => AddRemoteState(
    phase: phase ?? this.phase,
    provider: provider ?? this.provider,
    name: name ?? this.name,
    values: values ?? this.values,
    showAdvanced: showAdvanced ?? this.showAdvanced,
    question: question,
    questionState: questionState,
    error: error,
  );
}

/// Drives the add-remote wizard: pick a provider → fill the dynamic form → run the
/// interactive `config/create` loop (which also covers OAuth / team-drive questions).
class AddRemoteController extends Notifier<AddRemoteState> {
  @override
  AddRemoteState build() => const AddRemoteState();

  void reset() => state = const AddRemoteState();

  void pickProvider(RcloneProvider p) {
    final defaults = <String, String>{
      for (final o in p.options)
        if (o.defaultStr.isNotEmpty) o.name: o.defaultStr,
    };
    state = AddRemoteState(phase: AddPhase.form, provider: p, values: defaults);
  }

  void setName(String s) => state = state.copyWith(name: s);

  void setValue(String option, String value) {
    final next = Map<String, String>.from(state.values)..[option] = value;
    state = state.copyWith(values: next);
  }

  void toggleAdvanced() =>
      state = state.copyWith(showAdvanced: !state.showAdvanced);

  void backToProviders() => state = const AddRemoteState();

  Future<void> submit() async {
    final p = state.provider;
    if (p == null) return;
    if (state.name.trim().isEmpty) {
      state = state.copyWith(
        phase: AddPhase.form,
        error: 'Enter a name for this remote',
      );
      return;
    }
    state = state.copyWith(phase: AddPhase.creating, error: null);
    final params = <String, dynamic>{
      for (final entry in state.values.entries)
        if (entry.value.isNotEmpty) entry.key: entry.value,
    };
    await _call(
      method: 'config/create',
      body: {
        'name': state.name.trim(),
        'type': p.name,
        'parameters': params,
        'opt': {'nonInteractive': true, 'obscure': true, 'all': true},
      },
    );
  }

  /// Answer the current interactive [question] and continue the flow.
  Future<void> answer(String result) async {
    final p = state.provider;
    final st = state.questionState;
    if (p == null || st == null) return;
    state = state.copyWith(phase: AddPhase.creating, error: null);
    await _call(
      method: 'config/create',
      body: {
        'name': state.name.trim(),
        'type': p.name,
        'opt': {
          'nonInteractive': true,
          'continue': true,
          'state': st,
          'result': result,
        },
      },
    );
  }

  Future<void> _call({
    required String method,
    required Map<String, dynamic> body,
  }) async {
    final client = ref.read(engineControllerProvider).client;
    if (client == null) {
      state = state.copyWith(phase: AddPhase.error, error: 'Engine not ready');
      return;
    }
    try {
      final res = await client.rpc(method, body);
      final nextState = res['State'] as String?;
      final option = res['Option'] as Map<String, dynamic>?;
      final err = (res['Error'] as String?) ?? '';
      if (err.isNotEmpty) {
        state = state.copyWith(phase: AddPhase.error, error: err);
        return;
      }
      if (nextState != null && nextState.isNotEmpty && option != null) {
        state = state.copyWith(
          phase: AddPhase.question,
          question: ProviderOption.fromJson(option),
          questionState: nextState,
        );
        return;
      }
      // Done — the remote now exists.
      ref.invalidate(remotesProvider);
      state = state.copyWith(phase: AddPhase.done);
    } on RcloneException catch (e) {
      state = state.copyWith(phase: AddPhase.error, error: e.message);
    } catch (e) {
      state = state.copyWith(phase: AddPhase.error, error: '$e');
    }
  }
}

final addRemoteControllerProvider =
    NotifierProvider<AddRemoteController, AddRemoteState>(
      AddRemoteController.new,
    );

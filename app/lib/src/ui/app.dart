import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/settings_controller.dart';
import 'home_screen.dart';
import 'theme/app_theme.dart';

/// Application root: themes (mode driven by settings) + the home shell.
class AircloneApp extends ConsumerWidget {
  const AircloneApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(
      settingsControllerProvider.select((s) => s.themeMode),
    );
    return MaterialApp(
      title: 'Airclone',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: mode,
      home: const HomeScreen(),
    );
  }
}

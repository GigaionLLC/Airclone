import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/settings_controller.dart';
import '../state/window_backdrop.dart';
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
    final backdrop = ref.watch(windowBackdropProvider);
    // A translucent backdrop (Mica/Acrylic) only shows if the app paints behind
    // it transparently — drop the scaffold/canvas fill so the OS material reads.
    final translucent =
        backdrop == WindowBackdrop.mica || backdrop == WindowBackdrop.acrylic;
    ThemeData withBackdrop(ThemeData t) => translucent
        ? t.copyWith(
            scaffoldBackgroundColor: Colors.transparent,
            canvasColor: Colors.transparent,
          )
        : t;
    return MaterialApp(
      title: 'Airclone',
      debugShowCheckedModeBanner: false,
      theme: withBackdrop(AppTheme.light()),
      darkTheme: withBackdrop(AppTheme.dark()),
      themeMode: mode,
      home: const HomeScreen(),
    );
  }
}

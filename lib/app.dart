import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'repositories/hymn_repository.dart';
import 'services/audio_service.dart';
import 'services/user_store.dart';
import 'theme/app_theme.dart';
import 'screens/app_shell.dart';

class PcgHymnsApp extends StatefulWidget {
  const PcgHymnsApp({super.key});

  @override
  State<PcgHymnsApp> createState() => _PcgHymnsAppState();
}

class _PcgHymnsAppState extends State<PcgHymnsApp> {
  final _repository = const HymnRepository();
  final _audio = HymnAudioService();

  @override
  void dispose() {
    _audio.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MultiProvider(
        providers: [
          Provider.value(value: _repository),
          Provider.value(value: _audio),
        ],
        child: Consumer<UserStore>(
          builder: (context, preferences, _) => MaterialApp(
            title: 'PCG Hymns',
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            themeMode: preferences.themeMode,
            debugShowCheckedModeBanner: false,
            home: const AppShell(),
          ),
        ),
      );
}

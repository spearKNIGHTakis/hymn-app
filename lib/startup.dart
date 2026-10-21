import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'repositories/hymn_repository.dart';
import 'services/download_manager.dart';
import 'services/user_store.dart';
import 'theme/app_theme.dart';

class AppStartup extends StatefulWidget {
  const AppStartup({
    super.key,
    this.loadPreferences = SharedPreferences.getInstance,
  });

  final Future<SharedPreferences> Function() loadPreferences;

  @override
  State<AppStartup> createState() => _AppStartupState();
}

class _AppStartupState extends State<AppStartup> {
  late Future<SharedPreferences> _preferences;

  @override
  void initState() {
    super.initState();
    _preferences = widget.loadPreferences();
  }

  void _retry() {
    setState(() {
      _preferences = widget.loadPreferences();
    });
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<SharedPreferences>(
        future: _preferences,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return MaterialApp(
              title: 'PCG Hymns',
              theme: AppTheme.light(),
              darkTheme: AppTheme.dark(),
              home: Scaffold(
                body: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline, size: 40),
                        const SizedBox(height: 16),
                        const Text(
                          'PCG Hymns could not finish starting.',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Your saved preferences could not be opened: ${snapshot.error}',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: _retry,
                          child: const Text('Try again'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }
          if (!snapshot.hasData) {
            return MaterialApp(
              title: 'PCG Hymns',
              theme: AppTheme.light(),
              darkTheme: AppTheme.dark(),
              home: const Scaffold(
                body: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.menu_book_rounded, size: 48),
                      SizedBox(height: 20),
                      CircularProgressIndicator(),
                      SizedBox(height: 12),
                      Text('Starting PCG Hymns…'),
                    ],
                  ),
                ),
              ),
            );
          }

          const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
          const supabasePublishableKey = String.fromEnvironment(
            'SUPABASE_PUBLISHABLE_KEY',
            defaultValue: String.fromEnvironment('SUPABASE_ANON_KEY'),
          );
          final preferences = snapshot.requireData;
          return MultiProvider(
            providers: [
              ChangeNotifierProvider(create: (_) => UserStore(preferences)),
              ChangeNotifierProvider(
                  create: (_) => DownloadManager(preferences)),
            ],
            child: const PcgHymnsApp(
              repository: HymnRepository(
                supabaseUrl: supabaseUrl,
                supabaseAnonKey: supabasePublishableKey,
              ),
            ),
          );
        },
      );
}

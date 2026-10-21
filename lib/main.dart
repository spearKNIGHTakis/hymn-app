import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'repositories/hymn_repository.dart';
import 'services/download_manager.dart';
import 'services/user_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final preferences = await SharedPreferences.getInstance();
  const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  const supabasePublishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
    defaultValue: String.fromEnvironment('SUPABASE_ANON_KEY'),
  );
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => UserStore(preferences)),
        ChangeNotifierProvider(create: (_) => DownloadManager(preferences)),
      ],
      child: const PcgHymnsApp(
        repository: HymnRepository(
          supabaseUrl: supabaseUrl,
          supabaseAnonKey: supabasePublishableKey,
        ),
      ),
    ),
  );
}

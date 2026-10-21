import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'services/download_manager.dart';
import 'services/user_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final preferences = await SharedPreferences.getInstance();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => UserStore(preferences)),
        ChangeNotifierProvider(create: (_) => DownloadManager(preferences)),
      ],
      child: const PcgHymnsApp(),
    ),
  );
}

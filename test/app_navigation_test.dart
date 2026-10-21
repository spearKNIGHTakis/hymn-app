import 'package:flutter_test/flutter_test.dart';
import 'package:pcg_hymns/app.dart';
import 'package:pcg_hymns/services/download_manager.dart';
import 'package:pcg_hymns/services/user_store.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('empty catalogue supports navigation across main tabs',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => UserStore(preferences)),
        ChangeNotifierProvider(create: (_) => DownloadManager(preferences)),
      ],
      child: const PcgHymnsApp(),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Sing in Faith'), findsOneWidget);
    await tester.tap(find.text('Hymns').last);
    await tester.pumpAndSettle();
    expect(find.text('Catalogue awaiting verified content'), findsOneWidget);
    await tester.tap(find.text('Progress').last);
    await tester.pumpAndSettle();
    expect(find.text('Singing history'), findsOneWidget);
  });
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pcg_hymns/startup.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('shows a startup screen while preferences initialize',
      (tester) async {
    final completer = Completer<SharedPreferences>();
    await tester.pumpWidget(
      AppStartup(loadPreferences: () => completer.future),
    );

    expect(find.text('Starting PCG Hymns…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    SharedPreferences.setMockInitialValues({});
    completer.complete(await SharedPreferences.getInstance());
    await tester.pumpAndSettle();

    expect(find.text('Sing in Faith'), findsOneWidget);
  });

  testWidgets('shows a retryable message if startup initialization fails',
      (tester) async {
    await tester.pumpWidget(
      AppStartup(
        loadPreferences: () async => throw StateError('storage unavailable'),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('PCG Hymns could not finish starting.'),
      findsOneWidget,
    );
    expect(find.textContaining('storage unavailable'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });
}

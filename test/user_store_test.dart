import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pcg_hymns/services/user_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('persists favourites and singing events by stable hymn ID', () async {
    final preferences = await SharedPreferences.getInstance();
    final store = UserStore(preferences);
    await store.toggleFavourite('hymn-stable-id');
    await store.markSung('hymn-stable-id');

    expect(store.favourites, contains('hymn-stable-id'));
    expect(store.singingEvents, hasLength(1));
    expect(store.singingEvents.single.hymnId, 'hymn-stable-id');
    await store.undoSingingEvent(store.singingEvents.single);
    expect(store.singingEvents, isEmpty);
  });

  test('persists lyric size and font style within supported limits', () async {
    final preferences = await SharedPreferences.getInstance();
    final store = UserStore(preferences);

    await store.setLyricScale(1.2);
    await store.setLyricFontStyle(LyricFontStyle.serif);

    expect(store.lyricScale, 1.2);
    expect(store.lyricFontStyle, LyricFontStyle.serif);
    await store.setLyricScale(2);
    expect(store.lyricScale, 1.5);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pcg_hymns/services/download_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('refuses insecure recording URLs without registering a download',
      () async {
    SharedPreferences.setMockInitialValues({});
    final manager = DownloadManager(await SharedPreferences.getInstance());

    await expectLater(
      manager.download(
          recordingId: 'recording-a',
          hymnId: 'hymn-a',
          url: 'http://example.com/audio.mp3'),
      throwsFormatException,
    );
    expect(manager.entries, isEmpty);
    expect(manager.progress, isEmpty);
  });
}

import 'dart:async';
import 'dart:io';

import 'package:just_audio/just_audio.dart';

import '../models/hymn.dart';
import 'download_manager.dart';

class HymnAudioService {
  final AudioPlayer player = AudioPlayer();
  String? currentHymnId;
  String? currentRecordingId;

  Future<void> play(
      Hymn hymn, HymnRecording recording, DownloadManager downloads) async {
    currentHymnId = hymn.id;
    currentRecordingId = recording.id;
    final local = downloads.forRecording(recording.id);
    if (local != null && await File(local.path).exists()) {
      await player.setFilePath(local.path);
    } else if (recording.url case final url?) {
      await player.setUrl(url);
    } else {
      throw StateError('Recording not available yet.');
    }
    unawaited(player.play());
  }

  Future<void> dispose() => player.dispose();
}

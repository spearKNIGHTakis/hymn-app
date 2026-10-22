
import 'package:just_audio/just_audio.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class HymnAudioService {
  HymnAudioService({AudioPlayer? player})
      : _player = player ?? AudioPlayer();

  final AudioPlayer _player;

  AudioPlayer get player => _player;

  final SupabaseClient _supabase = Supabase.instance.client;

  Future<void> playHymn(String hymnId) async {
    // Find the recording registered for this hymn.
    final recording = await _supabase
        .from('hymn_recordings')
        .select('storage_path, language, recording_type')
        .eq('hymn_id', hymnId)
        .eq('language', 'twi')
        .eq('recording_type', 'maleSolo')
        .maybeSingle();

    if (recording == null) {
      throw Exception('No Twi male-solo recording is registered for this hymn.');
    }

    final String storagePath = recording['storage_path'] as String;

    // Use a public URL for public buckets, or a signed URL for private buckets.
    final storage = _supabase.storage.from('hymn-audio');

    final String audioUrl;
    try {
      audioUrl = await storage.createSignedUrl(storagePath, 3600);
    } catch (e) {
      throw Exception(
        'Could not access the hymn audio. Check Storage permissions: $e',
      );
    }

    await _player.setUrl(audioUrl);
    await _player.play();
  }

  Future<void> pause() => _player.pause();

  Future<void> resume() => _player.play();

  Future<void> stop() => _player.stop();

  Future<void> dispose() => _player.dispose();
}

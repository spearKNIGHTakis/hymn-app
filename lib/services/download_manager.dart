import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DownloadEntry {
  const DownloadEntry(
      {required this.recordingId, required this.hymnId, required this.path});
  final String recordingId;
  final String hymnId;
  final String path;

  Map<String, String> toJson() =>
      {'recordingId': recordingId, 'hymnId': hymnId, 'path': path};
  factory DownloadEntry.fromJson(Map<String, dynamic> json) => DownloadEntry(
        recordingId: json['recordingId'] as String,
        hymnId: json['hymnId'] as String,
        path: json['path'] as String,
      );
}

class DownloadManager extends ChangeNotifier {
  DownloadManager(this._preferences);
  final SharedPreferences _preferences;
  final Map<String, double> progress = {};
  final Map<String, String> activeDownloads = {};

  List<DownloadEntry> get entries {
    try {
      final raw = _preferences.getString('downloads');
      if (raw == null) return [];
      return (jsonDecode(raw) as List<dynamic>)
          .map((item) => DownloadEntry.fromJson(item as Map<String, dynamic>))
          .where((entry) => File(entry.path).existsSync())
          .toList();
    } catch (_) {
      return [];
    }
  }

  DownloadEntry? forRecording(String id) {
    for (final entry in entries) {
      if (entry.recordingId == id) return entry;
    }
    return null;
  }

  int get storageBytes =>
      entries.fold(0, (sum, entry) => sum + File(entry.path).lengthSync());

  Future<void> download(
      {required String recordingId,
      required String hymnId,
      required String url}) async {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      throw const FormatException(
          'Only valid HTTPS recording URLs can be downloaded.');
    }
    if (activeDownloads.containsKey(recordingId)) return;
    if (forRecording(recordingId) != null) return;
    activeDownloads[recordingId] = hymnId;
    progress[recordingId] = 0;
    notifyListeners();
    final directory = await getApplicationDocumentsDirectory();
    final safeId = recordingId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final temporary = File('${directory.path}/$safeId.part');
    final destination = File('${directory.path}/$safeId.audio');
    final client = http.Client();
    try {
      final request = http.Request('GET', uri);
      final response = await client.send(request);
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException(
            'Download failed with HTTP ${response.statusCode}.');
      }
      final total = response.contentLength ?? 0;
      var received = 0;
      final sink = temporary.openWrite();
      try {
        await for (final chunk in response.stream) {
          sink.add(chunk);
          received += chunk.length;
          progress[recordingId] = total > 0 ? received / total : 0;
          notifyListeners();
        }
        await sink.flush();
      } finally {
        await sink.close();
      }
      if (received == 0 || (total > 0 && received != total)) {
        throw const HttpException('Downloaded audio was empty or incomplete.');
      }
      if (await destination.exists()) await destination.delete();
      await temporary.rename(destination.path);
      final updated = [
        ...entries,
        DownloadEntry(
            recordingId: recordingId, hymnId: hymnId, path: destination.path)
      ];
      await _save(updated);
    } catch (_) {
      if (await temporary.exists()) await temporary.delete();
      rethrow;
    } finally {
      client.close();
      activeDownloads.remove(recordingId);
      progress.remove(recordingId);
      notifyListeners();
    }
  }

  Future<void> delete(String recordingId) async {
    final entry = forRecording(recordingId);
    if (entry == null) return;
    final file = File(entry.path);
    if (await file.exists()) await file.delete();
    await _save(
        entries.where((item) => item.recordingId != recordingId).toList());
  }

  Future<void> _save(List<DownloadEntry> values) async {
    await _preferences.setString(
        'downloads', jsonEncode(values.map((item) => item.toJson()).toList()));
    notifyListeners();
  }
}

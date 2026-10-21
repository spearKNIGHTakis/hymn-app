import 'dart:convert';

import 'package:flutter/services.dart';

import '../models/hymn.dart';

class HymnRepository {
  const HymnRepository();

  Future<List<Hymn>> loadBundled() async {
    final source = await rootBundle.loadString('assets/catalogue.json');
    return parseCatalogue(source);
  }

  List<Hymn> parseCatalogue(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! Map<String, dynamic> || decoded['schemaVersion'] != 1) {
      throw const FormatException('Unsupported catalogue schema');
    }
    final entries = decoded['hymns'];
    if (entries is! List ||
        entries.any((item) => item is! Map<String, dynamic>)) {
      throw const FormatException('Catalogue hymns must be a list of objects');
    }
    final hymns =
        entries.cast<Map<String, dynamic>>().map(Hymn.fromJson).toList();
    final ids = <String>{};
    final recordingIds = <String>{};
    for (final hymn in hymns) {
      if (!ids.add(hymn.id)) {
        throw FormatException('Duplicate hymn ID: ${hymn.id}');
      }
      for (final recording in hymn.recordings) {
        if (!recordingIds.add(recording.id)) {
          throw FormatException('Duplicate recording ID: ${recording.id}');
        }
      }
    }
    return List.unmodifiable(hymns);
  }

  List<Hymn> search(
    Iterable<Hymn> hymns, {
    String query = '',
    HymnLanguage? language,
    String sortBy = 'number',
  }) {
    final needle = query.trim().toLowerCase();
    final result = hymns.where((hymn) {
      return (language == null || hymn.language == language) &&
          (needle.isEmpty || hymn.searchableText.contains(needle));
    }).toList();
    result.sort((a, b) => sortBy == 'title'
        ? a.title.toLowerCase().compareTo(b.title.toLowerCase())
        : a.number.compareTo(b.number));
    return result;
  }
}

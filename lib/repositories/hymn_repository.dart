import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/hymn.dart';

class CatalogueLoadResult {
  const CatalogueLoadResult({
    required this.hymns,
    required this.isRemote,
    this.syncMessage,
  });

  final List<Hymn> hymns;
  final bool isRemote;
  final String? syncMessage;
}

class HymnRepository {
  const HymnRepository({
    this.supabaseUrl = const String.fromEnvironment('SUPABASE_URL'),
    this.supabaseAnonKey = const String.fromEnvironment(
      'SUPABASE_PUBLISHABLE_KEY',
      defaultValue: String.fromEnvironment('SUPABASE_ANON_KEY'),
    ),
  });

  static const _cacheKey = 'publishedCatalogue';
  final String supabaseUrl;
  final String supabaseAnonKey;

  Future<List<Hymn>> loadBundled() async {
    final source = await rootBundle.loadString('assets/catalogue.json');
    return parseCatalogue(source);
  }

  Future<CatalogueLoadResult> load() async {
    final bundledHymns = await loadBundled();
    final preferences = await SharedPreferences.getInstance();
    final cachedSource = preferences.getString(_cacheKey);
    List<Hymn>? cachedHymns;
    String? cacheError;
    if (cachedSource != null) {
      try {
        cachedHymns = parseCatalogue(cachedSource);
      } on FormatException catch (error) {
        cacheError = 'The saved offline catalogue could not be read: $error';
        await preferences.remove(_cacheKey);
      }
    }

    if (supabaseUrl.isEmpty && supabaseAnonKey.isEmpty) {
      return CatalogueLoadResult(
        hymns: cachedHymns ?? bundledHymns,
        isRemote: false,
        syncMessage: cacheError,
      );
    }
    if (supabaseUrl.isEmpty || supabaseAnonKey.isEmpty) {
      return CatalogueLoadResult(
        hymns: cachedHymns ?? bundledHymns,
        isRemote: false,
        syncMessage:
            'Online catalogue sync needs SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY.',
      );
    }

    try {
      final baseUri = Uri.tryParse(supabaseUrl);
      if (baseUri == null ||
          baseUri.scheme != 'https' ||
          baseUri.host.isEmpty) {
        throw const FormatException('SUPABASE_URL must be a valid HTTPS URL.');
      }
      final uri = Uri.https(
        baseUri.authority,
        '/rest/v1/catalogue_versions',
        const {
          'select': 'content',
          'channel': 'eq.published',
          'limit': '1',
        },
      );
      final response = await http.get(
        uri,
        headers: {
          'apikey': supabaseAnonKey,
          'Authorization': 'Bearer $supabaseAnonKey',
        },
      ).timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) {
        throw HttpException(
          'Catalogue request returned HTTP ${response.statusCode}.',
          uri: uri,
        );
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! List || decoded.isEmpty) {
        return CatalogueLoadResult(
          hymns: cachedHymns ?? bundledHymns,
          isRemote: false,
          syncMessage:
              'No published online catalogue was found; showing saved content.',
        );
      }
      final row = decoded.first;
      if (row is! Map<String, dynamic> || row['content'] == null) {
        throw const FormatException(
            'The published catalogue response is malformed.');
      }
      final catalogueJson = jsonEncode(row['content']);
      final remoteHymns = parseCatalogue(catalogueJson);
      final saved = await preferences.setString(_cacheKey, catalogueJson);
      return CatalogueLoadResult(
        hymns: remoteHymns,
        isRemote: true,
        syncMessage: saved
            ? null
            : 'Online catalogue loaded, but its offline copy could not be saved.',
      );
    } on Exception catch (error) {
      return CatalogueLoadResult(
        hymns: cachedHymns ?? bundledHymns,
        isRemote: false,
        syncMessage:
            'Could not sync the published catalogue; showing ${cachedHymns == null ? "the bundled" : "the saved offline"} version. $error',
      );
    }
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

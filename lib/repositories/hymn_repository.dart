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
      final remoteHymns = await _resolvePlaybackUrls(
        parseCatalogue(catalogueJson),
        baseUri,
      );
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

  Future<List<Hymn>> _resolvePlaybackUrls(
    List<Hymn> hymns,
    Uri baseUri,
  ) async {
    return Future.wait(
      hymns.map((hymn) async {
        final recordings = await Future.wait(
          hymn.recordings.map((recording) async {
            final storagePath = recording.storagePath;
            if (storagePath == null) return recording;

            final encodedPath = storagePath
                .split('/')
                .map(Uri.encodeComponent)
                .join('/');
            final uri = Uri.parse(
              '${baseUri.scheme}://${baseUri.authority}/storage/v1/object/sign/hymn-audio/$encodedPath',
            );
            final response = await http
                .post(
                  uri,
                  headers: {
                    'apikey': supabaseAnonKey,
                    'Authorization': 'Bearer $supabaseAnonKey',
                    'Content-Type': 'application/json',
                  },
                  body: jsonEncode({'expiresIn': 3600}),
                )
                .timeout(const Duration(seconds: 12));
            if (response.statusCode != 200) {
              throw HttpException(
                'Could not create a playback URL for a published recording (HTTP ${response.statusCode}).',
                uri: uri,
              );
            }
            final body = jsonDecode(response.body);
            if (body is! Map<String, dynamic> ||
                body['signedURL'] is! String ||
                (body['signedURL'] as String).isEmpty) {
              throw const FormatException(
                'The recording playback response is malformed.',
              );
            }
            final returnedPath = body['signedURL'] as String;
            final playbackUri = returnedPath.startsWith('https://')
                ? Uri.parse(returnedPath)
                : Uri.parse(
                    '${baseUri.scheme}://${baseUri.authority}${returnedPath.startsWith('/storage/v1/') ? returnedPath : '/storage/v1$returnedPath'}',
                  );
            if (playbackUri.scheme != 'https' ||
                playbackUri.host != baseUri.host ||
                playbackUri.authority != baseUri.authority) {
              throw const FormatException(
                'The recording playback URL is not hosted by this Supabase project.',
              );
            }
            return recording.withPlaybackUrl(playbackUri.toString());
          }),
        );
        return hymn.withRecordings(recordings);
      }),
    );
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

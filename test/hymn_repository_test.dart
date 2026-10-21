import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pcg_hymns/models/hymn.dart';
import 'package:pcg_hymns/repositories/hymn_repository.dart';

Map<String, dynamic> _hymn({
  required String id,
  required String number,
  required String title,
  String language = 'english',
  List<String> stanzas = const [],
  List<Map<String, dynamic>> recordings = const [],
}) =>
    {
      'id': id,
      'number': number,
      'title': title,
      'language': language,
      'stanzas': stanzas,
      'recordings': recordings,
    };

String _catalogue(List<Map<String, dynamic>> hymns) =>
    jsonEncode({'schemaVersion': 1, 'hymns': hymns});

void main() {
  const repository = HymnRepository();

  test('parses language, stanza formatting and optional recordings', () {
    final hymns = repository.parseCatalogue(_catalogue([
      _hymn(
          id: 'eng-placeholder',
          number: '1',
          title: 'Placeholder English',
          stanzas: ['Line one\nLine two']),
      _hymn(
          id: 'twi-placeholder',
          number: '2',
          title: 'Placeholder Twi',
          language: 'twi'),
    ]));

    expect(hymns.first.stanzas.single, 'Line one\nLine two');
    expect(hymns.first.recordings, isEmpty);
    expect(hymns.last.language, HymnLanguage.twi);
  });

  test('filters and searches number, title and lyrics', () {
    final hymns = repository.parseCatalogue(_catalogue([
      _hymn(
          id: 'one',
          number: '12',
          title: 'Morning',
          stanzas: ['A verified lyric placeholder']),
      _hymn(id: 'two', number: '25', title: 'Evening', language: 'twi'),
    ]));

    expect(
        repository.search(hymns, language: HymnLanguage.twi).single.id, 'two');
    expect(repository.search(hymns, query: '12').single.id, 'one');
    expect(repository.search(hymns, query: 'MORNING').single.id, 'one');
    expect(repository.search(hymns, query: 'verified lyric').single.id, 'one');
  });

  test('accepts an empty catalogue and rejects duplicate IDs', () {
    expect(repository.parseCatalogue(_catalogue([])), isEmpty);
    expect(
      () => repository.parseCatalogue(_catalogue([
        _hymn(id: 'same', number: '1', title: 'First'),
        _hymn(id: 'same', number: '2', title: 'Second'),
      ])),
      throwsFormatException,
    );
  });

  test('rejects malformed language and non-HTTPS recording URLs', () {
    expect(
        () => Hymn.fromJson(
            _hymn(id: 'bad', number: '1', title: 'Bad', language: 'Ga')),
        throwsFormatException);
    expect(
      () => Hymn.fromJson(_hymn(
        id: 'bad-audio',
        number: '1',
        title: 'Bad audio',
        recordings: [
          {
            'id': 'recording-1',
            'type': 'choir',
            'url': 'http://example.com/audio.mp3'
          }
        ],
      )),
      throwsFormatException,
    );
  });
}

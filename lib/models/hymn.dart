enum HymnLanguage { english, twi }

enum RecordingType { maleSolo, femaleSolo, choir, congregation, instrumental }

extension HymnLanguageLabel on HymnLanguage {
  String get label => this == HymnLanguage.english ? 'English' : 'Twi';
}

extension RecordingTypeLabel on RecordingType {
  String get label => switch (this) {
        RecordingType.maleSolo => 'Male solo',
        RecordingType.femaleSolo => 'Female solo',
        RecordingType.choir => 'Choir',
        RecordingType.congregation => 'Congregation',
        RecordingType.instrumental => 'Instrumental',
      };
}

class HymnRecording {
  const HymnRecording({
    required this.id,
    required this.type,
    this.url,
    this.durationSeconds,
    this.fileSizeBytes,
    this.attribution,
    this.permission,
  });

  final String id;
  final RecordingType type;
  final String? url;
  final int? durationSeconds;
  final int? fileSizeBytes;
  final String? attribution;
  final String? permission;

  factory HymnRecording.fromJson(Map<String, dynamic> json) {
    final id = _requiredString(json, 'id');
    final typeName = _requiredString(json, 'type');
    final type = RecordingType.values.where((item) => item.name == typeName);
    if (type.isEmpty) {
      throw FormatException('Invalid recording type: $typeName');
    }
    final url = json['url'] as String?;
    if (url != null && url.isNotEmpty) {
      final uri = Uri.tryParse(url);
      if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
        throw FormatException('Recording $id must use a valid HTTPS URL');
      }
    }
    return HymnRecording(
      id: id,
      type: type.first,
      url: url,
      durationSeconds: _optionalInt(json, 'durationSeconds'),
      fileSizeBytes: _optionalInt(json, 'fileSizeBytes'),
      attribution: json['attribution'] as String?,
      permission: json['permission'] as String?,
    );
  }

  static int? _optionalInt(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value == null) return null;
    if (value is! int || value < 0) {
      throw FormatException('$key must be a positive integer');
    }
    return value;
  }
}

class Hymn {
  const Hymn({
    required this.id,
    required this.number,
    required this.title,
    required this.language,
    required this.stanzas,
    this.chorus,
    this.author,
    this.composer,
    this.source,
    this.copyright,
    this.attribution,
    this.permission,
    this.artwork,
    this.recordings = const [],
  });

  final String id;
  final String number;
  final String title;
  final HymnLanguage language;
  final List<String> stanzas;
  final String? chorus;
  final String? author;
  final String? composer;
  final String? source;
  final String? copyright;
  final String? attribution;
  final String? permission;
  final String? artwork;
  final List<HymnRecording> recordings;

  factory Hymn.fromJson(Map<String, dynamic> json) {
    final id = _requiredString(json, 'id');
    final languageName = _requiredString(json, 'language');
    final language =
        HymnLanguage.values.where((item) => item.name == languageName);
    if (language.isEmpty) {
      throw FormatException('Invalid language: $languageName');
    }
    final rawStanzas = json['stanzas'];
    if (rawStanzas is! List || rawStanzas.any((line) => line is! String)) {
      throw FormatException('Hymn $id must have a list of stanza strings');
    }
    final rawRecordings = json['recordings'] ?? const [];
    if (rawRecordings is! List ||
        rawRecordings.any((item) => item is! Map<String, dynamic>)) {
      throw FormatException('Hymn $id has malformed recordings');
    }
    return Hymn(
      id: id,
      number: _requiredString(json, 'number'),
      title: _requiredString(json, 'title'),
      language: language.first,
      stanzas: rawStanzas.cast<String>(),
      chorus: json['chorus'] as String?,
      author: json['author'] as String?,
      composer: json['composer'] as String?,
      source: json['source'] as String?,
      copyright: json['copyright'] as String?,
      attribution: json['attribution'] as String?,
      permission: json['permission'] as String?,
      artwork: json['artwork'] as String?,
      recordings: rawRecordings
          .cast<Map<String, dynamic>>()
          .map(HymnRecording.fromJson)
          .toList(growable: false),
    );
  }

  String get searchableText =>
      '$number $title ${stanzas.join(' ')} ${chorus ?? ''}'.toLowerCase();
}

String _requiredString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('Missing required field: $key');
  }
  return value;
}

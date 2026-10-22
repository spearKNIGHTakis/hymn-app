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
    this.storagePath,
    this.durationSeconds,
    this.fileSizeBytes,
    this.attribution,
    this.permission,
  });

  final String id;
  final RecordingType type;
  final String? url;
  final String? storagePath;
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
    final url = _optionalString(json, 'url');
    if (url != null && url.isNotEmpty) {
      final uri = Uri.tryParse(url);
      if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
        throw FormatException('Recording $id must use a valid HTTPS URL');
      }
    }
    final storagePath = _optionalString(json, 'storagePath');
    if (storagePath != null &&
        (storagePath.trim().isEmpty ||
            storagePath.startsWith('/') ||
            storagePath
                .split('/')
                .any((part) => part.isEmpty || part == '.' || part == '..'))) {
      throw FormatException('Recording $id has an invalid storage path');
    }
    return HymnRecording(
      id: id,
      type: type.first,
      url: url,
      storagePath: storagePath,
      durationSeconds: _optionalInt(json, 'durationSeconds'),
      fileSizeBytes: _optionalInt(json, 'fileSizeBytes'),
      attribution: _optionalString(json, 'attribution'),
      permission: _optionalString(json, 'permission'),
    );
  }

  HymnRecording withPlaybackUrl(String playbackUrl) => HymnRecording(
        id: id,
        type: type,
        url: playbackUrl,
        storagePath: storagePath,
        durationSeconds: durationSeconds,
        fileSizeBytes: fileSizeBytes,
        attribution: attribution,
        permission: permission,
      );

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

  Hymn withRecordings(List<HymnRecording> value) => Hymn(
        id: id,
        number: number,
        title: title,
        language: language,
        stanzas: stanzas,
        chorus: chorus,
        author: author,
        composer: composer,
        source: source,
        copyright: copyright,
        attribution: attribution,
        permission: permission,
        artwork: artwork,
        recordings: value,
      );

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
      chorus: _optionalString(json, 'chorus'),
      author: _optionalString(json, 'author'),
      composer: _optionalString(json, 'composer'),
      source: _optionalString(json, 'source'),
      copyright: _optionalString(json, 'copyright'),
      attribution: _optionalString(json, 'attribution'),
      permission: _optionalString(json, 'permission'),
      artwork: _optionalString(json, 'artwork'),
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

String? _optionalString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is! String) {
    throw FormatException('$key must be a string');
  }
  return value;
}

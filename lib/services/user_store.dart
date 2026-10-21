import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum LyricFontStyle {
  sans('sans-serif'),
  serif('serif');

  const LyricFontStyle(this.fontFamily);

  final String fontFamily;
}

class SingingEvent {
  const SingingEvent({required this.hymnId, required this.at});
  final String hymnId;
  final DateTime at;

  Map<String, dynamic> toJson() =>
      {'hymnId': hymnId, 'at': at.toIso8601String()};
  factory SingingEvent.fromJson(Map<String, dynamic> json) => SingingEvent(
        hymnId: json['hymnId'] as String,
        at: DateTime.parse(json['at'] as String),
      );
}

class UserStore extends ChangeNotifier {
  UserStore(this._preferences);
  final SharedPreferences _preferences;

  Set<String> get favourites =>
      _preferences.getStringList('favourites')?.toSet() ?? {};
  List<String> get recentIds => _preferences.getStringList('recent') ?? [];
  ThemeMode get themeMode => switch (_preferences.getString('themeMode')) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };
  double get lyricScale => _preferences.getDouble('lyricScale') ?? 1.0;
  LyricFontStyle get lyricFontStyle =>
      _preferences.getString('lyricFontStyle') == 'serif'
          ? LyricFontStyle.serif
          : LyricFontStyle.sans;
  String get defaultLanguage =>
      _preferences.getString('defaultLanguage') ?? 'english';
  bool get wifiOnly => _preferences.getBool('wifiOnly') ?? false;
  List<SingingEvent> get singingEvents {
    try {
      return (_preferences.getString('singingEvents') == null
              ? <dynamic>[]
              : jsonDecode(_preferences.getString('singingEvents')!)
                  as List<dynamic>)
          .map((item) => SingingEvent.fromJson(item as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> toggleFavourite(String hymnId) async {
    final values = favourites;
    if (!values.add(hymnId)) values.remove(hymnId);
    await _preferences.setStringList('favourites', values.toList());
    notifyListeners();
  }

  Future<void> markPlayed(String hymnId) async {
    final values =
        [hymnId, ...recentIds.where((id) => id != hymnId)].take(20).toList();
    await _preferences.setStringList('recent', values);
    notifyListeners();
  }

  Future<void> markSung(String hymnId) async {
    final values = [
      ...singingEvents,
      SingingEvent(hymnId: hymnId, at: DateTime.now())
    ];
    await _saveEvents(values);
  }

  Future<void> undoSingingEvent(SingingEvent event) async {
    final values = singingEvents;
    final index = values.lastIndexWhere(
        (item) => item.hymnId == event.hymnId && item.at == event.at);
    if (index >= 0) values.removeAt(index);
    await _saveEvents(values);
  }

  Future<void> clearSingingEvents() => _saveEvents([]);

  Future<void> _saveEvents(List<SingingEvent> events) async {
    await _preferences.setString('singingEvents',
        jsonEncode(events.map((item) => item.toJson()).toList()));
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode value) async {
    await _preferences.setString('themeMode', value.name);
    notifyListeners();
  }

  Future<void> setLyricScale(double value) async {
    await _preferences.setDouble('lyricScale', value.clamp(0.8, 1.5));
    notifyListeners();
  }

  Future<void> setLyricFontStyle(LyricFontStyle value) async {
    await _preferences.setString('lyricFontStyle', value.name);
    notifyListeners();
  }

  Future<void> setDefaultLanguage(String value) async {
    await _preferences.setString('defaultLanguage', value);
    notifyListeners();
  }

  Future<void> setWifiOnly(bool value) async {
    await _preferences.setBool('wifiOnly', value);
    notifyListeners();
  }
}

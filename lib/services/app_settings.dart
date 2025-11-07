// Сервис для управления настройками приложения с моментальным обновлением
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppSettings extends ChangeNotifier {
  static final AppSettings _instance = AppSettings._internal();
  factory AppSettings() => _instance;
  AppSettings._internal();

  String _themeMode = 'system';
  double _textScale = 1.0;

  String get themeMode => _themeMode;
  double get textScale => _textScale;

  Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _themeMode = prefs.getString('theme_mode') ?? 'system';
    _textScale = prefs.getDouble('text_scale') ?? 1.0;
    notifyListeners();
  }

  Future<void> setThemeMode(String themeMode) async {
    if (_themeMode == themeMode) return;
    _themeMode = themeMode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('theme_mode', themeMode);
    notifyListeners();
  }

  Future<void> setTextScale(double scale) async {
    if (_textScale == scale) return;
    _textScale = scale;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('text_scale', scale);
    notifyListeners();
  }
}


import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum MapMode { standard, satellite }

class ThemeProvider extends ChangeNotifier with WidgetsBindingObserver {
  ThemeMode _themeMode = ThemeMode.system;
  MapMode _mapMode = MapMode.satellite; // Default to satellite for tactical feel
  final SharedPreferences _prefs;

  // Fallback lock: prevents mid-session theme snap
  final bool _isLocked;

  // Debounce guard for rapid toggle
  DateTime? _lastToggleTime;

  ThemeProvider(this._prefs, {bool isLocked = false}) : _isLocked = isLocked {
    _loadTheme();
    WidgetsBinding.instance.addObserver(this);
  }

  ThemeMode get themeMode => _themeMode;
  MapMode get mapMode => _mapMode;

  String get mapUrlTemplate {
    if (_mapMode == MapMode.satellite) {
      return 'https://mt1.google.com/vt/lyrs=y&x={x}&y={y}&z={z}';
    } else {
      return 'https://mt1.google.com/vt/lyrs=m&x={x}&y={y}&z={z}';
    }
  }

  bool get isDarkMode {
    if (_themeMode == ThemeMode.system) {
      return WidgetsBinding.instance.platformDispatcher.platformBrightness ==
          Brightness.dark;
    }
    return _themeMode == ThemeMode.dark;
  }

  void _loadTheme() {
    // If locked to system theme (startup timeout occurred), don't load saved value
    if (_isLocked) {
      _themeMode = ThemeMode.system;
      notifyListeners();
      return;
    }

    final savedTheme = _prefs.getString('theme_mode');
    if (savedTheme == 'light') {
      _themeMode = ThemeMode.light;
    } else if (savedTheme == 'dark') {
      _themeMode = ThemeMode.dark;
    } else {
      _themeMode = ThemeMode.system;
    }

    final savedMap = _prefs.getString('map_mode');
    if (savedMap == 'standard') {
      _mapMode = MapMode.standard;
    } else {
      _mapMode = MapMode.satellite;
    }

    notifyListeners();
  }

  Future<void> toggleTheme() async {
    // Debounce: ignore if last change < 300ms ago
    final now = DateTime.now();
    if (_lastToggleTime != null &&
        now.difference(_lastToggleTime!).inMilliseconds < 300) {
      return;
    }
    _lastToggleTime = now;

    // Haptic only on major mode change (not system)
    try {
      await HapticFeedback.mediumImpact();
    } catch (_) {}

    if (_themeMode == ThemeMode.light) {
      _themeMode = ThemeMode.dark;
    } else if (_themeMode == ThemeMode.dark) {
      _themeMode = ThemeMode.system;
    } else {
      _themeMode = ThemeMode.light;
    }

    await _prefs.setString(
        'theme_mode', _themeMode.toString().split('.').last);
    notifyListeners();
  }

  Future<void> toggleMapMode() async {
    _mapMode = _mapMode == MapMode.satellite ? MapMode.standard : MapMode.satellite;
    await _prefs.setString('map_mode', _mapMode.toString().split('.').last);
    notifyListeners();
  }

  @override
  void didChangePlatformBrightness() {
    if (_themeMode == ThemeMode.system) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}

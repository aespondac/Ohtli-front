import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:html' as html;
import 'dart:ui';

enum OhtliThemeMode { light, dark, system }
enum OhtliFontSize { small, medium, large, extraLarge }

class OhtliSettings extends ChangeNotifier {
  static final OhtliSettings instance = OhtliSettings._();
  OhtliSettings._() {
    _loadSettings();
  }

  OhtliThemeMode _themeMode = OhtliThemeMode.system;
  OhtliFontSize _fontSize = OhtliFontSize.medium;

  OhtliThemeMode get themeMode => _themeMode;
  OhtliFontSize get fontSize => _fontSize;

  set themeMode(OhtliThemeMode mode) {
    if (_themeMode != mode) {
      _themeMode = mode;
      _saveSettings();
      notifyListeners();
    }
  }

  set fontSize(OhtliFontSize size) {
    if (_fontSize != size) {
      _fontSize = size;
      _saveSettings();
      notifyListeners();
    }
  }

  double get textScaleFactor {
    switch (_fontSize) {
      case OhtliFontSize.small:
        return 0.85;
      case OhtliFontSize.medium:
        return 1.0;
      case OhtliFontSize.large:
        return 1.15;
      case OhtliFontSize.extraLarge:
        return 1.30;
    }
  }

  bool get isDarkMode {
    if (_themeMode == OhtliThemeMode.dark) return true;
    if (_themeMode == OhtliThemeMode.light) return false;
    // System fallback
    return PlatformDispatcher.instance.platformBrightness == Brightness.dark;
  }

  void _loadSettings() {
    if (kIsWeb) {
      try {
        final savedTheme = html.window.localStorage['ohtli_theme_mode'];
        if (savedTheme != null) {
          _themeMode = OhtliThemeMode.values.firstWhere(
            (e) => e.toString() == savedTheme,
            orElse: () => OhtliThemeMode.system,
          );
        }
        final savedSize = html.window.localStorage['ohtli_font_size'];
        if (savedSize != null) {
          _fontSize = OhtliFontSize.values.firstWhere(
            (e) => e.toString() == savedSize,
            orElse: () => OhtliFontSize.medium,
          );
        }
      } catch (e) {
        print("Error loading settings from localStorage: $e");
      }
    }
  }

  void _saveSettings() {
    if (kIsWeb) {
      try {
        html.window.localStorage['ohtli_theme_mode'] = _themeMode.toString();
        html.window.localStorage['ohtli_font_size'] = _fontSize.toString();
      } catch (e) {
        print("Error saving settings to localStorage: $e");
      }
    }
  }
}

class OhtliColors {
  static const Color stormyTeal = Color(0xFF2C666E);
  static const Color xoconostle = Color(0xFF6C3953);
  static const Color cantera = Color(0xFFD1CDC4);

  static Color get cloudDancer {
    return OhtliSettings.instance.isDarkMode
        ? const Color(0xFF121214) // Dark obsidian background
        : const Color(0xFFF0EEE9); // Light CDMX cream
  }

  static Color get onyx {
    return OhtliSettings.instance.isDarkMode
        ? const Color(0xFFF0EEE9) // Soft light cream for readable text in dark mode
        : const Color(0xFF0A090C); // Obsidian black text
  }

  static Color get inputBg {
    return OhtliSettings.instance.isDarkMode
        ? const Color(0xFF1E1E22) // Dark input background
        : const Color(0xFFDCD8CF); // Light cantera input background
  }
}

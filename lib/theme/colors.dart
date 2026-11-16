import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;
import 'dart:ui';

enum OhtliThemeMode { light, dark, system }
enum OhtliFontSize { small, medium, large, extraLarge }

class OhtliSettings extends ChangeNotifier with WidgetsBindingObserver {
  static final OhtliSettings instance = OhtliSettings._();
  OhtliSettings._() {
    _loadSettings();
  }

  /// Registra el observador para seguir en vivo el modo claro/oscuro del sistema.
  /// Se llama una vez desde main() tras inicializar el binding.
  void attachToSystem() {
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangePlatformBrightness() {
    // En modo "Sistema" todos los colores dependen del brillo del sistema: se redibuja la app
    if (_themeMode == OhtliThemeMode.system) notifyListeners();
  }

  /// Alterna Sistema → Claro → Oscuro → Sistema.
  void cycleThemeMode() {
    switch (_themeMode) {
      case OhtliThemeMode.system:
        themeMode = OhtliThemeMode.light;
        break;
      case OhtliThemeMode.light:
        themeMode = OhtliThemeMode.dark;
        break;
      case OhtliThemeMode.dark:
        themeMode = OhtliThemeMode.system;
        break;
    }
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
        final savedTheme = web.window.localStorage.getItem('ohtli_theme_mode');
        if (savedTheme != null) {
          _themeMode = OhtliThemeMode.values.firstWhere(
            (e) => e.toString() == savedTheme,
            orElse: () => OhtliThemeMode.system,
          );
        }
        final savedSize = web.window.localStorage.getItem('ohtli_font_size');
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
        web.window.localStorage.setItem('ohtli_theme_mode', _themeMode.toString());
        web.window.localStorage.setItem('ohtli_font_size', _fontSize.toString());
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
  static const Color cempasuchil = Color(0xFFE2711D);

  static Color get cloudDancer {
    return OhtliSettings.instance.isDarkMode
        ? const Color(0xFF121214) // Dark obsidian background
        : const Color(0xFFF0EEE9); // Light CDMX cream
  }

  /// Líneas punteadas del fondo (RouteBackgroundPainter): tenues en modo oscuro, donde el
  /// gris cantera fijo se veía casi blanco sobre el texto.
  static Color get routeLine {
    return OhtliSettings.instance.isDarkMode
        ? Colors.white.withValues(alpha: 0.10)
        : cantera.withValues(alpha: 0.95);
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

  static Color get cardBg {
    return OhtliSettings.instance.isDarkMode
        ? const Color(0xFF1E1E22) // Dark card surface
        : Colors.white; // Light card surface
  }

  static Color get cardBorder {
    return OhtliSettings.instance.isDarkMode
        ? const Color(0xFF2E2E34) // Dark subtle border
        : const Color(0xFF0A090C).withValues(alpha: 0.08); // Light subtle border
  }

  static Color get innerCardBg {
    return OhtliSettings.instance.isDarkMode
        ? const Color(0xFF151518) // Dark inner card background
        : const Color(0xFFF7F5F1); // Light inner card background
  }

  // Reglas de color (decisión del usuario, 17-nov-2026):
  // - El acento de la marca es el xoconostle (morado): resaltados, botones destacados, etiquetas, insignias.
  // - El cempasúchil queda SOLO para las estrellas de calificación y para advertencias, errores y
  //   acciones de borrar.
  // Usa estos nombres en vez de cempasuchil/xoconostle directo.

  /// Acento principal (xoconostle). En modo oscuro, una versión clara para que se lea.
  static Color get accent => OhtliSettings.instance.isDarkMode ? accentLight : xoconostle;

  /// Relleno de acento con texto blanco encima (botones, insignias, avisos): igual en los dos modos.
  static const Color accentFill = xoconostle;

  /// Xoconostle claro: acento sobre fondos oscuros o fotos.
  static const Color accentLight = Color(0xFFD3A3BD);

  /// Estrellas de calificación.
  static const Color rating = cempasuchil;

  /// Advertencias, errores y borrar: fondos, íconos y bordes.
  static const Color warning = cempasuchil;

  /// Texto de advertencia o error: cempasúchil oscurecido para pasar contraste AA sobre crema,
  /// y aclarado en modo oscuro.
  static Color get warningText => OhtliSettings.instance.isDarkMode ? const Color(0xFFF29A55) : const Color(0xFFA34B0B);

  /// Turquesa para textos de acento: más claro en modo oscuro para mantener el contraste.
  static Color get accentText {
    return OhtliSettings.instance.isDarkMode ? const Color(0xFF6FB6BF) : stormyTeal;
  }

  static Color get subtleText {
    return OhtliSettings.instance.isDarkMode
        ? const Color(0xFFF0EEE9).withValues(alpha: 0.65)
        : const Color(0xFF0A090C).withValues(alpha: 0.65);
  }
}

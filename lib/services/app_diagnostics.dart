import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:ui' as ui;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

import '../config/app_version.dart';
import '../theme/colors.dart';

/// Lo que acompaña a un comentario ("Enviar comentarios") para entender qué pasó: una captura de
/// la pantalla, el dispositivo, el estado de la app y la cuenta, y los últimos errores.
///
/// - [screenKey] va en un `RepaintBoundary` alrededor de toda la app (main.dart).
/// - [install] guarda los últimos errores de Flutter sin cambiar cómo se reportan.
class AppDiagnostics {
  AppDiagnostics._();

  static final GlobalKey screenKey = GlobalKey(debugLabel: 'ohtli-screen');
  static final DateTime _startedAt = DateTime.now();

  static const int maxErrors = 10;
  static final List<Map<String, String>> _errors = [];

  /// Últimos errores de la app (el más reciente al final).
  static List<Map<String, String>> get recentErrors => List.unmodifiable(_errors);

  static bool _installed = false;

  static void install() {
    if (_installed) return;
    _installed = true;
    _startedAt; // los static se inician al usarse: así cuenta desde que abrió la app
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      recordError(details.exceptionAsString(), details.library);
      if (previous != null) {
        previous(details);
      } else {
        FlutterError.presentError(details);
      }
    };
    final previousPlatform = ui.PlatformDispatcher.instance.onError;
    ui.PlatformDispatcher.instance.onError = (error, stack) {
      recordError(error.toString(), 'async');
      return previousPlatform?.call(error, stack) ?? false;
    };
  }

  static void recordError(String message, [String? where]) {
    final text = message.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (text.isEmpty) return;
    _errors.add({
      'at': DateTime.now().toIso8601String(),
      'message': text.length > 300 ? '${text.substring(0, 299)}…' : text,
      if (where != null && where.isNotEmpty) 'where': where.length > 60 ? where.substring(0, 60) : where,
    });
    if (_errors.length > maxErrors) _errors.removeRange(0, _errors.length - maxErrors);
  }

  /// Captura PNG de lo que se ve en la app (sin el diálogo de comentarios, que se abre después).
  /// null si no se pudo (p. ej. aún no se pinta la pantalla).
  static Future<Uint8List?> captureScreen({double maxPixelRatio = 1.5}) async {
    try {
      final boundary = screenKey.currentContext?.findRenderObject();
      if (boundary is! RenderRepaintBoundary) return null;
      final dpr = ui.PlatformDispatcher.instance.views.first.devicePixelRatio;
      final image = await boundary.toImage(pixelRatio: dpr.clamp(1.0, maxPixelRatio));
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      return data?.buffer.asUint8List();
    } catch (e) {
      debugPrint('[Diagnostics] sin captura: $e');
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Dispositivo, sistema y cuenta
  // ---------------------------------------------------------------------------

  static Object? _prop(JSObject o, String name) {
    try {
      final v = o.getProperty<JSAny?>(name.toJS);
      if (v == null) return null;
      if (v.isA<JSNumber>()) return (v as JSNumber).toDartDouble;
      if (v.isA<JSString>()) return (v as JSString).toDart;
      if (v.isA<JSBoolean>()) return (v as JSBoolean).toDart;
      return v;
    } catch (_) {
      return null;
    }
  }

  static String _num(Object? v) {
    if (v is double) return v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);
    return v?.toString() ?? '';
  }

  /// Navegador, sistema operativo, pantalla, red y capacidad del equipo.
  static Map<String, String> device() {
    final out = <String, String>{};
    try {
      final nav = web.window.navigator;
      final ua = nav.userAgent;
      out['navegador'] = describeBrowserOf(ua);
      out['userAgent'] = ua.length > 300 ? ua.substring(0, 300) : ua;
      out['pantalla'] = '${web.window.screen.width}x${web.window.screen.height}';
      out['ventana'] = '${web.window.innerWidth}x${web.window.innerHeight}';
      out['densidad'] = _num(web.window.devicePixelRatio);
      out['tactil'] = nav.maxTouchPoints > 0 ? 'sí (${nav.maxTouchPoints} puntos)' : 'no';
      out['idioma'] = nav.language;
      final cores = _num(_prop(nav as JSObject, 'hardwareConcurrency'));
      if (cores.isNotEmpty) out['nucleos'] = cores;
      final memory = _num(_prop(nav as JSObject, 'deviceMemory'));
      if (memory.isNotEmpty) out['memoria'] = '$memory GB';
      out['conexion'] = nav.onLine ? 'en línea' : 'sin conexión';
      final connection = (nav as JSObject).getProperty<JSObject?>('connection'.toJS);
      if (connection != null) {
        final type = _prop(connection, 'effectiveType');
        final downlink = _num(_prop(connection, 'downlink'));
        if (type != null) out['red'] = '$type${downlink.isEmpty ? '' : ' · $downlink Mb/s'}';
      }
      final standalone = web.window.matchMedia('(display-mode: standalone)').matches;
      out['instalada'] = standalone ? 'sí (app en inicio)' : 'no (pestaña del navegador)';
    } catch (e) {
      debugPrint('[Diagnostics] dispositivo: $e');
    }
    final now = DateTime.now();
    final offset = now.timeZoneOffset;
    final sign = offset.isNegative ? '-' : '+';
    final hh = offset.inHours.abs().toString().padLeft(2, '0');
    final mm = (offset.inMinutes.abs() % 60).toString().padLeft(2, '0');
    out['zonaHoraria'] = 'UTC$sign$hh:$mm';
    return out;
  }

  /// Estado de la app: versión, ruta, tema, letra, tiempo abierta y errores recientes.
  static Map<String, String> system() {
    final settings = OhtliSettings.instance;
    final out = <String, String>{
      'version': kAppVersion,
      'modo': kReleaseMode ? 'release' : (kProfileMode ? 'profile' : 'debug'),
      'tema': switch (settings.themeMode) {
        OhtliThemeMode.light => 'claro',
        OhtliThemeMode.dark => 'oscuro',
        OhtliThemeMode.system => settings.isDarkMode ? 'sistema (oscuro)' : 'sistema (claro)',
      },
      'letra': switch (settings.fontSize) {
        OhtliFontSize.small => 'chica',
        OhtliFontSize.medium => 'normal',
        OhtliFontSize.large => 'grande',
        OhtliFontSize.extraLarge => 'muy grande',
      },
      'abiertaHace': _ago(DateTime.now().difference(_startedAt)),
      'errores': '${_errors.length}',
    };
    try {
      out['ruta'] = web.window.location.pathname;
      out['renderer'] = const bool.fromEnvironment('dart.tool.dart2wasm') ? 'wasm' : 'js';
    } catch (_) {}
    return out;
  }

  /// La cuenta que manda el comentario. Solo lo lee el administrador.
  static Map<String, String> user() {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) return const {};
    return {
      'uid': u.uid,
      if ((u.displayName ?? '').isNotEmpty) 'nombre': u.displayName!,
      if ((u.email ?? '').isNotEmpty) 'correo': u.email!,
      'correoVerificado': u.emailVerified ? 'sí' : 'no',
      'acceso': u.providerData.map((p) => p.providerId).where((p) => p.isNotEmpty).join(', '),
      if (u.metadata.creationTime != null) 'cuentaDesde': u.metadata.creationTime!.toIso8601String().substring(0, 10),
    };
  }

  static String _ago(Duration d) {
    if (d.inMinutes < 1) return '${d.inSeconds} s';
    if (d.inHours < 1) return '${d.inMinutes} min';
    return '${d.inHours} h ${d.inMinutes % 60} min';
  }

  /// Navegador y sistema en pocas palabras ("Chrome · macOS").
  static String describeBrowserOf(String userAgent) {
    final ua = userAgent.toLowerCase();
    String browser;
    if (ua.contains('edg/')) {
      browser = 'Edge';
    } else if (ua.contains('opr/') || ua.contains('opera')) {
      browser = 'Opera';
    } else if (ua.contains('samsungbrowser')) {
      browser = 'Samsung Internet';
    } else if (ua.contains('firefox/') || ua.contains('fxios')) {
      browser = 'Firefox';
    } else if (ua.contains('crios') || ua.contains('chrome/')) {
      browser = 'Chrome';
    } else if (ua.contains('safari/')) {
      browser = 'Safari';
    } else {
      browser = 'Otro navegador';
    }
    String os;
    if (ua.contains('iphone') || ua.contains('ipad') || ua.contains('ipod')) {
      os = 'iOS';
    } else if (ua.contains('android')) {
      os = 'Android';
    } else if (ua.contains('mac os') || ua.contains('macintosh')) {
      os = 'macOS';
    } else if (ua.contains('windows')) {
      os = 'Windows';
    } else if (ua.contains('cros')) {
      os = 'ChromeOS';
    } else if (ua.contains('linux')) {
      os = 'Linux';
    } else {
      os = 'otro sistema';
    }
    return '$browser · $os';
  }
}

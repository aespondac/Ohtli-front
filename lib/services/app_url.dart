// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'package:web/web.dart' as web;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'ohtli_sso.dart';

/// URL del navegador sincronizada con la pantalla de la app (solo en ohtli.quest).
///
/// La app no usa rutas de Flutter: [MainNavigationController] decide qué pantalla mostrar.
/// Este servicio refleja esa pantalla en la URL (`/explorar`, `/mis-viajes`, `/lugares`…)
/// para que el botón Atrás del navegador funcione, se puedan compartir enlaces y al recargar
/// se vuelva a la misma pantalla. Cuando el navegador cambia la URL (Atrás/Adelante), avisa
/// a [onExternal].
class AppUrl {
  AppUrl._();

  static final AppUrl instance = AppUrl._();

  /// URL con la que arrancó la app, leída en main() antes de que el enrutador toque el
  /// historial (conserva el fragmento de los enlaces antiguos con `#/`).
  static Uri launchUri = Uri.base;

  /// Rutas de las pestañas de la pantalla principal (índices de HomePage).
  static const Map<int, String> homeTabPaths = {
    0: '/explorar',
    1: '/mis-viajes',
    2: '/perfil',
    3: '/amigos',
    5: '/lugares',
    6: '/notificaciones',
  };

  /// Índice de pestaña para una ruta, o null si no es una pestaña.
  static int? homeTabForPath(String path) {
    final p = normalize(path);
    if (p == '/places') return 5;
    for (final e in homeTabPaths.entries) {
      if (e.value == p) return e.key;
    }
    return null;
  }

  /// Quita la diagonal final y pasa a minúsculas: `/Lugares/` → `/lugares`.
  static String normalize(String path) {
    var p = path.toLowerCase();
    while (p.length > 1 && p.endsWith('/')) {
      p = p.substring(0, p.length - 1);
    }
    return p.isEmpty ? '/' : p;
  }

  /// Solo se sincroniza en el sitio principal: los subdominios (Labs, API) tienen sus propias
  /// rutas fijas.
  static bool get enabled {
    if (!kIsWeb) return false;
    final host = web.window.location.hostname;
    // Canales de vista previa de Firebase Hosting (othli-497404--algo.web.app) para probar
    final isPreview = host.startsWith('othli-497404--') && host.endsWith('.web.app');
    return OhtliSso.isMainHost || isPreview || host == 'localhost' || host == '127.0.0.1';
  }

  /// La recibe MainNavigationController: el navegador fue a [uri] (Atrás/Adelante).
  void Function(Uri uri)? onExternal;

  /// Muestra [location] en la barra de direcciones. Con [replace] no agrega una entrada al
  /// historial (redirecciones automáticas, como abrir la app ya con sesión).
  void show(String location, {bool replace = false}) {
    if (!enabled) return;
    final current = '${web.window.location.pathname}${web.window.location.search}';
    if (current == location) return;
    SystemNavigator.routeInformationUpdated(uri: Uri.parse(location), replace: replace);
  }
}

class OhtliRouteParser extends RouteInformationParser<Uri> {
  @override
  Future<Uri> parseRouteInformation(RouteInformation routeInformation) async => routeInformation.uri;
}

/// Enrutador mínimo: una sola página (la app) y la URL va por [AppUrl]. Al ir Atrás en el
/// navegador cierra los diálogos y pantallas abiertas encima y avisa a la app.
class OhtliRouterDelegate extends RouterDelegate<Uri>
    with ChangeNotifier, PopNavigatorRouterDelegateMixin<Uri> {
  OhtliRouterDelegate(this.child);

  final Widget child;

  @override
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  bool _started = false;

  // La URL la informa AppUrl directamente; el Router no la reescribe.
  @override
  Uri? get currentConfiguration => null;

  @override
  Widget build(BuildContext context) {
    return Navigator(
      key: navigatorKey,
      pages: [MaterialPage(key: const ValueKey('ohtli'), child: child)],
      onDidRemovePage: (_) {},
    );
  }

  @override
  Future<void> setInitialRoutePath(Uri configuration) async {
    // La pantalla inicial la decide MainNavigationController con AppUrl.launchUri
    _started = true;
  }

  @override
  Future<void> setNewRoutePath(Uri configuration) async {
    if (!_started) {
      _started = true;
      return;
    }
    navigatorKey.currentState?.popUntil((route) => route.isFirst);
    AppUrl.instance.onExternal?.call(configuration);
  }
}

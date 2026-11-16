import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

import 'trip_follow.dart';

enum LocationProblem { denied, unavailable }

/// Ubicación en tiempo real del navegador (watchPosition). En la web solo llega mientras
/// Ohtli está abierto: con la pantalla apagada o en otra app el navegador la pausa.
class LiveLocation {
  LiveLocation({required this.onFix, required this.onProblem});

  final void Function(GeoFix fix) onFix;
  final void Function(LocationProblem problem) onProblem;
  int? _watchId;

  bool get running => _watchId != null;

  static bool get supported {
    try {
      return (web.window.navigator as JSObject).has('geolocation');
    } catch (_) {
      return false;
    }
  }

  /// ¿Ya dio permiso? Así se retoma el seguimiento sin volver a preguntar.
  static Future<bool> granted() async {
    try {
      final status = await web.window.navigator.permissions.query({'name': 'geolocation'}.jsify() as JSObject).toDart;
      return status.state == 'granted';
    } catch (_) {
      return false;
    }
  }

  void start() {
    if (_watchId != null) return;
    if (!supported) {
      onProblem(LocationProblem.unavailable);
      return;
    }
    try {
      _watchId = web.window.navigator.geolocation.watchPosition(
        ((web.GeolocationPosition p) {
          final c = p.coords;
          onFix(GeoFix(c.latitude, c.longitude, c.accuracy, _timeOf(p)));
        }).toJS,
        ((web.GeolocationPositionError e) {
          onProblem(e.code == 1 ? LocationProblem.denied : LocationProblem.unavailable);
        }).toJS,
        web.PositionOptions(enableHighAccuracy: true, maximumAge: 15000, timeout: 30000),
      );
    } catch (_) {
      onProblem(LocationProblem.unavailable);
    }
  }

  void stop() {
    final id = _watchId;
    _watchId = null;
    if (id == null) return;
    try {
      web.window.navigator.geolocation.clearWatch(id);
    } catch (_) {}
  }

  /// La hora de la lectura (puede venir de unos segundos antes). Se lee como número porque
  /// algunos navegadores la dan con decimales.
  static DateTime _timeOf(web.GeolocationPosition p) {
    final now = DateTime.now();
    try {
      final ms = (p as JSObject).getProperty<JSNumber>('timestamp'.toJS).toDartDouble;
      final at = DateTime.fromMillisecondsSinceEpoch(ms.round());
      if (at.isAfter(now) || now.difference(at) > const Duration(minutes: 10)) return now;
      return at;
    } catch (_) {
      return now;
    }
  }
}

/// Avisos del sistema (los de la barra de notificaciones), con el service worker de la app.
class WebNotify {
  static bool get supported {
    try {
      return (web.window as JSObject).has('Notification');
    } catch (_) {
      return false;
    }
  }

  static bool get granted => supported && web.Notification.permission == 'granted';

  /// Pide permiso (debe ir en respuesta a un toque). Devuelve si se puede avisar.
  static Future<bool> ask() async {
    if (!supported) return false;
    final now = web.Notification.permission;
    if (now == 'granted') return true;
    if (now == 'denied') return false;
    try {
      final r = await web.Notification.requestPermission().toDart;
      return r.toDart == 'granted';
    } catch (_) {
      return false;
    }
  }

  static bool get pageVisible {
    try {
      return web.document.visibilityState == 'visible';
    } catch (_) {
      return true;
    }
  }

  static Future<void> show(String title, String body, {String tag = ''}) async {
    if (!granted) return;
    final options = web.NotificationOptions(
      body: body,
      icon: '/icons/Icon-192.png',
      badge: '/icons/Icon-maskable-192.png',
      tag: tag,
      data: {'url': web.window.location.href}.jsify(),
    );
    try {
      // En Android solo funciona desde el service worker.
      final reg = await web.window.navigator.serviceWorker.ready.toDart.timeout(const Duration(seconds: 3));
      await reg.showNotification(title, options).toDart;
    } catch (_) {
      try {
        web.Notification(title, options);
      } catch (_) {}
    }
  }
}

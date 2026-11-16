import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

import 'app_url.dart';
import 'live_location.dart' show WebNotify;

/// Clave pública VAPID de Firebase (Configuración del proyecto → Cloud Messaging → Certificados
/// web push; generada el 15-nov-2026). No es secreta: el navegador la usa para suscribirse. Con
/// `--dart-define=fcmVapidKey=…` se puede cambiar sin tocar el código.
const String kFcmVapidKey = String.fromEnvironment(
  'fcmVapidKey',
  defaultValue: 'BItu7D6F7GixzrOT0RpiiJPyobq9vcO9DDOVUU78YMTTUSiD6aHDIeibZpYeWTWa-7WjSLxlvj4vqzHVBgv8jak',
);

/// Qué pasa con los avisos push en este dispositivo.
enum PushStatus {
  /// El navegador no tiene push (o no hay clave VAPID configurada).
  unsupported,

  /// iPhone/iPad: solo hay push con Ohtli instalado en la pantalla de inicio.
  needsInstall,

  /// La persona bloqueó las notificaciones en el navegador.
  denied,

  /// Se puede activar con un toque.
  off,

  /// Activando (pidiendo el token).
  working,

  /// Llegan aunque Ohtli esté cerrado.
  on,
}

/// "web-ios", "web-android" o "web-desktop".
String pushPlatformOf(String userAgent, {int maxTouchPoints = 0}) {
  final ua = userAgent.toLowerCase();
  // iPadOS se presenta como Mac, pero con pantalla táctil.
  if (RegExp(r'iphone|ipad|ipod').hasMatch(ua) || (ua.contains('macintosh') && maxTouchPoints > 1)) return 'web-ios';
  if (ua.contains('android')) return 'web-android';
  return 'web-desktop';
}

/// ¿Hay que (re)escribir el token en Firestore? Si cambió, si es de otra cuenta o una vez al día
/// (así `updatedAt` dice qué dispositivos siguen vivos).
bool pushTokenNeedsSync({
  required String token,
  required String uid,
  String? savedToken,
  String? savedUid,
  int? savedAtMs,
  required int nowMs,
}) {
  if (token != savedToken || uid != savedUid || savedAtMs == null) return true;
  return nowMs - savedAtMs > const Duration(hours: 24).inMilliseconds;
}

/// Avisos push con Firebase Cloud Messaging (FCM), también con Ohtli cerrado.
///
/// Se usa el SDK JS de FCM por interop (no el plugin firebase_messaging): el plugin no deja pasar
/// el registro del service worker y registraría uno propio (`firebase-messaging-sw.js`) junto al
/// de la app; además cargaría la mensajería al arrancar. Así se usa `ohtli_sw.js`, que ya da el
/// modo sin conexión y muestra los avisos, y el módulo (`firebase-messaging.js`, de la misma versión
/// que carga firebase_core_web) solo se descarga cuando hace falta.
///
/// - El permiso se pide con un toque ([enableFromTap]).
/// - El token va a `users/{uid}/push_tokens/{token}` (plataforma y `updatedAt`); lo leen las
///   Cloud Functions (functions/push.js) para mandar cada aviso nuevo.
/// - Si cambia la cuenta en este navegador, el token anterior se invalida para que la otra
///   persona no reciba avisos ajenos.
class PushService {
  PushService._();

  static final PushService instance = PushService._();

  final ValueNotifier<PushStatus> status = ValueNotifier<PushStatus>(PushStatus.unsupported);

  StreamSubscription<User?>? _authSub;
  String? _uid;
  bool _started = false;
  Future<JSObject?>? _messaging;

  static const String _kToken = 'ohtli_push_token';
  static const String _kTokenUid = 'ohtli_push_token_uid';
  static const String _kSyncedAt = 'ohtli_push_synced_at';
  static String _kOn(String uid) => 'ohtli_push_on_$uid';

  bool get configured => kFcmVapidKey.isNotEmpty;

  /// Se llama una vez al arrancar, con Firebase ya inicializado.
  void start() {
    if (_started || !kIsWeb) return;
    _started = true;
    _listenServiceWorker();
    _authSub = FirebaseAuth.instance.authStateChanges().listen(_onUser);
  }

  @visibleForTesting
  void stop() {
    _authSub?.cancel();
    _started = false;
  }

  Future<void> _onUser(User? user) async {
    final prev = _uid;
    _uid = user?.uid;
    if (prev != null && prev != _uid && _read(_kOn(prev)) == '1' && _read(_kTokenUid) == prev) {
      // Cerró sesión o cambió de cuenta: el token de la otra cuenta deja de servir (el servidor
      // borra su documento la próxima vez que FCM lo rechace).
      await _deleteToken();
    }
    _refreshStatus();
    final uid = _uid;
    if (uid != null && _read(_kOn(uid)) == '1' && _permission == 'granted') {
      // Renueva el token (FCM lo rota) sin competir con la carga inicial de la app.
      if (prev == null) await Future<void>.delayed(const Duration(seconds: 8));
      if (_uid == uid) unawaited(_register(uid));
    }
  }

  /// Activa los avisos en este dispositivo. Debe llamarse directo en el toque (Safari solo pide
  /// permiso dentro del gesto). Devuelve si ya se pueden mostrar notificaciones; el registro del
  /// token sigue en segundo plano y se refleja en [status].
  Future<bool> enableFromTap() {
    final ask = WebNotify.ask();
    return ask.then((granted) {
      final uid = _uid ?? FirebaseAuth.instance.currentUser?.uid;
      if (granted && uid != null) {
        _write(_kOn(uid), '1');
        unawaited(_register(uid));
      } else {
        _refreshStatus();
      }
      return granted;
    });
  }

  /// Apaga los avisos push en este dispositivo (los avisos de la campana siguen).
  Future<void> disable() async {
    final uid = _uid ?? FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      _write(_kOn(uid), '0');
      final token = _read(_kToken);
      if (token != null && _read(_kTokenUid) == uid) {
        try {
          await _tokensOf(uid).doc(token).delete();
        } catch (e) {
          debugPrint('[Push] no se pudo borrar el token: $e');
        }
      }
    }
    await _deleteToken();
    _refreshStatus();
  }

  // ---------------------------------------------------------------------------

  static CollectionReference<Map<String, dynamic>> _tokensOf(String uid) =>
      FirebaseFirestore.instance.collection('users').doc(uid).collection('push_tokens');

  static String? get _permission => WebNotify.supported ? web.Notification.permission : null;

  static bool get _hasPushManager {
    try {
      return globalContext.has('PushManager') && (web.window.navigator as JSObject).has('serviceWorker');
    } catch (_) {
      return false;
    }
  }

  static bool get _standalone {
    try {
      return web.window.matchMedia('(display-mode: standalone)').matches ||
          ((web.window.navigator as JSObject).getProperty<JSBoolean?>('standalone'.toJS)?.toDart ?? false);
    } catch (_) {
      return false;
    }
  }

  static String get _platform {
    try {
      return pushPlatformOf(web.window.navigator.userAgent, maxTouchPoints: web.window.navigator.maxTouchPoints);
    } catch (_) {
      return 'web-desktop';
    }
  }

  void _refreshStatus() {
    if (status.value == PushStatus.working) return;
    status.value = _computeStatus();
  }

  PushStatus _computeStatus() {
    if (!kIsWeb || !configured) return PushStatus.unsupported;
    if (_platform == 'web-ios' && !_standalone) return PushStatus.needsInstall;
    if (!_hasPushManager || !WebNotify.supported) return PushStatus.unsupported;
    if (_permission == 'denied') return PushStatus.denied;
    final uid = _uid;
    if (uid != null && _permission == 'granted' && _read(_kOn(uid)) == '1') return PushStatus.on;
    return PushStatus.off;
  }

  Future<void> _register(String uid) async {
    if (!configured) return;
    status.value = PushStatus.working;
    try {
      final messaging = await _loadMessaging();
      if (messaging == null) {
        status.value = PushStatus.unsupported;
        return;
      }
      final reg = await _serviceWorker();
      final opts = JSObject()
        ..['vapidKey'] = kFcmVapidKey.toJS
        ..['serviceWorkerRegistration'] = reg;
      final module = await _module!;
      final token = (await module.callMethod<JSPromise<JSString>>('getToken'.toJS, messaging, opts).toDart).toDart;
      if (_uid != uid) return; // cambió la cuenta mientras tanto
      final now = DateTime.now().millisecondsSinceEpoch;
      final savedToken = _read(_kToken);
      final savedUid = _read(_kTokenUid);
      if (pushTokenNeedsSync(
        token: token,
        uid: uid,
        savedToken: savedToken,
        savedUid: savedUid,
        savedAtMs: int.tryParse(_read(_kSyncedAt) ?? ''),
        nowMs: now,
      )) {
        await _tokensOf(uid).doc(token).set({
          'token': token,
          'platform': _platform,
          'standalone': _standalone,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        if (savedToken != null && savedToken != token && savedUid == uid) {
          unawaited(_tokensOf(uid).doc(savedToken).delete().then((_) {}, onError: (_) {}));
        }
        _write(_kToken, token);
        _write(_kTokenUid, uid);
        _write(_kSyncedAt, '$now');
      }
      _write(_kOn(uid), '1');
      status.value = PushStatus.on;
    } catch (e) {
      debugPrint('[Push] no se pudo activar: $e');
      status.value = _permission == 'denied' ? PushStatus.denied : PushStatus.off;
    }
  }

  Future<void> _deleteToken() async {
    try {
      if (_read(_kToken) != null) {
        final messaging = await _loadMessaging();
        if (messaging != null) {
          await (await _module!).callMethod<JSPromise<JSAny?>>('deleteToken'.toJS, messaging).toDart;
        }
      }
    } catch (e) {
      debugPrint('[Push] no se pudo invalidar el token: $e');
    }
    _remove(_kToken);
    _remove(_kTokenUid);
    _remove(_kSyncedAt);
  }

  Future<JSObject>? _module;

  /// `getMessaging(app)` del SDK JS de FCM, o null si el navegador no tiene push.
  Future<JSObject?> _loadMessaging() => _messaging ??= () async {
        final core = globalContext.getProperty<JSObject?>('firebase_core'.toJS);
        if (core == null) return null;
        final version = core.getProperty<JSString?>('SDK_VERSION'.toJS)?.toDart;
        if (version == null) return null;
        _module = importModule('https://www.gstatic.com/firebasejs/$version/firebase-messaging.js'.toJS).toDart;
        final module = await _module!;
        final supported = (await module.callMethod<JSPromise<JSBoolean>>('isSupported'.toJS).toDart).toDart;
        if (!supported) return null;
        final app = core.callMethod<JSObject>('getApp'.toJS);
        return module.callMethod<JSObject>('getMessaging'.toJS, app);
      }()
          .catchError((Object e) {
        debugPrint('[Push] no cargó la mensajería: $e');
        _messaging = null;
        return null;
      });

  /// El service worker de la app (index.html lo registra; si aún no, se registra aquí).
  static Future<web.ServiceWorkerRegistration> _serviceWorker() async {
    final sw = web.window.navigator.serviceWorker;
    final existing = await sw.getRegistration('/').toDart;
    if (existing == null) await sw.register('/ohtli_sw.js'.toJS).toDart;
    return sw.ready.toDart;
  }

  /// Al tocar un aviso con Ohtli abierto en otra pantalla, ohtli_sw.js pide ir a la del aviso.
  void _listenServiceWorker() {
    try {
      if (!(web.window.navigator as JSObject).has('serviceWorker')) return;
      web.window.navigator.serviceWorker.addEventListener(
        'message',
        ((web.MessageEvent e) {
          final data = e.data;
          if (data == null || !data.isA<JSObject>()) return;
          final obj = data as JSObject;
          if (obj.getProperty<JSString?>('type'.toJS)?.toDart != 'ohtli:open') return;
          final url = obj.getProperty<JSString?>('url'.toJS)?.toDart;
          final uri = url == null ? null : Uri.tryParse(url);
          if (uri == null) return;
          AppUrl.instance.show(uri.hasQuery ? '${uri.path}?${uri.query}' : uri.path);
          AppUrl.instance.onExternal?.call(uri);
        }).toJS,
      );
    } catch (_) {}
  }

  static String? _read(String key) {
    try {
      return web.window.localStorage.getItem(key);
    } catch (_) {
      return null;
    }
  }

  static void _write(String key, String value) {
    try {
      web.window.localStorage.setItem(key, value);
    } catch (_) {}
  }

  static void _remove(String key) {
    try {
      web.window.localStorage.removeItem(key);
    } catch (_) {}
  }
}

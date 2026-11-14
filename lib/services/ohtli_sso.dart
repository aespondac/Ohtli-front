// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use, avoid_print

import 'dart:convert';
import 'dart:html' as html;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// SSO entre subdominios: una sola sesión de Ohtli para ohtli.quest y lab.ohtli.quest.
///
/// Firebase Auth guarda la sesión por origen. Para no pedir iniciar sesión otra vez
/// en cada subdominio, el subdominio sin sesión va a `https://ohtli.quest/sso`,
/// donde la app (con la sesión de siempre) pide al servidor un código de un solo uso
/// y vuelve con él en el fragmento (`#ohtli_sso=…`). El subdominio lo canjea por un
/// custom token y entra con la misma cuenta. Detalles y seguridad: functions/sso.js.
class OhtliSso {
  OhtliSso._();

  static const String mainHost = 'ohtli.quest';
  // El dominio principal se sirve en www (ohtli.quest redirige ahí con 301).
  static const String mainOrigin = 'https://www.ohtli.quest';
  static const Set<String> _mainHosts = {'ohtli.quest', 'www.ohtli.quest'};
  static const String _fragmentKey = 'ohtli_sso';
  static const String _attemptKey = 'ohtli_sso_attempt';
  static const String _pausedKey = 'ohtli_sso_paused';
  static const Duration _attemptWindow = Duration(minutes: 2);

  static String? _pendingCode;
  static bool _cancelled = false;

  static String get _host => kIsWeb ? (html.window.location.hostname ?? '').toLowerCase() : '';

  /// Estamos en un subdominio que participa del SSO (p. ej. lab.ohtli.quest).
  static bool get isSubdomain => _host.endsWith('.$mainHost') && !_mainHosts.contains(_host);

  /// Estamos en el dominio principal, que es quien emite los códigos.
  static bool get isMainHost => _mainHosts.contains(_host);

  /// Hay un código recibido de ohtli.quest pendiente de canjear.
  static bool get hasPendingCode => _pendingCode != null;

  /// Se llama en main() antes de runApp: toma el código del fragmento y lo quita de
  /// la URL (para que no quede en el historial ni lo lea el enrutador de la app).
  static void captureFromUrl() {
    if (!kIsWeb) return;
    try {
      final hash = html.window.location.hash;
      if (!hash.startsWith('#$_fragmentKey')) return;
      final params = Uri.splitQueryString(hash.substring(1));
      final code = params[_fragmentKey];
      if (code != null && code.isNotEmpty) _pendingCode = code;
      if (params.containsKey('${_fragmentKey}_cancel')) _cancelled = true;
      final loc = html.window.location;
      html.window.history.replaceState(null, '', '${loc.pathname}${loc.search}');
    } catch (e) {
      print('SSO: error reading fragment: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Subdominio
  // ---------------------------------------------------------------------------

  /// Canjea el código recibido e inicia sesión. Devuelve true si se inició sesión.
  static Future<bool> redeemPendingCode() async {
    final code = _pendingCode;
    _pendingCode = null;
    if (code == null) return false;
    try {
      final response = await html.HttpRequest.request(
        '/__sso/redeem',
        method: 'POST',
        sendData: jsonEncode({'code': code}),
        requestHeaders: {'Content-Type': 'application/json'},
      );
      final token = (jsonDecode(response.responseText ?? '{}') as Map)['token'];
      if (token is! String || token.isEmpty) return false;
      await FirebaseAuth.instance.setPersistence(Persistence.LOCAL);
      await FirebaseAuth.instance.signInWithCustomToken(token);
      _clearAttempt();
      _setPaused(false);
      return true;
    } catch (e) {
      print('SSO: could not redeem code: $e');
      return false;
    }
  }

  /// Si conviene, manda al usuario a ohtli.quest para traer su sesión.
  /// Devuelve true si se inició la redirección (la página está por cambiar).
  static bool maybeAutoRedirect() {
    if (!isSubdomain || _cancelled || _isPaused || _recentlyAttempted) return false;
    continueWithOhtli();
    return true;
  }

  /// Botón "Continuar con tu cuenta de Ohtli" (o redirección automática).
  static void continueWithOhtli() {
    if (!kIsWeb) return;
    _setPaused(false);
    try {
      html.window.sessionStorage[_attemptKey] = DateTime.now().millisecondsSinceEpoch.toString();
    } catch (_) {}
    final loc = html.window.location;
    final back = '${loc.origin}${loc.pathname}${loc.search}';
    html.window.location.assign('$mainOrigin/sso?return=${Uri.encodeComponent(back)}');
  }

  /// "Cambiar de cuenta" en un subdominio: cierra la sesión local y va al selector
  /// de cuentas de ohtli.quest, que vuelve con la cuenta elegida.
  static Future<void> switchAccountOnSubdomain() async {
    if (!isSubdomain) return;
    await FirebaseAuth.instance.signOut();
    continueWithOhtli();
  }

  /// Al cerrar sesión en el subdominio: no volver a entrar solo con la sesión de
  /// ohtli.quest hasta que la persona lo pida (botón) o inicie sesión.
  static void onSignedOutOnSubdomain() {
    if (isSubdomain) _setPaused(true);
  }

  static void onSignedInOnSubdomain() {
    if (isSubdomain) {
      _setPaused(false);
      _clearAttempt();
    }
  }

  static bool get _isPaused {
    try {
      return html.window.localStorage[_pausedKey] == '1';
    } catch (_) {
      return false;
    }
  }

  static void _setPaused(bool paused) {
    try {
      if (paused) {
        html.window.localStorage[_pausedKey] = '1';
      } else {
        html.window.localStorage.remove(_pausedKey);
      }
    } catch (_) {}
  }

  /// Evita un ciclo de redirecciones si ohtli.quest volvió sin código.
  static bool get _recentlyAttempted {
    try {
      final raw = html.window.sessionStorage[_attemptKey];
      final at = raw == null ? null : int.tryParse(raw);
      if (at == null) return false;
      return DateTime.now().millisecondsSinceEpoch - at < _attemptWindow.inMilliseconds;
    } catch (_) {
      return false;
    }
  }

  static void _clearAttempt() {
    try {
      html.window.sessionStorage.remove(_attemptKey);
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // Dominio principal (ohtli.quest/sso)
  // ---------------------------------------------------------------------------

  /// Valida el destino de `?return=`: solo https://<sub>.ohtli.quest.
  static Uri? parseReturnTarget(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final uri = Uri.tryParse(raw);
    if (uri == null || uri.scheme != 'https' || uri.hasPort || uri.userInfo.isNotEmpty) return null;
    final host = uri.host.toLowerCase();
    if (!host.endsWith('.$mainHost') || _mainHosts.contains(host)) return null;
    return uri.removeFragment();
  }

  /// Pide al servidor un código para [target] con la sesión actual y vuelve allá.
  static Future<void> issueAndReturn(Uri target) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('Sin sesión');
    final idToken = await user.getIdToken();
    final response = await html.HttpRequest.request(
      '/__sso/issue',
      method: 'POST',
      sendData: jsonEncode({'target': target.toString()}),
      requestHeaders: {'Content-Type': 'application/json', 'Authorization': 'Bearer $idToken'},
    );
    final code = (jsonDecode(response.responseText ?? '{}') as Map)['code'];
    if (code is! String || code.isEmpty) throw StateError('Respuesta sin código');
    html.window.location.replace('$target#$_fragmentKey=$code');
  }

  /// Tras cambiar de cuenta en el selector de ohtli.quest/sso, la página se recarga;
  /// esta marca hace que continúe sola al subdominio con la cuenta elegida.
  static const String _continueAfterSwitchKey = 'ohtli_sso_continue';

  static void markContinueAfterSwitch() {
    try {
      html.window.sessionStorage[_continueAfterSwitchKey] = '1';
    } catch (_) {}
  }

  static bool takeContinueAfterSwitch() {
    try {
      return html.window.sessionStorage.remove(_continueAfterSwitchKey) != null;
    } catch (_) {
      return false;
    }
  }

  /// "Cancelar" en ohtli.quest: vuelve al subdominio para iniciar sesión ahí.
  static void cancelAndReturn(Uri target) {
    html.window.location.replace('$target#${_fragmentKey}_cancel=1');
  }
}

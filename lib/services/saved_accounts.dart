// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use, avoid_print

import 'dart:convert';
import 'dart:html' as html;
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Una cuenta recordada en este navegador (solo datos para mostrarla; nada secreto).
class SavedAccount {
  final String uid;
  final String email;
  final String name;
  final String? photoURL;

  const SavedAccount({required this.uid, required this.email, required this.name, this.photoURL});

  String get initials {
    final source = name.trim().isNotEmpty ? name : email;
    return source.split(RegExp(r'[\s@.]+')).where((w) => w.isNotEmpty).take(2).map((w) => w[0].toUpperCase()).join();
  }

  Map<String, dynamic> toJson() => {'uid': uid, 'email': email, 'name': name, 'photoURL': photoURL};

  static SavedAccount? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final uid = raw['uid'];
    if (uid is! String || uid.isEmpty) return null;
    return SavedAccount(
      uid: uid,
      email: (raw['email'] as String?) ?? '',
      name: (raw['name'] as String?) ?? '',
      photoURL: raw['photoURL'] as String?,
    );
  }
}

enum SwitchAccountResult { switched, expired, failed }

/// Varias cuentas en el mismo navegador.
///
/// Firebase Auth solo tiene una sesión activa por app. Para poder cambiar sin volver
/// a escribir la contraseña, cada cuenta que inicia sesión con "Recordar sesión"
/// deja una copia de su sesión en una app de Firebase con nombre propio
/// (`ohtli-acct-<uid>`), que el SDK guarda en IndexedDB igual que la sesión normal.
/// Cambiar de cuenta = copiar esa sesión a la app principal (`updateCurrentUser`).
///
/// No se guardan contraseñas. Si la sesión guardada caduca (p. ej. cambiaste la
/// contraseña), la cuenta se olvida y hay que iniciar sesión de nuevo.
class SavedAccounts {
  SavedAccounts._();

  static const String _storageKey = 'ohtli_saved_accounts';
  static const int maxAccounts = 5;

  /// Aumenta cada vez que cambia la lista, para redibujar el menú.
  static final ValueNotifier<int> changes = ValueNotifier<int>(0);

  // ---------------------------------------------------------------------------
  // Lista local
  // ---------------------------------------------------------------------------

  static List<SavedAccount> list() {
    if (!kIsWeb) return const [];
    try {
      final raw = html.window.localStorage[_storageKey];
      if (raw == null || raw.isEmpty) return const [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded.map(SavedAccount.fromJson).whereType<SavedAccount>().toList();
    } catch (e) {
      print('Error reading saved accounts: $e');
      return const [];
    }
  }

  static bool isSaved(String uid) => list().any((a) => a.uid == uid);

  static void _write(List<SavedAccount> accounts) {
    try {
      html.window.localStorage[_storageKey] = jsonEncode(accounts.map((a) => a.toJson()).toList());
    } catch (e) {
      print('Error writing saved accounts: $e');
    }
    changes.value++;
  }

  // ---------------------------------------------------------------------------
  // SDK de Firebase (JS) que ya carga FlutterFire
  // ---------------------------------------------------------------------------

  static JSObject get _core => globalContext['firebase_core'] as JSObject;
  static JSObject get _authModule => globalContext['firebase_auth'] as JSObject;

  static String _appName(String uid) => 'ohtli-acct-$uid';

  static JSObject _defaultAuth() => _authModule.callMethod<JSObject>('getAuth'.toJS);

  static JSObject _accountAuth(String uid) {
    JSObject app;
    try {
      app = _core.callMethod<JSObject>('getApp'.toJS, _appName(uid).toJS);
    } catch (_) {
      final defaultApp = _core.callMethod<JSObject>('getApp'.toJS);
      app = _core.callMethod<JSObject>('initializeApp'.toJS, defaultApp['options'], _appName(uid).toJS);
    }
    return _authModule.callMethod<JSObject>('getAuth'.toJS, app);
  }

  static Future<void> _ready(JSObject auth) async {
    // authStateReady espera a que el SDK lea la sesión guardada en IndexedDB.
    if (auth.has('authStateReady')) {
      await auth.callMethod<JSPromise>('authStateReady'.toJS).toDart;
    }
  }

  static JSObject? _currentUser(JSObject auth) {
    final user = auth['currentUser'];
    return (user == null || user.isUndefinedOrNull) ? null : user as JSObject;
  }

  static Future<void> _deleteApp(String uid) async {
    try {
      final app = _core.callMethod<JSObject>('getApp'.toJS, _appName(uid).toJS);
      await _core.callMethod<JSPromise>('deleteApp'.toJS, app).toDart;
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // Operaciones
  // ---------------------------------------------------------------------------

  /// Recuerda la cuenta con la que se acaba de iniciar sesión ("Recordar sesión").
  static Future<void> remember(User user) async {
    if (!kIsWeb) return;
    try {
      final current = _currentUser(_defaultAuth());
      if (current == null) return;
      final auth = _accountAuth(user.uid);
      await _ready(auth);
      await _authModule.callMethod<JSPromise>('updateCurrentUser'.toJS, auth, current).toDart;

      final accounts = list().where((a) => a.uid != user.uid).toList();
      accounts.insert(
        0,
        SavedAccount(uid: user.uid, email: user.email ?? '', name: user.displayName ?? '', photoURL: user.photoURL),
      );
      // Si se pasa del límite, se olvida la que lleva más tiempo sin usarse.
      while (accounts.length > maxAccounts) {
        final dropped = accounts.removeLast();
        await _signOutAccount(dropped.uid);
      }
      _write(accounts);
    } catch (e) {
      print('Error remembering account: $e');
    }
  }

  static Future<void> _signOutAccount(String uid) async {
    try {
      final auth = _accountAuth(uid);
      await _ready(auth);
      await _authModule.callMethod<JSPromise>('signOut'.toJS, auth).toDart;
    } catch (e) {
      print('Error signing out saved account: $e');
    }
    await _deleteApp(uid);
  }

  /// Olvida una cuenta en este navegador (al cerrar su sesión).
  static Future<void> forget(String uid) async {
    if (!kIsWeb) return;
    await _signOutAccount(uid);
    _write(list().where((a) => a.uid != uid).toList());
  }

  /// Cambia la sesión activa a una cuenta recordada. Tras [SwitchAccountResult.switched]
  /// conviene recargar la página para que toda la app arranque con la nueva cuenta.
  static Future<SwitchAccountResult> switchTo(String uid) async {
    if (!kIsWeb) return SwitchAccountResult.failed;
    try {
      final auth = _accountAuth(uid);
      await _ready(auth);
      final user = _currentUser(auth);
      if (user == null) {
        await forget(uid);
        return SwitchAccountResult.expired;
      }
      // Comprueba que la sesión siga siendo válida (forzando un token nuevo).
      try {
        await _authModule.callMethod<JSPromise>('getIdToken'.toJS, user, true.toJS).toDart;
      } catch (_) {
        await forget(uid);
        return SwitchAccountResult.expired;
      }
      await FirebaseAuth.instance.setPersistence(Persistence.LOCAL);
      await _authModule.callMethod<JSPromise>('updateCurrentUser'.toJS, _defaultAuth(), user).toDart;

      // La cuenta elegida pasa al principio de la lista.
      final accounts = list();
      final chosen = accounts.where((a) => a.uid == uid).toList();
      _write([...chosen, ...accounts.where((a) => a.uid != uid)]);
      return SwitchAccountResult.switched;
    } catch (e) {
      print('Error switching account: $e');
      return SwitchAccountResult.failed;
    }
  }
}

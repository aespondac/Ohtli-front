// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use, avoid_print

import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Una cuenta recordada en este navegador (solo datos para mostrarla).
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
/// Firebase Auth tiene una sola sesión activa. Para cambiar sin volver a escribir
/// la contraseña, al recordar una cuenta se guarda el estado de su sesión tal como
/// lo persiste el propio SDK (`user.toJSON()`: uid, perfil y tokens). Cambiar de
/// cuenta = poner ese estado como la sesión guardada de la app (localStorage, donde
/// la guarda `Persistence.LOCAL`) y recargar: al
/// arrancar, Firebase la carga y la valida con App Check como cualquier sesión.
///
/// Por qué no se usan apps de Firebase separadas por cuenta: App Check es
/// obligatorio para Auth en este proyecto y esas apps no tienen App Check, así que
/// Firebase rechazaba sus sesiones al validarlas y el cambio fallaba ("caducó").
///
/// No se guardan contraseñas. El estado de sesión vive en este navegador, igual que
/// la sesión normal de Firebase. Si una cuenta se revoca (p. ej. cambiaste la
/// contraseña), al cambiar a ella no entra y se olvida.
class SavedAccounts {
  SavedAccounts._();

  static const String _listKey = 'ohtli_saved_accounts';
  static const String _sessionPrefix = 'ohtli_saved_session_';
  static const String _pendingSwitchKey = 'ohtli_switch_target';
  static const int maxAccounts = 5;

  // Persistencia del SDK de Firebase Auth (IndexedDB).
  static const String _dbName = 'firebaseLocalStorageDb';
  static const String _dbStore = 'firebaseLocalStorage';
  static const String _dbKeyPath = 'fbase_key';

  /// Aumenta cada vez que cambia la lista, para redibujar el menú.
  static final ValueNotifier<int> changes = ValueNotifier<int>(0);

  // ---------------------------------------------------------------------------
  // Lista local
  // ---------------------------------------------------------------------------

  static List<SavedAccount> list() {
    if (!kIsWeb) return const [];
    try {
      final raw = html.window.localStorage[_listKey];
      if (raw == null || raw.isEmpty) return const [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded.map(SavedAccount.fromJson).whereType<SavedAccount>().toList();
    } catch (e) {
      print('Error reading saved accounts: $e');
      return const [];
    }
  }

  /// La cuenta está recordada y tiene su sesión guardada (se puede cambiar a ella).
  static bool isSaved(String uid) => list().any((a) => a.uid == uid) && _readSession(uid) != null;

  static void _writeList(List<SavedAccount> accounts) {
    try {
      html.window.localStorage[_listKey] = jsonEncode(accounts.map((a) => a.toJson()).toList());
    } catch (e) {
      print('Error writing saved accounts: $e');
    }
    changes.value++;
  }

  static String? _readSession(String uid) {
    try {
      final raw = html.window.localStorage['$_sessionPrefix$uid'];
      return (raw == null || raw.isEmpty) ? null : raw;
    } catch (_) {
      return null;
    }
  }

  static void _writeSession(String uid, String? json) {
    try {
      if (json == null) {
        html.window.localStorage.remove('$_sessionPrefix$uid');
      } else {
        html.window.localStorage['$_sessionPrefix$uid'] = json;
      }
    } catch (e) {
      print('Error writing saved session: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // SDK de Firebase (JS) que ya carga FlutterFire
  // ---------------------------------------------------------------------------

  static JSObject get _core => globalContext['firebase_core'] as JSObject;
  static JSObject get _authModule => globalContext['firebase_auth'] as JSObject;

  static JSObject _defaultApp() => _core.callMethod<JSObject>('getApp'.toJS);

  /// Clave con la que el SDK guarda la sesión de la app principal.
  static String _defaultUserKey() {
    final options = _defaultApp()['options'] as JSObject;
    final apiKey = (options['apiKey'] as JSString).toDart;
    return 'firebase:authUser:$apiKey:[DEFAULT]';
  }

  /// Estado de la sesión actual tal como lo guarda el SDK (`user.toJSON()`).
  static String? _currentSessionJson(String expectedUid) {
    final auth = _authModule.callMethod<JSObject>('getAuth'.toJS);
    final user = auth['currentUser'];
    if (user == null || user.isUndefinedOrNull) return null;
    final blob = (user as JSObject).callMethod<JSObject>('toJSON'.toJS);
    final json = (globalContext['JSON'] as JSObject).callMethod<JSString>('stringify'.toJS, blob).toDart;
    final decoded = jsonDecode(json);
    if (decoded is! Map || decoded['uid'] != expectedUid) return null;
    return json;
  }

  /// Espera a que termine una petición/transacción de IndexedDB.
  static Future<JSAny?> _await(JSObject target, {String ok = 'onsuccess'}) {
    final completer = Completer<JSAny?>();
    target[ok] = ((JSAny? _) {
      if (!completer.isCompleted) completer.complete(target.has('result') ? target['result'] : null);
    }).toJS;
    target['onerror'] = ((JSAny? _) {
      if (!completer.isCompleted) completer.completeError(StateError('IndexedDB: ${target['error']}'));
    }).toJS;
    return completer.future;
  }

  static Future<JSObject> _openAuthDb() async {
    // Misma base y versión que usa el SDK; si no existiera, se crea igual que él.
    final request = (globalContext['indexedDB'] as JSObject).callMethod<JSObject>('open'.toJS, _dbName.toJS, 1.toJS);
    request['onupgradeneeded'] = ((JSAny? _) {
      final db = request['result'] as JSObject;
      final names = db['objectStoreNames'] as JSObject;
      if (!names.callMethod<JSBoolean>('contains'.toJS, _dbStore.toJS).toDart) {
        db.callMethod('createObjectStore'.toJS, _dbStore.toJS, {'keyPath': _dbKeyPath}.jsify());
      }
    }).toJS;
    return (await _await(request)) as JSObject;
  }

  static JSObject _store(JSObject db, JSObject tx) => tx.callMethod<JSObject>('objectStore'.toJS, _dbStore.toJS);

  /// Deja [blob] como la sesión guardada de la app principal. `Persistence.LOCAL`
  /// en web es localStorage, que es lo primero que revisa el SDK al arrancar; las
  /// copias en IndexedDB o sessionStorage se borran para que no compitan.
  static Future<void> _writeDefaultSession(Map<String, dynamic> blob) async {
    final key = _defaultUserKey();
    html.window.localStorage[key] = jsonEncode(blob);
    try {
      html.window.sessionStorage.remove(key);
    } catch (_) {}
    try {
      final db = await _openAuthDb();
      try {
        final tx = db.callMethod<JSObject>('transaction'.toJS, _dbStore.toJS, 'readwrite'.toJS);
        final done = _await(tx, ok: 'oncomplete');
        _store(db, tx).callMethod('delete'.toJS, key.toJS);
        await done;
      } finally {
        db.callMethod('close'.toJS);
      }
    } catch (e) {
      print('Error clearing IndexedDB session copy: $e');
    }
  }

  /// Limpia las sesiones de la versión anterior (apps `ohtli-acct-<uid>`).
  static Future<void> _cleanupLegacy() async {
    try {
      final db = await _openAuthDb();
      try {
        final tx = db.callMethod<JSObject>('transaction'.toJS, _dbStore.toJS, 'readwrite'.toJS);
        final done = _await(tx, ok: 'oncomplete');
        final store = _store(db, tx);
        final keysRequest = store.callMethod<JSObject>('getAllKeys'.toJS);
        keysRequest['onsuccess'] = ((JSAny? _) {
          final keys = (keysRequest['result'] as JSArray<JSAny?>).toDart;
          for (final key in keys) {
            if (key.isA<JSString>() && (key as JSString).toDart.contains(':ohtli-acct-')) {
              store.callMethod('delete'.toJS, key);
            }
          }
        }).toJS;
        await done;
      } finally {
        db.callMethod('close'.toJS);
      }
    } catch (e) {
      print('Error cleaning legacy saved accounts: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Operaciones
  // ---------------------------------------------------------------------------

  /// Recuerda la cuenta con la sesión actual ("Recordar sesión" o "Recordar esta cuenta").
  /// Devuelve true si quedó lista para cambiar a ella después.
  static Future<bool> remember(User user) async {
    if (!kIsWeb) return false;
    try {
      final session = _currentSessionJson(user.uid);
      if (session == null) return false;
      _writeSession(user.uid, session);

      final accounts = list().where((a) => a.uid != user.uid).toList();
      accounts.insert(
        0,
        SavedAccount(uid: user.uid, email: user.email ?? '', name: user.displayName ?? '', photoURL: user.photoURL),
      );
      // Si se pasa del límite, se olvida la que lleva más tiempo sin usarse.
      while (accounts.length > maxAccounts) {
        _writeSession(accounts.removeLast().uid, null);
      }
      _writeList(accounts);
      return true;
    } catch (e) {
      print('Error remembering account: $e');
      return false;
    }
  }

  /// Al arrancar con sesión: si la cuenta está recordada, actualiza su sesión
  /// guardada y su nombre/foto. También limpia restos de la versión anterior.
  static Future<void> syncCurrent(User user) async {
    if (!kIsWeb) return;
    if (list().any((a) => a.uid == user.uid)) {
      await remember(user);
    }
    // Las cuentas recordadas con la versión anterior no tienen sesión guardada: no se
    // puede cambiar a ellas, así que se quitan (al volver a entrar con "Recordar
    // sesión" reaparecen).
    final all = list();
    final usable = all.where((a) => _readSession(a.uid) != null).toList();
    if (usable.length != all.length) _writeList(usable);
    await _cleanupLegacy();
  }

  /// Olvida una cuenta en este navegador (al cerrar su sesión).
  static Future<void> forget(String uid) async {
    if (!kIsWeb) return;
    _writeSession(uid, null);
    _writeList(list().where((a) => a.uid != uid).toList());
  }

  /// Pone como sesión activa una cuenta recordada. Tras [SwitchAccountResult.switched]
  /// el llamador debe recargar la página: al arrancar, Firebase carga esa sesión.
  static Future<SwitchAccountResult> switchTo(String uid) async {
    if (!kIsWeb) return SwitchAccountResult.failed;
    final raw = _readSession(uid);
    if (raw == null) {
      await forget(uid);
      return SwitchAccountResult.expired;
    }
    try {
      final blob = jsonDecode(raw);
      if (blob is! Map<String, dynamic> || blob['uid'] != uid) {
        await forget(uid);
        return SwitchAccountResult.expired;
      }
      // Guarda la sesión más reciente de la cuenta actual para poder volver a ella.
      final current = FirebaseAuth.instance.currentUser;
      if (current != null && list().any((a) => a.uid == current.uid)) {
        final session = _currentSessionJson(current.uid);
        if (session != null) _writeSession(current.uid, session);
      }

      await FirebaseAuth.instance.setPersistence(Persistence.LOCAL);
      // Cerrar la sesión local evita que el SDK sobrescriba lo que vamos a escribir
      // (no revoca nada en el servidor: la sesión guardada de esta cuenta sigue valiendo).
      await FirebaseAuth.instance.signOut();
      blob['appName'] = '[DEFAULT]';
      await _writeDefaultSession(blob);

      html.window.sessionStorage[_pendingSwitchKey] = uid;
      final accounts = list();
      _writeList([...accounts.where((a) => a.uid == uid), ...accounts.where((a) => a.uid != uid)]);
      return SwitchAccountResult.switched;
    } catch (e) {
      print('Error switching account: $e');
      return SwitchAccountResult.failed;
    }
  }

  /// Primer estado de sesión tras recargar por un cambio de cuenta. Si la cuenta
  /// elegida no entró (sesión revocada), la olvida y devuelve su nombre para avisar.
  static String? checkPendingSwitch(User? user) {
    if (!kIsWeb) return null;
    try {
      final target = html.window.sessionStorage.remove(_pendingSwitchKey);
      if (target == null || user?.uid == target) return null;
      final account = list().where((a) => a.uid == target).firstOrNull;
      forget(target);
      return account == null ? 'esa cuenta' : (account.name.isNotEmpty ? account.name : account.email);
    } catch (_) {
      return null;
    }
  }
}

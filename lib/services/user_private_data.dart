import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'profile_directory.dart';

/// Datos personales del usuario que NO deben ser públicos (contacto, direcciones,
/// privacidad y perfil de gustos).
///
/// El documento `users/{uid}` es el perfil social (nombre, foto, título, amigos) y
/// cualquiera puede leerlo. Los datos sensibles viven en `users/{uid}/private/account`,
/// que solo su dueño puede leer o escribir (ver firestore.rules).
///
/// Las cuentas creadas antes de este cambio todavía pueden tener estos campos en el
/// documento público: [watch] los combina mientras tanto y, al abrir la app, los mueve
/// al documento privado y los borra del público ([migrateLegacyFields]).
class UserPrivateData {
  UserPrivateData._();

  /// Campos que se guardan en el documento privado.
  static const Set<String> fields = {
    'email',
    'phone',
    'addresses',
    'privacy_share',
    'privacy_notifications',
    'privacy_public',
    // Dejar que me encuentren por correo o teléfono (si el perfil es público) y los
    // hashes que publiqué en contact_directory (para retirarlos)
    'contact_discoverable',
    'phone_verified',
    'directory_hashes',
    // Perfil de gustos (onboarding + vector de 768 dimensiones del motor Yollotl)
    'cultural_profile',
    'taste_axes',
    'taste_axes_preview',
    'taste_recipe',
    'taste_vector',
    'taste_vector_dim',
    'taste_model',
    'taste_updated_at',
    'embedding_vector',
    // Copia de la marca de baja para poder restaurar la cuenta por correo
    'isDeleted',
  };

  static FirebaseFirestore get _db => FirebaseFirestore.instance;

  static DocumentReference<Map<String, dynamic>> publicRef(String uid) =>
      _db.collection('users').doc(uid);

  static DocumentReference<Map<String, dynamic>> privateRef(String uid) =>
      _db.collection('users').doc(uid).collection('private').doc('account');

  /// Separa un mapa de cambios en la parte pública y la privada.
  static ({Map<String, dynamic> public, Map<String, dynamic> private}) split(
      Map<String, dynamic> data) {
    final pub = <String, dynamic>{};
    final priv = <String, dynamic>{};
    data.forEach((key, value) {
      if (fields.contains(key)) {
        priv[key] = value;
      } else {
        pub[key] = value;
      }
    });
    return (public: pub, private: priv);
  }

  /// Guarda [data] repartiendo cada campo en el documento que le corresponde.
  /// `isDeleted` se escribe en ambos: el perfil público lo usa para ocultar la cuenta.
  static Future<void> save(String uid, Map<String, dynamic> data) async {
    final parts = split(data);
    final pub = Map<String, dynamic>.from(parts.public);
    if (data.containsKey('isDeleted')) pub['isDeleted'] = data['isDeleted'];
    // Los demás no pueden leer el documento privado: el perfil público lleva una marca
    // con la preferencia "Perfil público" para que la app oculte amigos y crónicas.
    if (data['privacy_public'] is bool) {
      pub['profilePrivate'] = data['privacy_public'] == false;
    }
    final futures = <Future<void>>[];
    if (pub.isNotEmpty) {
      futures.add(publicRef(uid).set(pub, SetOptions(merge: true)));
    }
    if (parts.private.isNotEmpty) {
      futures.add(privateRef(uid).set({
        ...parts.private,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true)));
    }
    await Future.wait(futures);
    // Correo y teléfono en el directorio solo mientras el perfil sea público y se permita.
    if (data.containsKey('phone') || data.containsKey('privacy_public') || data.containsKey('contact_discoverable')) {
      unawaited(ProfileDirectory.sync(uid));
    }
  }

  /// Lee una sola vez el documento privado (con respaldo en los campos antiguos).
  static Future<Map<String, dynamic>> get(String uid) async {
    final results = await Future.wait([publicRef(uid).get(), privateRef(uid).get()]);
    return _merge(results[0].data(), results[1].data());
  }

  /// Escucha perfil público + privado combinados. Emite `null` si el perfil público
  /// todavía no existe (cuenta nueva).
  static Stream<Map<String, dynamic>?> watch(String uid) {
    late StreamController<Map<String, dynamic>?> controller;
    StreamSubscription? pubSub;
    StreamSubscription? privSub;
    Map<String, dynamic>? pub;
    Map<String, dynamic>? priv;
    bool pubLoaded = false;
    bool privLoaded = false;
    bool migrated = false;

    void emit() {
      if (!pubLoaded || !privLoaded) return;
      if (!migrated && pub != null) {
        migrated = true;
        migrateLegacyFields(uid, pub!, priv);
      }
      controller.add(pub == null ? null : _merge(pub, priv));
    }

    controller = StreamController<Map<String, dynamic>?>(
      onListen: () {
        pubSub = publicRef(uid).snapshots().listen((s) {
          pub = s.data();
          pubLoaded = true;
          emit();
        }, onError: controller.addError);
        privSub = privateRef(uid).snapshots().listen((s) {
          priv = s.data();
          privLoaded = true;
          emit();
        }, onError: (Object e) {
          // Sin acceso al privado (p. ej. reglas aún no desplegadas): seguir con el público
          debugPrint('[UserPrivateData] privado no disponible: $e');
          privLoaded = true;
          emit();
        });
      },
      onCancel: () async {
        await pubSub?.cancel();
        await privSub?.cancel();
      },
    );
    return controller.stream;
  }

  /// Mueve los campos sensibles que sigan en el perfil público al documento privado
  /// (sin pisar lo que ya exista ahí) y los borra del público.
  static Future<void> migrateLegacyFields(
    String uid,
    Map<String, dynamic> publicData,
    Map<String, dynamic>? privateData,
  ) async {
    final legacy = <String, dynamic>{};
    for (final key in fields) {
      if (key == 'isDeleted') continue; // la marca pública se conserva
      if (publicData.containsKey(key)) legacy[key] = publicData[key];
    }
    // "Perfil público" antes no tenía efecto y venía apagado por defecto: al migrar,
    // todos los perfiles quedan públicos hasta que el usuario decida otra cosa.
    final hadLegacyPrivacy = legacy.remove('privacy_public') != null;
    if (legacy.isEmpty && !hadLegacyPrivacy) return;
    try {
      final toCopy = <String, dynamic>{
        for (final e in legacy.entries)
          if (privateData == null || !privateData.containsKey(e.key)) e.key: e.value,
      };
      if (toCopy.isNotEmpty) {
        await privateRef(uid).set({
          ...toCopy,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
      await publicRef(uid).update({
        for (final key in legacy.keys) key: FieldValue.delete(),
        if (hadLegacyPrivacy) 'privacy_public': FieldValue.delete(),
      });
      debugPrint('[UserPrivateData] campos privados movidos: ${legacy.keys.join(', ')}');
    } catch (e) {
      debugPrint('[UserPrivateData] no se pudieron mover los campos privados: $e');
    }
  }

  /// Perfil público con los campos privados encima (el privado manda).
  static Map<String, dynamic> _merge(
      Map<String, dynamic>? pub, Map<String, dynamic>? priv) {
    final merged = <String, dynamic>{...?pub};
    // El valor antiguo de "Perfil público" en el documento público era solo el valor por
    // defecto (no tenía efecto): no se toma como una elección del usuario.
    merged.remove('privacy_public');
    if (priv != null) {
      for (final key in fields) {
        if (key == 'isDeleted') continue;
        if (priv.containsKey(key)) merged[key] = priv[key];
      }
    }
    return merged;
  }
}

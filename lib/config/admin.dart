import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Superusuario de Ohtli: aprueba lugares sugeridos y publica las notas de versión.
///
/// Debe coincidir con `isSuperUser()` en firestore.rules: las reglas son las que
/// realmente protegen los datos; esta comprobación solo decide qué se muestra.
const String kSuperUserEmail = 'daniesponda120@gmail.com';

bool isSuperUserEmail(String? email) => (email ?? '').trim().toLowerCase() == kSuperUserEmail;

bool isSuperUser([User? user]) => isSuperUserEmail((user ?? FirebaseAuth.instance.currentUser)?.email);

/// UID del superusuario, para encontrar sus publicaciones (p. ej. las notas de
/// versión en Explorar) sin depender de que los perfiles de `users` sean públicos.
///
/// Se guarda en `app_config/editorial` (lectura pública, solo el superusuario
/// escribe): cada vez que el superusuario usa la app lo publica ahí.
class SuperUserDirectory {
  SuperUserDirectory._();

  static final DocumentReference<Map<String, dynamic>> _doc =
      FirebaseFirestore.instance.collection('app_config').doc('editorial');
  static Future<String?>? _uid;

  static Future<String?> uid() {
    final current = FirebaseAuth.instance.currentUser;
    if (current != null && isSuperUser(current)) {
      registerCurrentSuperUser();
      return Future.value(current.uid);
    }
    return _uid ??= _doc.get().timeout(const Duration(seconds: 10)).then((d) => d.data()?['superUserUid'] as String?).catchError((_) {
      _uid = null; // permite reintentar más tarde
      return null;
    });
  }

  static bool _registered = false;

  /// Si la sesión es del superusuario, publica su UID (una vez por sesión de la app).
  static void registerCurrentSuperUser() {
    final current = FirebaseAuth.instance.currentUser;
    if (_registered || current == null || !isSuperUser(current)) return;
    _registered = true;
    _doc.set({'superUserUid': current.uid, 'updatedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true)).catchError((_) {
      _registered = false;
    });
  }
}

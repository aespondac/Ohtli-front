import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:web/web.dart' as web;

import 'public_profiles.dart';
import 'photo_storage.dart';

/// Foto de perfil: se sube a Storage (users/{uid}/profile.jpg) y su URL queda en users/{uid},
/// en el perfil público y en Firebase Auth. Lo mismo que hace Cuenta, para usarlo también en el
/// onboarding.
class ProfilePhotoService {
  ProfilePhotoService._();

  /// Entró con Google (su foto viene de ahí, pero la puede cambiar).
  static bool get signedInWithGoogle =>
      FirebaseAuth.instance.currentUser?.providerData.any((p) => p.providerId == 'google.com') ?? false;

  /// Sube la foto recortada (data URI o base64 de un JPEG) y devuelve su URL.
  static Future<String> upload(String base64Jpeg) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('Sin sesión');
    // replaces: la URL lleva versión para que el navegador no siga mostrando la foto anterior
    final url = await PhotoStorage.uploadDataUrl('users/${user.uid}/profile.jpg', base64Jpeg, replaces: true);
    await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .set({'photoURL': url, 'updatedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
    await PublicProfiles.mirror(user.uid, {'photoURL': url});
    try {
      web.window.localStorage.setItem('ohtli_profile_pic_${user.uid}', url);
    } catch (_) {}
    try {
      await user.updatePhotoURL(url);
      await user.reload();
    } catch (_) {}
    return url;
  }
}

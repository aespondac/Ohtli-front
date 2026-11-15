import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../services/user_private_data.dart';
import '../services/social_graph.dart';
import 'package:http/http.dart' as http;

class UserProfileHelper {
  /// Fetches bytes from a Google photo URL using a native web request
  static Future<Uint8List?> fetchUrlBytes(String url) async {
    if (!kIsWeb) return null;
    try {
      final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 3));
      if (response.statusCode != 200) return null;
      return response.bodyBytes;
    } catch (e) {
      print("Error fetching URL bytes natively: $e");
      return null;
    }
  }

  /// Restores a deleted profile or initializes a new one.
  /// Checks if a user with the same email has been flagged as 'isDeleted' in Firestore.
  /// If found, copies the old profile data (including saved addresses, settings, and phone)
  /// to the new user document, resets the deletion flags, and purges the old document.
  static Future<void> syncAndRestoreProfile(
    User user, {
    String? customDisplayName,
  }) async {
    final email = user.email ?? '';
    final incomingName = customDisplayName ?? user.displayName ?? '';

    final firestore = FirebaseFirestore.instance;
    final docRef = firestore.collection('users').doc(user.uid);

    // 1. Get the current active document first if it exists
    DocumentSnapshot? currentDoc;
    try {
      currentDoc = await docRef.get();
    } catch (e) {
      print("Error fetching current user document: $e");
    }
    // Perfil público + datos privados (users/{uid}/private/account) combinados
    Map<String, dynamic>? currentData = currentDoc?.data() as Map<String, dynamic>?;
    if (currentData != null) {
      try {
        currentData = await UserPrivateData.get(user.uid);
      } catch (e) {
        print("Error fetching private user data: $e");
      }
    }

    // 2. Check if there is an existing deleted account with the same email to restore.
    // El correo vive en el documento privado; las reglas solo permiten esta consulta
    // si el correo coincide con el de la sesión y está verificado.
    String? oldUid;
    Map<String, dynamic>? oldData;

    if (email.isNotEmpty && user.emailVerified) {
      try {
        final query = await firestore
            .collectionGroup('private')
            .where('email', isEqualTo: email)
            .where('isDeleted', isEqualTo: true)
            .limit(1)
            .get();

        if (query.docs.isNotEmpty) {
          final oldPrivate = query.docs.first;
          oldUid = oldPrivate.reference.parent.parent?.id;
          if (oldUid != null && oldUid != user.uid) {
            final oldPublic = await firestore.collection('users').doc(oldUid).get();
            oldData = {...?oldPublic.data(), ...oldPrivate.data()};
            print("Found a deleted user profile to restore: oldUid = $oldUid");
          } else {
            oldUid = null;
          }
        }
      } catch (e) {
        print("Error checking for deleted user profile: $e");
      }
    }

    // 3. Determine photoURL (Preserve existing active photo, then restored photo, only fallback to Google upload if empty)
    String photoURL = '';

    if (currentData != null &&
        currentData['photoURL'] != null &&
        currentData['photoURL'].toString().isNotEmpty) {
      photoURL = currentData['photoURL'].toString();
      print("User already has an active profile photo in Firestore: $photoURL");
    } else if (oldData != null &&
        oldData['photoURL'] != null &&
        oldData['photoURL'].toString().isNotEmpty) {
      photoURL = oldData['photoURL'].toString();
      print("Restoring old deleted profile photo: $photoURL");
    }

    // Only if no profile photo exists anywhere, and they signed in with Google, we fetch and upload their Google photo
    if (photoURL.isEmpty &&
        user.photoURL != null &&
        user.photoURL!.isNotEmpty) {
      final googlePhotoUrl = user.photoURL!;
      if (kIsWeb) {
        // Fetch and upload to Firebase Storage to keep it in our bucket
        print(
          "No profile photo found. Attempting to fetch and upload Google profile picture natively: $googlePhotoUrl",
        );
        final bytes = await fetchUrlBytes(googlePhotoUrl);
        if (bytes != null && bytes.isNotEmpty) {
          try {
            final storageRef = FirebaseStorage.instance.ref(
              'users/${user.uid}/profile.jpg',
            );
            await storageRef.putData(
              bytes,
              SettableMetadata(contentType: 'image/jpeg'),
            );
            photoURL = await storageRef.getDownloadURL();
            print(
              "Successfully uploaded Google profile picture to Firebase Storage: $photoURL",
            );

            // Update Auth photoURL as well
            await user.updatePhotoURL(photoURL);
            await user.reload();
          } catch (storageErr) {
            print(
              "Error uploading Google profile picture to Firebase Storage: $storageErr",
            );
            // Fallback to the Google photo URL directly
            photoURL = googlePhotoUrl;
          }
        } else {
          photoURL = googlePhotoUrl;
        }
      } else {
        photoURL = googlePhotoUrl;
      }
    }

    // 4. Build the structure preserving active state
    Map<String, dynamic> dataToSave = {
      'uid': user.uid,
      'displayName': incomingName.isNotEmpty
          ? incomingName
          : (currentData?['displayName'] ?? oldData?['displayName'] ?? ''),
      'email': email,
      'phone':
          currentData?['phone'] ?? oldData?['phone'] ?? user.phoneNumber ?? '',
      'photoURL': photoURL,
      'addresses': currentData?['addresses'] ?? oldData?['addresses'] ?? [],
      'privacy_share':
          currentData?['privacy_share'] ?? oldData?['privacy_share'] ?? true,
      'privacy_notifications':
          currentData?['privacy_notifications'] ??
          oldData?['privacy_notifications'] ??
          true,
      'privacy_public':
          currentData?['privacy_public'] ?? oldData?['privacy_public'] ?? true,
      'possessedTitles': currentData?['possessedTitles'] ?? oldData?['possessedTitles'] ?? ['viajero'],
      'activeTitleId': currentData?['activeTitleId'] ?? oldData?['activeTitleId'] ?? 'viajero',
      'coverURL': currentData?['coverURL'] ?? oldData?['coverURL'] ?? '',
      'coverUrl': currentData?['coverUrl'] ?? oldData?['coverUrl'] ?? '',
      'onboarding_completed': currentData?['onboarding_completed'] ?? oldData?['onboarding_completed'] ?? false,
      if ((currentData?['taste_vector'] ?? oldData?['taste_vector']) != null)
        'taste_vector': currentData?['taste_vector'] ?? oldData?['taste_vector'],
      if ((currentData?['taste_axes'] ?? oldData?['taste_axes']) != null)
        'taste_axes': currentData?['taste_axes'] ?? oldData?['taste_axes'],
      if ((currentData?['taste_recipe'] ?? oldData?['taste_recipe']) != null)
        'taste_recipe': currentData?['taste_recipe'] ?? oldData?['taste_recipe'],
      if ((currentData?['taste_vector_dim'] ?? oldData?['taste_vector_dim']) != null)
        'taste_vector_dim': currentData?['taste_vector_dim'] ?? oldData?['taste_vector_dim'],
      if ((currentData?['taste_model'] ?? oldData?['taste_model']) != null)
        'taste_model': currentData?['taste_model'] ?? oldData?['taste_model'],
      if ((currentData?['cultural_profile'] ?? oldData?['cultural_profile']) != null)
        'cultural_profile': currentData?['cultural_profile'] ?? oldData?['cultural_profile'],
      'isDeleted': false,
      'deletedAt': null,
      'scheduledDeletionAt': null,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    // Only set createdAt if we are not restoring, or keep old createdAt
    if (oldData != null && oldData['createdAt'] != null) {
      dataToSave['createdAt'] = oldData['createdAt'];
      dataToSave['restoredAt'] = FieldValue.serverTimestamp();
    } else if (currentData != null && currentData['createdAt'] != null) {
      dataToSave['createdAt'] = currentData['createdAt'];
    } else {
      dataToSave['createdAt'] = FieldValue.serverTimestamp();
    }

    // Save to the new UID: el perfil público y los datos privados por separado
    await UserPrivateData.save(user.uid, dataToSave);

    // Listas sociales en users/{uid}/social/*: mover las del perfil antiguo y las de
    // una cuenta restaurada.
    await SocialGraph.migrateLegacy(user.uid);
    if (oldUid != null && oldUid != user.uid) {
      try {
        final old = await SocialGraph.getGraph(oldUid);
        final lists = {
          if (old.friends.isNotEmpty) 'friends': FieldValue.arrayUnion(old.friends),
          if (old.following.isNotEmpty) 'following': FieldValue.arrayUnion(old.following),
        };
        if (lists.isNotEmpty) {
          await SocialGraph.graphRef(user.uid).set(lists, SetOptions(merge: true));
        }
      } catch (e) {
        print("Error restoring social lists: $e");
      }
    }
    print("User profile fully synchronized in Firestore.");

    // 4. Clean up the old deleted document if UID changed
    if (oldUid != null && oldUid != user.uid) {
      try {
        await UserPrivateData.privateRef(oldUid).delete();
        await firestore.collection('users').doc(oldUid).delete();
        print("Cleaned up legacy deleted profile document $oldUid");
      } catch (e) {
        print("Error deleting legacy restored document: $e");
      }
    }
  }
}


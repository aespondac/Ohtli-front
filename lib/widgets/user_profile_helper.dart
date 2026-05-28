import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:html' as html;

class UserProfileHelper {
  /// Fetches bytes from a Google photo URL using a native web request
  static Future<Uint8List?> fetchUrlBytes(String url) async {
    if (!kIsWeb) return null;
    try {
      final response = await html.HttpRequest.request(
        url,
        responseType: 'arraybuffer',
      );
      final responseBuffer = response.response as ByteBuffer;
      return responseBuffer.asUint8List();
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
    final currentData = currentDoc?.data() as Map<String, dynamic>?;

    // 2. Check if there is an existing deleted document with the same email to restore
    String? oldUid;
    Map<String, dynamic>? oldData;

    if (email.isNotEmpty) {
      try {
        final query = await firestore
            .collection('users')
            .where('email', isEqualTo: email)
            .where('isDeleted', isEqualTo: true)
            .limit(1)
            .get();

        if (query.docs.isNotEmpty) {
          final oldDoc = query.docs.first;
          oldUid = oldDoc.id;
          oldData = oldDoc.data();
          print("Found a deleted user profile to restore: oldUid = $oldUid");
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
            final bucket = FirebaseStorage.instance.app.options.storageBucket;
            photoURL =
                "https://firebasestorage.googleapis.com/v0/b/$bucket/o/users%2F${user.uid}%2Fprofile.jpg?alt=media";
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
          currentData?['privacy_public'] ?? oldData?['privacy_public'] ?? false,
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

    // Save to the new UID document
    await docRef.set(dataToSave, SetOptions(merge: true));
    print("User profile fully synchronized in Firestore.");

    // 4. Clean up the old deleted document if UID changed
    if (oldUid != null && oldUid != user.uid) {
      try {
        await firestore.collection('users').doc(oldUid).delete();
        print("Cleaned up legacy deleted profile document $oldUid");
      } catch (e) {
        print("Error deleting legacy restored document: $e");
      }
    }
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:typed_data';
import 'dart:js' as js;
import 'dart:js' show allowInterop;
import 'dart:js_util' show promiseToFuture;
import 'dart:ui_web' as ui_web;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../../theme/colors.dart';
import '../../widgets/image_cropper_dialog.dart';
import '../../widgets/address_picker_widget.dart' as address_picker;
import '../construction_page.dart'; // Reuse RouteBackgroundPainter

enum AccountSection {
  dashboard,
  personalInfo,
  security,
  addresses,
  privacy,
}

class AccountManagementPage extends StatefulWidget {
  final VoidCallback onBackToHome;
  final VoidCallback onLogout;

  const AccountManagementPage({
    super.key,
    required this.onBackToHome,
    required this.onLogout,
  });

  @override
  State<AccountManagementPage> createState() => _AccountManagementPageState();
}

class _AccountManagementPageState extends State<AccountManagementPage> {
  AccountSection _currentSection = AccountSection.dashboard;
  String? _localPhotoURL;
  bool _isSavingProfile = false;
  bool _sidebarCollapsed = false;
  bool _isHoveringLogout = false;

  // Personal Info form controllers
  final _personalFormKey = GlobalKey<FormState>();
  late TextEditingController _firstNameController;
  late TextEditingController _lastNameController;
  late TextEditingController _phoneController;

  // Security form controllers
  final _securityFormKey = GlobalKey<FormState>();
  late TextEditingController _currentPasswordController;
  late TextEditingController _newPasswordController;
  late TextEditingController _confirmPasswordController;
  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  bool _isUpdatingPassword = false;

  // Addresses state
  List<Map<String, dynamic>> _addresses = [];
  bool _isEditingAddress = false;
  int? _editingAddressIndex;
  final _addressFormKey = GlobalKey<FormState>();


  // Privacy state
  bool _shareTravelData = true;
  bool _receiveNotifications = true;
  bool _publicProfile = false;

  // Synchronous loader state for AddressPickerWidget (to avoid browser loading locks)
  bool _isAddressPickerLoaded = true;
  bool _isLoadingAddressPicker = false;
  StreamSubscription<DocumentSnapshot>? _userDataSubscription;
  bool _isInitialSyncDone = false;

  Future<void> _loadAddressPicker() async {
    // No-op: library is imported synchronously
  }

  @override
  void initState() {
    super.initState();
    final user = FirebaseAuth.instance.currentUser;
    
    // Split display name
    String firstName = '';
    String lastName = '';
    if (user?.displayName != null) {
      final parts = user!.displayName!.split(' ');
      if (parts.isNotEmpty) {
        firstName = parts.first;
        if (parts.length > 1) {
          lastName = parts.sublist(1).join(' ');
        }
      }
    }
    _firstNameController = TextEditingController(text: firstName);
    _lastNameController = TextEditingController(text: lastName);

    // Load phone from LocalStorage
    String localPhone = '';
    if (user != null) {
      localPhone = html.window.localStorage['ohtli_phone_${user.uid}'] ?? '';
    }
    _phoneController = TextEditingController(text: localPhone);

    // Security controllers
    _currentPasswordController = TextEditingController();
    _newPasswordController = TextEditingController();
    _confirmPasswordController = TextEditingController();

    _syncUserData();
    _loadPrivacySettings();
    _injectGooglePlacesApi();
  }

  void _injectGooglePlacesApi() {
    if (!kIsWeb) return;
    const mapsApiKey = String.fromEnvironment('mapsApiKey');
    const apiKey = String.fromEnvironment('apiKey');
    final activeKey = mapsApiKey.isNotEmpty ? mapsApiKey : apiKey;
    if (activeKey.isEmpty) return;

    if (html.document.getElementById('google-maps-places-script') != null) {
      return;
    }

    final script = html.ScriptElement()
      ..id = 'google-maps-places-script'
      ..src = 'https://maps.googleapis.com/maps/api/js?key=$activeKey&libraries=places&language=es&region=MX'
      ..async = true;
    html.document.head!.append(script);
  }

  void _syncUserData() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // 1. Load from localStorage synchronously for instant render
    final localPic = html.window.localStorage['ohtli_profile_pic_${user.uid}'];
    if (localPic != null && localPic.isNotEmpty) {
      _localPhotoURL = localPic;
    } else {
      _localPhotoURL = user.photoURL;
    }

    final localPhone = html.window.localStorage['ohtli_phone_${user.uid}'] ?? '';
    _phoneController.text = localPhone;

    final jsonStr = html.window.localStorage['ohtli_addresses_${user.uid}'];
    if (jsonStr != null && jsonStr.isNotEmpty) {
      try {
        final List<dynamic> decoded = json.decode(jsonStr);
        _addresses = decoded.map((e) => Map<String, dynamic>.from(e)).toList();
      } catch (e) {
        print("Error decoding cached addresses: $e");
      }
    }

    // 2. Subscribe to real-time updates from Cloud Firestore
    _userDataSubscription = FirebaseFirestore.instance.collection('users').doc(user.uid).snapshots().listen((doc) {
      if (!doc.exists) {
        if (!_isInitialSyncDone) {
          print("User document does not exist in Firestore. Creating it with local caches...");
          final Map<String, dynamic> initialData = {
            'privacy_share': _shareTravelData,
            'privacy_notifications': _receiveNotifications,
            'privacy_public': _publicProfile,
          };

          if (localPic != null && localPic.isNotEmpty) {
            if (localPic.startsWith('data:image') || localPic.startsWith('data:')) {
              _uploadLocalPhotoToFirestore(user.uid, localPic);
            } else {
              initialData['photoURL'] = localPic;
            }
          }
          if (localPhone.isNotEmpty) {
            initialData['phone'] = localPhone;
          }
          if (_addresses.isNotEmpty) {
            initialData['addresses'] = _addresses;
          }

          FirebaseFirestore.instance.collection('users').doc(user.uid).set(
            initialData,
            SetOptions(merge: true),
          ).then((_) {
            print("Successfully initialized user cloud document with local caches.");
          }).catchError((e) {
            print("Error initializing user cloud document: $e");
          });
          _isInitialSyncDone = true;
        }
        return;
      }

      final data = doc.data();
      if (data != null) {
        bool needUpload = false;
        final Map<String, dynamic> uploadData = {};

        // A. Sync Photo
        if (data.containsKey('photoURL')) {
          final String? remotePhoto = data['photoURL'] as String?;
          if (remotePhoto != null && remotePhoto.isNotEmpty) {
            if (mounted) {
              setState(() {
                _localPhotoURL = remotePhoto;
              });
              html.window.localStorage['ohtli_profile_pic_${user.uid}'] = remotePhoto;
            }
          } else if (localPic != null && localPic.isNotEmpty) {
            if (localPic.startsWith('data:image') || localPic.startsWith('data:')) {
              _uploadLocalPhotoToFirestore(user.uid, localPic);
            } else {
              uploadData['photoURL'] = localPic;
              needUpload = true;
            }
          }
        } else if (localPic != null && localPic.isNotEmpty) {
          if (localPic.startsWith('data:image') || localPic.startsWith('data:')) {
            _uploadLocalPhotoToFirestore(user.uid, localPic);
          } else {
            uploadData['photoURL'] = localPic;
            needUpload = true;
          }
        }

        // B. Sync Phone
        if (data.containsKey('phone')) {
          final String? remotePhone = data['phone'] as String?;
          if (remotePhone != null && remotePhone.isNotEmpty) {
            if (mounted) {
              setState(() {
                _phoneController.text = remotePhone;
              });
              html.window.localStorage['ohtli_phone_${user.uid}'] = remotePhone;
            }
          } else if (localPhone.isNotEmpty) {
            uploadData['phone'] = localPhone;
            needUpload = true;
          }
        } else if (localPhone.isNotEmpty) {
          uploadData['phone'] = localPhone;
          needUpload = true;
        }

        // C. Sync Privacy Settings
        if (data.containsKey('privacy_share')) {
          final bool? remoteShare = data['privacy_share'] as bool?;
          if (remoteShare != null) {
            if (mounted) {
              setState(() {
                _shareTravelData = remoteShare;
              });
              html.window.localStorage['ohtli_privacy_share_${user.uid}'] = remoteShare.toString();
            }
          }
        } else {
          uploadData['privacy_share'] = _shareTravelData;
          needUpload = true;
        }

        if (data.containsKey('privacy_notifications')) {
          final bool? remoteNotifications = data['privacy_notifications'] as bool?;
          if (remoteNotifications != null) {
            if (mounted) {
              setState(() {
                _receiveNotifications = remoteNotifications;
              });
              html.window.localStorage['ohtli_privacy_notifications_${user.uid}'] = remoteNotifications.toString();
            }
          }
        } else {
          uploadData['privacy_notifications'] = _receiveNotifications;
          needUpload = true;
        }

        if (data.containsKey('privacy_public')) {
          final bool? remotePublic = data['privacy_public'] as bool?;
          if (remotePublic != null) {
            if (mounted) {
              setState(() {
                _publicProfile = remotePublic;
              });
              html.window.localStorage['ohtli_privacy_public_${user.uid}'] = remotePublic.toString();
            }
          }
        } else {
          uploadData['privacy_public'] = _publicProfile;
          needUpload = true;
        }

        // D. Sync / Reconcile Addresses
        List<Map<String, dynamic>> cloudList = [];
        if (data.containsKey('addresses')) {
          final List<dynamic>? remoteList = data['addresses'] as List<dynamic>?;
          if (remoteList != null) {
            cloudList = remoteList.map((e) => Map<String, dynamic>.from(e)).toList();
          }
        }

        if (!_isInitialSyncDone) {
          // Reconcile offline additions and deletions only once on first load
          final deletedIds = _getDeletedAddressIds(user.uid);
          final reconciled = _reconcileAddresses(_addresses, cloudList, deletedIds);

          if (!_areAddressListsEqual(_addresses, reconciled)) {
            if (mounted) {
              setState(() {
                _addresses = reconciled;
              });
              html.window.localStorage['ohtli_addresses_${user.uid}'] = json.encode(_addresses);
            }
          }

          if (!_areAddressListsEqual(cloudList, reconciled)) {
            uploadData['addresses'] = reconciled;
            needUpload = true;
          }

          html.window.localStorage['ohtli_deleted_addresses_${user.uid}'] = json.encode([]);
          _isInitialSyncDone = true;
        } else {
          // Subsequent stream updates: accept the cloud as the absolute source of truth
          // to guarantee that creations, edits, and deletions on any other device reflect instantly.
          if (!_areAddressListsEqual(_addresses, cloudList)) {
            if (mounted) {
              setState(() {
                _addresses = cloudList;
              });
              html.window.localStorage['ohtli_addresses_${user.uid}'] = json.encode(_addresses);
            }
          }
        }

        if (needUpload && uploadData.isNotEmpty) {
          FirebaseFirestore.instance.collection('users').doc(user.uid).set(
            uploadData,
            SetOptions(merge: true),
          ).catchError((e) {
            print("Error syncing local caches to Firestore: $e");
          });
        }
      }
    }, onError: (e) {
      print("Error listening to user data Firestore stream: $e");
    });
  }

  void _uploadLocalPhotoToFirestore(String uid, String base64String) async {
    // Only upload to Firebase Storage (the lowest cost option)
    try {
      final rawBase64 = base64String.contains(',')
          ? base64String.split(',').last
          : base64String;
      final imageBytes = base64Decode(rawBase64);
      final storageRef = FirebaseStorage.instance.ref('users/$uid/profile.jpg');
      await storageRef.putData(
        Uint8List.fromList(imageBytes),
        SettableMetadata(contentType: 'image/jpeg'),
      );
      final bucket = FirebaseStorage.instance.app.options.storageBucket;
      final String downloadUrl = "https://firebasestorage.googleapis.com/v0/b/$bucket/o/users%2F$uid%2Fprofile.jpg?alt=media";
      
      // Update localStorage with the verified bucket URL
      html.window.localStorage['ohtli_profile_pic_$uid'] = downloadUrl;
      
      // Update UI state if still active
      if (mounted) {
        setState(() {
          _localPhotoURL = downloadUrl;
        });
      }

      // Sync verified URL to Firestore
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'photoURL': downloadUrl,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      print("Successfully migrated local photo to Firebase Storage and synced URL to Firestore.");
    } catch (e) {
      // Storage failed or not enabled. Keep base64 ONLY locally (no cost in Firestore!)
      print("Storage migration failed. Kept photo exclusively local to avoid Firestore base64 costs: $e");
    }
  }

  @override
  void dispose() {
    _userDataSubscription?.cancel();
    _firstNameController.dispose();
    _lastNameController.dispose();
    _phoneController.dispose();
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  // Address helper: Save to LocalStorage and Cloud Firestore
  Future<void> _saveAddresses() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    
    // 1. Write to LocalStorage for instant local persist
    html.window.localStorage['ohtli_addresses_${user.uid}'] = json.encode(_addresses);

    // 2. Write to Cloud Firestore to sync across all devices — await to detect errors
    try {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'addresses': _addresses,
      }, SetOptions(merge: true));
    } catch (e) {
      print("Error saving addresses to Firestore: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Dirección guardada localmente. Se sincronizará al reconectar.',
              style: GoogleFonts.inter(fontWeight: FontWeight.w500),
            ),
            backgroundColor: OhtliColors.cantera,
          ),
        );
      }
    }
  }

  // Offline Synchronization Helpers
  String _getAddressId(Map<String, dynamic> addr) {
    // Use the explicit 'id' field if present; otherwise generate a stable deterministic ID
    // from the address content (avoiding hashCode which is NOT stable across Dart platforms/browsers)
    if (addr['id'] != null && (addr['id'] as String).isNotEmpty) {
      return addr['id'] as String;
    }
    // Deterministic fallback: combine street + lat + lng as a string key
    final street = (addr['street'] ?? '').toString().trim().toLowerCase();
    final lat = (addr['lat'] ?? 0).toString();
    final lng = (addr['lng'] ?? 0).toString();
    return 'addr_${street}_${lat}_$lng';
  }

  Set<String> _getDeletedAddressIds(String uid) {
    final jsonStr = html.window.localStorage['ohtli_deleted_addresses_$uid'];
    if (jsonStr != null && jsonStr.isNotEmpty) {
      try {
        final List<dynamic> decoded = json.decode(jsonStr);
        return decoded.map((e) => e.toString()).toSet();
      } catch (e) {
        print("Error decoding deleted address IDs: $e");
      }
    }
    return {};
  }

  void _trackAddressDeletion(String uid, String addrId) {
    final deleted = _getDeletedAddressIds(uid);
    deleted.add(addrId);
    html.window.localStorage['ohtli_deleted_addresses_$uid'] = json.encode(deleted.toList());
  }

  List<Map<String, dynamic>> _reconcileAddresses(
    List<Map<String, dynamic>> localList,
    List<Map<String, dynamic>> cloudList,
    Set<String> deletedIds,
  ) {
    final List<Map<String, dynamic>> merged = [];
    
    final Map<String, Map<String, dynamic>> cloudMap = {};
    for (final addr in cloudList) {
      final id = _getAddressId(addr);
      cloudMap[id] = addr;
    }
    
    final Map<String, Map<String, dynamic>> localMap = {};
    for (final addr in localList) {
      final id = _getAddressId(addr);
      localMap[id] = addr;
    }

    // Process local list
    for (final localAddr in localList) {
      final id = _getAddressId(localAddr);
      if (cloudMap.containsKey(id)) {
        // If present in both, prefer the cloud data as the latest truth
        merged.add(cloudMap[id]!);
      } else {
        // Local-only addition (added while offline), keep it to upload it
        merged.add(localAddr);
      }
    }

    // Process cloud list (check for additions from other devices or deletions)
    for (final cloudAddr in cloudList) {
      final id = _getAddressId(cloudAddr);
      if (!localMap.containsKey(id)) {
        if (deletedIds.contains(id)) {
          // Address was deleted locally while offline, exclude from merged to delete in cloud
          print("Excluding locally deleted address: $id");
        } else {
          // Address was added on another device, keep it!
          merged.add(cloudAddr);
        }
      }
    }

    return merged;
  }

  bool _areAddressListsEqual(List<Map<String, dynamic>> listA, List<Map<String, dynamic>> listB) {
    if (listA.length != listB.length) return false;
    for (int i = 0; i < listA.length; i++) {
      final a = listA[i];
      final b = listB[i];
      if (a['customName'] != b['customName'] ||
          a['category'] != b['category'] ||
          a['street'] != b['street'] ||
          a['suburb'] != b['suburb'] ||
          a['zip'] != b['zip'] ||
          a['city'] != b['city'] ||
          a['state'] != b['state'] ||
          a['country'] != b['country'] ||
          a['lat'] != b['lat'] ||
          a['lng'] != b['lng'] ||
          a['id'] != b['id']) {
        return false;
      }
    }
    return true;
  }

  // Privacy helpers
  void _loadPrivacySettings() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    _shareTravelData = html.window.localStorage['ohtli_privacy_share_${user.uid}'] != 'false';
    _receiveNotifications = html.window.localStorage['ohtli_privacy_notifications_${user.uid}'] != 'false';
    _publicProfile = html.window.localStorage['ohtli_privacy_public_${user.uid}'] == 'true';
  }

  void _savePrivacySetting(String key, bool value) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    html.window.localStorage['ohtli_privacy_${key}_${user.uid}'] = value.toString();

    // Also sync to Cloud Firestore!
    FirebaseFirestore.instance.collection('users').doc(user.uid).set({
      'privacy_$key': value,
    }, SetOptions(merge: true)).catchError((e) {
      print("Error saving privacy setting to Firestore: $e");
    });
  }

  // Photo Upload Handler (avoiding Firebase URL size limit)
  Future<void> _handlePhotoUpload() async {
    if (!kIsWeb) return;

    try {
      final uploadInput = html.FileUploadInputElement()..accept = 'image/*';
      uploadInput.click();

      uploadInput.onChange.listen((e) {
        final files = uploadInput.files;
        if (files != null && files.isNotEmpty) {
          final file = files[0];
          final reader = html.FileReader();

          // 1. Attach onload listener BEFORE calling readAsDataUrl to prevent race conditions on mobile!
          reader.onLoadEnd.listen((e) {
            final dynamic result = reader.result;
            if (result is String && result.isNotEmpty) {
              try {
                // Extract raw base64 data from the data URL and decode to a true Dart-allocated Uint8List
                final String base64Data = result.split(',').last;
                final Uint8List bytes = base64Decode(base64Data);

                if (bytes.isNotEmpty) {
                  // Open Crop Dialog with a safe delay to allow iOS to restore viewport focus
                  Future.delayed(const Duration(milliseconds: 200), () {
                    if (mounted) {
                      showDialog(
                        context: context,
                        barrierDismissible: false,
                        builder: (context) => OhtliImageCropperDialog(
                          imageBytes: bytes,
                          onCropped: (String base64String) async {
                            setState(() {
                              _isSavingProfile = true;
                              _localPhotoURL = base64String;
                            });
                            try {
                              final user = FirebaseAuth.instance.currentUser;
                              if (user != null) {
                                // Keep base64 in localStorage for instant local display
                                html.window.localStorage['ohtli_profile_pic_${user.uid}'] = base64String;

                                // Upload to Firebase Storage instead of Firestore to avoid 1MiB document limit
                                String? downloadUrl;
                                try {
                                  // Extract raw base64 bytes from the data URI
                                  final rawBase64 = base64String.contains(',')
                                      ? base64String.split(',').last
                                      : base64String;
                                  final imageBytes = base64Decode(rawBase64);

                                  final storageRef = FirebaseStorage.instance
                                      .ref('users/${user.uid}/profile.jpg');
                                  await storageRef.putData(
                                    Uint8List.fromList(imageBytes),
                                    SettableMetadata(contentType: 'image/jpeg'),
                                  );
                                  final bucket = FirebaseStorage.instance.app.options.storageBucket;
                                  downloadUrl = "https://firebasestorage.googleapis.com/v0/b/$bucket/o/users%2F${user.uid}%2Fprofile.jpg?alt=media";
                                } catch (storageError) {
                                  print("Firebase Storage upload error: $storageError");
                                }

                                if (downloadUrl != null) {
                                  // Save the download URL (never base64!) to Firestore for cross-device sync
                                  try {
                                    await FirebaseFirestore.instance
                                        .collection('users')
                                        .doc(user.uid)
                                        .set({
                                          'photoURL': downloadUrl,
                                          'updatedAt': FieldValue.serverTimestamp(),
                                        }, SetOptions(merge: true));
                                  } catch (fsError) {
                                    print("Error saving profile photo URL to Firestore: $fsError");
                                  }

                                  // Update Firebase Auth profile with the real download URL
                                  try {
                                    await user.updatePhotoURL(downloadUrl);
                                    await user.reload();
                                  } catch (authError) {
                                    print("Firebase Auth profile sync bypassed: $authError");
                                  }

                                  if (mounted) {
                                    setState(() {});
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          '¡Foto de perfil sincronizada en la nube exitosamente!',
                                          style: GoogleFonts.inter(fontWeight: FontWeight.w500),
                                        ),
                                        backgroundColor: OhtliColors.stormyTeal,
                                      ),
                                    );
                                  }
                                } else {
                                  // Storage upload failed/not enabled. Block Firestore base64 to save costs!
                                  if (mounted) {
                                    setState(() {});
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          'Foto de perfil guardada localmente (sin sincronización en la nube para ahorrar datos).',
                                          style: GoogleFonts.inter(fontWeight: FontWeight.w500),
                                        ),
                                        backgroundColor: OhtliColors.cantera,
                                      ),
                                    );
                                  }
                                }
                              }
                            } catch (err) {
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Error al guardar la imagen: ${err.toString()}'),
                                    backgroundColor: OhtliColors.xoconostle,
                                  ),
                                );
                              }
                            } finally {
                              if (mounted) {
                                setState(() => _isSavingProfile = false);
                              }
                            }
                          },
                        ),
                      );
                    }
                  });
                }
              } catch (err) {
                print("Error parsing uploaded image: $err");
              }
            } else {
              print("Uploaded file could not be read as Data URL string");
            }
          });

          // 3. Initiate read AFTER event listener is fully registered
          reader.readAsDataUrl(file);
        }
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: ${e.toString()}'),
          backgroundColor: OhtliColors.xoconostle,
        ),
      );
    }
  }

  // Handle personal info submit
  Future<void> _savePersonalInfo() async {
    if (!_personalFormKey.currentState!.validate()) return;
    setState(() => _isSavingProfile = true);
    
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final newName = "${_firstNameController.text.trim()} ${_lastNameController.text.trim()}".trim();
        final phoneText = _phoneController.text.trim();
        final currentPhone = html.window.localStorage['ohtli_phone_${user.uid}'] ?? '';

        // Check if anything actually changed to avoid unnecessary operations
        final nameChanged = newName.isNotEmpty && newName != (user.displayName ?? '');
        final phoneChanged = phoneText != currentPhone;

        if (nameChanged) {
          await user.updateDisplayName(newName);
        }
        
        // Save phone to LocalStorage
        html.window.localStorage['ohtli_phone_${user.uid}'] = phoneText;

        // Also persist name, email, and phone to Cloud Firestore for robust cross-device sync
        try {
          await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
            'displayName': newName,
            'email': user.email ?? '',
            'phone': phoneText,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
          print("Successfully synced profile changes to Firestore.");
        } catch (fsError) {
          print("Firestore error syncing user profile details: $fsError");
        }

        // Wrap reload in its own try-catch so it never crashes the save flow
        try {
          await user.reload();
        } catch (reloadError) {
          print("Non-critical user reload error (ignored): $reloadError");
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '¡Información personal actualizada exitosamente!',
              style: GoogleFonts.inter(fontWeight: FontWeight.w500),
            ),
            backgroundColor: OhtliColors.stormyTeal,
          ),
        );
        setState(() {
          _currentSection = AccountSection.dashboard;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: OhtliColors.xoconostle,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSavingProfile = false);
      }
    }
  }

  // Handle security/password update with reauthentication
  Future<void> _changePassword() async {
    if (!_securityFormKey.currentState!.validate()) return;
    
    final currentPassword = _currentPasswordController.text;
    final newPassword = _newPasswordController.text;
    final confirmPassword = _confirmPasswordController.text;

    if (newPassword != confirmPassword) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Las contraseñas nuevas no coinciden.'),
          backgroundColor: OhtliColors.xoconostle,
        ),
      );
      return;
    }

    setState(() => _isUpdatingPassword = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null && user.email != null) {
        // Reauthenticate
        final credential = EmailAuthProvider.credential(
          email: user.email!,
          password: currentPassword,
        );

        await user.reauthenticateWithCredential(credential);
        await user.updatePassword(newPassword);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '¡Contraseña cambiada exitosamente!',
                style: GoogleFonts.inter(fontWeight: FontWeight.w500),
              ),
              backgroundColor: OhtliColors.stormyTeal,
            ),
          );
          
          _currentPasswordController.clear();
          _newPasswordController.clear();
          _confirmPasswordController.clear();

          setState(() {
            _currentSection = AccountSection.dashboard;
          });
        }
      }
    } catch (e) {
      String errorMessage = 'Error al actualizar contraseña. Verifica tu contraseña actual.';
      if (e is FirebaseAuthException) {
        if (e.code == 'wrong-password') {
          errorMessage = 'La contraseña actual es incorrecta.';
        } else if (e.code == 'weak-password') {
          errorMessage = 'La nueva contraseña es muy débil.';
        }
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: OhtliColors.xoconostle,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isUpdatingPassword = false);
      }
    }
  }

  // Secure account deletion flow
  void _showDeleteAccountDialog(BuildContext parentContext) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    bool isGoogleUser = false;
    for (final info in user.providerData) {
      if (info.providerId == 'google.com') {
        isGoogleUser = true;
      }
    }

    final deletePasswordController = TextEditingController();
    final deleteFormKey = GlobalKey<FormState>();
    bool isDeleting = false;

    showDialog(
      context: parentContext,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: OhtliColors.cloudDancer,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: Row(
                children: [
                  const Icon(Icons.delete_forever_rounded, color: OhtliColors.xoconostle, size: 24),
                  const SizedBox(width: 8),
                  Text(
                    '¿Eliminar cuenta?',
                    style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: OhtliColors.onyx, fontSize: 18),
                  ),
                ],
              ),
              content: Form(
                key: deleteFormKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Esta acción es irreversible y eliminará todos tus datos en Ohtli permanentemente. Firebase requiere volver a verificar tu identidad antes de continuar.',
                      style: GoogleFonts.inter(fontSize: 13, color: OhtliColors.onyx.withOpacity(0.7), height: 1.4),
                    ),
                    const SizedBox(height: 20),
                    if (isGoogleUser) ...[
                      Text(
                        'Iniciaste sesión con Google. Presiona el botón de abajo para re-autenticarte de forma segura.',
                        style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w500, color: OhtliColors.onyx),
                      ),
                      const SizedBox(height: 16),
                    ] else ...[
                      TextFormField(
                        controller: deletePasswordController,
                        obscureText: true,
                        style: GoogleFonts.inter(color: OhtliColors.onyx, fontSize: 14),
                        validator: (value) => value == null || value.isEmpty ? 'Ingresa tu contraseña actual' : null,
                        decoration: InputDecoration(
                          labelText: 'Contraseña Actual',
                          labelStyle: GoogleFonts.inter(color: OhtliColors.onyx.withOpacity(0.5)),
                          prefixIcon: const Icon(Icons.lock_outline_rounded, color: OhtliColors.stormyTeal, size: 20),
                          filled: true,
                          fillColor: OhtliColors.cantera.withOpacity(0.3),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    if (isDeleting)
                      const Center(
                        child: CircularProgressIndicator(color: OhtliColors.xoconostle),
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isDeleting ? null : () => Navigator.of(context).pop(),
                  child: Text('Cancelar', style: GoogleFonts.inter(color: OhtliColors.onyx.withOpacity(0.6))),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: isDeleting
                      ? null
                      : () async {
                          if (!isGoogleUser && !deleteFormKey.currentState!.validate()) return;
                          
                          setDialogState(() => isDeleting = true);
                          
                          try {
                            if (isGoogleUser) {
                              // Google re-authentication
                              final googleProvider = GoogleAuthProvider();
                              await user.reauthenticateWithPopup(googleProvider);
                            } else {
                              // Email re-authentication
                              final credential = EmailAuthProvider.credential(
                                email: user.email!,
                                password: deletePasswordController.text,
                              );
                              await user.reauthenticateWithCredential(credential);
                            }
                            
                            // Delete local storage keys securely
                            html.window.localStorage.remove('ohtli_profile_pic_${user.uid}');
                            html.window.localStorage.remove('ohtli_phone_${user.uid}');
                            html.window.localStorage.remove('ohtli_addresses_${user.uid}');
                            html.window.localStorage.remove('ohtli_privacy_share_${user.uid}');
                            html.window.localStorage.remove('ohtli_privacy_notifications_${user.uid}');
                            html.window.localStorage.remove('ohtli_privacy_public_${user.uid}');
                            
                            // Delete the user from Firebase
                            await user.delete();
                            
                            if (mounted) {
                              Navigator.of(context).pop(); // Close dialog
                              ScaffoldMessenger.of(parentContext).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'Tu cuenta ha sido eliminada permanentemente. Esperamos volver a verte.',
                                    style: GoogleFonts.inter(fontWeight: FontWeight.w500),
                                  ),
                                  backgroundColor: OhtliColors.xoconostle,
                                  duration: const Duration(seconds: 4),
                                ),
                              );
                              widget.onLogout();
                            }
                          } catch (e) {
                            String err = 'Error al re-autenticar o eliminar la cuenta. Inténtalo de nuevo.';
                            if (e is FirebaseAuthException) {
                              if (e.code == 'wrong-password') {
                                err = 'La contraseña ingresada es incorrecta.';
                              } else if (e.code == 'user-mismatch') {
                                err = 'La cuenta de re-autenticación no coincide con la cuenta actual.';
                              }
                            }
                            
                            if (mounted) {
                              ScaffoldMessenger.of(parentContext).showSnackBar(
                                SnackBar(
                                  content: Text(err),
                                  backgroundColor: OhtliColors.xoconostle,
                                ),
                              );
                            }
                          } finally {
                            if (mounted) {
                              setDialogState(() => isDeleting = false);
                            }
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: OhtliColors.xoconostle,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text(
                    isGoogleUser ? 'Re-autenticar y Eliminar' : 'Confirmar y Eliminar',
                    style: GoogleFonts.inter(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildAvatarWidget({
    required double radius,
    required String initials,
    required String? photoURL,
    VoidCallback? onTap,
    bool showEditIcon = false,
  }) {
    Widget avatarContent;
    if (photoURL != null && photoURL.isNotEmpty) {
      if (photoURL.startsWith('data:image') || photoURL.startsWith('data:')) {
        try {
          final String base64Data = photoURL.split(',').last;
          final Uint8List decodedBytes = base64.decode(base64Data);
          avatarContent = ClipOval(
            child: Image.memory(
              decodedBytes,
              width: radius * 2,
              height: radius * 2,
              fit: BoxFit.cover,
            ),
          );
        } catch (e) {
          avatarContent = Center(child: Text(initials, style: GoogleFonts.inter(color: Colors.white, fontSize: radius * 0.7, fontWeight: FontWeight.w600)));
        }
      } else {
        avatarContent = ClipOval(
          child: Image.network(
            photoURL,
            width: radius * 2,
            height: radius * 2,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) {
              return Center(child: Text(initials, style: GoogleFonts.inter(color: Colors.white, fontSize: radius * 0.7, fontWeight: FontWeight.w600)));
            },
          ),
        );
      }
    } else {
      avatarContent = Center(
        child: Text(
          initials,
          style: GoogleFonts.inter(
            color: Colors.white,
            fontSize: radius * 0.7,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    Widget mainAvatar = Container(
      width: radius * 2,
      height: radius * 2,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: OhtliColors.stormyTeal,
      ),
      child: avatarContent,
    );

    if (showEditIcon && onTap != null) {
      final double containerSize = (radius * 2) + 6;
      return GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: SizedBox(
            width: containerSize,
            height: containerSize,
            child: Stack(
              children: [
                Positioned(
                  top: 0,
                  left: 0,
                  child: mainAvatar,
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(color: OhtliColors.stormyTeal, width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.15),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.camera_alt_rounded,
                      color: OhtliColors.stormyTeal,
                      size: 16,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (onTap != null) {
      return GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: mainAvatar,
        ),
      );
    }

    return mainAvatar;
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final localPic = html.window.localStorage['ohtli_profile_pic_${user.uid}'];
      if (localPic != null && localPic.isNotEmpty) {
        _localPhotoURL = localPic;
      }
    }

    final displayName = user?.displayName ?? user?.email ?? 'Viajero';
    final initials = displayName
        .split(' ')
        .where((w) => w.isNotEmpty)
        .take(2)
        .map((w) => w[0].toUpperCase())
        .join();

    final screenSize = MediaQuery.of(context).size;
    final isMobile = screenSize.width < 800;

    const colorSidebar = Color(0xFFE4E1DA);
    final sidebarWidth = _sidebarCollapsed ? 64.0 : 200.0;

    // Body content with background lines
    Widget mainBody = Stack(
      children: [
        Positioned.fill(
          child: CustomPaint(
            painter: RouteBackgroundPainter(OhtliColors.cantera.withOpacity(0.4)),
          ),
        ),
        SafeArea(
          child: Column(
            children: [
              _buildAppBar(isMobile),
              Expanded(
                child: Center(
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 800),
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      transitionBuilder: (child, anim) {
                        return FadeTransition(
                          opacity: anim,
                          child: SlideTransition(
                            position: Tween<Offset>(
                              begin: const Offset(0.0, 0.05),
                              end: Offset.zero,
                            ).animate(anim),
                            child: child,
                          ),
                        );
                      },
                      child: _buildActiveContent(user, displayName, initials, isMobile),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );

    if (isMobile) {
      return Scaffold(
        backgroundColor: OhtliColors.cloudDancer,
        body: mainBody,
      );
    }

    // Desktop: Row with persistent sidebar on the left and main configuration screen on the right
    return Scaffold(
      backgroundColor: OhtliColors.cloudDancer,
      body: Row(
        children: [
          // ========= PERSISTENT SIDEBAR =========
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
            width: sidebarWidth,
            decoration: const BoxDecoration(
              color: colorSidebar,
              border: Border(
                right: BorderSide(color: Color(0xFFD1CDC4), width: 1),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top: Isologo or Logo (clickable to return home)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                  child: Row(
                    children: [
                      if (_sidebarCollapsed) ...
                        [
                          Expanded(
                            child: Center(
                              child: GestureDetector(
                                onTap: widget.onBackToHome,
                                child: MouseRegion(
                                  cursor: SystemMouseCursors.click,
                                  child: SvgPicture.asset(
                                    'assets/icon_isologo.svg',
                                    height: 26,
                                    fit: BoxFit.contain,
                                    colorFilter: const ColorFilter.mode(OhtliColors.stormyTeal, BlendMode.srcIn),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ]
                      else ...
                        [
                          Expanded(
                            child: GestureDetector(
                              onTap: widget.onBackToHome,
                              child: MouseRegion(
                                cursor: SystemMouseCursors.click,
                                child: SvgPicture.asset(
                                  'assets/logo.svg',
                                  height: 22,
                                  fit: BoxFit.contain,
                                  alignment: Alignment.centerLeft,
                                  colorFilter: const ColorFilter.mode(OhtliColors.stormyTeal, BlendMode.srcIn),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          InkWell(
                            onTap: () => setState(() => _sidebarCollapsed = !_sidebarCollapsed),
                            borderRadius: BorderRadius.circular(8),
                            child: Padding(
                              padding: const EdgeInsets.all(4),
                              child: const Icon(
                                Icons.keyboard_arrow_left_rounded,
                                size: 18,
                                color: OhtliColors.stormyTeal,
                              ),
                            ),
                          ),
                        ],
                    ],
                  ),
                ),

                if (_sidebarCollapsed)
                  Center(
                    child: InkWell(
                      onTap: () => setState(() => _sidebarCollapsed = !_sidebarCollapsed),
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: const Icon(
                          Icons.keyboard_arrow_right_rounded,
                          size: 18,
                          color: OhtliColors.stormyTeal,
                        ),
                      ),
                    ),
                  ),

                const Spacer(),

                // Bottom: Avatar + Name + Logout (clickable avatar/name returns to configuration dashboard)
                const Divider(height: 1, color: Color(0xFFD1CDC4)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  child: Row(
                    children: [
                      _buildAvatarWidget(
                        radius: 16,
                        initials: initials,
                        photoURL: _localPhotoURL,
                        onTap: () {
                          if (_currentSection != AccountSection.dashboard) {
                            setState(() {
                              _currentSection = AccountSection.dashboard;
                            });
                          }
                        },
                      ),
                      if (!_sidebarCollapsed) ...
                        [
                          const SizedBox(width: 10),
                          Expanded(
                            child: GestureDetector(
                              onTap: () {
                                if (_currentSection != AccountSection.dashboard) {
                                  setState(() {
                                    _currentSection = AccountSection.dashboard;
                                  });
                                }
                              },
                              child: MouseRegion(
                                cursor: SystemMouseCursors.click,
                                child: Text(
                                  displayName.split(' ').first,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.inter(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w400,
                                    color: OhtliColors.onyx.withOpacity(0.8),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          MouseRegion(
                            onEnter: (_) => setState(() => _isHoveringLogout = true),
                            onExit: (_) => setState(() => _isHoveringLogout = false),
                            child: InkWell(
                              onTap: widget.onLogout,
                              borderRadius: BorderRadius.circular(8),
                              child: Padding(
                                padding: const EdgeInsets.all(4),
                                child: Icon(
                                  Icons.logout_rounded,
                                  size: 17,
                                  color: _isHoveringLogout
                                      ? OhtliColors.xoconostle
                                      : OhtliColors.stormyTeal,
                                ),
                              ),
                            ),
                          ),
                        ]
                      else
                        const SizedBox.shrink(),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Main configuration page body
          Expanded(
            child: mainBody,
          ),
        ],
      ),
    );
  }

  Widget _buildAppBar(bool isMobile) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Back/Return Button
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: TextButton.icon(
              onPressed: () {
                if (_currentSection != AccountSection.dashboard) {
                  setState(() {
                    _currentSection = AccountSection.dashboard;
                    _isEditingAddress = false;
                  });
                } else {
                  widget.onBackToHome();
                }
              },
              icon: const Icon(Icons.arrow_back_rounded, color: OhtliColors.stormyTeal, size: 20),
              label: Text(
                _currentSection == AccountSection.dashboard ? 'Volver al Inicio' : 'Atrás',
                style: GoogleFonts.inter(
                  color: OhtliColors.stormyTeal,
                  fontWeight: FontWeight.w500,
                  fontSize: 14,
                ),
              ),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                backgroundColor: OhtliColors.cantera.withOpacity(0.3),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),

          // Action section title or branding
          if (_currentSection != AccountSection.dashboard)
            Text(
              _getSectionTitle(_currentSection),
              style: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: OhtliColors.onyx,
              ),
            )
          else
            Text(
              'Mi Cuenta',
              style: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: OhtliColors.onyx.withOpacity(0.5),
              ),
            ),
        ],
      ),
    );
  }

  String _getSectionTitle(AccountSection section) {
    switch (section) {
      case AccountSection.personalInfo:
        return 'Información Personal';
      case AccountSection.security:
        return 'Seguridad';
      case AccountSection.addresses:
        return 'Direcciones';
      case AccountSection.privacy:
        return 'Privacidad';
      default:
        return '';
    }
  }

  Widget _buildActiveContent(
    User? user,
    String displayName,
    String initials,
    bool isMobile,
  ) {
    switch (_currentSection) {
      case AccountSection.dashboard:
        return _buildDashboard(user, displayName, initials, isMobile);
      case AccountSection.personalInfo:
        return _buildPersonalInfoForm(user);
      case AccountSection.security:
        return _buildSecurityForm();
      case AccountSection.addresses:
        return _buildAddressesView();
      case AccountSection.privacy:
        return _buildPrivacyView();
    }
  }

  // Dashboard layout
  Widget _buildDashboard(
    User? user,
    String displayName,
    String initials,
    bool isMobile,
  ) {
    return SingleChildScrollView(
      child: Column(
        children: [
          const SizedBox(height: 20),
          // Large Avatar
          _buildAvatarWidget(
            radius: isMobile ? 56 : 70,
            initials: initials,
            photoURL: _localPhotoURL,
            onTap: _handlePhotoUpload,
            showEditIcon: true,
          ),
          const SizedBox(height: 18),

          // User Name
          Text(
            displayName,
            textAlign: TextAlign.center,
            style: GoogleFonts.caprasimo(
              fontSize: isMobile ? 24 : 28,
              fontWeight: FontWeight.w400,
              color: OhtliColors.stormyTeal,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 4),

          // User Email
          Text(
            user?.email ?? '',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w300,
              color: OhtliColors.onyx.withOpacity(0.5),
            ),
          ),
          const SizedBox(height: 10),

          // User ID and Cloud Sync Status Badge
          if (user != null)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: OhtliColors.cantera.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: OhtliColors.cantera.withOpacity(0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.fingerprint_rounded, size: 12, color: OhtliColors.stormyTeal),
                      const SizedBox(width: 4),
                      Text(
                        'ID: ${user.uid.substring(0, 8)}...',
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                          color: OhtliColors.onyx.withOpacity(0.7),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFDEF7EC),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFBCF0DA)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.cloud_done_rounded, size: 12, color: Color(0xFF03543F)),
                      const SizedBox(width: 4),
                      Text(
                        'Nube Sincronizada',
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF03543F),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          const SizedBox(height: 28),

          // Grid for Desktop or ListTile list for Mobile
          if (isMobile)
            _buildMobileDashboardList()
          else
            _buildDesktopDashboardGrid(),

          const SizedBox(height: 40),

          // Bottom Logout (only displayed on Mobile dashboard now since Desktop has it in persistent sidebar!)
          if (isMobile) ...[
            SizedBox(
              width: 200,
              child: OutlinedButton.icon(
                onPressed: widget.onLogout,
                icon: const Icon(Icons.logout_rounded, size: 18, color: OhtliColors.xoconostle),
                label: Text(
                  'Cerrar sesión',
                  style: GoogleFonts.inter(
                    color: OhtliColors.xoconostle,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: OhtliColors.xoconostle, width: 1.5),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                  backgroundColor: Colors.transparent,
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ],
      ),
    );
  }

  // Grid for Desktop
  Widget _buildDesktopDashboardGrid() {
    return Container(
      constraints: const BoxConstraints(maxWidth: 680),
      child: Wrap(
        spacing: 20,
        runSpacing: 20,
        alignment: WrapAlignment.center,
        children: [
          _DashboardCard(
            title: 'Información Personal',
            description: 'Datos personales y de contacto proporcionados.',
            icon: Icons.person_outline_rounded,
            onTap: () => setState(() => _currentSection = AccountSection.personalInfo),
          ),
          _DashboardCard(
            title: 'Seguridad',
            description: 'Gestiona la seguridad y contraseña de tu cuenta.',
            icon: Icons.security_rounded,
            onTap: () => setState(() => _currentSection = AccountSection.security),
          ),
          _DashboardCard(
            title: 'Direcciones',
            description: 'Direcciones guardadas para facturación y envíos.',
            icon: Icons.location_on_outlined,
            onTap: () => setState(() => _currentSection = AccountSection.addresses),
          ),
          _DashboardCard(
            title: 'Privacidad',
            description: 'Control sobre tus preferencias y el uso de tus datos.',
            icon: Icons.privacy_tip_outlined,
            onTap: () => setState(() => _currentSection = AccountSection.privacy),
          ),
        ],
      ),
    );
  }

  // List layout for Mobile
  Widget _buildMobileDashboardList() {
    return Column(
      children: [
        _buildMobileListTile(
          title: 'Información Personal',
          icon: Icons.person_outline_rounded,
          onTap: () => setState(() => _currentSection = AccountSection.personalInfo),
        ),
        const SizedBox(height: 12),
        _buildMobileListTile(
          title: 'Seguridad',
          icon: Icons.security_rounded,
          onTap: () => setState(() => _currentSection = AccountSection.security),
        ),
        const SizedBox(height: 12),
        _buildMobileListTile(
          title: 'Direcciones',
          icon: Icons.location_on_outlined,
          onTap: () => setState(() => _currentSection = AccountSection.addresses),
        ),
        const SizedBox(height: 12),
        _buildMobileListTile(
          title: 'Privacidad',
          icon: Icons.privacy_tip_outlined,
          onTap: () => setState(() => _currentSection = AccountSection.privacy),
        ),
      ],
    );
  }

  Widget _buildMobileListTile({
    required String title,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Material(
      color: const Color(0xFFDCD8CF),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Row(
            children: [
              Icon(icon, color: OhtliColors.stormyTeal, size: 22),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: OhtliColors.onyx,
                  ),
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: OhtliColors.stormyTeal, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  // 1. Personal Info subform
  Widget _buildPersonalInfoForm(User? user) {
    return Card(
      elevation: 0,
      color: const Color(0xFFDCD8CF),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _personalFormKey,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Edita tu información personal',
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: OhtliColors.onyx,
                  ),
                ),
                const SizedBox(height: 20),

                // Correo (Inmodificable)
                TextFormField(
                  initialValue: user?.email ?? '',
                  readOnly: true,
                  style: GoogleFonts.inter(color: OhtliColors.onyx.withOpacity(0.6), fontSize: 14),
                  decoration: InputDecoration(
                    labelText: 'Correo Electrónico (No editable)',
                    labelStyle: GoogleFonts.inter(color: OhtliColors.onyx.withOpacity(0.5)),
                    prefixIcon: const Icon(Icons.email_outlined, color: OhtliColors.stormyTeal, size: 20),
                    suffixIcon: Tooltip(
                      message: 'El correo electrónico es el identificador principal.',
                      child: Icon(Icons.info_outline_rounded, color: OhtliColors.onyx.withOpacity(0.4), size: 18),
                    ),
                    filled: true,
                    fillColor: OhtliColors.cloudDancer.withOpacity(0.5),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 16),

                // Nombres
                TextFormField(
                  controller: _firstNameController,
                  style: GoogleFonts.inter(color: OhtliColors.onyx, fontSize: 14),
                  validator: (value) => value == null || value.trim().isEmpty ? 'Ingresa tus nombres' : null,
                  decoration: InputDecoration(
                    labelText: 'Nombres',
                    labelStyle: GoogleFonts.inter(color: OhtliColors.onyx.withOpacity(0.5)),
                    prefixIcon: const Icon(Icons.person_outline_rounded, color: OhtliColors.stormyTeal, size: 20),
                    filled: true,
                    fillColor: OhtliColors.cloudDancer,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 16),

                // Apellidos
                TextFormField(
                  controller: _lastNameController,
                  style: GoogleFonts.inter(color: OhtliColors.onyx, fontSize: 14),
                  validator: (value) => value == null || value.trim().isEmpty ? 'Ingresa tus apellidos' : null,
                  decoration: InputDecoration(
                    labelText: 'Apellidos',
                    labelStyle: GoogleFonts.inter(color: OhtliColors.onyx.withOpacity(0.5)),
                    prefixIcon: const Icon(Icons.person_outline_rounded, color: OhtliColors.stormyTeal, size: 20),
                    filled: true,
                    fillColor: OhtliColors.cloudDancer,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 16),

                // Teléfono
                TextFormField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  style: GoogleFonts.inter(color: OhtliColors.onyx, fontSize: 14),
                  decoration: InputDecoration(
                    labelText: 'Número Telefónico',
                    labelStyle: GoogleFonts.inter(color: OhtliColors.onyx.withOpacity(0.5)),
                    prefixIcon: const Icon(Icons.phone_outlined, color: OhtliColors.stormyTeal, size: 20),
                    filled: true,
                    fillColor: OhtliColors.cloudDancer,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 28),

                // Botones
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => setState(() => _currentSection = AccountSection.dashboard),
                        child: Text('Cancelar', style: GoogleFonts.inter(color: OhtliColors.onyx.withOpacity(0.6))),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _isSavingProfile ? null : _savePersonalInfo,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: OhtliColors.stormyTeal,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          elevation: 0,
                        ),
                        child: _isSavingProfile
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                            : Text('Guardar', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // 2. Security subform
  Widget _buildSecurityForm() {
    return Card(
      elevation: 0,
      color: const Color(0xFFDCD8CF),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _securityFormKey,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Cambiar contraseña',
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: OhtliColors.onyx,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Por seguridad, requerimos verificar tu contraseña actual antes de actualizarla.',
                  style: GoogleFonts.inter(
                    fontSize: 12.5,
                    color: OhtliColors.onyx.withOpacity(0.55),
                  ),
                ),
                const SizedBox(height: 24),

                // Contraseña Actual
                TextFormField(
                  controller: _currentPasswordController,
                  obscureText: _obscureCurrent,
                  style: GoogleFonts.inter(color: OhtliColors.onyx, fontSize: 14),
                  validator: (value) => value == null || value.isEmpty ? 'Ingresa tu contraseña actual' : null,
                  decoration: InputDecoration(
                    labelText: 'Contraseña Actual',
                    labelStyle: GoogleFonts.inter(color: OhtliColors.onyx.withOpacity(0.5)),
                    prefixIcon: const Icon(Icons.lock_outline_rounded, color: OhtliColors.stormyTeal, size: 20),
                    suffixIcon: IconButton(
                      icon: Icon(_obscureCurrent ? Icons.visibility_rounded : Icons.visibility_off_rounded, size: 18),
                      onPressed: () => setState(() => _obscureCurrent = !_obscureCurrent),
                    ),
                    filled: true,
                    fillColor: OhtliColors.cloudDancer,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 16),

                // Nueva Contraseña
                TextFormField(
                  controller: _newPasswordController,
                  obscureText: _obscureNew,
                  style: GoogleFonts.inter(color: OhtliColors.onyx, fontSize: 14),
                  validator: (value) {
                    if (value == null || value.isEmpty) return 'Ingresa la nueva contraseña';
                    if (value.length < 6) return 'Debe tener al menos 6 caracteres';
                    return null;
                  },
                  decoration: InputDecoration(
                    labelText: 'Nueva Contraseña',
                    labelStyle: GoogleFonts.inter(color: OhtliColors.onyx.withOpacity(0.5)),
                    prefixIcon: const Icon(Icons.lock_rounded, color: OhtliColors.stormyTeal, size: 20),
                    suffixIcon: IconButton(
                      icon: Icon(_obscureNew ? Icons.visibility_rounded : Icons.visibility_off_rounded, size: 18),
                      onPressed: () => setState(() => _obscureNew = !_obscureNew),
                    ),
                    filled: true,
                    fillColor: OhtliColors.cloudDancer,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 16),

                // Confirmar Contraseña
                TextFormField(
                  controller: _confirmPasswordController,
                  obscureText: _obscureConfirm,
                  style: GoogleFonts.inter(color: OhtliColors.onyx, fontSize: 14),
                  validator: (value) => value == null || value.isEmpty ? 'Confirma la nueva contraseña' : null,
                  decoration: InputDecoration(
                    labelText: 'Confirmar Nueva Contraseña',
                    labelStyle: GoogleFonts.inter(color: OhtliColors.onyx.withOpacity(0.5)),
                    prefixIcon: const Icon(Icons.lock_rounded, color: OhtliColors.stormyTeal, size: 20),
                    suffixIcon: IconButton(
                      icon: Icon(_obscureConfirm ? Icons.visibility_rounded : Icons.visibility_off_rounded, size: 18),
                      onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                    ),
                    filled: true,
                    fillColor: OhtliColors.cloudDancer,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 28),

                // Botones
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => setState(() => _currentSection = AccountSection.dashboard),
                        child: Text('Cancelar', style: GoogleFonts.inter(color: OhtliColors.onyx.withOpacity(0.6))),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _isUpdatingPassword ? null : _changePassword,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: OhtliColors.stormyTeal,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          elevation: 0,
                        ),
                        child: _isUpdatingPassword
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                            : Text('Actualizar', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  IconData _getCategoryIcon(String? category) {
    switch (category?.trim().toLowerCase()) {
      case 'hogar': return Icons.home_rounded;
      case 'hotel': return Icons.hotel_rounded;
      case 'renta en app': return Icons.vpn_key_rounded;
      case 'familiar': return Icons.family_restroom_rounded;
      case 'amigos': return Icons.group_rounded;
      default: return Icons.location_on_rounded;
    }
  }

  // 3. Addresses CRUD view
  Widget _buildAddressesView() {
    if (_isEditingAddress) {
      if (!_isAddressPickerLoaded) {
        // Trigger dynamic loading if not already in progress
        if (!_isLoadingAddressPicker) {
          _loadAddressPicker();
        }
        return Card(
          elevation: 0,
          color: const Color(0xFFDCD8CF),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: const Padding(
            padding: EdgeInsets.all(40),
            child: Center(
              child: CircularProgressIndicator(color: OhtliColors.stormyTeal),
            ),
          ),
        );
      }

      return address_picker.AddressPickerWidget(
        initialAddress: _editingAddressIndex == null ? null : _addresses[_editingAddressIndex!],
        existingNames: _addresses
            .asMap()
            .entries
            .where((entry) => _editingAddressIndex == null || entry.key != _editingAddressIndex)
            .map((entry) => entry.value['customName'] as String? ?? '')
            .where((name) => name.isNotEmpty)
            .toList(),
        onSave: (addressData) {
          setState(() {
            if (_editingAddressIndex == null) {
              final String id = 'addr_${DateTime.now().millisecondsSinceEpoch}_${addressData['street'].hashCode}';
              addressData['id'] = id;
              _addresses.add(addressData);
            } else {
              final oldAddress = _addresses[_editingAddressIndex!];
              addressData['id'] = oldAddress['id'] ?? _getAddressId(oldAddress);
              _addresses[_editingAddressIndex!] = addressData;
            }
            _saveAddresses();
            _isEditingAddress = false;
          });

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                _editingAddressIndex == null
                    ? '¡Dirección agregada exitosamente!'
                    : '¡Dirección actualizada exitosamente!',
                style: GoogleFonts.inter(fontWeight: FontWeight.w500),
              ),
              backgroundColor: OhtliColors.stormyTeal,
            ),
          );
        },
        onCancel: () {
          setState(() {
            _isEditingAddress = false;
          });
        },
      );
    }

    return Card(
      elevation: 0,
      color: const Color(0xFFDCD8CF),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Mis Direcciones',
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: OhtliColors.onyx,
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: () {
                    setState(() {
                      _isEditingAddress = true;
                      _editingAddressIndex = null;
                    });
                  },
                  icon: const Icon(Icons.add, size: 16),
                  label: Text('Agregar', style: GoogleFonts.inter(fontWeight: FontWeight.w500)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: OhtliColors.stormyTeal,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            Expanded(
              child: _addresses.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.location_off_outlined, color: OhtliColors.onyx.withOpacity(0.2), size: 48),
                          const SizedBox(height: 12),
                          Text(
                            'No tienes direcciones guardadas.',
                            style: GoogleFonts.inter(
                              color: OhtliColors.onyx.withOpacity(0.5),
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '¡Agrega una para tus futuros viajes!',
                            style: GoogleFonts.inter(
                              color: OhtliColors.onyx.withOpacity(0.4),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      itemCount: _addresses.length,
                      itemBuilder: (context, index) {
                        final addr = _addresses[index];
                        final addressStr = "${addr['street'] ?? ''}, ${addr['suburb'] ?? ''}, C.P. ${addr['zip'] ?? ''}, ${addr['city'] ?? ''}, ${addr['state'] ?? ''}, ${addr['country'] ?? ''}";
                        
                        final hasCustomName = addr['customName'] != null && (addr['customName'] as String).trim().isNotEmpty;
                        final displayTitle = hasCustomName ? addr['customName'] as String : addr['street'] ?? 'Dirección';
                        
                        final category = addr['category'] as String? ?? 'Otro';
                        final icon = _getCategoryIcon(category);

                        return Card(
                          color: OhtliColors.cloudDancer,
                          elevation: 0,
                          margin: const EdgeInsets.only(bottom: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            leading: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: Color(0xFFDCD8CF),
                              ),
                              child: Icon(icon, color: OhtliColors.stormyTeal, size: 20),
                            ),
                            title: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    displayTitle,
                                    style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: OhtliColors.onyx, fontSize: 14.5),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: OhtliColors.stormyTeal.withOpacity(0.09),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    category,
                                    style: GoogleFonts.inter(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: OhtliColors.stormyTeal,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                hasCustomName ? "${addr['street'] ?? ''}\n$addressStr" : addressStr,
                                style: GoogleFonts.inter(fontSize: 12, color: OhtliColors.onyx.withOpacity(0.6), height: 1.3),
                              ),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.edit_rounded, color: OhtliColors.stormyTeal, size: 18),
                                  onPressed: () {
                                    setState(() {
                                      _isEditingAddress = true;
                                      _editingAddressIndex = index;
                                    });
                                  },
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline_rounded, color: OhtliColors.xoconostle, size: 18),
                                  onPressed: () {
                                    final user = FirebaseAuth.instance.currentUser;
                                    if (user != null) {
                                      final addr = _addresses[index];
                                      final addrId = _getAddressId(addr);
                                      _trackAddressDeletion(user.uid, addrId);
                                    }
                                    setState(() {
                                      _addresses.removeAt(index);
                                      _saveAddresses();
                                    });
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('Dirección eliminada correctamente.', style: GoogleFonts.inter()),
                                        backgroundColor: OhtliColors.stormyTeal,
                                      ),
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // Note: Local map picker and form views have been modularized and moved to lib/widgets/address_picker_widget.dart

  // 4. Privacy switches and Danger Zone (Account deletion)
  Widget _buildPrivacyView() {
    return Card(
      elevation: 0,
      color: const Color(0xFFDCD8CF),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Preferencias de Privacidad',
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: OhtliColors.onyx,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Configura cómo Ohtli interactúa y comparte tus datos de viaje.',
                style: GoogleFonts.inter(
                  fontSize: 12.5,
                  color: OhtliColors.onyx.withOpacity(0.55),
                ),
              ),
              const SizedBox(height: 24),

              // Switch 1: Compartir datos
              SwitchListTile(
                activeColor: OhtliColors.stormyTeal,
                contentPadding: EdgeInsets.zero,
                title: Text(
                  'Compartir datos de viaje',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: OhtliColors.onyx, fontSize: 14),
                ),
                subtitle: Text(
                  'Permite a Ohtli utilizar tu historial para sugerirte mejores rutas en base a tendencias de viaje.',
                  style: GoogleFonts.inter(fontSize: 12, color: OhtliColors.onyx.withOpacity(0.55)),
                ),
                value: _shareTravelData,
                onChanged: (val) {
                  setState(() {
                    _shareTravelData = val;
                    _savePrivacySetting('share', val);
                  });
                },
              ),
              const Divider(height: 32, color: OhtliColors.cantera),

              // Switch 2: Notificaciones
              SwitchListTile(
                activeColor: OhtliColors.stormyTeal,
                contentPadding: EdgeInsets.zero,
                title: Text(
                  'Recibir notificaciones',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: OhtliColors.onyx, fontSize: 14),
                ),
                subtitle: Text(
                  'Notificar sobre el estado de tu cuenta, actualizaciones de viaje y alertas del clima en CDMX.',
                  style: GoogleFonts.inter(fontSize: 12, color: OhtliColors.onyx.withOpacity(0.55)),
                ),
                value: _receiveNotifications,
                onChanged: (val) {
                  setState(() {
                    _receiveNotifications = val;
                    _savePrivacySetting('notifications', val);
                  });
                },
              ),
              const Divider(height: 32, color: OhtliColors.cantera),

              // Switch 3: Perfil público
              SwitchListTile(
                activeColor: OhtliColors.stormyTeal,
                contentPadding: EdgeInsets.zero,
                title: Text(
                  'Perfil público',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: OhtliColors.onyx, fontSize: 14),
                ),
                subtitle: Text(
                  'Permite que otros viajeros en Ohtli puedan buscar tu nombre y ver tus insignias de viaje alcanzadas.',
                  style: GoogleFonts.inter(fontSize: 12, color: OhtliColors.onyx.withOpacity(0.55)),
                ),
                value: _publicProfile,
                onChanged: (val) {
                  setState(() {
                    _publicProfile = val;
                    _savePrivacySetting('public', val);
                  });
                },
              ),
              const Divider(height: 32, color: OhtliColors.cantera),

              // DANGER ZONE: ACCOUNT DELETION
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: OhtliColors.xoconostle.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: OhtliColors.xoconostle.withOpacity(0.3), width: 1.2),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.warning_amber_rounded, color: OhtliColors.xoconostle, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'Zona de Peligro',
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w700,
                            color: OhtliColors.xoconostle,
                            fontSize: 13.5,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Al eliminar tu cuenta se borrarán irreversiblemente tus fotos, direcciones y datos locales de viaje de los servidores de Ohtli.',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: OhtliColors.onyx.withOpacity(0.65),
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      height: 38,
                      child: TextButton.icon(
                        onPressed: () => _showDeleteAccountDialog(context),
                        icon: const Icon(Icons.delete_forever_rounded, size: 18, color: Colors.white),
                        label: Text(
                          'Eliminar mi cuenta permanentemente',
                          style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 12.5),
                        ),
                        style: TextButton.styleFrom(
                          backgroundColor: OhtliColors.xoconostle,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 32),

              // Confirm and Back Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => setState(() => _currentSection = AccountSection.dashboard),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: OhtliColors.stormyTeal,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: Text('Confirmar y Volver', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Custom Config Card for Desktop Hover effects
class _DashboardCard extends StatefulWidget {
  final String title;
  final String description;
  final IconData icon;
  final VoidCallback onTap;

  const _DashboardCard({
    required this.title,
    required this.description,
    required this.icon,
    required this.onTap,
  });

  @override
  State<_DashboardCard> createState() => _DashboardCardState();
}

class _DashboardCardState extends State<_DashboardCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          width: 320,
          height: 140,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFFDCD8CF),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(_isHovered ? 0.12 : 0.05),
                blurRadius: _isHovered ? 14 : 6,
                offset: Offset(0, _isHovered ? 6 : 2),
              ),
            ],
          ),
          transform: Matrix4.identity()..translate(0.0, _isHovered ? -4.0 : 0.0, 0.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(widget.icon, color: OhtliColors.stormyTeal, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.title,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w700,
                        color: OhtliColors.onyx,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Expanded(
                child: Text(
                  widget.description,
                  style: GoogleFonts.inter(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w400,
                    color: OhtliColors.onyx.withOpacity(0.6),
                    height: 1.3,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

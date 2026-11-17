// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use, avoid_print, use_build_context_synchronously

import '../../services/ohtli_features.dart';
import 'dart:async';
import 'dart:convert';
import 'package:web/web.dart' as web;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../services/two_factor.dart';
import '../../widgets/phone_verification_field.dart';
import '../../widgets/two_factor_card.dart';
import '../../widgets/usertag_settings.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/user_private_data.dart';
import '../../services/photo_storage.dart';
import '../../services/profile_photo_service.dart';
import '../../services/feedback_service.dart';
import '../../theme/colors.dart';
import '../../widgets/ohtli_sidebar.dart';
import '../../widgets/feedback_dialog.dart';
import '../../widgets/ohtli_account_switcher.dart';
import '../../widgets/image_cropper_dialog.dart';
import '../../widgets/address_picker_widget.dart' as address_picker;
import '../../utils/friendly_errors.dart';
import 'public_profile_page.dart';
import '../admin/place_suggestions_page.dart';
import '../admin/explore_featured_page.dart';
import '../admin/admin_inbox_page.dart';
import '../../services/admin_inbox.dart';
import '../trips/trip_screens.dart' deferred as trips;
import '../../widgets/deferred_view.dart';
import '../../widgets/push_toggle.dart' show PushSettingTile;
import '../../config/admin.dart';
import '../../services/poi_suggestion_service.dart';
import '../../utils/web_helpers.dart';
import '../register/register_page.dart' show PasswordChecklist, PasswordRules;
import '../../services/public_profiles.dart';

enum AccountSection { dashboard, personalInfo, security, addresses, privacy, preferences, insider }

class AccountManagementPage extends StatefulWidget {
  final void Function(int index) onBackToHome;
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
  List<Map<String, dynamic>> get _activeAddresses {
    return _addresses.where((addr) => addr['isDeleted'] != true).toList();
  }

  bool _isEditingAddress = false;
  int? _editingAddressIndex;

  // Privacy state
  bool _shareTravelData = true;
  bool _receiveNotifications = true;
  bool _publicProfile = false;

  // Preferences state tracking
  OhtliThemeMode? _initialThemeMode;
  OhtliFontSize? _initialFontSize;

  // Synchronous loader state for AddressPickerWidget (to avoid browser loading locks)
  final bool _isAddressPickerLoaded = true;
  final bool _isLoadingAddressPicker = false;
  StreamSubscription<Map<String, dynamic>?>? _userDataSubscription;
  bool _isInitialSyncDone = false;

  Future<void> _loadAddressPicker() async {
    // No-op: library is imported synchronously
  }

  @override
  void initState() {
    super.initState();
    // Administrador: cuántas donaciones, reportes y comentarios esperan revisión
    if (isSuperUser()) {
      for (final section in AdminInboxSection.values) {
        _inboxSubs.add(AdminInbox.watchPending(section).listen((n) {
          if (mounted) setState(() => _inboxPending[section] = n);
        }, onError: (_) {}));
      }
    }
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
      localPhone = web.window.localStorage.getItem('ohtli_phone_${user.uid}') ?? '';
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

    if (web.document.getElementById('google-maps-places-script') != null) {
      return;
    }

    ensureScript(
      id: 'google-maps-places-script',
      src: 'https://maps.googleapis.com/maps/api/js?key=$activeKey&libraries=places&language=es&region=MX',
    );
  }

  void _syncUserData() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // 1. Load from localStorage synchronously for instant render
    final localPic = web.window.localStorage.getItem('ohtli_profile_pic_${user.uid}');
    if (localPic != null && localPic.isNotEmpty) {
      _localPhotoURL = localPic;
    } else {
      _localPhotoURL = user.photoURL;
    }

    final localPhone =
        web.window.localStorage.getItem('ohtli_phone_${user.uid}') ?? '';
    _phoneController.text = localPhone;

    final jsonStr = web.window.localStorage.getItem('ohtli_addresses_${user.uid}');
    if (jsonStr != null && jsonStr.isNotEmpty) {
      try {
        final List<dynamic> decoded = json.decode(jsonStr);
        _addresses = decoded.map((e) => Map<String, dynamic>.from(e)).toList();
      } catch (e) {
        print("Error decoding cached addresses: $e");
      }
    }

    // 2. Subscribe to real-time updates from Cloud Firestore
    // Perfil público + datos privados (users/{uid}/private/account) combinados
    _userDataSubscription = UserPrivateData.watch(user.uid)
        .listen(
          (data) {
            if (data == null) {
              if (!_isInitialSyncDone) {
                print(
                  "User document does not exist in Firestore. Creating it with local caches...",
                );
                final Map<String, dynamic> initialData = {
                  'privacy_share': _shareTravelData,
                  'privacy_notifications': _receiveNotifications,
                  'privacy_public': _publicProfile,
                };

                if (localPic != null && localPic.isNotEmpty) {
                  if (localPic.startsWith('data:image') ||
                      localPic.startsWith('data:')) {
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

                UserPrivateData.save(user.uid, initialData)
                    .then((_) {
                      print(
                        "Successfully initialized user cloud document with local caches.",
                      );
                    })
                    .catchError((e) {
                      print("Error initializing user cloud document: $e");
                    });
                _isInitialSyncDone = true;
              }
              return;
            }

            {
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
                    web.window.localStorage.setItem('ohtli_profile_pic_${user.uid}', remotePhoto);
                  }
                } else if (localPic != null && localPic.isNotEmpty) {
                  if (localPic.startsWith('data:image') ||
                      localPic.startsWith('data:')) {
                    _uploadLocalPhotoToFirestore(user.uid, localPic);
                  } else {
                    uploadData['photoURL'] = localPic;
                    needUpload = true;
                  }
                }
              } else if (localPic != null && localPic.isNotEmpty) {
                if (localPic.startsWith('data:image') ||
                    localPic.startsWith('data:')) {
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
                    web.window.localStorage.setItem('ohtli_phone_${user.uid}', remotePhone);
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
                    web.window.localStorage.setItem('ohtli_privacy_share_${user.uid}', remoteShare.toString());
                  }
                }
              } else {
                uploadData['privacy_share'] = _shareTravelData;
                needUpload = true;
              }

              if (data.containsKey('privacy_notifications')) {
                final bool? remoteNotifications =
                    data['privacy_notifications'] as bool?;
                if (remoteNotifications != null) {
                  if (mounted) {
                    setState(() {
                      _receiveNotifications = remoteNotifications;
                    });
                    web.window.localStorage.setItem('ohtli_privacy_notifications_${user.uid}', remoteNotifications.toString());
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
                    web.window.localStorage.setItem('ohtli_privacy_public_${user.uid}', remotePublic.toString());
                  }
                }
              } else {
                uploadData['privacy_public'] = _publicProfile;
                needUpload = true;
              }

              // D. Sync / Reconcile Addresses
              List<Map<String, dynamic>> cloudList = [];
              if (data.containsKey('addresses')) {
                final List<dynamic>? remoteList =
                    data['addresses'] as List<dynamic>?;
                if (remoteList != null) {
                  cloudList = remoteList
                      .map((e) => Map<String, dynamic>.from(e))
                      .toList();
                }
              }

              if (!_isInitialSyncDone) {
                // Reconcile offline additions and deletions only once on first load
                final deletedIds = _getDeletedAddressIds(user.uid);
                final reconciled = _reconcileAddresses(
                  _addresses,
                  cloudList,
                  deletedIds,
                );

                if (!_areAddressListsEqual(_addresses, reconciled)) {
                  if (mounted) {
                    setState(() {
                      _addresses = reconciled;
                    });
                    web.window.localStorage.setItem('ohtli_addresses_${user.uid}', json.encode(_addresses));
                  }
                }

                if (!_areAddressListsEqual(cloudList, reconciled)) {
                  uploadData['addresses'] = reconciled;
                  needUpload = true;
                }

                web.window.localStorage.setItem('ohtli_deleted_addresses_${user.uid}', json
                    .encode([]));
                _isInitialSyncDone = true;
              } else {
                // Subsequent stream updates: accept the cloud as the absolute source of truth
                // to guarantee that creations, edits, and deletions on any other device reflect instantly.
                if (!_areAddressListsEqual(_addresses, cloudList)) {
                  if (mounted) {
                    setState(() {
                      _addresses = cloudList;
                    });
                    web.window.localStorage.setItem('ohtli_addresses_${user.uid}', json.encode(_addresses));
                  }
                }
              }

              if (needUpload && uploadData.isNotEmpty) {
                UserPrivateData.save(user.uid, uploadData)
                    .catchError((e) {
                      print("Error syncing local caches to Firestore: $e");
                    });
              }
            }
          },
          onError: (e) {
            print("Error listening to user data Firestore stream: $e");
          },
        );
  }

  void _uploadLocalPhotoToFirestore(String uid, String base64String) async {
    // Only upload to Firebase Storage (the lowest cost option)
    try {
      final String downloadUrl =
          await PhotoStorage.uploadDataUrl('users/$uid/profile.jpg', base64String, replaces: true);

      // Update localStorage with the verified bucket URL
      web.window.localStorage.setItem('ohtli_profile_pic_$uid', downloadUrl);

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
      await PublicProfiles.mirror(uid, {'photoURL': downloadUrl});
      print(
        "Successfully migrated local photo to Firebase Storage and synced URL to Firestore.",
      );
    } catch (e) {
      // Storage failed or not enabled. Keep base64 ONLY locally (no cost in Firestore!)
      print(
        "Storage migration failed. Kept photo exclusively local to avoid Firestore base64 costs: $e",
      );
    }
  }

  final List<StreamSubscription<int>> _inboxSubs = [];
  final Map<AdminInboxSection, int> _inboxPending = {};

  @override
  void dispose() {
    for (final sub in _inboxSubs) {
      sub.cancel();
    }
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
    web.window.localStorage.setItem('ohtli_addresses_${user.uid}', json.encode(
      _addresses,
    ));

    // 2. Write to Cloud Firestore to sync across all devices — await to detect errors
    try {
      // Strip 'isOffline' before writing to Firestore
      final List<Map<String, dynamic>> uploadList = _addresses.map((e) {
        final Map<String, dynamic> copy = Map<String, dynamic>.from(e);
        copy.remove('isOffline');
        return copy;
      }).toList();

      await UserPrivateData.save(user.uid, {'addresses': uploadList});

      // Successfully wrote to Firestore! Clean 'isOffline' locally too
      setState(() {
        for (final addr in _addresses) {
          addr.remove('isOffline');
        }
      });
      web.window.localStorage.setItem('ohtli_addresses_${user.uid}', json.encode(
        _addresses,
      ));
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
    final jsonStr = web.window.localStorage.getItem('ohtli_deleted_addresses_$uid');
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
    web.window.localStorage.setItem('ohtli_deleted_addresses_$uid', json.encode(
      deleted.toList(),
    ));
  }

  List<Map<String, dynamic>> _reconcileAddresses(
    List<Map<String, dynamic>> localList,
    List<Map<String, dynamic>> cloudList,
    Set<String> deletedIds,
  ) {
    final List<Map<String, dynamic>> reconciled = [];
    final Map<String, Map<String, dynamic>> mergedMap = {};

    // Helper to check if deletion is older than 7 days (1 week)
    bool isDeletionExpired(Map<String, dynamic> addr) {
      if (addr['isDeleted'] != true) return false;
      final deletedAt = addr['deletedAt'];
      if (deletedAt == null) return true;
      final int deletedTime = deletedAt is int
          ? deletedAt
          : (int.tryParse(deletedAt.toString()) ?? 0);
      final now = DateTime.now().millisecondsSinceEpoch;
      const oneWeekMs = 7 * 24 * 60 * 60 * 1000;
      return (now - deletedTime) >= oneWeekMs;
    }

    // Combine lists, preferring the fresher record based on the updatedAt timestamp
    void processAddress(Map<String, dynamic> addr) {
      final id = _getAddressId(addr);

      // If the address has been marked deleted for over 7 days, completely purge it!
      if (isDeletionExpired(addr)) {
        print("Purging expired deleted address: $id");
        mergedMap.remove(id);
        return;
      }

      if (mergedMap.containsKey(id)) {
        final existing = mergedMap[id]!;
        final int existingUpdate = existing['updatedAt'] is int
            ? existing['updatedAt']
            : (int.tryParse(existing['updatedAt'].toString()) ?? 0);
        final int incomingUpdate = addr['updatedAt'] is int
            ? addr['updatedAt']
            : (int.tryParse(addr['updatedAt'].toString()) ?? 0);

        if (incomingUpdate > existingUpdate) {
          mergedMap[id] = addr;
        }
      } else {
        // Discard local-only stale cached items if deleted in the cloud (and not marked isOffline)
        final isLocalOnly = !cloudList.any((e) => _getAddressId(e) == id);
        if (isLocalOnly &&
            addr['isDeleted'] != true &&
            addr['isOffline'] != true) {
          print("Discarding stale cached address: $id");
          return;
        }
        mergedMap[id] = addr;
      }
    }

    // Process local and cloud items to resolve conflicts
    for (final addr in localList) {
      processAddress(addr);
    }
    for (final addr in cloudList) {
      processAddress(addr);
    }

    // Export merged active & active-deleted entries
    for (final addr in mergedMap.values) {
      if (!isDeletionExpired(addr)) {
        reconciled.add(addr);
      }
    }

    return reconciled;
  }

  bool _areAddressListsEqual(
    List<Map<String, dynamic>> listA,
    List<Map<String, dynamic>> listB,
  ) {
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
    _shareTravelData =
        web.window.localStorage.getItem('ohtli_privacy_share_${user.uid}') != 'false';
    _receiveNotifications =
        web.window.localStorage.getItem('ohtli_privacy_notifications_${user.uid}') !=
        'false';
    _publicProfile =
        web.window.localStorage.getItem('ohtli_privacy_public_${user.uid}') != 'false';
  }

  void _savePrivacySetting(String key, bool value) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    web.window.localStorage.setItem('ohtli_privacy_${key}_${user.uid}', value
        .toString());

    // Also sync to Cloud Firestore!
    UserPrivateData.save(user.uid, {'privacy_$key': value})
        .catchError((e) {
          print("Error saving privacy setting to Firestore: $e");
        });
  }

  // Photo Upload Handler (avoiding Firebase URL size limit)
  Future<void> _handlePhotoUpload() async {
    if (!kIsWeb) return;

    try {
      final picked = await pickFile(accept: 'image/*,.cr2,.nef,.arw,.dng,.orf,.pef,.rw2,.raf,.raw');
      if (picked == null) return;
              try {
                final Uint8List bytes = picked.bytes;

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
                                web.window.localStorage.setItem('ohtli_profile_pic_${user.uid}', base64String);

                                // Storage + users/{uid} + perfil público + Auth, igual que en el onboarding
                                String? downloadUrl;
                                try {
                                  downloadUrl = await ProfilePhotoService.upload(base64String);
                                } catch (storageError) {
                                  print("Firebase Storage upload error: $storageError");
                                }

                                if (downloadUrl != null) {
                                  _localPhotoURL = downloadUrl;
                                  if (mounted) {
                                    setState(() {});
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          '¡Foto de perfil sincronizada en la nube exitosamente!',
                                          style: GoogleFonts.inter(
                                            fontWeight: FontWeight.w500,
                                          ),
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
                                          style: GoogleFonts.inter(
                                            fontWeight: FontWeight.w500,
                                          ),
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
                                    content: Text(
                                      'Error al guardar la imagen: ${err.toString()}',
                                    ),
                                    backgroundColor: OhtliColors.warning,
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
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(friendlyError(e)),
          backgroundColor: OhtliColors.warning,
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
        final newName =
            "${_firstNameController.text.trim()} ${_lastNameController.text.trim()}"
                .trim();
        final phoneText = _phoneController.text.trim();

        // Check if anything actually changed to avoid unnecessary operations
        final nameChanged =
            newName.isNotEmpty && newName != (user.displayName ?? '');

        if (nameChanged) {
          await user.updateDisplayName(newName);
        }

        // Save phone to LocalStorage
        web.window.localStorage.setItem('ohtli_phone_${user.uid}', phoneText);

        // Also persist name, email, and phone to Cloud Firestore for robust cross-device sync
        try {
          // displayName va al perfil público; email y teléfono, al documento privado
          await UserPrivateData.save(user.uid, {
                'displayName': newName,
                'email': user.email ?? '',
                'updatedAt': FieldValue.serverTimestamp(),
              });
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
            content: Text(friendlyError(e)),
            backgroundColor: OhtliColors.warning,
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
          backgroundColor: OhtliColors.warning,
        ),
      );
      return;
    }

    setState(() => _isUpdatingPassword = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null && user.email != null) {
        bool hasPassword = false;
        for (final info in user.providerData) {
          if (info.providerId == 'password') {
            hasPassword = true;
          }
        }

        if (hasPassword) {
          // Reauthenticate
          final credential = EmailAuthProvider.credential(
            email: user.email!,
            password: currentPassword,
          );
          await TwoFactor.reauthenticate(context, user, credential);
        }
        
        await user.updatePassword(newPassword);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                hasPassword ? '¡Contraseña cambiada exitosamente!' : '¡Contraseña creada exitosamente!',
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
      String errorMessage =
          'Error al actualizar contraseña. Verifica tu contraseña actual.';
      if (e is FirebaseAuthException) {
        if (e.code == 'wrong-password') {
          errorMessage = 'La contraseña actual es incorrecta.';
        } else if (e.code == 'weak-password') {
          errorMessage = 'La nueva contraseña es muy débil.';
        } else if (e.code == 'requires-recent-login') {
          errorMessage = 'Debes cerrar sesión y volver a entrar antes de poder crear una contraseña por primera vez.';
        }
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: OhtliColors.warning,
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

    bool hasPassword = false;
    for (final info in user.providerData) {
      if (info.providerId == 'password') {
        hasPassword = true;
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
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: Row(
                children: [
                  const Icon(
                    Icons.delete_forever_rounded,
                    color: OhtliColors.warning,
                    size: 24,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '¿Eliminar cuenta?',
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.bold,
                      color: OhtliColors.onyx,
                      fontSize: 18,
                    ),
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
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: OhtliColors.onyx.withValues(alpha: 0.7),
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 20),
                    if (!hasPassword) ...[
                      Text(
                        'Por seguridad, debes crear una contraseña en la sección de Seguridad antes de poder eliminar tu cuenta.',
                        style: GoogleFonts.inter(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                          color: OhtliColors.warningText,
                        ),
                      ),
                      const SizedBox(height: 16),
                    ] else ...[
                      TextFormField(
                        controller: deletePasswordController,
                        obscureText: true,
                        style: GoogleFonts.inter(
                          color: OhtliColors.onyx,
                          fontSize: 14,
                        ),
                        validator: (value) => value == null || value.isEmpty
                            ? 'Ingresa tu contraseña actual'
                            : null,
                        decoration: InputDecoration(
                          labelText: 'Contraseña actual',
                          labelStyle: GoogleFonts.inter(
                            color: OhtliColors.onyx.withValues(alpha: 0.5),
                          ),
                          prefixIcon: const Icon(
                            Icons.lock_outline_rounded,
                            color: OhtliColors.stormyTeal,
                            size: 20,
                          ),
                          filled: true,
                          fillColor: OhtliColors.cantera.withValues(alpha: 0.3),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    if (isDeleting)
                      const Center(
                        child: CircularProgressIndicator(
                          color: OhtliColors.warning,
                        ),
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isDeleting
                      ? null
                      : () => Navigator.of(context).pop(),
                  child: Text(
                    'Cancelar',
                    style: GoogleFonts.inter(
                      color: OhtliColors.onyx.withValues(alpha: 0.6),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                if (!hasPassword)
                  ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                      setState(() {
                        _currentSection = AccountSection.security;
                      });
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: OhtliColors.stormyTeal,
                      foregroundColor: Colors.white,
                    ),
                    child: Text(
                      'Ir a Seguridad',
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  )
                else
                  ElevatedButton(
                    onPressed: isDeleting
                        ? null
                        : () async {
                            if (!deleteFormKey.currentState!.validate()) {
                              return;
                            }

                            setDialogState(() => isDeleting = true);

                            try {
                              // Email re-authentication
                              final credential = EmailAuthProvider.credential(
                                email: user.email!,
                                password: deletePasswordController.text,
                              );
                              await TwoFactor.reauthenticate(context, user, credential);

                            // Delete local storage keys securely
                            web.window.localStorage.removeItem(
                              'ohtli_profile_pic_${user.uid}',
                            );
                            web.window.localStorage.removeItem(
                              'ohtli_phone_${user.uid}',
                            );
                            web.window.localStorage.removeItem(
                              'ohtli_addresses_${user.uid}',
                            );
                            web.window.localStorage.removeItem(
                              'ohtli_privacy_share_${user.uid}',
                            );
                            web.window.localStorage.removeItem(
                              'ohtli_privacy_notifications_${user.uid}',
                            );
                            web.window.localStorage.removeItem(
                              'ohtli_privacy_public_${user.uid}',
                            );

                            // Flag Firestore document as deleted (to be deleted permanently in 30 days)
                            try {
                              await UserPrivateData.save(user.uid, {
                                    'email': user.email ?? '',
                                    'isDeleted': true,
                                    'deletedAt': FieldValue.serverTimestamp(),
                                    'scheduledDeletionAt': Timestamp.fromDate(
                                      DateTime.now().add(
                                        const Duration(days: 30),
                                      ),
                                    ),
                                    'updatedAt': FieldValue.serverTimestamp(),
                                  });
                              print(
                                "Successfully marked Firestore user document as deleted for 30 days.",
                              );
                            } catch (fsError) {
                              print(
                                "Error marking user as deleted in Firestore: $fsError",
                              );
                            }

                            // Lo que el motor aprendió del uso de la cuenta (ARCO); antes de borrar el usuario
                            await FeedbackService.deleteMine();

                            // Delete the user from Firebase
                            await user.delete();

                            if (mounted) {
                              Navigator.of(context).pop(); // Close dialog
                              ScaffoldMessenger.of(parentContext).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'Tu cuenta ha sido eliminada permanentemente. Esperamos volver a verte.',
                                    style: GoogleFonts.inter(
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  backgroundColor: OhtliColors.warning,
                                  duration: const Duration(seconds: 4),
                                ),
                              );
                              widget.onLogout();
                            }
                          } catch (e) {
                            String err =
                                'Error al re-autenticar o eliminar la cuenta. Inténtalo de nuevo.';
                            if (e is FirebaseAuthException) {
                              if (e.code == 'wrong-password') {
                                err = 'La contraseña ingresada es incorrecta.';
                              } else if (e.code == 'user-mismatch') {
                                err =
                                    'La cuenta de re-autenticación no coincide con la cuenta actual.';
                              }
                            }

                            if (mounted) {
                              ScaffoldMessenger.of(parentContext).showSnackBar(
                                SnackBar(
                                  content: Text(err),
                                  backgroundColor: OhtliColors.warning,
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
                    backgroundColor: OhtliColors.warning,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    'Confirmar y Eliminar',
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
      } else {
        avatarContent = ClipOval(
          child: Image.network(
            photoURL,
            width: radius * 2,
            height: radius * 2,
            fit: BoxFit.cover,
            // Mientras llega la foto se ven las iniciales, no un círculo vacío
            frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
              if (wasSynchronouslyLoaded || frame != null) return child;
              return Center(
                child: Text(
                  initials,
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: radius * 0.7,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              );
            },
            errorBuilder: (context, error, stackTrace) {
              return Center(
                child: Text(
                  initials,
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: radius * 0.7,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              );
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
                Positioned(top: 0, left: 0, child: mainAvatar),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: OhtliColors.stormyTeal,
                        width: 2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.15),
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
        child: MouseRegion(cursor: SystemMouseCursors.click, child: mainAvatar),
      );
    }

    return mainAvatar;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: OhtliSettings.instance,
      builder: (context, _) {
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          final localPic =
              web.window.localStorage.getItem('ohtli_profile_pic_${user.uid}');
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
        final isMobile = ohtliIsMobileWidth(screenSize.width);
    // Escritorio: navegación de ajustes a la izquierda y la sección elegida a la derecha.
    // Teléfono: la lista de ajustes y, al abrir una sección, su encabezado con flecha atrás.
    final Widget content = AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      transitionBuilder: (child, anim) => FadeTransition(opacity: anim, child: child),
      child: KeyedSubtree(
        key: ValueKey('${_currentSection.name}-$_isEditingAddress'),
        child: _currentSection == AccountSection.dashboard
            ? (isMobile
                ? _buildDashboard(user, displayName, initials, isMobile)
                : _buildOverview(user, displayName, initials))
            : _sectionFrame(_currentSection, _buildActiveContent(user, displayName, initials, isMobile), isMobile),
      ),
    );

    Widget mainBody = Theme(
      data: _formTheme(Theme.of(context)),
      child: SafeArea(
        child: isMobile
            ? Column(
                children: [
                  _buildAppBar(isMobile),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                      child: content,
                    ),
                  ),
                ],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(width: 300, child: _buildDesktopNav(user, displayName, initials)),
                  Container(width: 1, color: OhtliColors.cardBorder),
                  Expanded(
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        // Direcciones lleva el mapa al lado de los campos: 150 px más ancha.
                        constraints: BoxConstraints(maxWidth: _currentSection == AccountSection.addresses ? 910 : 760),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(40, 36, 40, 24),
                          child: content,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );

    if (isMobile) {
      return Scaffold(backgroundColor: OhtliColors.cloudDancer, body: mainBody);
    }

    // Desktop: Row with persistent sidebar on the left and main configuration screen on the right
    return Scaffold(
      backgroundColor: OhtliColors.cloudDancer,
      body: Row(
        children: [
          // ========= PERSISTENT SIDEBAR =========
          // ========= SIDEBAR =========
          OhtliSidebar(
            currentIndex: 2, // Highlight avatar/account
            onTabSelected: (index) {
              widget.onBackToHome(index);
            },
            onNavigateToAccount: () {
              if (_currentSection != AccountSection.dashboard) {
                setState(() {
                  _currentSection = AccountSection.dashboard;
                });
              } else {
                widget.onBackToHome(0); // Act as toggle!
              }
            },
            onLogout: widget.onLogout,
          ),

          // Main configuration page body
          Expanded(child: mainBody),
        ],
      ),
    );
      },
    );
  }

  Widget _buildAppBar(bool isMobile) {
    if (!isMobile) {
      return const SizedBox(height: 24); // Clean top spacing on desktop
    }

    final user = FirebaseAuth.instance.currentUser;
    final displayName = user?.displayName ?? user?.email ?? 'Viajero';
    final initials = displayName
        .split(' ')
        .where((w) => w.isNotEmpty)
        .take(2)
        .map((w) => w[0].toUpperCase())
        .join();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Left: Ohtli Logo SVG
          SizedBox(
            height: 32,
            child: SvgPicture.asset(
              'assets/icon_isologo.svg',
              fit: BoxFit.contain,
              colorFilter: const ColorFilter.mode(OhtliColors.stormyTeal, BlendMode.srcIn),
            ),
          ),

          // Right: Toggle Avatar Button
          _buildAvatarWidget(
            radius: 18,
            initials: initials,
            photoURL: _localPhotoURL,
            onTap: () {
              if (_currentSection != AccountSection.dashboard) {
                setState(() {
                  _currentSection = AccountSection.dashboard;
                  _isEditingAddress = false;
                });
              } else {
                widget.onBackToHome(0); // Toggles back to main view (home page)
              }
            },
          ),
        ],
      ),
    );
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
      case AccountSection.preferences:
        return _buildPreferencesView();
      case AccountSection.insider:
        return const _InsiderSettings();
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
            style: GoogleFonts.outfit(
              fontSize: isMobile ? 26 : 30,
              fontWeight: FontWeight.w800,
              color: OhtliColors.onyx,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 4),

          // User Email
          Text(
            user?.email ?? '',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w400,
              color: OhtliColors.onyx.withValues(alpha: 0.55),
            ),
          ),
          const SizedBox(height: 14),
          if (user != null)
            OutlinedButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (ctx) => PublicProfilePage(
                    userId: user.uid,
                    showBackButton: true,
                    onBack: () => Navigator.pop(ctx),
                  ),
                ),
              ),
              icon: const Icon(Icons.badge_outlined, size: 18),
              label: Text('Ver mi perfil', style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
              style: OutlinedButton.styleFrom(
                foregroundColor: OhtliColors.accentText,
                side: BorderSide(color: OhtliColors.accentText.withValues(alpha: 0.5)),
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              ),
            ),
          const SizedBox(height: 28),

          // Ajustes agrupados (mismo diseño en móvil y escritorio)
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSettingsGroup('Tu cuenta', _accountItems()),
                const SizedBox(height: 22),
                _buildSettingsGroup('Tu experiencia', _experienceItems()),
                // Solo para el superusuario
                if (isSuperUser(user)) ...[
                  Builder(builder: (_) {
                    SuperUserDirectory.registerCurrentSuperUser();
                    return const SizedBox(height: 22);
                  }),
                  StreamBuilder<int>(
                    stream: PoiSuggestionService.watchPendingCount(),
                    builder: (context, snap) {
                      final pending = snap.data ?? 0;
                      return _buildSettingsGroup('Administración', _adminItems(pending));
                    },
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 40),

          // En móvil no hay menú lateral: aquí se cambia de cuenta y se cierra sesión.
          if (isMobile) ...[
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: OhtliAccountSwitcherSection(onLogout: widget.onLogout),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: 200,
              child: OutlinedButton.icon(
                onPressed: () => AccountSwitchActions.logoutKeepingRemembered(widget.onLogout),
                icon: const Icon(
                  Icons.logout_rounded,
                  size: 18,
                  color: OhtliColors.warning,
                ),
                label: Text(
                  'Cerrar sesión',
                  style: GoogleFonts.inter(
                    color: OhtliColors.warningText,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(
                    color: OhtliColors.warning,
                    width: 1.5,
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
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

  /// Título y descripción de cada sección (en el encabezado del panel).
  static const Map<AccountSection, (String, String)> _sectionInfo = {
    AccountSection.dashboard: ('Tu cuenta', 'Tu foto, tu nombre y cómo te ven los demás.'),
    AccountSection.personalInfo: ('Información personal', 'Tu nombre y cómo te podemos contactar.'),
    AccountSection.security: ('Seguridad', 'Tu contraseña y las cuentas con las que entras.'),
    AccountSection.addresses: ('Direcciones', 'Puntos de partida guardados para planear tus rutas.'),
    AccountSection.privacy: ('Privacidad', 'Quién ve tu perfil, tus viajes y tus datos.'),
    AccountSection.preferences: ('Preferencias y accesibilidad', 'Tema, colores y tamaño de letra.'),
    AccountSection.insider: ('Ohtli Insider', 'Las funciones en prueba de los estudios de Ohtli Labs en los que participas.'),
  };

  void _openSection(AccountSection section) => setState(() {
        _currentSection = section;
        _isEditingAddress = false;
      });

  /// Campos con borde visible y contorno de enfoque, y botones redondeados, en todas las
  /// secciones sin repetir el estilo en cada campo.
  ThemeData _formTheme(ThemeData base) {
    OutlineInputBorder border(Color c, double w) =>
        OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: c, width: w));
    return base.copyWith(
      inputDecorationTheme: base.inputDecorationTheme.copyWith(
        enabledBorder: border(OhtliColors.cardBorder, 1),
        focusedBorder: border(OhtliColors.accentText, 1.6),
        errorBorder: border(OhtliColors.warning, 1.2),
        focusedErrorBorder: border(OhtliColors.warning, 1.6),
        floatingLabelStyle: GoogleFonts.inter(color: OhtliColors.accentText, fontWeight: FontWeight.w600),
      ),
      textSelectionTheme: TextSelectionThemeData(cursorColor: OhtliColors.accentText),
    );
  }

  /// Encabezado de una sección: en teléfono con flecha para volver a la lista.
  Widget _sectionFrame(AccountSection section, Widget child, bool isMobile) {
    final (title, subtitle) = _sectionInfo[section]!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isMobile) ...[
              IconButton(
                tooltip: 'Volver a Cuenta',
                onPressed: () => _openSection(AccountSection.dashboard),
                icon: Icon(Icons.arrow_back_rounded, color: OhtliColors.onyx),
              ),
              const SizedBox(width: 4),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Semantics(
                    header: true,
                    child: Text(
                      title,
                      style: GoogleFonts.outfit(
                        fontSize: isMobile ? 24 : 30,
                        fontWeight: FontWeight.w800,
                        color: OhtliColors.onyx,
                        letterSpacing: -0.6,
                        height: 1.1,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: GoogleFonts.inter(fontSize: 14, color: OhtliColors.subtleText, height: 1.4),
                  ),
                ],
              ),
            ),
          ],
        ),
        SizedBox(height: isMobile ? 16 : 24),
        // Arriba y a la medida de su contenido (con scroll si no cabe), no estirada
        Expanded(child: Align(alignment: Alignment.topCenter, child: child)),
      ],
    );
  }

  List<_SettingsItem> _accountItems() => [
        _SettingsItem(
          icon: Icons.person_outline_rounded,
          title: 'Información personal',
          subtitle: 'Tu nombre y datos de contacto',
          section: AccountSection.personalInfo,
          onTap: () => _openSection(AccountSection.personalInfo),
        ),
        _SettingsItem(
          icon: Icons.lock_outline_rounded,
          title: 'Seguridad',
          subtitle: 'Contraseña y cuentas vinculadas',
          section: AccountSection.security,
          onTap: () => _openSection(AccountSection.security),
        ),
        _SettingsItem(
          icon: Icons.location_on_outlined,
          title: 'Direcciones',
          subtitle: 'Puntos de partida para tus rutas',
          section: AccountSection.addresses,
          onTap: () => _openSection(AccountSection.addresses),
        ),
      ];

  List<_SettingsItem> _experienceItems() => [
        _SettingsItem(
          icon: Icons.privacy_tip_outlined,
          title: 'Privacidad',
          subtitle: 'Quién ve tu perfil y tus viajes',
          section: AccountSection.privacy,
          onTap: () => _openSection(AccountSection.privacy),
        ),
        _SettingsItem(
          icon: Icons.accessibility_new_rounded,
          title: 'Preferencias y accesibilidad',
          subtitle: 'Tema, colores y tamaño de letra',
          section: AccountSection.preferences,
          onTap: () => _openSection(AccountSection.preferences),
        ),
        // Solo testers de Ohtli Labs: activar la sección Ohtli Insider (oculta por defecto).
        if (OhtliFeatures.instance.access.value.isTester)
          _SettingsItem(
            icon: Icons.science_outlined,
            title: 'Ohtli Insider',
            subtitle: 'Funciones en prueba de tus estudios',
            section: AccountSection.insider,
            onTap: () => _openSection(AccountSection.insider),
          ),
        _SettingsItem(
          icon: Icons.rate_review_outlined,
          title: 'Enviar comentarios',
          subtitle: 'Cuéntanos qué mejorar o qué falló',
          opensDialog: true,
          onTap: () => showFeedbackDialog(context, screen: 'mi_cuenta'),
        ),
      ];

  List<_SettingsItem> _adminItems(int pending) => [
        _SettingsItem(
          icon: Icons.add_location_alt_outlined,
          title: pending > 0 ? 'Lugares sugeridos · $pending' : 'Lugares sugeridos',
          subtitle: 'Revisa y aprueba lugares nuevos',
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PlaceSuggestionsPage())),
        ),
        // Bandeja de administración: tres secciones separadas, cada una con su aviso por correo
        for (final (section, icon, subtitle) in const [
          (AdminInboxSection.donations, Icons.volunteer_activism_outlined, 'Fotos donadas a los lugares'),
          (AdminInboxSection.reports, Icons.flag_outlined, 'Datos de lugares por corregir'),
          (AdminInboxSection.feedback, Icons.rate_review_outlined, 'Ideas y fallas con capturas y datos del equipo'),
        ])
          _SettingsItem(
            icon: icon,
            title: (_inboxPending[section] ?? 0) > 0 ? '${section.label} · ${_inboxPending[section]}' : section.label,
            subtitle: subtitle,
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AdminInboxPage(initial: section))),
          ),
        _SettingsItem(
          icon: Icons.push_pin_outlined,
          title: 'Destacados de Explorar',
          subtitle: 'Viajes del bloque principal',
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ExploreFeaturedPage())),
        ),
        _SettingsItem(
          icon: Icons.new_releases_outlined,
          title: 'Notas de versión',
          subtitle: 'La crónica de cada versión',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => DeferredView(load: trips.loadLibrary, builder: (_) => trips.ReleaseNotesAdminPage()),
            ),
          ),
        ),
      ];

  /// Columna izquierda en escritorio: tu perfil arriba y las secciones agrupadas.
  Widget _buildDesktopNav(User? user, String displayName, String initials) {
    final onDashboard = _currentSection == AccountSection.dashboard;
    Widget groupLabel(String text) => Padding(
          padding: const EdgeInsets.fromLTRB(12, 22, 12, 8),
          child: Text(
            text.toUpperCase(),
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.1,
              color: OhtliColors.subtleText,
            ),
          ),
        );
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 32, 16, 24),
      children: [
        Material(
          color: onDashboard ? OhtliColors.stormyTeal.withValues(alpha: 0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => _openSection(AccountSection.dashboard),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  _buildAvatarWidget(radius: 22, initials: initials, photoURL: _localPhotoURL),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w700, color: OhtliColors.onyx),
                        ),
                        Text(
                          user?.email ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(fontSize: 12, color: OhtliColors.subtleText),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        groupLabel('Tu cuenta'),
        for (final item in _accountItems()) _navTile(item),
        groupLabel('Tu experiencia'),
        for (final item in _experienceItems()) _navTile(item),
        if (isSuperUser(user))
          StreamBuilder<int>(
            stream: PoiSuggestionService.watchPendingCount(),
            builder: (context, snap) {
              SuperUserDirectory.registerCurrentSuperUser();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  groupLabel('Administración'),
                  for (final item in _adminItems(snap.data ?? 0)) _navTile(item),
                ],
              );
            },
          ),
      ],
    );
  }

  Widget _navTile(_SettingsItem item) {
    final selected = item.section != null && item.section == _currentSection;
    final fg = selected ? OhtliColors.accentText : OhtliColors.onyx;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: selected ? OhtliColors.stormyTeal.withValues(alpha: 0.12) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: item.onTap,
          child: Semantics(
            selected: selected,
            button: true,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              child: Row(
                children: [
                  Icon(item.icon, size: 20, color: selected ? OhtliColors.accentText : OhtliColors.subtleText),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      item.title,
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                        color: fg,
                      ),
                    ),
                  ),
                  if (item.section == null && !item.opensDialog)
                    Icon(Icons.open_in_new_rounded, size: 15, color: OhtliColors.subtleText),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Resumen en escritorio cuando no hay sección abierta: tu foto, nombre y perfil público.
  Widget _buildOverview(User? user, String displayName, String initials) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Tu cuenta',
            style: GoogleFonts.outfit(fontSize: 30, fontWeight: FontWeight.w800, color: OhtliColors.onyx, letterSpacing: -0.6),
          ),
          const SizedBox(height: 4),
          Text(
            'Tu foto, tu nombre y cómo te ven los demás.',
            style: GoogleFonts.inter(fontSize: 14, color: OhtliColors.subtleText),
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: OhtliColors.cardBg,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: OhtliColors.cardBorder),
            ),
            child: Row(
              children: [
                _buildAvatarWidget(
                  radius: 56,
                  initials: initials,
                  photoURL: _localPhotoURL,
                  onTap: _handlePhotoUpload,
                  showEditIcon: true,
                ),
                const SizedBox(width: 28),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayName,
                        style: GoogleFonts.outfit(fontSize: 28, fontWeight: FontWeight.w800, color: OhtliColors.onyx, height: 1.1),
                      ),
                      const SizedBox(height: 4),
                      Text(user?.email ?? '', style: GoogleFonts.inter(fontSize: 14, color: OhtliColors.subtleText)),
                      const SizedBox(height: 18),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          FilledButton.icon(
                            onPressed: _handlePhotoUpload,
                            icon: const Icon(Icons.photo_camera_outlined, size: 18),
                            label: const Text('Cambiar foto'),
                            style: FilledButton.styleFrom(
                              backgroundColor: OhtliColors.stormyTeal,
                              foregroundColor: Colors.white,
                              shape: const StadiumBorder(),
                              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                              textStyle: GoogleFonts.inter(fontWeight: FontWeight.w700),
                            ),
                          ),
                          if (user != null)
                            OutlinedButton.icon(
                              onPressed: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (ctx) => PublicProfilePage(
                                    userId: user.uid,
                                    showBackButton: true,
                                    onBack: () => Navigator.pop(ctx),
                                  ),
                                ),
                              ),
                              icon: const Icon(Icons.badge_outlined, size: 18),
                              label: const Text('Ver mi perfil público'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: OhtliColors.onyx,
                                side: BorderSide(color: OhtliColors.onyx.withValues(alpha: 0.18)),
                                shape: const StadiumBorder(),
                                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                                textStyle: GoogleFonts.inter(fontWeight: FontWeight.w700),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Elige una sección a la izquierda para cambiar tus datos, tu contraseña, tus direcciones o tus preferencias.',
            style: GoogleFonts.inter(fontSize: 13.5, color: OhtliColors.subtleText, height: 1.5),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsGroup(String title, List<_SettingsItem> items) {
    final isDark = OhtliSettings.instance.isDarkMode;
    final divider = isDark ? Colors.white.withValues(alpha: 0.06) : OhtliColors.cardBorder.withValues(alpha: 0.7);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 6, bottom: 8),
          child: Text(
            title.toUpperCase(),
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
              color: OhtliColors.onyx.withValues(alpha: 0.5),
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: OhtliColors.inputBg,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 3)),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (int i = 0; i < items.length; i++) ...[
                if (i > 0) Divider(height: 1, thickness: 1, indent: 68, color: divider),
                _buildSettingsRow(items[i]),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSettingsRow(_SettingsItem item) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: item.onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: OhtliColors.stormyTeal.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(item.icon, color: OhtliColors.stormyTeal, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600, color: OhtliColors.onyx),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.subtitle,
                      style: GoogleFonts.inter(fontSize: 12.5, color: OhtliColors.onyx.withValues(alpha: 0.55)),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: OhtliColors.onyx.withValues(alpha: 0.35), size: 22),
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
      color: OhtliColors.cardBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: OhtliColors.cardBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _personalFormKey,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [

                // Correo (Inmodificable)
                TextFormField(
                  initialValue: user?.email ?? '',
                  readOnly: true,
                  style: GoogleFonts.inter(
                    color: OhtliColors.onyx.withValues(alpha: 0.6),
                    fontSize: 14,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Correo (no se puede cambiar)',
                    labelStyle: GoogleFonts.inter(
                      color: OhtliColors.onyx.withValues(alpha: 0.5),
                    ),
                    prefixIcon: const Icon(
                      Icons.email_outlined,
                      color: OhtliColors.stormyTeal,
                      size: 20,
                    ),
                    suffixIcon: Tooltip(
                      message:
                          'El correo electrónico es el identificador principal.',
                      child: Icon(
                        Icons.info_outline_rounded,
                        color: OhtliColors.onyx.withValues(alpha: 0.4),
                        size: 18,
                      ),
                    ),
                    filled: true,
                    fillColor: OhtliColors.cloudDancer.withValues(alpha: 0.5),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Nombres
                TextFormField(
                  controller: _firstNameController,
                  style: GoogleFonts.inter(
                    color: OhtliColors.onyx,
                    fontSize: 14,
                  ),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Ingresa tus nombres'
                      : null,
                  decoration: InputDecoration(
                    labelText: 'Nombre',
                    labelStyle: GoogleFonts.inter(
                      color: OhtliColors.onyx.withValues(alpha: 0.5),
                    ),
                    prefixIcon: const Icon(
                      Icons.person_outline_rounded,
                      color: OhtliColors.stormyTeal,
                      size: 20,
                    ),
                    filled: true,
                    fillColor: OhtliColors.cloudDancer,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Apellidos
                TextFormField(
                  controller: _lastNameController,
                  style: GoogleFonts.inter(
                    color: OhtliColors.onyx,
                    fontSize: 14,
                  ),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Ingresa tus apellidos'
                      : null,
                  decoration: InputDecoration(
                    labelText: 'Apellidos',
                    labelStyle: GoogleFonts.inter(
                      color: OhtliColors.onyx.withValues(alpha: 0.5),
                    ),
                    prefixIcon: const Icon(
                      Icons.person_outline_rounded,
                      color: OhtliColors.stormyTeal,
                      size: 20,
                    ),
                    filled: true,
                    fillColor: OhtliColors.cloudDancer,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Teléfono: se verifica por SMS (habilita la verificación en dos pasos y que
                // te encuentren por él si tu perfil es público).
                Text('Teléfono (opcional)', style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: OhtliColors.onyx, fontSize: 14)),
                const SizedBox(height: 8),
                const PhoneVerificationField(),
                const SizedBox(height: 28),

                // Botones
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => setState(
                          () => _currentSection = AccountSection.dashboard,
                        ),
                        child: Text(
                          'Cancelar',
                          style: GoogleFonts.inter(
                            color: OhtliColors.onyx.withValues(alpha: 0.6),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _isSavingProfile ? null : _savePersonalInfo,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: OhtliColors.stormyTeal,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          elevation: 0,
                        ),
                        child: _isSavingProfile
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(
                                'Guardar',
                                style: GoogleFonts.inter(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
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
    final user = FirebaseAuth.instance.currentUser;
    bool hasPassword = false;
    bool hasGoogle = false;
    if (user != null) {
      for (final info in user.providerData) {
        if (info.providerId == 'password') hasPassword = true;
        if (info.providerId == 'google.com') hasGoogle = true;
      }
    }

    return Card(
      elevation: 0,
      color: OhtliColors.cardBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: OhtliColors.cardBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _securityFormKey,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
              const TwoFactorCard(),
              const SizedBox(height: 24),
                Text(
                  hasPassword
                      ? 'Por seguridad, requerimos verificar tu contraseña actual antes de actualizarla.'
                      : 'Como te registraste con Google, puedes crear una contraseña para tu cuenta de Ohtli.',
                  style: GoogleFonts.inter(
                    fontSize: 12.5,
                    color: OhtliColors.onyx.withValues(alpha: 0.55),
                  ),
                ),
                const SizedBox(height: 24),

                if (hasPassword) ...[
                  // Contraseña Actual
                  TextFormField(
                    controller: _currentPasswordController,
                    obscureText: _obscureCurrent,
                    style: GoogleFonts.inter(
                      color: OhtliColors.onyx,
                      fontSize: 14,
                    ),
                    validator: (value) => value == null || value.isEmpty
                        ? 'Ingresa tu contraseña actual'
                        : null,
                    decoration: InputDecoration(
                      labelText: 'Contraseña actual',
                      labelStyle: GoogleFonts.inter(
                        color: OhtliColors.onyx.withValues(alpha: 0.5),
                      ),
                      prefixIcon: const Icon(
                        Icons.lock_outline_rounded,
                        color: OhtliColors.stormyTeal,
                        size: 20,
                      ),
                      suffixIcon: IconButton(
                        tooltip: _obscureCurrent ? 'Mostrar contraseña' : 'Ocultar contraseña',
                        icon: Icon(
                          _obscureCurrent
                              ? Icons.visibility_rounded
                              : Icons.visibility_off_rounded,
                          size: 18,
                        ),
                        onPressed: () =>
                            setState(() => _obscureCurrent = !_obscureCurrent),
                      ),
                      filled: true,
                      fillColor: OhtliColors.cloudDancer,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // Nueva Contraseña
                TextFormField(
                  controller: _newPasswordController,
                  obscureText: _obscureNew,
                  style: GoogleFonts.inter(
                    color: OhtliColors.onyx,
                    fontSize: 14,
                  ),
                  onChanged: (_) => setState(() {}), // actualiza la lista de requisitos
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Escribe la nueva contraseña.';
                    }
                    if (!PasswordRules.meetsAll(value)) {
                      return 'Aún le falta algo de la lista.';
                    }
                    return null;
                  },
                  decoration: InputDecoration(
                    labelText: 'Nueva contraseña',
                    labelStyle: GoogleFonts.inter(
                      color: OhtliColors.onyx.withValues(alpha: 0.5),
                    ),
                    prefixIcon: const Icon(
                      Icons.lock_rounded,
                      color: OhtliColors.stormyTeal,
                      size: 20,
                    ),
                    suffixIcon: IconButton(
                      tooltip: _obscureNew ? 'Mostrar contraseña' : 'Ocultar contraseña',
                      icon: Icon(
                        _obscureNew
                            ? Icons.visibility_rounded
                            : Icons.visibility_off_rounded,
                        size: 18,
                      ),
                      onPressed: () =>
                          setState(() => _obscureNew = !_obscureNew),
                    ),
                    filled: true,
                    fillColor: OhtliColors.cloudDancer,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                PasswordChecklist(password: _newPasswordController.text, highlightMissing: false),
                const SizedBox(height: 16),

                // Confirmar Contraseña
                TextFormField(
                  controller: _confirmPasswordController,
                  obscureText: _obscureConfirm,
                  style: GoogleFonts.inter(
                    color: OhtliColors.onyx,
                    fontSize: 14,
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) return 'Repite la nueva contraseña.';
                    if (value != _newPasswordController.text) return 'No coincide con la de arriba.';
                    return null;
                  },
                  decoration: InputDecoration(
                    labelText: 'Repite la nueva contraseña',
                    labelStyle: GoogleFonts.inter(
                      color: OhtliColors.onyx.withValues(alpha: 0.5),
                    ),
                    prefixIcon: const Icon(
                      Icons.lock_rounded,
                      color: OhtliColors.stormyTeal,
                      size: 20,
                    ),
                    suffixIcon: IconButton(
                      tooltip: _obscureConfirm ? 'Mostrar contraseña' : 'Ocultar contraseña',
                      icon: Icon(
                        _obscureConfirm
                            ? Icons.visibility_rounded
                            : Icons.visibility_off_rounded,
                        size: 18,
                      ),
                      onPressed: () =>
                          setState(() => _obscureConfirm = !_obscureConfirm),
                    ),
                    filled: true,
                    fillColor: OhtliColors.cloudDancer,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 28),

                // Botones
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => setState(
                          () => _currentSection = AccountSection.dashboard,
                        ),
                        child: Text(
                          'Cancelar',
                          style: GoogleFonts.inter(
                            color: OhtliColors.onyx.withValues(alpha: 0.6),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _isUpdatingPassword ? null : _changePassword,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: OhtliColors.stormyTeal,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          elevation: 0,
                        ),
                        child: _isUpdatingPassword
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(
                                hasPassword ? 'Actualizar' : 'Crear',
                                style: GoogleFonts.inter(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
                
                const SizedBox(height: 40),
                Divider(color: OhtliColors.onyx.withValues(alpha: 0.1)),
                const SizedBox(height: 24),
                
                Text(
                  'Cuentas vinculadas',
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: OhtliColors.onyx,
                  ),
                ),
                const SizedBox(height: 16),
                
                if (hasGoogle)
                  Row(
                    children: [
                      const Icon(Icons.check_circle_rounded, color: OhtliColors.stormyTeal, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'Cuenta de Google vinculada',
                        style: GoogleFonts.inter(
                          color: OhtliColors.onyx.withValues(alpha: 0.8),
                          fontSize: 14,
                        ),
                      ),
                    ],
                  )
                else
                  ElevatedButton.icon(
                    onPressed: () async {
                      try {
                        final provider = GoogleAuthProvider()..setCustomParameters({'prompt': 'select_account'});
                        await FirebaseAuth.instance.currentUser?.linkWithPopup(provider);
                        if (mounted) {
                          setState(() {});
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Cuenta de Google vinculada exitosamente.'),
                              backgroundColor: OhtliColors.stormyTeal,
                            ),
                          );
                        }
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(friendlyError(e, fallback: 'No pudimos vincular tu cuenta de Google. Intenta de nuevo.')),
                              backgroundColor: OhtliColors.warning,
                            ),
                          );
                        }
                      }
                    },
                    icon: SvgPicture.network(
                      'https://upload.wikimedia.org/wikipedia/commons/c/c1/Google_%22G%22_logo.svg',
                      width: 18,
                      height: 18,
                      placeholderBuilder: (context) => const Icon(Icons.g_mobiledata),
                    ),
                    label: Text(
                      'Vincular cuenta de Google',
                      style: GoogleFonts.inter(fontWeight: FontWeight.w500),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: OhtliColors.onyx,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                        side: BorderSide(color: OhtliColors.onyx.withValues(alpha: 0.12)),
                      ),
                    ),
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
      case 'hogar':
        return Icons.home_rounded;
      case 'hotel':
        return Icons.hotel_rounded;
      case 'renta en app':
        return Icons.vpn_key_rounded;
      case 'familiar':
        return Icons.family_restroom_rounded;
      case 'amigos':
        return Icons.group_rounded;
      default:
        return Icons.location_on_rounded;
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
          color: OhtliColors.cardBg,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
            side: BorderSide(color: OhtliColors.cardBorder),
          ),
          child: const Padding(
            padding: EdgeInsets.all(40),
            child: Center(
              child: CircularProgressIndicator(color: OhtliColors.stormyTeal),
            ),
          ),
        );
      }

      return address_picker.AddressPickerWidget(
        initialAddress: _editingAddressIndex == null
            ? null
            : _addresses[_editingAddressIndex!],
        existingNames: _activeAddresses
            .asMap()
            .entries
            .where(
              (entry) =>
                  _editingAddressIndex == null ||
                  entry.key != _editingAddressIndex,
            )
            .map((entry) => entry.value['customName'] as String? ?? '')
            .where((name) => name.isNotEmpty)
            .toList(),
        onSave: (addressData) {
          setState(() {
            addressData['updatedAt'] = DateTime.now().millisecondsSinceEpoch;
            if (_editingAddressIndex == null) {
              final String id =
                  'addr_${DateTime.now().millisecondsSinceEpoch}_${addressData['street'].hashCode}';
              addressData['id'] = id;
              addressData['isOffline'] =
                  true; // Mark as pending offline addition
              _addresses.add(addressData);
            } else {
              final oldAddress = _addresses[_editingAddressIndex!];
              addressData['id'] = oldAddress['id'] ?? _getAddressId(oldAddress);
              addressData['isOffline'] = true; // Mark as pending offline edit
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
      color: OhtliColors.cardBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: OhtliColors.cardBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: _activeAddresses.isEmpty ? MainAxisSize.min : MainAxisSize.max,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _activeAddresses.isEmpty
                      ? 'Sin direcciones todavía'
                      : '${_activeAddresses.length} ${_activeAddresses.length == 1 ? 'dirección guardada' : 'direcciones guardadas'}',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: OhtliColors.subtleText,
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
                  label: Text(
                    'Agregar dirección',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w700),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: OhtliColors.stormyTeal,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            Flexible(
              fit: _activeAddresses.isEmpty ? FlexFit.loose : FlexFit.tight,
              child: _activeAddresses.isEmpty
                  ? Align(
                      alignment: Alignment.topCenter,
                      heightFactor: 1, // a la medida del aviso, sin estirar la tarjeta
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
                        decoration: BoxDecoration(
                          color: OhtliColors.cloudDancer,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: OhtliColors.cardBorder),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.add_location_alt_outlined, color: OhtliColors.accentText, size: 36),
                            const SizedBox(height: 12),
                            Text(
                              'Guarda tu casa, tu hotel o la oficina',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w700, color: OhtliColors.onyx),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Así podrás empezar tus rutas desde ahí con un toque.',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.inter(fontSize: 13.5, color: OhtliColors.subtleText, height: 1.4),
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _activeAddresses.length,
                      itemBuilder: (context, index) {
                        final activeAddrs = _activeAddresses;
                        final addr = activeAddrs[index];
                        final addressStr =
                            "${addr['street'] ?? ''}, ${addr['suburb'] ?? ''}, C.P. ${addr['zip'] ?? ''}, ${addr['city'] ?? ''}, ${addr['state'] ?? ''}, ${addr['country'] ?? ''}";

                        final hasCustomName =
                            addr['customName'] != null &&
                            (addr['customName'] as String).trim().isNotEmpty;
                        final displayTitle = hasCustomName
                            ? addr['customName'] as String
                            : addr['street'] ?? 'Dirección';

                        final category = addr['category'] as String? ?? 'Otro';
                        final icon = _getCategoryIcon(category);

                        return Card(
                          color: OhtliColors.cloudDancer,
                          elevation: 0,
                          margin: const EdgeInsets.only(bottom: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            leading: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: OhtliColors.inputBg,
                              ),
                              child: Icon(
                                icon,
                                color: OhtliColors.stormyTeal,
                                size: 20,
                              ),
                            ),
                            title: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    displayTitle,
                                    style: GoogleFonts.inter(
                                      fontWeight: FontWeight.w600,
                                      color: OhtliColors.onyx,
                                      fontSize: 14.5,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: OhtliColors.stormyTeal.withValues(
                                      alpha: 0.09,
                                    ),
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
                                hasCustomName
                                    ? "${addr['street'] ?? ''}\n$addressStr"
                                    : addressStr,
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  color: OhtliColors.onyx.withValues(alpha: 0.6),
                                  height: 1.3,
                                ),
                              ),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  tooltip: 'Editar dirección',
                                  icon: const Icon(
                                    Icons.edit_rounded,
                                    color: OhtliColors.stormyTeal,
                                    size: 18,
                                  ),
                                  onPressed: () {
                                    final mainIndex = _addresses.indexWhere(
                                      (e) =>
                                          _getAddressId(e) ==
                                          _getAddressId(addr),
                                    );
                                    if (mainIndex >= 0) {
                                      setState(() {
                                        _isEditingAddress = true;
                                        _editingAddressIndex = mainIndex;
                                      });
                                    }
                                  },
                                ),
                                IconButton(
                                  tooltip: 'Eliminar dirección',
                                  icon: const Icon(
                                    Icons.delete_outline_rounded,
                                    color: OhtliColors.warning,
                                    size: 18,
                                  ),
                                  onPressed: () {
                                    final mainIndex = _addresses.indexWhere(
                                      (e) =>
                                          _getAddressId(e) ==
                                          _getAddressId(addr),
                                    );
                                    if (mainIndex >= 0) {
                                      final user =
                                          FirebaseAuth.instance.currentUser;
                                      if (user != null) {
                                        _trackAddressDeletion(
                                          user.uid,
                                          _getAddressId(addr),
                                        );
                                      }
                                      setState(() {
                                        final target = _addresses[mainIndex];
                                        target['isDeleted'] = true;
                                        target['deletedAt'] = DateTime.now()
                                            .millisecondsSinceEpoch;
                                        target['updatedAt'] = DateTime.now()
                                            .millisecondsSinceEpoch;
                                        _saveAddresses();
                                      });
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            'Dirección eliminada correctamente.',
                                            style: GoogleFonts.inter(),
                                          ),
                                          backgroundColor:
                                              OhtliColors.stormyTeal,
                                        ),
                                      );
                                    }
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
      color: OhtliColors.cardBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: OhtliColors.cardBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [

              // Switch 1: Compartir datos
              SwitchListTile(
                activeThumbColor: OhtliColors.stormyTeal,
                contentPadding: EdgeInsets.zero,
                title: Text(
                  'Compartir datos de viaje',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w600,
                    color: OhtliColors.onyx,
                    fontSize: 14,
                  ),
                ),
                subtitle: Text(
                  'Permite a Ohtli utilizar tu historial para sugerirte mejores rutas en base a tendencias de viaje.',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: OhtliColors.onyx.withValues(alpha: 0.55),
                  ),
                ),
                value: _shareTravelData,
                onChanged: (val) {
                  setState(() {
                    _shareTravelData = val;
                  });
                },
              ),
              Divider(height: 32, color: OhtliColors.cardBorder),

              // Switch 2: Notificaciones
              SwitchListTile(
                activeThumbColor: OhtliColors.stormyTeal,
                contentPadding: EdgeInsets.zero,
                title: Text(
                  'Recibir notificaciones',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w600,
                    color: OhtliColors.onyx,
                    fontSize: 14,
                  ),
                ),
                subtitle: Text(
                  'Notificar sobre el estado de tu cuenta, actualizaciones de viaje y alertas del clima en CDMX.',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: OhtliColors.onyx.withValues(alpha: 0.55),
                  ),
                ),
                value: _receiveNotifications,
                onChanged: (val) {
                  setState(() {
                    _receiveNotifications = val;
                  });
                },
              ),
              // Push con Ohtli cerrado (por dispositivo).
              const PushSettingTile(),
              Divider(height: 32, color: OhtliColors.cardBorder),

              // Switch 3: Perfil público
              SwitchListTile(
                activeThumbColor: OhtliColors.stormyTeal,
                contentPadding: EdgeInsets.zero,
                title: Text(
                  'Perfil público',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w600,
                    color: OhtliColors.onyx,
                    fontSize: 14,
                  ),
                ),
                subtitle: Text(
                  'Permite que otros viajeros en Ohtli puedan buscar tu nombre y ver tus insignias de viaje alcanzadas.',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: OhtliColors.onyx.withValues(alpha: 0.55),
                  ),
                ),
                value: _publicProfile,
                onChanged: (val) {
                  setState(() {
                    _publicProfile = val;
                  });
                },
              ),
              Divider(height: 32, color: OhtliColors.cardBorder),

              // Usertag y que te encuentren por correo o teléfono
              const UsertagSettings(),
              Divider(height: 32, color: OhtliColors.cardBorder),

              // DANGER ZONE: ACCOUNT DELETION
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: OhtliColors.warning.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: OhtliColors.warning.withValues(alpha: 0.3),
                    width: 1.2,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.warning_amber_rounded,
                          color: OhtliColors.warning,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Zona de riesgo',
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w700,
                            color: OhtliColors.warningText,
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
                        color: OhtliColors.onyx.withValues(alpha: 0.65),
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      height: 38,
                      child: TextButton.icon(
                        onPressed: () => _showDeleteAccountDialog(context),
                        icon: const Icon(
                          Icons.delete_forever_rounded,
                          size: 18,
                          color: Colors.white,
                        ),
                        label: Text(
                          'Eliminar mi cuenta permanentemente',
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w600,
                            fontSize: 12.5,
                          ),
                        ),
                        style: TextButton.styleFrom(
                          backgroundColor: OhtliColors.warning,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 32),

              // Volver and Guardar Buttons
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () {
                        setState(() {
                          _loadPrivacySettings();
                          _currentSection = AccountSection.dashboard;
                        });
                      },
                      child: Text(
                        'Cancelar',
                        style: GoogleFonts.inter(
                          color: OhtliColors.onyx.withValues(alpha: 0.6),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        _savePrivacySetting('share', _shareTravelData);
                        _savePrivacySetting('notifications', _receiveNotifications);
                        _savePrivacySetting('public', _publicProfile);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Preferencias de privacidad guardadas.',
                              style: GoogleFonts.inter(),
                            ),
                            backgroundColor: OhtliColors.stormyTeal,
                          ),
                        );
                        setState(() {
                          _currentSection = AccountSection.dashboard;
                        });
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: OhtliColors.stormyTeal,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        elevation: 0,
                      ),
                      child: Text(
                        'Guardar',
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPreferencesView() {
    return ListenableBuilder(
      listenable: OhtliSettings.instance,
      builder: (context, _) {
        final settings = OhtliSettings.instance;

        // Capture initial values upon entering this screen to support Cancelar/Volver revert behavior
        if (_initialThemeMode == null) {
          _initialThemeMode = settings.themeMode;
          _initialFontSize = settings.fontSize;
        }

        return Card(
          elevation: 0,
          color: OhtliColors.cardBg,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
            side: BorderSide(color: OhtliColors.cardBorder),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [

                  // Card for Visual Theme
                  Text(
                    'Apariencia',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: OhtliColors.onyx,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _buildThemeCard(
                          title: 'Claro',
                          icon: Icons.light_mode_rounded,
                          isSelected: settings.themeMode == OhtliThemeMode.light,
                          onTap: () => settings.themeMode = OhtliThemeMode.light,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildThemeCard(
                          title: 'Oscuro',
                          icon: Icons.dark_mode_rounded,
                          isSelected: settings.themeMode == OhtliThemeMode.dark,
                          onTap: () => settings.themeMode = OhtliThemeMode.dark,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildThemeCard(
                          title: 'Sistema',
                          icon: Icons.settings_brightness_rounded,
                          isSelected: settings.themeMode == OhtliThemeMode.system,
                          onTap: () => settings.themeMode = OhtliThemeMode.system,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 28),

                  // Card for Font Size
                  Text(
                    'Tamaño de letra',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: OhtliColors.onyx,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Ajusta el tamaño del texto para una lectura más cómoda.',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: OhtliColors.onyx.withValues(alpha: 0.6),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Column(
                    children: [
                      _buildFontSizeTile(
                        title: 'Pequeño (85%)',
                        description: 'Ideal para ver más contenido en pantalla.',
                        isSelected: settings.fontSize == OhtliFontSize.small,
                        onTap: () => settings.fontSize = OhtliFontSize.small,
                        sampleStyle: GoogleFonts.inter(fontSize: 11),
                      ),
                      const SizedBox(height: 10),
                      _buildFontSizeTile(
                        title: 'Mediano (100%, predeterminado)',
                        description: 'Diseño original del sistema.',
                        isSelected: settings.fontSize == OhtliFontSize.medium,
                        onTap: () => settings.fontSize = OhtliFontSize.medium,
                        sampleStyle: GoogleFonts.inter(fontSize: 13),
                      ),
                      const SizedBox(height: 10),
                      _buildFontSizeTile(
                        title: 'Grande (115%)',
                        description: 'Mayor visibilidad de los títulos y textos.',
                        isSelected: settings.fontSize == OhtliFontSize.large,
                        onTap: () => settings.fontSize = OhtliFontSize.large,
                        sampleStyle: GoogleFonts.inter(fontSize: 15),
                      ),
                      const SizedBox(height: 10),
                      _buildFontSizeTile(
                        title: 'Muy grande (130%)',
                        description: 'Máxima accesibilidad de lectura.',
                        isSelected: settings.fontSize == OhtliFontSize.extraLarge,
                        onTap: () => settings.fontSize = OhtliFontSize.extraLarge,
                        sampleStyle: GoogleFonts.inter(fontSize: 17),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),

                  // Volver and Guardar Buttons
                  Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () {
                            if (_initialThemeMode != null) {
                              settings.themeMode = _initialThemeMode!;
                            }
                            if (_initialFontSize != null) {
                              settings.fontSize = _initialFontSize!;
                            }
                            _initialThemeMode = null;
                            _initialFontSize = null;
                            setState(() {
                              _currentSection = AccountSection.dashboard;
                            });
                          },
                          child: Text(
                            'Cancelar',
                            style: GoogleFonts.inter(
                              color: OhtliColors.onyx.withValues(alpha: 0.6),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            _initialThemeMode = null;
                            _initialFontSize = null;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Preferencias y accesibilidad guardadas.',
                                  style: GoogleFonts.inter(),
                                ),
                                backgroundColor: OhtliColors.stormyTeal,
                              ),
                            );
                            setState(() {
                              _currentSection = AccountSection.dashboard;
                            });
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: OhtliColors.stormyTeal,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            elevation: 0,
                          ),
                          child: Text(
                            'Guardar',
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildThemeCard({
    required String title,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? OhtliColors.stormyTeal.withValues(alpha: 0.12)
              : OhtliColors.inputBg.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? OhtliColors.accentText : OhtliColors.cardBorder,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              size: 26,
              color: isSelected ? OhtliColors.accentText : OhtliColors.onyx.withValues(alpha: 0.7),
            ),
            const SizedBox(height: 8),
            Text(
              title,
              style: GoogleFonts.inter(
                fontSize: 13.5,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                color: isSelected ? OhtliColors.accentText : OhtliColors.onyx,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFontSizeTile({
    required String title,
    required String description,
    required bool isSelected,
    required VoidCallback onTap,
    required TextStyle sampleStyle,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected
              ? OhtliColors.stormyTeal.withValues(alpha: 0.08)
              : OhtliColors.inputBg.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? OhtliColors.stormyTeal
                : OhtliColors.cantera.withValues(alpha: 0.3),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Radio<bool>(
              value: true,
              groupValue: isSelected ? true : false,
              activeColor: OhtliColors.stormyTeal,
              onChanged: (_) => onTap(),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.inter(
                      fontSize: 14.5,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                      color: OhtliColors.onyx,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    description,
                    style: GoogleFonts.inter(
                      fontSize: 11.5,
                      color: OhtliColors.onyx.withValues(alpha: 0.55),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: OhtliColors.cloudDancer,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: OhtliColors.cantera.withValues(alpha: 0.3)),
              ),
              child: Text(
                'Aa',
                style: sampleStyle.copyWith(
                  fontWeight: FontWeight.bold,
                  color: OhtliColors.onyx,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Custom Config Card for Desktop Hover effects
class _SettingsItem {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  /// Sección que abre (null si abre otra pantalla, como las de administración).
  final AccountSection? section;

  /// Abre un diálogo en la misma pantalla (sin el ícono de "abre otra pantalla").
  final bool opensDialog;

  const _SettingsItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.section,
    this.opensDialog = false,
  });
}

/// Cuenta → Ohtli Insider: el tester decide si ve la sección en el menú.
class _InsiderSettings extends StatelessWidget {
  const _InsiderSettings();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<FeatureAccess>(
      valueListenable: OhtliFeatures.instance.access,
      builder: (context, a, _) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SwitchListTile(
          activeThumbColor: OhtliColors.stormyTeal,
          contentPadding: EdgeInsets.zero,
          title: Text('Mostrar Ohtli Insider',
              style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: OhtliColors.onyx, fontSize: 14)),
          subtitle: Text(
            'Agrega al menú la sección con las funciones en prueba de los estudios en los que participas y lo que esos '
            'estudios te piden, como validar sus resultados.',
            style: GoogleFonts.inter(fontSize: 12, color: OhtliColors.onyx.withValues(alpha: 0.55)),
          ),
          value: a.insiderEnabled,
          onChanged: a.isTester ? (v) => OhtliFeatures.instance.setInsider(v) : null,
        ),
        if (!a.isTester)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('Disponible para testers de Ohtli Labs.',
                style: GoogleFonts.inter(fontSize: 12, color: OhtliColors.subtleText)),
          ),
      ]),
    );
  }
}

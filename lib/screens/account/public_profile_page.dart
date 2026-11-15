// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use, avoid_print, use_build_context_synchronously

import '../../services/social_graph.dart';
import 'dart:async';
import 'dart:ui' show ImageFilter;
import 'dart:convert';
import 'package:web/web.dart' as web;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../../theme/cdmx_photos.dart';
import '../../theme/colors.dart';
import '../../utils/friendly_errors.dart';
import '../../models/trip_model.dart';
import '../../widgets/trip_card.dart';
import '../../widgets/ohtli_ui.dart';
import '../../models/profile_moment.dart';
import '../../widgets/moment_picker_dialog.dart';
import '../../widgets/trip_polaroid.dart';
import '../../widgets/image_cropper_dialog.dart';
import '../../services/trip_service.dart';
import 'account_management_page.dart';
import '../friends_page.dart';
import '../../utils/web_helpers.dart';
import '../../screens/trips/trip_screens.dart' deferred as trips;
import '../../widgets/deferred_view.dart';

class PublicProfilePage extends StatefulWidget {
  final String userId;
  final bool showBackButton;
  final VoidCallback? onBack;

  const PublicProfilePage({
    super.key,
    required this.userId,
    this.showBackButton = false,
    this.onBack,
  });

  @override
  State<PublicProfilePage> createState() => _PublicProfilePageState();
}

class _PublicProfilePageState extends State<PublicProfilePage> with SingleTickerProviderStateMixin {
  // Preservar iconos contra tree-shaking
  // ignore: unused_field
  static const List<Icon> _preservedIcons = [
    Icon(Icons.edit_rounded),
    Icon(Icons.arrow_back_ios_new_rounded),
    Icon(Icons.camera_alt_rounded),
    Icon(Icons.calendar_today_rounded),
    Icon(Icons.check_rounded),
    Icon(Icons.person_add_rounded),
    Icon(Icons.star_rounded),
    Icon(Icons.stars_rounded),
    Icon(Icons.check_circle_rounded),
  ];

  Map<String, dynamic>? _userProfile;
  bool _isLoadingProfile = true;
  List<Trip>? _trips;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _tripsSubscription;
  
  // Follow and friendship states
  int _followersCount = 0;
  bool _isFollowing = false;
  bool _isFriend = false;
  bool _isCloseFriend = false;
  
  bool _hasSentRequest = false;
  bool _hasIncomingRequest = false;
  String? _pendingRequestId;
  String? _sentRequestId;
  
  StreamSubscription<SocialData>? _followersSubscription;
  StreamSubscription<SocialData>? _currentUserSubscription;
  StreamSubscription<QuerySnapshot>? _requestsSubscription;
  StreamSubscription<QuerySnapshot>? _incomingRequestsSubscription;
  
  // Tab controller for trips vs plans
  late TabController _tabController;
  late ScrollController _scrollController;
  
  // Local active user
  final User? _currentUser = FirebaseAuth.instance.currentUser;
  bool get _isSelf => _currentUser != null && _currentUser.uid == widget.userId;

  /// "Perfil público" apagado: quien no es su amigo solo ve nombre, foto y título.
  bool get _isHiddenForViewer =>
      !_isSelf && !_isFriend &&
      (_userProfile?['profilePrivate'] == true || (_profileSocial?.hidden ?? false));

  SocialData? _profileSocial;

  Widget _buildPrivateProfileNotice(bool isDark) {
    final double padding = OhtliUi.pagePadding(MediaQuery.of(context).size.width);
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(padding, 12, padding, 40),
      child: Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: const OhtliEmptyState(
            icon: Icons.lock_outline_rounded,
            color: OhtliColors.xoconostle,
            title: 'Este perfil es privado',
            message: 'Sus viajes y amigos solo los ven sus amigos.',
          ),
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (mounted) {
        setState(() {});
      }
    });
    _scrollController = ScrollController();
    // Una sola suscripción a los viajes: antes se creaba un stream nuevo en cada build
    // (y el scroll hacía build en cada píxel), así que la lista parpadeaba con el spinner.
    // Las reglas solo dejan a otros leer viajes publicados y públicos: sin esos filtros la
    // consulta se rechazaba completa y el perfil de los demás salía sin viajes.
    final tripsRef = FirebaseFirestore.instance.collection('users').doc(widget.userId).collection('trips');
    final Query<Map<String, dynamic>> tripsQuery = _isSelf
        ? tripsRef
        : tripsRef.where('status', isEqualTo: 'published').where('visibility', isEqualTo: 'public');
    _tripsSubscription = tripsQuery.snapshots().listen((snap) {
      if (!mounted) return;
      final list = snap.docs.map((d) => Trip.fromMap(d.data(), d.id)).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      setState(() => _trips = list);
    }, onError: (e) {
      debugPrint('[Perfil] viajes: $e');
      if (mounted) setState(() => _trips = const []);
    });
    _initializeDefaultTitles();
    _loadProfileData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _scrollController.dispose();
    _tripsSubscription?.cancel();
    _followersSubscription?.cancel();
    _currentUserSubscription?.cancel();
    _requestsSubscription?.cancel();
    _incomingRequestsSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadProfileData() async {
    if (!mounted) return;
    setState(() => _isLoadingProfile = true);

    try {
      // 1. Listen to profile document in real-time
      FirebaseFirestore.instance
          .collection('users')
          .doc(widget.userId)
          .snapshots()
          .listen((doc) async {
        if (doc.exists && mounted) {
          final data = doc.data();
          setState(() {
            _userProfile = data;
            _isLoadingProfile = false;
          });

          // Self-heal: ensure activeTitleId, possessedTitles, following, friends, closeFriends are set for self
          if (_isSelf && data != null) {
            final List<dynamic> possessed = data['possessedTitles'] ?? [];
            final String? active = data['activeTitleId'];
            if (possessed.isEmpty || active == null) {
              await FirebaseFirestore.instance.collection('users').doc(_currentUser!.uid).set({
                'possessedTitles': possessed.isEmpty ? ['viajero'] : possessed,
                'activeTitleId': active ?? 'viajero',
              }, SetOptions(merge: true));
            }
            // Las listas sociales viven en users/{uid}/social/*: mover las antiguas
            if (data.containsKey('friends') || data.containsKey('following') || data.containsKey('closeFriends')) {
              await SocialGraph.migrateLegacy(_currentUser!.uid);
            }
          }
        } else if (mounted) {
          setState(() {
            _userProfile = {
              'displayName': 'Viajero Ohtli',
              'photoURL': null,
              'coverURL': null,
              'title': 'Viajero',
              'createdAt': null,
            };
            _isLoadingProfile = false;
          });
        }
      });

      // 2. Query followers count in real-time
      // Amigos, seguidos y seguidores de este perfil (si es privado y no somos amigos,
      // las reglas no dejan leerlos: hidden).
      _followersSubscription = SocialGraph.watchGraph(widget.userId).listen((social) {
        if (mounted) {
          setState(() {
            _profileSocial = social;
            _followersCount = social.followers.length;
          });
        }
      });

      // 3. Listen to current user following and friendship states
      if (_currentUser != null) {
        _currentUserSubscription = SocialGraph.watchGraph(_currentUser.uid, includeClose: true)
            .listen((social) {
          if (mounted) {
            final following = social.following;
            final friends = social.friends;
            final closeFriends = social.closeFriends;
            setState(() {
              _isFollowing = following.contains(widget.userId);
              _isFriend = friends.contains(widget.userId);
              _isCloseFriend = closeFriends.contains(widget.userId);
            });
          }
        });

        // 4. Listen to pending friend requests (sent and incoming)
        if (!_isSelf) {
          _requestsSubscription = FirebaseFirestore.instance
              .collection('friend_requests')
              .where('senderId', isEqualTo: _currentUser.uid)
              .where('receiverId', isEqualTo: widget.userId)
              .where('status', isEqualTo: 'pending')
              .snapshots()
              .listen((snapshot) {
            if (mounted) {
              setState(() {
                _hasSentRequest = snapshot.docs.isNotEmpty;
                _sentRequestId = snapshot.docs.isNotEmpty ? snapshot.docs.first.id : null;
              });
            }
          });

          _incomingRequestsSubscription = FirebaseFirestore.instance
              .collection('friend_requests')
              .where('senderId', isEqualTo: widget.userId)
              .where('receiverId', isEqualTo: _currentUser.uid)
              .where('status', isEqualTo: 'pending')
              .snapshots()
              .listen((snapshot) {
            if (mounted) {
              setState(() {
                _hasIncomingRequest = snapshot.docs.isNotEmpty;
                _pendingRequestId = snapshot.docs.isNotEmpty ? snapshot.docs.first.id : null;
              });
            }
          });
        }
      }
    } catch (e) {
      print("Error loading profile: $e");
      if (mounted) {
        setState(() => _isLoadingProfile = false);
      }
    }
  }

  Future<void> _toggleFollow() async {
    if (_currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Inicia sesión para poder seguir a otros viajeros',
            style: GoogleFonts.inter(),
          ),
          backgroundColor: OhtliColors.xoconostle,
        ),
      );
      return;
    }

    try {
      await SocialGraph.setFollowing(_currentUser.uid, widget.userId, !_isFollowing);
    } catch (e) {
      print("Error toggling follow: $e");
    }
  }

  Future<void> _sendFriendRequest() async {
    if (_currentUser == null) return;

    try {
      final firestore = FirebaseFirestore.instance;

      // Check if there is already a friend request between these two users to avoid duplicates
      final existingRequests = await firestore
          .collection('friend_requests')
          .where('senderId', isEqualTo: _currentUser.uid)
          .where('receiverId', isEqualTo: widget.userId)
          .where('status', isEqualTo: 'pending')
          .get();

      final existingIncoming = await firestore
          .collection('friend_requests')
          .where('senderId', isEqualTo: widget.userId)
          .where('receiverId', isEqualTo: _currentUser.uid)
          .where('status', isEqualTo: 'pending')
          .get();

      if (existingRequests.docs.isNotEmpty || existingIncoming.docs.isNotEmpty) {
        _showStatusSnackBar('Ya existe una solicitud de amistad pendiente.');
        return;
      }

      // 1. Create a top-level friend request
      final docRef = await firestore.collection('friend_requests').add({
        'senderId': _currentUser.uid,
        'senderName': _currentUser.displayName ?? 'Un viajero',
        'senderPhoto': _currentUser.photoURL,
        'receiverId': widget.userId,
        'status': 'pending',
        'timestamp': FieldValue.serverTimestamp(),
      });

      // 2. Add notification inside target user's private subcollection
      await firestore
          .collection('users')
          .doc(widget.userId)
          .collection('notifications')
          .doc(docRef.id)
          .set({
        'type': 'friend_request',
        'senderId': _currentUser.uid,
        'senderName': _currentUser.displayName ?? 'Un viajero',
        'senderPhoto': _currentUser.photoURL,
        'status': 'pending',
        'timestamp': FieldValue.serverTimestamp(),
      });

      _showStatusSnackBar('¡Solicitud de amistad enviada!');
    } catch (e) {
      print("Error sending friend request: $e");
    }
  }

  Future<void> _cancelFriendRequest(String requestId) async {
    if (_currentUser == null) return;

    try {
      final firestore = FirebaseFirestore.instance;

      // 1. Query and delete all pending top-level friend requests between these two users
      final requestsSnapshot = await firestore
          .collection('friend_requests')
          .where('senderId', isEqualTo: _currentUser.uid)
          .where('receiverId', isEqualTo: widget.userId)
          .where('status', isEqualTo: 'pending')
          .get();

      for (var doc in requestsSnapshot.docs) {
        await doc.reference.delete();
      }

      // Fallback: Also try to delete specific requestId if not deleted yet
      try {
        await firestore.collection('friend_requests').doc(requestId).delete();
      } catch (_) {}

      // 2. Query and delete all pending notifications of type friend_request between these two users
      final notificationsSnapshot = await firestore
          .collection('users')
          .doc(widget.userId)
          .collection('notifications')
          .where('senderId', isEqualTo: _currentUser.uid)
          .where('type', isEqualTo: 'friend_request')
          .where('status', isEqualTo: 'pending')
          .get();

      for (var doc in notificationsSnapshot.docs) {
        await doc.reference.delete();
      }

      // Fallback: Also try to delete specific notification by requestId if not deleted yet
      try {
        await firestore
            .collection('users')
            .doc(widget.userId)
            .collection('notifications')
            .doc(requestId)
            .delete();
      } catch (_) {}

      _showStatusSnackBar('Solicitud de amistad cancelada.');
    } catch (e) {
      print("Error canceling friend request: $e");
    }
  }

  Future<void> _acceptFriendRequest(String requestId) async {
    if (_currentUser == null) return;

    try {
      final firestore = FirebaseFirestore.instance;

      // 1. Update the top-level friend request
      await firestore.collection('friend_requests').doc(requestId).update({
        'status': 'accepted',
      });

      // 2. Update Bob's private notification
      await firestore
          .collection('users')
          .doc(_currentUser.uid)
          .collection('notifications')
          .doc(requestId)
          .update({
        'status': 'accepted',
      });

      // 3-4. Amistad en ambos sentidos (users/{uid}/social/graph)
      await SocialGraph.addFriendship(_currentUser.uid, widget.userId);

      _showStatusSnackBar('¡Ahora son amigos!');
    } catch (e) {
      print("Error accepting friend request: $e");
    }
  }

  Future<void> _setFriendStatus(String status) async {
    if (_currentUser == null) return;
    final me = _currentUser.uid;

    try {
      if (status == 'none') {
        // Remove friendship mutually
        await SocialGraph.removeFriendship(me, widget.userId);
        _showStatusSnackBar('Relación de amistad removida.');
      } else if (status == 'friend') {
        // Keep as friend, remove from closeFriends (Mejores Amigos is local-only)
        await SocialGraph.setCloseFriend(me, widget.userId, false);
        _showStatusSnackBar('Actualizado a amigo normal.');
      } else if (status == 'closeFriend') {
        // Add to closeFriends (user is the ONLY ONE choosing their close friends)
        await SocialGraph.setCloseFriend(me, widget.userId, true);
        _showStatusSnackBar('¡Añadido a tus Mejores Amigos!');
      }
    } catch (e) {
      print("Error setting friend status: $e");
    }
  }

  void _showStatusSnackBar(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: GoogleFonts.inter(fontWeight: FontWeight.w500)),
        backgroundColor: OhtliColors.stormyTeal,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Future<void> _initializeDefaultTitles() async {
    final firestore = FirebaseFirestore.instance;
    final collection = firestore.collection('titles');
    
    try {
      final doc = await collection.doc('viajero').get();
      if (!doc.exists) {
        print("Initializing default titles in Firestore...");
        await collection.doc('viajero').set({
          'name': 'Viajero',
          'description': 'Miembro fundador de la comunidad Ohtli.',
        });
        await collection.doc('explorador').set({
          'name': 'Explorador',
          'description': 'Viajero aventurero con varios destinos registrados.',
        });
        await collection.doc('cronista').set({
          'name': 'Cronista',
          'description': 'Narrador talentoso de crónicas y bitácoras de viaje.',
        });
        await collection.doc('guia').set({
          'name': 'Guía Ohtli',
          'description': 'Experto local que orienta a la comunidad con recomendaciones únicas.',
        });
      }
    } catch (e) {
      print("Error initializing default titles: $e");
    }
  }

  Widget _buildActiveTitleWidget(String? activeTitleId, bool isDark) {
    final titleId = activeTitleId ?? 'viajero';
    
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('titles').doc(titleId).snapshots(),
      builder: (context, snapshot) {
        String titleName = 'Viajero';
        if (snapshot.hasData && snapshot.data!.exists) {
          final data = snapshot.data!.data() as Map<String, dynamic>?;
          titleName = data?['name'] ?? 'Viajero';
        }
        
        final Widget pill = Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.38),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: Colors.white.withValues(alpha: 0.18), width: 0.8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.workspace_premium_rounded, size: 14, color: OhtliColors.cempasuchil),
              const SizedBox(width: 6),
              Text(titleName, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white)),
              if (_isSelf) ...[
                const SizedBox(width: 6),
                Icon(Icons.edit_rounded, size: 12, color: Colors.white.withValues(alpha: 0.8)),
              ],
            ],
          ),
        );

        if (!_isSelf) return pill;

        return Tooltip(
          message: 'Cambiar título',
          child: InkWell(onTap: _showTitleSelectionDialog, borderRadius: BorderRadius.circular(30), child: pill),
        );
      },
    );
  }

  Future<void> _showTitleSelectionDialog() async {
    final isDark = OhtliSettings.instance.isDarkMode;
    final List<dynamic> possessed = _userProfile?['possessedTitles'] ?? ['viajero'];
    final String activeId = _userProfile?['activeTitleId'] ?? 'viajero';

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: OhtliColors.cloudDancer,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Text(
            'Mis Títulos de Viajero',
            style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: OhtliColors.onyx),
          ),
          content: SizedBox(
            width: 400,
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('titles').snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(color: OhtliColors.stormyTeal));
                }

                final allDocs = snapshot.data?.docs ?? [];
                // Only show the titles that the user actually possesses!
                final docs = allDocs.where((doc) => possessed.contains(doc.id)).toList();
                
                return SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: docs.map((doc) {
                      final data = doc.data() as Map<String, dynamic>;
                      final id = doc.id;
                      final name = data['name'] ?? 'Viajero';
                      final desc = data['description'] ?? '';
                      final isActive = activeId == id;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        decoration: BoxDecoration(
                          color: isActive 
                              ? OhtliColors.stormyTeal.withOpacity(0.1) 
                              : (isDark ? const Color(0xFF1E1E22) : Colors.white),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: isActive 
                                ? OhtliColors.stormyTeal 
                                : (isDark ? const Color(0xFF2C2C32) : OhtliColors.cantera.withOpacity(0.4)),
                            width: isActive ? 1.5 : 1,
                          ),
                        ),
                        child: ListTile(
                          leading: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: OhtliColors.xoconostle.withOpacity(0.1),
                            ),
                            child: Icon(
                              isActive ? Icons.stars_rounded : Icons.star_rounded,
                              color: OhtliColors.xoconostle,
                              size: 18,
                            ),
                          ),
                          title: Text(
                            name,
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.bold,
                              fontSize: 13.5,
                              color: OhtliColors.onyx,
                            ),
                          ),
                          subtitle: Text(
                            desc,
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              color: OhtliColors.onyx.withOpacity(0.6),
                            ),
                          ),
                          trailing: isActive
                              ? const Icon(Icons.check_circle_rounded, color: OhtliColors.stormyTeal, size: 20)
                              : null,
                          onTap: !isActive
                              ? () async {
                                  await FirebaseFirestore.instance
                                      .collection('users')
                                      .doc(_currentUser!.uid)
                                      .update({'activeTitleId': id});
                                  Navigator.pop(context);
                                  _showStatusSnackBar('Título activo cambiado a "$name"');
                                }
                              : null,
                        ),
                      );
                    }).toList(),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  Future<void> _handleImageUpload({required bool isCover}) async {
    if (!kIsWeb) return;

    try {
      final picked = await pickFile(accept: 'image/*,.cr2,.nef,.arw,.dng,.orf,.pef,.rw2,.raf,.raw');
      if (picked == null || picked.bytes.isEmpty) return;
              final Uint8List bytes = picked.bytes;

              Future.delayed(const Duration(milliseconds: 200), () {
                if (mounted) {
                  showDialog(
                    context: context,
                    barrierDismissible: false,
                    builder: (context) => OhtliImageCropperDialog(
                      imageBytes: bytes,
                      isCircle: !isCover,
                      aspectRatio: isCover ? (3.0 / 1.0) : 1.0,
                      onCropped: (String croppedBase64) => _saveImageToCloud(
                        base64String: croppedBase64,
                        isCover: isCover,
                      ),
                    ),
                  );
                }
              });
    } catch (err) {
      print("File pick error: $err");
    }
  }

  Future<void> _saveImageToCloud({
    required String base64String,
    required bool isCover,
  }) async {
    if (_currentUser == null) return;

    try {
      final rawBase64 = base64String.contains(',')
          ? base64String.split(',').last
          : base64String;
      final imageBytes = base64Decode(rawBase64);

      final fileName = isCover ? 'cover.jpg' : 'profile.jpg';
      final storageRef = FirebaseStorage.instance.ref('users/${_currentUser.uid}/$fileName');
      
      await storageRef.putData(
        Uint8List.fromList(imageBytes),
        SettableMetadata(contentType: 'image/jpeg'),
      );

      final downloadUrl = await storageRef.getDownloadURL();

      final Map<String, dynamic> updateData = {
        isCover ? 'coverURL' : 'photoURL': downloadUrl,
        if (isCover) 'coverUrl': downloadUrl,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      await FirebaseFirestore.instance
          .collection('users')
          .doc(_currentUser.uid)
          .set(updateData, SetOptions(merge: true));

      if (!isCover) {
        await _currentUser.updatePhotoURL(downloadUrl);
        await _currentUser.reload();
        // Update local cache
        web.window.localStorage.setItem('ohtli_profile_pic_${_currentUser.uid}', downloadUrl);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isCover ? '¡Foto de portada actualizada!' : '¡Foto de perfil actualizada!',
              style: GoogleFonts.inter(fontWeight: FontWeight.w500),
            ),
            backgroundColor: OhtliColors.stormyTeal,
          ),
        );
      }
    } catch (e) {
      print("Error uploading image: $e");
    }
  }

  String _formatJoinedDate(dynamic rawDate) {
    if (rawDate == null) return 'registrado recientemente';
    DateTime? date;
    if (rawDate is Timestamp) {
      date = rawDate.toDate();
    } else if (rawDate is String) {
      date = DateTime.tryParse(rawDate);
    }

    if (date == null) return 'registrado recientemente';
    final months = [
      'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio',
      'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre'
    ];
    return 'miembro desde ${months[date.month - 1]} de ${date.year}';
  }

  ImageProvider _getImageProvider(String url) {
    if (url.startsWith('data:')) {
      final String base64Data = url.split(',').last;
      return MemoryImage(base64Decode(base64Data));
    }
    return NetworkImage(url);
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = OhtliSettings.instance.isDarkMode;
    final double width = MediaQuery.of(context).size.width;
    final bool isDesktop = !ohtliIsMobileWidth(width);
    final double padding = OhtliUi.pagePadding(width);

    if (_isLoadingProfile) {
      return Scaffold(
        backgroundColor: OhtliColors.cloudDancer,
        body: const Center(child: CircularProgressIndicator(color: OhtliColors.stormyTeal, strokeWidth: 3)),
      );
    }

    final List<dynamic> followingList = _profileSocial?.following ?? const [];
    final double heroMax = (isDesktop ? 400 : 330) + (isDesktop ? 132 : 96) * 0.55;
    final double heroMin = isDesktop ? 84 : 76;

    final tabBar = TabBar(
      controller: _tabController,
      isScrollable: true,
      tabAlignment: TabAlignment.start,
      dividerColor: Colors.transparent,
      indicatorSize: TabBarIndicatorSize.tab,
      indicator: BoxDecoration(
        color: OhtliColors.stormyTeal,
        borderRadius: BorderRadius.circular(30),
        boxShadow: [BoxShadow(color: OhtliColors.stormyTeal.withValues(alpha: 0.3), blurRadius: 14, offset: const Offset(0, 5))],
      ),
      splashBorderRadius: BorderRadius.circular(30),
      overlayColor: WidgetStateProperty.all(Colors.transparent),
      labelPadding: const EdgeInsets.symmetric(horizontal: 20),
      labelColor: Colors.white,
      unselectedLabelColor: OhtliColors.onyx.withValues(alpha: 0.65),
      labelStyle: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 14),
      unselectedLabelStyle: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 14),
      tabs: [
        Tab(height: 42, text: _visibleTrips(isTrip: true).isEmpty ? 'Viajes' : 'Viajes · ${_visibleTrips(isTrip: true).length}'),
        Tab(height: 42, text: _visibleTrips(isTrip: false).isEmpty ? 'Planes' : 'Planes · ${_visibleTrips(isTrip: false).length}'),
      ],
    );

    final moments = _moments;
    final bool showMoments = !_isHiddenForViewer && (moments.isNotEmpty || _isSelf);
    final String firstName = ((_userProfile?['displayName'] as String?) ?? '').split(' ').first;

    return Scaffold(
      backgroundColor: OhtliColors.cloudDancer,
      body: NestedScrollView(
        controller: _scrollController,
        headerSliverBuilder: (BuildContext context, bool innerBoxIsScrolled) {
          return <Widget>[
            SliverPersistentHeader(
              pinned: true,
              delegate: _ProfileHeroDelegate(
                maxHeight: heroMax,
                minHeight: heroMin,
                builder: (context, t) => _buildHero(context, t, isDesktop: isDesktop, padding: padding, isDark: isDark),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(padding, 20, padding, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (isDesktop)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(child: _buildStatsRow(isDark, followingList.length)),
                          const SizedBox(width: 20),
                          _buildActionButtons(isDark),
                        ],
                      )
                    else ...[
                      _buildActionButtons(isDark),
                      const SizedBox(height: 16),
                      _buildStatsRow(isDark, followingList.length),
                    ],
                    if (showMoments) ...[
                      const SizedBox(height: 34),
                      OhtliSectionHeader(
                        eyebrow: 'Momentos',
                        icon: Icons.favorite_rounded,
                        color: OhtliColors.cempasuchil,
                        title: _isSelf ? 'Momentos que atesoras' : (firstName.isEmpty ? 'Sus momentos' : 'Momentos de $firstName'),
                        subtitle: _isSelf ? 'Fotos de tus viajes que eliges para tu perfil.' : null,
                        trailing: _isSelf && moments.isNotEmpty
                            ? OhtliSecondaryButton(compact: true, label: 'Editar', icon: Icons.edit_rounded, onPressed: _editMoments)
                            : null,
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (showMoments) SliverToBoxAdapter(child: _buildMomentsStrip(moments, padding)),
            const SliverToBoxAdapter(child: SizedBox(height: 20)),
            SliverPersistentHeader(
              pinned: true,
              delegate: _SliverAppBarDelegate(tabBar, horizontalPadding: padding),
            ),
          ];
        },
        body: TabBarView(
          controller: _tabController,
          children: _isHiddenForViewer
              ? [_buildPrivateProfileNotice(isDark), _buildPrivateProfileNotice(isDark)]
              : [
                  _buildTripsList(isDesktop, isDark, isTrip: true),
                  _buildTripsList(isDesktop, isDark, isTrip: false),
                ],
        ),
      ),
    );
  }

  /// Viajes (publicados) o planes (borradores) que puede ver quien mira el perfil.
  List<Trip> _visibleTrips({required bool isTrip}) {
    final trips = _trips ?? const <Trip>[];
    return trips.where((t) {
      if (_isSelf) return isTrip ? t.status == 'published' : t.status == 'draft';
      if (isTrip) return t.status == 'published' && t.visibility == 'public';
      return _isFriend && t.status == 'draft';
    }).toList();
  }

  void _openTrip(Trip trip) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => trip.status == 'published'
            ? DeferredView(load: trips.loadLibrary, builder: (_) => trips.TripViewerPage(trip: trip, onBackToDashboard: () => Navigator.pop(context)))
            : DeferredView(load: trips.loadLibrary, builder: (_) => trips.TripEditorPage(trip: trip)),
      ),
    );
  }

  /// Portada: foto a todo lo ancho con el nombre encima; al bajar se compacta en una barra con foto y nombre.
  /// [t] va de 0 (abierta) a 1 (compacta). No usa setState: la anima el propio header fijo.
  Widget _buildHero(BuildContext context, double t, {required bool isDesktop, required double padding, required bool isDark}) {
    final String displayName = _userProfile?['displayName'] ?? 'Viajero Ohtli';
    final String? photoURL = _userProfile?['photoURL'];
    final String? coverURL = _userProfile?['coverURL'] ?? _userProfile?['coverUrl'];
    final dynamic rawCreatedAt = _userProfile?['createdAt'];
    final initials = displayName.split(' ').where((w) => w.isNotEmpty).take(2).map((w) => w[0].toUpperCase()).join();

    final double margin = (isDesktop ? padding * 0.5 : 10) * (1 - t);
    final double radius = OhtliUi.radiusLarge * (1 - t);
    final double fullOpacity = (1 - t * 1.8).clamp(0.0, 1.0);
    final double compactOpacity = ((t - 0.55) / 0.45).clamp(0.0, 1.0);
    // La foto de perfil va montada sobre el borde inferior de la portada (medio afuera).
    final double avatarSize = isDesktop ? 132 : 96;
    final double overlap = avatarSize * 0.55 * (1 - t);
    final double avatarLeft = margin + (isDesktop ? 32 : 20);

    Widget avatar(double size, {double border = 4}) {
      final fallback = Center(
        child: Text(initials, style: GoogleFonts.outfit(color: Colors.white, fontSize: size * 0.32, fontWeight: FontWeight.w800)),
      );
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: OhtliColors.stormyTeal,
          border: Border.all(color: _isCloseFriend ? OhtliColors.cempasuchil : (border >= 4 ? OhtliColors.cloudDancer : Colors.white), width: border),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 18, offset: const Offset(0, 6))],
        ),
        child: ClipOval(
          child: photoURL != null && photoURL.isNotEmpty
              ? Image(image: _getImageProvider(photoURL), fit: BoxFit.cover, gaplessPlayback: true, errorBuilder: (c, e, s) => fallback)
              : fallback,
        ),
      );
    }

    final String eyebrow = _isSelf ? 'TU PERFIL' : (_isCloseFriend ? 'MEJOR AMIGO' : (_isFriend ? 'TU AMIGO' : 'PERFIL DE VIAJERO'));

    final expanded = Padding(
      padding: EdgeInsets.fromLTRB((isDesktop ? 32 : 20) + avatarSize + (isDesktop ? 24 : 14), 0, isDesktop ? 36 : 20, isDesktop ? 26 : 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(eyebrow, style: OhtliUi.eyebrow(OhtliColors.cempasuchil).copyWith(shadows: [Shadow(color: Colors.black.withValues(alpha: 0.7), blurRadius: 10)])),
                const SizedBox(height: 6),
                Text(
                  displayName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.outfit(
                    fontSize: isDesktop ? 46 : 30,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: -0.8,
                    height: 1.05,
                    shadows: [Shadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 16)],
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _buildActiveTitleWidget(_userProfile?['activeTitleId'] ?? 'viajero', isDark),
                    OhtliMetaPill(icon: Icons.calendar_today_rounded, label: _formatJoinedDate(rawCreatedAt), onDark: true),
                    if (_isHiddenForViewer) const OhtliMetaPill(icon: Icons.lock_outline_rounded, label: 'Perfil privado', onDark: true),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );

    final compact = Padding(
      padding: EdgeInsets.symmetric(horizontal: padding),
      child: Row(
        children: [
          if (widget.showBackButton) const SizedBox(width: 48),
          avatar(42, border: 2),
          const SizedBox(width: 12),
          Expanded(
            child: Text(displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.outfit(fontSize: 19, fontWeight: FontWeight.w800, color: Colors.white)),
          ),
        ],
      ),
    );

    final cover = Padding(
      padding: EdgeInsets.fromLTRB(margin, margin, margin, 0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Se desenfoca al bajar; la barra compacta queda sobre la foto borrosa.
            ImageFiltered(
              enabled: t > 0.01,
              imageFilter: ImageFilter.blur(sigmaX: 14 * t, sigmaY: 14 * t, tileMode: TileMode.decal),
              child: Image(
                image: coverURL != null && coverURL.isNotEmpty ? _getImageProvider(coverURL) : NetworkImage(CdmxPhotos.cover(widget.userId.hashCode)),
                fit: BoxFit.cover,
                gaplessPlayback: true,
                errorBuilder: (c, e, s) => Container(color: OhtliColors.stormyTeal),
              ),
            ),
            // Velo: deja ver la foto arriba y oscurece donde va el texto; al compactar oscurece toda la barra.
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color.lerp(const Color(0x40000000), const Color(0xB0000000), t)!,
                    Color.lerp(const Color(0x00000000), const Color(0xA0000000), t)!,
                    Color.lerp(const Color(0xC8000000), const Color(0xB0000000), t)!,
                  ],
                  stops: const [0, 0.42, 1],
                ),
              ),
            ),
            if (fullOpacity > 0)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Opacity(opacity: fullOpacity, child: expanded),
              ),
            if (compactOpacity > 0) Positioned.fill(child: Opacity(opacity: compactOpacity, child: compact)),
            if (widget.showBackButton)
              Positioned.fill(
                child: Padding(
                  padding: EdgeInsets.only(left: 14 + (padding - 20) * t, top: 14 * (1 - t)),
                  child: Align(
                    alignment: Alignment(-1, -1 + t),
                    child: _glassButton(icon: Icons.arrow_back_rounded, tooltip: 'Volver', onTap: widget.onBack),
                  ),
                ),
              ),
            if (_isSelf && fullOpacity > 0)
              Positioned(
                top: 14,
                right: 14,
                child: Opacity(
                  opacity: fullOpacity,
                  child: _glassButton(
                    icon: Icons.photo_camera_back_rounded,
                    label: isDesktop ? 'Cambiar portada' : null,
                    tooltip: 'Cambiar portada',
                    onTap: () => _handleImageUpload(isCover: true),
                  ),
                ),
              ),
          ],
        ),
      ),
    );

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(left: 0, right: 0, top: 0, bottom: overlap, child: cover),
        if (fullOpacity > 0)
          Positioned(
            left: avatarLeft,
            bottom: 0,
            child: Opacity(
              opacity: fullOpacity,
              child: Stack(
            clipBehavior: Clip.none,
            children: [
              avatar(avatarSize, border: 5),
              if (_isSelf)
                Positioned(
                  right: -2,
                  bottom: 2,
                  child: Tooltip(
                    message: 'Cambiar foto',
                    child: Material(
                      color: OhtliColors.cempasuchil,
                      shape: CircleBorder(side: BorderSide(color: OhtliColors.cloudDancer, width: 3)),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () => _handleImageUpload(isCover: false),
                        child: const Padding(padding: EdgeInsets.all(7), child: Icon(Icons.camera_alt_rounded, color: Colors.white, size: 15)),
                      ),
                    ),
                  ),
                )
              else if (_isCloseFriend)
                Positioned(
                  right: 0,
                  bottom: 4,
                  child: Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: OhtliColors.cempasuchil,
                      shape: BoxShape.circle,
                      border: Border.all(color: OhtliColors.cloudDancer, width: 3),
                    ),
                    child: const Icon(Icons.star_rounded, size: 14, color: Colors.white),
                  ),
                ),
            ],
          ),
            ),
          ),
      ],
    );
  }

  Widget _glassButton({required IconData icon, String? label, required VoidCallback? onTap, required String tooltip}) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.black.withValues(alpha: 0.38),
        shape: StadiumBorder(side: BorderSide(color: Colors.white.withValues(alpha: 0.22))),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: label == null ? 10 : 14, vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: Colors.white, size: 17),
                if (label != null) ...[
                  const SizedBox(width: 7),
                  Text(label, style: GoogleFonts.inter(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w700)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<ProfileMoment> get _moments => ProfileMoment.listFrom(_userProfile?['moments']);

  /// Elegir o cambiar los momentos del perfil (solo tu propio perfil).
  Future<void> _editMoments() async {
    final picked = await MomentPickerDialog.show(context, trips: _trips ?? const [], current: _moments);
    if (picked == null || !mounted) return;
    setState(() => _userProfile = {...?_userProfile, 'moments': picked.map((m) => m.toMap()).toList()});
    if (_currentUser == null) return;
    try {
      await FirebaseFirestore.instance.collection('users').doc(_currentUser.uid).update({'moments': picked.map((m) => m.toMap()).toList()});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(friendlyError(e, fallback: 'No pudimos guardar tus momentos. Intenta de nuevo.'), style: GoogleFonts.inter()),
          backgroundColor: OhtliColors.xoconostle,
        ));
      }
    }
  }

  /// El viaje del momento, si quien mira puede abrirlo (tuyo, o publicado y público).
  Trip? _momentTrip(ProfileMoment m) {
    for (final t in _trips ?? const <Trip>[]) {
      if (t.id != m.tripId) continue;
      if (_isSelf || (t.status == 'published' && t.visibility == 'public')) return t;
    }
    return null;
  }

  /// Tira de polaroids inclinadas con los momentos elegidos.
  Widget _buildMomentsStrip(List<ProfileMoment> items, double padding) {
    const angles = [-0.05, 0.035, -0.02, 0.045, -0.04, 0.025, -0.03, 0.04];
    if (items.isEmpty) {
      // Solo en tu perfil: invitación a elegir los primeros.
      return Padding(
        padding: EdgeInsets.fromLTRB(padding, 18, padding, 8),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: OhtliEmptyState(
            icon: Icons.photo_library_rounded,
            color: OhtliColors.cempasuchil,
            title: 'Fija tus momentos favoritos',
            message: 'Elige fotos de tus viajes para que todos las vean en tu perfil. Si el viaje es privado, solo se verá la foto.',
            action: OhtliPrimaryButton(compact: true, highlight: true, label: 'Elegir momentos', icon: Icons.add_photo_alternate_rounded, onPressed: _editMoments),
          ),
        ),
      );
    }
    return SizedBox(
      height: 262,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.fromLTRB(padding, 22, padding, 22),
        clipBehavior: Clip.none,
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: 22),
        itemBuilder: (context, i) {
          final m = items[i];
          final trip = _momentTrip(m);
          return _MemoryPolaroid(
            url: m.url,
            // Si no puedes ver el viaje, no se muestra de qué viaje es.
            caption: trip == null ? null : (m.caption.isNotEmpty ? m.caption : (m.tripTitle.isEmpty ? 'Sin título' : m.tripTitle)),
            date: m.date,
            angle: angles[i % angles.length],
            onTap: trip == null ? null : () => _openTrip(trip),
          );
        },
      ),
    );
  }

  Widget _buildStatsRow(bool isDark, int followingCount) {
    final int friendsCount = _profileSocial?.friends.length ?? 0;
    final bool hidden = _isHiddenForViewer;
    final int tripsCount = _visibleTrips(isTrip: true).length;
    final int plansCount = _visibleTrips(isTrip: false).length;

    Widget stat(String value, String label, {VoidCallback? onTap}) {
      final child = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: GoogleFonts.outfit(fontWeight: FontWeight.w800, fontSize: 26, color: OhtliColors.onyx, height: 1.05)),
          const SizedBox(height: 2),
          Text(label, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: OhtliColors.subtleText)),
        ],
      );
      if (onTap == null) return child;
      return Semantics(
        button: true,
        child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(10), child: Padding(padding: const EdgeInsets.all(2), child: child)),
      );
    }

    final tiles = <Widget>[
        stat(hidden ? '—' : '$tripsCount', tripsCount == 1 ? 'Viaje' : 'Viajes',
            onTap: hidden ? null : () => _tabController.animateTo(0)),
        if (_isSelf)
          stat('$plansCount', plansCount == 1 ? 'Plan' : 'Planes',
              onTap: () => _tabController.animateTo(1)),
        stat(
          hidden ? '—' : '$friendsCount',
          friendsCount == 1 ? 'Amigo' : 'Amigos',
          onTap: _isSelf
              ? () => Navigator.push(context, MaterialPageRoute(builder: (context) => const FriendsPage(showBackButton: true)))
              : null,
        ),
        stat('$_followersCount', _followersCount == 1 ? 'Seguidor' : 'Seguidores'),
        stat('$followingCount', 'Siguiendo'),
    ];
    // En celular, una sola fila que se desliza; en escritorio, en renglones.
    if (ohtliIsMobileWidth(MediaQuery.of(context).size.width)) {
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        child: Row(children: [for (final t in tiles) Padding(padding: const EdgeInsets.only(right: 28), child: t)]),
      );
    }
    return Wrap(spacing: 36, runSpacing: 14, children: tiles);
  }

  Widget _buildActionButtons(bool isDark) {
    if (!_isSelf) {
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _isFollowing
              ? OhtliSecondaryButton(compact: true, label: 'Siguiendo', icon: Icons.check_rounded, onPressed: _toggleFollow)
              : OhtliPrimaryButton(compact: true, label: 'Seguir', icon: Icons.add_rounded, onPressed: _toggleFollow),
          _buildFriendButton(isDark),
        ],
      );
    }
    return OhtliSecondaryButton(
      compact: true,
      label: 'Editar perfil',
      icon: Icons.edit_rounded,
      onPressed: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => AccountManagementPage(
              onBackToHome: (_) => Navigator.pop(context),
              onLogout: () async {
                Navigator.pushReplacementNamed(context, '/login');
                await FirebaseAuth.instance.signOut();
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildTripsList(bool isDesktop, bool isDark, {required bool isTrip}) {
    if (_trips == null) {
      return const Center(
        child: Padding(padding: EdgeInsets.symmetric(vertical: 40.0), child: CircularProgressIndicator(color: OhtliColors.stormyTeal)),
      );
    }
    return _buildTripsGrid(_visibleTrips(isTrip: isTrip), isDesktop, isDark, isTrip: isTrip);
  }

  Widget _buildFriendButton(bool isDark) {
    if (_currentUser == null) return const SizedBox.shrink();

    // 1. Ya son amigos: menú para cambiar a mejor amigo o eliminar la amistad.
    if (_isFriend) {
      PopupMenuItem<String> item(String value, IconData icon, String label, Color color, {bool checked = false}) => PopupMenuItem<String>(
            value: value,
            child: Row(
              children: [
                Icon(icon, size: 18, color: color),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(label,
                      style: GoogleFonts.inter(
                          fontSize: 14, fontWeight: FontWeight.w600, color: value == 'none' ? OhtliColors.xoconostle : OhtliColors.onyx)),
                ),
                if (checked) Icon(Icons.check_rounded, size: 16, color: OhtliColors.accentText),
              ],
            ),
          );

      return PopupMenuButton<String>(
        tooltip: 'Opciones de amistad',
        onSelected: _setFriendStatus,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        color: OhtliColors.cardBg,
        offset: const Offset(0, 48),
        itemBuilder: (context) => [
          item('friend', Icons.people_outline_rounded, 'Amigo', OhtliColors.accentText, checked: !_isCloseFriend),
          item('closeFriend', Icons.star_rounded, 'Mejor amigo', OhtliColors.cempasuchil, checked: _isCloseFriend),
          const PopupMenuDivider(height: 1),
          item('none', Icons.person_remove_rounded, 'Eliminar amistad', OhtliColors.xoconostle),
        ],
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          decoration: BoxDecoration(
            color: _isCloseFriend ? OhtliColors.cempasuchil.withValues(alpha: 0.14) : OhtliColors.cardBg,
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: _isCloseFriend ? OhtliColors.cempasuchil.withValues(alpha: 0.45) : OhtliColors.onyx.withValues(alpha: 0.18)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(_isCloseFriend ? Icons.star_rounded : Icons.people_alt_rounded,
                  size: 16, color: _isCloseFriend ? OhtliColors.cempasuchil : OhtliColors.accentText),
              const SizedBox(width: 6),
              Text(_isCloseFriend ? 'Mejor amigo' : 'Amigo',
                  style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w700, color: OhtliColors.onyx)),
              const SizedBox(width: 2),
              Icon(Icons.expand_more_rounded, size: 18, color: OhtliColors.subtleText),
            ],
          ),
        ),
      );
    }

    // 2. Ya le enviaste solicitud: tocar la cancela.
    if (_hasSentRequest) {
      return Tooltip(
        message: 'Cancelar solicitud',
        child: OhtliSecondaryButton(
          compact: true,
          label: 'Solicitud enviada',
          icon: Icons.hourglass_top_rounded,
          onPressed: _sentRequestId == null ? null : () => _cancelFriendRequest(_sentRequestId!),
        ),
      );
    }

    // 3. Te envió solicitud.
    if (_hasIncomingRequest) {
      return OhtliPrimaryButton(
        compact: true,
        highlight: true,
        label: 'Aceptar solicitud',
        icon: Icons.check_rounded,
        onPressed: () => _acceptFriendRequest(_pendingRequestId!),
      );
    }

    // 4. Sin relación.
    return OhtliSecondaryButton(
      compact: true,
      label: 'Añadir amigo',
      icon: Icons.person_add_alt_1_rounded,
      onPressed: _sendFriendRequest,
    );
  }

  Widget _buildTripsGrid(List<Trip> items, bool isDesktop, bool isDark, {required bool isTrip}) {
    final double screenWidth = MediaQuery.of(context).size.width;
    final double padding = OhtliUi.pagePadding(screenWidth);

    if (items.isEmpty) {
      final String name = (_userProfile?['displayName'] as String?)?.split(' ').first ?? 'Este viajero';
      String title;
      String subtitle;
      IconData icon;
      Color? color;
      if (isTrip) {
        icon = Icons.landscape_rounded;
        title = _isSelf ? 'Aún no publicas viajes' : '$name aún no comparte viajes';
        subtitle = _isSelf ? 'Cuando publiques un viaje aparecerá aquí para que tus amigos lo vean.' : 'Cuando publique uno, lo verás aquí.';
      } else if (!_isSelf && !_isFriend) {
        icon = Icons.lock_outline_rounded;
        color = OhtliColors.xoconostle;
        title = 'Planes solo para amigos';
        subtitle = 'Agrega a $name como amigo para ver los planes que está armando.';
      } else {
        icon = Icons.map_outlined;
        title = _isSelf ? 'No tienes planes en curso' : '$name no tiene planes en curso';
        subtitle = _isSelf ? 'Tus borradores aparecerán aquí mientras los armas.' : 'Cuando empiece uno, lo verás aquí.';
      }
      return SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(padding, 12, padding, 40),
        child: Align(
          alignment: Alignment.topLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: OhtliEmptyState(icon: icon, color: color, title: title, message: subtitle),
          ),
        ),
      );
    }

    final double availableWidth = isDesktop ? (screenWidth - 260) : screenWidth;
    final int crossAxisCount = isDesktop ? (availableWidth >= 940 ? 3 : 2) : 1;

    final double cardWidth = (availableWidth - padding * 2 - (crossAxisCount - 1) * 20) / crossAxisCount;
    final double cardHeight = crossAxisCount == 1 ? 125.0 : (cardWidth * 9 / 16) + 150.0;
    final double computedAspectRatio = cardWidth / cardHeight;

    return GridView.builder(
      padding: EdgeInsets.fromLTRB(padding, 12, padding, 40),
    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        mainAxisSpacing: 20,
        crossAxisSpacing: 20,
        childAspectRatio: computedAspectRatio,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final trip = items[index];
        return TripCard(
          trip: trip,
          isHorizontal: crossAxisCount == 1,
          onEdit: () {
            if (trip.status == 'published') {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => DeferredView(load: trips.loadLibrary, builder: (_) => trips.TripViewerPage(
                    trip: trip,
                    onBackToDashboard: () => Navigator.pop(context),
                  )),
                ),
              );
            } else {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => DeferredView(load: trips.loadLibrary, builder: (_) => trips.TripEditorPage(trip: trip)),
                ),
              );
            }
          },
          onFeDeErratas: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => DeferredView(load: trips.loadLibrary, builder: (_) => trips.TripEditorPage(trip: trip)),
              ),
            );
          },
          onDelete: () => _deleteTrip(trip),
        );
      },
    );
  }

  Future<void> _deleteTrip(Trip trip) async {
    try {
      await TripService().deleteTrip(widget.userId, trip.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '¡Viaje "${trip.title}" eliminado!',
              style: GoogleFonts.inter(fontWeight: FontWeight.w500),
            ),
            backgroundColor: OhtliColors.stormyTeal,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(friendlyError(e, fallback: 'No pudimos eliminar el viaje. Intenta de nuevo.'), style: GoogleFonts.inter()),
            backgroundColor: OhtliColors.xoconostle,
          ),
        );
      }
    }
  }
}

class _SliverAppBarDelegate extends SliverPersistentHeaderDelegate {
  final TabBar tabBar;
  final double horizontalPadding;

  _SliverAppBarDelegate(this.tabBar, {required this.horizontalPadding});

  static const double _height = 58;

  @override
  double get minExtent => _height;
  @override
  double get maxExtent => _height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: OhtliColors.cloudDancer,
      alignment: Alignment.centerLeft,
      padding: EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: 8),
      child: tabBar,
    );
  }

  @override
  bool shouldRebuild(_SliverAppBarDelegate oldDelegate) => oldDelegate.horizontalPadding != horizontalPadding;
}

/// Header fijo de la portada: le pasa al builder cuánto se ha compactado (0 abierta, 1 barra).
class _ProfileHeroDelegate extends SliverPersistentHeaderDelegate {
  final double maxHeight;
  final double minHeight;
  final Widget Function(BuildContext context, double t) builder;

  _ProfileHeroDelegate({required this.maxHeight, required this.minHeight, required this.builder});

  @override
  double get maxExtent => maxHeight;
  @override
  double get minExtent => minHeight;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    final double t = (shrinkOffset / (maxHeight - minHeight)).clamp(0.0, 1.0);
    return builder(context, t);
  }

  @override
  bool shouldRebuild(_ProfileHeroDelegate old) => true;
}

/// Polaroid de un viaje: papel blanco, foto, título a mano y una leve inclinación.
class _MemoryPolaroid extends StatefulWidget {
  final String url;
  /// null: viaje que quien mira no puede ver; solo se muestra la foto.
  final String? caption;
  final DateTime? date;
  final double angle;
  final VoidCallback? onTap;

  const _MemoryPolaroid({required this.url, required this.caption, required this.date, required this.angle, required this.onTap});

  @override
  State<_MemoryPolaroid> createState() => _MemoryPolaroidState();
}

class _MemoryPolaroidState extends State<_MemoryPolaroid> {
  bool _hover = false;

  static const _months = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];

  @override
  Widget build(BuildContext context) {
    final d = widget.date;
    final bool open = widget.onTap != null && widget.caption != null;
    return Semantics(
      button: open,
      label: open ? 'Abrir viaje ${widget.caption}' : 'Momento de un viaje privado',
      child: MouseRegion(
        cursor: open ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedRotation(
            turns: _hover ? 0 : widget.angle / (2 * 3.14159),
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutBack,
            child: AnimatedScale(
              scale: _hover ? 1.05 : 1,
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutBack,
              child: Container(
                width: 168,
                padding: const EdgeInsets.fromLTRB(9, 9, 9, 0),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFDF8),
                  borderRadius: BorderRadius.circular(6),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withValues(alpha: _hover ? 0.24 : 0.14), blurRadius: _hover ? 26 : 14, offset: Offset(0, _hover ? 12 : 6)),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: SizedBox(height: 150, width: double.infinity, child: OhtliPhoto(widget.url)),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(2, 8, 2, 10),
                      child: SizedBox(
                        height: 34,
                        child: widget.caption == null
                            ? Align(
                                alignment: Alignment.centerLeft,
                                child: Tooltip(
                                  message: 'Viaje privado: solo se comparte esta foto',
                                  child: Icon(Icons.lock_outline_rounded, size: 15, color: const Color(0xFF8A817A).withValues(alpha: 0.8)),
                                ),
                              )
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    widget.caption!,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.fraunces(fontSize: 14, fontStyle: FontStyle.italic, fontWeight: FontWeight.w600, color: const Color(0xFF2A2522)),
                                  ),
                                  if (d != null) ...[
                                    const SizedBox(height: 2),
                                    Text('${d.day} ${_months[d.month - 1]} ${d.year}',
                                        style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: const Color(0xFF8A817A))),
                                  ],
                                ],
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

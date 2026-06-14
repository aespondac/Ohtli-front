// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use, avoid_print, use_build_context_synchronously

import 'dart:async';
import 'dart:ui';
import 'dart:convert';
import 'dart:html' as html;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../../theme/colors.dart';
import '../../models/trip_model.dart';
import '../../widgets/trip_card.dart';
import '../../widgets/image_cropper_dialog.dart';
import '../../services/trip_service.dart';
import '../trips/trip_viewer_page.dart';
import '../trips/trip_editor_page.dart';
import 'account_management_page.dart';
import '../friends_page.dart';

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
  double _scrollOffset = 0.0;
  
  // Follow and friendship states
  int _followersCount = 0;
  bool _isFollowing = false;
  bool _isFriend = false;
  bool _isCloseFriend = false;
  
  bool _hasSentRequest = false;
  bool _hasIncomingRequest = false;
  String? _pendingRequestId;
  String? _sentRequestId;
  
  StreamSubscription<QuerySnapshot>? _followersSubscription;
  StreamSubscription<DocumentSnapshot>? _currentUserSubscription;
  StreamSubscription<QuerySnapshot>? _requestsSubscription;
  StreamSubscription<QuerySnapshot>? _incomingRequestsSubscription;
  
  // Tab controller for trips vs plans
  late TabController _tabController;
  late ScrollController _scrollController;
  
  // Local active user
  final User? _currentUser = FirebaseAuth.instance.currentUser;
  bool get _isSelf => _currentUser != null && _currentUser.uid == widget.userId;

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
    _scrollController.addListener(() {
      if (mounted) {
        setState(() {
          _scrollOffset = _scrollController.offset;
        });
      }
    });
    _initializeDefaultTitles();
    _loadProfileData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _scrollController.dispose();
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
            final List<dynamic>? following = data['following'];
            final List<dynamic>? friends = data['friends'];
            final List<dynamic>? closeFriends = data['closeFriends'];
            
            if (possessed.isEmpty || active == null || following == null || friends == null || closeFriends == null) {
              await FirebaseFirestore.instance.collection('users').doc(_currentUser!.uid).set({
                'possessedTitles': possessed.isEmpty ? ['viajero'] : possessed,
                'activeTitleId': active ?? 'viajero',
                'following': following ?? [],
                'friends': friends ?? [],
                'closeFriends': closeFriends ?? [],
              }, SetOptions(merge: true));
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
      _followersSubscription = FirebaseFirestore.instance
          .collection('users')
          .where('following', arrayContains: widget.userId)
          .snapshots()
          .listen((snapshot) {
        if (mounted) {
          setState(() {
            _followersCount = snapshot.docs.length;
          });
        }
      });

      // 3. Listen to current user following and friendship states
      if (_currentUser != null) {
        _currentUserSubscription = FirebaseFirestore.instance
            .collection('users')
            .doc(_currentUser.uid)
            .snapshots()
            .listen((doc) {
          if (doc.exists && mounted) {
            final data = doc.data();
            final List<dynamic> following = data?['following'] ?? [];
            final List<dynamic> friends = data?['friends'] ?? [];
            final List<dynamic> closeFriends = data?['closeFriends'] ?? [];
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

    final docRef = FirebaseFirestore.instance.collection('users').doc(_currentUser.uid);

    try {
      if (_isFollowing) {
        await docRef.set({
          'following': FieldValue.arrayRemove([widget.userId])
        }, SetOptions(merge: true));
      } else {
        await docRef.set({
          'following': FieldValue.arrayUnion([widget.userId])
        }, SetOptions(merge: true));
      }
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

      // 3. Add Bob to Alice's friends list
      await firestore.collection('users').doc(widget.userId).update({
        'friends': FieldValue.arrayUnion([_currentUser.uid]),
      });

      // 4. Add Alice to Bob's friends list
      await firestore.collection('users').doc(_currentUser.uid).update({
        'friends': FieldValue.arrayUnion([widget.userId]),
      });

      _showStatusSnackBar('¡Ahora son amigos!');
    } catch (e) {
      print("Error accepting friend request: $e");
    }
  }

  Future<void> _setFriendStatus(String status) async {
    if (_currentUser == null) return;
    final docRef = FirebaseFirestore.instance.collection('users').doc(_currentUser.uid);

    try {
      if (status == 'none') {
        // Remove friendship mutually
        await docRef.update({
          'friends': FieldValue.arrayRemove([widget.userId]),
          'closeFriends': FieldValue.arrayRemove([widget.userId]),
        });
        await FirebaseFirestore.instance.collection('users').doc(widget.userId).update({
          'friends': FieldValue.arrayRemove([_currentUser.uid]),
        });
        _showStatusSnackBar('Relación de amistad removida.');
      } else if (status == 'friend') {
        // Keep as friend, remove from closeFriends (Mejores Amigos is local-only)
        await docRef.update({
          'closeFriends': FieldValue.arrayRemove([widget.userId]),
        });
        _showStatusSnackBar('Actualizado a amigo normal.');
      } else if (status == 'closeFriend') {
        // Add to closeFriends (user is the ONLY ONE choosing their close friends)
        await docRef.update({
          'closeFriends': FieldValue.arrayUnion([widget.userId]),
        });
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
        
        final Widget textWidget = Text(
          titleName,
          style: GoogleFonts.inter(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: OhtliColors.xoconostle,
          ),
        );
        
        if (!_isSelf) return textWidget;
        
        return InkWell(
          onTap: _showTitleSelectionDialog,
          borderRadius: BorderRadius.circular(4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              textWidget,
              const SizedBox(width: 6),
              const Icon(
                Icons.edit_rounded,
                size: 13,
                color: OhtliColors.xoconostle,
              ),
            ],
          ),
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
      final uploadInput = html.FileUploadInputElement()
        ..accept = 'image/*,.cr2,.nef,.arw,.dng,.orf,.pef,.rw2,.raf,.raw';
      uploadInput.click();

      uploadInput.onChange.listen((e) {
        final files = uploadInput.files;
        if (files != null && files.isNotEmpty) {
          final file = files[0];
          final reader = html.FileReader();

          reader.onLoadEnd.listen((e) {
            final dynamic result = reader.result;
            if (result is String && result.isNotEmpty) {
              final String base64Data = result.split(',').last;
              final Uint8List bytes = base64Decode(base64Data);

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
            }
          });
          reader.readAsDataUrl(file);
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
        html.window.localStorage['ohtli_profile_pic_${_currentUser.uid}'] = downloadUrl;
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
    final bool isDesktop = width >= 800;

    if (_isLoadingProfile) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(
            color: OhtliColors.stormyTeal,
            strokeWidth: 3,
          ),
        ),
      );
    }

    final String displayName = _userProfile?['displayName'] ?? 'Viajero Ohtli';
    final String? photoURL = _userProfile?['photoURL'];
    final String? coverURL = _userProfile?['coverURL'] ?? _userProfile?['coverUrl'];
    final List<dynamic> followingList = _userProfile?['following'] ?? [];
    final dynamic rawCreatedAt = _userProfile?['createdAt'];

    final initials = displayName
        .split(' ')
        .where((w) => w.isNotEmpty)
        .take(2)
        .map((w) => w[0].toUpperCase())
        .join();

    // 1. Calculate collapsing banner height and blur amount based on scroll offset
    final double clampedOffset = _scrollOffset.clamp(0.0, double.infinity);
    final double initialCoverHeight = isDesktop ? 320.0 : 180.0;
    final double minCoverHeight = isDesktop ? 120.0 : 70.0;
    
    // As we scroll, the height of the cover shrinks
    final double coverHeight = (initialCoverHeight - clampedOffset).clamp(minCoverHeight, initialCoverHeight);
    
    // Proportional progress and blur
    final double collapseProgress = ((initialCoverHeight - coverHeight) / (initialCoverHeight - minCoverHeight)).clamp(0.0, 1.0);
    final double blurSigma = collapseProgress * 12.0;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121214) : OhtliColors.cloudDancer,
      body: NestedScrollView(
        controller: _scrollController,
        headerSliverBuilder: (BuildContext context, bool innerBoxIsScrolled) {
          return <Widget>[
            SliverToBoxAdapter(
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // Cover Photo Banner with bottom spacing to expand the Stack
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        height: coverHeight,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF1E1E22) : OhtliColors.cantera.withOpacity(0.3),
                        ),
                        child: ClipRect(
                          child: ImageFiltered(
                            imageFilter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
                            child: Container(
                              decoration: BoxDecoration(
                                image: coverURL != null && coverURL.isNotEmpty
                                    ? DecorationImage(
                                        image: _getImageProvider(coverURL),
                                        fit: BoxFit.cover,
                                      )
                                    : null,
                                gradient: coverURL == null
                                    ? LinearGradient(
                                        colors: [
                                          OhtliColors.stormyTeal.withOpacity(0.8),
                                          OhtliColors.xoconostle.withOpacity(0.7),
                                        ],
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      )
                                    : null,
                              ),
                            ),
                          ),
                        ),
                      ),
                      SizedBox(height: isDesktop ? 95 : 75),
                    ],
                  ),

                  // Edit Cover Button
                  if (_isSelf)
                    Positioned(
                      top: 16,
                      right: 16,
                      child: Visibility(
                        visible: collapseProgress < 0.8,
                        child: Opacity(
                          opacity: (1.0 - collapseProgress).clamp(0.0, 1.0),
                          child: InkWell(
                            onTap: () => _handleImageUpload(isCover: true),
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.6),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.edit_rounded, color: Colors.white, size: 15),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Cambiar Portada',
                                    style: GoogleFonts.inter(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),

                  // Back Button
                  if (widget.showBackButton)
                    Positioned(
                      top: 16,
                      left: 16,
                      child: GestureDetector(
                        onTap: widget.onBack,
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.black.withOpacity(0.5),
                          ),
                          child: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18),
                        ),
                      ),
                    ),

                  // Overlapping Profile Avatar
                  Positioned(
                    bottom: isDesktop ? 35 : 30,
                    left: 24,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Container(
                          width: isDesktop ? 130 : 90,
                          height: isDesktop ? 130 : 90,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isDark ? const Color(0xFF121214) : OhtliColors.cloudDancer,
                              width: 4,
                            ),
                            color: OhtliColors.stormyTeal,
                          ),
                          child: ClipOval(
                            child: photoURL != null && photoURL.isNotEmpty
                                ? Image(
                                    image: _getImageProvider(photoURL),
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) => Center(
                                      child: Text(
                                        initials,
                                        style: GoogleFonts.inter(color: Colors.white, fontSize: isDesktop ? 36 : 24, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                  )
                                : Center(
                                    child: Text(
                                      initials,
                                      style: GoogleFonts.inter(color: Colors.white, fontSize: isDesktop ? 36 : 24, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                          ),
                        ),
                        if (_isSelf)
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: GestureDetector(
                              onTap: () => _handleImageUpload(isCover: false),
                              child: Container(
                                padding: const EdgeInsets.all(6),
                                decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: OhtliColors.stormyTeal,
                                ),
                                child: const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 16),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),

                  Positioned(
                    bottom: 0,
                    right: 24,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildStatsRow(isDark, followingList.length),
                        const SizedBox(height: 12),
                        _buildActionButtons(isDark),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Spacer for Avatar overlap is handled by the cover banner Column's 95px height expansion
            const SliverToBoxAdapter(
              child: SizedBox(height: 10),
            ),

            // Profile metadata
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          displayName,
                          style: GoogleFonts.outfit(
                            fontSize: isDesktop ? 26 : 22,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : OhtliColors.onyx,
                          ),
                        ),
                        if (_isCloseFriend) ...[
                          const SizedBox(width: 8),
                          const Icon(Icons.star_rounded, color: OhtliColors.stormyTeal, size: 20),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    _buildActiveTitleWidget(
                      _userProfile?['activeTitleId'] ?? 'viajero',
                      isDark,
                    ),
                    const SizedBox(height: 12),
                    
                    // Stats & Actions now rendered inside Stack Positioned on all widths

                    // Registration Date
                    Row(
                      children: [
                        Icon(Icons.calendar_today_rounded, size: 13, color: isDark ? Colors.white38 : OhtliColors.cantera),
                        const SizedBox(width: 6),
                        Text(
                          _formatJoinedDate(rawCreatedAt),
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            color: isDark ? Colors.white54 : OhtliColors.onyx.withOpacity(0.5),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SliverToBoxAdapter(
              child: SizedBox(height: 24),
            ),

            // Pinned TabBar header
            SliverPersistentHeader(
              pinned: true,
              delegate: _SliverAppBarDelegate(
                TabBar(
                  controller: _tabController,
                  indicatorColor: OhtliColors.stormyTeal,
                  labelColor: OhtliColors.stormyTeal,
                  unselectedLabelColor: isDark ? Colors.white38 : OhtliColors.onyx.withOpacity(0.5),
                  labelStyle: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 13.5),
                  unselectedLabelStyle: GoogleFonts.outfit(fontWeight: FontWeight.w600, fontSize: 13.5),
                  tabs: const [
                    Tab(text: 'Viajes'),
                    Tab(text: 'Planes'),
                  ],
                ),
                isDark: isDark,
              ),
            ),
          ];
        },
        body: TabBarView(
          controller: _tabController,
          children: [
            _buildTripsList(isDesktop, isDark, isTrip: true),
            _buildTripsList(isDesktop, isDark, isTrip: false),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsRow(bool isDark, int followingCount) {
    final int friendsCount = (_userProfile?['friends'] as List<dynamic>?)?.length ?? 0;

    Widget friendsWidget = RichText(
      text: TextSpan(
        children: [
          TextSpan(
            text: '$friendsCount ',
            style: GoogleFonts.outfit(
              fontWeight: FontWeight.bold,
              fontSize: 13.5,
              color: isDark ? Colors.white : OhtliColors.onyx,
            ),
          ),
          TextSpan(
            text: 'Amigos',
            style: GoogleFonts.inter(
              fontSize: 12,
              color: isDark ? Colors.white54 : OhtliColors.onyx.withOpacity(0.55),
            ),
          ),
        ],
      ),
    );

    if (_isSelf) {
      friendsWidget = GestureDetector(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => FriendsPage(showBackButton: true),
            ),
          );
        },
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: friendsWidget,
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        friendsWidget,
        const SizedBox(width: 16),
        RichText(
          text: TextSpan(
            children: [
              TextSpan(
                text: '$_followersCount ',
                style: GoogleFonts.outfit(
                  fontWeight: FontWeight.bold,
                  fontSize: 13.5,
                  color: isDark ? Colors.white : OhtliColors.onyx,
                ),
              ),
              TextSpan(
                text: 'Seguidores',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: isDark ? Colors.white54 : OhtliColors.onyx.withOpacity(0.55),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        RichText(
          text: TextSpan(
            children: [
              TextSpan(
                text: '$followingCount ',
                style: GoogleFonts.outfit(
                  fontWeight: FontWeight.bold,
                  fontSize: 13.5,
                  color: isDark ? Colors.white : OhtliColors.onyx,
                ),
              ),
              TextSpan(
                text: 'Siguiendo',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: isDark ? Colors.white54 : OhtliColors.onyx.withOpacity(0.55),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildActionButtons(bool isDark) {
    if (!_isSelf) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ElevatedButton.icon(
            onPressed: _toggleFollow,
            icon: Icon(_isFollowing ? Icons.check_rounded : Icons.person_add_rounded, size: 14),
            label: Text(
              _isFollowing ? 'Siguiendo' : 'Seguir',
              style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: _isFollowing ? OhtliColors.cantera : OhtliColors.stormyTeal,
              foregroundColor: _isFollowing ? OhtliColors.onyx : Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
          ),
          const SizedBox(width: 8),
          _buildFriendButton(isDark),
        ],
      );
    } else {
      return OutlinedButton.icon(
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
        icon: const Icon(Icons.edit_rounded, size: 14),
        label: Text(
          'Configurar Cuenta',
          style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: OhtliColors.stormyTeal,
          side: const BorderSide(color: OhtliColors.stormyTeal, width: 1.2),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        ),
      );
    }
  }

  Widget _buildTripsList(bool isDesktop, bool isDark, {required bool isTrip}) {
    return StreamBuilder<List<Trip>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(widget.userId)
          .collection('trips')
          .orderBy('createdAt', descending: true)
          .snapshots()
          .map((snapshot) => snapshot.docs
              .map((doc) => Trip.fromMap(doc.data(), doc.id))
              .toList()),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 40.0),
              child: CircularProgressIndicator(color: OhtliColors.stormyTeal),
            ),
          );
        }

        final trips = snapshot.data ?? [];
        
        final List<Trip> filteredItems = trips.where((t) {
          if (_isSelf) {
            return isTrip ? t.status == 'published' : t.status == 'draft';
          } else {
            if (isTrip) {
              return t.status == 'published' && t.visibility == 'public';
            } else {
              return _isFriend && t.status == 'draft';
            }
          }
        }).toList();

        return _buildTripsGrid(filteredItems, isDesktop, isDark, isTrip: isTrip);
      },
    );
  }

  Widget _buildFriendButton(bool isDark) {
    if (_currentUser == null) return const SizedBox.shrink();

    // 1. If already friends
    if (_isFriend) {
      Color btnBg = Colors.transparent;
      Color btnText = OhtliColors.onyx;
      IconData btnIcon = Icons.people_alt_rounded;
      String btnLabel = 'Amigo';
      bool isOutline = true;

      if (_isCloseFriend) {
        btnBg = OhtliColors.stormyTeal;
        btnText = Colors.white;
        btnIcon = Icons.people_alt_rounded;
        btnLabel = 'Mejor Amigo';
        isOutline = false;
      } else {
        btnBg = OhtliColors.cantera.withValues(alpha: 0.8);
        btnText = OhtliColors.onyx;
        btnIcon = Icons.people_alt_rounded;
        btnLabel = 'Amigo';
        isOutline = false;
      }

      final Widget buttonChild = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(btnIcon, size: 14, color: isOutline ? OhtliColors.stormyTeal : btnText),
          const SizedBox(width: 6),
          Text(
            btnLabel,
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: isOutline ? OhtliColors.stormyTeal : btnText,
            ),
          ),
          const SizedBox(width: 4),
          Icon(
            Icons.arrow_drop_down_rounded,
            size: 16,
            color: isOutline ? OhtliColors.stormyTeal : btnText,
          ),
        ],
      );

      return PopupMenuButton<String>(
        onSelected: _setFriendStatus,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        color: isDark ? const Color(0xFF25252A) : Colors.white,
        offset: const Offset(0, 40),
        itemBuilder: (context) => [
          PopupMenuItem<String>(
            value: 'friend',
            child: Row(
              children: [
                const Icon(Icons.people_outline_rounded, size: 16, color: OhtliColors.stormyTeal),
                const SizedBox(width: 10),
                Text(
                  'Amigo Normal',
                  style: GoogleFonts.inter(fontSize: 12.5, color: isDark ? Colors.white : OhtliColors.onyx),
                ),
                if (!_isCloseFriend) ...[
                  const Spacer(),
                  const Icon(Icons.check_rounded, size: 14, color: Colors.green),
                ],
              ],
            ),
          ),
          PopupMenuItem<String>(
            value: 'closeFriend',
            child: Row(
              children: [
                const Icon(Icons.people_rounded, size: 16, color: OhtliColors.stormyTeal),
                const SizedBox(width: 10),
                Text(
                  'Mejor Amigo',
                  style: GoogleFonts.inter(fontSize: 12.5, color: isDark ? Colors.white : OhtliColors.onyx),
                ),
                if (_isCloseFriend) ...[
                  const Spacer(),
                  const Icon(Icons.check_rounded, size: 14, color: Colors.green),
                ],
              ],
            ),
          ),
          const PopupMenuDivider(height: 1),
          PopupMenuItem<String>(
            value: 'none',
            child: Row(
              children: [
                const Icon(Icons.person_remove_rounded, size: 16, color: OhtliColors.xoconostle),
                const SizedBox(width: 10),
                Text(
                  'Eliminar Amistad',
                  style: GoogleFonts.inter(
                    fontSize: 12.5,
                    color: OhtliColors.xoconostle,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: btnBg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: buttonChild,
          ),
        ),
      );
    }

    // 2. If Alice sent a request to Bob
    if (_hasSentRequest) {
      return GestureDetector(
        onTap: () {
          if (_sentRequestId != null) {
            _cancelFriendRequest(_sentRequestId!);
          }
        },
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF25252A) : OhtliColors.cantera.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.hourglass_empty_rounded,
                  size: 14,
                  color: isDark ? Colors.white54 : OhtliColors.onyx,
                ),
                const SizedBox(width: 6),
                Text(
                  'Pendiente',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white54 : OhtliColors.onyx,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // 3. If Bob sent a request to Alice
    if (_hasIncomingRequest) {
      return ElevatedButton.icon(
        onPressed: () => _acceptFriendRequest(_pendingRequestId!),
        icon: const Icon(Icons.check_rounded, size: 14, color: Colors.white),
        label: Text(
          'Aceptar Solicitud',
          style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: OhtliColors.stormyTeal,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        ),
      );
    }

    // 4. Default: Show "Añadir amigo"
    return GestureDetector(
      onTap: _sendFriendRequest,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF25252A) : OhtliColors.cantera.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.person_add_alt_1_rounded,
                size: 14,
                color: isDark ? Colors.white54 : OhtliColors.onyx,
              ),
              const SizedBox(width: 6),
              Text(
                'Añadir amigo',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white54 : OhtliColors.onyx,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTripsGrid(List<Trip> items, bool isDesktop, bool isDark, {required bool isTrip}) {
    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isTrip ? Icons.landscape_rounded : Icons.map_outlined,
              size: 48,
              color: isDark ? Colors.white24 : OhtliColors.cantera,
            ),
            const SizedBox(height: 12),
            Text(
              isTrip ? 'No hay viajes para mostrar.' : 'No hay planes para mostrar.',
              style: GoogleFonts.inter(
                fontSize: 13,
                color: isDark ? Colors.white54 : OhtliColors.onyx.withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
      );
    }

    final double screenWidth = MediaQuery.of(context).size.width;
    final double availableWidth = isDesktop ? (screenWidth - 260) : screenWidth;
    final int crossAxisCount = isDesktop ? (availableWidth >= 940 ? 3 : 2) : 1;
    final double padding = isDesktop ? 24.0 : 16.0;
    
    final double cardWidth = (availableWidth - padding * 2 - (crossAxisCount - 1) * 20) / crossAxisCount;
    final double cardHeight = crossAxisCount == 1 
        ? 125.0 
        : (cardWidth * 9 / 16) + 160.0;
    final double computedAspectRatio = cardWidth / cardHeight;

    return GridView.builder(
      padding: EdgeInsets.all(padding),
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
                  builder: (context) => TripViewerPage(
                    trip: trip,
                    onBackToDashboard: () => Navigator.pop(context),
                  ),
                ),
              );
            } else {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => TripEditorPage(trip: trip),
                ),
              );
            }
          },
          onFeDeErratas: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => TripEditorPage(trip: trip),
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
      print("Error deleting trip: $e");
    }
  }
}

class _SliverAppBarDelegate extends SliverPersistentHeaderDelegate {
  final TabBar tabBar;
  final bool isDark;

  _SliverAppBarDelegate(this.tabBar, {required this.isDark});

  @override
  double get minExtent => tabBar.preferredSize.height;
  @override
  double get maxExtent => tabBar.preferredSize.height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: isDark ? const Color(0xFF121214) : OhtliColors.cloudDancer,
      child: tabBar,
    );
  }

  @override
  bool shouldRebuild(_SliverAppBarDelegate oldDelegate) {
    return false;
  }
}

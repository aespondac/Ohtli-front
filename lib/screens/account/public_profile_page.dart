// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use, avoid_print, use_build_context_synchronously

import 'dart:async';
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
  Map<String, dynamic>? _userProfile;
  bool _isLoadingProfile = true;
  
  // Follow and friendship states
  int _followersCount = 0;
  bool _isFollowing = false;
  bool _isFriend = false;
  bool _isCloseFriend = false;
  
  StreamSubscription<QuerySnapshot>? _followersSubscription;
  StreamSubscription<DocumentSnapshot>? _currentUserSubscription;
  
  // Tab controller for trips vs plans
  late TabController _tabController;
  
  // Local active user
  final User? _currentUser = FirebaseAuth.instance.currentUser;
  bool get _isSelf => _currentUser != null && _currentUser!.uid == widget.userId;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (mounted) {
        setState(() {});
      }
    });
    _initializeDefaultTitles();
    _loadProfileData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _followersSubscription?.cancel();
    _currentUserSubscription?.cancel();
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
            .doc(_currentUser!.uid)
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

    final docRef = FirebaseFirestore.instance.collection('users').doc(_currentUser!.uid);

    try {
      if (_isFollowing) {
        await docRef.update({
          'following': FieldValue.arrayRemove([widget.userId])
        });
      } else {
        await docRef.update({
          'following': FieldValue.arrayUnion([widget.userId])
        });
      }
    } catch (e) {
      print("Error toggling follow: $e");
    }
  }

  Future<void> _setFriendStatus(String status) async {
    if (_currentUser == null) return;
    final docRef = FirebaseFirestore.instance.collection('users').doc(_currentUser!.uid);

    try {
      if (status == 'none') {
        await docRef.update({
          'friends': FieldValue.arrayRemove([widget.userId]),
          'closeFriends': FieldValue.arrayRemove([widget.userId]),
        });
        _showStatusSnackBar('Relación de amistad removida.');
      } else if (status == 'friend') {
        await docRef.update({
          'friends': FieldValue.arrayUnion([widget.userId]),
          'closeFriends': FieldValue.arrayRemove([widget.userId]),
        });
        _showStatusSnackBar('¡Añadido como Amigo!');
      } else if (status == 'closeFriend') {
        await docRef.update({
          'closeFriends': FieldValue.arrayUnion([widget.userId]),
          'friends': FieldValue.arrayRemove([widget.userId]),
        });
        _showStatusSnackBar('¡Añadido como Close Friend! ⭐');
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
                              ? OhtliColors.stormyTeal.withValues(alpha: 0.1) 
                              : (isDark ? const Color(0xFF1E1E22) : Colors.white),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: isActive 
                                ? OhtliColors.stormyTeal 
                                : (isDark ? const Color(0xFF2C2C32) : OhtliColors.cantera.withValues(alpha: 0.4)),
                            width: isActive ? 1.5 : 1,
                          ),
                        ),
                        child: ListTile(
                          leading: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: OhtliColors.xoconostle.withValues(alpha: 0.1),
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
                              color: OhtliColors.onyx.withValues(alpha: 0.6),
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
      final storageRef = FirebaseStorage.instance.ref('users/${_currentUser!.uid}/$fileName');
      
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
          .doc(_currentUser!.uid)
          .set(updateData, SetOptions(merge: true));

      if (!isCover) {
        await _currentUser!.updatePhotoURL(downloadUrl);
        await _currentUser!.reload();
        // Update local cache
        html.window.localStorage['ohtli_profile_pic_${_currentUser!.uid}'] = downloadUrl;
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

    final Widget profileBody = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. Cover Banner & Avatar Header
        Stack(
          clipBehavior: Clip.none,
          children: [
            // Cover Photo
            Container(
              height: isDesktop ? 320 : 180,
              width: double.infinity,
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E1E22) : OhtliColors.cantera.withValues(alpha: 0.3),
                image: coverURL != null && coverURL.isNotEmpty
                    ? DecorationImage(
                        image: _getImageProvider(coverURL),
                        fit: BoxFit.cover,
                      )
                    : null,
                gradient: coverURL == null
                    ? LinearGradient(
                        colors: [
                          OhtliColors.stormyTeal.withValues(alpha: 0.8),
                          OhtliColors.xoconostle.withValues(alpha: 0.7),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      )
                    : null,
              ),
              child: _isSelf
                  ? Stack(
                      children: [
                        Positioned(
                          top: 16,
                          right: 16,
                          child: InkWell(
                            onTap: () => _handleImageUpload(isCover: true),
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.6),
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
                      ],
                    )
                  : null,
            ),

            // Back Button inside cover if pushed
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
                      color: Colors.black.withValues(alpha: 0.5),
                    ),
                    child: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18),
                  ),
                ),
              ),

            // Overlapping Profile Avatar
            Positioned(
              bottom: isDesktop ? -60 : -45,
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
          ],
        ),

        const SizedBox(height: 70),

        // 2. Profile Meta Details (Name, Title, Stats)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Left Column: Name, Title, Joined Date
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      style: GoogleFonts.outfit(
                        fontSize: isDesktop ? 26 : 22,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : OhtliColors.onyx,
                      ),
                    ),
                    const SizedBox(height: 4),
                    _buildActiveTitleWidget(
                      _userProfile?['activeTitleId'] ?? 'viajero',
                      isDark,
                    ),
                    const SizedBox(height: 12),
                    // Registration Date
                    Row(
                      children: [
                        Icon(Icons.calendar_today_rounded, size: 13, color: isDark ? Colors.white38 : OhtliColors.cantera),
                        const SizedBox(width: 6),
                        Text(
                          _formatJoinedDate(rawCreatedAt),
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            color: isDark ? Colors.white54 : OhtliColors.onyx.withValues(alpha: 0.5),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              // Right Column: Stats (Followers/Following) + Action Button
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Stats counter
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
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
                                color: isDark ? Colors.white54 : OhtliColors.onyx.withValues(alpha: 0.55),
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
                              text: '${followingList.length} ',
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
                                color: isDark ? Colors.white54 : OhtliColors.onyx.withValues(alpha: 0.55),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  // Actions: Follow & Friend options, or Configure Account Settings
                  if (!_isSelf)
                    Row(
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
                    )
                  else
                    OutlinedButton.icon(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => AccountManagementPage(
                              onBackToHome: (_) => Navigator.pop(context),
                              onLogout: () async {
                                await FirebaseAuth.instance.signOut();
                                Navigator.pushReplacementNamed(context, '/login');
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
                    ),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 24),

        // 3. Custom Tabs: "Viajes" vs "Planes"
        Container(
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: isDark ? const Color(0xFF2C2C32) : OhtliColors.cantera.withValues(alpha: 0.3),
                width: 1,
              ),
            ),
          ),
          child: TabBar(
            controller: _tabController,
            indicatorColor: OhtliColors.stormyTeal,
            labelColor: OhtliColors.stormyTeal,
            unselectedLabelColor: isDark ? Colors.white38 : OhtliColors.onyx.withValues(alpha: 0.5),
            labelStyle: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 13.5),
            unselectedLabelStyle: GoogleFonts.outfit(fontWeight: FontWeight.w600, fontSize: 13.5),
            tabs: const [
              Tab(text: 'Viajes'),
              Tab(text: 'Planes'),
            ],
          ),
        ),

        // 4. Tab Grids / Lists
        Expanded(
          child: StreamBuilder<List<Trip>>(
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
              
              // Filter based on self vs public visibility
              final List<Trip> filteredTrips = trips.where((t) {
                if (_isSelf) return t.status == 'published'; // Show all my published trips
                return t.status == 'published' && t.visibility == 'public'; // Show only public published
              }).toList();

              final List<Trip> filteredPlans = trips.where((t) {
                if (_isSelf) return t.status == 'draft'; // Show all my draft plans
                return t.status == 'draft' && t.visibility == 'public'; // Show only public drafts
              }).toList();

              return _tabController.index == 0
                  ? _buildTripsGrid(filteredTrips, isDesktop, isDark, isTrip: true)
                  : _buildTripsGrid(filteredPlans, isDesktop, isDark, isTrip: false);
            },
          ),
        ),
      ],
    );

  return Scaffold(
    backgroundColor: isDark ? const Color(0xFF121214) : OhtliColors.cloudDancer,
    body: profileBody,
  );
  }

  Widget _buildFriendButton(bool isDark) {
    Color btnBg = Colors.transparent;
    Color btnText = OhtliColors.onyx;
    IconData btnIcon = Icons.person_add_alt_1_rounded;
    String btnLabel = 'Añadir amigo';
    bool isOutline = true;

    if (_isCloseFriend) {
      btnBg = const Color(0xFF10B981); // Emerald green
      btnText = Colors.white;
      btnIcon = Icons.star_rounded;
      btnLabel = 'Close Friend';
      isOutline = false;
    } else if (_isFriend) {
      btnBg = OhtliColors.cantera.withValues(alpha: 0.8);
      btnText = OhtliColors.onyx;
      btnIcon = Icons.people_alt_rounded;
      btnLabel = 'Amigos';
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
                'Añadir como Amigo',
                style: GoogleFonts.inter(fontSize: 12.5, color: OhtliColors.onyx),
              ),
              if (_isFriend) ...[
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
              const Icon(Icons.star_rounded, size: 16, color: Color(0xFF10B981)),
              const SizedBox(width: 10),
              Text(
                'Añadir como Close Friend',
                style: GoogleFonts.inter(fontSize: 12.5, color: OhtliColors.onyx),
              ),
              if (_isCloseFriend) ...[
                const Spacer(),
                const Icon(Icons.check_rounded, size: 14, color: Colors.green),
              ],
            ],
          ),
        ),
        if (_isFriend || _isCloseFriend) ...[
          const PopupMenuDivider(height: 1),
          PopupMenuItem<String>(
            value: 'none',
            child: Row(
              children: [
                const Icon(Icons.person_remove_rounded, size: 16, color: OhtliColors.xoconostle),
                const SizedBox(width: 10),
                Text(
                  'Eliminar de mis Amigos',
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
      ],
      child: isOutline
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                border: Border.all(color: OhtliColors.stormyTeal, width: 1.2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: buttonChild,
            )
          : Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: btnBg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: buttonChild,
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

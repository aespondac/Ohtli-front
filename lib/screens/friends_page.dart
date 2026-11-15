import '../services/social_graph.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../theme/colors.dart';
import '../utils/friendly_errors.dart';
import 'account/public_profile_page.dart'; // To visit their profile!
import 'friends_feed.dart';
import '../widgets/ohtli_ui.dart';

class FriendsPage extends StatefulWidget {
  final bool showBackButton;
  const FriendsPage({super.key, this.showBackButton = false});

  @override
  State<FriendsPage> createState() => _FriendsPageState();
}

class _FriendsPageState extends State<FriendsPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  final User? _currentUser = FirebaseAuth.instance.currentUser;
  String _searchQuery = '';

  /// Lista de la columna izquierda: 'friends', 'following' o 'followers'.
  String _peopleList = 'friends';

  // Streams creados UNA sola vez: antes se recreaban en cada build (cada tecla del buscador),
  // lo que mostraba el spinner a pantalla completa y hacía perder el foco del campo de búsqueda.
  late final Stream<SocialData> _meStream;
  late final Stream<QuerySnapshot> _sentRequestsStream;
  late final Stream<QuerySnapshot> _incomingRequestsStream;

  // Ya no se descarga toda la colección de usuarios: solo amigos, una muestra de sugeridos
  // y los resultados de búsqueda, guardados en caché.
  final Map<String, DocumentSnapshot> _userCache = {};
  final Set<String> _userIdsInFlight = {};
  List<String> _suggestionIds = [];
  List<String> _searchResultIds = [];
  bool _searchingServer = false;
  Timer? _searchDebounce;
  static const int _suggestionsLimit = 40;

  String get _uid => _currentUser?.uid ?? '__none__';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    final db = FirebaseFirestore.instance;
    _meStream = SocialGraph.watchGraph(_uid, includeClose: true);
    _sentRequestsStream = db
        .collection('friend_requests')
        .where('senderId', isEqualTo: _uid)
        .where('status', isEqualTo: 'pending')
        .snapshots();
    _incomingRequestsStream = db
        .collection('friend_requests')
        .where('receiverId', isEqualTo: _uid)
        .where('status', isEqualTo: 'pending')
        .snapshots();
    _loadSuggestions();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadSuggestions() async {
    try {
      final snap = await FirebaseFirestore.instance.collection('users').limit(_suggestionsLimit).get();
      if (!mounted) return;
      setState(() {
        for (final d in snap.docs) {
          _userCache[d.id] = d;
        }
        // Los perfiles privados no aparecen en sugerencias (sí en la búsqueda por nombre)
        _suggestionIds = snap.docs
            .where((d) => d.data()['profilePrivate'] != true)
            .map((d) => d.id)
            .toList();
      });
    } catch (e) {
      debugPrint('[Friends] sugeridos: $e');
    }
  }

  // Trae (en lotes) los perfiles de amigos/solicitudes que aún no están en caché
  void _ensureUsers(Iterable<dynamic> ids) {
    final missing = ids
        .map((e) => e.toString())
        .where((id) => id.isNotEmpty && !_userCache.containsKey(id) && !_userIdsInFlight.contains(id))
        .toList();
    if (missing.isEmpty) return;
    _userIdsInFlight.addAll(missing);
    () async {
      for (var i = 0; i < missing.length; i += 10) {
        final chunk = missing.sublist(i, (i + 10).clamp(0, missing.length));
        try {
          final snap = await FirebaseFirestore.instance
              .collection('users')
              .where(FieldPath.documentId, whereIn: chunk)
              .get();
          if (!mounted) return;
          setState(() {
            for (final d in snap.docs) {
              _userCache[d.id] = d;
            }
          });
        } catch (e) {
          debugPrint('[Friends] perfiles: $e');
        } finally {
          _userIdsInFlight.removeAll(chunk);
        }
      }
    }();
  }

  void _onSearchChanged(String val) {
    setState(() => _searchQuery = val);
    _searchDebounce?.cancel();
    final q = val.trim();
    if (q.isEmpty) {
      setState(() {
        _searchResultIds = [];
        _searchingServer = false;
      });
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 350), () => _searchServer(q));
  }

  // Búsqueda por prefijo en el servidor (tal cual y con mayúscula inicial)
  Future<void> _searchServer(String q) async {
    setState(() => _searchingServer = true);
    final variants = <String>{q, q[0].toUpperCase() + q.substring(1)};
    final ids = <String>[];
    try {
      for (final v in variants) {
        final snap = await FirebaseFirestore.instance
            .collection('users')
            .where('displayName', isGreaterThanOrEqualTo: v)
            .where('displayName', isLessThan: '$v\uf8ff')
            .limit(20)
            .get();
        for (final d in snap.docs) {
          _userCache[d.id] = d;
          ids.add(d.id);
        }
      }
    } catch (e) {
      debugPrint('[Friends] búsqueda: $e');
    }
    if (!mounted || _searchQuery.trim() != q) return;
    setState(() {
      _searchResultIds = ids;
      _searchingServer = false;
    });
  }

  Future<void> _toggleFriendStatus(String targetUserId, String action) async {
    if (_currentUser == null) return;
    final me = _currentUser.uid;

    try {
      if (action == 'none') {
        // Remove friendship mutually
        await SocialGraph.removeFriendship(me, targetUserId);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Amistad removida.', style: GoogleFonts.inter()),
              backgroundColor: OhtliColors.stormyTeal,
            ),
          );
        }
      } else if (action == 'friend') {
        // Keep as friend, remove from close friends
        await SocialGraph.setCloseFriend(me, targetUserId, false);
      } else if (action == 'closeFriend') {
        // Add to close friends (user is the ONLY ONE choosing their close friends)
        await SocialGraph.setCloseFriend(me, targetUserId, true);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('¡Añadido a tus Mejores Amigos!', style: GoogleFonts.inter()),
              backgroundColor: OhtliColors.stormyTeal,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint("Error changing friend status: $e");
    }
  }

  /// Rechaza una solicitud recibida (igual que desde Notificaciones).
  Future<void> _declineFriendRequest(String requestId, String senderId) async {
    if (_currentUser == null) return;
    final db = FirebaseFirestore.instance;
    try {
      await db.collection('friend_requests').doc(requestId).update({'status': 'declined'});
      await db.collection('users').doc(_currentUser.uid).collection('notifications').doc(requestId).update({'status': 'declined'}).catchError((_) {});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Solicitud rechazada.', style: GoogleFonts.inter()), backgroundColor: OhtliColors.xoconostle),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(friendlyError(e, fallback: 'No pudimos rechazar la solicitud. Intenta de nuevo.'), style: GoogleFonts.inter()),
          backgroundColor: OhtliColors.xoconostle,
        ));
      }
    }
  }

  Future<void> _acceptFriendRequestFromSuggested(String requestId, String targetUserId) async {
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
      await SocialGraph.addFriendship(_currentUser.uid, targetUserId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('¡Ahora son amigos!', style: GoogleFonts.inter()),
            backgroundColor: OhtliColors.stormyTeal,
          ),
        );
      }
    } catch (e) {
      debugPrint("Error accepting friend request from suggested: $e");
    }
  }

  Future<void> _cancelFriendRequest(String requestId, String targetUserId) async {
    if (_currentUser == null) return;

    try {
      final firestore = FirebaseFirestore.instance;

      // 1. Query and delete all pending top-level friend requests between these two users
      final requestsSnapshot = await firestore
          .collection('friend_requests')
          .where('senderId', isEqualTo: _currentUser.uid)
          .where('receiverId', isEqualTo: targetUserId)
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
          .doc(targetUserId)
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
            .doc(targetUserId)
            .collection('notifications')
            .doc(requestId)
            .delete();
      } catch (_) {}

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Solicitud de amistad cancelada.', style: GoogleFonts.inter()),
            backgroundColor: OhtliColors.stormyTeal,
          ),
        );
      }
    } catch (e) {
      debugPrint("Error canceling friend request: $e");
    }
  }

  Future<void> _sendFriendRequest(String targetUserId, String targetName, String? targetPhoto) async {
    if (_currentUser == null) return;

    try {
      final firestore = FirebaseFirestore.instance;

      // Check if there is already a friend request between these two users to avoid duplicates
      final existingRequests = await firestore
          .collection('friend_requests')
          .where('senderId', isEqualTo: _currentUser.uid)
          .where('receiverId', isEqualTo: targetUserId)
          .where('status', isEqualTo: 'pending')
          .get();

      final existingIncoming = await firestore
          .collection('friend_requests')
          .where('senderId', isEqualTo: targetUserId)
          .where('receiverId', isEqualTo: _currentUser.uid)
          .where('status', isEqualTo: 'pending')
          .get();

      if (existingRequests.docs.isNotEmpty || existingIncoming.docs.isNotEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Ya existe una solicitud de amistad pendiente.', style: GoogleFonts.inter()),
              backgroundColor: OhtliColors.xoconostle,
            ),
          );
        }
        return;
      }

      // 1. Create a top-level friend request
      final docRef = await firestore.collection('friend_requests').add({
        'senderId': _currentUser.uid,
        'senderName': _currentUser.displayName ?? 'Un viajero',
        'senderPhoto': _currentUser.photoURL,
        'receiverId': targetUserId,
        'status': 'pending',
        'timestamp': FieldValue.serverTimestamp(),
      });

      // 2. Add notification inside target user's private subcollection
      await firestore
          .collection('users')
          .doc(targetUserId)
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

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('¡Solicitud de amistad enviada a $targetName!', style: GoogleFonts.inter()),
            backgroundColor: OhtliColors.stormyTeal,
          ),
        );
      }
    } catch (e) {
      debugPrint("Error sending friend request: $e");
    }
  }

  void _openProfile(String userId) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (ctx) => PublicProfilePage(userId: userId, showBackButton: true, onBack: () => Navigator.pop(ctx))),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_currentUser == null) {
      return Scaffold(
        backgroundColor: OhtliColors.cloudDancer,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: const OhtliEmptyState(
                icon: Icons.people_alt_rounded,
                title: 'Inicia sesión',
                message: 'Inicia sesión para ver tu lista de amigos.',
              ),
            ),
          ),
        ),
      );
    }

    final double width = MediaQuery.of(context).size.width;
    final double padding = OhtliUi.pagePadding(width);
    final bool isMobile = width < 700;

    return Scaffold(
      backgroundColor: OhtliColors.cloudDancer,
      body: StreamBuilder<SocialData>(
        stream: _meStream,
        builder: (context, userSnapshot) {
          if (userSnapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 460),
                  child: const OhtliEmptyState(
                    icon: Icons.wifi_off_rounded,
                    color: OhtliColors.xoconostle,
                    title: 'No pudimos cargar tus amigos',
                    message: 'Revisa tu conexión e intenta de nuevo.',
                  ),
                ),
              ),
            );
          }
          final SocialData? social = userSnapshot.data;
          final List<dynamic> friends = social?.friends ?? const [];
          final List<dynamic> closeFriends = social?.closeFriends ?? const [];
          if (social != null) _ensureUsers(friends);

          return StreamBuilder<QuerySnapshot>(
            stream: _sentRequestsStream,
            builder: (context, sentRequestsSnapshot) {
              return StreamBuilder<QuerySnapshot>(
                stream: _incomingRequestsStream,
                builder: (context, incomingRequestsSnapshot) {
                  _ensureUsers((incomingRequestsSnapshot.data?.docs ?? []).map((d) => d['senderId']));
                  _ensureUsers((sentRequestsSnapshot.data?.docs ?? []).map((d) => d['receiverId']));
                  final candidateIds = <String>{
                    ...friends.map((e) => e.toString()),
                    ..._suggestionIds,
                    ..._searchResultIds,
                    ...(incomingRequestsSnapshot.data?.docs ?? []).map((d) => d['senderId'].toString()),
                  };
                  final allUsers = [
                    for (final id in candidateIds)
                      if (_userCache[id] != null) _userCache[id]!,
                  ];
                  final Map<String, String> sentPendingMap = {
                    for (var doc in sentRequestsSnapshot.data?.docs ?? []) doc['receiverId'] as String: doc.id
                  };
                  final Map<String, String> incomingPendingMap = {
                    for (var doc in incomingRequestsSnapshot.data?.docs ?? []) doc['senderId'] as String: doc.id
                  };

                  var friendUsers = allUsers.where((doc) => friends.contains(doc.id)).toList();
                  // Sugeridos: todos menos uno mismo y los amigos; primero quienes te enviaron solicitud.
                  var suggestedUsers = allUsers.where((doc) => doc.id != _uid && !friends.contains(doc.id)).toList()
                    ..sort((a, b) => (incomingPendingMap.containsKey(b.id) ? 1 : 0) - (incomingPendingMap.containsKey(a.id) ? 1 : 0));

                  if (_searchQuery.isNotEmpty) {
                    bool matches(DocumentSnapshot doc) {
                      final name = (doc.data() as Map<String, dynamic>)['displayName'] ?? '';
                      return name.toString().toLowerCase().contains(_searchQuery.toLowerCase());
                    }

                    friendUsers = friendUsers.where(matches).toList();
                    suggestedUsers = suggestedUsers.where(matches).toList();
                  }

                  final int incoming = incomingPendingMap.length;
                  final int closeCount = closeFriends.where((id) => friends.contains(id)).length;
                  final String summary = social == null
                      ? 'Cargando a tu gente…'
                      : [
                          friends.isEmpty ? 'Aún no tienes amigos' : (friends.length == 1 ? '1 amigo' : '${friends.length} amigos'),
                          if (closeCount > 0) closeCount == 1 ? '1 mejor amigo' : '$closeCount mejores amigos',
                          if (incoming > 0) incoming == 1 ? '1 solicitud por responder' : '$incoming solicitudes por responder',
                        ].join(' · ');

                  Widget headerWith(double right) => Padding(
                    padding: EdgeInsets.fromLTRB(padding, isMobile ? 24 : 40, right, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (widget.showBackButton) ...[
                          Material(
                            color: OhtliColors.cardBg,
                            shape: CircleBorder(side: BorderSide(color: OhtliColors.cardBorder)),
                            child: IconButton(
                              tooltip: 'Volver',
                              icon: Icon(Icons.arrow_back_rounded, color: OhtliColors.onyx, size: 20),
                              onPressed: () => Navigator.pop(context),
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                        OhtliSectionHeader(
                          eyebrow: 'Tu gente',
                          icon: Icons.people_alt_rounded,
                          title: 'Amigos',
                          subtitle: summary,
                          large: true,
                        ),
                        const SizedBox(height: 22),
                        ConstrainedBox(constraints: const BoxConstraints(maxWidth: 560), child: _buildSearchField()),
                        const SizedBox(height: 14),
                      ],
                    ),
                  );
                  final header = headerWith(padding);

                  final Map<String, DocumentSnapshot> users = _userCache;
                  final List<String> friendIds = friends.map((e) => e.toString()).toList();
                  final List<String> following = social?.following ?? const [];
                  final List<String> followers = social?.followers ?? const [];
                  if (social != null) _ensureUsers([...following, ...followers]);

                  bool matchesId(String id) {
                    if (_searchQuery.isEmpty) return true;
                    final name = ((users[id]?.data() as Map<String, dynamic>?)?['displayName'] ?? '').toString();
                    return name.toLowerCase().contains(_searchQuery.toLowerCase());
                  }

                  final people = _PeopleData(
                    closeFriends: friendIds.where((id) => closeFriends.contains(id) && matchesId(id)).toList(),
                    otherFriends: friendIds.where((id) => !closeFriends.contains(id) && matchesId(id)).toList(),
                    following: following.where(matchesId).toList(),
                    followers: followers.where(matchesId).toList(),
                    suggested: suggestedUsers,
                    sentPending: sentPendingMap,
                    incomingPending: incomingPendingMap,
                  );

                  final feed = FriendsActivityFeed(
                    friendIds: friendIds,
                    users: users,
                    padding: padding,
                    onOpenProfile: _openProfile,
                    onShowSuggestions: () => _tabController.animateTo(1),
                    showFriendsRing: false,
                    header: _buildRequestsSection(people, users),
                  );

                  return LayoutBuilder(
                    builder: (context, box) {
                      // Escritorio: tu gente a la izquierda y la actividad a la derecha.
                      if (box.maxWidth >= 980) {
                        // Escritorio: izquierda, el título, el buscador y tu gente; derecha,
                        // la actividad a todo lo alto de la pantalla.
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              flex: 4,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  headerWith(12),
                                  Expanded(
                                    child: social == null
                                        ? _buildSkeleton(padding)
                                        : _buildPeoplePanel(people, users, EdgeInsets.fromLTRB(padding, 8, 12, 48)),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 28),
                            Expanded(
                              flex: 5,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const SizedBox(height: 46),
                                  Expanded(
                                    child: social == null
                                        ? _buildSkeleton(0)
                                        : FriendsActivityFeed(
                                            friendIds: friendIds,
                                            users: users,
                                            padding: padding,
                                            leftPadding: 0,
                                            onOpenProfile: _openProfile,
                                            onShowSuggestions: () {},
                                            showFriendsRing: false,
                                            header: Column(
                                              crossAxisAlignment: CrossAxisAlignment.stretch,
                                              children: [
                                                ?_buildRequestsSection(people, users),
                                                Padding(
                                                  padding: const EdgeInsets.only(bottom: 14),
                                                  child: Row(
                                                    children: [
                                                      Icon(Icons.dynamic_feed_rounded, size: 14, color: OhtliColors.accentText),
                                                      const SizedBox(width: 6),
                                                      Text('ACTIVIDAD', style: OhtliUi.eyebrow(OhtliColors.accentText)),
                                                    ],
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        );
                      }
                      // Celular y pantallas angostas: dos pestañas.
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          header,
                          Container(
                            alignment: Alignment.centerLeft,
                            padding: EdgeInsets.symmetric(horizontal: padding),
                            child: TabBar(
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
                              padding: const EdgeInsets.only(bottom: 12),
                              labelColor: Colors.white,
                              unselectedLabelColor: OhtliColors.onyx.withValues(alpha: 0.65),
                              labelStyle: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 14),
                              unselectedLabelStyle: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 14),
                              tabs: [
                                const Tab(height: 42, text: 'Actividad'),
                                Tab(height: 42, text: incoming == 0 ? 'Gente' : 'Gente · $incoming nuevas'),
                              ],
                            ),
                          ),
                          Expanded(
                            child: social == null
                                ? _buildSkeleton(padding)
                                : TabBarView(
                                    controller: _tabController,
                                    children: [
                                      feed,
                                      _buildPeoplePanel(people, users, EdgeInsets.fromLTRB(padding, 8, padding, 48)),
                                    ],
                                  ),
                          ),
                        ],
                      );
                    },
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  /// Buscador tipo píldora (como el de Lugares).
  Widget _buildSearchField() {
    return Container(
      decoration: BoxDecoration(
        color: OhtliColors.cardBg,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: OhtliColors.cardBorder),
        boxShadow: OhtliUi.softShadow(),
      ),
      child: TextField(
        controller: _searchController,
        onChanged: _onSearchChanged,
        style: GoogleFonts.inter(color: OhtliColors.onyx, fontSize: 14.5),
        decoration: InputDecoration(
          hintText: 'Buscar viajeros por nombre',
          hintStyle: GoogleFonts.inter(color: OhtliColors.subtleText, fontSize: 14.5),
          prefixIcon: Padding(
            padding: const EdgeInsets.only(left: 18, right: 10),
            child: Icon(Icons.search_rounded, color: OhtliColors.accentText, size: 21),
          ),
          prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
          suffixIcon: _searchingServer
              ? const Padding(
                  padding: EdgeInsets.all(16),
                  child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: OhtliColors.stormyTeal)),
                )
              : (_searchQuery.isNotEmpty
                  ? IconButton(
                      tooltip: 'Borrar búsqueda',
                      icon: Icon(Icons.close_rounded, size: 18, color: OhtliColors.subtleText),
                      onPressed: () {
                        _searchController.clear();
                        _onSearchChanged('');
                      },
                    )
                  : null),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 17, horizontal: 4),
        ),
      ),
    );
  }

  Widget _buildSkeleton(double padding) {
    return ListView(
      padding: EdgeInsets.fromLTRB(padding, 8, padding, 40),
      children: [
        for (var i = 0; i < 5; i++)
          Container(
            height: 64,
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: OhtliColors.cardBg,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: OhtliColors.cardBorder),
            ),
          ),
      ],
    );
  }

  /// Columna de tu gente: mejores amigos con sus fotos, la lista elegida
  /// (Amigos, Seguidos o Seguidores) y, después de una línea, Sugerencias.
  Widget _buildPeoplePanel(_PeopleData people, Map<String, DocumentSnapshot> users, EdgeInsets padding) {
    final listIds = switch (_peopleList) {
      'following' => people.following,
      'followers' => people.followers,
      _ => people.otherFriends,
    };
    final emptyText = switch (_peopleList) {
      'following' => _searchQuery.isNotEmpty ? 'Nadie con ese nombre entre quienes sigues.' : 'Aún no sigues a nadie.',
      'followers' => _searchQuery.isNotEmpty ? 'Nadie con ese nombre entre tus seguidores.' : 'Aún no tienes seguidores.',
      _ => _searchQuery.isNotEmpty
          ? 'Ningún amigo con ese nombre.'
          : (people.closeFriends.isEmpty ? 'Aún no tienes amigos en tu lista.' : 'Todos tus amigos están en mejores amigos.'),
    };

    Widget sectionTitle(String text, {Widget? trailing}) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            children: [
              Expanded(child: Text(text.toUpperCase(), style: OhtliUi.eyebrow(OhtliColors.accentText))),
              ?trailing,
            ],
          ),
        );

    return ListView(
      padding: padding,
      children: [
        // Mejores amigos: fotos grandes, como historias.
        sectionTitle('Mejores amigos'),
        if (people.closeFriends.isEmpty)
          Text(
            _searchQuery.isNotEmpty ? 'Ningún mejor amigo con ese nombre.' : 'Marca a tus amigos más cercanos con «Hacer mejor amigo» para tenerlos aquí.',
            style: OhtliUi.body(size: 13.5),
          )
        else
          SizedBox(
            height: 96,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              itemCount: people.closeFriends.length,
              separatorBuilder: (_, _) => const SizedBox(width: 14),
              itemBuilder: (context, i) {
                final id = people.closeFriends[i];
                final data = users[id]?.data() as Map<String, dynamic>?;
                final name = (data?['displayName'] as String?) ?? '…';
                return Semantics(
                  button: true,
                  label: 'Perfil de $name',
                  child: InkWell(
                    onTap: () => _openProfile(id),
                    borderRadius: BorderRadius.circular(16),
                    child: SizedBox(
                      width: 70,
                      child: Column(
                        children: [
                          _Avatar(name: name, photoURL: data?['photoURL'] as String?, closeFriend: true, size: 64),
                          const SizedBox(height: 6),
                          Text(name.split(' ').first,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: OhtliColors.onyx)),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        const SizedBox(height: 26),
        // Selector de la lista.
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final opt in [
                ('friends', 'Amigos', people.otherFriends.length + people.closeFriends.length),
                ('following', 'Seguidos', people.following.length),
                ('followers', 'Seguidores', people.followers.length),
              ]) ...[
                OhtliChoiceChip(
                  label: opt.$3 == 0 ? opt.$2 : '${opt.$2} · ${opt.$3}',
                  selected: _peopleList == opt.$1,
                  onTap: () => setState(() => _peopleList = opt.$1),
                ),
                const SizedBox(width: 8),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        if (listIds.isEmpty)
          Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text(emptyText, style: OhtliUi.body(size: 13.5)))
        else
          for (final id in listIds)
            _personRow(
              id,
              users[id],
              trailing: _peopleList == 'friends' ? _friendMenu(id, false) : null,
            ),
        const SizedBox(height: 22),
        Divider(color: OhtliColors.cardBorder, height: 1),
        const SizedBox(height: 22),
        sectionTitle('Sugerencias'),
        if (people.suggested.where((d) => !people.incomingPending.containsKey(d.id) && !people.sentPending.containsKey(d.id)).isEmpty)
          Text(_searchQuery.isNotEmpty ? 'No encontramos a nadie con ese nombre.' : 'Busca viajeros por su nombre para enviarles una solicitud.',
              style: OhtliUi.body(size: 13.5))
        else
          for (final doc in people.suggested
              .where((d) => !people.incomingPending.containsKey(d.id) && !people.sentPending.containsKey(d.id))
              .take(_searchQuery.isNotEmpty ? 30 : 12))
            _personRow(doc.id, doc, trailing: _suggestionAction(doc, people)),
      ],
    );
  }

  /// Solicitudes recibidas (Aceptar / Rechazar) y enviadas (Cancelar); van arriba de la actividad.
  Widget? _buildRequestsSection(_PeopleData people, Map<String, DocumentSnapshot> users) {
    if (people.incomingPending.isEmpty && people.sentPending.isEmpty) return null;
    Widget sectionTitle(String text, {Widget? trailing}) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            children: [
              Expanded(child: Text(text.toUpperCase(), style: OhtliUi.eyebrow(OhtliColors.accentText))),
              ?trailing,
            ],
          ),
        );
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: OhtliSurface(
        padding: const EdgeInsets.fromLTRB(14, 16, 14, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
          sectionTitle(
            'Solicitudes',
            trailing: people.incomingPending.isEmpty
                ? null
                : Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(color: OhtliColors.xoconostle, borderRadius: BorderRadius.circular(30)),
                    child: Text('${people.incomingPending.length}', style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w800, color: Colors.white)),
                  ),
          ),
          for (final e in people.incomingPending.entries)
            _personRow(
              e.key,
              users[e.key],
              highlight: true,
              subtitle: 'Te envió una solicitud',
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Rechazar',
                    onPressed: () => _declineFriendRequest(e.value, e.key),
                    icon: Icon(Icons.close_rounded, color: OhtliColors.subtleText),
                  ),
                  OhtliPrimaryButton(compact: true, label: 'Aceptar', onPressed: () => _acceptFriendRequestFromSuggested(e.value, e.key)),
                ],
              ),
            ),
          for (final e in people.sentPending.entries)
            _personRow(
              e.key,
              users[e.key],
              subtitle: 'Solicitud enviada',
              trailing: OhtliSecondaryButton(compact: true, label: 'Cancelar', onPressed: () => _cancelFriendRequest(e.value, e.key)),
            ),
          ],
        ),
      ),
    );
  }

  /// Renglón de una persona: foto, nombre, título (o un aviso) y una acción a la derecha.
  Widget _personRow(String id, DocumentSnapshot? doc, {Widget? trailing, String? subtitle, bool highlight = false}) {
    final data = doc?.data() as Map<String, dynamic>?;
    final String name = (data?['displayName'] as String?) ?? 'Viajero Ohtli';
    final String activeTitleId = (data?['activeTitleId'] as String?) ?? 'viajero';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: highlight ? OhtliColors.stormyTeal.withValues(alpha: 0.08) : Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: () => _openProfile(id),
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              children: [
                _Avatar(name: name, photoURL: data?['photoURL'] as String?, closeFriend: false, size: 46),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.outfit(color: OhtliColors.onyx, fontWeight: FontWeight.w800, fontSize: 15.5)),
                      const SizedBox(height: 2),
                      if (subtitle != null)
                        Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.inter(color: OhtliColors.accentText, fontSize: 12.5, fontWeight: FontWeight.w700))
                      else
                        StreamBuilder<DocumentSnapshot>(
                          stream: _titleStream(activeTitleId),
                          builder: (context, snap) {
                            final titleName = (snap.data?.data() as Map<String, dynamic>?)?['name'] ?? 'Viajero';
                            return Text(titleName.toString(),
                                maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.inter(color: OhtliColors.subtleText, fontSize: 12.5, fontWeight: FontWeight.w500));
                          },
                        ),
                    ],
                  ),
                ),
                if (trailing != null) ...[const SizedBox(width: 8), trailing],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Los títulos se comparten entre renglones: un stream por título, no por persona.
  final Map<String, Stream<DocumentSnapshot>> _titleStreams = {};
  Stream<DocumentSnapshot> _titleStream(String id) =>
      _titleStreams[id] ??= FirebaseFirestore.instance.collection('titles').doc(id).snapshots().asBroadcastStream();

  Widget _friendMenu(String friendId, bool isCloseFriend) {
    return PopupMenuButton<String>(
      tooltip: 'Opciones de amistad',
      onSelected: (action) => _toggleFriendStatus(friendId, action),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      color: OhtliColors.cardBg,
      icon: Icon(Icons.more_horiz_rounded, color: OhtliColors.subtleText),
      itemBuilder: (context) => [
        PopupMenuItem<String>(
          value: isCloseFriend ? 'friend' : 'closeFriend',
          child: _menuRow(
            isCloseFriend ? Icons.star_outline_rounded : Icons.star_rounded,
            isCloseFriend ? 'Quitar de mejores amigos' : 'Hacer mejor amigo',
            OhtliColors.cempasuchil,
          ),
        ),
        PopupMenuItem<String>(
          value: 'none',
          child: _menuRow(Icons.person_remove_rounded, 'Eliminar amigo', OhtliColors.xoconostle),
        ),
      ],
    );
  }

  Widget _suggestionAction(DocumentSnapshot doc, _PeopleData people) {
    final id = doc.id;
    final data = doc.data() as Map<String, dynamic>;
    final String? sentRequestId = people.sentPending[id];
    final String? incomingRequestId = people.incomingPending[id];
    if (sentRequestId != null) {
      return Tooltip(
        message: 'Cancelar solicitud',
        child: OhtliSecondaryButton(compact: true, label: 'Pendiente', onPressed: () => _cancelFriendRequest(sentRequestId, id)),
      );
    }
    if (incomingRequestId != null) {
      return OhtliPrimaryButton(compact: true, label: 'Aceptar', icon: Icons.check_rounded, onPressed: () => _acceptFriendRequestFromSuggested(incomingRequestId, id));
    }
    return OhtliSecondaryButton(
      compact: true,
      label: 'Añadir',
      icon: Icons.person_add_alt_1_rounded,
      onPressed: () => _sendFriendRequest(id, data['displayName'] ?? 'Viajero', data['photoURL']),
    );
  }

  Widget _menuRow(IconData icon, String label, Color color) => Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Text(label, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: OhtliColors.onyx)),
        ],
      );
}

/// Foto de perfil redonda con iniciales de respaldo y estrella si es mejor amigo.
class _Avatar extends StatelessWidget {
  final String name;
  final String? photoURL;
  final bool closeFriend;
  final double size;

  const _Avatar({required this.name, required this.photoURL, required this.closeFriend, this.size = 54});

  @override
  Widget build(BuildContext context) {
    final initials = name.split(' ').where((w) => w.isNotEmpty).take(2).map((w) => w[0].toUpperCase()).join();
    Widget fallback() => Center(
          child: Text(initials, style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w800, fontSize: size * 0.32)),
        );
    return SizedBox(
      width: size + 2,
      height: size + 2,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: OhtliColors.stormyTeal,
              boxShadow: OhtliUi.softShadow(),
            ),
            child: ClipOval(
              child: photoURL != null && photoURL!.isNotEmpty
                  ? Image.network(photoURL!, fit: BoxFit.cover, errorBuilder: (c, e, s) => fallback())
                  : fallback(),
            ),
          ),
          if (closeFriend)
            Positioned(
              right: -3,
              bottom: -3,
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: OhtliColors.cempasuchil,
                  shape: BoxShape.circle,
                  border: Border.all(color: OhtliColors.cardBg, width: 2.5),
                ),
                child: const Icon(Icons.star_rounded, size: 12, color: Colors.white),
              ),
            ),
        ],
      ),
    );
  }
}

/// Listas ya filtradas para la columna de tu gente.
class _PeopleData {
  final List<String> closeFriends;
  final List<String> otherFriends;
  final List<String> following;
  final List<String> followers;
  final List<DocumentSnapshot> suggested;
  final Map<String, String> sentPending;
  final Map<String, String> incomingPending;

  const _PeopleData({
    required this.closeFriends,
    required this.otherFriends,
    required this.following,
    required this.followers,
    required this.suggested,
    required this.sentPending,
    required this.incomingPending,
  });
}

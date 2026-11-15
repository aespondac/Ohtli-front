import '../services/social_graph.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../theme/colors.dart';
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
    _tabController = TabController(length: 4, vsync: this);
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
                  var suggestedUsers = allUsers.where((doc) => doc.id != _currentUser.uid && !friends.contains(doc.id)).toList()
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

                  final header = Padding(
                    padding: EdgeInsets.fromLTRB(padding, isMobile ? 24 : 40, padding, 0),
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

                  final tabs = Container(
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
                        Tab(height: 42, text: friends.isEmpty ? 'Tus amigos' : 'Tus amigos · ${friends.length}'),
                        Tab(height: 42, text: closeCount == 0 ? 'Mejores amigos' : 'Mejores amigos · $closeCount'),
                        Tab(height: 42, text: incoming == 0 ? 'Sugeridos' : 'Sugeridos · $incoming nuevas'),
                      ],
                    ),
                  );

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      header,
                      tabs,
                      Expanded(
                        child: social == null
                            ? _buildSkeleton(width, padding)
                            : TabBarView(
                                controller: _tabController,
                                children: [
                                  FriendsActivityFeed(
                                    friendIds: friends.map((e) => e.toString()).toList(),
                                    users: _userCache,
                                    padding: padding,
                                    onOpenProfile: _openProfile,
                                    onShowSuggestions: () => _tabController.animateTo(3),
                                  ),
                                  _buildFriendsList(friendUsers, closeFriends, width, padding, isSuggested: false, onlyCloseFriends: false),
                                  _buildFriendsList(friendUsers, closeFriends, width, padding, isSuggested: false, onlyCloseFriends: true),
                                  _buildFriendsList(
                                    suggestedUsers,
                                    closeFriends,
                                    width,
                                    padding,
                                    isSuggested: true,
                                    sentPendingMap: sentPendingMap,
                                    incomingPendingMap: incomingPendingMap,
                                  ),
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

  int _columnsFor(double width) => width > 1250 ? 3 : (width > 820 ? 2 : 1);

  Widget _buildSkeleton(double width, double padding) {
    return GridView.builder(
      padding: EdgeInsets.fromLTRB(padding, 8, padding, 40),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: _columnsFor(width),
        mainAxisExtent: 88,
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
      ),
      itemCount: 6,
      itemBuilder: (_, _) => Container(
        decoration: BoxDecoration(
          color: OhtliColors.cardBg,
          borderRadius: BorderRadius.circular(OhtliUi.radiusCard),
          border: Border.all(color: OhtliColors.cardBorder),
        ),
      ),
    );
  }

  Widget _buildFriendsList(
    List<DocumentSnapshot> list,
    List<dynamic> closeFriends,
    double width,
    double padding, {
    required bool isSuggested,
    bool onlyCloseFriends = false,
    Map<String, String> sentPendingMap = const {},
    Map<String, String> incomingPendingMap = const {},
  }) {
    final displayedList = onlyCloseFriends ? list.where((doc) => closeFriends.contains(doc.id)).toList() : list;

    if (displayedList.isEmpty) {
      final bool searching = _searchQuery.trim().isNotEmpty;
      return SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(padding, 8, padding, 40),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: searching
              ? OhtliEmptyState(
                  icon: Icons.search_off_rounded,
                  title: 'Sin resultados',
                  message: 'No encontramos a nadie con «${_searchQuery.trim()}». Revisa cómo se escribe su nombre.',
                )
              : isSuggested
                  ? const OhtliEmptyState(
                      icon: Icons.travel_explore_rounded,
                      title: 'No hay sugerencias por ahora',
                      message: 'Busca a otros viajeros por su nombre para enviarles una solicitud.',
                    )
                  : onlyCloseFriends
                      ? const OhtliEmptyState(
                          icon: Icons.star_rounded,
                          color: OhtliColors.cempasuchil,
                          title: 'Aún no eliges mejores amigos',
                          message: 'Marca a tus amigos más cercanos desde «Tus amigos» para compartir con ellos lo que solo ellos pueden ver.',
                        )
                      : OhtliEmptyState(
                          icon: Icons.people_alt_rounded,
                          title: 'Aún no tienes amigos en tu lista',
                          message: 'Con amigos puedes viajar juntos, dejarles planes sorpresa y ver lo que publican.',
                          action: OhtliPrimaryButton(
                            compact: true,
                            label: 'Ver sugeridos',
                            icon: Icons.person_add_alt_1_rounded,
                            onPressed: () => _tabController.animateTo(3),
                          ),
                        ),
        ),
      );
    }

    return GridView.builder(
      padding: EdgeInsets.fromLTRB(padding, 8, padding, 40),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: _columnsFor(width),
        mainAxisExtent: 88,
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
      ),
      itemCount: displayedList.length,
      itemBuilder: (context, index) {
        final doc = displayedList[index];
        final friendId = doc.id;
        final data = doc.data() as Map<String, dynamic>;
        final String name = data['displayName'] ?? 'Viajero Ohtli';
        final String? photoURL = data['photoURL'];
        final String activeTitleId = data['activeTitleId'] ?? 'viajero';
        final bool isCloseFriend = closeFriends.contains(friendId);
        final String? incomingRequestId = incomingPendingMap[friendId];

        return OhtliSurface(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          onTap: () => _openProfile(friendId),
          accent: isCloseFriend ? OhtliColors.cempasuchil : null,
          selected: isSuggested && incomingRequestId != null,
          child: Row(
            children: [
              _Avatar(name: name, photoURL: photoURL, closeFriend: isCloseFriend),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.outfit(color: OhtliColors.onyx, fontWeight: FontWeight.w800, fontSize: 16),
                    ),
                    const SizedBox(height: 3),
                    if (isSuggested && incomingRequestId != null)
                      Text('Te envió una solicitud',
                          style: GoogleFonts.inter(color: OhtliColors.accentText, fontSize: 12.5, fontWeight: FontWeight.w700))
                    else
                      StreamBuilder<DocumentSnapshot>(
                        stream: FirebaseFirestore.instance.collection('titles').doc(activeTitleId).snapshots(),
                        builder: (context, titleSnapshot) {
                          String titleName = 'Viajero';
                          if (titleSnapshot.hasData && titleSnapshot.data!.exists) {
                            final titleData = titleSnapshot.data!.data() as Map<String, dynamic>?;
                            titleName = titleData?['name'] ?? 'Viajero';
                          }
                          return Text(titleName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(color: OhtliColors.subtleText, fontSize: 12.5, fontWeight: FontWeight.w500));
                        },
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              if (isSuggested)
                () {
                  final String? sentRequestId = sentPendingMap[friendId];
                  if (sentRequestId != null) {
                    return Tooltip(
                      message: 'Cancelar solicitud',
                      child: OhtliSecondaryButton(
                        compact: true,
                        label: 'Pendiente',
                        icon: Icons.hourglass_top_rounded,
                        onPressed: () => _cancelFriendRequest(sentRequestId, friendId),
                      ),
                    );
                  } else if (incomingRequestId != null) {
                    return OhtliPrimaryButton(
                      compact: true,
                      label: 'Aceptar',
                      icon: Icons.check_rounded,
                      onPressed: () => _acceptFriendRequestFromSuggested(incomingRequestId, friendId),
                    );
                  }
                  return OhtliSecondaryButton(
                    compact: true,
                    label: 'Añadir',
                    icon: Icons.person_add_alt_1_rounded,
                    onPressed: () => _sendFriendRequest(friendId, name, photoURL),
                  );
                }()
              else
                PopupMenuButton<String>(
                  tooltip: 'Opciones de amistad',
                  onSelected: (action) => _toggleFriendStatus(friendId, action),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                  color: OhtliColors.cardBg,
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
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: isCloseFriend ? OhtliColors.cempasuchil.withValues(alpha: 0.14) : OhtliColors.innerCardBg,
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(color: isCloseFriend ? OhtliColors.cempasuchil.withValues(alpha: 0.4) : OhtliColors.cardBorder),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(isCloseFriend ? Icons.star_rounded : Icons.check_rounded,
                            size: 15, color: isCloseFriend ? OhtliColors.cempasuchil : OhtliColors.accentText),
                        const SizedBox(width: 5),
                        Text(
                          isCloseFriend ? 'Mejor amigo' : 'Amigo',
                          style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w700, color: OhtliColors.onyx),
                        ),
                        const SizedBox(width: 2),
                        Icon(Icons.expand_more_rounded, size: 16, color: OhtliColors.subtleText),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );
      },
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

  const _Avatar({required this.name, required this.photoURL, required this.closeFriend});

  @override
  Widget build(BuildContext context) {
    final initials = name.split(' ').where((w) => w.isNotEmpty).take(2).map((w) => w[0].toUpperCase()).join();
    Widget fallback() => Center(
          child: Text(initials, style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 17)),
        );
    return SizedBox(
      width: 56,
      height: 56,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: OhtliColors.stormyTeal,
              border: Border.all(color: closeFriend ? OhtliColors.cempasuchil : OhtliColors.cardBg, width: 2.5),
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

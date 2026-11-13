// ignore_for_file: deprecated_member_use, avoid_print

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../theme/colors.dart';
import '../../models/poi_model.dart';
import '../../widgets/poi_detail_dialog.dart';
import '../construction_page.dart'; // RouteBackgroundPainter
import '../places/places_page.dart';
import '../trips/trip_viewer_page.dart';

// Crónicas destacadas (fijadas por el equipo editorial)
class PinnedStory {
  final String tripId;
  final String authorId;

  const PinnedStory({required this.tripId, required this.authorId});
}

const List<PinnedStory> kPinnedStories = [
  PinnedStory(
    tripId: '8c945367-4543-403d-8f56-51798d7f4e7d',
    authorId: '4cavo5EKn6Vvuoo2s46VokEj7lE3',
  ),
];

/// Resumen ligero de una crónica pública para las tarjetas de Explorar.
class _CommunityTrip {
  final String tripId;
  final String authorId;
  final String title;
  final String description;
  final String coverUrl;
  final DateTime updatedAt;

  const _CommunityTrip({
    required this.tripId,
    required this.authorId,
    required this.title,
    required this.description,
    required this.coverUrl,
    required this.updatedAt,
  });
}

/// Vista "Explorar": portada de la app con crónicas destacadas, accesos rápidos,
/// una selección diaria de lugares y las crónicas públicas de la comunidad.
class ExplorePage extends StatefulWidget {
  /// Cambia a otra pestaña de HomePage (1: Mis Viajes, 3: Amigos, 5: Lugares…)
  final ValueChanged<int> onOpenTab;
  final VoidCallback onPlanTrip;

  const ExplorePage({
    super.key,
    required this.onOpenTab,
    required this.onPlanTrip,
  });

  @override
  State<ExplorePage> createState() => _ExplorePageState();
}

class _ExplorePageState extends State<ExplorePage> {
  // Preservar iconos contra tree-shaking en la web
  // ignore: unused_field
  static const List<Icon> _preservedIcons = [
    Icon(Icons.add_road_rounded),
    Icon(Icons.place_outlined),
    Icon(Icons.map_outlined),
    Icon(Icons.people_outline),
    Icon(Icons.arrow_forward_rounded),
    Icon(Icons.auto_stories_outlined),
    Icon(Icons.refresh_rounded),
    Icon(Icons.stars_rounded),
    Icon(Icons.location_on_outlined),
  ];

  // Creados una sola vez: si se recrean en cada build, la crónica destacada
  // vuelve a pedirse (y parpadea) y el carrusel regresa a la primera tarjeta.
  final PageController _pinnedController = PageController(viewportFraction: 1.0);
  final Map<String, Future<List<DocumentSnapshot>>> _pinnedFutures = {};
  final Map<String, Future<DocumentSnapshot>> _authorFutures = {};
  int _pinnedPage = 0;

  late Future<List<Poi>> _placesFuture;
  late Future<List<_CommunityTrip>> _communityFuture;

  @override
  void initState() {
    super.initState();
    _placesFuture = _loadDailyPlaces();
    _communityFuture = _loadCommunityTrips();
  }

  @override
  void dispose() {
    _pinnedController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Datos
  // ---------------------------------------------------------------------------

  /// Selección del día: misma lista durante todo el día, distinta al siguiente.
  Future<List<Poi>> _loadDailyPlaces() async {
    final catalog = await PlacesPage.loadCatalog();
    final now = DateTime.now();
    final seed = now.year * 1000 + now.month * 40 + now.day;
    final withPhoto = catalog.where((p) => p.photoUrl.isNotEmpty).toList();
    final pool = withPhoto.length >= 8 ? withPhoto : List<Poi>.from(catalog);
    pool.sort((a, b) => ((a.poiId.hashCode ^ seed) & 0x7fffffff)
        .compareTo((b.poiId.hashCode ^ seed) & 0x7fffffff));

    // Variedad: como máximo 3 lugares por categoría
    final perCategory = <String, int>{};
    final picks = <Poi>[];
    for (final poi in pool) {
      final count = perCategory[poi.category] ?? 0;
      if (count >= 3) continue;
      perCategory[poi.category] = count + 1;
      picks.add(poi);
      if (picks.length >= 12) break;
    }
    return picks;
  }

  Future<List<_CommunityTrip>> _loadCommunityTrips() async {
    final pinnedIds = kPinnedStories.map((p) => p.tripId).toSet();
    final snapshot = await FirebaseFirestore.instance
        .collectionGroup('trips')
        .where('status', isEqualTo: 'published')
        .where('visibility', isEqualTo: 'public')
        // Requiere el índice compuesto (status, visibility, updatedAt) de firestore.indexes.json
        .orderBy('updatedAt', descending: true)
        .limit(20)
        .get()
        .timeout(const Duration(seconds: 10));

    final trips = <_CommunityTrip>[];
    for (final doc in snapshot.docs) {
      if (pinnedIds.contains(doc.id)) continue;
      final data = doc.data();
      // Las sorpresas no se muestran en el feed público
      if (data['isSurprise'] == true) continue;
      final authorId = (data['userId'] ?? doc.reference.parent.parent?.id ?? '').toString();
      if (authorId.isEmpty) continue;
      final updated = data['updatedAt'];
      trips.add(_CommunityTrip(
        tripId: doc.id,
        authorId: authorId,
        title: (data['title'] ?? '').toString().trim().isEmpty
            ? 'Viaje sin título'
            : data['title'].toString(),
        description: (data['description'] ?? '').toString(),
        coverUrl: (data['coverUrl'] ?? '').toString(),
        updatedAt: updated is Timestamp ? updated.toDate() : DateTime.fromMillisecondsSinceEpoch(0),
      ));
    }
    trips.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return trips.take(12).toList();
  }

  Future<DocumentSnapshot> _authorFuture(String authorId) {
    return _authorFutures[authorId] ??=
        FirebaseFirestore.instance.collection('users').doc(authorId).get();
  }

  void _openTrip(String tripId, String authorId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TripViewerPage(tripId: tripId, authorId: authorId),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Layout
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final bool isDark = OhtliSettings.instance.isDarkMode;
    final bool isMobile = MediaQuery.of(context).size.width < 800;
    final double gutter = isMobile ? 16.0 : 24.0;

    return Stack(
      children: [
        Positioned.fill(
          child: CustomPaint(
            painter: RouteBackgroundPainter(OhtliColors.cantera.withOpacity(0.95)),
          ),
        ),
        Positioned.fill(
          child: SafeArea(
            child: RefreshIndicator(
              color: OhtliColors.stormyTeal,
              onRefresh: () async {
                setState(() {
                  _placesFuture = _loadDailyPlaces();
                  _communityFuture = _loadCommunityTrips();
                });
                await Future.wait([
                  _placesFuture.catchError((_) => <Poi>[]),
                  _communityFuture.catchError((_) => <_CommunityTrip>[]),
                ]);
              },
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                // Espacio extra abajo para que el botón flotante no tape la última sección
                padding: const EdgeInsets.only(bottom: 110.0),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1280),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildGreeting(isMobile, gutter),
                        _buildPinnedStoriesCarousel(isMobile, isDark),
                        if (kPinnedStories.length > 1) _buildPinnedDots(),
                        const SizedBox(height: 8),
                        _buildQuickActions(isMobile, gutter),
                        const SizedBox(height: 28),
                        _buildSectionHeader(
                          gutter: gutter,
                          title: 'Lugares para descubrir',
                          subtitle: 'Una selección del día curada por nuestro Agente Recolector',
                          actionLabel: 'Ver todos',
                          onAction: () => widget.onOpenTab(5),
                        ),
                        _buildPlacesRow(isMobile, gutter),
                        const SizedBox(height: 28),
                        _buildSectionHeader(
                          gutter: gutter,
                          title: 'Crónicas de la comunidad',
                          subtitle: 'Rutas reales que otros viajeros compartieron',
                        ),
                        _buildCommunityRow(isMobile, gutter),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildGreeting(bool isMobile, double gutter) {
    final user = FirebaseAuth.instance.currentUser;
    final fullName = user?.displayName?.trim() ?? '';
    final firstName = fullName.isNotEmpty ? fullName.split(' ').first : '';
    final hour = DateTime.now().hour;
    final salute = hour < 12
        ? 'Buenos días'
        : (hour < 19 ? 'Buenas tardes' : 'Buenas noches');

    return Padding(
      padding: EdgeInsets.fromLTRB(gutter, isMobile ? 16 : 28, gutter, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            firstName.isNotEmpty ? '$salute, $firstName' : salute,
            style: GoogleFonts.outfit(
              fontSize: isMobile ? 24 : 30,
              fontWeight: FontWeight.w600,
              color: OhtliColors.onyx,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '¿Qué camino de la Ciudad de México quieres recorrer hoy?',
            style: GoogleFonts.inter(
              fontSize: isMobile ? 13 : 14,
              fontWeight: FontWeight.w300,
              color: OhtliColors.subtleText,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPinnedDots() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(kPinnedStories.length, (i) {
        final active = i == _pinnedPage;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          margin: const EdgeInsets.symmetric(horizontal: 3),
          width: active ? 18 : 6,
          height: 6,
          decoration: BoxDecoration(
            color: active ? OhtliColors.stormyTeal : OhtliColors.cantera,
            borderRadius: BorderRadius.circular(3),
          ),
        );
      }),
    );
  }

  Widget _buildQuickActions(bool isMobile, double gutter) {
    final actions = <_QuickAction>[
      _QuickAction(
        icon: Icons.add_road_rounded,
        title: 'Planea un viaje',
        subtitle: 'Arma tu ruta ideal',
        color: OhtliColors.stormyTeal,
        onTap: widget.onPlanTrip,
      ),
      _QuickAction(
        icon: Icons.place_outlined,
        title: 'Lugares',
        subtitle: 'Explora el catálogo',
        color: OhtliColors.xoconostle,
        onTap: () => widget.onOpenTab(5),
      ),
      _QuickAction(
        icon: Icons.map_outlined,
        title: 'Mis viajes',
        subtitle: 'Tus crónicas y borradores',
        color: OhtliColors.cempasuchil,
        onTap: () => widget.onOpenTab(1),
      ),
      _QuickAction(
        icon: Icons.people_outline,
        title: 'Amigos',
        subtitle: 'Viaja acompañado',
        color: const Color(0xFF4A7C59),
        onTap: () => widget.onOpenTab(3),
      ),
    ];

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: gutter),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth < 560 ? 2 : 4;
          const spacing = 12.0;
          final itemWidth = (constraints.maxWidth - spacing * (columns - 1)) / columns;
          return Wrap(
            spacing: spacing,
            runSpacing: spacing,
            children: actions
                .map((a) => SizedBox(width: itemWidth, child: _QuickActionCard(action: a)))
                .toList(),
          );
        },
      ),
    );
  }

  Widget _buildSectionHeader({
    required double gutter,
    required String title,
    String? subtitle,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    return Padding(
      padding: EdgeInsets.fromLTRB(gutter, 0, gutter, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.outfit(
                    fontSize: 19,
                    fontWeight: FontWeight.w600,
                    color: OhtliColors.onyx,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w300,
                      color: OhtliColors.subtleText,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (actionLabel != null && onAction != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(foregroundColor: OhtliColors.stormyTeal),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    actionLabel,
                    style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.arrow_forward_rounded, size: 14),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Lugares
  // ---------------------------------------------------------------------------

  Widget _buildPlacesRow(bool isMobile, double gutter) {
    final double cardWidth = isMobile ? 200 : 240;
    final double cardHeight = isMobile ? 250 : 280;

    return FutureBuilder<List<Poi>>(
      future: _placesFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildSkeletonRow(gutter, cardWidth, cardHeight);
        }
        if (snapshot.hasError || (snapshot.data?.isEmpty ?? true)) {
          return _buildInlineMessage(
            gutter: gutter,
            icon: Icons.place_outlined,
            message: snapshot.hasError
                ? 'No pudimos cargar los lugares. El servidor puede estar despertando.'
                : 'Aún no hay lugares en el catálogo.',
            actionLabel: snapshot.hasError ? 'Reintentar' : null,
            onAction: snapshot.hasError
                ? () => setState(() => _placesFuture = _loadDailyPlaces())
                : null,
          );
        }

        final places = snapshot.data!;
        return SizedBox(
          height: cardHeight + 8,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(horizontal: gutter, vertical: 4),
            itemCount: places.length,
            separatorBuilder: (_, _) => const SizedBox(width: 14),
            itemBuilder: (context, index) {
              final poi = places[index];
              return _ExploreCard(
                width: cardWidth,
                height: cardHeight,
                imageUrl: poi.imageUrl,
                badgeIcon: poi.categoryIcon,
                badgeLabel: poi.categoryDisplay,
                badgeColor: poi.categoryColor,
                title: poi.name,
                caption: poi.coloniaAlcaldiaDisplay,
                captionIcon: Icons.location_on_outlined,
                onTap: () => PoiDetailDialog.show(context, poi),
              );
            },
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Crónicas de la comunidad
  // ---------------------------------------------------------------------------

  Widget _buildCommunityRow(bool isMobile, double gutter) {
    final double cardWidth = isMobile ? 240 : 300;
    final double cardHeight = isMobile ? 230 : 260;

    return FutureBuilder<List<_CommunityTrip>>(
      future: _communityFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildSkeletonRow(gutter, cardWidth, cardHeight);
        }
        if (snapshot.hasError) {
          print('Explorar: error cargando crónicas públicas: ${snapshot.error}');
          return _buildInlineMessage(
            gutter: gutter,
            icon: Icons.auto_stories_outlined,
            message: 'No pudimos cargar las crónicas de la comunidad.',
            actionLabel: 'Reintentar',
            onAction: () => setState(() => _communityFuture = _loadCommunityTrips()),
          );
        }
        final trips = snapshot.data ?? const [];
        if (trips.isEmpty) {
          return _buildInlineMessage(
            gutter: gutter,
            icon: Icons.auto_stories_outlined,
            message: 'Todavía no hay crónicas públicas. ¡Publica la tuya y sé el primero!',
            actionLabel: 'Ir a Mis viajes',
            onAction: () => widget.onOpenTab(1),
          );
        }

        return SizedBox(
          height: cardHeight + 8,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(horizontal: gutter, vertical: 4),
            itemCount: trips.length,
            separatorBuilder: (_, _) => const SizedBox(width: 14),
            itemBuilder: (context, index) {
              final trip = trips[index];
              return FutureBuilder<DocumentSnapshot>(
                future: _authorFuture(trip.authorId),
                builder: (context, authorSnap) {
                  final authorData = (authorSnap.data?.exists ?? false)
                      ? authorSnap.data!.data() as Map<String, dynamic>?
                      : null;
                  final authorName = (authorData?['displayName'] ?? 'Viajero Ohtli').toString();
                  return _ExploreCard(
                    width: cardWidth,
                    height: cardHeight,
                    imageUrl: trip.coverUrl,
                    badgeIcon: Icons.auto_stories_outlined,
                    badgeLabel: 'Crónica',
                    badgeColor: OhtliColors.stormyTeal,
                    title: trip.title,
                    caption: 'por $authorName',
                    captionIcon: Icons.person_outline,
                    onTap: () => _openTrip(trip.tripId, trip.authorId),
                  );
                },
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildSkeletonRow(double gutter, double width, double height) {
    return SizedBox(
      height: height + 8,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.symmetric(horizontal: gutter, vertical: 4),
        itemCount: 4,
        separatorBuilder: (_, _) => const SizedBox(width: 14),
        itemBuilder: (_, _) => Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: OhtliColors.cardBg.withOpacity(0.6),
            borderRadius: BorderRadius.circular(20),
          ),
        ),
      ),
    );
  }

  Widget _buildInlineMessage({
    required double gutter,
    required IconData icon,
    required String message,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: gutter),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        decoration: BoxDecoration(
          color: OhtliColors.cardBg.withOpacity(0.85),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: OhtliColors.cardBorder),
        ),
        child: Row(
          children: [
            Icon(icon, color: OhtliColors.stormyTeal, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: GoogleFonts.inter(fontSize: 13, color: OhtliColors.subtleText),
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(width: 8),
              TextButton(
                onPressed: onAction,
                style: TextButton.styleFrom(foregroundColor: OhtliColors.stormyTeal),
                child: Text(
                  actionLabel,
                  style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Crónicas destacadas (carrusel)
  // ---------------------------------------------------------------------------

  Widget _buildPinnedStoriesCarousel(bool isMobile, bool isDark) {
    final double height = isMobile ? 260.0 : 380.0;

    return SizedBox(
      height: height,
      width: double.infinity,
      child: PageView.builder(
        controller: _pinnedController,
        itemCount: kPinnedStories.length,
        onPageChanged: (page) => setState(() => _pinnedPage = page),
        itemBuilder: (context, index) {
          final pinned = kPinnedStories[index];
          return _buildPinnedStoryCard(pinned, isMobile, isDark);
        },
      ),
    );
  }

  Widget _buildPinnedStoryCard(PinnedStory pinned, bool isMobile, bool isDark) {
    return FutureBuilder<List<DocumentSnapshot>>(
      future: _pinnedFutures['${pinned.authorId}/${pinned.tripId}'] ??= Future.wait([
        FirebaseFirestore.instance
            .collection('users')
            .doc(pinned.authorId)
            .collection('trips')
            .doc(pinned.tripId)
            .get(),
        FirebaseFirestore.instance
            .collection('users')
            .doc(pinned.authorId)
            .get(),
      ]),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Container(
            margin: EdgeInsets.symmetric(
              horizontal: isMobile ? 16.0 : 24.0,
              vertical: isMobile ? 12.0 : 16.0,
            ),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E1E22) : Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Center(
              child: CircularProgressIndicator(color: OhtliColors.stormyTeal),
            ),
          );
        }

        if (!snapshot.hasData || snapshot.data![0].exists == false) {
          return const SizedBox();
        }

        final tripDoc = snapshot.data![0];
        final authorDoc = snapshot.data![1];

        final tripData = tripDoc.data() as Map<String, dynamic>?;
        final authorData = authorDoc.exists ? (authorDoc.data() as Map<String, dynamic>?) : null;

        final String title = tripData?['title'] ?? 'Sin Título';
        final String cover = tripData?['coverUrl'] ?? '';
        final String desc = tripData?['description'] ?? 'Sin descripción.';
        
        final String authorName = authorData?['displayName'] ?? 'Viajero Ohtli';
        final String? authorPhoto = authorData?['photoURL'];
        final String activeTitleId = authorData?['activeTitleId'] ?? 'viajero';

        bool isHovered = false;
        return StatefulBuilder(
          builder: (context, setState) {
            return MouseRegion(
              onEnter: (_) => setState(() => isHovered = true),
              onExit: (_) => setState(() => isHovered = false),
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => TripViewerPage(
                        tripId: pinned.tripId,
                        authorId: pinned.authorId,
                      ),
                    ),
                  );
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOutCubic,
                  margin: EdgeInsets.symmetric(
                    horizontal: isMobile ? 16.0 : 24.0,
                    vertical: isMobile ? 12.0 : 16.0,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: isHovered 
                            ? OhtliColors.stormyTeal.withOpacity(0.15)
                            : Colors.black.withOpacity(0.08),
                        blurRadius: isHovered ? 16 : 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Stack(
                      children: [
                        // Cover Image Background with Zoom Effect on Hover
                        Positioned.fill(
                          child: AnimatedScale(
                            scale: isHovered ? 1.05 : 1.0,
                            duration: const Duration(milliseconds: 400),
                            curve: Curves.easeOutCubic,
                            child: cover.isNotEmpty
                                ? Image(
                                    image: _getImageProvider(cover),
                                    fit: BoxFit.cover,
                                  )
                                : Container(color: OhtliColors.cantera),
                          ),
                        ),
                        // Premium Dark Gradient Overlay
                        Positioned.fill(
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Colors.black.withOpacity(0.8),
                                  Colors.black.withOpacity(0.1),
                                  Colors.black.withOpacity(0.85),
                                ],
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                stops: const [0.0, 0.45, 1.0],
                              ),
                            ),
                          ),
                        ),
                        // Badge: "CRÓNICA DESTACADA"
                        Positioned(
                          top: isMobile ? 16 : 24,
                          left: isMobile ? 16 : 24,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: OhtliColors.xoconostle,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.stars_rounded, color: Colors.white, size: 12),
                                const SizedBox(width: 4),
                                Text(
                                  'CRÓNICA DESTACADA',
                                  style: GoogleFonts.inter(
                                    color: Colors.white,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 1.0,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        
                        // Content overlay
                        Positioned(
                          bottom: isMobile ? 16 : 32,
                          left: isMobile ? 16 : 32,
                          right: isMobile ? 16 : 32,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                style: GoogleFonts.outfit(
                                  color: Colors.white,
                                  fontSize: isMobile ? 18 : 22,
                                  fontWeight: FontWeight.bold,
                                  height: 1.2,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                desc,
                                style: GoogleFonts.inter(
                                  color: Colors.white.withOpacity(0.8),
                                  fontSize: 12,
                                  height: 1.4,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 14),
                              // Author Profile Row
                              Row(
                                children: [
                                  Container(
                                    width: 28,
                                    height: 28,
                                    decoration: const BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: OhtliColors.stormyTeal,
                                    ),
                                    child: ClipOval(
                                      child: authorPhoto != null && authorPhoto.isNotEmpty
                                          ? Image(
                                              image: _getImageProvider(authorPhoto),
                                              fit: BoxFit.cover,
                                              errorBuilder: (c, e, s) => Center(
                                                child: Text(
                                                  authorName.substring(0, 1).toUpperCase(),
                                                  style: GoogleFonts.inter(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                                ),
                                              ),
                                            )
                                          : Center(
                                              child: Text(
                                                authorName.substring(0, 1).toUpperCase(),
                                                style: GoogleFonts.inter(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                              ),
                                            ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          authorName,
                                          style: GoogleFonts.outfit(
                                            color: Colors.white,
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        StreamBuilder<DocumentSnapshot>(
                                          stream: FirebaseFirestore.instance
                                              .collection('titles')
                                              .doc(activeTitleId)
                                              .snapshots(),
                                          builder: (context, titleSnapshot) {
                                            String titleName = 'Viajero';
                                            if (titleSnapshot.hasData && titleSnapshot.data!.exists) {
                                              final titleData = titleSnapshot.data!.data() as Map<String, dynamic>?;
                                              titleName = titleData?['name'] ?? 'Viajero';
                                            }
                                            return Text(
                                              titleName,
                                              style: GoogleFonts.inter(
                                                color: Colors.white.withOpacity(0.6),
                                                fontSize: 10,
                                              ),
                                            );
                                          },
                                        ),
                                      ],
                                    ),
                                  ),
                                  // Read Action Indicator
                                  Row(
                                    children: [
                                      Text(
                                        'Leer historia',
                                        style: GoogleFonts.inter(
                                          color: Colors.white,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 12),
                                    ],
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  ImageProvider _getImageProvider(String url) {
    if (url.startsWith('data:')) {
      final String base64Data = url.split(',').last;
      return MemoryImage(base64Decode(base64Data));
    }
    return NetworkImage(url);
  }
}

// -----------------------------------------------------------------------------
// Widgets auxiliares
// -----------------------------------------------------------------------------

class _QuickAction {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _QuickAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });
}

class _QuickActionCard extends StatefulWidget {
  final _QuickAction action;

  const _QuickActionCard({required this.action});

  @override
  State<_QuickActionCard> createState() => _QuickActionCardState();
}

class _QuickActionCardState extends State<_QuickActionCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final a = widget.action;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: a.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: OhtliColors.cardBg.withOpacity(0.92),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: _hovered ? a.color.withOpacity(0.5) : OhtliColors.cardBorder,
            ),
            boxShadow: [
              BoxShadow(
                color: (_hovered ? a.color : Colors.black).withOpacity(_hovered ? 0.14 : 0.05),
                blurRadius: _hovered ? 16 : 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: a.color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(a.icon, color: a.color, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      a.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.outfit(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: OhtliColors.onyx,
                      ),
                    ),
                    Text(
                      a.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(fontSize: 11, color: OhtliColors.subtleText),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Tarjeta con imagen de fondo, insignia y título, usada en las filas horizontales.
class _ExploreCard extends StatefulWidget {
  final double width;
  final double height;
  final String imageUrl;
  final IconData badgeIcon;
  final String badgeLabel;
  final Color badgeColor;
  final String title;
  final String caption;
  final IconData captionIcon;
  final VoidCallback onTap;

  const _ExploreCard({
    required this.width,
    required this.height,
    required this.imageUrl,
    required this.badgeIcon,
    required this.badgeLabel,
    required this.badgeColor,
    required this.title,
    required this.caption,
    required this.captionIcon,
    required this.onTap,
  });

  @override
  State<_ExploreCard> createState() => _ExploreCardState();
}

class _ExploreCardState extends State<_ExploreCard> {
  bool _hovered = false;

  ImageProvider? _provider() {
    final url = widget.imageUrl;
    if (url.isEmpty) return null;
    if (url.startsWith('data:')) {
      try {
        return MemoryImage(base64Decode(url.split(',').last));
      } catch (_) {
        return null;
      }
    }
    return NetworkImage(url);
  }

  @override
  Widget build(BuildContext context) {
    final provider = _provider();
    final placeholder = Container(
      color: OhtliColors.cantera,
      child: Center(
        child: Icon(widget.badgeIcon, color: Colors.white.withOpacity(0.8), size: 36),
      ),
    );

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
          width: widget.width,
          height: widget.height,
          transform: Matrix4.translationValues(0, _hovered ? -3 : 0, 0),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: _hovered
                    ? OhtliColors.stormyTeal.withOpacity(0.18)
                    : Colors.black.withOpacity(0.08),
                blurRadius: _hovered ? 16 : 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Stack(
              children: [
                Positioned.fill(
                  child: AnimatedScale(
                    scale: _hovered ? 1.05 : 1.0,
                    duration: const Duration(milliseconds: 400),
                    curve: Curves.easeOutCubic,
                    child: provider == null
                        ? placeholder
                        : Image(
                            image: provider,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => placeholder,
                          ),
                  ),
                ),
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withOpacity(0.25),
                          Colors.transparent,
                          Colors.black.withOpacity(0.82),
                        ],
                        stops: const [0.0, 0.4, 1.0],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 12,
                  left: 12,
                  right: 12,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                      decoration: BoxDecoration(
                        color: widget.badgeColor.withOpacity(0.9),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(widget.badgeIcon, color: Colors.white, size: 11),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              widget.badgeLabel.toUpperCase(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.8,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 14,
                  right: 14,
                  bottom: 14,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.outfit(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          height: 1.2,
                        ),
                      ),
                      if (widget.caption.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(widget.captionIcon, color: Colors.white70, size: 12),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                widget.caption,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.inter(color: Colors.white70, fontSize: 11),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

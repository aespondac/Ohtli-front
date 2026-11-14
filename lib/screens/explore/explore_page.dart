// ignore_for_file: deprecated_member_use, avoid_print

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../theme/colors.dart';
import '../../models/poi_model.dart';
import '../../widgets/poi_detail_dialog.dart';
import '../places/places_page.dart';
import '../trips/trip_viewer_page.dart';
import '../../config/editorial.dart';
import '../../services/explore_config_service.dart';
import '../../services/saved_places.dart';
import '../../widgets/ohtli_ui.dart';
import '../../widgets/ohtli_service_icon.dart';
import '../../widgets/poi_card.dart';
import '../../widgets/trip_planner_dialog.dart';
import '../../widgets/trip_polaroid.dart';
import '../../models/trip_model.dart';

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

  // Historias destacadas: últimas notas de versión del equipo + crónicas fijadas.
  List<PinnedStory> _featured = List<PinnedStory>.from(kPinnedStories);

  late Future<List<Poi>> _placesFuture;
  late Future<List<_CommunityTrip>> _communityFuture;

  @override
  void initState() {
    super.initState();
    _placesFuture = _loadDailyPlaces();
    _communityFuture = _loadCommunityTrips();
    _loadFeatured();
  }

  // Viajes que el superusuario eligió para el bloque principal (null = destacados por defecto)
  List<PinnedStory>? _configuredPinned;

  /// Bloque principal: la nota de versión (si el superusuario la tiene activada) y luego los
  /// viajes que él eligió en Cuenta → Administración → Destacados de Explorar.
  Future<void> _loadFeatured() async {
    final config = await ExploreConfigService.load();
    final pinned = config.pinned?.map((p) => PinnedStory(tripId: p.tripId, authorId: p.authorId)).toList();
    final notes = config.showReleaseNotes ? await _loadReleaseNotes() : const <PinnedStory>[];
    if (!mounted) return;
    final base = pinned ?? kPinnedStories;
    final ids = notes.map((n) => n.tripId).toSet();
    final featured = [...notes, ...base.where((p) => !ids.contains(p.tripId))];
    setState(() {
      _configuredPinned = pinned;
      _featured = featured;
      _pinnedPage = 0;
      // Lo que ya va en el bloque principal no se repite en el feed de la comunidad
      if (pinned != null) _communityFuture = _loadCommunityTrips();
    });
    if (_pinnedController.hasClients) _pinnedController.jumpToPage(0);
  }

  /// Notas de versión publicadas por el equipo editorial, la más reciente primero.
  /// Solo filtros de igualdad: no requieren índice compuesto, y incluir
  /// visibility == public permite que las reglas acepten la consulta de cualquiera.
  Future<List<PinnedStory>> _loadReleaseNotes() async {
    try {
      // Solo las del superusuario (único que puede publicarlas, ver config/admin.dart)
      final superUid = await SuperUserDirectory.uid();
      if (superUid == null) return const [];
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(superUid)
          .collection('trips')
          .where('kind', isEqualTo: 'release_notes')
          .where('status', isEqualTo: 'published')
          .where('visibility', isEqualTo: 'public')
          .get()
          .timeout(const Duration(seconds: 10));
      final docs = snapshot.docs.toList();
      DateTime when(QueryDocumentSnapshot<Map<String, dynamic>> d) {
        final u = d.data()['updatedAt'];
        return u is Timestamp ? u.toDate() : DateTime.fromMillisecondsSinceEpoch(0);
      }

      docs.sort((a, b) => when(b).compareTo(when(a)));
      final notes = docs
          .take(kFeaturedReleaseNotes)
          .map((d) => PinnedStory(tripId: d.id, authorId: (d.data()['userId'] ?? d.reference.parent.parent!.id).toString()))
          .toList();
      return notes;
    } catch (e) {
      print('No se pudieron cargar las notas de versión: $e');
      return const [];
    }
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
    final pinnedIds = (_configuredPinned ?? kPinnedStories).map((p) => p.tripId).toSet();
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
      // Las notas de versión van en el carrusel de destacadas, no en el feed
      if (data['kind'] == 'release_notes') continue;
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
    final double gutter = isMobile ? 16.0 : 40.0;

    return Stack(
      children: [
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
                // Ocupa todo el ancho disponible junto al menú lateral
                child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildGreeting(isMobile, gutter),
                        if (_featured.isNotEmpty) _buildPinnedStoriesCarousel(isMobile, isDark),
                        if (_featured.length > 1) _buildPinnedDots(),
                        const SizedBox(height: 12),
                        _buildQuickActions(isMobile, gutter),
                        const SizedBox(height: 40),
                        _buildSectionHeader(
                          gutter: gutter,
                          eyebrow: 'Selección del día',
                          icon: Icons.auto_awesome_rounded,
                          title: 'Lugares para descubrir',
                          subtitle: 'Una selección del día curada por nuestro Agente Recolector',
                          actionLabel: 'Ver todos',
                          onAction: () => widget.onOpenTab(5),
                        ),
                        _buildPlacesRow(isMobile, gutter),
                        const SizedBox(height: 40),
                        _buildSectionHeader(
                          gutter: gutter,
                          eyebrow: 'Comunidad',
                          icon: Icons.auto_stories_rounded,
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
      padding: EdgeInsets.fromLTRB(gutter, isMobile ? 20 : 36, gutter, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.explore_rounded, size: 14, color: OhtliColors.accentText),
              const SizedBox(width: 6),
              Text('EXPLORAR · CIUDAD DE MÉXICO', style: OhtliUi.eyebrow(OhtliColors.accentText)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            firstName.isNotEmpty ? '$salute, $firstName' : salute,
            style: OhtliUi.title(size: isMobile ? 28 : 38),
          ),
          const SizedBox(height: 6),
          Text(
            '¿Qué camino de la Ciudad de México quieres recorrer hoy?',
            style: OhtliUi.body(size: isMobile ? 14 : 15.5),
          ),
        ],
      ),
    );
  }

  Widget _buildPinnedDots() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(_featured.length, (i) {
        final active = i == _pinnedPage;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          margin: const EdgeInsets.symmetric(horizontal: 3),
          width: active ? 18 : 6,
          height: 6,
          decoration: BoxDecoration(
            color: active ? OhtliColors.stormyTeal : OhtliColors.onyx.withValues(alpha: 0.15),
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
    required String eyebrow,
    required String title,
    IconData? icon,
    String? subtitle,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    return Padding(
      padding: EdgeInsets.fromLTRB(gutter, 0, gutter, 16),
      child: OhtliSectionHeader(
        eyebrow: eyebrow,
        icon: icon,
        title: title,
        subtitle: subtitle,
        trailing: actionLabel != null && onAction != null
            ? TextButton.icon(
                onPressed: onAction,
                iconAlignment: IconAlignment.end,
                icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                label: Text(actionLabel),
                style: TextButton.styleFrom(
                  foregroundColor: OhtliColors.accentText,
                  backgroundColor: OhtliColors.stormyTeal.withValues(alpha: 0.10),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                  shape: const StadiumBorder(),
                  textStyle: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700),
                ),
              )
            : null,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Lugares
  // ---------------------------------------------------------------------------

  Widget _buildPlacesRow(bool isMobile, double gutter) {
    final double cardWidth = isMobile ? 240 : 268;
    final double cardHeight = isMobile ? 330 : 344;

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
        final signedIn = FirebaseAuth.instance.currentUser != null;
        return ValueListenableBuilder<List<String>>(
          valueListenable: SavedPlaces.ids,
          builder: (context, savedIds, _) => SizedBox(
            height: cardHeight + 16,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.symmetric(horizontal: gutter, vertical: 6),
              itemCount: places.length,
              separatorBuilder: (_, _) => const SizedBox(width: 16),
              itemBuilder: (context, index) {
                final poi = places[index];
                return PoiCard(
                  poi: poi,
                  width: cardWidth,
                  height: cardHeight,
                  variant: PoiCardVariant.standard,
                  isSaved: savedIds.contains(poi.poiId),
                  onToggleSave: signedIn ? () => SavedPlaces.toggle(poi.poiId) : null,
                  onTap: () => PoiDetailDialog.show(context, poi),
                  // Sin cuenta, Explorar no se muestra; con cuenta abre el planificador desde aquí
                  onCreateRoute: signedIn ? () => TripPlannerDialog.show(context, initialOriginPoi: poi) : null,
                );
              },
            ),
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Crónicas de la comunidad
  // ---------------------------------------------------------------------------

  Widget _buildCommunityRow(bool isMobile, double gutter) {
    final double cardWidth = isMobile ? 230 : 260;
    final double cardHeight = isMobile ? 260 : 280;

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
          height: cardHeight + 16,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(horizontal: gutter, vertical: 6),
            itemCount: trips.length,
            separatorBuilder: (_, _) => const SizedBox(width: 16),
            itemBuilder: (context, index) {
              final trip = trips[index];
              return FutureBuilder<DocumentSnapshot>(
                future: _authorFuture(trip.authorId),
                builder: (context, authorSnap) {
                  final authorData = (authorSnap.data?.exists ?? false)
                      ? authorSnap.data!.data() as Map<String, dynamic>?
                      : null;
                  final authorName = (authorData?['displayName'] ?? 'Viajero Ohtli').toString();
                  return _CommunityPolaroid(
                    width: cardWidth,
                    height: cardHeight,
                    coverUrl: trip.coverUrl,
                    title: trip.title,
                    authorName: authorName,
                    authorPhoto: authorData?['photoURL'] as String?,
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
            color: OhtliColors.cardBg.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(28),
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
      child: OhtliEmptyState(
        icon: icon,
        title: message,
        message: actionLabel == 'Reintentar'
            ? 'Revisa tu conexión e inténtalo de nuevo.'
            : (actionLabel != null ? 'Publica un viaje desde Mis viajes y aparecerá aquí para toda la comunidad.' : 'Vuelve más tarde: esto se actualiza todos los días.'),
        action: actionLabel != null && onAction != null
            ? OhtliSecondaryButton(label: actionLabel, icon: Icons.arrow_forward_rounded, onPressed: onAction)
            : null,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Crónicas destacadas (carrusel)
  // ---------------------------------------------------------------------------

  Widget _buildPinnedStoriesCarousel(bool isMobile, bool isDark) {
    final double height = isMobile ? 420.0 : 340.0;

    return SizedBox(
      height: height,
      width: double.infinity,
      child: PageView.builder(
        controller: _pinnedController,
        itemCount: _featured.length,
        onPageChanged: (page) => setState(() => _pinnedPage = page),
        itemBuilder: (context, index) {
          final pinned = _featured[index];
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
              horizontal: isMobile ? 16.0 : 40.0,
              vertical: isMobile ? 12.0 : 16.0,
            ),
            decoration: BoxDecoration(
              color: OhtliColors.cardBg,
              borderRadius: BorderRadius.circular(28),
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
        final String desc = tripData?['description'] ?? 'Sin descripción.';
        final bool isReleaseNotes = tripData?['kind'] == 'release_notes';
        final String? version = tripData?['version']?.toString();
        final String badgeText = isReleaseNotes
            ? 'NOVEDADES DE OHTLI${version != null && version.isNotEmpty ? ' · V$version' : ''}'
            : 'CRÓNICA DESTACADA';
        
        final String authorName = authorData?['displayName'] ?? 'Viajero Ohtli';
        final String? authorPhoto = authorData?['photoURL'];
        final String activeTitleId = authorData?['activeTitleId'] ?? 'viajero';

        final trip = Trip.fromMap({...?tripData, 'userId': pinned.authorId}, pinned.tripId);
        final accent = isReleaseNotes ? OhtliColors.stormyTeal : OhtliColors.xoconostle;

        void open() {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => TripViewerPage(tripId: pinned.tripId, authorId: pinned.authorId)),
          );
        }

        final avatar = Container(
          width: 34,
          height: 34,
          decoration: const BoxDecoration(shape: BoxShape.circle, color: OhtliColors.stormyTeal),
          child: ClipOval(
            child: authorPhoto != null && authorPhoto.isNotEmpty
                ? Image(
                    image: _getImageProvider(authorPhoto),
                    fit: BoxFit.cover,
                    errorBuilder: (c, e, s) => Center(
                      child: Text(authorName.substring(0, 1).toUpperCase(),
                          style: GoogleFonts.inter(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                    ),
                  )
                : Center(
                    child: Text(authorName.substring(0, 1).toUpperCase(),
                        style: GoogleFonts.inter(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
          ),
        );

        bool isHovered = false;
        return StatefulBuilder(
          builder: (context, setState) {
            final text = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(color: accent.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(30)),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(isReleaseNotes ? Icons.new_releases_rounded : Icons.auto_stories_rounded, color: accent, size: 13),
                      const SizedBox(width: 6),
                      Text(badgeText, style: GoogleFonts.inter(color: accent, fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
                    ],
                  ),
                ),
                SizedBox(height: isMobile ? 12 : 18),
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.outfit(
                    color: OhtliColors.onyx,
                    fontSize: isMobile ? 24 : 34,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.8,
                    height: 1.05,
                  ),
                ),
                const SizedBox(height: 10),
                Text(desc, maxLines: isMobile ? 2 : 3, overflow: TextOverflow.ellipsis, style: OhtliUi.body(size: isMobile ? 14 : 15.5)),
                SizedBox(height: isMobile ? 14 : 22),
                Row(
                  children: [
                    avatar,
                    const SizedBox(width: 10),
                    Flexible(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(authorName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.outfit(color: OhtliColors.onyx, fontSize: 14, fontWeight: FontWeight.w700)),
                          StreamBuilder<DocumentSnapshot>(
                            stream: FirebaseFirestore.instance.collection('titles').doc(activeTitleId).snapshots(),
                            builder: (context, titleSnapshot) {
                              String titleName = 'Viajero';
                              if (titleSnapshot.hasData && titleSnapshot.data!.exists) {
                                final titleData = titleSnapshot.data!.data() as Map<String, dynamic>?;
                                titleName = titleData?['name'] ?? 'Viajero';
                              }
                              return Text(titleName, style: OhtliUi.body(size: 12));
                            },
                          ),
                        ],
                      ),
                    ),
                    if (!isMobile) ...[
                      const SizedBox(width: 16),
                      OhtliPrimaryButton(
                        label: isReleaseNotes ? 'Ver novedades' : 'Leer historia',
                        icon: Icons.arrow_forward_rounded,
                        highlight: !isReleaseNotes,
                        onPressed: open,
                      ),
                    ],
                  ],
                ),
              ],
            );

            final desk = ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: AnimatedScale(
                duration: const Duration(milliseconds: 500),
                curve: Curves.easeOutCubic,
                scale: isHovered ? 1.04 : 1.0,
                child: SizedBox.expand(child: OhtliPhoto(TripPhotos.initial(trip).photos.first)),
              ),
            );

            return MouseRegion(
              onEnter: (_) => setState(() => isHovered = true),
              onExit: (_) => setState(() => isHovered = false),
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: open,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOutCubic,
                  margin: EdgeInsets.symmetric(horizontal: isMobile ? 16.0 : 40.0, vertical: isMobile ? 12.0 : 16.0),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: OhtliColors.cardBg,
                    borderRadius: BorderRadius.circular(32),
                    border: Border.all(color: isHovered ? accent.withValues(alpha: 0.35) : OhtliColors.cardBorder),
                    boxShadow: OhtliUi.softShadow(color: isHovered ? accent : null, raised: isHovered),
                  ),
                  child: isMobile
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: desk),
                            Padding(padding: const EdgeInsets.fromLTRB(10, 16, 10, 8), child: text),
                          ],
                        )
                      : Row(
                          children: [
                            Expanded(flex: 5, child: Padding(padding: const EdgeInsets.fromLTRB(30, 20, 24, 20), child: text)),
                            Expanded(flex: 6, child: desk),
                          ],
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
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final a = widget.action;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: a.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
          height: 96,
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          transform: Matrix4.translationValues(0, _hover ? -3 : 0, 0),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [a.color.withValues(alpha: _hover ? 0.20 : 0.13), OhtliColors.cardBg],
            ),
            border: Border.all(color: _hover ? a.color.withValues(alpha: 0.45) : a.color.withValues(alpha: 0.16)),
            boxShadow: OhtliUi.softShadow(color: _hover ? a.color : null, raised: _hover),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  OhtliServiceIcon(icon: a.icon, color: a.color, size: 34),
                  const Spacer(),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 240),
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(color: _hover ? a.color : Colors.white.withValues(alpha: 0.8), shape: BoxShape.circle),
                    child: Icon(Icons.arrow_outward_rounded, size: 16, color: _hover ? Colors.white : a.color),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(a.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.outfit(fontSize: 16.5, fontWeight: FontWeight.w800, color: OhtliColors.onyx, letterSpacing: -0.2)),
                  Text(a.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: OhtliUi.body(size: 12.5)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Crónica de la comunidad como polaroid sobre la mesa.
class _CommunityPolaroid extends StatefulWidget {
  final double width;
  final double height;
  final String coverUrl;
  final String title;
  final String authorName;
  final String? authorPhoto;
  final VoidCallback onTap;

  const _CommunityPolaroid({
    required this.width,
    required this.height,
    required this.coverUrl,
    required this.title,
    required this.authorName,
    this.authorPhoto,
    required this.onTap,
  });

  @override
  State<_CommunityPolaroid> createState() => _CommunityPolaroidState();
}

class _CommunityPolaroidState extends State<_CommunityPolaroid> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final photo = widget.authorPhoto;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
          width: widget.width,
          height: widget.height,
          padding: const EdgeInsets.all(6),
          transform: Matrix4.translationValues(0, _hover ? -4 : 0, 0),
          decoration: BoxDecoration(
            color: OhtliColors.cardBg,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: _hover ? OhtliColors.stormyTeal.withValues(alpha: 0.35) : OhtliColors.cardBorder),
            boxShadow: OhtliUi.softShadow(color: _hover ? OhtliColors.stormyTeal : null, raised: _hover),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: AnimatedScale(
                    duration: const Duration(milliseconds: 400),
                    curve: Curves.easeOutCubic,
                    scale: _hover ? 1.05 : 1.0,
                    child: SizedBox.expand(child: OhtliPhoto(widget.coverUrl)),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 10, 8, 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.outfit(fontSize: 17, fontWeight: FontWeight.w800, color: OhtliColors.onyx, letterSpacing: -0.2)),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 10,
                          backgroundColor: OhtliColors.stormyTeal.withValues(alpha: 0.4),
                          backgroundImage: photo != null && photo.isNotEmpty && !photo.startsWith('data:') ? NetworkImage(photo) : null,
                          child: photo != null && photo.isNotEmpty && !photo.startsWith('data:')
                              ? null
                              : Text(widget.authorName.isNotEmpty ? widget.authorName[0].toUpperCase() : '?',
                                  style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.w800, color: Colors.white)),
                        ),
                        const SizedBox(width: 7),
                        Expanded(
                          child: Text('por ${widget.authorName}', maxLines: 1, overflow: TextOverflow.ellipsis, style: OhtliUi.body(size: 12.5)),
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
            borderRadius: BorderRadius.circular(28),
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
            borderRadius: BorderRadius.circular(28),
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
                  top: 14,
                  left: 14,
                  right: 14,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.38),
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.18), width: 0.8),
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
                  left: 18,
                  right: 18,
                  bottom: 18,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.outfit(
                          color: Colors.white,
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                          height: 1.15,
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

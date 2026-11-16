// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:web/web.dart' as web;
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme/colors.dart';
import '../models/poi_model.dart';
import '../utils/friendly_errors.dart';
import '../services/saved_places.dart';
import '../services/feedback_service.dart';
import 'osrm_map_widget.dart';
import 'ohtli_ui.dart';
import 'poi_status_badge.dart';
import '../screens/places/places_page.dart';
import '../screens/trips/trip_screens.dart' deferred as trips;
import 'deferred_view.dart';
import 'trip_planner_dialog.dart';

class PoiDetailDialog extends StatefulWidget {
  final Poi poi;
  final bool isSaved;
  final ValueChanged<bool>? onSaveToggle;
  final VoidCallback? onCreateRoute;
  final bool asSheet;

  /// Dónde se abrió (retroalimentación): affinity, itinerary, catalog, trip, detail…
  final String surface;

  const PoiDetailDialog({
    super.key,
    required this.poi,
    this.isSaved = false,
    this.onSaveToggle,
    this.onCreateRoute,
    this.asSheet = false,
    this.surface = 'other',
  });

  static void show(
    BuildContext context,
    Poi poi, {
    bool isSaved = false,
    ValueChanged<bool>? onSaveToggle,
    VoidCallback? onCreateRoute,
    String surface = 'other',
    int? position,
  }) {
    FeedbackService.opened(poi.poiId, surface: surface, position: position);
    // En móvil se abre como hoja inferior (más natural con el pulgar); en escritorio, como diálogo
    if (ohtliIsMobileWidth(MediaQuery.of(context).size.width)) {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: false,
        backgroundColor: Colors.transparent,
        builder: (context) => FractionallySizedBox(
          heightFactor: 0.94,
          child: PoiDetailDialog(
            poi: poi,
            isSaved: isSaved,
            onSaveToggle: onSaveToggle,
            onCreateRoute: onCreateRoute,
            asSheet: true,
            surface: surface,
          ),
        ),
      );
      return;
    }
    showDialog(
      context: context,
      builder: (context) => PoiDetailDialog(
        poi: poi,
        isSaved: isSaved,
        onSaveToggle: onSaveToggle,
        onCreateRoute: onCreateRoute,
        surface: surface,
      ),
    );
  }

  @override
  State<PoiDetailDialog> createState() => _PoiDetailDialogState();
}

class _PoiDetailDialogState extends State<PoiDetailDialog> {
  late bool _isSaved;
  List<Map<String, dynamic>> _matchingPublicTrips = [];
  bool _isLoadingTrips = true;

  final Stopwatch _dwell = Stopwatch()..start();

  @override
  void initState() {
    super.initState();
    FeedbackService.ensureStarted();
    _isSaved = widget.isSaved;
    _checkSavedStatus();
    _findMatchingPublicTrips();
    _findNearby();
  }

  void _checkSavedStatus() {
    SavedPlaces.ensureStarted();
    if (SavedPlaces.contains(widget.poi.poiId)) _isSaved = true;
  }

  void _toggleSave() {
    // Guardar lugares es solo para cuentas registradas
    if (FirebaseAuth.instance.currentUser == null) return;
    setState(() => _isSaved = !_isSaved);
    final wanted = _isSaved;
    SavedPlaces.setSaved(widget.poi.poiId, wanted).catchError((_) {
      if (mounted) {
        setState(() => _isSaved = !wanted);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo guardar el lugar. Revisa tu conexión.')),
        );
      }
      return !wanted;
    });
    widget.onSaveToggle?.call(_isSaved);
    FeedbackService.saved(widget.poi.poiId, _isSaved, surface: widget.surface);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _isSaved ? 'Guardado en "Mis lugares"' : 'Eliminado de "Mis lugares"',
          style: GoogleFonts.inter(color: Colors.white),
        ),
        backgroundColor: _isSaved ? OhtliColors.stormyTeal : OhtliColors.xoconostle,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  /// Busca viajes públicos que incluyan este lugar en su título o descripción
  Future<void> _findMatchingPublicTrips() async {
    try {
      final nameLower = widget.poi.name.trim().toLowerCase();
      final words = nameLower.split(' ').where((w) => w.length > 3).take(3).toList();

      final snapshot = await FirebaseFirestore.instance
          .collectionGroup('trips')
          .where('status', isEqualTo: 'published')
          .where('visibility', isEqualTo: 'public')
          .limit(15)
          .get()
          .timeout(const Duration(seconds: 8));

      final List<Map<String, dynamic>> results = [];
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final title = (data['title'] ?? '').toString().toLowerCase();
        final desc = (data['description'] ?? '').toString().toLowerCase();

        bool matches = title.contains(nameLower) || desc.contains(nameLower);
        if (!matches && words.isNotEmpty) {
          matches = words.any((w) => title.contains(w) || desc.contains(w));
        }

        if (matches) {
          results.add({
            'tripId': doc.id,
            'authorId': data['userId'] ?? '',
            'title': data['title'] ?? 'Viaje sin título',
            'coverUrl': data['coverUrl'] ?? '',
            'description': data['description'] ?? '',
          });
        }
      }

      if (mounted) {
        setState(() {
          _matchingPublicTrips = results;
          _isLoadingTrips = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoadingTrips = false);
      }
    }
  }

  void _openInMaps() {
    final poi = widget.poi;
    FeedbackService.directions(poi.poiId, surface: widget.surface);
    final query = Uri.encodeComponent('${poi.name} (${poi.location.lat},${poi.location.lng})');
    final url = 'https://www.google.com/maps/search/?api=1&query=$query';
    if (kIsWeb) {
      web.window.open(url, '_blank');
    }
  }

  /// Crea una ruta / viaje directamente iniciando con este lugar
  Future<void> _createRouteFromThisPlace() async {
    if (widget.onCreateRoute != null) {
      Navigator.of(context).pop();
      widget.onCreateRoute!();
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Inicia sesión para crear y guardar rutas personalizadas.',
            style: GoogleFonts.inter(color: Colors.white),
          ),
          backgroundColor: OhtliColors.stormyTeal,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
      return;
    }

    // Todo plan sale del asistente: empieza con este lugar como punto de partida.
    final nav = Navigator.of(context);
    nav.pop();
    await TripPlannerDialog.show(nav.context, initialOriginPoi: widget.poi);
  }

  bool _isNarrativeExpanded = false;
  final PageController _gallery = PageController();
  int _photoIndex = 0;
  List<(Poi, double)> _nearby = const [];

  @override
  void dispose() {
    FeedbackService.dwell(widget.poi.poiId, _dwell.elapsed, surface: widget.surface);
    _gallery.dispose();
    super.dispose();
  }

  /// Fotos reales del lugar; si no hay, la foto de referencia de su categoría.
  List<String> get _photos {
    final out = <String>[];
    for (final u in [widget.poi.imageUrl, ...widget.poi.photos]) {
      if (u.isNotEmpty && !out.contains(u)) out.add(u);
    }
    return out.take(6).toList();
  }

  /// Lugares del catálogo a menos de 1.5 km, del más cercano al más lejano.
  /// Radio de "a unos pasos": ~10 minutos caminando.
  static const double _nearbyRadius = 800;
  static const String _apiUrl = String.fromEnvironment('yollotlApiUrl', defaultValue: 'https://api.ohtli.quest');

  Future<void> _findNearby() async {
    final poi = widget.poi;
    if (!poi.location.isValid) return;
    var list = await _nearbyFromEngine(poi);
    // Respaldo: la selección del catálogo que ya tiene la app (menos lugares)
    list ??= await _nearbyFromLocalCatalog(poi);
    if (mounted && list.isNotEmpty) setState(() => _nearby = list!.take(10).toList());
  }

  /// Cercanos sobre TODO el catálogo del motor (la app solo descarga una selección).
  Future<List<(Poi, double)>?> _nearbyFromEngine(Poi poi) async {
    try {
      final uri = Uri.parse('$_apiUrl/v1/pois').replace(queryParameters: {
        'near': '${poi.location.lat},${poi.location.lng}',
        'radius': _nearbyRadius.toInt().toString(),
        'limit': '14',
      });
      final res = await http.get(uri).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return null;
      final decoded = jsonDecode(res.body);
      if (decoded is! Map || decoded['pois'] is! List) return null;
      final list = <(Poi, double)>[];
      for (final raw in decoded['pois'] as List) {
        if (raw is! Map) continue;
        final p = Poi.fromMap(Map<String, dynamic>.from(raw));
        if (p.poiId == poi.poiId || !p.location.isValid || !p.isValidCulturalPlace) continue;
        final d = (raw['distance_m'] as num?)?.toDouble() ??
            _distanceMeters(poi.location.lat, poi.location.lng, p.location.lat, p.location.lng);
        if (d <= _nearbyRadius) list.add((p, d));
      }
      list.sort((a, b) => a.$2.compareTo(b.$2));
      return list;
    } catch (_) {
      return null;
    }
  }

  Future<List<(Poi, double)>> _nearbyFromLocalCatalog(Poi poi) async {
    try {
      final all = await PlacesPage.loadCatalog();
      final list = <(Poi, double)>[];
      for (final p in all) {
        if (p.poiId == poi.poiId || !p.location.isValid) continue;
        final d = _distanceMeters(poi.location.lat, poi.location.lng, p.location.lat, p.location.lng);
        if (d <= _nearbyRadius) list.add((p, d));
      }
      list.sort((a, b) => a.$2.compareTo(b.$2));
      return list;
    } catch (_) {
      return const [];
    }
  }

  static double _distanceMeters(double lat1, double lng1, double lat2, double lng2) {
    const r = 6371000.0;
    double rad(double d) => d * math.pi / 180;
    final dLat = rad(lat2 - lat1), dLng = rad(lng2 - lng1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(rad(lat1)) * math.cos(rad(lat2)) * math.sin(dLng / 2) * math.sin(dLng / 2);
    return 2 * r * math.asin(math.min(1, math.sqrt(a)));
  }

  static String _distanceLabel(double m) {
    final walk = (m / 80).ceil();
    final dist = m < 1000 ? '${(m / 10).round() * 10} m' : '${(m / 1000).toStringAsFixed(1)} km';
    return '$dist · $walk min a pie';
  }

  void _openNearby(Poi p) {
    final nav = Navigator.of(context);
    final parent = nav.context;
    nav.pop();
    PoiDetailDialog.show(parent, p, onCreateRoute: widget.onCreateRoute, surface: 'detail');
  }

  Future<void> _share() async {
    final poi = widget.poi;
    FeedbackService.shared(poi.poiId, surface: widget.surface);
    final address = poi.address.trim().isNotEmpty ? poi.address.trim() : poi.coloniaAlcaldiaDisplay;
    final maps = 'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent('${poi.name} (${poi.location.lat},${poi.location.lng})')}';
    await Clipboard.setData(ClipboardData(text: '${poi.name}\n$address\n$maps'));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Copiamos el nombre, la dirección y el mapa del lugar.', style: GoogleFonts.inter(color: Colors.white)),
        backgroundColor: OhtliColors.stormyTeal,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isMobile = ohtliIsMobileWidth(screenSize.width);

    if (widget.asSheet || isMobile) {
      final body = _buildSingleColumn(context);
      if (widget.asSheet) {
        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          child: Material(color: OhtliColors.cardBg, child: body),
        );
      }
      return Dialog(
        backgroundColor: OhtliColors.cardBg,
        clipBehavior: Clip.antiAlias,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(OhtliUi.radiusLarge)),
        child: body,
      );
    }

    final asideWidth = screenSize.width > 1200 ? 380.0 : 340.0;
    return Dialog(
      backgroundColor: OhtliColors.cardBg,
      clipBehavior: Clip.antiAlias,
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 32),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(OhtliUi.radiusLarge),
        side: BorderSide(color: OhtliColors.cardBorder),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 1120, maxHeight: math.min(screenSize.height * 0.9, 860)),
        child: Stack(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: CustomScrollView(
                    physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                    slivers: [
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(OhtliUi.radiusCard),
                            child: SizedBox(height: 380, child: _buildHero(isMobile: false)),
                          ),
                        ),
                      ),
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(32, 26, 32, 32),
                        sliver: SliverList(delegate: SliverChildListDelegate(_buildBody(isMobile: false))),
                      ),
                    ],
                  ),
                ),
                SizedBox(width: asideWidth, child: _buildAside()),
              ],
            ),
            Positioned(
              top: 24,
              right: 24,
              child: _buildRoundIcon(
                icon: Icons.close_rounded,
                tooltip: 'Cerrar',
                onTap: () => Navigator.of(context).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------- Móvil: una sola columna ----------
  Widget _buildSingleColumn(BuildContext context) {
    final poi = widget.poi;
    return Column(
      children: [
        Expanded(
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
            slivers: [
              SliverLayoutBuilder(
                builder: (context, constraints) {
                  const heroHeight = 300.0;
                  final collapsed = constraints.scrollOffset > heroHeight - kToolbarHeight - 20;
                  return SliverAppBar(
                    pinned: true,
                    expandedHeight: heroHeight,
                    automaticallyImplyLeading: false,
                    elevation: 0,
                    scrolledUnderElevation: 0,
                    backgroundColor: OhtliColors.cardBg,
                    surfaceTintColor: Colors.transparent,
                    titleSpacing: 20,
                    title: AnimatedOpacity(
                      opacity: collapsed ? 1 : 0,
                      duration: const Duration(milliseconds: 180),
                      child: Text(poi.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.outfit(fontSize: 17, fontWeight: FontWeight.w800, color: OhtliColors.onyx)),
                    ),
                    actions: [
                      _buildRoundIcon(
                        icon: Icons.close_rounded,
                        tooltip: 'Cerrar',
                        onTap: () => Navigator.of(context).pop(),
                        onImage: !collapsed,
                      ),
                      const SizedBox(width: 14),
                    ],
                    flexibleSpace: FlexibleSpaceBar(
                      collapseMode: CollapseMode.parallax,
                      background: _buildHero(isMobile: true),
                    ),
                  );
                },
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
                sliver: SliverList(delegate: SliverChildListDelegate(_buildBody(isMobile: true))),
              ),
            ],
          ),
        ),
        _buildMobileActionBar(),
      ],
    );
  }

  // ---------- Portada con galería ----------
  Widget _buildHero({required bool isMobile}) {
    final poi = widget.poi;
    final photos = _photos;
    return Stack(
      fit: StackFit.expand,
      children: [
        PageView.builder(
          controller: _gallery,
          itemCount: photos.length,
          onPageChanged: (i) => setState(() => _photoIndex = i),
          itemBuilder: (_, i) => _buildPhoto(photos[i]),
        ),
        IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.black.withValues(alpha: 0.30), Colors.transparent, Colors.black.withValues(alpha: 0.82)],
                stops: const [0.0, 0.35, 1.0],
              ),
            ),
          ),
        ),
        // Sin foto propia se muestra una de otro lugar de la ciudad: decirlo para no confundir
        if (!poi.hasOwnPhoto && _photoIndex == 0)
          Positioned(
            top: 14,
            left: 14,
            child: IgnorePointer(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Foto de referencia',
                  style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white),
                ),
              ),
            ),
          ),
        if (photos.length > 1 && !isMobile) ...[
          Positioned(
            left: 14,
            top: 0,
            bottom: 0,
            child: Center(
              child: _buildRoundIcon(
                icon: Icons.chevron_left_rounded,
                tooltip: 'Foto anterior',
                onTap: () => _gallery.animateToPage((_photoIndex - 1) % photos.length,
                    duration: const Duration(milliseconds: 320), curve: Curves.easeOutCubic),
              ),
            ),
          ),
          Positioned(
            right: 14,
            top: 0,
            bottom: 0,
            child: Center(
              child: _buildRoundIcon(
                icon: Icons.chevron_right_rounded,
                tooltip: 'Foto siguiente',
                onTap: () => _gallery.animateToPage((_photoIndex + 1) % photos.length,
                    duration: const Duration(milliseconds: 320), curve: Curves.easeOutCubic),
              ),
            ),
          ),
        ],
        Positioned(
          left: isMobile ? 20 : 26,
          right: isMobile ? 20 : 26,
          bottom: isMobile ? 20 : 24,
          child: IgnorePointer(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(color: poi.categoryColor, borderRadius: BorderRadius.circular(30)),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(poi.categoryIcon, size: 13, color: Colors.white),
                          const SizedBox(width: 5),
                          Text(poi.categoryDisplay.toUpperCase(),
                              style: GoogleFonts.inter(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 0.8)),
                        ],
                      ),
                    ),
                    if (poi.isClosedTemporarily) ...[
                      const SizedBox(width: 8),
                      const Flexible(child: PoiClosedBadge()),
                    ],
                    const Spacer(),
                    if (photos.length > 1)
                      Row(
                        children: [
                          for (var i = 0; i < photos.length; i++)
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 220),
                              margin: const EdgeInsets.only(left: 5),
                              width: i == _photoIndex ? 18 : 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: i == _photoIndex ? 0.95 : 0.5),
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                        ],
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  poi.name,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.outfit(
                    fontSize: isMobile ? 27 : 36,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    height: 1.05,
                    letterSpacing: -0.6,
                    shadows: [Shadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 12)],
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.location_on_rounded, size: 15, color: Colors.white70),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(poi.coloniaAlcaldiaDisplay,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(fontSize: 13.5, color: Colors.white.withValues(alpha: 0.88), fontWeight: FontWeight.w500)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPhoto(String url) {
    final poi = widget.poi;
    final placeholder = Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [poi.categoryColor.withValues(alpha: 0.55), poi.categoryColor.withValues(alpha: 0.25)],
        ),
      ),
      child: Center(child: Icon(poi.categoryIcon, size: 56, color: Colors.white.withValues(alpha: 0.7))),
    );
    return Stack(
      fit: StackFit.expand,
      children: [
        placeholder,
        Image.network(
          url,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          frameBuilder: (context, child, frame, sync) {
            if (sync) return child;
            return AnimatedOpacity(
              opacity: frame == null ? 0 : 1,
              duration: const Duration(milliseconds: 350),
              curve: Curves.easeOut,
              child: child,
            );
          },
          errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
        ),
      ],
    );
  }

  Widget _buildRoundIcon({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
    bool onImage = true,
  }) {
    final Color fg = onImage ? Colors.white : OhtliColors.onyx;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: onImage ? Colors.black.withValues(alpha: 0.42) : OhtliColors.innerCardBg,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(width: 38, height: 38, child: Icon(icon, size: 20, color: fg)),
        ),
      ),
    );
  }

  // ---------- Contenido ----------
  List<Widget> _buildBody({required bool isMobile}) {
    final poi = widget.poi;
    final bool isLabsUrl = kIsWeb && web.window.location.hostname.contains('labs');
    final highlights = _highlightPills(poi);
    final vibes = poi.vibeTags.map((v) => v.startsWith('#') ? v.substring(1) : v).where((v) => v.trim().isNotEmpty).toList();
    final reviews = poi.reviewsSnippets.where((r) => r.trim().length > 12).take(6).toList();
    return [
      if (poi.isClosedTemporarily) ...[
        const PoiClosedNotice(),
        const SizedBox(height: 14),
      ],
      _buildQuickFacts(poi, isMobile),
      const SizedBox(height: 30),
      _buildTitle('SOBRE ESTE LUGAR', 'La historia en corto', Icons.auto_stories_rounded, OhtliColors.stormyTeal),
      const SizedBox(height: 12),
      _buildNarrative(poi),
      if (highlights.isNotEmpty) ...[
        const SizedBox(height: 30),
        _buildTitle('ANTES DE IR', 'Lo que debes saber', Icons.tips_and_updates_rounded, OhtliColors.cempasuchil),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: highlights),
      ],
      if (vibes.isNotEmpty) ...[
        const SizedBox(height: 30),
        _buildTitle('AMBIENTE', 'Cómo se siente', Icons.mood_rounded, const Color(0xFF8E24AA)),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: vibes.map(_buildVibeChip).toList()),
      ],
      if (reviews.isNotEmpty) ...[
        const SizedBox(height: 30),
        _buildTitle('RESEÑAS', 'Lo que dicen quienes han ido', Icons.format_quote_rounded, OhtliColors.xoconostle),
        const SizedBox(height: 12),
        SizedBox(
          height: 150,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: reviews.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (_, i) => _buildReviewCard(reviews[i]),
          ),
        ),
      ],
      if (isMobile && poi.location.isValid) ...[
        const SizedBox(height: 30),
        _buildTitle('UBICACIÓN', 'Cómo llegar', Icons.place_rounded, OhtliColors.stormyTeal),
        const SizedBox(height: 12),
        _buildAddressCard(),
        const SizedBox(height: 12),
        ClipRRect(borderRadius: BorderRadius.circular(20), child: _buildMap(height: 200)),
        const SizedBox(height: 12),
        OhtliSecondaryButton(label: 'Abrir en Google Maps', icon: Icons.directions_rounded, onPressed: _openInMaps),
      ],
      if (_nearby.isNotEmpty) ...[
        const SizedBox(height: 30),
        _buildTitle('A UNOS PASOS', 'Cerca de aquí', Icons.near_me_rounded, OhtliColors.stormyTeal),
        const SizedBox(height: 12),
        SizedBox(
          height: 196,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _nearby.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (_, i) => _buildNearbyCard(_nearby[i].$1, _nearby[i].$2),
          ),
        ),
      ],
      if (FirebaseAuth.instance.currentUser != null) ...[
        const SizedBox(height: 30),
        _buildFeedbackRow(),
      ],
      const SizedBox(height: 30),
      _buildTripsSection(),
      if (isLabsUrl) ...[
        const SizedBox(height: 24),
        _buildLabsMetadata(poi),
      ],
    ];
  }

  Widget _buildTitle(String eyebrow, String title, IconData icon, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 6),
            Text(eyebrow, style: OhtliUi.eyebrow(color)),
          ],
        ),
        const SizedBox(height: 4),
        Text(title, style: OhtliUi.title(size: 21)),
      ],
    );
  }

  static const Map<String, String> _cuisineNames = {
    'mexican': 'Mexicana', 'tacos': 'Tacos', 'taco': 'Tacos', 'regional': 'Regional', 'seafood': 'Mariscos',
    'italian': 'Italiana', 'pizza': 'Pizza', 'japanese': 'Japonesa', 'sushi': 'Sushi', 'chinese': 'China',
    'spanish': 'Española', 'french': 'Francesa', 'american': 'Americana', 'burger': 'Hamburguesas',
    'coffee_shop': 'Café', 'coffee': 'Café', 'cake': 'Repostería', 'bakery': 'Panadería', 'ice_cream': 'Helados',
    'vegetarian': 'Vegetariana', 'vegan': 'Vegana', 'international': 'Internacional', 'chicken': 'Pollo',
    'sandwich': 'Sándwiches', 'steak_house': 'Cortes', 'argentinian': 'Argentina', 'korean': 'Coreana',
    'thai': 'Tailandesa', 'indian': 'India', 'peruvian': 'Peruana', 'lebanese': 'Libanesa', 'breakfast': 'Desayunos',
  };

  String get _cuisineDisplay {
    final parts = widget.poi.cuisine
        .split(RegExp(r'[;,]'))
        .map((c) => c.trim().toLowerCase())
        .where((c) => c.isNotEmpty)
        .map((c) => _cuisineNames[c] ?? (c[0].toUpperCase() + c.substring(1).replaceAll('_', ' ')))
        .toSet()
        .take(3);
    return parts.join(' · ');
  }

  // Datos clave en tarjetas
  Widget _buildQuickFacts(Poi poi, bool isMobile) {
    final hasRealHours = poi.hasOpeningHours;
    final cuisine = _cuisineDisplay;
    final facts = [
      _QuickFact(Icons.payments_rounded, poi.priceIsEstimate ? 'Precio estimado' : 'Precio', poi.priceRangeEstimate.replaceAll(', estimado', ''), OhtliColors.stormyTeal),
      _QuickFact(Icons.schedule_rounded, hasRealHours ? 'Horario' : 'Horario aprox.', poi.openingHoursDisplay, OhtliColors.cempasuchil),
      if (cuisine.isNotEmpty) _QuickFact(Icons.restaurant_menu_rounded, 'Cocina', cuisine, OhtliColors.xoconostle),
    ];
    return LayoutBuilder(builder: (context, c) {
      // En teléfono, una columna: en dos, el precio y el horario se cortaban ('Costoso (~ $350 - $6…')
      final cols = c.maxWidth >= 640 ? facts.length : (c.maxWidth >= 440 ? 2 : 1);
      final w = (c.maxWidth - (cols - 1) * 10) / cols;
      return Wrap(
        spacing: 10,
        runSpacing: 10,
        children: facts.map((f) => SizedBox(width: w, child: _buildFactTile(f))).toList(),
      );
    });
  }

  Widget _buildFactTile(_QuickFact f) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: f.color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: f.color.withValues(alpha: 0.18)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: f.color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(12)),
            child: Icon(f.icon, size: 18, color: f.color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(f.label.toUpperCase(),
                    style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.9, color: OhtliColors.subtleText)),
                const SizedBox(height: 3),
                Text(f.value,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w700, color: OhtliColors.onyx, height: 1.3)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Descripción con "Leer más" cuando es larga
  Widget _buildNarrative(Poi poi) {
    final text = poi.cleanNarrative;
    final isLong = text.length > 360;
    final style = GoogleFonts.inter(fontSize: 15, height: 1.65, color: OhtliColors.onyx.withValues(alpha: 0.86));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AnimatedSize(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: Text(
            text,
            maxLines: (!isLong || _isNarrativeExpanded) ? null : 6,
            overflow: (!isLong || _isNarrativeExpanded) ? TextOverflow.visible : TextOverflow.ellipsis,
            style: style,
          ),
        ),
        if (isLong)
          TextButton.icon(
            onPressed: () => setState(() => _isNarrativeExpanded = !_isNarrativeExpanded),
            icon: Icon(_isNarrativeExpanded ? Icons.expand_less_rounded : Icons.expand_more_rounded, size: 18),
            label: Text(_isNarrativeExpanded ? 'Leer menos' : 'Leer más', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700)),
            style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 6), foregroundColor: OhtliColors.stormyTeal),
          ),
      ],
    );
  }

  // Solo características reales del lugar
  List<Widget> _highlightPills(Poi poi) => [
        if (poi.patrimonioHistorico) _buildFriendlyPill(Icons.account_balance_rounded, 'Patrimonio histórico', OhtliColors.xoconostle),
        if (poi.areaVerdeCercana) _buildFriendlyPill(Icons.park_rounded, 'Áreas verdes cerca', const Color(0xFF2E7D32)),
        if (poi.wheelchairAccessible) _buildFriendlyPill(Icons.accessible_rounded, 'Accesible en silla de ruedas', const Color(0xFF1E6FD9)),
        if (poi.coeficienteMovilidad > 0) _buildFriendlyPill(Icons.directions_bike_rounded, 'Cerca de Ecobici y ciclovías', OhtliColors.cempasuchil),
        if (poi.musicaEnVivo) _buildFriendlyPill(Icons.music_note_rounded, 'Música en vivo', const Color(0xFF8E24AA)),
        if (poi.consumoAlcohol) _buildFriendlyPill(Icons.local_bar_rounded, 'Bebidas y coctelería', const Color(0xFFD81B60)),
      ];

  Widget _buildVibeChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
      decoration: BoxDecoration(
        color: OhtliColors.innerCardBg,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: OhtliColors.cardBorder),
      ),
      child: Text('#$label', style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600, color: OhtliColors.onyx.withValues(alpha: 0.8))),
    );
  }

  Widget _buildReviewCard(String text) {
    return Container(
      width: 290,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: OhtliColors.innerCardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: OhtliColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.format_quote_rounded, size: 22, color: OhtliColors.xoconostle.withValues(alpha: 0.7)),
          const SizedBox(height: 4),
          Expanded(
            child: Text(text,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(fontSize: 13.5, height: 1.5, color: OhtliColors.onyx.withValues(alpha: 0.85), fontStyle: FontStyle.italic)),
          ),
          Text('Visitante', style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w700, color: OhtliColors.subtleText)),
        ],
      ),
    );
  }

  Widget _buildNearbyCard(Poi p, double meters) {
    return SizedBox(
      width: 210,
      child: Material(
        color: OhtliColors.innerCardBg,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _openNearby(p),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 112,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.network(p.imageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => Container(
                              color: p.categoryColor.withValues(alpha: 0.2),
                              child: Icon(p.categoryIcon, color: p.categoryColor),
                            )),
                    Positioned(
                      left: 8,
                      top: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.55), borderRadius: BorderRadius.circular(20)),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(p.categoryIcon, size: 11, color: Colors.white),
                            const SizedBox(width: 4),
                            Text(p.categoryDisplay, style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.w700, color: Colors.white)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                child: Text(p.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.outfit(fontSize: 14.5, fontWeight: FontWeight.w700, color: OhtliColors.onyx, height: 1.15)),
              ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                child: Row(
                  children: [
                    Icon(Icons.directions_walk_rounded, size: 13, color: OhtliColors.stormyTeal),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(_distanceLabel(meters),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w600, color: OhtliColors.subtleText)),
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

  // ---------- Panel lateral (escritorio) ----------
  Widget _buildAside() {
    final poi = widget.poi;
    return Container(
      decoration: BoxDecoration(
        color: OhtliColors.innerCardBg,
        border: Border(left: BorderSide(color: OhtliColors.cardBorder)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(OhtliUi.radiusCard),
                child: poi.location.isValid
                    ? LayoutBuilder(builder: (_, c) => _buildMap(height: c.maxHeight))
                    : Container(
                        color: OhtliColors.cardBg,
                        alignment: Alignment.center,
                        padding: const EdgeInsets.all(24),
                        child: Text('Este lugar todavía no tiene ubicación en el mapa.',
                            textAlign: TextAlign.center, style: OhtliUi.body(size: 13)),
                      ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildAddressCard(),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: OhtliSecondaryButton(label: 'Cómo llegar', icon: Icons.directions_rounded, onPressed: _openInMaps, compact: true)),
                    const SizedBox(width: 8),
                    Expanded(child: OhtliSecondaryButton(label: 'Compartir', icon: Icons.ios_share_rounded, onPressed: _share, compact: true)),
                  ],
                ),
                const SizedBox(height: 16),
                Divider(height: 1, color: OhtliColors.cardBorder),
                const SizedBox(height: 16),
                if (FirebaseAuth.instance.currentUser != null) ...[
                  _buildSaveButton(expand: true),
                  const SizedBox(height: 10),
                ],
                OhtliPrimaryButton(
                  label: 'Crear ruta desde aquí',
                  icon: Icons.alt_route_rounded,
                  onPressed: _createRouteFromThisPlace,
                  highlight: true,
                  expand: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMap({required double height}) {
    final poi = widget.poi;
    return OsrmMapWidget(
      stops: [
        {
          'name': poi.name,
          'lat': poi.location.lat,
          'lng': poi.location.lng,
          'category': poi.category,
        },
      ],
      height: height,
      isDark: OhtliSettings.instance.isDarkMode,
      compact: true,
    );
  }

  Widget _buildAddressCard() {
    final poi = widget.poi;
    final address = poi.address.trim().isNotEmpty ? poi.address.trim() : poi.coloniaAlcaldiaDisplay;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: OhtliColors.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: OhtliColors.cardBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(color: OhtliColors.stormyTeal.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(11)),
            child: const Icon(Icons.place_rounded, size: 18, color: OhtliColors.stormyTeal),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('DIRECCIÓN', style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.9, color: OhtliColors.subtleText)),
                const SizedBox(height: 2),
                Text(address,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: OhtliColors.onyx, height: 1.35)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSaveButton({bool expand = false, bool iconOnly = false}) {
    final icon = AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      transitionBuilder: (child, anim) => ScaleTransition(scale: anim, child: child),
      child: Icon(
        _isSaved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
        key: ValueKey(_isSaved),
        size: iconOnly ? 22 : 18,
        color: _isSaved ? OhtliColors.cempasuchil : OhtliColors.onyx,
      ),
    );
    final style = OutlinedButton.styleFrom(
      foregroundColor: OhtliColors.onyx,
      backgroundColor: OhtliColors.cardBg,
      padding: iconOnly ? EdgeInsets.zero : const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
      side: BorderSide(color: _isSaved ? OhtliColors.cempasuchil : OhtliColors.cardBorder),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      textStyle: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 14),
    );
    if (iconOnly) {
      return Tooltip(
        message: _isSaved ? 'Quitar de Mis lugares' : 'Guardar en Mis lugares',
        child: SizedBox(width: 52, height: 52, child: OutlinedButton(onPressed: _toggleSave, style: style, child: icon)),
      );
    }
    return OutlinedButton.icon(
      onPressed: _toggleSave,
      icon: icon,
      label: Text(_isSaved ? 'Guardado en Mis lugares' : 'Guardar en Mis lugares'),
      style: style,
    );
  }

  Widget _buildTripsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildTitle('COMUNIDAD', 'Viajes que pasan por aquí', Icons.route_rounded, OhtliColors.cempasuchil),
        const SizedBox(height: 12),
        if (_isLoadingTrips)
          SizedBox(
            height: 160,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: 3,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (_, _) => Container(
                width: 230,
                decoration: BoxDecoration(color: OhtliColors.innerCardBg, borderRadius: BorderRadius.circular(20)),
              ),
            ),
          )
        else if (_matchingPublicTrips.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: OhtliColors.innerCardBg,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: OhtliColors.cardBorder),
            ),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(color: OhtliColors.cempasuchil.withValues(alpha: 0.14), shape: BoxShape.circle),
                  child: const Icon(Icons.explore_rounded, size: 20, color: OhtliColors.cempasuchil),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Aún nadie ha publicado un viaje con este lugar. Puedes ser la primera persona en crear uno.',
                    style: GoogleFonts.inter(fontSize: 13, color: OhtliColors.subtleText, height: 1.45),
                  ),
                ),
              ],
            ),
          )
        else
          SizedBox(
            height: 160,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _matchingPublicTrips.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, i) => _buildTripCard(_matchingPublicTrips[i]),
            ),
          ),
      ],
    );
  }

  Widget _buildTripCard(Map<String, dynamic> tripData) {
    final cover = tripData['coverUrl'].toString();
    final fallback = Container(
      color: OhtliColors.stormyTeal.withValues(alpha: 0.12),
      child: const Icon(Icons.map_rounded, color: OhtliColors.stormyTeal),
    );
    return SizedBox(
      width: 230,
      child: Material(
        color: OhtliColors.innerCardBg,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => DeferredView(
                    load: trips.loadLibrary,
                    builder: (_) => trips.TripViewerPage(
                          tripId: tripData['tripId'],
                          authorId: tripData['authorId'],
                        )),
              ),
            );
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              cover.isNotEmpty ? Image.network(cover, fit: BoxFit.cover, errorBuilder: (_, _, _) => fallback) : fallback,
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black.withValues(alpha: 0.78)],
                    stops: const [0.35, 1.0],
                  ),
                ),
              ),
              Positioned(
                left: 12,
                right: 12,
                bottom: 12,
                child: Text(
                  tripData['title'].toString(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white, height: 1.15),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLabsMetadata(Poi poi) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.science_rounded, size: 16, color: Colors.amber),
              const SizedBox(width: 6),
              Text(
                'Metadatos de Ingeniería (Solo en Labs)',
                style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.amber[900]),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text('ID: ${poi.poiId}', style: GoogleFonts.firaCode(fontSize: 10.5, color: OhtliColors.subtleText)),
          Text('Coords: ${poi.location.lat}, ${poi.location.lng}', style: GoogleFonts.firaCode(fontSize: 10.5, color: OhtliColors.subtleText)),
          if (poi.actividadEconomica.isNotEmpty)
            Text('INEGI: ${poi.actividadEconomica}', style: GoogleFonts.inter(fontSize: 10.5, color: OhtliColors.subtleText)),
          if (poi.cuisine.isNotEmpty) Text('Cocina (OSM): ${poi.cuisine}', style: GoogleFonts.inter(fontSize: 10.5, color: OhtliColors.subtleText)),
          Text('Fotos: ${poi.photos.length} · Reseñas: ${poi.reviewsSnippets.length}', style: GoogleFonts.inter(fontSize: 10.5, color: OhtliColors.subtleText)),
        ],
      ),
    );
  }

  // Acciones siempre visibles (móvil)
  /// 👍 / "No me interesa" y reporte de datos (retroalimentación explícita, RF-12).
  Widget _buildFeedbackRow() {
    final id = widget.poi.poiId;
    return ValueListenableBuilder<Set<String>>(
      valueListenable: FeedbackService.liked,
      builder: (context, liked, _) => ValueListenableBuilder<Set<String>>(
        valueListenable: FeedbackService.disliked,
        builder: (context, disliked, _) {
          final isLiked = liked.contains(id);
          final isDisliked = disliked.contains(id);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildTitle('TU OPINIÓN', '¿Te interesa este lugar?', Icons.thumbs_up_down_rounded, OhtliColors.stormyTeal),
              const SizedBox(height: 6),
              Text('Con esto ajustamos lo que te recomendamos.', style: OhtliUi.body(size: 13)),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OhtliChoiceChip(
                    label: 'Me interesa',
                    icon: isLiked ? Icons.thumb_up_alt_rounded : Icons.thumb_up_alt_outlined,
                    selected: isLiked,
                    onTap: () => FeedbackService.toggleLike(id, surface: widget.surface),
                  ),
                  OhtliChoiceChip(
                    label: 'No me interesa',
                    icon: isDisliked ? Icons.thumb_down_alt_rounded : Icons.thumb_down_alt_outlined,
                    selected: isDisliked,
                    onTap: () {
                      FeedbackService.toggleDislike(id, surface: widget.surface);
                      if (!isDisliked) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text('Listo, no te lo volveremos a sugerir.', style: GoogleFonts.inter(color: Colors.white)),
                          backgroundColor: OhtliColors.stormyTeal,
                          behavior: SnackBarBehavior.floating,
                          duration: const Duration(seconds: 3),
                          action: SnackBarAction(
                            label: 'Deshacer',
                            textColor: Colors.white,
                            onPressed: () => FeedbackService.toggleDislike(id, surface: widget.surface),
                          ),
                        ));
                      }
                    },
                  ),
                  OhtliChoiceChip(
                    label: 'Reportar un dato',
                    icon: Icons.flag_outlined,
                    selected: false,
                    onTap: _showReportSheet,
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showReportSheet() async {
    const options = [
      ('closed', 'Cerró definitivamente', Icons.block_rounded),
      ('horario', 'El horario está mal', Icons.schedule_rounded),
      ('precio', 'El precio está mal', Icons.payments_outlined),
      ('ubicacion', 'La ubicación está mal', Icons.wrong_location_outlined),
    ];
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: OhtliColors.cardBg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text('¿Qué está mal en ${widget.poi.name}?',
                    style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w800, color: OhtliColors.onyx)),
              ),
              for (final o in options)
                ListTile(
                  leading: Icon(o.$3, color: OhtliColors.accentText),
                  title: Text(o.$2, style: GoogleFonts.inter(fontSize: 15, color: OhtliColors.onyx)),
                  onTap: () => Navigator.of(ctx).pop(o.$1),
                ),
            ],
          ),
        ),
      ),
    );
    if (choice == null || !mounted) return;
    FeedbackService.report(widget.poi.poiId, closed: choice == 'closed', reason: choice);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Gracias. Revisaremos este lugar.', style: GoogleFonts.inter(color: Colors.white)),
      backgroundColor: OhtliColors.stormyTeal,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 2),
    ));
  }

  Widget _buildMobileActionBar() {
    final canSave = FirebaseAuth.instance.currentUser != null;
    return Container(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + MediaQuery.of(context).padding.bottom),
      decoration: BoxDecoration(
        color: OhtliColors.cardBg,
        border: Border(top: BorderSide(color: OhtliColors.cardBorder)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 12, offset: const Offset(0, -4))],
      ),
      child: Row(
        children: [
          if (canSave) ...[
            _buildSaveButton(iconOnly: true),
            const SizedBox(width: 8),
          ],
          Tooltip(
            message: 'Compartir',
            child: SizedBox(
              width: 52,
              height: 52,
              child: OutlinedButton(
                onPressed: _share,
                style: OutlinedButton.styleFrom(
                  padding: EdgeInsets.zero,
                  side: BorderSide(color: OhtliColors.cardBorder),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: Icon(Icons.ios_share_rounded, size: 20, color: OhtliColors.onyx),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: OhtliPrimaryButton(
              label: 'Crear ruta desde aquí',
              icon: Icons.alt_route_rounded,
              onPressed: _createRouteFromThisPlace,
              highlight: true,
              expand: true,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFriendlyPill(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 6),
          Text(label, style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w700, color: color)),
        ],
      ),
    );
  }
}

class _QuickFact {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  const _QuickFact(this.icon, this.label, this.value, this.color);
}

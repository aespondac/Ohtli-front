// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:html' as html;
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';
import '../theme/colors.dart';
import '../models/poi_model.dart';
import '../models/trip_model.dart';
import '../screens/trips/trip_editor_page.dart';
import '../screens/trips/trip_viewer_page.dart';
import '../utils/friendly_errors.dart';
import 'osrm_map_widget.dart';

class PoiDetailDialog extends StatefulWidget {
  final Poi poi;
  final bool isSaved;
  final ValueChanged<bool>? onSaveToggle;
  final VoidCallback? onCreateRoute;
  final bool asSheet;

  const PoiDetailDialog({
    super.key,
    required this.poi,
    this.isSaved = false,
    this.onSaveToggle,
    this.onCreateRoute,
    this.asSheet = false,
  });

  static void show(
    BuildContext context,
    Poi poi, {
    bool isSaved = false,
    ValueChanged<bool>? onSaveToggle,
    VoidCallback? onCreateRoute,
  }) {
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
      ),
    );
  }

  @override
  State<PoiDetailDialog> createState() => _PoiDetailDialogState();
}

class _PoiDetailDialogState extends State<PoiDetailDialog> {
  late bool _isSaved;
  bool _isCreatingTrip = false;
  List<Map<String, dynamic>> _matchingPublicTrips = [];
  bool _isLoadingTrips = true;

  @override
  void initState() {
    super.initState();
    _isSaved = widget.isSaved;
    _checkSavedStatus();
    _findMatchingPublicTrips();
  }

  void _checkSavedStatus() {
    if (kIsWeb) {
      try {
        final saved = html.window.localStorage['ohtli_saved_pois'];
        if (saved != null && saved.isNotEmpty) {
          final ids = saved.split(',').where((id) => id.trim().isNotEmpty).toList();
          if (ids.contains(widget.poi.poiId)) {
            setState(() => _isSaved = true);
          }
        }
      } catch (_) {}
    }
  }

  void _toggleSave() {
    setState(() => _isSaved = !_isSaved);
    if (kIsWeb) {
      try {
        final saved = html.window.localStorage['ohtli_saved_pois'];
        List<String> ids = (saved != null && saved.isNotEmpty)
            ? saved.split(',').where((id) => id.trim().isNotEmpty).toList()
            : [];
        if (_isSaved) {
          if (!ids.contains(widget.poi.poiId)) ids.insert(0, widget.poi.poiId);
        } else {
          ids.remove(widget.poi.poiId);
        }
        html.window.localStorage['ohtli_saved_pois'] = ids.join(',');
      } catch (_) {}
    }
    widget.onSaveToggle?.call(_isSaved);

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
    final query = Uri.encodeComponent('${poi.name} (${poi.location.lat},${poi.location.lng})');
    final url = 'https://www.google.com/maps/search/?api=1&query=$query';
    if (kIsWeb) {
      html.window.open(url, '_blank');
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

    setState(() => _isCreatingTrip = true);

    try {
      final tripId = const Uuid().v4();
      final now = DateTime.now();
      final poi = widget.poi;

      final initialPlace = PlaceSection(
        id: 'sec_${now.millisecondsSinceEpoch}_0',
        title: poi.name,
        description: poi.cleanNarrative,
        rating: 5,
        mainPhotoUrl: poi.imageUrl,
        secondaryPhotoUrls: [],
        cost: poi.priceMxnAvg ?? (poi.priceLevel * 60.0),
        currency: 'MXN',
        lat: poi.location.isValid ? poi.location.lat : null,
        lng: poi.location.isValid ? poi.location.lng : null,
      );

      final newTrip = Trip(
        id: tripId,
        userId: user.uid,
        title: 'Ruta desde ${poi.name}',
        description: 'Itinerario cultural comenzando en ${poi.name}, ${poi.coloniaAlcaldiaDisplay}.',
        coverUrl: poi.imageUrl,
        status: 'draft',
        visibility: 'private',
        createdAt: now,
        updatedAt: now,
      );

      final content = TripContent(sections: [initialPlace]);

      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('trips')
          .doc(tripId)
          .set(newTrip.toMap());

      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('trips')
          .doc(tripId)
          .collection('details')
          .doc('content')
          .set(content.toMap());

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Ruta creada. Abriendo editor...',
              style: GoogleFonts.inter(color: Colors.white),
            ),
            backgroundColor: OhtliColors.cempasuchil,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );

        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => TripEditorPage(trip: newTrip),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isCreatingTrip = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(friendlyError(e, fallback: 'No pudimos crear la ruta. Intenta de nuevo.')),
            backgroundColor: OhtliColors.xoconostle,
          ),
        );
      }
    }
  }

  // ==========================================
  // DISEÑO DEL MODAL
  // - Escritorio: diálogo centrado. Móvil: hoja inferior a pantalla casi completa.
  // - Portada que se colapsa al hacer scroll y deja el nombre fijo arriba.
  // - Datos rápidos (precio, horario, zona), descripción, ubicación con mapa,
  //   y acciones fijas abajo.
  // ==========================================
  bool _isNarrativeExpanded = false;

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isMobile = ohtliIsMobileWidth(screenSize.width);

    if (widget.asSheet) {
      return ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: Material(
          color: OhtliColors.cardBg,
          child: _buildContent(context, isMobile: true, radius: 24),
        ),
      );
    }

    return Dialog(
      backgroundColor: OhtliColors.cardBg,
      clipBehavior: Clip.antiAlias,
      insetPadding: EdgeInsets.symmetric(
        horizontal: isMobile ? 16 : 40,
        vertical: isMobile ? 24 : 32,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: OhtliColors.cardBorder),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 760,
          maxHeight: screenSize.height * 0.9,
        ),
        child: _buildContent(context, isMobile: isMobile, radius: 24),
      ),
    );
  }

  Widget _buildContent(BuildContext context, {required bool isMobile, required double radius}) {
    final poi = widget.poi;
    final bool isLabsUrl = kIsWeb && html.window.location.hostname != null && html.window.location.hostname!.contains('labs');
    final double heroHeight = isMobile ? 260 : 300;
    final double hPad = isMobile ? 20 : 28;

    return Column(
      children: [
        Expanded(
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
            slivers: [
              _buildHeroAppBar(poi, heroHeight, isMobile),
              SliverPadding(
                padding: EdgeInsets.fromLTRB(hPad, 20, hPad, 28),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    _buildQuickFacts(poi, isMobile),
                    const SizedBox(height: 26),
                    _buildSectionTitle('Sobre este lugar'),
                    const SizedBox(height: 10),
                    _buildNarrative(poi),
                    ..._buildHighlightsSection(poi),
                    if (poi.vibeTags.isNotEmpty) ...[
                      const SizedBox(height: 26),
                      _buildSectionTitle('Ambiente'),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: poi.vibeTags.map((v) => _buildVibeChip(v.startsWith('#') ? v.substring(1) : v)).toList(),
                      ),
                    ],
                    if (poi.location.isValid) ...[
                      const SizedBox(height: 26),
                      _buildLocationSection(poi, isMobile),
                    ],
                    const SizedBox(height: 26),
                    _buildTripsSection(),
                    if (isLabsUrl) ...[
                      const SizedBox(height: 24),
                      _buildLabsMetadata(poi),
                    ],
                  ]),
                ),
              ),
            ],
          ),
        ),
        _buildActionBar(isMobile),
      ],
    );
  }

  // Portada colapsable: al hacer scroll queda una barra con el nombre del lugar
  Widget _buildHeroAppBar(Poi poi, double heroHeight, bool isMobile) {
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final collapsedRatio = (constraints.scrollOffset / (heroHeight - kToolbarHeight)).clamp(0.0, 1.0);
        final collapsed = collapsedRatio > 0.85;
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
            child: Text(
              poi.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.outfit(fontSize: 17, fontWeight: FontWeight.w800, color: OhtliColors.onyx),
            ),
          ),
          actions: [
            _buildHeaderIconButton(
              icon: Icons.close_rounded,
              tooltip: 'Cerrar',
              onTap: () => Navigator.of(context).pop(),
              onImage: !collapsed,
            ),
            const SizedBox(width: 14),
          ],
          flexibleSpace: FlexibleSpaceBar(
            collapseMode: CollapseMode.parallax,
            background: Stack(
              fit: StackFit.expand,
              children: [
                _buildHeroImage(poi),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.40),
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.86),
                      ],
                      stops: const [0.0, 0.38, 1.0],
                    ),
                  ),
                ),
                Positioned(
                  left: isMobile ? 20 : 28,
                  right: isMobile ? 20 : 28,
                  bottom: 22,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: poi.categoryColor,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${poi.categoryEmoji} ${poi.categoryDisplay.toUpperCase()}',
                          style: GoogleFonts.inter(
                            color: Colors.white,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        poi.name,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.outfit(
                          fontSize: isMobile ? 26 : 32,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          height: 1.1,
                          shadows: [Shadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 12)],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(Icons.location_on_rounded, size: 15, color: Colors.white70),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              poi.coloniaAlcaldiaDisplay,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(fontSize: 13, color: Colors.white.withValues(alpha: 0.85), fontWeight: FontWeight.w500),
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
        );
      },
    );
  }

  Widget _buildHeroImage(Poi poi) {
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
          poi.imageUrl,
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

  Widget _buildHeaderIconButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
    bool highlighted = false,
    bool onImage = true,
  }) {
    final Color fg = highlighted ? OhtliColors.cempasuchil : (onImage ? Colors.white : OhtliColors.onyx);
    return Tooltip(
      message: tooltip,
      child: Material(
        color: onImage ? Colors.black.withValues(alpha: 0.42) : OhtliColors.innerCardBg,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 38,
            height: 38,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              transitionBuilder: (child, anim) => ScaleTransition(scale: anim, child: child),
              child: Icon(icon, key: ValueKey(icon), size: 19, color: fg),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String text) {
    return Text(
      text,
      style: GoogleFonts.outfit(fontSize: 17, fontWeight: FontWeight.w800, color: OhtliColors.onyx),
    );
  }

  // Tres datos clave de un vistazo
  Widget _buildQuickFacts(Poi poi, bool isMobile) {
    final hasRealHours = poi.openingHours.trim().isNotEmpty;
    final facts = [
      _QuickFact(Icons.payments_outlined, 'Precio', poi.priceRangeEstimate, OhtliColors.stormyTeal),
      _QuickFact(Icons.schedule_rounded, hasRealHours ? 'Horario' : 'Horario aprox.', poi.openingHoursDisplay, OhtliColors.cempasuchil),
    ];
    final tiles = facts.map((f) => _buildFactTile(f)).toList();
    if (isMobile) {
      return Column(
        children: [
          for (var i = 0; i < tiles.length; i++) ...[
            if (i > 0) Divider(height: 1, color: OhtliColors.cardBorder),
            tiles[i],
          ],
        ],
      );
    }
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < tiles.length; i++) ...[
            if (i > 0) VerticalDivider(width: 1, color: OhtliColors.cardBorder),
            Expanded(child: tiles[i]),
          ],
        ],
      ),
    );
  }

  Widget _buildFactTile(_QuickFact f) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(color: f.color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
            child: Icon(f.icon, size: 17, color: f.color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  f.label.toUpperCase(),
                  style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: OhtliColors.subtleText),
                ),
                const SizedBox(height: 3),
                Text(
                  f.value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: OhtliColors.onyx, height: 1.3),
                ),
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
    final isLong = text.length > 320;
    final style = GoogleFonts.inter(fontSize: 14.5, height: 1.6, color: OhtliColors.onyx.withValues(alpha: 0.88));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AnimatedSize(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: Text(
            text,
            maxLines: (!isLong || _isNarrativeExpanded) ? null : 5,
            overflow: (!isLong || _isNarrativeExpanded) ? TextOverflow.visible : TextOverflow.ellipsis,
            style: style,
          ),
        ),
        if (isLong)
          TextButton(
            onPressed: () => setState(() => _isNarrativeExpanded = !_isNarrativeExpanded),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 6),
              foregroundColor: OhtliColors.stormyTeal,
            ),
            child: Text(
              _isNarrativeExpanded ? 'Leer menos' : 'Leer más',
              style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700),
            ),
          ),
      ],
    );
  }

  // Solo características reales del lugar (antes se mostraba siempre "Entorno caminable de día" sin dato que lo respaldara)
  List<Widget> _buildHighlightsSection(Poi poi) {
    final pills = <Widget>[
      if (poi.patrimonioHistorico) _buildFriendlyPill(Icons.account_balance_rounded, 'Patrimonio histórico', OhtliColors.xoconostle),
      if (poi.areaVerdeCercana) _buildFriendlyPill(Icons.park_rounded, 'Áreas verdes cerca', const Color(0xFF2E7D32)),
      if (poi.wheelchairAccessible) _buildFriendlyPill(Icons.accessible_rounded, 'Accesible en silla de ruedas', const Color(0xFF1E6FD9)),
      if (poi.coeficienteMovilidad > 0) _buildFriendlyPill(Icons.directions_bike_rounded, 'Cerca de Ecobici y ciclovías', OhtliColors.cempasuchil),
      if (poi.musicaEnVivo) _buildFriendlyPill(Icons.music_note_rounded, 'Música en vivo', const Color(0xFF8E24AA)),
      if (poi.consumoAlcohol) _buildFriendlyPill(Icons.local_bar_rounded, 'Bebidas y coctelería', const Color(0xFFD81B60)),
    ];
    if (pills.isEmpty) return const [];
    return [
      const SizedBox(height: 26),
      _buildSectionTitle('Lo que debes saber'),
      const SizedBox(height: 10),
      Wrap(spacing: 8, runSpacing: 8, children: pills),
    ];
  }

  Widget _buildVibeChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: OhtliColors.stormyTeal.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: OhtliColors.stormyTeal),
      ),
    );
  }

  Widget _buildLocationSection(Poi poi, bool isMobile) {
    final address = poi.address.trim().isNotEmpty ? poi.address.trim() : poi.coloniaAlcaldiaDisplay;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: _buildSectionTitle('Ubicación')),
            TextButton.icon(
              onPressed: _openInMaps,
              icon: const Icon(Icons.directions_rounded, size: 17),
              label: Text('Cómo llegar', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700)),
              style: TextButton.styleFrom(foregroundColor: OhtliColors.stormyTeal),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          address,
          style: GoogleFonts.inter(fontSize: 13, color: OhtliColors.subtleText, height: 1.4),
        ),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: OsrmMapWidget(
            stops: [
              {
                'name': poi.name,
                'lat': poi.location.lat,
                'lng': poi.location.lng,
                'category': poi.category,
              },
            ],
            height: isMobile ? 180 : 210,
            isDark: OhtliSettings.instance.isDarkMode,
            compact: true,
          ),
        ),
      ],
    );
  }

  Widget _buildTripsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('Viajes que pasan por aquí'),
        const SizedBox(height: 12),
        if (_isLoadingTrips)
          SizedBox(
            height: 150,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: 2,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (_, __) => Container(
                width: 220,
                decoration: BoxDecoration(color: OhtliColors.innerCardBg, borderRadius: BorderRadius.circular(16)),
              ),
            ),
          )
        else if (_matchingPublicTrips.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: OhtliColors.innerCardBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: OhtliColors.cardBorder),
            ),
            child: Row(
              children: [
                Icon(Icons.explore_outlined, size: 22, color: OhtliColors.stormyTeal),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Aún nadie ha publicado un viaje con este lugar. Puedes ser la primera persona en crear uno.',
                    style: GoogleFonts.inter(fontSize: 13, color: OhtliColors.subtleText, height: 1.4),
                  ),
                ),
              ],
            ),
          )
        else
          SizedBox(
            height: 150,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _matchingPublicTrips.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, i) => _buildTripCard(_matchingPublicTrips[i]),
            ),
          ),
      ],
    );
  }

  Widget _buildTripCard(Map<String, dynamic> tripData) {
    final cover = tripData['coverUrl'].toString();
    return SizedBox(
      width: 220,
      child: Material(
        color: OhtliColors.innerCardBg,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => TripViewerPage(
                  tripId: tripData['tripId'],
                  authorId: tripData['authorId'],
                ),
              ),
            );
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: cover.isNotEmpty
                    ? Image.network(
                        cover,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => Container(
                          color: OhtliColors.stormyTeal.withValues(alpha: 0.12),
                          child: const Icon(Icons.map_rounded, color: OhtliColors.stormyTeal),
                        ),
                      )
                    : Container(
                        color: OhtliColors.stormyTeal.withValues(alpha: 0.12),
                        child: const Icon(Icons.map_rounded, color: OhtliColors.stormyTeal),
                      ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                child: Text(
                  tripData['title'].toString(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w700, color: OhtliColors.onyx, height: 1.2),
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
        ],
      ),
    );
  }

  // Acciones siempre visibles
  Widget _buildActionBar(bool isMobile) {
    final primary = ElevatedButton.icon(
      onPressed: _isCreatingTrip ? null : _createRouteFromThisPlace,
      icon: _isCreatingTrip
          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF1A120B)))
          : const Icon(Icons.alt_route_rounded, size: 18),
      label: Text(_isCreatingTrip ? 'Creando ruta...' : 'Crear ruta desde aquí'),
      style: ElevatedButton.styleFrom(
        backgroundColor: OhtliColors.cempasuchil,
        foregroundColor: const Color(0xFF1A120B),
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 15),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: GoogleFonts.outfit(fontWeight: FontWeight.w800, fontSize: 15),
      ),
    );
    final secondary = OutlinedButton.icon(
      onPressed: _toggleSave,
      icon: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        transitionBuilder: (child, anim) => ScaleTransition(scale: anim, child: child),
        child: Icon(
          _isSaved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
          key: ValueKey(_isSaved),
          size: 18,
          color: _isSaved ? OhtliColors.cempasuchil : OhtliColors.onyx,
        ),
      ),
      label: Text(_isSaved ? 'Guardado' : 'Guardar'),
      style: OutlinedButton.styleFrom(
        foregroundColor: OhtliColors.onyx,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
        side: BorderSide(color: OhtliColors.cardBorder),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 14),
      ),
    );
    return Container(
      padding: EdgeInsets.fromLTRB(isMobile ? 16 : 24, 12, isMobile ? 16 : 24, 12 + MediaQuery.of(context).padding.bottom),
      decoration: BoxDecoration(
        color: OhtliColors.cardBg,
        border: Border(top: BorderSide(color: OhtliColors.cardBorder)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 12, offset: const Offset(0, -4)),
        ],
      ),
      child: Row(
        children: [
          if (isMobile)
            // En móvil, guardar es solo un ícono para que el botón principal quepa en una línea
            Tooltip(
              message: _isSaved ? 'Quitar de Mis lugares' : 'Guardar en Mis lugares',
              child: SizedBox(
                width: 52,
                height: 52,
                child: OutlinedButton(
                  onPressed: _toggleSave,
                  style: OutlinedButton.styleFrom(
                    padding: EdgeInsets.zero,
                    side: BorderSide(color: _isSaved ? OhtliColors.cempasuchil : OhtliColors.cardBorder),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: Icon(
                    _isSaved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
                    size: 22,
                    color: _isSaved ? OhtliColors.cempasuchil : OhtliColors.onyx,
                  ),
                ),
              ),
            )
          else
            secondary,
          const SizedBox(width: 10),
          Expanded(child: primary),
        ],
      ),
    );
  }

  Widget _buildFriendlyPill(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
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

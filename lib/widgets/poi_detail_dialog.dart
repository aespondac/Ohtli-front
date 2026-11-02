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

class PoiDetailDialog extends StatefulWidget {
  final Poi poi;
  final bool isSaved;
  final ValueChanged<bool>? onSaveToggle;
  final VoidCallback? onCreateRoute;

  const PoiDetailDialog({
    super.key,
    required this.poi,
    this.isSaved = false,
    this.onSaveToggle,
    this.onCreateRoute,
  });

  static void show(
    BuildContext context,
    Poi poi, {
    bool isSaved = false,
    ValueChanged<bool>? onSaveToggle,
    VoidCallback? onCreateRoute,
  }) {
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
          .get();

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
            content: Text('Error al crear la ruta: $e'),
            backgroundColor: OhtliColors.xoconostle,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final poi = widget.poi;
    final screenSize = MediaQuery.of(context).size;
    final isMobile = screenSize.width < 700;

    // Detect if running inside labs
    final bool isLabsUrl = kIsWeb && html.window.location.hostname != null &&
        html.window.location.hostname!.contains('labs');

    return Dialog(
      backgroundColor: OhtliColors.cardBg,
      insetPadding: EdgeInsets.symmetric(
        horizontal: isMobile ? 16 : 40,
        vertical: isMobile ? 24 : 36,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: OhtliColors.cardBorder),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 720,
          maxHeight: screenSize.height * 0.90,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. Hero Image Banner with Elegant Gradient & Context
            Stack(
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                  child: AspectRatio(
                    aspectRatio: isMobile ? 16 / 9 : 21 / 9,
                    child: Image.network(
                      poi.imageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => Container(
                        color: poi.categoryColor.withValues(alpha: 0.15),
                        child: Center(
                          child: Icon(poi.categoryIcon, size: 48, color: poi.categoryColor),
                        ),
                      ),
                    ),
                  ),
                ),
                // Gradient overlay for contrast
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.35),
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.82),
                        ],
                        stops: const [0.0, 0.4, 1.0],
                      ),
                    ),
                  ),
                ),
                // Close button top-right
                Positioned(
                  top: 14,
                  right: 14,
                  child: IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, color: Colors.white, size: 20),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.black.withValues(alpha: 0.5),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                // Save/Favorite quick toggle button top-left
                Positioned(
                  top: 14,
                  left: 14,
                  child: InkWell(
                    onTap: _toggleSave,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _isSaved ? OhtliColors.cempasuchil : Colors.white24,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _isSaved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
                            color: _isSaved ? OhtliColors.cempasuchil : Colors.white,
                            size: 16,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            _isSaved ? 'Guardado' : 'Guardar',
                            style: GoogleFonts.inter(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                // Title & Highlights at the bottom of the banner
                Positioned(
                  bottom: 16,
                  left: 20,
                  right: 20,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
                                letterSpacing: 0.4,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.65),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                            ),
                            child: Text(
                              poi.priceRangeEstimate,
                              style: GoogleFonts.inter(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        poi.name,
                        style: GoogleFonts.outfit(
                          fontSize: isMobile ? 22 : 26,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          height: 1.15,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(Icons.location_on_rounded, size: 14, color: Colors.white70),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              poi.coloniaAlcaldiaDisplay,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                color: Colors.white70,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),

            // 2. Scrollable Body
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Opening Hours Card
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                      decoration: BoxDecoration(
                        color: OhtliColors.innerCardBg,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: OhtliColors.cardBorder),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.access_time_rounded, size: 17, color: OhtliColors.stormyTeal),
                          const SizedBox(width: 10),
                          Text(
                            'Horario sugerido:',
                            style: GoogleFonts.inter(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: OhtliColors.onyx,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              poi.openingHoursDisplay,
                              style: GoogleFonts.inter(
                                fontSize: 12.5,
                                color: OhtliColors.subtleText,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    // "Sobre este lugar" Section (Clean narrative without technical forms)
                    Text(
                      'Sobre este lugar',
                      style: GoogleFonts.outfit(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: OhtliColors.onyx,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      poi.cleanNarrative,
                      style: GoogleFonts.inter(
                        fontSize: 13.5,
                        height: 1.55,
                        color: OhtliColors.onyx.withValues(alpha: 0.88),
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Practical Amenities & Urban Highlights
                    Text(
                      'Lo que debes saber',
                      style: GoogleFonts.outfit(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: OhtliColors.onyx,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (poi.areaVerdeCercana)
                          _buildFriendlyPill(Icons.park_rounded, 'Rodeado de áreas verdes', const Color(0xFF2E7D32)),
                        if (poi.wheelchairAccessible)
                          _buildFriendlyPill(Icons.accessible_rounded, 'Accesible para sillas de ruedas', Colors.blue),
                        if (poi.coeficienteMovilidad > 0)
                          _buildFriendlyPill(Icons.directions_bike_rounded, 'Conectado a Ecobici y ciclovías', OhtliColors.cempasuchil),
                        if (poi.patrimonioHistorico)
                          _buildFriendlyPill(Icons.account_balance_rounded, 'Monumento / Patrimonio histórico', OhtliColors.xoconostle),
                        if (poi.musicaEnVivo)
                          _buildFriendlyPill(Icons.music_note_rounded, 'Música en vivo', const Color(0xFF8E24AA)),
                        if (poi.consumoAlcohol)
                          _buildFriendlyPill(Icons.local_bar_rounded, 'Bebidas artesanales / Coctelería', const Color(0xFFD81B60)),
                        _buildFriendlyPill(Icons.verified_user_rounded, 'Entorno caminable de día', OhtliColors.stormyTeal),
                      ],
                    ),

                    // Vibe & Atmosphere Hashtags
                    if (poi.vibeTags.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      Text(
                        'Atmósfera y vibras',
                        style: GoogleFonts.outfit(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: OhtliColors.onyx,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: poi.vibeTags.map((v) {
                          final tag = v.startsWith('#') ? v : '#$v';
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: OhtliColors.innerCardBg,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: OhtliColors.cardBorder),
                            ),
                            child: Text(
                              tag,
                              style: GoogleFonts.inter(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: OhtliColors.stormyTeal,
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],

                    const SizedBox(height: 24),

                    // Public Trips containing this Place (Replaces raw reviews snippets)
                    Row(
                      children: [
                        Text(
                          'Viajes y crónicas de viajeros',
                          style: GoogleFonts.outfit(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: OhtliColors.onyx,
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (_isLoadingTrips)
                          const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2, color: OhtliColors.stormyTeal),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    if (!_isLoadingTrips && _matchingPublicTrips.isEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: OhtliColors.innerCardBg,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: OhtliColors.cardBorder),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.explore_outlined, size: 20, color: OhtliColors.subtleText),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Aún no hay viajes públicos registrados con este lugar. ¡Sé el primero en crear una ruta!',
                                style: GoogleFonts.inter(fontSize: 12.5, color: OhtliColors.subtleText),
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      Column(
                        children: _matchingPublicTrips.map((tripData) {
                          return Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            decoration: BoxDecoration(
                              color: OhtliColors.innerCardBg,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: OhtliColors.cardBorder),
                            ),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                              leading: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Container(
                                  width: 48,
                                  height: 48,
                                  color: OhtliColors.cardBg,
                                  child: tripData['coverUrl'].toString().isNotEmpty
                                      ? Image.network(tripData['coverUrl'], fit: BoxFit.cover)
                                      : const Icon(Icons.map_rounded, color: OhtliColors.stormyTeal),
                                ),
                              ),
                              title: Text(
                                tripData['title'],
                                style: GoogleFonts.outfit(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: OhtliColors.onyx,
                                ),
                              ),
                              subtitle: Text(
                                tripData['description'],
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.inter(fontSize: 11.5, color: OhtliColors.subtleText),
                              ),
                              trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14),
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
                            ),
                          );
                        }).toList(),
                      ),

                    // Technical Metadata ONLY in labs.ohtli.quest
                    if (isLabsUrl) ...[
                      const SizedBox(height: 24),
                      Container(
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
                      ),
                    ],
                  ],
                ),
              ),
            ),

            // 3. Footer Action Buttons: [Crea una ruta desde aquí] (Primary) + [Google Maps]
            Container(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
              decoration: BoxDecoration(
                color: OhtliColors.innerCardBg,
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
                border: Border(top: BorderSide(color: OhtliColors.cardBorder)),
              ),
              child: isMobile
                  ? Column(
                      children: [
                        // Primary CTA: Crea una ruta desde aquí
                        SizedBox(
                          width: double.infinity,
                          height: 44,
                          child: ElevatedButton.icon(
                            onPressed: _isCreatingTrip ? null : _createRouteFromThisPlace,
                            icon: _isCreatingTrip
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                                  )
                                : const Icon(Icons.alt_route_rounded, size: 18),
                            label: const Text('Crea una ruta desde este punto'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: OhtliColors.cempasuchil,
                              foregroundColor: const Color(0xFF1A120B),
                              elevation: 0,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              textStyle: GoogleFonts.outfit(fontWeight: FontWeight.w800, fontSize: 14),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: _openInMaps,
                            icon: const Icon(Icons.map_rounded, size: 16),
                            label: const Text('Ver en Google Maps'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: OhtliColors.onyx,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              side: BorderSide(color: OhtliColors.cardBorder),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ),
                      ],
                    )
                  : Row(
                      children: [
                        // Secondary action: Google Maps
                        OutlinedButton.icon(
                          onPressed: _openInMaps,
                          icon: const Icon(Icons.map_rounded, size: 16),
                          label: const Text('Ver en Google Maps'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: OhtliColors.onyx,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                            side: BorderSide(color: OhtliColors.cardBorder),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                        const Spacer(),
                        // Primary CTA: Crea una ruta desde este punto
                        ElevatedButton.icon(
                          onPressed: _isCreatingTrip ? null : _createRouteFromThisPlace,
                          icon: _isCreatingTrip
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                                )
                              : const Icon(Icons.alt_route_rounded, size: 18),
                          label: const Text('Crea una ruta desde este punto'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: OhtliColors.cempasuchil,
                            foregroundColor: const Color(0xFF1A120B),
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            textStyle: GoogleFonts.outfit(fontWeight: FontWeight.w800, fontSize: 14),
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
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

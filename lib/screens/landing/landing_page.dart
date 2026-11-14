// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../theme/colors.dart';
import '../../theme/cdmx_photos.dart';
import '../../models/poi_model.dart';
import '../../widgets/poi_card.dart';
import '../../widgets/poi_detail_dialog.dart';
import '../places/places_page.dart';

/// Crónica pública resumida para la portada.
class _PublicTrip {
  final String tripId;
  final String authorId;
  final String title;
  final String description;
  final String coverUrl;

  const _PublicTrip(
    this.tripId,
    this.authorId,
    this.title,
    this.description,
    this.coverUrl,
  );
}

/// Página de inicio pública de ohtli.quest.
/// Sin cuenta se pueden ver lugares y crónicas públicas; lo personal (rutas, guardados,
/// recomendaciones) invita a crear una cuenta.
class LandingPage extends StatefulWidget {
  final VoidCallback onLoginClick;
  final VoidCallback onRegisterClick;
  final VoidCallback onOpenPlaces;
  final void Function(String tripId, String authorId) onOpenPublicTrip;
  final VoidCallback? onOpenTerms;

  const LandingPage({
    super.key,
    required this.onLoginClick,
    required this.onRegisterClick,
    required this.onOpenPlaces,
    required this.onOpenPublicTrip,
    this.onOpenTerms,
  });

  @override
  State<LandingPage> createState() => _LandingPageState();
}

class _LandingPageState extends State<LandingPage> {
  final _scrollController = ScrollController();
  final _placesKey = GlobalKey();
  final _howKey = GlobalKey();
  final _storiesKey = GlobalKey();
  final _placesScroll = ScrollController();

  late final Future<List<Poi>> _catalogFuture = PlacesPage.loadCatalog();
  late final Future<List<_PublicTrip>> _tripsFuture = _loadPublicTrips();

  @override
  void dispose() {
    _scrollController.dispose();
    _placesScroll.dispose();
    super.dispose();
  }

  Future<List<_PublicTrip>> _loadPublicTrips() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collectionGroup('trips')
          .where('status', isEqualTo: 'published')
          .where('visibility', isEqualTo: 'public')
          .orderBy('updatedAt', descending: true)
          .limit(20)
          .get()
          .timeout(const Duration(seconds: 10));
      final trips = <_PublicTrip>[];
      for (final doc in snapshot.docs) {
        final data = doc.data();
        if (data['isSurprise'] == true || data['kind'] == 'release_notes')
          continue;
        final authorId =
            (data['userId'] ?? doc.reference.parent.parent?.id ?? '')
                .toString();
        if (authorId.isEmpty) continue;
        final title = (data['title'] ?? '').toString().trim();
        trips.add(
          _PublicTrip(
            doc.id,
            authorId,
            title.isEmpty ? 'Viaje sin título' : title,
            (data['description'] ?? '').toString(),
            (data['coverUrl'] ?? '').toString(),
          ),
        );
        if (trips.length >= 6) break;
      }
      return trips;
    } catch (e) {
      debugPrint('Landing: no se pudieron cargar crónicas públicas: $e');
      return [];
    }
  }

  void _scrollTo(GlobalKey key) {
    final ctx = key.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeInOutCubic,
    );
  }

  void _openPlace(Poi poi) {
    PoiDetailDialog.show(context, poi, onCreateRoute: widget.onRegisterClick);
  }

  void _openExternal(String url) {
    if (kIsWeb) html.window.open(url, '_blank');
  }

  double _hPad(double width) => width < 700 ? 20 : (width < 1100 ? 40 : 64);

  Widget _constrained(Widget child, double width) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1240),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: _hPad(width)),
          child: child,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isMobile = width < 800;

    return Scaffold(
      backgroundColor: OhtliColors.cloudDancer,
      body: SafeArea(
        child: SingleChildScrollView(
          controller: _scrollController,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _constrained(_buildNav(isMobile), width),
              _constrained(_buildHero(isMobile), width),
              const SizedBox(height: 28),
              _constrained(_buildStats(isMobile), width),
              SizedBox(key: _placesKey, height: isMobile ? 56 : 88),
              _buildPlacesSection(isMobile, width),
              SizedBox(key: _howKey, height: isMobile ? 56 : 88),
              _constrained(_buildHowItWorks(isMobile), width),
              SizedBox(key: _storiesKey, height: isMobile ? 56 : 88),
              _constrained(_buildStories(isMobile, width), width),
              SizedBox(height: isMobile ? 56 : 88),
              _constrained(_buildFinalCta(isMobile), width),
              const SizedBox(height: 48),
              _constrained(_buildFooter(isMobile), width),
              const SizedBox(height: 28),
            ],
          ),
        ),
      ),
    );
  }

  // ───────────────────────── Navegación ─────────────────────────

  Widget _buildNav(bool isMobile) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: isMobile ? 16 : 24),
      child: Row(
        children: [
          SvgPicture.asset(
            'assets/logo.svg',
            height: isMobile ? 22 : 26,
            colorFilter: const ColorFilter.mode(
              OhtliColors.stormyTeal,
              BlendMode.srcIn,
            ),
          ),
          if (!isMobile) ...[
            const SizedBox(width: 40),
            _navLink('Lugares', () => _scrollTo(_placesKey)),
            _navLink('Cómo funciona', () => _scrollTo(_howKey)),
            _navLink('Crónicas', () => _scrollTo(_storiesKey)),
          ],
          const Spacer(),
          TextButton(
            onPressed: widget.onLoginClick,
            style: TextButton.styleFrom(
              foregroundColor: OhtliColors.onyx,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              textStyle: GoogleFonts.inter(
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
            child: const Text('Iniciar sesión'),
          ),
          const SizedBox(width: 6),
          ElevatedButton(
            onPressed: widget.onRegisterClick,
            style: ElevatedButton.styleFrom(
              backgroundColor: OhtliColors.stormyTeal,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: EdgeInsets.symmetric(
                horizontal: isMobile ? 16 : 20,
                vertical: 13,
              ),
              shape: const StadiumBorder(),
              textStyle: GoogleFonts.inter(
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
            child: Text(isMobile ? 'Crear cuenta' : 'Crear cuenta gratis'),
          ),
        ],
      ),
    );
  }

  Widget _navLink(String label, VoidCallback onTap) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: OhtliColors.subtleText,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        textStyle: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 14),
      ),
      child: Text(label),
    );
  }

  // ───────────────────────── Portada ─────────────────────────

  Widget _buildHero(bool isMobile) {
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: OhtliColors.stormyTeal.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(
              color: OhtliColors.stormyTeal.withValues(alpha: 0.2),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.auto_awesome_rounded,
                size: 14,
                color: OhtliColors.stormyTeal,
              ),
              const SizedBox(width: 7),
              Text(
                'Rutas culturales con IA · CDMX',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: OhtliColors.stormyTeal,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        Text.rich(
          TextSpan(
            children: [
              const TextSpan(text: 'Tu camino por la\nCiudad de México, '),
              TextSpan(
                text: 'a tu medida.',
                style: TextStyle(color: OhtliColors.stormyTeal),
              ),
            ],
          ),
          style: GoogleFonts.outfit(
            fontSize: isMobile ? 38 : 60,
            fontWeight: FontWeight.w800,
            color: OhtliColors.onyx,
            height: 1.02,
            letterSpacing: isMobile ? -1.0 : -2.0,
          ),
        ),
        const SizedBox(height: 20),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Text(
            'Ohtli (del náhuatl, camino) descubre museos, cafés, cantinas y miradores que van contigo '
            'y los convierte en rutas según tu tiempo, tu presupuesto y tus gustos.',
            style: GoogleFonts.inter(
              fontSize: isMobile ? 15.5 : 17,
              color: OhtliColors.subtleText,
              height: 1.6,
            ),
          ),
        ),
        const SizedBox(height: 30),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            ElevatedButton.icon(
              onPressed: widget.onRegisterClick,
              icon: const Icon(Icons.alt_route_rounded, size: 19),
              label: const Text('Crea tu ruta gratis'),
              style: ElevatedButton.styleFrom(
                backgroundColor: OhtliColors.cempasuchil,
                foregroundColor: const Color(0xFF1A120B),
                elevation: 0,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 19,
                ),
                shape: const StadiumBorder(),
                textStyle: GoogleFonts.outfit(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
            ),
            OutlinedButton.icon(
              onPressed: widget.onOpenPlaces,
              icon: const Icon(Icons.explore_rounded, size: 19),
              label: const Text('Explorar lugares'),
              style: OutlinedButton.styleFrom(
                foregroundColor: OhtliColors.onyx,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 19,
                ),
                side: BorderSide(
                  color: OhtliColors.onyx.withValues(alpha: 0.18),
                ),
                shape: const StadiumBorder(),
                textStyle: GoogleFonts.outfit(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.lock_open_rounded,
              size: 15,
              color: OhtliColors.subtleText,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                'Explora lugares y crónicas públicas sin necesidad de cuenta.',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: OhtliColors.subtleText,
                ),
              ),
            ),
          ],
        ),
      ],
    );

    final collage = _buildCollage(isMobile);

    if (isMobile) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 12),
          text,
          const SizedBox(height: 36),
          collage,
        ],
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 36),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(flex: 11, child: text),
          const SizedBox(width: 48),
          Expanded(flex: 10, child: collage),
        ],
      ),
    );
  }

  Widget _photoTile(String url, {double radius = 28}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Container(color: OhtliColors.stormyTeal.withValues(alpha: 0.2)),
          Image.network(
            url,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Widget _floatingChip(
    IconData icon,
    String title,
    String subtitle,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 16, 10),
      decoration: BoxDecoration(
        color: OhtliColors.cardBg,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.16),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 19, color: color),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: GoogleFonts.outfit(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: OhtliColors.onyx,
                ),
              ),
              Text(
                subtitle,
                style: GoogleFonts.inter(
                  fontSize: 11.5,
                  color: OhtliColors.subtleText,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCollage(bool isMobile) {
    final h = isMobile ? 340.0 : 500.0;
    return SizedBox(
      height: h,
      child: LayoutBuilder(
        builder: (context, c) {
          final w = c.maxWidth;
          return Stack(
            clipBehavior: Clip.none,
            children: [
              // Foto principal
              Positioned(
                left: w * 0.18,
                top: 0,
                right: 0,
                bottom: h * 0.16,
                child: _photoTile(CdmxPhotos.covers[0], radius: 32),
              ),
              // Foto secundaria
              Positioned(
                left: 0,
                bottom: 0,
                width: w * 0.46,
                height: h * 0.48,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(
                      color: OhtliColors.cloudDancer,
                      width: 6,
                    ),
                  ),
                  child: _photoTile(CdmxPhotos.covers[6], radius: 22),
                ),
              ),
              Positioned(
                right: isMobile ? 8 : -12,
                bottom: h * 0.06,
                child: _floatingChip(
                  Icons.alt_route_rounded,
                  'Ruta de 4 paradas',
                  'Centro Histórico · 5 h',
                  OhtliColors.cempasuchil,
                ),
              ),
              Positioned(
                left: w * 0.12,
                top: h * 0.08,
                child: _floatingChip(
                  Icons.auto_awesome_rounded,
                  'Hecho para ti',
                  'Según tus gustos',
                  OhtliColors.stormyTeal,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // ───────────────────────── Cifras ─────────────────────────

  Widget _buildStats(bool isMobile) {
    return FutureBuilder<List<Poi>>(
      future: _catalogFuture,
      builder: (context, snap) {
        final pois = snap.data ?? const <Poi>[];
        final items = [
          (
            Icons.place_rounded,
            pois.isEmpty ? '—' : '${pois.length}',
            'lugares curados',
            OhtliColors.stormyTeal,
          ),
          (
            Icons.category_rounded,
            pois.isEmpty
                ? '—'
                : '${pois.map((p) => p.category).toSet().length}',
            'categorías',
            OhtliColors.xoconostle,
          ),
          (
            Icons.route_rounded,
            'IA',
            'rutas optimizadas',
            OhtliColors.cempasuchil,
          ),
          (
            Icons.groups_rounded,
            'Crónicas',
            'de la comunidad',
            const Color(0xFF3949AB),
          ),
        ];
        return Container(
          width: double.infinity,
          padding: EdgeInsets.symmetric(
            horizontal: isMobile ? 18 : 32,
            vertical: isMobile ? 18 : 26,
          ),
          decoration: BoxDecoration(
            color: OhtliColors.cardBg,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: OhtliColors.cardBorder),
          ),
          child: LayoutBuilder(
            builder: (context, c) {
              // En móvil, cuadrícula de 2×2; en escritorio, una sola fila
              final itemW = isMobile ? (c.maxWidth - 14) / 2 : 220.0;
              return Wrap(
                alignment: WrapAlignment.spaceBetween,
                runSpacing: 18,
                spacing: 14,
                children: items
                    .map(
                      (it) => SizedBox(
                        width: itemW,
                        child: Row(
                          children: [
                            Container(
                              width: isMobile ? 36 : 42,
                              height: isMobile ? 36 : 42,
                              decoration: BoxDecoration(
                                color: it.$4.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Icon(
                                it.$1,
                                size: isMobile ? 18 : 21,
                                color: it.$4,
                              ),
                            ),
                            SizedBox(width: isMobile ? 10 : 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    it.$2,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.outfit(
                                      fontSize: isMobile ? 18 : 22,
                                      fontWeight: FontWeight.w800,
                                      color: OhtliColors.onyx,
                                    ),
                                  ),
                                  Text(
                                    it.$3,
                                    maxLines: 2,
                                    style: GoogleFonts.inter(
                                      fontSize: 12,
                                      color: OhtliColors.subtleText,
                                      height: 1.3,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                    .toList(),
              );
            },
          ),
        );
      },
    );
  }

  // ───────────────────────── Encabezado de sección ─────────────────────────

  Widget _sectionHeader({
    required String eyebrow,
    required String title,
    required String subtitle,
    required bool isMobile,
    Widget? trailing,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                eyebrow.toUpperCase(),
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.6,
                  color: OhtliColors.stormyTeal,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                title,
                style: GoogleFonts.outfit(
                  fontSize: isMobile ? 28 : 40,
                  fontWeight: FontWeight.w800,
                  color: OhtliColors.onyx,
                  letterSpacing: isMobile ? -0.6 : -1.2,
                  height: 1.08,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                subtitle,
                style: GoogleFonts.inter(
                  fontSize: 15,
                  color: OhtliColors.subtleText,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
        if (trailing != null && !isMobile) ...[
          const SizedBox(width: 20),
          trailing,
        ],
      ],
    );
  }

  Widget _arrowLink(String label, VoidCallback onTap) {
    return TextButton.icon(
      onPressed: onTap,
      iconAlignment: IconAlignment.end,
      icon: const Icon(Icons.arrow_forward_rounded, size: 18),
      label: Text(label),
      style: TextButton.styleFrom(
        foregroundColor: OhtliColors.stormyTeal,
        textStyle: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 14),
      ),
    );
  }

  // ───────────────────────── Lugares ─────────────────────────

  Widget _buildPlacesSection(bool isMobile, double width) {
    final hPad = _hPad(width);
    final sidePad = width > 1240 ? (width - 1240) / 2 + hPad : hPad;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _constrained(
          _sectionHeader(
            eyebrow: 'Lugares',
            title: 'Rincones para empezar',
            subtitle:
                'Una muestra del catálogo. Ábrelos para ver horario, precio y ubicación.',
            isMobile: isMobile,
            trailing: _arrowLink('Ver todos los lugares', widget.onOpenPlaces),
          ),
          width,
        ),
        const SizedBox(height: 26),
        FutureBuilder<List<Poi>>(
          future: _catalogFuture,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return SizedBox(
                height: 360,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: EdgeInsets.symmetric(horizontal: sidePad),
                  itemCount: 5,
                  separatorBuilder: (_, _) => const SizedBox(width: 20),
                  itemBuilder: (_, _) => Container(
                    width: 268,
                    decoration: BoxDecoration(
                      color: OhtliColors.cardBorder,
                      borderRadius: BorderRadius.circular(24),
                    ),
                  ),
                ),
              );
            }
            final pois = _pickSample(snap.data ?? const []);
            if (pois.isEmpty) {
              return _constrained(
                _infoCard(
                  Icons.cloud_off_rounded,
                  'No pudimos cargar los lugares ahora mismo.',
                  'Intenta de nuevo en unos segundos.',
                ),
                width,
              );
            }
            return SizedBox(
              height: 372,
              child: ListView.separated(
                controller: _placesScroll,
                scrollDirection: Axis.horizontal,
                clipBehavior: Clip.none,
                padding: EdgeInsets.fromLTRB(sidePad, 6, sidePad, 22),
                itemCount: pois.length + 1,
                separatorBuilder: (_, _) => const SizedBox(width: 20),
                itemBuilder: (context, i) {
                  if (i == pois.length) return _seeAllTile();
                  final poi = pois[i];
                  return PoiCard(
                    poi: poi,
                    width: 268,
                    height: 344,
                    variant: PoiCardVariant.standard,
                    onTap: () => _openPlace(poi),
                    onCreateRoute: widget.onRegisterClick,
                  );
                },
              ),
            );
          },
        ),
        if (isMobile)
          Padding(
            padding: EdgeInsets.symmetric(horizontal: hPad),
            child: Align(
              alignment: Alignment.centerLeft,
              child: _arrowLink('Ver todos los lugares', widget.onOpenPlaces),
            ),
          ),
      ],
    );
  }

  /// Muestra variada: hasta 2 lugares por categoría, 10 en total.
  List<Poi> _pickSample(List<Poi> all) {
    final perCat = <String, int>{};
    final out = <Poi>[];
    for (final p in all) {
      final n = perCat[p.category] ?? 0;
      if (n >= 2) continue;
      perCat[p.category] = n + 1;
      out.add(p);
      if (out.length >= 10) break;
    }
    return out;
  }

  Widget _seeAllTile() {
    return GestureDetector(
      onTap: widget.onOpenPlaces,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          width: 220,
          margin: const EdgeInsets.only(bottom: 28),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF1B4A51), OhtliColors.stormyTeal],
            ),
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.arrow_forward_rounded,
                  color: OhtliColors.stormyTeal,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'Ver todo el catálogo',
                style: GoogleFonts.outfit(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Filtra por categoría, precio o colonia.',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: Colors.white.withValues(alpha: 0.8),
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ───────────────────────── Cómo funciona ─────────────────────────

  Widget _buildHowItWorks(bool isMobile) {
    final steps = [
      (
        Icons.favorite_rounded,
        'Cuéntanos qué te mueve',
        'Un breve cuestionario sobre tus gustos, tu ritmo y tu presupuesto.',
        OhtliColors.xoconostle,
      ),
      (
        Icons.auto_awesome_rounded,
        'Ohtli traza tu ruta',
        'La IA elige lugares afines y ordena las paradas para aprovechar tu tiempo.',
        OhtliColors.stormyTeal,
      ),
      (
        Icons.auto_stories_rounded,
        'Vívela y compártela',
        'Convierte tu recorrido en una crónica con fotos para tus amigos o la comunidad.',
        OhtliColors.cempasuchil,
      ),
    ];
    final cards = [
      for (var i = 0; i < steps.length; i++)
        Container(
          padding: const EdgeInsets.all(26),
          decoration: BoxDecoration(
            color: OhtliColors.cardBg,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: OhtliColors.cardBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          steps[i].$4,
                          Color.lerp(steps[i].$4, Colors.black, 0.25)!,
                        ],
                      ),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: steps[i].$4.withValues(alpha: 0.3),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Icon(steps[i].$1, color: Colors.white, size: 24),
                  ),
                  const Spacer(),
                  Text(
                    '0${i + 1}',
                    style: GoogleFonts.outfit(
                      fontSize: 34,
                      fontWeight: FontWeight.w800,
                      color: OhtliColors.onyx.withValues(alpha: 0.08),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              Text(
                steps[i].$2,
                style: GoogleFonts.outfit(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: OhtliColors.onyx,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                steps[i].$3,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  color: OhtliColors.subtleText,
                  height: 1.55,
                ),
              ),
            ],
          ),
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionHeader(
          eyebrow: 'Cómo funciona',
          title: 'De la idea a la ruta en minutos',
          subtitle: 'Tres pasos para dejar de buscar y empezar a recorrer.',
          isMobile: isMobile,
        ),
        const SizedBox(height: 28),
        if (isMobile)
          ...cards.expand((c) => [c, const SizedBox(height: 14)])
        else
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < cards.length; i++) ...[
                  if (i > 0) const SizedBox(width: 18),
                  Expanded(child: cards[i]),
                ],
              ],
            ),
          ),
      ],
    );
  }

  // ───────────────────────── Crónicas públicas ─────────────────────────

  Widget _buildStories(bool isMobile, double width) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionHeader(
          eyebrow: 'Crónicas',
          title: 'Rutas que ya recorrió la comunidad',
          subtitle: 'Léelas sin cuenta y llévate ideas para tu próximo paseo.',
          isMobile: isMobile,
        ),
        const SizedBox(height: 28),
        FutureBuilder<List<_PublicTrip>>(
          future: _tripsFuture,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const SizedBox(
                height: 200,
                child: Center(
                  child: CircularProgressIndicator(
                    color: OhtliColors.stormyTeal,
                    strokeWidth: 2.4,
                  ),
                ),
              );
            }
            final trips = snap.data ?? const [];
            if (trips.isEmpty) {
              return _infoCard(
                Icons.auto_stories_rounded,
                'Pronto verás aquí las primeras crónicas públicas.',
                'Crea tu cuenta y sé de las primeras personas en publicar la tuya.',
              );
            }
            final columns = isMobile ? 1 : (width < 1100 ? 2 : 3);
            return LayoutBuilder(
              builder: (context, c) {
                const gap = 20.0;
                final cardW = (c.maxWidth - gap * (columns - 1)) / columns;
                return Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: trips
                      .map(
                        (t) => SizedBox(
                          width: cardW,
                          child: _StoryCard(
                            trip: t,
                            onTap: () =>
                                widget.onOpenPublicTrip(t.tripId, t.authorId),
                          ),
                        ),
                      )
                      .toList(),
                );
              },
            );
          },
        ),
      ],
    );
  }

  Widget _infoCard(IconData icon, String title, String message) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: OhtliColors.cardBg,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: OhtliColors.cardBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: OhtliColors.stormyTeal.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: OhtliColors.stormyTeal),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.outfit(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: OhtliColors.onyx,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  message,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: OhtliColors.subtleText,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ───────────────────────── Llamado final ─────────────────────────

  Widget _buildFinalCta(bool isMobile) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(isMobile ? 28 : 36),
      child: Stack(
        children: [
          const SizedBox(width: double.infinity),
          Positioned.fill(
            child: Image.network(
              CdmxPhotos.covers[3],
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    const Color(0xFF0A090C).withValues(alpha: 0.97),
                    const Color(0xFF0A090C).withValues(alpha: 0.88),
                    const Color(0xFF0A090C).withValues(alpha: 0.55),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: isMobile ? 24 : 56,
              vertical: isMobile ? 36 : 60,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '¿Listo para trazar\ntu propio camino?',
                  style: GoogleFonts.outfit(
                    fontSize: isMobile ? 30 : 44,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    height: 1.05,
                    letterSpacing: -1,
                  ),
                ),
                const SizedBox(height: 14),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: Text(
                    'Con tu cuenta recibes recomendaciones personalizadas, guardas tus lugares favoritos y creas rutas en segundos.',
                    style: GoogleFonts.inter(
                      fontSize: 15,
                      color: Colors.white.withValues(alpha: 0.82),
                      height: 1.55,
                    ),
                  ),
                ),
                const SizedBox(height: 26),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    ElevatedButton(
                      onPressed: widget.onRegisterClick,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: OhtliColors.cempasuchil,
                        foregroundColor: const Color(0xFF1A120B),
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 26,
                          vertical: 19,
                        ),
                        shape: const StadiumBorder(),
                        textStyle: GoogleFonts.outfit(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                      child: const Text('Crear cuenta gratis'),
                    ),
                    TextButton(
                      onPressed: widget.onLoginClick,
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 19,
                        ),
                        textStyle: GoogleFonts.inter(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                      child: const Text('Ya tengo cuenta'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ───────────────────────── Pie de página ─────────────────────────

  Widget _buildFooter(bool isMobile) {
    final links = Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        _footerLink('Lugares', widget.onOpenPlaces),
        if (widget.onOpenTerms != null)
          _footerLink('Términos y condiciones', widget.onOpenTerms!),
        _footerLink(
          'Ohtli Labs',
          () => _openExternal('https://lab.ohtli.quest'),
        ),
        _footerLink('API', () => _openExternal('https://api.ohtli.quest')),
      ],
    );
    final brand = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SvgPicture.asset(
          'assets/logo.svg',
          height: 20,
          colorFilter: ColorFilter.mode(OhtliColors.onyx, BlendMode.srcIn),
        ),
        const SizedBox(height: 8),
        Text(
          '© ${DateTime.now().year} Ohtli · Hecho en la Ciudad de México',
          style: GoogleFonts.inter(
            fontSize: 12.5,
            color: OhtliColors.subtleText,
          ),
        ),
      ],
    );
    return Container(
      padding: const EdgeInsets.only(top: 28),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: OhtliColors.cardBorder)),
      ),
      child: isMobile
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [brand, const SizedBox(height: 14), links],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [brand, const Spacer(), links],
            ),
    );
  }

  Widget _footerLink(String label, VoidCallback onTap) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: OhtliColors.subtleText,
        textStyle: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600),
      ),
      child: Text(label),
    );
  }
}

class _StoryCard extends StatefulWidget {
  final _PublicTrip trip;
  final VoidCallback onTap;

  const _StoryCard({required this.trip, required this.onTap});

  @override
  State<_StoryCard> createState() => _StoryCardState();
}

class _StoryCardState extends State<_StoryCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.trip;
    final cover = t.coverUrl.isNotEmpty
        ? t.coverUrl
        : CdmxPhotos.cover(t.tripId.hashCode);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 260),
          height: 300,
          transform: Matrix4.translationValues(0, _hover ? -4 : 0, 0),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(26),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: _hover ? 0.22 : 0.08),
                blurRadius: _hover ? 30 : 16,
                spreadRadius: -4,
                offset: Offset(0, _hover ? 18 : 8),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(26),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Container(color: OhtliColors.stormyTeal),
                AnimatedScale(
                  scale: _hover ? 1.05 : 1,
                  duration: const Duration(milliseconds: 600),
                  curve: Curves.easeOutCubic,
                  child: Image.network(
                    cover,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.85),
                      ],
                      stops: const [0.35, 1.0],
                    ),
                  ),
                ),
                Positioned(
                  top: 14,
                  left: 14,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.38),
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.2),
                        width: 0.8,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.auto_stories_rounded,
                          size: 13,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          'Crónica',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  left: 20,
                  right: 20,
                  bottom: 20,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.outfit(
                          fontSize: 21,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          height: 1.15,
                        ),
                      ),
                      if (t.description.trim().isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          t.description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            color: Colors.white.withValues(alpha: 0.8),
                            height: 1.4,
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Text(
                            'Leer crónica',
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: OhtliColors.cempasuchil,
                            ),
                          ),
                          const SizedBox(width: 6),
                          AnimatedSlide(
                            offset: Offset(_hover ? 0.3 : 0, 0),
                            duration: const Duration(milliseconds: 250),
                            child: const Icon(
                              Icons.arrow_forward_rounded,
                              size: 16,
                              color: OhtliColors.cempasuchil,
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
        ),
      ),
    );
  }
}

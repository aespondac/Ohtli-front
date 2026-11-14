// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:barcode/barcode.dart';
import 'package:share_plus/share_plus.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../../models/trip_model.dart';
import '../../services/trip_service.dart';
import '../../theme/colors.dart';
import '../../widgets/ohtli_place_photo_stack.dart';
import '../../widgets/ohtli_markdown_renderer.dart';
import '../../services/markdown_helpers.dart';
import '../../widgets/ohtli_sidebar.dart';
import '../../widgets/osrm_map_widget.dart';
import '../home_page.dart';
import '../account/account_management_page.dart';
import '../account/public_profile_page.dart';
import 'trip_editor_page.dart';
import '../error_404_page.dart';
import '../error_403_page.dart';
import '../../services/pdf_export_service.dart';
import '../../services/trip_transfers.dart';
import '../../utils/friendly_errors.dart';
import '../../services/poi_suggestion_service.dart';
import '../../widgets/place_details_form.dart';
import '../../services/trip_social_service.dart';
import '../../widgets/trip_social/block_social.dart';
import '../../widgets/trip_mini_map.dart';
import '../../widgets/reveal_on_scroll.dart';
import '../../theme/cdmx_photos.dart';
import '../../services/place_locator.dart';
import 'trip_sample.dart';
import 'trip_traveler_tools.dart';
import '../../config/admin.dart' show isSuperUser;

class TripViewerPage extends StatefulWidget {
  final Trip? trip;
  final String? tripId;
  final String? authorId;
  final bool isPublicLink;
  final VoidCallback? onLoginRedirect;
  final VoidCallback? onBackToDashboard;

  /// Vista previa desde el editor (E6): se muestran estos bloques sin leer Firestore.
  final List<TripSection>? previewSections;

  const TripViewerPage({
    super.key,
    this.trip,
    this.tripId,
    this.authorId,
    this.isPublicLink = false,
    this.onLoginRedirect,
    this.onBackToDashboard,
    this.previewSections,
  });

  @override
  State<TripViewerPage> createState() => _TripViewerPageState();
}

class _TripViewerPageState extends State<TripViewerPage> {
  Trip? _trip;
  List<TripSection> _sections = [];
  Map<String, dynamic>? _authorProfile;
  List<Map<String, dynamic>> _coAuthorsProfiles = [];
  String _authorActiveTitleName = 'Viajero';
  bool _isLoading = true;
  bool _isExportingPdf = false;
  String? _errorMessage;
  int? _errorCode;

  bool get _isPreview => widget.previewSections != null;

  // Lectura: progreso, índice y saltos a bloques (V2/V3)
  final ScrollController _scrollController = ScrollController();
  final ValueNotifier<double> _readProgress = ValueNotifier(0);
  final Map<String, GlobalKey> _blockKeys = {};
  final GlobalKey _mapKey = GlobalKey();
  String? _highlightedId;

  // Modo "estoy en el viaje" (V4): paradas visitadas en este dispositivo
  bool _tripMode = false;
  Set<String> _visited = {};

  // Reseña después del viaje (T5)
  bool _isSavingReview = false;

  // Notas y reacciones del grupo (solo miembros del viaje)
  TripSocialService? _social;
  StreamSubscription<List<TripNote>>? _notesSub;
  StreamSubscription<Map<String, Map<String, String>>>? _reactionsSub;
  List<TripNote> _notes = [];
  Map<String, Map<String, String>> _blockReactions = {};
  final Set<String> _openThreads = {};

  // Diseño de lectura: mensajes al margen (pantallas anchas) y panel lateral plegable.
  bool _marginLayout = false;
  bool _asideCollapsed = false;

  // Viaje de muestra (/muestra): etapa y papel simulados, mensajes en memoria.
  SampleStage _sampleStage = SampleStage.durante;
  bool _sampleAsMember = true;
  SampleTripSocialService? _sampleSocial;
  bool get _isSample => widget.tripId == kSampleTripId || widget.trip?.id == kSampleTripId;

  // Ubicaciones encontradas para paradas que no la traen guardada (solo para dibujarlas).
  final Map<String, (double, double)> _resolvedCoords = {};

  // Portadas tomadas de la base de imágenes de Ohtli (paradas vinculadas al catálogo).
  final Map<String, String> _catalogCovers = {};
  bool _locating = false;

  // Panel lateral flotante: ancho del panel abierto y del riel plegado, y el espacio que reserva.
  static const double _kAsideW = 340;
  static const double _kRailW = 56;
  static const double _kAsideGap = 14;
  double _asideInset = 0;

  Future<void> _exportPdf({bool printOnly = false}) async {
    if (_trip == null || _sections.isEmpty) return;

    setState(() => _isExportingPdf = true);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                printOnly
                    ? 'Preparando vista de impresión del itinerario...'
                    : 'Generando documento PDF editorial con código QR...',
                style: GoogleFonts.inter(fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
        backgroundColor: OhtliColors.stormyTeal,
        duration: const Duration(seconds: 3),
      ),
    );

    try {
      final authorName = _authorProfile?['displayName'] ?? 'Viajero Ohtli';
      final coAuthorNames = _trip!.coAuthorNames;
      final qrBaseUrl = '${Uri.base.origin}/?tripId=${_trip!.id}&authorId=${_trip!.userId}';

      if (printOnly) {
        await PdfExportService.printTripPdf(
          trip: _trip!,
          sections: _sections,
          authorName: authorName,
          coAuthors: coAuthorNames,
          qrBaseUrl: qrBaseUrl,
        );
      } else {
        await PdfExportService.downloadTripPdf(
          trip: _trip!,
          sections: _sections,
          authorName: authorName,
          coAuthors: coAuthorNames,
          qrBaseUrl: qrBaseUrl,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(friendlyError(e, fallback: 'No pudimos exportar el itinerario. Intenta de nuevo.')),
            backgroundColor: OhtliColors.xoconostle,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isExportingPdf = false);
      }
    }
  }



  bool _checkIsLocked(Trip t, bool isSurpriseForMe, bool isAuthor) {
    if (!isSurpriseForMe || isAuthor) {
      return false;
    }
    if (t.unlockOnPublish && t.status == 'published') {
      return false;
    }
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final unlockDate = uid != null ? t.surpriseUnlockDates[uid] : null;
    if (unlockDate == null) {
      return false;
    }
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final unlockDay = DateTime(unlockDate.year, unlockDate.month, unlockDate.day);
    return today.isBefore(unlockDay);
  }

  @override
  void initState() {
    super.initState();
    try {
      _asideCollapsed = html.window.localStorage['ohtli_trip_aside_collapsed'] == '1';
    } catch (_) {}
    _scrollController.addListener(_onScroll);
    _loadTripData();
  }

  @override
  void dispose() {
    _notesSub?.cancel();
    _reactionsSub?.cancel();
    _scrollController.dispose();
    _readProgress.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    _readProgress.value = pos.maxScrollExtent <= 0 ? 0 : (pos.pixels / pos.maxScrollExtent).clamp(0.0, 1.0);
  }

  // ---------------------------------------------------------------------------
  // Navegación entre bloques (V2/V3)
  // ---------------------------------------------------------------------------
  void _scrollToKey(GlobalKey key, {String? highlightId}) {
    final ctx = key.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeInOutCubic,
      alignment: 0.06,
    );
    if (highlightId != null) {
      setState(() => _highlightedId = highlightId);
      Future.delayed(const Duration(milliseconds: 1800), () {
        if (mounted && _highlightedId == highlightId) setState(() => _highlightedId = null);
      });
    }
  }

  void _scrollToBlock(String id) {
    final key = _blockKeys[id];
    if (key != null) _scrollToKey(key, highlightId: id);
  }

  String _blockLabel(TripSection s) {
    if (s is TransferSection) return describeTransfer(s);
    if (s is UnknownSection) return 'Bloque';
    if (s is PlaceSection) return s.title.trim().isEmpty ? 'Lugar sin nombre' : s.title.trim();
    final String md = s is TextSection ? s.markdownText : (s as TextImageSection).markdownText;
    if (s is TextSection && parseTableMarkdown(md) != null) return 'Tabla';
    final line = md
        .split('\n')
        .map((l) => l
            .replaceAll(RegExp(r'\[![A-Z]+\]'), '')
            .replaceAll(RegExp(r'[#>*_`~\[\]]'), '')
            .trim())
        .firstWhere((l) => l.isNotEmpty, orElse: () => '');
    return line.isEmpty ? 'Nota' : line;
  }

  void _showIndexSheet(bool isDark) {
    int n = 0;
    final numbers = <String, int>{};
    for (final s in _sections) {
      if (s is PlaceSection) numbers[s.id] = ++n;
    }
    final hasMap = _sections.any((s) => s is PlaceSection);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? const Color(0xFF1E1E22) : Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) {
        void go(VoidCallback action) {
          Navigator.of(ctx).pop();
          WidgetsBinding.instance.addPostFrameCallback((_) => action());
        }

        return ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.75),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
                  child: Text('Índice del viaje',
                      style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: isDark ? Colors.white : OhtliColors.onyx)),
                ),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.only(bottom: 16),
                    children: [
                      if (hasMap)
                        ListTile(
                          leading: const Icon(Icons.map_rounded, color: OhtliColors.stormyTeal),
                          title: Text('Ruta completa en el mapa', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
                          onTap: () => go(() => _showRouteModal(isDark)),
                        ),
                      ..._sections.where((s) => s is! TransferSection && s is! UnknownSection).map((s) {
                        final num = numbers[s.id];
                        final visited = _visited.contains(s.id);
                        return ListTile(
                          dense: num == null,
                          leading: num != null
                              ? CircleAvatar(
                                  radius: 13,
                                  backgroundColor: visited ? OhtliColors.stormyTeal : OhtliColors.xoconostle,
                                  child: visited
                                      ? const Icon(Icons.check_rounded, size: 15, color: Colors.white)
                                      : Text('$num', style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.bold, color: Colors.white)),
                                )
                              : Icon(Icons.notes_rounded, size: 18, color: isDark ? Colors.white54 : OhtliColors.subtleText),
                          title: Text(
                            _blockLabel(s),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                              fontWeight: num != null ? FontWeight.w600 : FontWeight.w400,
                              color: isDark ? Colors.white : OhtliColors.onyx,
                            ),
                          ),
                          subtitle: (s is PlaceSection && s.arrivalTime != null)
                              ? Text('${s.arrivalTime}${s.departureTime != null ? ' – ${s.departureTime}' : ''}',
                                  style: GoogleFonts.inter(fontSize: 12))
                              : null,
                          onTap: () => go(() => _scrollToBlock(s.id)),
                        );
                      }),
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

  // ---------------------------------------------------------------------------
  // Resumen (V1)
  // ---------------------------------------------------------------------------
  static double _haversineKm(double lat1, double lng1, double lat2, double lng2) {
    const r = 6371.0;
    double rad(double d) => d * math.pi / 180;
    final dLat = rad(lat2 - lat1);
    final dLng = rad(lng2 - lng1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(rad(lat1)) * math.cos(rad(lat2)) * math.sin(dLng / 2) * math.sin(dLng / 2);
    return 2 * r * math.asin(math.sqrt(a));
  }

  static int? _minutesOf(String? t) {
    if (t == null) return null;
    final m = RegExp(r'(\d{1,2}):(\d{2})').firstMatch(t);
    if (m == null) return null;
    return int.parse(m.group(1)!) * 60 + int.parse(m.group(2)!);
  }

  // ---------------------------------------------------------------------------
  // Modo "estoy en el viaje" (V4)
  // ---------------------------------------------------------------------------
  String get _visitedStorageKey => 'ohtli_trip_visited_${_trip?.id ?? ''}';

  void _loadVisited() {
    try {
      final raw = html.window.localStorage[_visitedStorageKey];
      if (raw != null) _visited = Set<String>.from(jsonDecode(raw) as List);
    } catch (_) {}
  }

  void _saveVisited() {
    try {
      html.window.localStorage[_visitedStorageKey] = jsonEncode(_visited.toList());
    } catch (_) {}
  }

  void _setTripMode(bool on) {
    if (on) _loadVisited();
    setState(() => _tripMode = on);
    if (on) {
      final next = _nextStop;
      if (next != null) WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBlock(next.id));
    }
  }

  void _toggleVisited(String id) {
    setState(() {
      if (!_visited.remove(id)) _visited.add(id);
    });
    _saveVisited();
  }

  PlaceSection? get _nextStop {
    for (final p in _sections.whereType<PlaceSection>()) {
      if (!_visited.contains(p.id)) return p;
    }
    return null;
  }

  void _openDirectionsTo(PlaceSection p) {
    final c = _coordsOf(p);
    final dest = c != null
        ? '${c.$1},${c.$2}'
        : Uri.encodeComponent('${p.title}, Ciudad de México');
    final t = transferBefore(_sections, _sections.indexOf(p));
    final travelMode = t != null ? transferModeOf(t.mode).googleTravelMode : 'walking';
    html.window.open('https://www.google.com/maps/dir/?api=1&destination=$dest&travelmode=$travelMode', '_blank');
  }

  /// Bloque de traslado en la lectura: un conector compacto entre paradas.
  Widget _buildTransferViewer(TransferSection t, bool isDark) {
    final mode = transferModeOf(t.mode);
    final i = _sections.indexOf(t);
    PlaceSection? from;
    PlaceSection? to;
    for (int k = i - 1; k >= 0; k--) {
      if (_sections[k] is PlaceSection) {
        from = _sections[k] as PlaceSection;
        break;
      }
    }
    for (int k = i + 1; k < _sections.length; k++) {
      if (_sections[k] is PlaceSection) {
        to = _sections[k] as PlaceSection;
        break;
      }
    }
    String loc(PlaceSection p) =>
        (p.lat != null && p.lng != null) ? '${p.lat},${p.lng}' : Uri.encodeComponent('${p.title}, Ciudad de México');
    final String? routeUrl = (from != null && to != null)
        ? 'https://www.google.com/maps/dir/?api=1&origin=${loc(from)}&destination=${loc(to)}&travelmode=${mode.googleTravelMode}'
        : null;
    final Color sub = isDark ? Colors.white60 : OhtliColors.subtleText;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 44,
          child: Column(
            children: [
              Container(width: 2, height: 10, color: OhtliColors.stormyTeal.withValues(alpha: 0.3)),
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: OhtliColors.stormyTeal.withValues(alpha: isDark ? 0.25 : 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(mode.icon, size: 19, color: OhtliColors.stormyTeal),
              ),
              Container(width: 2, height: 10, color: OhtliColors.stormyTeal.withValues(alpha: 0.3)),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      describeTransfer(t),
                      style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700, color: isDark ? Colors.white : OhtliColors.onyx),
                    ),
                    if (t.cost > 0)
                      Text('· \$${t.cost.toStringAsFixed(t.cost % 1 == 0 ? 0 : 2)} ${t.currency}',
                          style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: OhtliColors.stormyTeal)),
                    if (t.isEstimated)
                      Tooltip(
                        message: 'Calculado por Ohtli a partir de la ubicación de las paradas',
                        child: Text('· estimado', style: GoogleFonts.inter(fontSize: 12, color: sub)),
                      ),
                  ],
                ),
                if (t.notes.trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(t.notes.trim(), style: GoogleFonts.inter(fontSize: 13, height: 1.4, color: sub)),
                ],
                if (routeUrl != null && !_isPreview)
                  TextButton.icon(
                    onPressed: () => html.window.open(routeUrl, '_blank'),
                    style: TextButton.styleFrom(
                      foregroundColor: OhtliColors.stormyTeal,
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                    ),
                    icon: const Icon(Icons.open_in_new_rounded, size: 14),
                    label: Text('Ver ruta', style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600)),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTripModePanel(bool isDark, {bool embedded = false}) {
    final places = _sections.whereType<PlaceSection>().toList();
    final next = _nextStop;
    final done = places.where((p) => _visited.contains(p.id)).length;
    final Color fg = isDark ? Colors.white : OhtliColors.onyx;
    return Material(
      elevation: embedded ? 0 : 12,
      color: embedded ? Colors.transparent : (isDark ? const Color(0xFF1E1E22) : Colors.white),
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    next == null ? '¡Recorrido completo!' : 'Siguiente parada · ${places.indexOf(next) + 1} de ${places.length}',
                    style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: OhtliColors.stormyTeal),
                  ),
                ),
                Text('$done/${places.length}', style: GoogleFonts.inter(fontSize: 12, color: isDark ? Colors.white60 : OhtliColors.subtleText)),
                IconButton(
                  tooltip: 'Salir del modo viaje',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.close_rounded, size: 18),
                  onPressed: () => _setTripMode(false),
                ),
              ],
            ),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: places.isEmpty ? 0 : done / places.length,
                minHeight: 5,
                backgroundColor: OhtliColors.stormyTeal.withValues(alpha: 0.12),
                color: OhtliColors.stormyTeal,
              ),
            ),
            const SizedBox(height: 10),
            if (next == null)
              Padding(
                padding: const EdgeInsets.only(right: 8, bottom: 4),
                child: Text('Visitaste todas las paradas. Puedes desmarcar alguna desde su bloque.',
                    style: GoogleFonts.inter(fontSize: 13, color: fg)),
              )
            else ...[
              InkWell(
                onTap: () => _scrollToBlock(next.id),
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text(
                    '${next.title}${next.arrivalTime != null ? ' · ${next.arrivalTime}' : ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.outfit(fontSize: 17, fontWeight: FontWeight.bold, color: fg),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: () => _openDirectionsTo(next),
                    style: FilledButton.styleFrom(
                      backgroundColor: OhtliColors.stormyTeal,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.directions_walk_rounded, size: 18),
                    label: Text('Cómo llegar', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
                  ),
                  OutlinedButton.icon(
                    onPressed: () {
                      _toggleVisited(next.id);
                      final after = _nextStop;
                      if (after != null) _scrollToBlock(after.id);
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: OhtliColors.stormyTeal,
                      side: const BorderSide(color: OhtliColors.stormyTeal),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.check_rounded, size: 18),
                    label: Text('Ya la visité', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Miembros del viaje: notas, reacciones y panel lateral
  // ---------------------------------------------------------------------------
  /// Dueño, coautor o destinatario de la sorpresa (los mismos que ya pueden abrir el viaje privado).
  String? get _myUid => _isSample ? (_sampleAsMember ? kSampleMyUid : null) : FirebaseAuth.instance.currentUser?.uid;

  bool get _isMember {
    if (_isSample) return _sampleAsMember;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final t = _trip;
    if (uid == null || t == null) return false;
    return t.userId == uid || t.coAuthorIds.contains(uid) || t.surpriseTargetIds.contains(uid);
  }

  bool get _isPublicTrip => _trip != null && _trip!.status == 'published' && _trip!.visibility == 'public';

  /// Mensajes y reacciones visibles: para los miembros y, si el viaje es público, para cualquiera.
  bool get _socialVisible => _social != null && !_isPreview && _trip?.isReleaseNotes != true;

  /// Solo los miembros del viaje escriben mensajes y reaccionan.
  bool get _canInteract => _socialVisible && _isMember;

  void _startSocial() {
    _notesSub?.cancel();
    _reactionsSub?.cancel();
    _social = null;
    if (!mounted || _isPreview || _trip == null || _trip!.isReleaseNotes || !(_isMember || _isPublicTrip)) return;
    final TripSocialService social = _isSample
        ? (_sampleSocial ??= SampleTripSocialService(TripSample.notes(_sampleStage), TripSample.reactions))
        : TripSocialService(_trip!.userId, _trip!.id);
    _social = social;
    _notesSub = social.notesStream().listen(
      (n) {
        if (mounted) setState(() => _notes = n);
      },
      onError: (e) => debugPrint('Notas del viaje: $e'),
    );
    _reactionsSub = social.reactionsStream().listen(
      (r) {
        if (mounted) setState(() => _blockReactions = r);
      },
      onError: (e) => debugPrint('Reacciones del viaje: $e'),
    );
    if (mounted) setState(() {});
  }

  // ---------------------------------------------------------------------------
  // Viaje de muestra
  // ---------------------------------------------------------------------------
  void _loadSample() {
    final stage = _sampleStage;
    setState(() {
      _trip = TripSample.trip(stage);
      _sections = TripSample.sections(stage);
      _authorProfile = TripSample.author;
      _coAuthorsProfiles = TripSample.coAuthors;
      _visited = TripSample.visited(stage);
      _isLoading = false;
    });
    _startSocial();
  }

  void _setSampleStage(SampleStage stage) {
    if (stage == _sampleStage) return;
    _sampleStage = stage;
    if (_tripMode && stage != SampleStage.durante) _tripMode = false;
    _loadSample();
  }

  void _setSampleRole(bool member) {
    if (member == _sampleAsMember) return;
    setState(() => _sampleAsMember = member);
    _startSocial();
  }

  void _sampleNotice(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text, style: GoogleFonts.inter())));
  }

  /// Lleva la muestra (etapa "Durante", con fecha de hoy) a la cuenta de quien la ve,
  /// reemplazando un viaje suyo o creando uno nuevo. Escribe con su propia sesión.
  Future<void> _bringSampleToAccount() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final isDark = _dark;
    List<Trip> mine = const [];
    try {
      mine = (await TripService().getTripsStream(user.uid).first).where((t) => !t.isReleaseNotes).toList();
    } catch (_) {}
    if (!mounted) return;
    String target = '';
    for (final t in mine) {
      if (t.title.toLowerCase().contains('tacos')) {
        target = t.id;
        break;
      }
    }
    final Color fg = isDark ? Colors.white : const Color(0xFF1F2A2A);
    final Color sub = isDark ? Colors.white60 : OhtliColors.subtleText;
    final String? chosen = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) {
          final replacing = target.isNotEmpty;
          final String replacedTitle = replacing ? mine.firstWhere((t) => t.id == target).title : '';
          return AlertDialog(
            backgroundColor: isDark ? const Color(0xFF1E1E22) : Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
            title: Text('Llevar la muestra a tu cuenta', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: fg)),
            content: SizedBox(
              width: 460,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Se guarda como un viaje real con fecha de hoy, en la etapa «Durante», para probar todas las herramientas.',
                      style: GoogleFonts.inter(fontSize: 13, height: 1.4, color: sub)),
                  const SizedBox(height: 12),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 260),
                    child: SingleChildScrollView(
                      child: Column(
                        children: [
                          RadioListTile<String>(
                            value: '',
                            groupValue: target,
                            onChanged: (v) => setState(() => target = v ?? ''),
                            dense: true,
                            activeColor: OhtliColors.stormyTeal,
                            title: Text('Crear un viaje nuevo', style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: fg)),
                          ),
                          for (final t in mine)
                            RadioListTile<String>(
                              value: t.id,
                              groupValue: target,
                              onChanged: (v) => setState(() => target = v ?? ''),
                              dense: true,
                              activeColor: OhtliColors.stormyTeal,
                              title: Text('Reemplazar «${t.title}»', style: GoogleFonts.inter(color: fg)),
                            ),
                        ],
                      ),
                    ),
                  ),
                  if (replacing) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: Colors.redAccent.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12)),
                      child: Text(
                        'Se borrará el contenido de «$replacedTitle» (paradas, textos y fotos del plan) y no se puede deshacer. '
                        'Se conservan quiénes son coautores y su visibilidad; los mensajes anteriores dejarán de verse.',
                        style: GoogleFonts.inter(fontSize: 12.5, height: 1.4, color: isDark ? const Color(0xFFFF8A80) : Colors.red.shade700),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: replacing ? Colors.redAccent : OhtliColors.stormyTeal, foregroundColor: Colors.white),
                onPressed: () => Navigator.pop(ctx, replacing ? target : '__nuevo__'),
                child: Text(replacing ? 'Reemplazar' : 'Crear viaje'),
              ),
            ],
          );
        },
      ),
    );
    if (chosen == null || !mounted) return;

    final sample = TripSample.trip(SampleStage.durante);
    final sections = TripSample.sections(SampleStage.durante);
    final trips = FirebaseFirestore.instance.collection('users').doc(user.uid).collection('trips');
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    try {
      String id;
      if (chosen == '__nuevo__') {
        id = trips.doc().id;
        final trip = Trip(
          id: id,
          userId: user.uid,
          title: sample.title,
          description: sample.description,
          coverUrl: sample.coverUrl,
          status: 'published',
          visibility: 'private',
          createdAt: now,
          updatedAt: now,
          travelDate: today,
        );
        // Escritura directa (sin el aviso de "nueva publicación" a seguidores).
        await trips.doc(id).set(trip.toMap());
      } else {
        id = chosen;
        await trips.doc(id).update({
          'title': sample.title,
          'description': sample.description,
          'coverUrl': sample.coverUrl,
          'travelDate': Timestamp.fromDate(today),
          'updatedAt': Timestamp.fromDate(now),
          'reviewedAt': FieldValue.delete(),
        });
      }
      await TripService().updateTripContent(user.uid, id, TripContent(sections: sections));
      try {
        html.window.localStorage.remove('ohtli_trip_visited_$id');
      } catch (_) {}
      if (!mounted) return;
      _notice('Listo. Abriendo tu viaje…');
      html.window.location.assign('${Uri.base.origin}/?tripId=$id&authorId=${user.uid}');
    } catch (e) {
      _notice(friendlyError(e, fallback: 'No se pudo guardar el viaje en tu cuenta.'));
    }
  }

  /// Barra de la muestra: cambia la etapa del viaje y el papel de quien lo ve.
  Widget _buildSampleBar(bool isDark, {required bool compact}) {
    final Color bg = isDark ? const Color(0xFF1E1E22) : Colors.white;
    final Color fg = isDark ? Colors.white : const Color(0xFF1F2A2A);
    Widget seg<T>(List<(T, String)> options, T value, ValueChanged<T> onChanged) => Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: isDark ? Colors.white.withValues(alpha: 0.06) : const Color(0xFFF1F4F3),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final o in options)
                GestureDetector(
                  onTap: () => onChanged(o.$1),
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: o.$1 == value ? OhtliColors.stormyTeal : Colors.transparent,
                        borderRadius: BorderRadius.circular(17),
                      ),
                      child: Text(o.$2,
                          style: GoogleFonts.inter(
                              fontSize: compact ? 11.5 : 12,
                              fontWeight: FontWeight.w700,
                              color: o.$1 == value ? Colors.white : fg.withValues(alpha: 0.75))),
                    ),
                  ),
                ),
            ],
          ),
        );
    final stageSeg = seg<SampleStage>([for (final st in SampleStage.values) (st, st.label)], _sampleStage, _setSampleStage);
    final roleSeg = seg<bool>(const [(true, 'Miembro'), (false, 'Visitante')], _sampleAsMember, _setSampleRole);
    final badge = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.science_outlined, size: 16, color: OhtliColors.cempasuchil),
        const SizedBox(width: 6),
        Text('Viaje de muestra', style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w800, color: fg)),
      ],
    );
    return Material(
      color: bg,
      elevation: 6,
      shadowColor: Colors.black.withValues(alpha: 0.25),
      borderRadius: BorderRadius.circular(26),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: compact ? 5 : 14, vertical: compact ? 5 : 7),
        // En el teléfono cabe en una línea sin la etiqueta.
        child: compact
            ? Row(mainAxisSize: MainAxisSize.min, children: [stageSeg, const SizedBox(width: 5), roleSeg])
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  badge,
                  const SizedBox(width: 14),
                  stageSeg,
                  const SizedBox(width: 8),
                  roleSeg,
                  // Solo para la cuenta de pruebas de Ohtli: guardar la muestra como viaje real.
                  if (isSuperUser()) ...[
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: _bringSampleToAccount,
                      style: FilledButton.styleFrom(
                        backgroundColor: OhtliColors.xoconostle,
                        foregroundColor: Colors.white,
                        visualDensity: VisualDensity.compact,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      icon: const Icon(Icons.download_rounded, size: 16),
                      label: Text('Llevar a mi cuenta', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700)),
                    ),
                  ],
                ],
              ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Ubicaciones para el mapa
  // ---------------------------------------------------------------------------
  (double, double)? _coordsOf(PlaceSection p) =>
      (p.lat != null && p.lng != null) ? (p.lat!, p.lng!) : _resolvedCoords[p.id];

  Future<void> _resolveCatalogCovers() async {
    for (final p in _sections.whereType<PlaceSection>()) {
      if ((p.coverUrl ?? '').isNotEmpty || p.poiId == null || _catalogCovers.containsKey(p.id)) continue;
      final url = await PlaceLocator.catalogPhoto(p);
      if (!mounted) return;
      if (url != null) setState(() => _catalogCovers[p.id] = url);
    }
  }

  /// Portada de la parada: la que eligieron los viajeros, la del catálogo o, si no hay,
  /// una foto de referencia de la CDMX según el tipo de lugar. [generic] marca esta última.
  ({String url, bool generic}) _coverFor(PlaceSection p) {
    if ((p.coverUrl ?? '').isNotEmpty) return (url: p.coverUrl!, generic: false);
    final cat = _catalogCovers[p.id];
    if (cat != null) return (url: cat, generic: false);
    final seed = p.id.codeUnits.fold<int>(0, (a, c) => a + c);
    return (url: CdmxPhotos.forCategory(p.title, seed), generic: true);
  }

  Widget _placeCover(PlaceSection p, bool isDark, double height) {
    final cover = _coverFor(p);
    final seed = p.id.codeUnits.fold<int>(0, (a, c) => a + c);
    return SizedBox(
      height: height,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image(
            image: _getImageProvider(cover.url),
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Image.network(
              CdmxPhotos.cover(seed),
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => ColoredBox(color: isDark ? const Color(0xFF26343A) : OhtliColors.cantera),
            ),
          ),
          // Se funde suave con la tarjeta.
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: const [0.55, 1],
                colors: [Colors.transparent, Colors.black.withValues(alpha: 0.22)],
              ),
            ),
          ),
          if (cover.generic)
            Positioned(
              left: 10,
              top: 10,
              child: Tooltip(
                message: 'Imagen de la CDMX: este lugar aún no tiene portada propia.',
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.45), borderRadius: BorderRadius.circular(8)),
                  child: Text('Foto de referencia', style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.white)),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _resolveMissingCoords() async {
    _resolveCatalogCovers();
    final missing = _sections.whereType<PlaceSection>().where((p) => _coordsOf(p) == null).toList();
    if (missing.isEmpty) return;
    setState(() => _locating = true);
    for (final p in missing) {
      final found = await PlaceLocator.locate(p);
      if (!mounted) return;
      if (found != null) setState(() => _resolvedCoords[p.id] = found);
    }
    if (mounted) setState(() => _locating = false);
  }

  Map<String, String> get _memberNames {
    final names = <String, String>{};
    if (_trip != null) names[_trip!.userId] = (_authorProfile?['displayName'] ?? 'Autor').toString();
    for (final c in _coAuthorsProfiles) {
      names[c['uid'].toString()] = (c['displayName'] ?? 'Viajero').toString();
    }
    for (final n in _notes) {
      names.putIfAbsent(n.authorId, () => n.authorName);
    }
    return names;
  }

  String get _myDisplayName {
    if (_isSample) return kSampleMyName;
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) return 'Viajero';
    final fromProfile = _memberNames[u.uid];
    if (fromProfile != null && fromProfile.isNotEmpty && fromProfile != 'Autor') return fromProfile;
    if (u.displayName != null && u.displayName!.trim().isNotEmpty) return u.displayName!.trim();
    return 'Viajero';
  }

  Future<void> _guardSocial(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyError(e, fallback: 'No se pudo guardar. Revisa tu conexión.'), style: GoogleFonts.inter())),
      );
    }
  }

  Future<void> _reactToBlock(String blockId, String? kind) async {
    final uid = _myUid;
    if (uid == null || _social == null) return;
    // Optimista: se ve al instante; el stream confirma.
    setState(() {
      final m = Map<String, String>.from(_blockReactions[blockId] ?? const {});
      if (kind == null) {
        m.remove(uid);
      } else {
        m[uid] = kind;
      }
      _blockReactions = {..._blockReactions, blockId: m};
    });
    await _guardSocial(() => _social!.reactToBlock(blockId, uid, kind));
  }

  Future<void> _confirmDeleteNote(TripNote note) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('¿Borrar la nota?', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
        content: Text('Se borrará para todos los miembros del viaje.', style: GoogleFonts.inter(fontSize: 14)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Borrar'),
          ),
        ],
      ),
    );
    if (ok == true) await _guardSocial(() => _social!.deleteNote(note.id));
  }

  String _blockLabelById(String id) {
    for (final s in _sections) {
      if (s.id == id) return _blockLabel(s);
    }
    return 'un bloque';
  }

  void _openThread(String blockId) {
    setState(() => _openThreads.add(blockId));
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBlock(blockId));
  }

  // ---------------------------------------------------------------------------
  // Herramientas del viajero (dueño y coautores; en la muestra, en memoria)
  // ---------------------------------------------------------------------------
  bool get _canEditContent {
    if (_isSample) return _sampleAsMember;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final t = _trip;
    if (uid == null || t == null || t.isReleaseNotes || _isPreview) return false;
    return t.userId == uid || t.coAuthorIds.contains(uid);
  }

  /// Desde el día del viaje (o si no tiene fecha) ya se registran cosas del camino.
  bool get _tripStarted {
    final d = _trip?.travelDate;
    if (d == null) return true;
    final now = DateTime.now();
    return !DateTime(d.year, d.month, d.day).isAfter(DateTime(now.year, now.month, now.day));
  }

  bool get _tripIsToday {
    final d = _trip?.travelDate;
    final now = DateTime.now();
    return d != null && d.year == now.year && d.month == now.month && d.day == now.day;
  }

  static String _hhmm(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  String _newSectionId(String tag) => 'sec_${DateTime.now().millisecondsSinceEpoch}_$tag';
  bool get _dark => OhtliSettings.instance.isDarkMode;

  /// Parada en curso: donde ya llegaron y aún no salen; si no, la siguiente por visitar.
  PlaceSection? get _currentStop {
    final places = _sections.whereType<PlaceSection>().toList();
    for (final p in places.reversed) {
      if (p.arrivedAt != null && p.leftAt == null) return p;
    }
    for (final p in places) {
      if (p.arrivedAt == null && !_visited.contains(p.id)) return p;
    }
    return null;
  }

  List<BlockOption> get _blockOptions => [
        for (final s in _sections)
          if (s is! UnknownSection) (id: s.id, label: _blockLabel(s), isPlace: s is PlaceSection),
      ];

  String get _defaultAfterId => _currentStop?.id ?? (_sections.isNotEmpty ? _sections.last.id : '');

  void _notice(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text, style: GoogleFonts.inter())));
  }

  /// Aplica un cambio al contenido: lee la versión guardada (por si otro viajero cambió algo),
  /// lo aplica y la guarda. En la muestra solo cambia en memoria.
  Future<bool> _changeContent(List<TripSection> Function(List<TripSection> sections) change, {String? done}) async {
    final t = _trip;
    if (t == null) return false;
    if (_isSample) {
      setState(() => _sections = change(List.of(_sections)));
      if (done != null) _notice('$done. En la muestra no se guarda.');
      return true;
    }
    try {
      final saved = await TripService().getTripContent(t.userId, t.id);
      final next = change(List.of(saved?.sections ?? _sections));
      await TripService().updateTripContent(t.userId, t.id, TripContent(sections: next));
      if (!mounted) return true;
      setState(() => _sections = next);
      if (done != null) _notice(done);
      return true;
    } catch (e) {
      _notice(friendlyError(e, fallback: 'No se pudo guardar. Revisa tu conexión.'));
      return false;
    }
  }

  List<TripSection> _updatePlace(List<TripSection> list, String id, PlaceSection Function(PlaceSection p) f) =>
      [for (final s in list) (s is PlaceSection && s.id == id) ? f(s) : s];

  List<TripSection> _insertAfter(List<TripSection> list, String afterId, TripSection section) {
    final i = list.indexWhere((s) => s.id == afterId);
    return List.of(list)..insert(i < 0 ? list.length : i + 1, section);
  }

  void _scrollSoon(String id) => WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBlock(id));

  Future<void> _markArrival(PlaceSection p) async {
    final now = _hhmm(DateTime.now());
    setState(() => _visited.add(p.id));
    _saveVisited();
    await _changeContent((l) => _updatePlace(l, p.id, (x) => x.copyWith(arrivedAt: now)), done: 'Llegada a ${p.title} a las $now');
  }

  Future<void> _markLeave(PlaceSection p) async {
    final now = _hhmm(DateTime.now());
    await _changeContent((l) => _updatePlace(l, p.id, (x) => x.copyWith(leftAt: now)), done: 'Salida de ${p.title} a las $now');
  }

  /// ¿En qué parada? La parada en curso va primero.
  Future<PlaceSection?> _chooseStop(String title) {
    final places = _sections.whereType<PlaceSection>().toList();
    final current = _currentStop;
    if (current != null) {
      places
        ..remove(current)
        ..insert(0, current);
    }
    final isDark = _dark;
    return showDialog<PlaceSection>(
      context: context,
      builder: (ctx) => SimpleDialog(
        backgroundColor: isDark ? const Color(0xFF1E1E22) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(title, style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: isDark ? Colors.white : const Color(0xFF1F2A2A))),
        children: [
          for (final p in places)
            SimpleDialogOption(
              onPressed: () => Navigator.of(ctx).pop(p),
              child: Row(
                children: [
                  Icon(p.unplanned ? Icons.alt_route_rounded : Icons.place_rounded, size: 18, color: OhtliColors.stormyTeal),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(p.title.isEmpty ? 'Parada sin nombre' : p.title,
                        style: GoogleFonts.inter(fontSize: 14, color: isDark ? Colors.white : const Color(0xFF1F2A2A))),
                  ),
                  if (identical(p, current)) Text('ahora', style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w700, color: OhtliColors.cempasuchil)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// Sube una foto a la carpeta de quien la toma (las reglas solo le permiten escribir en la suya).
  Future<String?> _uploadPhoto(String dataUrl) async {
    if (_isSample) return dataUrl;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final t = _trip;
    if (uid == null || t == null) return null;
    final bytes = base64Decode(dataUrl.split(',').last);
    final ref = FirebaseStorage.instance.ref('users/$uid/trips/${t.id}/viajeros/${DateTime.now().millisecondsSinceEpoch}.jpg');
    await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
    return ref.getDownloadURL();
  }

  Future<void> _addPhoto() async {
    final p = await _chooseStop('¿De qué parada es la foto?');
    if (p == null || !mounted) return;
    final dataUrl = await pickAndCropPhoto(context);
    if (dataUrl == null || !mounted) return;
    try {
      if (!_isSample) _notice('Subiendo foto…');
      final url = await _uploadPhoto(dataUrl);
      if (url == null) return;
      final ok = await _changeContent(
        (l) => _updatePlace(
            l, p.id, (x) => x.mainPhotoUrl.isEmpty ? x.copyWith(mainPhotoUrl: url) : x.copyWith(secondaryPhotoUrls: [url, ...x.secondaryPhotoUrls])),
        done: 'Foto agregada a ${p.title}',
      );
      if (ok) _scrollSoon(p.id);
    } catch (e) {
      _notice(friendlyError(e, fallback: 'No se pudo subir la foto.'));
    }
  }

  Future<void> _setCover() async {
    final p = await _chooseStop('¿A qué parada le cambias la portada?');
    if (p == null || !mounted) return;
    final dataUrl = await pickAndCropPhoto(context, aspectRatio: 16 / 9);
    if (dataUrl == null || !mounted) return;
    try {
      if (!_isSample) _notice('Subiendo portada…');
      final url = await _uploadPhoto(dataUrl);
      if (url == null) return;
      final ok = await _changeContent((l) => _updatePlace(l, p.id, (x) => x.copyWith(coverUrl: url)), done: 'Portada de ${p.title} actualizada');
      if (ok) _scrollSoon(p.id);
    } catch (e) {
      _notice(friendlyError(e, fallback: 'No se pudo subir la portada.'));
    }
  }

  Future<void> _addRealCost() async {
    final p = await _chooseStop('¿En qué parada?');
    if (p == null || !mounted) return;
    final v = await askRealCost(context, placeName: p.title, current: p.realCost, estimated: p.cost, isDark: _dark);
    if (v == null) return;
    final ok = await _changeContent((l) => _updatePlace(l, p.id, (x) => x.copyWith(realCost: v)), done: 'Gasto real guardado');
    if (ok) _scrollSoon(p.id);
  }

  Future<void> _addDetour() async {
    final d = await askDetour(context, options: _blockOptions, initialAfter: _defaultAfterId, isDark: _dark);
    if (d == null) return;
    final section = PlaceSection(
      id: _newSectionId('desvio'),
      title: d.name,
      description: d.note,
      rating: 0,
      mainPhotoUrl: '',
      secondaryPhotoUrls: const [],
      unplanned: true,
      arrivedAt: _tripIsToday ? _hhmm(DateTime.now()) : null,
    );
    final ok = await _changeContent((l) => _insertAfter(l, d.afterId, section), done: 'Desvío agregado');
    if (ok) {
      _resolveMissingCoords();
      _scrollSoon(section.id);
    }
  }

  Future<void> _addTransfer() async {
    // Por omisión, la última parada de la que salieron (el traslado parte de ahí).
    String from = _defaultAfterId;
    for (final p in _sections.whereType<PlaceSection>()) {
      if (p.leftAt != null) from = p.id;
    }
    final d = await askTransfer(context, options: _blockOptions, initialAfter: from, isDark: _dark);
    if (d == null) return;
    String id = _newSectionId('traslado');
    final ok = await _changeContent((l) {
      final i = l.indexWhere((s) => s.id == d.afterId);
      final next = (i >= 0 && i + 1 < l.length) ? l[i + 1] : null;
      // Si ya había un traslado (p. ej. estimado), se reemplaza por el real.
      if (next is TransferSection) id = next.id;
      final t = TransferSection(
        id: id,
        mode: d.mode,
        durationMins: d.minutes,
        distanceKm: next is TransferSection ? next.distanceKm : null,
        cost: d.cost,
        notes: d.note,
        isEstimated: false,
      );
      if (next is TransferSection) return List.of(l)..[i + 1] = t;
      return _insertAfter(l, d.afterId, t);
    }, done: 'Traslado guardado');
    if (ok) _scrollSoon(id);
  }

  Future<void> _addContentBlock(BlockKind kind) async {
    final d = await askBlock(context, kind: kind, options: _blockOptions, initialAfter: _defaultAfterId, isDark: _dark);
    if (d == null) return;
    try {
      final TripSection section;
      if (kind == BlockKind.image) {
        if (!_isSample) _notice('Subiendo imagen…');
        final url = await _uploadPhoto(d.imageDataUrl!);
        if (url == null) return;
        section = TextImageSection(id: _newSectionId('imagen'), markdownText: d.markdown, imageUrl: url, layout: 'right');
      } else {
        section = TextSection(id: _newSectionId(kind.name), markdownText: d.markdown);
      }
      final label = switch (kind) { BlockKind.text => 'Texto', BlockKind.note => 'Nota', BlockKind.table => 'Tabla', BlockKind.image => 'Imagen' };
      final ok = await _changeContent((l) => _insertAfter(l, d.afterId, section), done: '$label agregada');
      if (ok) _scrollSoon(section.id);
    } catch (e) {
      _notice(friendlyError(e, fallback: 'No se pudo guardar.'));
    }
  }

  /// Tarjeta del panel: "Llegué / Ya me voy" en la parada en curso y la rejilla de herramientas.
  Widget _buildTravelerToolsCard(bool isDark, {VoidCallback? onDone}) {
    final bool started = _tripStarted;
    final PlaceSection? current = started ? _currentStop : null;
    final Color fg = isDark ? Colors.white : const Color(0xFF1F2A2A);
    final Color sub = isDark ? Colors.white60 : OhtliColors.subtleText;
    void run(Future<void> Function() f) {
      onDone?.call();
      f();
    }

    final foto = (Icons.photo_camera_rounded, 'Foto', () => run(_addPhoto));
    final portada = (Icons.wallpaper_rounded, 'Portada', () => run(_setCover));
    final precio = (Icons.payments_rounded, 'Precio real', () => run(_addRealCost));
    final desvio = (Icons.alt_route_rounded, 'Desvío', () => run(_addDetour));
    final traslado = (Icons.route_rounded, 'Traslado', () => run(_addTransfer));
    final texto = (Icons.notes_rounded, 'Texto', () => run(() => _addContentBlock(BlockKind.text)));
    final imagen = (Icons.image_rounded, 'Imagen', () => run(() => _addContentBlock(BlockKind.image)));
    final tabla = (Icons.table_chart_rounded, 'Tabla', () => run(() => _addContentBlock(BlockKind.table)));
    final nota = (Icons.sticky_note_2_rounded, 'Nota', () => run(() => _addContentBlock(BlockKind.note)));
    // Todo está disponible siempre; antes del viaje van primero las de planear.
    final List<(IconData, String, VoidCallback)> ordered = started
        ? [foto, portada, precio, desvio, traslado, texto, imagen, tabla, nota]
        : [portada, texto, imagen, tabla, nota, traslado, foto, precio, desvio];

    return _panelCard(isDark: isDark, icon: Icons.backpack_rounded, title: 'HERRAMIENTAS DEL VIAJERO', children: [
      if (current != null) ...[
        Text(current.arrivedAt == null ? 'Siguiente parada' : 'Están en', style: GoogleFonts.inter(fontSize: 11.5, color: sub)),
        const SizedBox(height: 2),
        Text(current.title.isEmpty ? 'Parada sin nombre' : current.title,
            maxLines: 2, overflow: TextOverflow.ellipsis, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700, color: fg)),
        if (current.arrivedAt != null)
          Text('Llegaron a las ${current.arrivedAt}', style: GoogleFonts.inter(fontSize: 12, color: sub)),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: current.arrivedAt == null ? () => run(() => _markArrival(current)) : null,
                style: FilledButton.styleFrom(
                  backgroundColor: OhtliColors.stormyTeal,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.flag_rounded, size: 17),
                label: Text('Llegué', style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: current.arrivedAt != null && current.leftAt == null ? () => run(() => _markLeave(current)) : null,
                style: OutlinedButton.styleFrom(
                  foregroundColor: isDark ? Color.lerp(OhtliColors.stormyTeal, Colors.white, 0.5) : OhtliColors.stormyTeal,
                  side: BorderSide(color: OhtliColors.stormyTeal.withValues(alpha: current.arrivedAt != null ? 1 : 0.3)),
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.logout_rounded, size: 17),
                label: Text('Ya me voy', style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
      ] else if (!started) ...[
        Text('Preparen el viaje: agreguen notas, tablas o fotos. Llegué y Ya me voy aparecen el día del viaje.',
            style: GoogleFonts.inter(fontSize: 12.5, height: 1.4, color: sub)),
        const SizedBox(height: 12),
      ],
      LayoutBuilder(builder: (context, box) {
        final double w = ((box.maxWidth - 3 * 8) / 4).floorToDouble();
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final t in ordered)
              Material(
                color: isDark ? Colors.white.withValues(alpha: 0.05) : const Color(0xFFF3F6F5),
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: t.$3,
                  child: SizedBox(
                    width: w,
                    height: 64,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(t.$1, size: 21, color: isDark ? Color.lerp(OhtliColors.stormyTeal, Colors.white, 0.45) : OhtliColors.stormyTeal),
                        const SizedBox(height: 5),
                        Text(t.$2,
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.w600, color: fg)),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      }),
    ]);
  }

  Widget _placeBadge(IconData icon, String text, bool isDark, {bool amber = false}) {
    final Color fg = amber
        ? (isDark ? const Color(0xFFFBBF24) : const Color(0xFFB45309))
        : (isDark ? Color.lerp(OhtliColors.stormyTeal, Colors.white, 0.5)! : OhtliColors.stormyTeal);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: amber
            ? (isDark ? const Color(0xFF332711) : const Color(0xFFFFFBEB))
            : OhtliColors.stormyTeal.withValues(alpha: isDark ? 0.18 : 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: amber
              ? (isDark ? const Color(0xFFFBBF24).withValues(alpha: 0.25) : const Color(0xFFFDE68A))
              : OhtliColors.stormyTeal.withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: amber ? Colors.amber : fg),
          const SizedBox(width: 6),
          Text(text, style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.w700, color: fg)),
        ],
      ),
    );
  }

  Widget _panelCard({required bool isDark, required IconData icon, required String title, required List<Widget> children}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E22) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: isDark ? Colors.white10 : OhtliColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: OhtliColors.stormyTeal),
              const SizedBox(width: 7),
              Text(title,
                  style: GoogleFonts.inter(
                      fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.3, color: isDark ? Colors.white70 : OhtliColors.subtleText)),
            ],
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  Widget _memberAvatar(String name, String? photo, bool isDark, {String? badge}) {
    return Tooltip(
      message: badge != null ? '$name · $badge' : name,
      child: CircleAvatar(
        radius: 17,
        backgroundColor: OhtliColors.stormyTeal.withValues(alpha: 0.16),
        backgroundImage: (photo != null && photo.isNotEmpty) ? NetworkImage(photo) : null,
        child: (photo == null || photo.isEmpty)
            ? Text(name.isNotEmpty ? name.characters.first.toUpperCase() : '?',
                style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: OhtliColors.stormyTeal))
            : null,
      ),
    );
  }

  /// Contenido del panel privado. [onDone] cierra la hoja en móvil antes de navegar.
  List<Widget> _buildMemberPanelCards(bool isDark, bool canEdit, {VoidCallback? onDone}) {
    final t = _trip!;
    final Color fg = isDark ? Colors.white : OhtliColors.onyx;
    final Color sub = isDark ? Colors.white60 : OhtliColors.subtleText;
    final places = _sections.whereType<PlaceSection>().toList();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final cards = <Widget>[];

    // Viajeros
    final invited = t.surpriseTargetIds.where((id) => id != t.userId && !t.coAuthorIds.contains(id)).length;
    cards.add(_panelCard(isDark: isDark, icon: Icons.groups_rounded, title: 'VIAJEROS', children: [
      Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          _memberAvatar((_authorProfile?['displayName'] ?? 'Autor').toString(), _authorProfile?['photoURL'] as String?, isDark, badge: 'autor'),
          for (final c in _coAuthorsProfiles)
            _memberAvatar((c['displayName'] ?? 'Viajero').toString(), c['photoURL'] as String?, isDark, badge: 'coautor'),
          if (invited > 0)
            CircleAvatar(
              radius: 17,
              backgroundColor: OhtliColors.cempasuchil.withValues(alpha: 0.16),
              child: Text('+$invited', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: OhtliColors.cempasuchil)),
            ),
        ],
      ),
      const SizedBox(height: 10),
      Text('Solo los miembros escriben y reaccionan; quien lea el viaje ve los mensajes.', style: GoogleFonts.inter(fontSize: 12, height: 1.4, color: sub)),
    ]));

    // Herramientas del viajero (dueño y coautores)
    if (_canEditContent) cards.add(_buildTravelerToolsCard(isDark, onDone: onDone));

    // Modo viaje
    if (places.isNotEmpty) {
      cards.add(_panelCard(isDark: isDark, icon: Icons.near_me_rounded, title: 'MODO VIAJE', children: [
        if (_tripMode && onDone == null)
          _buildTripModePanel(isDark, embedded: true)
        else ...[
          Text(_tripMode ? 'El modo viaje está activo.' : 'Marca las paradas que visitas y abre la ruta a la siguiente.',
              style: GoogleFonts.inter(fontSize: 13, height: 1.4, color: fg)),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () {
                onDone?.call();
                _setTripMode(!_tripMode);
              },
              style: FilledButton.styleFrom(
                backgroundColor: _tripMode ? OhtliColors.xoconostle : OhtliColors.stormyTeal,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: Icon(_tripMode ? Icons.stop_circle_outlined : Icons.near_me_rounded, size: 18),
              label: Text(_tripMode ? 'Salir del modo viaje' : 'Estoy en el viaje', style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ]));
    }

    // Calificar
    if (places.isNotEmpty && t.travelDate != null) {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final day = DateTime(t.travelDate!.year, t.travelDate!.month, t.travelDate!.day);
      // Desde el día del viaje ya se puede calificar (cada parada al visitarla).
      final bool past = !day.isAfter(today);
      final bool isToday = day == today;
      final rated = places.where((p) => p.rating > 0).toList();
      final avg = rated.isEmpty ? 0.0 : rated.fold<int>(0, (a, p) => a + p.rating) / rated.length;
      cards.add(_panelCard(isDark: isDark, icon: Icons.star_rounded, title: 'CALIFICAR EL VIAJE', children: [
        if (t.reviewedAt != null && rated.isNotEmpty) ...[
          Row(
            children: [
              ...List.generate(5, (i) => Icon(i < avg.round() ? Icons.star_rounded : Icons.star_outline_rounded, size: 20, color: Colors.amber)),
              const SizedBox(width: 6),
              Text(avg.toStringAsFixed(1), style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: fg)),
            ],
          ),
          const SizedBox(height: 6),
          Text('${rated.length} de ${places.length} paradas calificadas.', style: GoogleFonts.inter(fontSize: 12, color: sub)),
        ] else
          Text(
            isToday
                ? 'Hoy es el viaje: califica cada parada cuando la visites.'
                : past
                    ? 'Ya pasó ${_formatSpanishDate(t.travelDate)}. ¿Qué tal estuvo cada parada?'
                    : 'Podrás calificar las paradas a partir ${_formatSpanishDate(t.travelDate).replaceFirst('el ', 'del ')}.',
            style: GoogleFonts.inter(fontSize: 13, height: 1.4, color: fg),
          ),
        if (past && canEdit) ...[
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {
                onDone?.call();
                _showReviewDialog(isDark);
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: isDark ? const Color(0xFFE8A3C4) : OhtliColors.xoconostle,
                side: BorderSide(color: isDark ? const Color(0xFFE8A3C4) : OhtliColors.xoconostle),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.rate_review_rounded, size: 18),
              label: Text(t.reviewedAt != null ? 'Editar calificación' : 'Calificar paradas', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ]));
    }

    // Actividad reciente
    final recent = _notes.reversed.take(5).toList();
    cards.add(_panelCard(isDark: isDark, icon: Icons.forum_rounded, title: 'ACTIVIDAD', children: [
      if (recent.isEmpty)
        Text('Pasa el cursor sobre un bloque para reaccionar o deja un mensaje junto a él.',
            style: GoogleFonts.inter(fontSize: 12.5, height: 1.4, color: sub))
      else
        for (final n in recent)
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () {
              onDone?.call();
              _openThread(n.blockId);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 4),
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(color: n.authorId == uid ? kBubbleMine : OhtliColors.stormyTeal, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${n.authorId == uid ? 'Tú' : n.authorName} · ${_blockLabelById(n.blockId)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: fg)),
                        Text(n.text, maxLines: 2, overflow: TextOverflow.ellipsis, style: GoogleFonts.inter(fontSize: 12.5, height: 1.35, color: sub)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
    ]));

    return cards;
  }

  /// En móvil el mismo panel se abre como hoja inferior.
  void _showMemberSheet(bool isDark, bool canEdit) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? const Color(0xFF161618) : OhtliColors.cloudDancer,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.62,
        maxChildSize: 0.92,
        minChildSize: 0.35,
        builder: (ctx, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(color: isDark ? Colors.white24 : Colors.black12, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 14, left: 2),
              child: Text('Tu viaje',
                  style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: isDark ? Colors.white : OhtliColors.onyx)),
            ),
            ..._buildMemberPanelCards(isDark, canEdit, onDone: () => Navigator.of(ctx).pop()),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Compartir (V5)
  // ---------------------------------------------------------------------------
  String get _shareUrl => '${Uri.base.origin}/?tripId=${_trip!.id}&authorId=${_trip!.userId}';

  void _showShareDialog(bool isDark) {
    if (_trip == null) return;
    final url = _shareUrl;
    final svg = Barcode.qrCode().toSvg(url, width: 220, height: 220, color: 0x1F2A2A);
    final bool isPrivate = _trip!.visibility != 'public';
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E1E22) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Compartir viaje', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isPrivate)
                Container(
                  margin: const EdgeInsets.only(bottom: 14),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: OhtliColors.cempasuchil.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.lock_outline_rounded, size: 16, color: OhtliColors.cempasuchil),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Este viaje es privado: solo tú y tus coautores podrán abrir el enlace.',
                          style: GoogleFonts.inter(fontSize: 12.5),
                        ),
                      ),
                    ],
                  ),
                ),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                child: SvgPicture.string(svg, width: 200, height: 200),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF25252A) : OhtliColors.cantera.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: SelectableText(url, maxLines: 2, style: GoogleFonts.inter(fontSize: 12)),
              ),
            ],
          ),
        ),
        actionsAlignment: MainAxisAlignment.spaceBetween,
        actions: [
          TextButton.icon(
            onPressed: () {
              final blob = html.Blob([svg], 'image/svg+xml');
              final href = html.Url.createObjectUrlFromBlob(blob);
              html.AnchorElement(href: href)
                ..download = 'ohtli-viaje-qr.svg'
                ..click();
              html.Url.revokeObjectUrl(href);
            },
            icon: const Icon(Icons.qr_code_2_rounded, size: 18),
            label: Text('Descargar QR', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextButton(
                onPressed: () => Share.share('${_trip!.title} — ${_trip!.isReleaseNotes ? 'novedades de Ohtli' : 'mi viaje en Ohtli'}\n$url'),
                child: Text('Más…', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
              ),
              const SizedBox(width: 4),
              FilledButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: url));
                  if (ctx.mounted) Navigator.of(ctx).pop();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Enlace copiado', style: GoogleFonts.inter()),
                        backgroundColor: OhtliColors.stormyTeal,
                      ),
                    );
                  }
                },
                style: FilledButton.styleFrom(backgroundColor: OhtliColors.stormyTeal),
                icon: const Icon(Icons.link_rounded, size: 18),
                label: Text('Copiar enlace', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Reseña después del viaje (T5)
  // ---------------------------------------------------------------------------
  /// Encabezado de las notas de versión: versión, fecha y compartir.
  Widget _buildReleaseNotesHeader(bool isDark) {
    final t = _trip!;
    return Padding(
      padding: const EdgeInsets.only(bottom: 28),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(color: OhtliColors.stormyTeal, borderRadius: BorderRadius.circular(10)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.new_releases_rounded, size: 16, color: Colors.white),
                const SizedBox(width: 6),
                Text(
                  'Notas de versión${t.version != null ? ' · v${t.version}' : ''}',
                  style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white),
                ),
              ],
            ),
          ),
          Text(
            'Actualizado el ${_formatSpanishDate(t.updatedAt)}',
            style: GoogleFonts.inter(fontSize: 12.5, color: isDark ? Colors.white60 : OhtliColors.subtleText),
          ),
          if (!_isPreview)
            TextButton.icon(
              onPressed: () => _showShareDialog(isDark),
              style: TextButton.styleFrom(foregroundColor: OhtliColors.stormyTeal),
              icon: const Icon(Icons.ios_share_rounded, size: 16),
              label: Text('Compartir', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
            ),
        ],
      ),
    );
  }

  Future<void> _showReviewDialog(bool isDark) async {
    final places = _sections.whereType<PlaceSection>().toList();
    final ratings = {for (final p in places) p.id: p.rating};
    final notes = {for (final p in places) p.id: TextEditingController()};
    final bool? saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          backgroundColor: isDark ? const Color(0xFF1E1E22) : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text('Califica tus paradas', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
          content: SizedBox(
            width: 460,
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: places.length,
              separatorBuilder: (_, __) => const Divider(height: 22),
              itemBuilder: (_, i) {
                final p = places[i];
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${i + 1}. ${p.title}', style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 14)),
                    Row(
                      children: List.generate(5, (star) {
                        final active = star < (ratings[p.id] ?? 0);
                        return IconButton(
                          visualDensity: VisualDensity.compact,
                          tooltip: '${star + 1} de 5',
                          icon: Icon(active ? Icons.star_rounded : Icons.star_outline_rounded,
                              color: active ? Colors.amber : OhtliColors.cantera),
                          onPressed: () => setD(() => ratings[p.id] = star + 1),
                        );
                      }),
                    ),
                    TextField(
                      controller: notes[p.id],
                      maxLines: 2,
                      minLines: 1,
                      style: GoogleFonts.inter(fontSize: 13),
                      decoration: InputDecoration(
                        hintText: '¿Algo que recordar? (opcional)',
                        isDense: true,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text('Cancelar', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: FilledButton.styleFrom(backgroundColor: OhtliColors.stormyTeal),
              child: Text('Guardar reseña', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );

    final noteTexts = {for (final e in notes.entries) e.key: e.value.text.trim()};
    for (final c in notes.values) {
      c.dispose();
    }
    if (saved != true || !mounted || _trip == null) return;

    final updated = _sections.map((s) {
      if (s is! PlaceSection) return s;
      final note = noteTexts[s.id] ?? '';
      return s.copyWith(
        rating: ratings[s.id],
        description: note.isEmpty ? null : '${s.description.trim()}\n\n**Después del viaje:** $note'.trim(),
      );
    }).toList();

    if (_isSample) {
      final t = _trip!;
      setState(() {
        _sections = updated;
        _trip = Trip.fromMap({...t.toMap(), 'reviewedAt': Timestamp.now()}, t.id);
      });
      _sampleNotice('En la muestra la calificación se ve, pero no se guarda.');
      return;
    }
    setState(() => _isSavingReview = true);
    try {
      await TripService().saveTripReview(_trip!.userId, _trip!.id, TripContent(sections: updated));
      if (!mounted) return;
      final t = _trip!;
      setState(() {
        _sections = updated;
        _trip = Trip.fromMap({...t.toMap(), 'reviewedAt': Timestamp.now()}, t.id);
        _isSavingReview = false;
      });
      final bool canEditNow = t.userId == FirebaseAuth.instance.currentUser?.uid || t.status == 'draft';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('¡Reseña guardada!', style: GoogleFonts.inter()),
          backgroundColor: OhtliColors.stormyTeal,
          duration: const Duration(seconds: 6),
          action: (t.status != 'published' && canEditNow)
              ? SnackBarAction(
                  label: 'Convertir en crónica',
                  textColor: OhtliColors.cempasuchil,
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => TripEditorPage(trip: _trip!)),
                    ).then((_) => _loadTripData());
                  },
                )
              : null,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSavingReview = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(friendlyError(e, fallback: 'No pudimos guardar tu reseña. Intenta de nuevo.')),
          backgroundColor: OhtliColors.xoconostle,
        ),
      );
    }
  }

  Future<void> _loadTripData() async {
    if (_isSample) {
      _loadSample();
      return;
    }
    final currentUser = FirebaseAuth.instance.currentUser;
    if (widget.trip != null) {
      final t = widget.trip!;
      final bool isAuthor = currentUser != null && t.userId == currentUser.uid;
      final bool isSurpriseForMe = t.isSurprise && 
          currentUser != null && 
          t.surpriseTargetIds.contains(currentUser.uid);
      final bool isLocked = _checkIsLocked(t, isSurpriseForMe, isAuthor);

      _trip = widget.trip;
      if (isLocked) {
        setState(() {
          _isLoading = false;
        });
        return;
      }

      await Future.wait([
        _loadTripContent(),
        _loadAuthorProfile(),
      ]);
      _startSocial();
      _resolveMissingCoords();
    } else if (widget.tripId != null && widget.authorId != null) {
      try {
        final fetchedTrip = await TripService().getTrip(widget.authorId!, widget.tripId!);
        if (fetchedTrip != null) {
          final bool isAuthor = currentUser != null && fetchedTrip.userId == currentUser.uid;
          final bool isSurpriseForMe = fetchedTrip.isSurprise && 
              currentUser != null && 
              fetchedTrip.surpriseTargetIds.contains(currentUser.uid);
          final bool isLocked = _checkIsLocked(fetchedTrip, isSurpriseForMe, isAuthor);

          _trip = fetchedTrip;
          if (isLocked) {
            setState(() {
              _isLoading = false;
            });
            return;
          }

          await Future.wait([
            _loadTripContent(),
            _loadAuthorProfile(),
          ]);
          _startSocial();
          _resolveMissingCoords();
        } else {
          setState(() {
            _errorCode = 404;
            _errorMessage = "Este viaje ha tomado otro rumbo. No logramos encontrar la bitácora que buscas.";
            _isLoading = false;
          });
        }
      } on FirebaseException catch (e) {
        if (e.code == 'permission-denied') {
          setState(() {
            _errorCode = 403;
            _errorMessage = "El aventurero ha decidido mantener esta bitácora bajo llave.";
            _isLoading = false;
          });
        } else if (e.code == 'not-found') {
          setState(() {
            _errorCode = 404;
            _errorMessage = "Este viaje ha tomado otro rumbo. No logramos encontrar la bitácora que buscas.";
            _isLoading = false;
          });
        } else {
          // Errores de red/servidor: no son "no encontrado" ni "privado"
          setState(() {
            _errorCode = null;
            _errorMessage = friendlyError(e, fallback: 'No pudimos cargar este viaje. Revisa tu conexión e intenta de nuevo.');
            _isLoading = false;
          });
        }
      } catch (e) {
        final errorString = e.toString().toLowerCase();
        if (errorString.contains('permission-denied') || errorString.contains('permission denied')) {
          setState(() {
            _errorCode = 403;
            _errorMessage = "El aventurero ha decidido mantener esta bitácora bajo llave.";
            _isLoading = false;
          });
        } else {
          setState(() {
            _errorCode = null;
            _errorMessage = friendlyError(e, fallback: 'No pudimos cargar este viaje. Revisa tu conexión e intenta de nuevo.');
            _isLoading = false;
          });
        }
      }
    } else {
      setState(() {
        _errorMessage = "Datos de consulta insuficientes para cargar la historia.";
        _isLoading = false;
      });
    }
  }

  Future<void> _loadAuthorProfile() async {
    if (_trip == null) return;
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(_trip!.userId).get();
      if (doc.exists && mounted) {
        final profileData = doc.data();
        setState(() {
          _authorProfile = profileData;
        });

        // Fetch dynamic relational active title name
        final String activeTitleId = profileData?['activeTitleId'] ?? 'viajero';
        final titleDoc = await FirebaseFirestore.instance.collection('titles').doc(activeTitleId).get();
        if (titleDoc.exists && mounted) {
          setState(() {
            _authorActiveTitleName = titleDoc.data()?['name'] ?? 'Viajero';
          });
        }
      }

      // Load co-authors profiles
      if (_trip!.coAuthorIds.isNotEmpty) {
        final coAuthorsSnapshot = await FirebaseFirestore.instance
            .collection('users')
            .where(FieldPath.documentId, whereIn: _trip!.coAuthorIds)
            .get();

        final List<Map<String, dynamic>> loadedCoAuthors = [];
        for (var doc in coAuthorsSnapshot.docs) {
          final data = doc.data();
          
          final String titleId = data['activeTitleId'] ?? 'viajero';
          final tDoc = await FirebaseFirestore.instance.collection('titles').doc(titleId).get();
          final String titleName = tDoc.exists ? (tDoc.data()?['name'] ?? 'Viajero') : 'Viajero';
          
          loadedCoAuthors.add({
            'uid': doc.id,
            'displayName': data['displayName'] ?? 'Viajero Ohtli',
            'photoURL': data['photoURL'],
            'title': titleName,
          });
        }
        if (mounted) {
          setState(() {
            _coAuthorsProfiles = loadedCoAuthors;
          });
        }
      }
    } catch (e) {
      print("Error loading author profile: $e");
    }
  }

  Future<void> _loadTripContent() async {
    if (_trip == null) return;
    if (widget.previewSections != null) {
      if (mounted) {
        setState(() {
          _sections = widget.previewSections!;
          _isLoading = false;
        });
      }
      return;
    }
    try {
      final content = await TripService().getTripContent(_trip!.userId, _trip!.id);
      if (mounted) {
        setState(() {
          _sections = content?.sections ?? [];
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        final errorString = e.toString().toLowerCase();
        if (errorString.contains('permission-denied') || errorString.contains('permission denied')) {
          setState(() {
            _errorCode = 403;
            _errorMessage = "No tienes permiso para ver el contenido de este viaje.";
            _isLoading = false;
          });
        } else {
          setState(() {
            _errorCode = null;
            _errorMessage = friendlyError(e, fallback: 'No pudimos cargar el contenido de este viaje. Intenta de nuevo.');
            _isLoading = false;
          });
        }
      }
    }
  }

  void _showImageLightbox({
    required List<String> urls,
    required int initialIndex,
    required String title,
  }) {
    if (urls.isEmpty) return;

    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.95),
      builder: (context) {
        int currentIndex = initialIndex;
        final pageController = PageController(initialPage: initialIndex);

        return StatefulBuilder(
          builder: (context, setState) {
            return Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: EdgeInsets.zero,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Dismiss gesture on empty space
                  Positioned.fill(
                    child: GestureDetector(
                      onTap: () => Navigator.pop(context),
                      behavior: HitTestBehavior.opaque,
                      child: const SizedBox.expand(),
                    ),
                  ),
                  // PageView for swiping images
                  PageView.builder(
                    controller: pageController,
                    itemCount: urls.length,
                    onPageChanged: (index) {
                      setState(() {
                        currentIndex = index;
                      });
                    },
                    itemBuilder: (context, idx) {
                      final url = urls[idx];
                      final provider = _getImageProvider(url);
                      return GestureDetector(
                        onTap: () {},
                        child: Center(
                          child: InteractiveViewer(
                            minScale: 0.5,
                            maxScale: 3.0,
                            child: Container(
                              constraints: BoxConstraints(
                                maxHeight: MediaQuery.of(context).size.height * 0.75,
                                maxWidth: MediaQuery.of(context).size.width * 0.9,
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(14),
                                child: Image(
                                  image: provider,
                                  fit: BoxFit.contain,
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  // Close Button
                  Positioned(
                    top: MediaQuery.of(context).padding.top + 16,
                    right: 16,
                    child: GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.black45,
                        ),
                        child: const Icon(Icons.close_rounded, color: Colors.white, size: 22),
                      ),
                    ),
                  ),
                  // Left Arrow for Desktop/Web
                  if (urls.length > 1 && currentIndex > 0)
                    Positioned(
                      left: 16,
                      child: GestureDetector(
                        onTap: () {
                          pageController.previousPage(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeInOut,
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.black45,
                          ),
                          child: const Icon(Icons.chevron_left_rounded, color: Colors.white, size: 28),
                        ),
                      ),
                    ),
                  // Right Arrow for Desktop/Web
                  if (urls.length > 1 && currentIndex < urls.length - 1)
                    Positioned(
                      right: 16,
                      child: GestureDetector(
                        onTap: () {
                          pageController.nextPage(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeInOut,
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.black45,
                          ),
                          child: const Icon(Icons.chevron_right_rounded, color: Colors.white, size: 28),
                        ),
                      ),
                    ),
                  // Page indicator & Title at the bottom
                  Positioned(
                    bottom: 40,
                    left: 20,
                    right: 20,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (urls.length > 1) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.black45,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              "${currentIndex + 1} de ${urls.length}",
                              style: GoogleFonts.inter(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
                        Text(
                          title,
                          style: GoogleFonts.outfit(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ],
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

  double _calculateTableTotal(TableData tableData, int colIdx) {
    double total = 0.0;
    for (int r = 0; r < tableData.rows.length; r++) {
      final valStr = tableData.rows[r][colIdx];
      final cleanStr = valStr.replaceAll(RegExp(r'[^\d.-]'), '');
      final double? val = double.tryParse(cleanStr);
      if (val != null) {
        total += val;
      }
    }
    return total;
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = OhtliSettings.instance.isDarkMode;
    final double width = MediaQuery.of(context).size.width;
    final bool isDesktop = width >= 800;

    if (_isLoading) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(
                width: 44,
                height: 44,
                child: CircularProgressIndicator(
                  color: OhtliColors.stormyTeal,
                  strokeWidth: 3,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                "Cargando historia...",
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white70 : OhtliColors.onyx,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Sin conexión, "no encontrado" significa que el viaje no está en la caché local
    // (persistencia de Firestore), no que el autor lo haya eliminado.
    if (_errorCode == 404 && !(html.window.navigator.onLine ?? true)) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.cloud_off_rounded, color: OhtliColors.xoconostle, size: 48),
                const SizedBox(height: 16),
                Text(
                  "Sin conexión",
                  style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Text(
                  "Este viaje no está guardado en este dispositivo. Ábrelo una vez con conexión para poder consultarlo después sin red.",
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(fontSize: 14, color: Colors.black54),
                ),
                const SizedBox(height: 20),
                TextButton(
                  onPressed: widget.onBackToDashboard ?? () {},
                  child: Text("explorar inicio", style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_errorCode == 404) {
      return Error404Page(
        onExploreHome: widget.onBackToDashboard ?? () {},
      );
    }

    if (_errorCode == 403) {
      return Error403Page(
        onExploreHome: widget.onBackToDashboard ?? () {},
        onLoginRedirect: widget.onLoginRedirect ?? () {},
      );
    }

    if (_errorMessage != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline_rounded, color: OhtliColors.xoconostle, size: 48),
                const SizedBox(height: 16),
                Text(
                  "¡Vaya! Ocurrió un inconveniente",
                  style: GoogleFonts.inter(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: OhtliColors.xoconostle,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _errorMessage!,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: isDark ? Colors.white54 : OhtliColors.onyx.withValues(alpha: 0.6),
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 24),
                OutlinedButton.icon(
                  onPressed: () {
                    setState(() {
                      _errorMessage = null;
                      _errorCode = null;
                      _isLoading = true;
                    });
                    _loadTripData();
                  },
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text("Reintentar"),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: OhtliColors.stormyTeal,
                    side: const BorderSide(color: OhtliColors.stormyTeal),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 10),
                ElevatedButton(
                  onPressed: widget.onBackToDashboard,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: OhtliColors.stormyTeal,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text("Volver al Dashboard"),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final User? currentUser = FirebaseAuth.instance.currentUser;
    final bool hasActiveSession = currentUser != null;
    final bool showTopNavbar = widget.isPublicLink;
    final bool isOwner = _isSample ? _sampleAsMember : (currentUser != null && _trip != null && _trip!.userId == currentUser.uid);
    final bool isCoAuthor = !_isSample && currentUser != null && _trip != null && _trip!.coAuthorIds.contains(currentUser.uid);
    final bool showErrataButton = isOwner || isCoAuthor;
    final bool canEdit = isOwner || (isCoAuthor && _trip != null && _trip!.status == 'draft');

    final isSurpriseForMe = _trip != null &&
        _trip!.isSurprise &&
        currentUser != null &&
        _trip!.surpriseTargetIds.contains(currentUser.uid);
    bool isLocked = false;
    if (isSurpriseForMe) {
      final bool isAuthor = _trip!.userId == currentUser.uid;
      isLocked = _checkIsLocked(_trip!, isSurpriseForMe, isAuthor);
    }

    // Panel lateral a todo lo alto (mini mapa, índice y, para miembros, herramientas).
    final bool showMemberPanel = _canInteract && !isLocked;
    final double screenW = MediaQuery.of(context).size.width;
    final bool sidebarShown = isDesktop && !widget.isPublicLink && hasActiveSession;
    final bool wideAside = !isLocked &&
        !_isPreview &&
        _trip != null &&
        !_trip!.isReleaseNotes &&
        _sections.isNotEmpty &&
        screenW >= (sidebarShown ? 1280 : 1100);
    // El panel flota sobre el contenido; el texto deja libre su ancho a la derecha.
    final double asideInset = wideAside ? (_asideCollapsed ? _kRailW : _kAsideW) + _kAsideGap * 2 : 0;
    _asideInset = asideInset;
    final int unreadish = _notes.length;

    final Widget mainScrollableContent = LayoutBuilder(
      builder: (context, box) {
        // Mensajes al margen de cada bloque cuando hay espacio a la derecha.
        _marginLayout = _socialVisible && box.maxWidth - asideInset >= 1060;
        final double readingWidth = _marginLayout ? 1040 : 820;
        return SingleChildScrollView(
          controller: _scrollController,
          child: Column(
            children: [
              if (_isPreview)
                Container(
                  width: double.infinity,
                  color: OhtliColors.cempasuchil,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Text(
                    'Vista previa · así verán tu viaje los lectores. Los cambios se guardan en el editor.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600, color: Colors.white),
                  ),
                ),
              _buildCoverHeader(isDark, isDesktop),
              const SizedBox(height: 40),
              Container(
                alignment: Alignment.topCenter,
                padding: EdgeInsets.only(right: asideInset),
                child: Container(
                  constraints: BoxConstraints(maxWidth: readingWidth),
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_trip?.isReleaseNotes == true)
                        _buildReleaseNotesHeader(isDark)
                      else if (!wideAside && _sections.any((s) => s is PlaceSection))
                        Padding(
                          padding: const EdgeInsets.only(bottom: 32),
                          child: KeyedSubtree(key: _mapKey, child: _buildMiniMap(isDark)),
                        ),
                      _buildTimeline(isDark, isDesktop),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 820),
                        child: _buildErrataHistorySection(isDark),
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(height: _tripMode ? 220 : 80),
            ],
          ),
        );
      },
    );

    final Widget activeContent = isLocked ? _buildLockedSurpriseView(isDark) : mainScrollableContent;

    final Widget bodyContent = Row(
      children: [
        if (isDesktop && !widget.isPublicLink && hasActiveSession)
          OhtliSidebar(
            currentIndex: 1,
            onTabSelected: (index) {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (context) => HomePage(
                    initialIndex: index,
                    onLogout: () {
                      Navigator.pushReplacementNamed(context, '/login');
                    },
                    onNavigateToAccount: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => AccountManagementPage(
                            onBackToHome: (idx) {
                              Navigator.pop(context);
                            },
                            onLogout: () async {
                              Navigator.pushReplacementNamed(context, '/login');
                              await FirebaseAuth.instance.signOut();
                            },
                          ),
                        ),
                      );
                    },
                  ),
                ),
              );
            },
            onNavigateToAccount: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => AccountManagementPage(
                    onBackToHome: (idx) {
                      Navigator.pop(context);
                    },
                    onLogout: () async {
                      Navigator.pushReplacementNamed(context, '/login');
                      await FirebaseAuth.instance.signOut();
                    },
                  ),
                ),
              );
            },
            onLogout: () async {
              Navigator.pushReplacementNamed(context, '/login');
              await FirebaseAuth.instance.signOut();
            },
          ),
        Expanded(
          child: Stack(
            children: [
              activeContent,
              // Barra de progreso de lectura (V2)
              if (!isLocked)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: IgnorePointer(
                    child: ValueListenableBuilder<double>(
                      valueListenable: _readProgress,
                      builder: (_, v, __) => LinearProgressIndicator(
                        value: v,
                        minHeight: 3,
                        backgroundColor: Colors.transparent,
                        color: OhtliColors.cempasuchil,
                      ),
                    ),
                  ),
                ),
              // Índice del viaje (V2)
              if (!isLocked && _sections.isNotEmpty && !wideAside)
                Positioned(
                  top: MediaQuery.of(context).padding.top + 12 + (_isPreview ? 34 : 0),
                  right: 16,
                  child: Material(
                    color: isDark ? const Color(0xFF1E1E22).withValues(alpha: 0.92) : Colors.white.withValues(alpha: 0.92),
                    shape: const StadiumBorder(),
                    elevation: 3,
                    child: InkWell(
                      customBorder: const StadiumBorder(),
                      onTap: () => _showIndexSheet(isDark),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.toc_rounded, size: 18, color: OhtliColors.stormyTeal),
                            const SizedBox(width: 6),
                            Text('Índice',
                                style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: isDark ? Colors.white : OhtliColors.onyx)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              // Botón del panel de miembros en móvil
              if (showMemberPanel && !wideAside && !_tripMode)
                Positioned(
                  left: 16,
                  bottom: 16 + MediaQuery.of(context).padding.bottom,
                  child: Material(
                    color: isDark ? const Color(0xFF2C2C2E) : Colors.white,
                    shape: const StadiumBorder(),
                    elevation: 4,
                    child: InkWell(
                      customBorder: const StadiumBorder(),
                      onTap: () => _showMemberSheet(isDark, canEdit),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.groups_rounded, size: 19, color: OhtliColors.stormyTeal),
                            const SizedBox(width: 8),
                            Text('Tu viaje',
                                style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700, color: isDark ? Colors.white : OhtliColors.onyx)),
                            if (unreadish > 0) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(color: kBubbleMine, borderRadius: BorderRadius.circular(10)),
                                child: Text('$unreadish', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white)),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              // Panel del modo viaje (V4): en pantallas anchas vive en el panel lateral
              if (_tripMode && !isLocked && (!wideAside || _asideCollapsed))
                Positioned(
                  left: 16,
                  right: 16 + asideInset,
                  bottom: 16 + MediaQuery.of(context).padding.bottom,
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 560),
                      child: _buildTripModePanel(isDark),
                    ),
                  ),
                ),
              if (_isSavingReview)
                const Positioned.fill(
                  child: ColoredBox(
                    color: Color(0x55000000),
                    child: Center(child: CircularProgressIndicator(color: Colors.white)),
                  ),
                ),
              if (!widget.isPublicLink && !isDesktop)
                Positioned(
                  top: MediaQuery.of(context).padding.top + 12,
                  left: 16,
                  child: GestureDetector(
                    onTap: () {
                      if (Navigator.canPop(context)) {
                        Navigator.pop(context);
                      } else if (widget.onBackToDashboard != null) {
                        widget.onBackToDashboard!();
                      }
                    },
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: (isDark ? const Color(0xFF1E1E22) : Colors.white).withOpacity(0.8),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Icon(
                        Icons.close_rounded,
                        size: 18,
                        color: isDark ? Colors.white70 : OhtliColors.onyx,
                      ),
                    ),
                  ),
                ),
              // Barra de la muestra: abajo, salvo cuando el panel del modo viaje ocupa ese lugar.
              if (_isSample && !isLocked)
                Positioned(
                  top: (_tripMode && (!wideAside || _asideCollapsed)) ? (isDesktop ? 14 : MediaQuery.of(context).padding.top + 58) : null,
                  bottom: (_tripMode && (!wideAside || _asideCollapsed)) ? null : 16 + MediaQuery.of(context).padding.bottom + (isDesktop ? 0 : 56),
                  left: 12,
                  right: 12 + asideInset,
                  child: Center(child: _buildSampleBar(isDark, compact: !isDesktop)),
                ),
              if (wideAside)
                Positioned(
                  top: 0,
                  right: 0,
                  bottom: 0,
                  child: _buildTripAside(isDark, canEdit, showEditAction: showErrataButton && (!isSurpriseForMe || !isLocked)),
                ),
            ],
          ),
        ),
      ],
    );

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121214) : OhtliColors.cloudDancer,
      appBar: showTopNavbar ? _buildPublicNavbar(hasActiveSession, isDark) : null,
      body: bodyContent,
      floatingActionButton: (_isPreview || _tripMode || wideAside)
          ? null
          : (showErrataButton && (!isSurpriseForMe || !isLocked))
          ? FloatingActionButton.extended(
              onPressed: () {
                if (_isSample) {
                  _openEditorOrErrata(canEdit);
                } else if (canEdit) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => TripEditorPage(trip: _trip!),
                    ),
                  ).then((_) {
                    _loadTripData();
                  });
                } else {
                  _showCoAuthorErrataDialog();
                }
              },
              backgroundColor: canEdit ? OhtliColors.stormyTeal : OhtliColors.xoconostle,
              foregroundColor: Colors.white,
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              icon: Icon(canEdit ? Icons.edit_rounded : Icons.history_edu_rounded, size: 20),
              label: Text(
                canEdit ? 'Editar' : 'Fe de Erratas',
                style: GoogleFonts.inter(fontWeight: FontWeight.bold),
              ),
            )
          : null,
    );
  }

  PreferredSizeWidget _buildPublicNavbar(bool isLoggedIn, bool isDark) {
    return AppBar(
      title: SvgPicture.asset(
        'assets/logo.svg',
        height: 22,
        fit: BoxFit.contain,
        colorFilter: const ColorFilter.mode(OhtliColors.stormyTeal, BlendMode.srcIn),
      ),
      backgroundColor: isDark ? const Color(0xFF1E1E22) : Colors.white,
      elevation: 0.5,
      actions: [
        if (_trip != null && _sections.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: IconButton(
              tooltip: 'Generar PDF',
              icon: _isExportingPdf
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(OhtliColors.stormyTeal),
                      ),
                    )
                  : const Icon(Icons.picture_as_pdf_outlined, color: OhtliColors.stormyTeal, size: 20),
              onPressed: _isExportingPdf ? null : () => _exportPdf(),
            ),
          ),
        if (isLoggedIn)
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: OutlinedButton.icon(
              onPressed: widget.onBackToDashboard,
              icon: const Icon(Icons.dashboard_rounded, size: 14),
              label: Text(
                'Mis Viajes',
                style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: OhtliColors.stormyTeal,
                side: const BorderSide(color: OhtliColors.stormyTeal, width: 1.2),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: ElevatedButton.icon(
              onPressed: widget.onLoginRedirect,
              icon: const Icon(Icons.login_rounded, size: 14),
              label: Text(
                'Iniciar Sesión',
                style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: OhtliColors.stormyTeal,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                elevation: 0,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildAuthorWidget(bool isDark) {
    if (_trip == null) return const SizedBox.shrink();

    final List<Map<String, dynamic>> allAuthors = [];

    // Add main author first
    allAuthors.add({
      'uid': _trip!.userId,
      'displayName': _authorProfile?['displayName'] ?? 'Viajero Ohtli',
      'photoURL': _authorProfile?['photoURL'],
      'title': _authorActiveTitleName,
    });

    // Add co-authors
    for (final coAuthorId in _trip!.coAuthorIds) {
      final cachedProfile = _coAuthorsProfiles.firstWhere(
        (p) => p['uid'] == coAuthorId,
        orElse: () => <String, dynamic>{},
      );
      if (cachedProfile.isNotEmpty) {
        allAuthors.add(cachedProfile);
      } else {
        int index = _trip!.coAuthorIds.indexOf(coAuthorId);
        String name = (index >= 0 && index < _trip!.coAuthorNames.length)
            ? _trip!.coAuthorNames[index]
            : 'Viajero Ohtli';
        allAuthors.add({
          'uid': coAuthorId,
          'displayName': name,
          'photoURL': null,
          'title': 'Viajero',
        });
      }
    }

    if (allAuthors.length == 1) {
      final author = allAuthors.first;
      final String name = author['displayName'] ?? 'Viajero Ohtli';
      final String? photoUrl = author['photoURL'];
      final String role = author['title'] ?? 'Viajero';
      final initials = name
          .split(' ')
          .where((w) => w.isNotEmpty)
          .take(2)
          .map((w) => w[0].toUpperCase())
          .join();

      return GestureDetector(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => PublicProfilePage(
                userId: author['uid'],
                showBackButton: true,
                onBack: () => Navigator.pop(context),
              ),
            ),
          );
        },
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    "Escrito por",
                    style: GoogleFonts.inter(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white30 : OhtliColors.onyx.withValues(alpha: 0.4),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    name,
                    style: GoogleFonts.outfit(
                      fontSize: 13.5,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : OhtliColors.onyx,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    role,
                    style: GoogleFonts.inter(
                      fontSize: 9.5,
                      color: isDark ? Colors.white54 : OhtliColors.onyx.withValues(alpha: 0.55),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 12),
              Container(
                width: 36,
                height: 36,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: OhtliColors.stormyTeal,
                ),
                child: ClipOval(
                  child: photoUrl != null && photoUrl.isNotEmpty
                      ? Image(
                          image: _getImageProvider(photoUrl),
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) => Center(
                            child: Text(
                              initials,
                              style: GoogleFonts.inter(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                          ),
                        )
                      : Center(
                          child: Text(
                            initials,
                            style: GoogleFonts.inter(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      );
    } else {
      return GestureDetector(
        onTap: () => _showAuthorsListDialog(allAuthors),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    "Escrito por",
                    style: GoogleFonts.inter(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white30 : OhtliColors.onyx.withValues(alpha: 0.4),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    "Varios autores",
                    style: GoogleFonts.outfit(
                      fontSize: 13.5,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : OhtliColors.onyx,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    "${allAuthors.length} colaboradores",
                    style: GoogleFonts.inter(
                      fontSize: 9.5,
                      color: isDark ? Colors.white54 : OhtliColors.onyx.withValues(alpha: 0.55),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 12),
              _buildStackedAvatars(allAuthors, isDark),
            ],
          ),
        ),
      );
    }
  }

  Widget _buildStackedAvatars(List<Map<String, dynamic>> allAuthors, bool isDark) {
    final int maxVisible = 3;
    final List<Widget> avatarWidgets = [];

    for (int i = 0; i < allAuthors.length; i++) {
      if (i >= maxVisible) {
        final int remaining = allAuthors.length - maxVisible;
        avatarWidgets.add(
          Align(
            widthFactor: 0.6,
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: isDark ? const Color(0xFF1E1E22) : Colors.white, width: 2),
              ),
              child: CircleAvatar(
                radius: 18,
                backgroundColor: OhtliColors.stormyTeal,
                child: Text(
                  '+$remaining',
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        );
        break;
      }

      final author = allAuthors[i];
      final String? photoURL = author['photoURL'];
      final String name = author['displayName'] ?? 'Viajero';
      final String initials = name.isNotEmpty ? name[0].toUpperCase() : '';

      avatarWidgets.add(
        Align(
          widthFactor: 0.6,
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: isDark ? const Color(0xFF1E1E22) : Colors.white, width: 2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: CircleAvatar(
              radius: 18,
              backgroundColor: OhtliColors.stormyTeal,
              backgroundImage: (photoURL != null && photoURL.isNotEmpty)
                  ? _getImageProvider(photoURL)
                  : null,
              child: (photoURL == null || photoURL.isEmpty)
                  ? Text(
                      initials,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    )
                  : null,
            ),
          ),
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: avatarWidgets,
    );
  }

  void _showAuthorsListDialog(List<Map<String, dynamic>> allAuthors) {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        final bool isDark = OhtliSettings.instance.isDarkMode;
        return AlertDialog(
          backgroundColor: isDark ? const Color(0xFF1E1E22) : OhtliColors.cloudDancer,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Text(
            'Autores',
            style: GoogleFonts.outfit(
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : OhtliColors.onyx,
            ),
          ),
          content: Container(
            width: double.maxFinite,
            constraints: const BoxConstraints(maxWidth: 400, maxHeight: 300),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: allAuthors.length,
              itemBuilder: (context, index) {
                final author = allAuthors[index];
                final String uid = author['uid'];
                final String name = author['displayName'] ?? 'Viajero Ohtli';
                final String? photoURL = author['photoURL'];
                final String role = author['title'] ?? 'Viajero';
                final String initials = name.isNotEmpty ? name[0].toUpperCase() : '';

                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(vertical: 4),
                  leading: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: OhtliColors.stormyTeal.withOpacity(0.2), width: 1),
                    ),
                    child: CircleAvatar(
                      radius: 20,
                      backgroundColor: OhtliColors.stormyTeal.withOpacity(0.1),
                      backgroundImage: (photoURL != null && photoURL.isNotEmpty)
                          ? _getImageProvider(photoURL)
                          : null,
                      child: (photoURL == null || photoURL.isEmpty)
                          ? Text(
                              initials,
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: OhtliColors.stormyTeal,
                              ),
                            )
                          : null,
                    ),
                  ),
                  title: Text(
                    name,
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: isDark ? Colors.white : OhtliColors.onyx,
                    ),
                  ),
                  subtitle: Text(
                    role,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: isDark ? Colors.white54 : OhtliColors.onyx.withOpacity(0.6),
                    ),
                  ),
                  trailing: const Icon(
                    Icons.chevron_right_rounded,
                    color: OhtliColors.stormyTeal,
                  ),
                  onTap: () {
                    Navigator.pop(dialogContext);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => PublicProfilePage(
                          userId: uid,
                          showBackButton: true,
                          onBack: () => Navigator.pop(context),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(
                'Cerrar',
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.bold,
                  color: OhtliColors.stormyTeal,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildErrataHistorySection(bool isDark) {
    final errata = _trip?.errataHistory ?? [];
    if (errata.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        Divider(color: isDark ? const Color(0xFF2C2C32) : OhtliColors.cantera.withValues(alpha: 0.3), height: 40),
        Row(
          children: [
            const Icon(Icons.history_edu_rounded, color: OhtliColors.xoconostle, size: 20),
            const SizedBox(width: 8),
            Text(
              "Notas de Cambios y Fe de Erratas",
              style: GoogleFonts.outfit(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : OhtliColors.onyx,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        ...errata.reversed.map((entry) {
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF231E1E) : const Color(0xFFFFF5F5),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isDark ? const Color(0xFF5A2C2C) : const Color(0xFFFEE2E2),
                width: 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      "Corrección publicada",
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: OhtliColors.xoconostle,
                      ),
                    ),
                    Text(
                      "${entry.date.day}/${entry.date.month}/${entry.date.year}",
                      style: GoogleFonts.inter(
                        fontSize: 10.5,
                        color: isDark ? Colors.white38 : OhtliColors.onyx.withValues(alpha: 0.4),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  entry.note,
                  style: GoogleFonts.inter(
                    fontSize: 12.5,
                    color: isDark ? Colors.white70 : OhtliColors.onyx,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  String _formatSpanishDate(DateTime? date) {
    if (date == null) return 'Sin fecha de viaje';
    final months = [
      'enero',
      'febrero',
      'marzo',
      'abril',
      'mayo',
      'junio',
      'julio',
      'agosto',
      'septiembre',
      'octubre',
      'noviembre',
      'diciembre'
    ];
    final day = date.day;
    final month = months[date.month - 1];
    final year = date.year;
    return 'el $day de $month del $year';
  }

  /// Datos rápidos del viaje para la portada: paradas, horario, traslados y costo.
  List<(IconData, String)> _coverFacts() {
    final facts = <(IconData, String)>[];
    final t = _trip;
    if (t?.travelDate != null) {
      const months = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];
      final d = t!.travelDate!;
      facts.add((Icons.event_rounded, '${d.day} ${months[d.month - 1]} ${d.year}'));
    }
    final places = _sections.whereType<PlaceSection>().toList();
    if (places.isEmpty) return facts;
    final int planned = places.where((p) => !p.unplanned).length;
    final int detours = places.length - planned;
    facts.add((
      Icons.place_rounded,
      '$planned ${planned == 1 ? 'parada' : 'paradas'}${detours > 0 ? ' · $detours ${detours == 1 ? 'desvío' : 'desvíos'}' : ''}'
    ));

    final starts = places.map((p) => _minutesOf(p.arrivalTime)).whereType<int>().toList();
    final ends = places.map((p) => _minutesOf(p.departureTime) ?? _minutesOf(p.arrivalTime)).whereType<int>().toList();
    if (starts.isNotEmpty && ends.isNotEmpty) {
      final a = starts.reduce(math.min);
      final b = ends.reduce(math.max);
      String fmt(int m) => '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';
      facts.add((Icons.schedule_rounded, b > a ? '${fmt(a)} – ${fmt(b)} · ${formatDuration(b - a)}' : fmt(a)));
    }

    final transfers = _sections.whereType<TransferSection>().toList();
    double km = transfers.fold<double>(0, (a, x) => a + (x.distanceKm ?? 0));
    if (km == 0) {
      PlaceSection? prev;
      for (final p in places) {
        if (p.lat == null || p.lng == null) continue;
        if (prev != null) km += _haversineKm(prev.lat!, prev.lng!, p.lat!, p.lng!);
        prev = p;
      }
    }
    if (km > 0) {
      final modes = transfers.map((x) => x.mode).toSet();
      final icon = modes.length == 1 ? transferModeOf(modes.first).icon : Icons.alt_route_rounded;
      facts.add((icon, km < 1 ? '${(km * 1000).round()} m' : '${km.toStringAsFixed(1)} km'));
    }

    final costs = <String, double>{};
    for (final p in places) {
      if (p.cost > 0) costs[p.currency] = (costs[p.currency] ?? 0) + p.cost;
    }
    for (final x in transfers) {
      if (x.cost > 0) costs[x.currency] = (costs[x.currency] ?? 0) + x.cost;
    }
    String money(double v) {
      final str = v.round().toString();
      final b = StringBuffer();
      for (int i = 0; i < str.length; i++) {
        if (i > 0 && (str.length - i) % 3 == 0) b.write(',');
        b.write(str[i]);
      }
      return '\$$b';
    }

    facts.add((Icons.payments_rounded, costs.isEmpty ? 'Gratis' : costs.entries.map((e) => '${money(e.value)} ${e.key}').join(' + ')));
    return facts;
  }

  Widget _buildCoverHeader(bool isDark, bool isDesktop) {
    final t = _trip;
    final String cover = t?.coverUrl ?? '';
    final bool onImage = cover.isNotEmpty;
    final String title = t?.title ?? 'Sin título';
    final String desc = t?.description ?? '';
    final Color fg = onImage ? Colors.white : (isDark ? Colors.white : OhtliColors.onyx);
    final Color sub = onImage ? Colors.white.withValues(alpha: 0.88) : (isDark ? Colors.white70 : OhtliColors.onyx.withValues(alpha: 0.72));
    final facts = t?.isReleaseNotes == true ? const <(IconData, String)>[] : _coverFacts();

    Widget chip((IconData, String) f) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
          decoration: BoxDecoration(
            color: onImage ? Colors.white.withValues(alpha: 0.16) : (isDark ? Colors.white.withValues(alpha: 0.07) : Colors.white),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: onImage ? Colors.white.withValues(alpha: 0.22) : (isDark ? Colors.white12 : OhtliColors.cardBorder)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(f.$1, size: 14, color: fg),
              const SizedBox(width: 6),
              Text(f.$2, style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600, color: fg)),
            ],
          ),
        );

    final Widget actions = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!_isPreview)
          FilledButton.icon(
            onPressed: () => _showShareDialog(isDark),
            style: FilledButton.styleFrom(
              backgroundColor: onImage ? Colors.white : OhtliColors.stormyTeal,
              foregroundColor: onImage ? const Color(0xFF1F2A2A) : Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            icon: const Icon(Icons.ios_share_rounded, size: 17),
            label: Text('Compartir', style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 13)),
          ),
        const SizedBox(width: 8),
        PopupMenuButton<String>(
          tooltip: 'Más opciones',
          enabled: !_isExportingPdf && _sections.isNotEmpty,
          onSelected: (v) => _exportPdf(printOnly: v == 'print'),
          itemBuilder: (_) => [
            PopupMenuItem(
              value: 'pdf',
              child: Row(children: [
                const Icon(Icons.picture_as_pdf_rounded, size: 18),
                const SizedBox(width: 10),
                Text('Descargar PDF', style: GoogleFonts.inter(fontSize: 13.5)),
              ]),
            ),
            PopupMenuItem(
              value: 'print',
              child: Row(children: [
                const Icon(Icons.print_rounded, size: 18),
                const SizedBox(width: 10),
                Text('Imprimir', style: GoogleFonts.inter(fontSize: 13.5)),
              ]),
            ),
          ],
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: onImage ? Colors.white.withValues(alpha: 0.16) : (isDark ? Colors.white.withValues(alpha: 0.07) : Colors.white),
              border: Border.all(color: onImage ? Colors.white.withValues(alpha: 0.25) : (isDark ? Colors.white12 : OhtliColors.cardBorder)),
            ),
            child: _isExportingPdf
                ? Padding(padding: const EdgeInsets.all(12), child: CircularProgressIndicator(strokeWidth: 2, color: fg))
                : Icon(Icons.more_horiz_rounded, color: fg),
          ),
        ),
      ],
    );

    final Widget content = Container(
      alignment: Alignment.topCenter,
      padding: EdgeInsets.only(right: _asideInset),
      child: Container(
        constraints: BoxConstraints(maxWidth: _marginLayout ? 1040 : 820),
        padding: EdgeInsets.fromLTRB(24, onImage ? 0 : 64, 24, onImage ? 34 : 36),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: GoogleFonts.outfit(fontSize: isDesktop ? 46 : 32, fontWeight: FontWeight.bold, color: fg, height: 1.06)),
            if (desc.isNotEmpty) ...[
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 680),
                child: OhtliMarkdownText(
                  text: desc,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(fontSize: isDesktop ? 16 : 14.5, color: sub, height: 1.5),
                ),
              ),
            ],
            if (facts.isNotEmpty) ...[
              const SizedBox(height: 18),
              Wrap(spacing: 8, runSpacing: 8, children: facts.map(chip).toList()),
            ],
            const SizedBox(height: 20),
            Wrap(
              spacing: 16,
              runSpacing: 14,
              crossAxisAlignment: WrapCrossAlignment.center,
              alignment: WrapAlignment.spaceBetween,
              children: [_buildAuthorWidget(onImage ? true : isDark), actions],
            ),
          ],
        ),
      ),
    );

    if (!onImage) {
      return Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF19191C) : OhtliColors.cantera.withValues(alpha: 0.22),
          border: Border(bottom: BorderSide(color: isDark ? Colors.white10 : OhtliColors.cardBorder)),
        ),
        child: content,
      );
    }
    return Stack(
      children: [
        Positioned.fill(
          child: Image(
            image: _getImageProvider(cover),
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => ColoredBox(color: isDark ? const Color(0xFF26343A) : OhtliColors.stormyTeal),
          ),
        ),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: const [0, 0.35, 1],
                colors: [Colors.black.withValues(alpha: 0.35), Colors.black.withValues(alpha: 0.05), Colors.black.withValues(alpha: 0.86)],
              ),
            ),
          ),
        ),
        // Crece con el texto; deja aire arriba para la barra y el botón de índice.
        Container(
          width: double.infinity,
          constraints: BoxConstraints(minHeight: isDesktop ? 540 : 470),
          padding: const EdgeInsets.only(top: 110),
          alignment: Alignment.bottomCenter,
          child: content,
        ),
      ],
    );
  }

  Widget _buildBlockCard(TripSection section, bool isDark, bool isDesktop, int index) {
    Widget blockContent = const SizedBox();

    if (section is UnknownSection) return const SizedBox.shrink();
    if (section is TransferSection) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 28),
        child: _buildTransferViewer(section, isDark),
      );
    }

    if (section is PlaceSection) {
      blockContent = _buildPlaceBlockViewer(section, isDark, isDesktop);
    } else if (section is TextSection) {
      final alertData = parseAlertMarkdown(section.markdownText);
      final tableData = parseTableMarkdown(section.markdownText);

      if (alertData != null) {
        blockContent = _buildAlertBlockViewer(alertData, isDark);
      } else if (tableData != null) {
        blockContent = _buildTableBlockViewer(tableData, isDark);
      } else {
        blockContent = _buildTextBlockViewer(section, isDark);
      }
    } else if (section is TextImageSection) {
      blockContent = _buildTextImageBlockViewer(section, isDark, isDesktop);
    }

    final bool highlighted = _highlightedId == section.id;
    if (section is PlaceSection && _tripMode) {
      final visited = _visited.contains(section.id);
      blockContent = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: FilterChip(
              selected: visited,
              onSelected: (_) => _toggleVisited(section.id),
              showCheckmark: true,
              checkmarkColor: Colors.white,
              selectedColor: OhtliColors.stormyTeal,
              label: Text(visited ? 'Visitada' : 'Marcar como visitada',
                  style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: visited ? Colors.white : OhtliColors.stormyTeal)),
              side: const BorderSide(color: OhtliColors.stormyTeal),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
          Opacity(opacity: visited ? 0.6 : 1, child: blockContent),
        ],
      );
    }

    final Widget framed = AnimatedContainer(
      duration: const Duration(milliseconds: 350),
      padding: EdgeInsets.all(highlighted ? 10 : 0),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        color: highlighted ? OhtliColors.cempasuchil.withValues(alpha: isDark ? 0.16 : 0.10) : Colors.transparent,
      ),
      child: blockContent,
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 40),
      child: _wrapBlock(section, framed, isDark, isDesktop),
    );
  }

  // ---------------------------------------------------------------------------
  // Lectura: línea de tiempo, reacciones al pasar el cursor y mensajes al margen
  // ---------------------------------------------------------------------------
  static const double _spineX = 22; // centro de la línea punteada (coincide con el ícono del traslado)
  static const double _spineIndent = 56; // sangría de los bloques respecto a la línea

  bool get _useTimeline => _trip?.isReleaseNotes != true && _sections.any((s) => s is PlaceSection);

  Widget _buildTimeline(bool isDark, bool isDesktop) {
    final list = ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _sections.length,
      itemBuilder: (context, index) {
        final section = _sections[index];
        return KeyedSubtree(
          key: _blockKeys.putIfAbsent(section.id, () => GlobalKey()),
          // Cada bloque aparece al entrar en pantalla (y al cargarse, si ya está a la vista).
          child: RevealOnScroll(
            key: ValueKey('reveal_${section.id}'),
            scroll: _scrollController,
            child: _buildBlockCard(section, isDark, isDesktop, index),
          ),
        );
      },
    );
    if (!_useTimeline) return list;
    return Stack(
      children: [
        Positioned(
          left: _spineX - 1,
          top: 8,
          bottom: 40,
          child: CustomPaint(
            size: const Size(2, double.infinity),
            painter: _DashedLinePainter(color: isDark ? Colors.white24 : OhtliColors.onyx.withValues(alpha: 0.22)),
          ),
        ),
        list,
      ],
    );
  }

  Widget _wrapBlock(TripSection section, Widget content, bool isDark, bool isDesktop) {
    final bool social = _socialVisible;
    final String? uid = _myUid;
    final reactions = social ? (_blockReactions[section.id] ?? const <String, String>{}) : const <String, String>{};
    final names = _memberNames;

    // Con mensajes al margen, las burbujas montan 42 px sobre el borde derecho: el texto de los
    // bloques sin tarjeta se detiene antes para que no quede debajo de ellas.
    if (_marginLayout && section is! PlaceSection) {
      content = Padding(padding: const EdgeInsets.only(right: 52), child: content);
    }

    // 1) Bloque con la pastilla de reacciones montada en su borde superior derecho.
    Widget block = content;
    // En las paradas la pastilla se monta sobre el borde superior de la tarjeta;
    // en el resto de bloques va encima del texto para no taparlo.
    double padTop = 30, pillTop = 0;
    if (section is PlaceSection) {
      final hasPhotos = section.mainPhotoUrl.isNotEmpty || section.secondaryPhotoUrls.any((u) => u.isNotEmpty);
      final bool inset = hasPhotos && isDesktop; // la tarjeta empieza 14 px abajo por las fotos
      final cardTop = inset ? 14.0 : 0.0;
      padTop = inset ? 0 : 12;
      pillTop = cardTop + padTop - 12 + (_tripMode ? 52 : 0);
    }
    // Con mensajes al margen, las burbujas montan 42 px sobre el borde: la pastilla se corre para no taparlas.
    final double pillRight = _marginLayout ? 58 : 18;
    if (social && (summarizeReactions(reactions).isNotEmpty || _canInteract)) {
      block = Stack(
        clipBehavior: Clip.none,
        children: [
          Padding(padding: EdgeInsets.only(top: padTop), child: content),
          Positioned(
            top: pillTop,
            right: pillRight,
            child: ReactionSummary(byUser: reactions, myUid: uid, memberNames: names, isDark: isDark),
          ),
        ],
      );
    }
    if (_canInteract) {
      // La burbuja «+» aparece junto a la pastilla de reacciones, en la esquina superior derecha.
      block = HoverTapback(
        selected: uid != null ? reactions[uid] : null,
        isDark: isDark,
        alignRight: true,
        offset: Offset(36 - pillRight, pillTop + 26),
        onPick: (k) => _reactToBlock(section.id, k),
        child: block,
      );
    }

    // 2) En la línea de tiempo, cada parada lleva su punto, hora y número. Un desvío no lleva
    //    título ni número: la línea punteada se abre en una rama y vuelve a la principal.
    if (_useTimeline && section is PlaceSection && section.unplanned) {
      const double shift = 30;
      final double toSpine = _spineIndent - _spineX;
      block = Stack(
        clipBehavior: Clip.none,
        children: [
          Padding(padding: const EdgeInsets.only(left: shift, top: 6, bottom: 6), child: block),
          Positioned(
            left: -toSpine,
            top: -26,
            bottom: -26,
            width: toSpine + shift,
            child: IgnorePointer(
              child: CustomPaint(
                painter: _DetourBranchPainter(
                  color: isDark ? Colors.white38 : OhtliColors.onyx.withValues(alpha: 0.32),
                  dot: OhtliColors.cempasuchil,
                  ring: isDark ? const Color(0xFF121214) : OhtliColors.cloudDancer,
                ),
              ),
            ),
          ),
        ],
      );
    } else if (_useTimeline && section is PlaceSection) {
      final places = _sections.whereType<PlaceSection>().where((p) => !p.unplanned).toList();
      final n = places.indexOf(section) + 1;
      final visited = _visited.contains(section.id);
      final time = section.arrivalTime != null && section.arrivalTime!.trim().isNotEmpty ? '${section.arrivalTime!.trim()} · ' : '';
      block = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  '${time}Parada $n de ${places.length}',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                    color: isDark ? Colors.white54 : OhtliColors.subtleText,
                  ),
                ),
              ),
              Positioned(
                left: -(_spineIndent - _spineX) - 9,
                top: -2,
                child: Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: visited || n == 1 ? OhtliColors.stormyTeal : (isDark ? const Color(0xFF3A3A3E) : OhtliColors.cantera),
                    border: Border.all(color: isDark ? const Color(0xFF121214) : OhtliColors.cloudDancer, width: 3),
                  ),
                ),
              ),
            ],
          ),
          block,
        ],
      );
    }

    // 3) Mensajes: al margen derecho (montados sobre el borde) o debajo en pantallas angostas.
    Widget row = block;
    if (social) {
      final notes = _notes.where((n) => n.blockId == section.id).toList();
      Widget thread({required bool compact, bool revealAdd = false}) => NoteThread(
            key: ValueKey('thread_${section.id}_$compact'),
            notes: notes,
            myUid: uid,
            canWrite: _canInteract,
            canModerate: uid != null && _trip!.userId == uid,
            compact: compact,
            revealAdd: revealAdd,
            memberNames: names,
            isDark: isDark,
            onSend: (text) => _social!.addNote(
              blockId: section.id,
              authorId: uid!,
              authorName: _myDisplayName,
              authorPhoto: _isSample ? null : FirebaseAuth.instance.currentUser?.photoURL,
              text: text,
            ),
            onEdit: (note, text) => _social!.editNote(note.id, text),
            onDelete: (note) => _confirmDeleteNote(note),
            onReact: (note, k) => _guardSocial(() => _social!.reactToNote(note.id, uid!, k)),
          );

      if (_marginLayout) {
        final double top = (_useTimeline && section is PlaceSection) ? 64 : 34;
        row = HoverBuilder(
          builder: (context, hovered) => Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: block),
              // Se monta sobre el borde derecho del bloque, como una nota pegada.
              // Se monta 42 px sobre el borde del bloque. La separación de arriba es de diseño (no un
              // desplazamiento) para que la fila crezca con los mensajes y todos reciban clics.
              Transform.translate(
                offset: const Offset(-42, 0),
                child: Padding(
                  padding: EdgeInsets.only(top: top),
                  // Los mensajes llegan un instante después del bloque, deslizándose desde el margen.
                  child: RevealOnScroll(
                    scroll: _scrollController,
                    delay: const Duration(milliseconds: 160),
                    from: const Offset(24, 0),
                    child: SizedBox(width: 236, child: thread(compact: true, revealAdd: hovered)),
                  ),
                ),
              ),
            ],
          ),
        );
      } else if (_canInteract || notes.isNotEmpty || summarizeReactions(reactions).isNotEmpty) {
        final open = _openThreads.contains(section.id);
        row = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            block,
            BlockSocialBar(
              reactions: reactions,
              noteCount: notes.length,
              threadOpen: open,
              myUid: uid,
              canInteract: _canInteract,
              memberNames: names,
              isDark: isDark,
              onReact: (k) => _reactToBlock(section.id, k),
              onToggleThread: () => setState(() => open ? _openThreads.remove(section.id) : _openThreads.add(section.id)),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: open ? thread(compact: false) : const SizedBox(width: double.infinity),
            ),
          ],
        );
      }
    }

    if (_useTimeline) row = Padding(padding: const EdgeInsets.only(left: _spineIndent), child: row);
    return row;
  }

  // ---------------------------------------------------------------------------
  // Panel lateral: mini mapa, índice y herramientas de los miembros
  // ---------------------------------------------------------------------------
  void _setAsideCollapsed(bool v) {
    setState(() => _asideCollapsed = v);
    try {
      html.window.localStorage['ohtli_trip_aside_collapsed'] = v ? '1' : '0';
    } catch (_) {}
  }

  void _openEditorOrErrata(bool canEdit) {
    if (_isSample) {
      _sampleNotice('El viaje de muestra no se puede editar.');
      return;
    }
    if (canEdit) {
      Navigator.push(context, MaterialPageRoute(builder: (context) => TripEditorPage(trip: _trip!))).then((_) => _loadTripData());
    } else {
      _showCoAuthorErrataDialog();
    }
  }

  Widget _buildTripAside(bool isDark, bool canEdit, {bool showEditAction = false}) {
    final Color border = isDark ? Colors.white10 : OhtliColors.cardBorder;
    final Color bg = isDark ? const Color(0xFF161618) : Colors.white;
    final Color fg = isDark ? Colors.white : OhtliColors.onyx;
    final bool member = _canInteract;
    BoxDecoration floating(double radius) => BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: border),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.12), blurRadius: 28, offset: const Offset(0, 10)),
            BoxShadow(color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.05), blurRadius: 4, offset: const Offset(0, 1)),
          ],
        );

    if (_asideCollapsed) {
      Widget railButton(IconData icon, String tip, VoidCallback onTap, {bool accent = false}) => Tooltip(
            message: tip,
            child: IconButton(
              onPressed: onTap,
              icon: Icon(icon, size: 21, color: accent ? OhtliColors.stormyTeal : (isDark ? Colors.white70 : OhtliColors.onyx.withValues(alpha: 0.7))),
            ),
          );
      // Riel plegado: una píldora flotante con los accesos.
      return SafeArea(
        left: false,
        child: Align(
          alignment: Alignment.topRight,
          child: Container(
            width: _kRailW,
            margin: const EdgeInsets.all(_kAsideGap),
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: floating(_kRailW / 2),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                railButton(Icons.keyboard_double_arrow_left_rounded, 'Abrir panel', () => _setAsideCollapsed(false), accent: true),
                Container(width: 24, height: 1, margin: const EdgeInsets.symmetric(vertical: 4), color: border),
                if (_sections.any((s) => s is PlaceSection)) railButton(Icons.map_rounded, 'Ruta completa', () => _showRouteModal(isDark)),
                railButton(Icons.toc_rounded, 'Índice', () => _setAsideCollapsed(false)),
                if (member) railButton(Icons.handyman_rounded, 'Herramientas del viaje', () => _setAsideCollapsed(false)),
                if (showEditAction)
                  railButton(canEdit ? Icons.edit_rounded : Icons.history_edu_rounded, canEdit ? 'Editar' : 'Fe de erratas',
                      () => _openEditorOrErrata(canEdit)),
              ],
            ),
          ),
        ),
      );
    }

    // Panel abierto: tarjeta flotante a todo lo alto, con margen y esquinas redondeadas.
    return SafeArea(
      left: false,
      child: Container(
        width: _kAsideW,
        margin: const EdgeInsets.all(_kAsideGap),
        clipBehavior: Clip.antiAlias,
        decoration: floating(26),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 14, 14, 24),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(member ? 'Tu viaje' : 'Recorrido',
                      style: GoogleFonts.outfit(fontSize: 17, fontWeight: FontWeight.bold, color: fg)),
                ),
                if (showEditAction)
                  Padding(
                    padding: const EdgeInsets.only(right: 2),
                    child: FilledButton.icon(
                      onPressed: () => _openEditorOrErrata(canEdit),
                      style: FilledButton.styleFrom(
                        backgroundColor: canEdit ? OhtliColors.stormyTeal : OhtliColors.xoconostle,
                        foregroundColor: Colors.white,
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: Icon(canEdit ? Icons.edit_rounded : Icons.history_edu_rounded, size: 16),
                      label: Text(canEdit ? 'Editar' : 'Fe de erratas', style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w700)),
                    ),
                  ),
                IconButton(
                  tooltip: 'Plegar panel',
                  onPressed: () => _setAsideCollapsed(true),
                  icon: Icon(Icons.keyboard_double_arrow_right_rounded, color: isDark ? Colors.white60 : OhtliColors.subtleText),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_sections.any((s) => s is PlaceSection)) ...[
              _buildMiniMap(isDark),
              const SizedBox(height: 18),
            ],
            _buildAsideIndex(isDark),
            if (member) ...[
              const SizedBox(height: 22),
              Row(
                children: [
                  Icon(Icons.lock_outline_rounded, size: 14, color: isDark ? Colors.white54 : OhtliColors.subtleText),
                  const SizedBox(width: 6),
                  Text('HERRAMIENTAS DEL VIAJE',
                      style: GoogleFonts.inter(
                          fontSize: 11.5, fontWeight: FontWeight.w700, letterSpacing: 0.4, color: isDark ? Colors.white54 : OhtliColors.subtleText)),
                ],
              ),
              const SizedBox(height: 10),
              ..._buildMemberPanelCards(isDark, canEdit),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMiniMap(bool isDark) {
    final places = _sections.whereType<PlaceSection>().toList();
    final next = _nextStop;
    final withCoords = places.where((p) => _coordsOf(p) != null).toList();
    final missing = places.length - withCoords.length;
    return Material(
      color: isDark ? const Color(0xFF1E1E22) : const Color(0xFFF1F4F3),
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _showRouteModal(isDark),
        child: SizedBox(
          height: 168,
          child: Stack(
            children: [
              Positioned.fill(
                child: TripMiniMap(
                  isDark: isDark,
                  stops: [
                    for (final p in withCoords)
                      MiniMapStop(
                        lat: _coordsOf(p)!.$1,
                        lng: _coordsOf(p)!.$2,
                        number: p.unplanned ? 0 : places.where((x) => !x.unplanned).toList().indexOf(p) + 1,
                        unplanned: p.unplanned,
                        visited: _visited.contains(p.id),
                        isNext: _tripMode && identical(p, next),
                      ),
                  ],
                ),
              ),
              if (missing > 0)
                Positioned(
                  left: 8,
                  top: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                    decoration: BoxDecoration(
                      color: (isDark ? Colors.black : Colors.white).withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      _locating
                          ? 'Buscando ubicación…'
                          : (missing == places.length ? 'Sin ubicación en el mapa' : '$missing sin ubicación'),
                      style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: isDark ? Colors.white70 : OhtliColors.subtleText),
                    ),
                  ),
                ),
              Positioned(
                right: 8,
                top: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                  decoration: BoxDecoration(
                    color: (isDark ? Colors.black : Colors.white).withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.open_in_full_rounded, size: 13, color: isDark ? Colors.white70 : OhtliColors.onyx),
                      const SizedBox(width: 4),
                      Text('Ver ruta', style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w600, color: isDark ? Colors.white70 : OhtliColors.onyx)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAsideIndex(bool isDark) {
    int n = 0;
    final items = <Widget>[];
    for (final s in _sections) {
      if (s is TransferSection || s is UnknownSection) continue;
      final bool isPlace = s is PlaceSection;
      final bool detour = s is PlaceSection && s.unplanned;
      if (isPlace && !detour) n++;
      final visited = _visited.contains(s.id);
      final highlighted = _highlightedId == s.id;
      items.add(InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _scrollToBlock(s.id),
        child: Container(
          padding: EdgeInsets.fromLTRB(isPlace ? 6 : 34, 7, 6, 7),
          decoration: BoxDecoration(
            color: highlighted ? OhtliColors.cempasuchil.withValues(alpha: 0.12) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              if (isPlace) ...[
                CircleAvatar(
                  radius: 11,
                  backgroundColor: detour
                      ? OhtliColors.cempasuchil.withValues(alpha: 0.18)
                      : (visited ? OhtliColors.stormyTeal : (isDark ? const Color(0xFF2C2C30) : OhtliColors.cantera.withValues(alpha: 0.6))),
                  child: detour
                      ? const Icon(Icons.alt_route_rounded, size: 13, color: OhtliColors.cempasuchil)
                      : visited
                      ? const Icon(Icons.check_rounded, size: 13, color: Colors.white)
                      : Text('$n',
                          style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.w700, color: isDark ? Colors.white : OhtliColors.onyx)),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Text(
                  _blockLabel(s),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: isPlace ? 13 : 12,
                    fontWeight: isPlace ? FontWeight.w600 : FontWeight.w400,
                    color: isPlace ? (isDark ? Colors.white : OhtliColors.onyx) : (isDark ? Colors.white54 : OhtliColors.subtleText),
                  ),
                ),
              ),
              if (_notes.any((m) => m.blockId == s.id))
                const Padding(
                  padding: EdgeInsets.only(left: 6),
                  child: Icon(Icons.chat_bubble_rounded, size: 12, color: kBubbleMine),
                ),
            ],
          ),
        ),
      ));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 6, bottom: 6),
          child: Text('ÍNDICE',
              style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w700, letterSpacing: 0.4, color: isDark ? Colors.white54 : OhtliColors.subtleText)),
        ),
        ...items,
      ],
    );
  }

  /// Ruta completa en un modal: el mapa interactivo con todas las paradas.
  void _showRouteModal(bool isDark) {
    final places = _sections.whereType<PlaceSection>().toList();
    if (places.isEmpty) return;
    final size = MediaQuery.of(context).size;
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: isDark ? const Color(0xFF1E1E22) : Colors.white,
        insetPadding: const EdgeInsets.all(24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1040),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 16, 10, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Ruta completa',
                              style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.bold, color: isDark ? Colors.white : OhtliColors.onyx)),
                          Text('${places.length} ${places.length == 1 ? 'parada' : 'paradas'} · toca una para ir a su bloque',
                              style: GoogleFonts.inter(fontSize: 12.5, color: isDark ? Colors.white60 : OhtliColors.subtleText)),
                        ],
                      ),
                    ),
                    IconButton(tooltip: 'Cerrar', onPressed: () => Navigator.of(ctx).pop(), icon: const Icon(Icons.close_rounded)),
                  ],
                ),
              ),
              OsrmMapWidget(
                onStopSelected: (stop) {
                  final id = stop['section_id'];
                  Navigator.of(ctx).pop();
                  if (id is String) WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBlock(id));
                },
                stops: places
                    .map((p) => {
                          'section_id': p.id,
                          'name': p.title,
                          'lat': _coordsOf(p)?.$1,
                          'lng': _coordsOf(p)?.$2,
                          'arrival_time': p.arrivalTime ?? '',
                          'departure_time': p.departureTime ?? '',
                          'price_mxn': p.cost,
                        })
                    .toList(),
                height: math.min(620, size.height * 0.68),
                isDark: isDark,
              ),
            ],
          ),
        ),
      ),
    );
  }

  final Set<String?> _contributedPlaces = {};

  Future<void> _contributeToPlace(PlaceSection place) async {
    final draft = PlaceDetailsDraft();
    final isDark = OhtliSettings.instance.isDarkMode;
    final send = await showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: isDark ? const Color(0xFF1E1E22) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        insetPadding: const EdgeInsets.all(16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 540, maxHeight: 720),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 8, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(place.title.isEmpty ? 'Completa este lugar' : place.title,
                          style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.bold, color: OhtliColors.onyx)),
                    ),
                    IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(ctx, false)),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text('Si ya fuiste, cuéntanos lo que sepas. Ayuda a que Ohtli lo recomiende mejor.',
                    style: GoogleFonts.inter(fontSize: 12.5, color: OhtliColors.onyx.withValues(alpha: 0.6))),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                  child: PlaceDetailsFields(draft: draft),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: () => Navigator.pop(ctx, true),
                      icon: const Icon(Icons.send_rounded, size: 18),
                      label: const Text('Enviar'),
                      style: ElevatedButton.styleFrom(backgroundColor: OhtliColors.stormyTeal, foregroundColor: Colors.white, elevation: 0),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (send != true || !mounted) return;
    if (draft.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No escribiste nada todavía.', style: GoogleFonts.inter())),
      );
      return;
    }
    try {
      await PoiSuggestionService.contribute(place.poiId!, draft.toMap());
      if (!mounted) return;
      setState(() => _contributedPlaces.add(place.poiId));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('¡Gracias! Lo tendremos en cuenta.', style: GoogleFonts.inter()), backgroundColor: OhtliColors.stormyTeal),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _contributedPlaces.add(place.poiId));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(friendlyError(e, fallback: 'Este lugar ya fue revisado. ¡Gracias por querer ayudar!'), style: GoogleFonts.inter()),
        ),
      );
    }
  }

  Widget _buildPlaceBlockViewer(PlaceSection place, bool isDark, bool isDesktop) {
    // Collect active photo urls
    final List<Map<String, dynamic>> drawOrderSlots = [];
    final List<String> activeUrls = [];
    if (place.mainPhotoUrl.isNotEmpty) {
      drawOrderSlots.add({'url': place.mainPhotoUrl, 'type': 'place_main'});
      activeUrls.add(place.mainPhotoUrl);
    }
    for (int i = 0; i < place.secondaryPhotoUrls.length; i++) {
      final url = place.secondaryPhotoUrls[i];
      if (url.isNotEmpty) {
        drawOrderSlots.add({'url': url, 'type': 'place_sec_$i'});
        activeUrls.add(url);
      }
    }

    // Sort to guarantee correct stack rendering depth (main is front, sec_0 is middle, sec_1 is back)
    drawOrderSlots.sort((a, b) {
      final tA = a['type'] as String;
      final tB = b['type'] as String;
      if (tA == 'place_sec_1') return -1;
      if (tA == 'place_sec_0' && tB == 'place_main') return -1;
      return 1;
    });

    final Widget photoStackWidget = drawOrderSlots.isNotEmpty
        ? OhtliPlacePhotoStack(
            drawOrderSlots: drawOrderSlots,
            isDark: isDark,
            slotBuilder: (slot, _) {
              final String currentUrl = slot['url'] as String;
              final int clickedIndex = activeUrls.indexOf(currentUrl);
              final ImageProvider provider = _getImageProvider(currentUrl);
              return GestureDetector(
                onTap: () => _showImageLightbox(
                  urls: activeUrls,
                  initialIndex: clickedIndex >= 0 ? clickedIndex : 0,
                  title: place.title.isNotEmpty ? place.title : 'Fotos del Lugar',
                ),
                child: Hero(
                  tag: 'place_photo_${place.id}_${slot['url']}',
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.15),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
                      image: DecorationImage(
                        image: provider,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                ),
              );
            },
          )
        : const SizedBox.shrink();

    final Widget infoWidget = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          place.title.isNotEmpty ? place.title : 'Sin Título del Lugar',
          style: GoogleFonts.outfit(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : OhtliColors.onyx,
          ),
        ),
        const SizedBox(height: 6),
        // Star ratings
        Row(
          children: List.generate(5, (starIdx) {
            final active = starIdx < place.rating;
            return Icon(
              active ? Icons.star_rounded : Icons.star_outline_rounded,
              color: active ? Colors.amber : (isDark ? Colors.white24 : OhtliColors.cantera),
              size: 16,
            );
          }),
        ),
        if (place.description.isNotEmpty) ...[
          const SizedBox(height: 12),
          OhtliMarkdownText(
            text: place.description,
            style: GoogleFonts.inter(
              fontSize: 13,
              color: isDark ? Colors.white70 : OhtliColors.onyx.withValues(alpha: 0.8),
              height: 1.45,
            ),
          ),
        ],
        // Costo estimado, gasto real y horas reales de llegada y salida.
        if (place.cost > 0.0 || place.realCost != null || place.arrivedAt != null) ...[
          const SizedBox(height: 14),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (place.cost > 0.0)
                _placeBadge(Icons.payments_outlined, 'Costo estimado: \$ ${place.cost.toStringAsFixed(2)} ${place.currency}', isDark, amber: true),
              if (place.realCost != null)
                _placeBadge(Icons.receipt_long_rounded, 'Gasto real: \$ ${place.realCost!.toStringAsFixed(2)} ${place.currency}', isDark),
              if (place.arrivedAt != null)
                _placeBadge(
                  Icons.schedule_rounded,
                  place.leftAt != null ? 'Estuvieron de ${place.arrivedAt} a ${place.leftAt}' : 'Llegaron a las ${place.arrivedAt}',
                  isDark,
                ),
            ],
          ),
        ],
        // Lugar nuevo propuesto por un viajero: quien lo conozca puede completar su información
        if (place.isSuggestion && FirebaseAuth.instance.currentUser != null && !_contributedPlaces.contains(place.poiId)) ...[
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: () => _contributeToPlace(place),
            icon: const Icon(Icons.edit_note_rounded, size: 18),
            label: Text('¿Conoces este lugar? Ayuda a completar su información',
                style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600)),
            style: TextButton.styleFrom(
              foregroundColor: isDark ? Color.lerp(OhtliColors.stormyTeal, Colors.white, 0.45) : OhtliColors.stormyTeal,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            ),
          ),
        ],
      ],
    );

    final BoxDecoration card = BoxDecoration(
      color: isDark ? const Color(0xFF1E1E22) : Colors.white,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: isDark ? Colors.white10 : OhtliColors.cardBorder),
      boxShadow: [
        BoxShadow(color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.05), blurRadius: 18, offset: const Offset(0, 6)),
      ],
    );

    // Portada arriba; la pila de fotos reales (160×195) queda montada entre la portada y el cuerpo
    // y, en escritorio, medio fuera del borde izquierdo, como fotos pegadas.
    final double coverH = isDesktop ? 132 : 150;
    if (drawOrderSlots.isEmpty) {
      return Container(
        clipBehavior: Clip.antiAlias,
        decoration: card,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _placeCover(place, isDark, coverH),
            Padding(padding: const EdgeInsets.all(22), child: infoWidget),
          ],
        ),
      );
    }

    if (isDesktop) {
      return Stack(
        clipBehavior: Clip.none,
        children: [
          Padding(
            // Las fotos ocupan x≈15–135: la tarjeta empieza en 76 para que queden medio fuera.
            padding: const EdgeInsets.only(left: 76, top: 14),
            child: Container(
              clipBehavior: Clip.antiAlias,
              decoration: card,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _placeCover(place, isDark, coverH),
                  Container(
                    constraints: const BoxConstraints(minHeight: 150),
                    padding: const EdgeInsets.fromLTRB(84, 18, 22, 22),
                    child: infoWidget,
                  ),
                ],
              ),
            ),
          ),
          Positioned(left: 0, top: 14 + coverH - 62, child: photoStackWidget),
        ],
      );
    }
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: double.infinity,
          clipBehavior: Clip.antiAlias,
          decoration: card,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _placeCover(place, isDark, coverH),
              Padding(padding: const EdgeInsets.fromLTRB(20, 195 - 80 + 14, 20, 20), child: infoWidget),
            ],
          ),
        ),
        Positioned(left: 0, right: 0, top: coverH - 80, child: Center(child: photoStackWidget)),
      ],
    );
  }

  Widget _buildAlertBlockViewer(AlertData alert, bool isDark) {
    Color alertColor = OhtliColors.stormyTeal;
    IconData alertIcon = Icons.info_outline_rounded;
    String alertName = "Nota / Info";
    
    if (alert.type == AlertType.warning) {
      alertColor = OhtliColors.xoconostle;
      alertIcon = Icons.warning_amber_rounded;
      alertName = "Advertencia";
    } else if (alert.type == AlertType.tip) {
      alertColor = OhtliColors.cempasuchil;
      alertIcon = Icons.lightbulb_outline_rounded;
      alertName = "Consejo / Tip";
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2C2C32) : alertColor.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? alertColor.withValues(alpha: 0.3) : alertColor.withValues(alpha: 0.15),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: alertColor.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(alertIcon, color: alertColor, size: 16),
              ),
              const SizedBox(width: 10),
              Text(
                alertName,
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  color: alertColor,
                ),
              ),
            ],
          ),
          if (alert.content.isNotEmpty) ...[
            const SizedBox(height: 10),
            OhtliMarkdownText(
              text: alert.content,
              style: GoogleFonts.inter(
                fontSize: 13,
                color: isDark ? Colors.white70 : OhtliColors.onyx,
                height: 1.45,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTableBlockViewer(TableData table, bool isDark) {
    final int numCols = table.columns.length;
    final bool showTotalRow = table.columns.any((col) => col.type == 'money' && col.isTotalEnabled);
    final Color headerBg = isDark ? const Color(0xFF25252A) : OhtliColors.cantera.withValues(alpha: 0.12);
    final Color cellBorder = isDark ? const Color(0xFF2C2C32) : OhtliColors.cantera.withValues(alpha: 0.25);

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Table Headers
          Row(
            children: List.generate(numCols, (colIdx) {
              final col = table.columns[colIdx];
              return Container(
                width: 150,
                margin: const EdgeInsets.only(right: 4),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: headerBg,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: cellBorder),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      col.type == 'money'
                          ? Icons.payments_rounded
                          : col.type == 'number'
                              ? Icons.tag_rounded
                              : Icons.text_fields_rounded,
                      size: 11,
                      color: OhtliColors.stormyTeal.withValues(alpha: 0.7),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: OhtliMarkdownText(
                        text: col.name,
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.bold,
                          fontSize: 11.5,
                          color: isDark ? Colors.white : OhtliColors.onyx,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ),
          const SizedBox(height: 4),
          // Rows
          ...List.generate(table.rows.length, (rowIdx) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: List.generate(numCols, (colIdx) {
                  final col = table.columns[colIdx];
                  final bool isMoney = col.type == 'money';
                  final bool isNumber = col.type == 'number';
                  final val = table.rows[rowIdx][colIdx];

                  return Container(
                    width: 150,
                    margin: const EdgeInsets.only(right: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: cellBorder),
                    ),
                    child: Align(
                      alignment: (isMoney || isNumber) ? Alignment.centerRight : Alignment.centerLeft,
                      child: isMoney && val.isNotEmpty
                          ? RichText(
                              textAlign: TextAlign.right,
                              text: TextSpan(
                                children: [
                                  TextSpan(
                                    text: '\$ ',
                                    style: GoogleFonts.inter(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: isDark ? Colors.white30 : OhtliColors.onyx.withValues(alpha: 0.35),
                                    ),
                                  ),
                                  TextSpan(
                                    text: val,
                                    style: GoogleFonts.inter(
                                      fontSize: 11.5,
                                      color: isDark ? Colors.white : OhtliColors.onyx,
                                    ),
                                  ),
                                  TextSpan(
                                    text: ' ${col.currency}',
                                    style: GoogleFonts.inter(
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.bold,
                                      color: isDark ? Colors.white30 : OhtliColors.onyx.withValues(alpha: 0.4),
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : OhtliMarkdownText(
                              text: val,
                              style: GoogleFonts.inter(
                                fontSize: 11.5,
                                color: isDark ? Colors.white70 : OhtliColors.onyx,
                              ),
                              textAlign: (isMoney || isNumber) ? TextAlign.right : TextAlign.left,
                            ),
                    ),
                  );
                }),
              ),
            );
          }),
          // Totals Row
          if (showTotalRow) ...[
            const SizedBox(height: 2),
            Row(
              children: List.generate(numCols, (colIdx) {
                final col = table.columns[colIdx];
                final bool isMoneyTotal = col.type == 'money' && col.isTotalEnabled;

                return Container(
                  width: 150,
                  margin: const EdgeInsets.only(right: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  decoration: BoxDecoration(
                    color: isMoneyTotal
                        ? (isDark ? const Color(0xFF2C2C32) : OhtliColors.stormyTeal.withValues(alpha: 0.04))
                        : Colors.transparent,
                    border: isMoneyTotal
                        ? Border(
                            top: BorderSide(color: OhtliColors.stormyTeal, width: 1.2),
                            bottom: BorderSide(color: OhtliColors.stormyTeal, width: 1.2),
                          )
                        : null,
                  ),
                  child: isMoneyTotal
                      ? Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Total:',
                              style: GoogleFonts.inter(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: OhtliColors.stormyTeal,
                              ),
                            ),
                            Text(
                              '\$ ${_calculateTableTotal(table, colIdx).toStringAsFixed(2)} ${col.currency}',
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: isDark ? Colors.white : OhtliColors.onyx,
                              ),
                            ),
                          ],
                        )
                      : const SizedBox.shrink(),
                );
              }),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTextBlockViewer(TextSection textSec, bool isDark) {
    if (textSec.markdownText.isEmpty) return const SizedBox.shrink();
    return OhtliMarkdownText(
      text: textSec.markdownText,
      style: GoogleFonts.inter(
        fontSize: 13.5,
        color: isDark ? Colors.white70 : OhtliColors.onyx,
        height: 1.5,
      ),
    );
  }

  Widget _buildTextImageBlockViewer(TextImageSection section, bool isDark, bool isDesktop) {
    final Widget imageWidget = section.imageUrl.isNotEmpty
        ? Center(
            child: Container(
              width: 120,
              height: 160,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 6,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: GestureDetector(
                  onTap: () => _showImageLightbox(
                    urls: [section.imageUrl],
                    initialIndex: 0,
                    title: "Foto adjunta",
                  ),
                  child: Image(
                    image: _getImageProvider(section.imageUrl),
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ),
          )
        : const SizedBox.shrink();

    final Widget textWidget = section.markdownText.isNotEmpty
        ? OhtliMarkdownText(
            text: section.markdownText,
            style: GoogleFonts.inter(
              fontSize: 13.5,
              color: isDark ? Colors.white70 : OhtliColors.onyx,
              height: 1.5,
            ),
          )
        : const SizedBox.shrink();

    if (isDesktop && section.imageUrl.isNotEmpty) {
      final bool isLeft = section.layout == 'left';
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isLeft) ...[
            imageWidget,
            const SizedBox(width: 20),
          ],
          Expanded(child: textWidget),
          if (!isLeft) ...[
            const SizedBox(width: 20),
            imageWidget,
          ],
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (section.imageUrl.isNotEmpty) ...[
          imageWidget,
          const SizedBox(height: 14),
        ],
        textWidget,
      ],
    );
  }

  Future<void> _showCoAuthorErrataDialog() async {
    final noteController = TextEditingController();

    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              backgroundColor: OhtliColors.cloudDancer,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: Row(
                children: [
                  const Icon(Icons.history_edu_rounded, color: OhtliColors.xoconostle, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Publicar Fe de Errata',
                    style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: OhtliColors.onyx),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Como co-autor de este plan, puedes publicar una fe de errata detallando cualquier corrección o actualización.',
                    style: GoogleFonts.inter(fontSize: 12, height: 1.45, color: OhtliColors.onyx.withOpacity(0.7)),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Descripción de cambios realizados:',
                    style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: OhtliColors.onyx),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: noteController,
                    maxLines: 3,
                    style: GoogleFonts.inter(fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'Ej. Corrección de costos de hospedaje y rutas de transporte...',
                      hintStyle: GoogleFonts.inter(fontSize: 12.5, color: Colors.grey),
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.all(12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: OhtliColors.cantera.withOpacity(0.5)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: OhtliColors.xoconostle, width: 1.2),
                      ),
                    ),
                    onChanged: (val) {
                      setStateDialog(() {});
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: Text(
                    'Cancelar',
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w600,
                      color: OhtliColors.onyx.withOpacity(0.6),
                    ),
                  ),
                ),
                ElevatedButton(
                  onPressed: noteController.text.trim().isEmpty
                      ? null
                      : () async {
                          final String noteText = noteController.text.trim();
                          Navigator.pop(dialogContext);

                          final newErrata = ErrataEntry(
                            id: DateTime.now().millisecondsSinceEpoch.toString(),
                            note: noteText,
                            date: DateTime.now(),
                          );

                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Guardando fe de errata...'),
                              backgroundColor: OhtliColors.xoconostle,
                              duration: Duration(milliseconds: 600),
                            ),
                          );

                          try {
                            final List<ErrataEntry> updatedHistory = List.from(_trip!.errataHistory)..add(newErrata);
                            await FirebaseFirestore.instance
                                .collection('users')
                                .doc(_trip!.userId)
                                .collection('trips')
                                .doc(_trip!.id)
                                .update({
                              'errataHistory': updatedHistory.map((e) => e.toMap()).toList(),
                              'updatedAt': FieldValue.serverTimestamp(),
                            });

                            _loadTripData();

                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: const Text('¡Fe de Errata publicada por el co-autor con éxito!'),
                                  backgroundColor: OhtliColors.xoconostle,
                                  behavior: SnackBarBehavior.floating,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                              );
                            }
                          } catch (e) {
                            print("Error saving co-author errata: $e");
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: OhtliColors.xoconostle,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.grey.shade300,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    elevation: 0,
                  ),
                  child: Text(
                    'Publicar Errata',
                    style: GoogleFonts.inter(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildLockedSurpriseView(bool isDark) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final unlockDate = uid != null ? _trip!.surpriseUnlockDates[uid] : null;
    if (unlockDate == null) return const SizedBox.shrink();

    final diff = unlockDate.difference(DateTime.now());
    final days = diff.inDays;
    final hours = diff.inHours % 24;
    final minutes = diff.inMinutes % 60;
    
    String countdownStr = "";
    if (days > 0) {
      countdownStr = "$days días, $hours hrs y $minutes min";
    } else if (hours > 0) {
      countdownStr = "$hours horas y $minutes minutos";
    } else {
      countdownStr = "$minutes minutos";
    }

    return Center(
      child: Container(
        margin: const EdgeInsets.all(24),
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E22) : Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        constraints: const BoxConstraints(maxWidth: 450),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 90,
              height: 90,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: OhtliColors.stormyTeal.withOpacity(0.08),
              ),
              child: const Center(
                child: Icon(Icons.lock_rounded, size: 40, color: OhtliColors.stormyTeal),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              '¡Shh... Es una sorpresa!',
              style: GoogleFonts.outfit(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: OhtliColors.onyx,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              'Este plan ha sido preparado especialmente para ti, pero aún no puedes abrirlo.',
              style: GoogleFonts.inter(
                fontSize: 13.5,
                color: OhtliColors.onyx.withOpacity(0.7),
                height: 1.45,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: OhtliColors.cantera.withOpacity(0.15),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  Text(
                    'Se abrirá en:',
                    style: GoogleFonts.inter(
                      fontSize: 11.5,
                      fontWeight: FontWeight.bold,
                      color: OhtliColors.stormyTeal,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    countdownStr,
                    style: GoogleFonts.inter(
                      fontSize: 14.5,
                      fontWeight: FontWeight.bold,
                      color: OhtliColors.onyx,
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

  Widget _buildFallbackMapVisual(List<PlaceSection> places, bool isDark) {
    return Container(
      width: double.infinity,
      height: 200,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF141416) : OhtliColors.innerCardBg,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.route_rounded, color: OhtliColors.stormyTeal, size: 36),
            const SizedBox(height: 8),
            Text(
              'Ruta secuencial con ${places.length} paradas programadas',
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white70 : OhtliColors.onyx,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Línea punteada vertical de la línea de tiempo.
class _DashedLinePainter extends CustomPainter {
  final Color color;
  const _DashedLinePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    const dash = 5.0, gap = 6.0;
    double y = 0;
    while (y < size.height) {
      canvas.drawLine(Offset(size.width / 2, y), Offset(size.width / 2, math.min(y + dash, size.height)), paint);
      y += dash + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _DashedLinePainter old) => old.color != color;
}


/// Rama punteada de un desvío: sale de la línea principal, corre junto al bloque y vuelve.
class _DetourBranchPainter extends CustomPainter {
  final Color color;
  final Color dot;
  final Color ring;
  const _DetourBranchPainter({required this.color, required this.dot, required this.ring});

  @override
  void paint(Canvas canvas, Size size) {
    const double x0 = 0; // la línea principal
    final double x1 = size.width - 14; // la rama
    final double h = size.height;
    const double bend = 40;
    final path = Path()
      ..moveTo(x0, 0)
      ..cubicTo(x0, bend * 0.55, x1, bend * 0.45, x1, bend)
      ..lineTo(x1, h - bend)
      ..cubicTo(x1, h - bend * 0.45, x0, h - bend * 0.55, x0, h);
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    const dash = 5.0, gap = 6.0;
    for (final metric in path.computeMetrics()) {
      double d = 0;
      while (d < metric.length) {
        canvas.drawPath(metric.extractPath(d, math.min(d + dash, metric.length)), paint);
        d += dash + gap;
      }
    }
    // Punto del desvío sobre la rama, a la altura del inicio del bloque.
    final c = Offset(x1, bend + 22);
    canvas.drawCircle(c, 8, Paint()..color = ring);
    canvas.drawCircle(c, 5.5, Paint()..color = dot);
  }

  @override
  bool shouldRepaint(covariant _DetourBranchPainter old) => old.color != color || old.dot != dot || old.ring != ring;
}

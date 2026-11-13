// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
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
  bool _reviewBannerDismissed = false;
  bool _isSavingReview = false;

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
    _scrollController.addListener(_onScroll);
    _loadTripData();
  }

  @override
  void dispose() {
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
                          title: Text('Mapa y cronología', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
                          onTap: () => go(() => _scrollToKey(_mapKey)),
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

  Widget _buildTripSummary(bool isDark, bool isDesktop) {
    final places = _sections.whereType<PlaceSection>().toList();
    if (places.isEmpty) return const SizedBox.shrink();

    // Traslados: si la bitácora los tiene, mandan; si no, línea recta entre paradas.
    final transfers = _sections.whereType<TransferSection>().toList();
    final transferKm = transfers.fold<double>(0, (a, t) => a + (t.distanceKm ?? 0));
    final transferMins = transfers.fold<int>(0, (a, t) => a + (t.durationMins ?? 0));
    final bool usesTransfers = transferKm > 0;
    double km = transferKm;
    if (!usesTransfers) {
      PlaceSection? prev;
      for (final p in places) {
        if (p.lat == null || p.lng == null) continue;
        if (prev != null) km += _haversineKm(prev.lat!, prev.lng!, p.lat!, p.lng!);
        prev = p;
      }
    }
    final modesUsed = transfers.map((t) => t.mode).toSet();
    final IconData moveIcon =
        modesUsed.length == 1 ? transferModeOf(modesUsed.first).icon : (modesUsed.isEmpty ? Icons.directions_walk_rounded : Icons.alt_route_rounded);

    // Horario: primera llegada → última salida (o llegada)
    final starts = places.map((p) => _minutesOf(p.arrivalTime)).whereType<int>().toList();
    final ends = places.map((p) => _minutesOf(p.departureTime) ?? _minutesOf(p.arrivalTime)).whereType<int>().toList();
    String? schedule;
    String? duration;
    if (starts.isNotEmpty && ends.isNotEmpty) {
      final a = starts.reduce(math.min);
      final b = ends.reduce(math.max);
      String fmt(int m) => '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';
      schedule = '${fmt(a)} – ${fmt(b)}';
      if (b > a) {
        final mins = b - a;
        duration = mins >= 60 ? '${mins ~/ 60} h${mins % 60 > 0 ? ' ${mins % 60} min' : ''}' : '$mins min';
      }
    }

    // Costo estimado por moneda
    final costs = <String, double>{};
    for (final p in places) {
      if (p.cost > 0) costs[p.currency] = (costs[p.currency] ?? 0) + p.cost;
    }
    for (final t in transfers) {
      if (t.cost > 0) costs[t.currency] = (costs[t.currency] ?? 0) + t.cost;
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

    final costText = costs.isEmpty
        ? 'Gratis'
        : costs.entries.map((e) => '${money(e.value)} ${e.key}').join(' + ');

    final Color fg = isDark ? Colors.white : OhtliColors.onyx;
    final Color sub = isDark ? Colors.white60 : OhtliColors.subtleText;

    Widget stat(IconData icon, String value, String label, Color tone) => Container(
          constraints: BoxConstraints(minWidth: isDesktop ? 150 : 140),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: tone.withValues(alpha: isDark ? 0.16 : 0.07),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 20, color: tone),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(value, style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: fg)),
                  Text(label, style: GoogleFonts.inter(fontSize: 11, color: sub)),
                ],
              ),
            ],
          ),
        );

    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E22) : Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: isDark ? Colors.white12 : OhtliColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              stat(Icons.place_rounded, '${places.length}', places.length == 1 ? 'parada' : 'paradas', OhtliColors.xoconostle),
              if (schedule != null)
                stat(Icons.schedule_rounded, schedule, duration != null ? 'aprox. $duration' : 'horario', OhtliColors.cempasuchil),
              if (km > 0)
                stat(
                    moveIcon,
                    km < 1 ? '${(km * 1000).round()} m' : '${km.toStringAsFixed(1)} km',
                    usesTransfers
                        ? (transferMins > 0 ? '${formatDuration(transferMins)} de traslados' : 'de traslados')
                        : 'entre paradas (línea recta)',
                    OhtliColors.stormyTeal),
              stat(Icons.payments_rounded, costText, 'costo estimado por persona', const Color(0xFFB45309)),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              if (!_isPreview)
                FilledButton.icon(
                  onPressed: () => _setTripMode(!_tripMode),
                  style: FilledButton.styleFrom(
                    backgroundColor: _tripMode ? OhtliColors.xoconostle : OhtliColors.stormyTeal,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: Icon(_tripMode ? Icons.stop_circle_outlined : Icons.near_me_rounded, size: 18),
                  label: Text(_tripMode ? 'Salir del modo viaje' : 'Estoy en el viaje',
                      style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
                ),
              OutlinedButton.icon(
                onPressed: _isPreview ? null : () => _showShareDialog(isDark),
                style: OutlinedButton.styleFrom(
                  foregroundColor: OhtliColors.stormyTeal,
                  side: const BorderSide(color: OhtliColors.stormyTeal),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.ios_share_rounded, size: 18),
                label: Text('Compartir', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ],
      ),
    );
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
    final dest = (p.lat != null && p.lng != null)
        ? '${p.lat},${p.lng}'
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

  Widget _buildTripModePanel(bool isDark) {
    final places = _sections.whereType<PlaceSection>().toList();
    final next = _nextStop;
    final done = places.where((p) => _visited.contains(p.id)).length;
    final Color fg = isDark ? Colors.white : OhtliColors.onyx;
    return Material(
      elevation: 12,
      color: isDark ? const Color(0xFF1E1E22) : Colors.white,
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
  bool _canReview(bool canEdit) {
    final t = _trip;
    if (t == null || _isPreview || !canEdit || t.reviewedAt != null || _reviewBannerDismissed || t.isReleaseNotes) return false;
    if (t.travelDate == null || !_sections.any((s) => s is PlaceSection)) return false;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final travelDay = DateTime(t.travelDate!.year, t.travelDate!.month, t.travelDate!.day);
    return travelDay.isBefore(today);
  }

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

  String get _reviewDismissKey => 'ohtli_review_dismissed_${_trip?.id ?? ''}';

  Widget _buildReviewBanner(bool isDark) {
    final dateText = _formatSpanishDate(_trip!.travelDate);
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            OhtliColors.cempasuchil.withValues(alpha: isDark ? 0.28 : 0.16),
            OhtliColors.xoconostle.withValues(alpha: isDark ? 0.22 : 0.10),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.rate_review_rounded, color: OhtliColors.xoconostle, size: 26),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('¿Qué tal estuvo tu viaje?',
                    style: GoogleFonts.outfit(fontSize: 17, fontWeight: FontWeight.bold, color: isDark ? Colors.white : OhtliColors.onyx)),
                const SizedBox(height: 4),
                Text(
                  'Ya pasó el $dateText. Califica tus paradas y anota lo que quieras recordar; después puedes convertirlo en una crónica.',
                  style: GoogleFonts.inter(fontSize: 13, height: 1.4, color: isDark ? Colors.white70 : OhtliColors.onyx.withValues(alpha: 0.75)),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: () => _showReviewDialog(isDark),
                      style: FilledButton.styleFrom(
                        backgroundColor: OhtliColors.xoconostle,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: const Icon(Icons.star_rounded, size: 18),
                      label: Text('Calificar paradas', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
                    ),
                    TextButton(
                      onPressed: () {
                        try {
                          html.window.localStorage[_reviewDismissKey] = '1';
                        } catch (_) {}
                        setState(() => _reviewBannerDismissed = true);
                      },
                      child: Text('Ahora no', style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: OhtliColors.xoconostle)),
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
    try {
      _reviewBannerDismissed = html.window.localStorage[_reviewDismissKey] == '1';
    } catch (_) {}
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
    final bool isOwner = currentUser != null && _trip != null && _trip!.userId == currentUser.uid;
    final bool isCoAuthor = currentUser != null && _trip != null && _trip!.coAuthorIds.contains(currentUser.uid);
    final bool showErrataButton = isOwner || isCoAuthor;
    final bool canEdit = isOwner || (isCoAuthor && _trip != null && _trip!.status == 'draft');

    final Widget mainScrollableContent = SingleChildScrollView(
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
          const SizedBox(height: 36),
          Center(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 820),
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_trip?.isReleaseNotes == true)
                    _buildReleaseNotesHeader(isDark)
                  else ...[
                    if (_canReview(canEdit)) _buildReviewBanner(isDark),
                    _buildTripSummary(isDark, isDesktop),
                    KeyedSubtree(key: _mapKey, child: _buildRouteMapAndChronologySection(isDark, isDesktop)),
                  ],
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _sections.length,
                    itemBuilder: (context, index) {
                      final section = _sections[index];
                      return KeyedSubtree(
                        key: _blockKeys.putIfAbsent(section.id, () => GlobalKey()),
                        child: _buildBlockCard(section, isDark, isDesktop, index),
                      );
                    },
                  ),
                  _buildErrataHistorySection(isDark),
                ],
              ),
            ),
          ),
          SizedBox(height: _tripMode ? 220 : 80),
        ],
      ),
    );

    Widget activeContent = mainScrollableContent;
    final isSurpriseForMe = _trip != null && 
        _trip!.isSurprise && 
        currentUser != null && 
        _trip!.surpriseTargetIds.contains(currentUser.uid);

    bool isLocked = false;

    if (isSurpriseForMe) {
      final bool isAuthor = _trip!.userId == currentUser.uid;
      isLocked = _checkIsLocked(_trip!, isSurpriseForMe, isAuthor);
      
      if (isLocked) {
        activeContent = _buildLockedSurpriseView(isDark);
      }
    }

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
              if (!isLocked && _sections.isNotEmpty)
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
              // Panel del modo viaje (V4)
              if (_tripMode && !isLocked)
                Positioned(
                  left: 16,
                  right: 16,
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
            ],
          ),
        ),
      ],
    );

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121214) : OhtliColors.cloudDancer,
      appBar: showTopNavbar ? _buildPublicNavbar(hasActiveSession, isDark) : null,
      body: bodyContent,
      floatingActionButton: (_isPreview || _tripMode)
          ? null
          : (showErrataButton && (!isSurpriseForMe || !isLocked))
          ? FloatingActionButton.extended(
              onPressed: () {
                if (canEdit) {
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
          : (!isLocked && _sections.isNotEmpty
              ? FloatingActionButton.extended(
                  onPressed: _isExportingPdf ? null : () => _exportPdf(),
                  backgroundColor: OhtliColors.stormyTeal,
                  foregroundColor: Colors.white,
                  elevation: 4,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  icon: const Icon(Icons.picture_as_pdf_rounded, size: 18),
                  label: Text(
                    'Generar PDF',
                    style: GoogleFonts.inter(fontWeight: FontWeight.bold),
                  ),
                )
              : null),
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

  Widget _buildCoverHeader(bool isDark, bool isDesktop) {
    final String cover = _trip?.coverUrl ?? '';
    final String title = _trip?.title ?? 'Sin Título';
    final String desc = _trip?.description ?? '';

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E22) : OhtliColors.cantera,
        border: Border(bottom: BorderSide(color: isDark ? const Color(0xFF2C2C32) : OhtliColors.cantera.withValues(alpha: 0.3))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (cover.isNotEmpty)
            Container(
              width: double.infinity,
              height: isDesktop ? 500 : 320,
              decoration: BoxDecoration(
                image: DecorationImage(
                  image: _getImageProvider(cover),
                  fit: BoxFit.cover,
                ),
              ),
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.black.withValues(alpha: 0.55),
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.65),
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
              ),
            ),
          Center(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 820),
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: GoogleFonts.outfit(
                                fontSize: isDesktop ? 32 : 24,
                                fontWeight: FontWeight.bold,
                                color: isDark ? OhtliColors.cantera : OhtliColors.onyx,
                                height: 1.15,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _formatSpanishDate(_trip?.travelDate),
                              style: GoogleFonts.inter(
                                fontSize: 12.5,
                                color: isDark ? Colors.white54 : OhtliColors.onyx.withValues(alpha: 0.6),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            if (!isDesktop) ...[
                              const SizedBox(height: 16),
                              Center(
                                child: _buildAuthorWidget(isDark),
                              ),
                            ],
                            if (desc.isNotEmpty) ...[
                              const SizedBox(height: 14),
                              OhtliMarkdownText(
                                text: desc,
                                style: GoogleFonts.inter(
                                  fontSize: 14.5,
                                  color: isDark ? Colors.white70 : OhtliColors.onyx.withValues(alpha: 0.7),
                                  height: 1.5,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (isDesktop) ...[
                        const SizedBox(width: 32),
                        _buildAuthorWidget(isDark),
                      ],
                    ],
                  ),
                  const SizedBox(height: 20),
                  Wrap(
                    spacing: 12,
                    runSpacing: 10,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      ElevatedButton.icon(
                        onPressed: _isExportingPdf ? null : () => _exportPdf(),
                        icon: _isExportingPdf
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.picture_as_pdf_rounded, size: 16),
                        label: Text(
                          _isExportingPdf ? 'Generando PDF...' : 'Generar PDF',
                          style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: OhtliColors.stormyTeal,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          elevation: 0,
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: _isExportingPdf ? null : () => _exportPdf(printOnly: true),
                        icon: const Icon(Icons.print_rounded, size: 16),
                        label: Text(
                          'Imprimir',
                          style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: isDark ? Colors.white70 : OhtliColors.onyx,
                          side: BorderSide(
                            color: isDark ? Colors.white24 : OhtliColors.onyx.withValues(alpha: 0.25),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
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

    return Padding(
      padding: const EdgeInsets.only(bottom: 36),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 350),
        padding: EdgeInsets.all(highlighted ? 10 : 0),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: highlighted ? OhtliColors.cempasuchil.withValues(alpha: isDark ? 0.16 : 0.10) : Colors.transparent,
        ),
        child: blockContent,
      ),
    );
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
        // Cost Badge
        if (place.cost > 0.0) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF332711) : const Color(0xFFFFFBEB),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isDark ? const Color(0xFFFBBF24).withValues(alpha: 0.25) : const Color(0xFFFDE68A),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.payments_outlined, size: 14, color: Colors.amber),
                const SizedBox(width: 6),
                Text(
                  "Costo estimado: \$ ${place.cost.toStringAsFixed(2)} ${place.currency}",
                  style: GoogleFonts.inter(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: isDark ? const Color(0xFFFBBF24) : const Color(0xFFB45309),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );

    if (isDesktop && drawOrderSlots.isNotEmpty) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          photoStackWidget,
          const SizedBox(width: 24),
          Expanded(child: infoWidget),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (drawOrderSlots.isNotEmpty) ...[
          Center(child: photoStackWidget),
          const SizedBox(height: 16),
        ],
        infoWidget,
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

  Widget _buildRouteMapAndChronologySection(bool isDark, bool isDesktop) {
    final places = _sections.whereType<PlaceSection>().toList();
    if (places.isEmpty) return const SizedBox.shrink();

    const mapsApiKey = String.fromEnvironment('mapsApiKey');
    const apiKey = String.fromEnvironment('apiKey');
    final activeKey = mapsApiKey.isNotEmpty ? mapsApiKey : apiKey;

    final markers = StringBuffer();
    final path = StringBuffer('&path=color:0x2F6B6Bff|weight:5');
    final waypointNames = <String>[];

    for (int i = 0; i < places.length; i++) {
      final p = places[i];
      final label = (i + 1).toString();
      if (p.lat != null && p.lng != null) {
        markers.write('&markers=color:0xE26D5C|label:$label|${p.lat},${p.lng}');
        path.write('|${p.lat},${p.lng}');
        waypointNames.add('${p.lat},${p.lng}');
      } else {
        final encodedName = Uri.encodeComponent('${p.title}, CDMX');
        markers.write('&markers=color:0xE26D5C|label:$label|$encodedName');
        waypointNames.add(encodedName);
      }
    }

    final staticMapUrl = activeKey.isNotEmpty
        ? 'https://maps.googleapis.com/maps/api/staticmap?size=900x420&scale=2&maptype=roadmap$path$markers&key=$activeKey'
        : '';

    String googleMapsDirectionsUrl = '';
    if (waypointNames.isNotEmpty) {
      final origin = waypointNames.first;
      final destination = waypointNames.last;
      final waypoints = waypointNames.length > 2
          ? waypointNames.sublist(1, waypointNames.length - 1).join('|')
          : '';
      googleMapsDirectionsUrl = 'https://www.google.com/maps/dir/?api=1&origin=$origin&destination=$destination' +
          (waypoints.isNotEmpty ? '&waypoints=$waypoints' : '') +
          '&travelmode=walking';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 28),
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E22) : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isDark ? Colors.white12 : OhtliColors.cardBorder,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.25 : 0.04),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header de la sección
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: OhtliColors.stormyTeal.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.map_rounded, color: OhtliColors.stormyTeal, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Mapa de la Ruta',
                        style: GoogleFonts.outfit(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : OhtliColors.onyx,
                        ),
                      ),
                      Text(
                        '${places.length} paradas organizadas cronológicamente',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: isDark ? Colors.white60 : OhtliColors.subtleText,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              if (googleMapsDirectionsUrl.isNotEmpty)
                ElevatedButton.icon(
                  onPressed: () {
                    html.window.open(googleMapsDirectionsUrl, '_blank');
                  },
                  icon: const Icon(Icons.open_in_new_rounded, size: 14),
                  label: Text(
                    isDesktop ? 'Abrir en Google Maps' : 'Abrir Mapa',
                    style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: OhtliColors.stormyTeal,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 18),

          // Contenedor visual del mapa con OpenStreetMap & OSRM
          OsrmMapWidget(
            onStopSelected: (stop) {
              final id = stop['section_id'];
              if (id is String) _scrollToBlock(id);
            },
            stops: places.map((p) => {
              'section_id': p.id,
              'name': p.title,
              'lat': p.lat,
              'lng': p.lng,
              'arrival_time': p.arrivalTime ?? '',
              'departure_time': p.departureTime ?? '',
              'price_mxn': p.cost,
            }).toList(),
            height: isDesktop ? 320 : 240,
            isDark: isDark,
          ),
          const SizedBox(height: 24),

          // Título de la Cronología
          Row(
            children: [
              const Icon(Icons.timeline_rounded, color: OhtliColors.cempasuchil, size: 18),
              const SizedBox(width: 8),
              Text(
                'Cronología del Recorrido',
                style: GoogleFonts.outfit(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : OhtliColors.onyx,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Lista de paradas de la cronología
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: places.length,
            itemBuilder: (context, idx) => InkWell(
              onTap: () => _scrollToBlock(places[idx].id),
              borderRadius: BorderRadius.circular(12),
              child: ((BuildContext context, int idx) {
              final p = places[idx];
              final isLast = idx == places.length - 1;
              final timeStr = p.arrivalTime != null ? '${p.arrivalTime}${p.departureTime != null ? " - ${p.departureTime}" : ""}' : 'Parada ${idx + 1}';

              final tr = idx > 0 ? transferBefore(_sections, _sections.indexOf(p)) : null;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                if (tr != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 42, bottom: 10, top: 0),
                    child: Row(
                      children: [
                        Icon(transferModeOf(tr.mode).icon, size: 15, color: OhtliColors.stormyTeal),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            describeTransfer(tr),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w600, color: isDark ? Colors.white60 : OhtliColors.subtleText),
                          ),
                        ),
                      ],
                    ),
                  ),
                IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Columna izquierda: Número y línea conectora
                    Column(
                      children: [
                        Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: OhtliColors.stormyTeal,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: OhtliColors.stormyTeal.withOpacity(0.3),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Center(
                            child: Text(
                              '${idx + 1}',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                        if (!isLast)
                          Expanded(
                            child: Container(
                              width: 2,
                              color: OhtliColors.stormyTeal.withOpacity(0.25),
                              margin: const EdgeInsets.symmetric(vertical: 4),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(width: 14),

                    // Columna derecha: Detalles de la parada
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(bottom: isLast ? 0 : 20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    p.title,
                                    style: GoogleFonts.outfit(
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                      color: isDark ? Colors.white : OhtliColors.onyx,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: OhtliColors.cempasuchil.withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    timeStr,
                                    style: GoogleFonts.inter(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: OhtliColors.cempasuchil,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if (p.cost > 0) ...[
                              const SizedBox(height: 3),
                              Text(
                                '\$${p.cost.toStringAsFixed(0)} ${p.currency}',
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: OhtliColors.stormyTeal,
                                ),
                              ),
                            ],
                            const SizedBox(height: 4),
                            Text(
                              p.description,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                color: isDark ? Colors.white60 : OhtliColors.subtleText,
                                height: 1.35,
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
            })(context, idx),
            ),
          ),
        ],
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

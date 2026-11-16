// ignore: avoid_web_libraries_in_flutter
import 'package:web/web.dart' as web;
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart' show PointerScrollEvent;
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
import '../../theme/release_tags.dart';
import '../../services/place_locator.dart';
import '../../services/trip_changes.dart';
import '../../services/trip_follow.dart';
import '../../services/live_location.dart';
import '../../services/push_service.dart';
import '../../services/trip_follow_remote.dart';
import 'trip_sample.dart';
import 'trip_traveler_tools.dart';
import '../../config/admin.dart' show isSuperUser;
import '../../utils/web_helpers.dart';
import '../../services/feedback_service.dart';

class TripViewerPage extends StatefulWidget {
  final Trip? trip;
  final String? tripId;
  final String? authorId;
  final bool isPublicLink;
  final VoidCallback? onLoginRedirect;
  final VoidCallback? onBackToDashboard;

  /// Vista previa desde el editor (E6): se muestran estos bloques sin leer Firestore.
  final List<TripSection>? previewSections;

  /// Abierto desde una tarjeta (crónica destacada de Explorar): se cierra con «Cerrar» o
  /// deslizando hacia abajo estando arriba del todo, y vuelve a la tarjeta.
  final bool presentedAsCard;

  const TripViewerPage({
    super.key,
    this.trip,
    this.tripId,
    this.authorId,
    this.isPublicLink = false,
    this.onLoginRedirect,
    this.onBackToDashboard,
    this.previewSections,
    this.presentedAsCard = false,
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

  // Cerrar deslizando hacia abajo (solo si se abrió desde una tarjeta).
  static const double _kPullClose = 150;
  final ValueNotifier<double> _pull = ValueNotifier<double>(0);
  bool _pullSnapping = false;
  bool _closingCard = false;
  bool _wasAtTop = true;
  DateTime _atTopSince = DateTime.now();
  Timer? _pullDecay;
  final ValueNotifier<double> _readProgress = ValueNotifier(0);
  final Map<String, GlobalKey> _blockKeys = {};
  final GlobalKey _mapKey = GlobalKey();
  String? _highlightedId;

  // Modo "estoy en el viaje" (V4): paradas visitadas en este dispositivo
  bool _tripMode = false;
  Set<String> _visited = {};

  // Seguir el viaje con la ubicación: llegada y salida automáticas y avisos para salir.
  final TripFollower _follower = TripFollower();
  LiveLocation? _live;
  bool _following = false;
  LocationProblem? _locationProblem;
  Timer? _followTimer;
  Set<String> _leaveAlertsSent = {};

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
  // Muestra de notas de versión (en lugar del viaje).
  bool _sampleNotes = false;
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
      _asideCollapsed = web.window.localStorage.getItem('ohtli_trip_aside_collapsed') == '1';
    } catch (_) {}
    _scrollController.addListener(_onScroll);
    _loadTripData();
  }

  @override
  void dispose() {
    _live?.stop();
    _followTimer?.cancel();
    _notesSub?.cancel();
    _reactionsSub?.cancel();
    _scrollController.dispose();
    _readProgress.dispose();
    _pullDecay?.cancel();
    _pull.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    _readProgress.value = pos.maxScrollExtent <= 0 ? 0 : (pos.pixels / pos.maxScrollExtent).clamp(0.0, 1.0);
    final bool atTop = pos.pixels <= pos.minScrollExtent + 0.5;
    if (atTop && !_wasAtTop) _atTopSince = DateTime.now();
    _wasAtTop = atTop;
  }

  // ---------------------------------------------------------------------------
  // Cerrar la crónica abierta desde una tarjeta
  // ---------------------------------------------------------------------------
  bool get _atTop =>
      !_scrollController.hasClients || _scrollController.position.pixels <= _scrollController.position.minScrollExtent + 0.5;

  /// Suma [d] al jalón hacia abajo. Con rueda o trackpad no cuenta si apenas se llegó
  /// arriba haciendo scroll (para no cerrar por inercia) y se cierra al pasar el umbral.
  void _pullBy(double d, {required bool wheel}) {
    if (!widget.presentedAsCard || _closingCard) return;
    if (wheel && DateTime.now().difference(_atTopSince) < const Duration(milliseconds: 450)) return;
    _pullSnapping = false;
    _pull.value = (_pull.value + d).clamp(0.0, _kPullClose * 1.3);
    if (wheel) {
      if (_pull.value >= _kPullClose) {
        _closeCard();
        return;
      }
      _pullDecay?.cancel();
      _pullDecay = Timer(const Duration(milliseconds: 450), _releasePull);
    }
  }

  void _releasePull() {
    if (_closingCard || _pull.value == 0) return;
    if (_pull.value >= _kPullClose) {
      _closeCard();
      return;
    }
    _pullSnapping = true;
    _pull.value = 0;
  }

  void _closeCard() {
    if (_closingCard) return;
    _closingCard = true;
    _pullDecay?.cancel();
    Navigator.of(context).maybePop();
  }

  bool _onCardScroll(ScrollNotification n) {
    if (!widget.presentedAsCard || n.depth != 0) return false;
    if (n is OverscrollNotification && n.dragDetails != null && n.overscroll < 0) {
      _pullBy(-n.overscroll, wheel: false);
    } else if (n is ScrollUpdateNotification && n.dragDetails != null) {
      final double delta = n.scrollDelta ?? 0;
      if (n.metrics.pixels < n.metrics.minScrollExtent) {
        // Física con rebote (iOS): la página ya se pasa del borde
        _pullSnapping = false;
        _pull.value = (n.metrics.minScrollExtent - n.metrics.pixels).clamp(0.0, _kPullClose * 1.3);
      } else if (_pull.value > 0 && delta > 0) {
        _pullBy(-delta, wheel: false);
      }
    } else if (n is ScrollEndNotification) {
      _releasePull();
    }
    return false;
  }

  /// Envuelve la página: al jalar se encoge y se redondea, con un aviso arriba.
  Widget _wrapPullToClose(Widget page, bool isDark) {
    return Listener(
      onPointerSignal: (e) {
        if (e is PointerScrollEvent && e.scrollDelta.dy < 0 && _atTop) _pullBy(-e.scrollDelta.dy * 0.6, wheel: true);
      },
      child: ValueListenableBuilder<double>(
        valueListenable: _pull,
        child: page,
        builder: (context, v, child) {
          return TweenAnimationBuilder<double>(
            tween: Tween(end: (v / _kPullClose).clamp(0.0, 1.0)),
            duration: _pullSnapping ? const Duration(milliseconds: 220) : Duration.zero,
            curve: Curves.easeOutCubic,
            child: child,
            builder: (context, p, child) => Stack(
              children: [
                Transform.translate(
                  offset: Offset(0, 48 * p),
                  child: Transform.scale(
                    scale: 1 - 0.08 * p,
                    alignment: Alignment.topCenter,
                    child: ClipRRect(borderRadius: BorderRadius.circular(28 * p), child: child),
                  ),
                ),
                if (p > 0.04)
                  Positioned(
                    top: 12,
                    left: 0,
                    right: 0,
                    child: IgnorePointer(
                      child: Center(
                        child: Opacity(
                          opacity: p,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(20)),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(p >= 1 ? Icons.close_rounded : Icons.keyboard_arrow_down_rounded, size: 16, color: Colors.white),
                                const SizedBox(width: 6),
                                Text(p >= 1 ? 'Suelta para cerrar' : 'Desliza para cerrar',
                                    style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w700, color: Colors.white)),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
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
      final raw = web.window.localStorage.getItem(_visitedStorageKey);
      if (raw != null) _visited = Set<String>.from(jsonDecode(raw) as List);
    } catch (_) {}
  }

  void _saveVisited() {
    try {
      web.window.localStorage.setItem(_visitedStorageKey, jsonEncode(_visited.toList()));
    } catch (_) {}
  }

  void _setTripMode(bool on) {
    if (on) _loadVisited();
    if (!on) _stopFollow();
    setState(() => _tripMode = on);
    if (on) {
      final next = _nextStop;
      if (next != null) WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBlock(next.id));
      _maybeResumeFollow();
    }
  }

  // ---------------------------------------------------------------------------
  // Seguir el viaje con la ubicación
  // ---------------------------------------------------------------------------
  String get _followPrefKey => 'ohtli_trip_follow_${_trip?.id ?? ''}';
  String get _leaveAlertsKey => 'ohtli_trip_leave_alerts_${_trip?.id ?? ''}';

  bool get _canFollow => _canEditContent && _phase == TripPhase.durante && !_isNotes;

  /// Donde están: llegaron y aún no salen.
  PlaceSection? get _hereStop {
    for (final p in _sections.whereType<PlaceSection>().toList().reversed) {
      if (p.arrivedAt != null && p.leftAt == null) return p;
    }
    return null;
  }

  /// Paradas a las que aún no llegan, en orden (sin la actual).
  List<PlaceSection> get _pendingStops {
    final here = _hereStop;
    return [
      for (final p in _sections.whereType<PlaceSection>())
        if (p.arrivedAt == null && !_visited.contains(p.id) && !identical(p, here)) p,
    ];
  }

  void _saveFollowPref(bool on) {
    try {
      web.window.localStorage.setItem(_followPrefKey, on ? '1' : '0');
    } catch (_) {}
  }

  void _loadLeaveAlerts() {
    // En la muestra los avisos se repiten en cada visita.
    if (_isSample) {
      _leaveAlertsSent = {};
      return;
    }
    try {
      final raw = web.window.localStorage.getItem(_leaveAlertsKey);
      _leaveAlertsSent = raw == null ? {} : (jsonDecode(raw) as List).map((e) => e.toString()).toSet();
    } catch (_) {
      _leaveAlertsSent = {};
    }
  }

  void _saveLeaveAlerts() {
    if (_isSample) return;
    try {
      web.window.localStorage.setItem(_leaveAlertsKey, jsonEncode(_leaveAlertsSent.toList()));
    } catch (_) {}
  }

  /// Si ya lo tenían encendido en este viaje y el navegador ya dio permiso, se retoma solo.
  Future<void> _maybeResumeFollow() async {
    if (_following || !_canFollow) return;
    String? pref;
    try {
      pref = web.window.localStorage.getItem(_followPrefKey);
    } catch (_) {}
    if (pref != '1') return;
    if (!await LiveLocation.granted()) return;
    if (!mounted || !_tripMode || _following) return;
    _startFollow();
  }

  Future<void> _toggleFollow() async {
    if (_following) {
      _stopFollow();
      _saveFollowPref(false);
      _notice('Ya no se sigue tu ubicación. Marca tu llegada y salida a mano.');
      return;
    }
    if (!LiveLocation.supported) {
      _notice('Este navegador no comparte la ubicación.');
      return;
    }
    // Los dos permisos se piden con el toque: avisos (también push, para avisar con Ohtli
    // cerrado) y ubicación.
    final notify = PushService.instance.enableFromTap();
    _startFollow();
    _saveFollowPref(true);
    final canNotify = await notify;
    if (!mounted) return;
    final push = PushService.instance.status.value;
    _notice(!canNotify
        ? (push == PushStatus.needsInstall
            ? 'Ohtli sigue tu viaje mientras esté abierto. En iPhone, agrega Ohtli a tu pantalla de inicio para que los avisos para salir lleguen con la app cerrada.'
            : 'Ohtli sigue tu viaje mientras esté abierto. Sin permiso de notificaciones, los avisos para salir solo se ven aquí.')
        : push == PushStatus.unsupported
        ? 'Ohtli sigue tu viaje mientras esté abierto: marca tu llegada y tu salida y te avisa cuándo salir.'
        : 'Ohtli marca tu llegada y tu salida mientras esté abierto, y te avisa cuándo salir aunque lo cierres.');
  }

  void _startFollow() {
    _live ??= LiveLocation(onFix: _onFix, onProblem: _onLocationProblem);
    _follower.reset();
    _locationProblem = null;
    _loadLeaveAlerts();
    _live!.start();
    _followTimer?.cancel();
    // Quien no se mueve casi no recibe lecturas: el reloj confirma llegadas, salidas y avisos.
    _followTimer = Timer.periodic(const Duration(seconds: 20), (_) => _followTick());
    setState(() => _following = true);
    // El servidor sigue avisando cuándo salir aunque cierren Ohtli (push). Se juntan los avisos
    // que ya dio, para no repetirlos aquí.
    final t = _trip;
    if (!_isSample && t != null) {
      TripFollowRemote.start(tripId: t.id, ownerId: t.userId).then((sent) {
        if (sent.isEmpty || !mounted) return;
        _leaveAlertsSent.addAll(sent);
        _saveLeaveAlerts();
      });
    }
  }

  void _stopFollow() {
    final wasFollowing = _following;
    _live?.stop();
    _followTimer?.cancel();
    _followTimer = null;
    if (_following && mounted) {
      setState(() => _following = false);
    } else {
      _following = false;
    }
    final t = _trip;
    if (wasFollowing && !_isSample && t != null) TripFollowRemote.stop(t.id);
  }

  void _onFix(GeoFix fix) {
    if (!mounted) return;
    _locationProblem = null;
    _followTick(fix: fix);
  }

  void _onLocationProblem(LocationProblem p) {
    if (!mounted) return;
    setState(() => _locationProblem = p);
  }

  FollowStop? _followStopOf(PlaceSection p) {
    final c = _coordsOf(p);
    return c == null ? null : FollowStop(p.id, c.$1, c.$2);
  }

  Future<void> _followTick({GeoFix? fix}) async {
    if (!mounted || !_following) return;
    if (!_tripMode || !_canFollow) {
      _stopFollow();
      return;
    }
    final here = _hereStop;
    final events = _follower.step(
      now: DateTime.now(),
      fix: fix,
      pending: [for (final p in _pendingStops) ?_followStopOf(p)],
      here: here == null ? null : _followStopOf(here),
    );
    setState(() {});
    for (final e in events) {
      await _applyFollowEvent(e);
    }
    _checkLeaveAlert();
  }

  PlaceSection? _placeById(String id) {
    for (final p in _sections.whereType<PlaceSection>()) {
      if (p.id == id) return p;
    }
    return null;
  }

  Future<void> _applyFollowEvent(FollowEvent e) async {
    final p = _placeById(e.stopId);
    if (p == null || !mounted) return;
    final at = _hhmm(e.at);
    final name = p.title.trim().isEmpty ? 'la parada' : p.title.trim();
    if (e.kind == FollowEventKind.arrive) {
      // Si otra parada seguía abierta, se cierra a la hora en que llegaron aquí.
      final open = _hereStop;
      final String? closed = (open != null && open.id != p.id) ? open.id : null;
      setState(() => _visited.add(p.id));
      _saveVisited();
      final ok = await _changeContent((l) {
        var out = l;
        if (closed != null) out = _updatePlace(out, closed, (x) => x.leftAt == null ? x.copyWith(leftAt: at) : x);
        return _updatePlace(out, p.id, (x) => x.arrivedAt == null ? x.copyWith(arrivedAt: at) : x);
      });
      if (!ok) return;
      _scrollSoon(p.id);
      _followNotice('Llegaste a $name', 'Ohtli marcó tu llegada a las $at.',
          tag: 'arrive-${p.id}', undo: () => _undoAutoArrival(p.id, closed: closed));
    } else {
      final ok = await _changeContent((l) => _updatePlace(l, p.id, (x) => x.leftAt == null ? x.copyWith(leftAt: at) : x));
      if (!ok) return;
      _followNotice('Saliste de $name', 'Ohtli marcó tu salida a las $at.', tag: 'leave-${p.id}', undo: () => _undoAutoLeave(p.id));
    }
  }

  /// "Deshacer": no estaban ahí. Esa parada ya no se marca sola; queda el botón "Llegué".
  Future<void> _undoAutoArrival(String id, {String? closed}) async {
    setState(() => _visited.remove(id));
    _saveVisited();
    await _changeContent((l) {
      var out = _updatePlace(l, id, (x) => x.copyWith(clearArrivedAt: true, clearLeftAt: true));
      if (closed != null) out = _updatePlace(out, closed, (x) => x.copyWith(clearLeftAt: true));
      return out;
    }, done: 'Llegada deshecha');
  }

  Future<void> _undoAutoLeave(String id) async {
    await _changeContent((l) => _updatePlace(l, id, (x) => x.copyWith(clearLeftAt: true)), done: 'Salida deshecha');
  }

  /// En pantalla, un aviso con "Deshacer"; con Ohtli en segundo plano, también una notificación.
  void _followNotice(String title, String body, {String tag = '', Future<void> Function()? undo, SnackBarAction? action}) {
    if (!WebNotify.pageVisible) WebNotify.show(title, body, tag: tag);
    if (!mounted) return;
    // El más reciente reemplaza al anterior y se va solo aunque tenga botón.
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text('$title. $body', style: GoogleFonts.inter()),
        duration: const Duration(seconds: 8),
        persist: false,
        action: undo != null ? SnackBarAction(label: 'Deshacer', onPressed: () => undo()) : action,
      ));
  }

  /// Cuándo salir de [here] para llegar a tiempo a la siguiente parada.
  LeavePlan? _leavePlanFor(PlaceSection here) {
    final pending = _pendingStops;
    final next = pending.isEmpty ? null : pending.first;
    final mins = next == null ? null : travelMinutesTo(_sections, next, from: here, fix: _following ? _follower.lastFix : null);
    return leavePlanFor(day: DateTime.now(), here: here, next: next, travelMins: mins);
  }

  void _checkLeaveAlert() {
    final here = _hereStop;
    if (here == null) return;
    final plan = _leavePlanFor(here);
    if (plan == null) return;
    final now = DateTime.now();
    final alert = leaveAlertAt(now, plan.leaveBy);
    if (alert == null) return;
    final key = '${alert.name}:${here.id}';
    if (_leaveAlertsSent.contains(key) || _leaveAlertsSent.contains('now:${here.id}')) return;
    _leaveAlertsSent.add(key);
    _saveLeaveAlerts();
    if (!_isSample && _trip != null) TripFollowRemote.markSent(_trip!.id, key);
    final next = plan.next;
    final text = leaveAlertText(sections: _sections, here: here, plan: plan, alert: alert, now: now);
    _followNotice(text.title, text.body,
        tag: 'leave-alert-${here.id}',
        action: next == null ? null : SnackBarAction(label: 'Cómo llegar', onPressed: () => _openDirectionsTo(next)));
  }

  String _followStatus(PlaceSection? here, PlaceSection? next) {
    if (_locationProblem == LocationProblem.denied) {
      return 'Sin permiso de ubicación: actívalo en tu navegador. Los avisos para salir siguen funcionando.';
    }
    final fix = _follower.lastFix;
    if (fix == null) {
      return _locationProblem == LocationProblem.unavailable ? 'Aún no encontramos tu ubicación…' : 'Buscando tu ubicación…';
    }
    if (here != null) {
      return _coordsOf(here) == null
          ? 'Esta parada no tiene ubicación: marca tu salida a mano.'
          : 'Tu salida se marca sola cuando te alejes.';
    }
    if (next != null) {
      final c = _coordsOf(next);
      if (c == null) return 'Esta parada no tiene ubicación: marca tu llegada a mano.';
      return 'A ${formatMeters(distanceMeters(fix.lat, fix.lng, c.$1, c.$2))} · tu llegada se marca sola';
    }
    return 'Siguiendo tu ubicación.';
  }

  Widget _buildFollowPill(bool isDark) {
    final bool on = _following;
    final Color teal = OhtliColors.stormyTeal;
    final Color fg = on ? Colors.white : (isDark ? Color.lerp(teal, Colors.white, 0.5)! : teal);
    return Tooltip(
      message: on
          ? 'Dejar de seguir tu ubicación'
          : 'Con tu ubicación, Ohtli marca tu llegada y tu salida (mientras esté abierto) y te avisa cuándo salir',
      child: Material(
        color: on ? teal : Colors.transparent,
        shape: StadiumBorder(side: BorderSide(color: on ? teal : teal.withValues(alpha: 0.55))),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: _toggleFollow,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(on ? Icons.my_location_rounded : Icons.location_searching_rounded, size: 14, color: fg),
                const SizedBox(width: 5),
                Text(on ? 'Siguiendo' : 'Seguir mi viaje',
                    style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w700, color: fg)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _toggleVisited(String id) {
    final wasVisited = _visited.contains(id);
    setState(() {
      if (!_visited.remove(id)) _visited.add(id);
    });
    if (!wasVisited) {
      final p = _sections.whereType<PlaceSection>().where((x) => x.id == id).firstOrNull;
      if (p != null) FeedbackService.visited(_catalogPoiOf(p), tripId: widget.tripId);
    }
    _saveVisited();
  }

  PlaceSection? get _nextStop {
    for (final p in _sections.whereType<PlaceSection>()) {
      if (!_visited.contains(p.id)) return p;
    }
    return null;
  }

  void _openDirectionsTo(PlaceSection p) {
    FeedbackService.directions(_catalogPoiOf(p), surface: 'trip');
    final c = _coordsOf(p);
    final dest = c != null
        ? '${c.$1},${c.$2}'
        : Uri.encodeComponent('${p.title}, Ciudad de México');
    final t = transferBefore(_sections, _sections.indexOf(p));
    final travelMode = t != null ? transferModeOf(t.mode).googleTravelMode : 'walking';
    web.window.open('https://www.google.com/maps/dir/?api=1&destination=$dest&travelmode=$travelMode', '_blank');
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
                    onPressed: () => web.window.open(routeUrl, '_blank'),
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

  /// Modo viaje: cambia según el momento. Rumbo a una parada: "Llegué", cómo llegar, traslado,
  /// desvío. En una parada: "Ya me voy", calificarla, foto, gasto, texto, imagen, tabla y nota.
  Widget _buildTripModePanel(bool isDark, {bool embedded = false}) {
    final places = _sections.whereType<PlaceSection>().toList();
    final Color fg = isDark ? Colors.white : const Color(0xFF1F2A2A);
    final Color sub = isDark ? Colors.white60 : OhtliColors.subtleText;
    final bool edit = _canEditContent;
    PlaceSection? here;
    for (final p in places.reversed) {
      if (p.arrivedAt != null && p.leftAt == null) {
        here = p;
        break;
      }
    }
    PlaceSection? next;
    for (final p in places) {
      if (p.arrivedAt == null && !_visited.contains(p.id) && !identical(p, here)) {
        next = p;
        break;
      }
    }
    final done = places.where((p) => p.arrivedAt != null || _visited.contains(p.id)).length;
    final PlaceSection? focus = here ?? next;

    Widget chip(IconData icon, String label, Future<void> Function() onTap) => ActionChip(
          avatar: Icon(icon, size: 16, color: isDark ? Color.lerp(OhtliColors.stormyTeal, Colors.white, 0.45) : OhtliColors.stormyTeal),
          label: Text(label, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: fg)),
          onPressed: () => onTap(),
          backgroundColor: isDark ? Colors.white.withValues(alpha: 0.06) : const Color(0xFFF3F6F5),
          side: BorderSide.none,
          visualDensity: VisualDensity.compact,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        );

    final String headline = here != null
        ? 'Estás en'
        : next != null
            ? (next.unplanned ? 'Desvío' : 'Siguiente parada')
            : '¡Recorrido completo!';

    final List<Widget> body = [];
    if (focus != null) {
      body.add(InkWell(
        onTap: () => _scrollToBlock(focus.id),
        child: Text(
          focus.title.isEmpty ? 'Parada sin nombre' : focus.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: fg),
        ),
      ));
      final LeavePlan? leave = here != null ? _leavePlanFor(here) : null;
      final bool timed = leave != null && leave.next != null && leave.arriveBy != null;
      body.add(Text(
        here != null
            ? 'Llegaron a las ${here.arrivedAt}${!timed && here.departureTime != null ? ' · el plan era salir a las ${here.departureTime}' : ''}'
            : (next!.arrivalTime != null ? 'En el plan: ${next.arrivalTime}' : 'Sin hora en el plan'),
        style: GoogleFonts.inter(fontSize: 12, color: sub),
      ));
      if (timed) {
        final bool late = !DateTime.now().isBefore(leave.leaveBy);
        final Color c = late ? OhtliColors.cempasuchil : (isDark ? Color.lerp(OhtliColors.stormyTeal, Colors.white, 0.45)! : OhtliColors.stormyTeal);
        final String nextName = leave.next!.title.trim().isEmpty ? 'la siguiente' : leave.next!.title.trim();
        body.add(Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            children: [
              Icon(late ? Icons.alarm_on_rounded : Icons.schedule_rounded, size: 14, color: c),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  late
                      ? 'Ya es hora de salir para llegar a $nextName a las ${_hhmm(leave.arriveBy!)}'
                      : 'Sal a las ${_hhmm(leave.leaveBy)} para llegar a $nextName a las ${_hhmm(leave.arriveBy!)}',
                  style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: c),
                ),
              ),
            ],
          ),
        ));
      }
      body.add(const SizedBox(height: 10));
    }

    if (here != null) {
      final h = here;
      // Calificar aquí mismo.
      if (edit)
        body.add(Row(
          children: [
            Text('¿Qué tal?', style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600, color: fg)),
            const SizedBox(width: 6),
            for (int i = 1; i <= 5; i++)
              InkResponse(
                radius: 18,
                onTap: () => _rateStop(h, i),
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: Icon(i <= h.rating ? Icons.star_rounded : Icons.star_outline_rounded, size: 24, color: i <= h.rating ? Colors.amber : sub),
                ),
              ),
          ],
        ));
      body.add(const SizedBox(height: 10));
      body.add(Wrap(spacing: 8, runSpacing: 8, children: [
        if (edit)
          FilledButton.icon(
            onPressed: () => _markLeave(h),
            style: FilledButton.styleFrom(
              backgroundColor: OhtliColors.stormyTeal,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            icon: const Icon(Icons.logout_rounded, size: 18),
            label: Text('Ya me voy', style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
          ),
        if (next != null)
          OutlinedButton.icon(
            onPressed: () => _openDirectionsTo(next!),
            style: OutlinedButton.styleFrom(
              foregroundColor: isDark ? Color.lerp(OhtliColors.stormyTeal, Colors.white, 0.5) : OhtliColors.stormyTeal,
              side: const BorderSide(color: OhtliColors.stormyTeal),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            icon: const Icon(Icons.directions_rounded, size: 18),
            label: Text('Ruta a la siguiente', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
          ),
      ]));
      if (edit) {
        body.add(const SizedBox(height: 10));
        body.add(Wrap(spacing: 6, runSpacing: 6, children: [
          chip(Icons.photo_camera_rounded, 'Foto', _addPhoto),
          chip(Icons.payments_rounded, 'Gasto', () async {
            final v = await askRealCost(context, placeName: h.title, current: h.realCost, estimated: h.cost, isDark: _dark);
            if (v != null) await _changeContent((l) => _updatePlace(l, h.id, (x) => x.copyWith(realCost: v)), done: 'Gasto guardado');
          }),
          chip(Icons.notes_rounded, 'Texto', () => _addContentBlock(BlockKind.text)),
          chip(Icons.image_rounded, 'Imagen', () => _addContentBlock(BlockKind.image)),
          chip(Icons.table_chart_rounded, 'Tabla', () => _addContentBlock(BlockKind.table)),
          chip(Icons.sticky_note_2_rounded, 'Nota', () => _addContentBlock(BlockKind.note)),
        ]));
      }
    } else if (next != null) {
      final n = next;
      body.add(Wrap(spacing: 8, runSpacing: 8, children: [
        FilledButton.icon(
          onPressed: () {
            if (edit) {
              _markArrival(n);
            } else {
              _toggleVisited(n.id);
            }
          },
          style: FilledButton.styleFrom(
            backgroundColor: OhtliColors.stormyTeal,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          icon: const Icon(Icons.flag_rounded, size: 18),
          label: Text(edit ? 'Llegué' : 'Ya la visité', style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
        ),
        OutlinedButton.icon(
          onPressed: () => _openDirectionsTo(n),
          style: OutlinedButton.styleFrom(
            foregroundColor: isDark ? Color.lerp(OhtliColors.stormyTeal, Colors.white, 0.5) : OhtliColors.stormyTeal,
            side: const BorderSide(color: OhtliColors.stormyTeal),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          icon: const Icon(Icons.directions_rounded, size: 18),
          label: Text('Cómo llegar', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
        ),
      ]));
      if (edit) {
        body.add(const SizedBox(height: 10));
        body.add(Wrap(spacing: 6, runSpacing: 6, children: [
          chip(Icons.route_rounded, 'Cómo van', _addTransfer),
          chip(Icons.alt_route_rounded, 'Desvío', _addDetour),
          chip(Icons.photo_camera_rounded, 'Foto', _addPhoto),
          chip(Icons.sticky_note_2_rounded, 'Nota', () => _addContentBlock(BlockKind.note)),
        ]));
      }
    } else {
      body.add(Text('Visitaron todas las paradas. Al terminar el viaje pasa a "después": calificar, completar precios, portadas y crónica.',
          style: GoogleFonts.inter(fontSize: 13, height: 1.4, color: fg)));
      if (edit) {
        body.add(const SizedBox(height: 10));
        body.add(Wrap(spacing: 8, runSpacing: 8, children: [
          FilledButton.icon(
            onPressed: _finishTrip,
            style: FilledButton.styleFrom(
              backgroundColor: OhtliColors.stormyTeal,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            icon: const Icon(Icons.flag_circle_rounded, size: 18),
            label: Text('Terminar el viaje', style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
          ),
          chip(Icons.photo_camera_rounded, 'Foto', _addPhoto),
        ]));
      }
    }
    // Se puede terminar antes de visitar todo (p. ej. si se cancela una parada).
    if (edit && (here != null || next != null)) {
      body.add(Align(
        alignment: Alignment.centerRight,
        child: TextButton.icon(
          onPressed: _finishTrip,
          style: TextButton.styleFrom(foregroundColor: sub, visualDensity: VisualDensity.compact),
          icon: const Icon(Icons.flag_circle_outlined, size: 16),
          label: Text('Terminar el viaje', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600)),
        ),
      ));
    }

    return Material(
      elevation: embedded ? 0 : 12,
      color: embedded ? Colors.transparent : (isDark ? const Color(0xFF1E1E22) : Colors.white),
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: EdgeInsets.fromLTRB(embedded ? 0 : 16, embedded ? 0 : 12, embedded ? 0 : 10, embedded ? 0 : 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(headline, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: here != null ? OhtliColors.cempasuchil : OhtliColors.stormyTeal)),
                ),
                if (_canFollow && (here != null || next != null)) ...[
                  _buildFollowPill(isDark),
                  const SizedBox(width: 10),
                ],
                Text('$done/${places.length}', style: GoogleFonts.inter(fontSize: 12, color: sub)),
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
            if (_following && (here != null || next != null)) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(_locationProblem == LocationProblem.denied ? Icons.location_disabled_rounded : Icons.near_me_rounded,
                      size: 13, color: _locationProblem == LocationProblem.denied ? OhtliColors.cempasuchil : sub),
                  const SizedBox(width: 5),
                  Expanded(child: Text(_followStatus(here, next), style: GoogleFonts.inter(fontSize: 11.5, color: sub))),
                ],
              ),
            ],
            const SizedBox(height: 10),
            ...body,
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
    if (_trip == null && stage == SampleStage.durante) _tripMode = true;
    if (_sampleNotes) {
      setState(() {
        _tripMode = false;
        _trip = TripSample.releaseNotes();
        _sections = TripSample.releaseNotesSections();
        _authorProfile = TripSample.author;
        _coAuthorsProfiles = TripSample.coAuthors;
        _visited = {};
        _isLoading = false;
      });
      return;
    }
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
    if (stage == _sampleStage && !_sampleNotes) return;
    _sampleStage = stage;
    _sampleNotes = false;
    // El modo viaje solo existe durante el viaje.
    _tripMode = stage == SampleStage.durante;
    if (!_tripMode) _stopFollow();
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
                        'Se borrará todo lo de «$replacedTitle»: paradas, textos, fotos, mensajes, reacciones y fe de erratas. '
                        'No se puede deshacer. Se conservan quiénes son coautores y su visibilidad.',
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
        final tripRef = trips.doc(id);
        // Reemplazar es empezar de cero: se borran los mensajes, las reacciones y la fe de
        // erratas del viaje anterior, y deja de estar terminado o calificado.
        for (final col in const ['notes', 'reactions']) {
          final docs = (await tripRef.collection(col).get()).docs;
          for (int i = 0; i < docs.length; i += 400) {
            final batch = FirebaseFirestore.instance.batch();
            for (final d in docs.skip(i).take(400)) {
              batch.delete(d.reference);
            }
            await batch.commit();
          }
        }
        await tripRef.update({
          'title': sample.title,
          'description': sample.description,
          'coverUrl': sample.coverUrl,
          'travelDate': Timestamp.fromDate(today),
          'updatedAt': Timestamp.fromDate(now),
          'errataHistory': <Map<String, dynamic>>[],
          'reviewedAt': FieldValue.delete(),
          'finishedAt': FieldValue.delete(),
        });
      }
      await TripService().updateTripContent(user.uid, id, TripContent(sections: sections));
      try {
        web.window.localStorage.removeItem('ohtli_trip_visited_$id');
      } catch (_) {}
      if (!mounted) return;
      _notice('Listo. Abriendo tu viaje…');
      web.window.location.assign('${Uri.base.origin}/?tripId=$id&authorId=${user.uid}');
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
    // "Notas" muestra unas notas de versión en lugar del viaje.
    final stageSeg = seg<SampleStage?>(
      [for (final st in SampleStage.values) (st, st.label), (null, 'Notas')],
      _sampleNotes ? null : _sampleStage,
      (st) {
        if (st != null) return _setSampleStage(st);
        if (_sampleNotes) return;
        _sampleNotes = true;
        _loadSample();
      },
    );
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
                  if (isSuperUser() && !_sampleNotes) ...[
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
  Future<bool> _changeContent(List<TripSection> Function(List<TripSection> sections) change,
      {String? done, List<String> extraChanges = const []}) async {
    final t = _trip;
    if (t == null) return false;
    if (_isSample) {
      final before = _sections;
      final next = change(List.of(_sections));
      setState(() => _sections = next);
      if (_phase == TripPhase.despues) await _recordErrata([...describeTripChanges(before, next), ...extraChanges]);
      if (done != null) _notice('$done. En la muestra no se guarda.');
      return true;
    }
    try {
      final saved = await TripService().getTripContent(t.userId, t.id);
      final before = saved?.sections ?? _sections;
      final next = change(List.of(before));
      await TripService().updateTripContent(t.userId, t.id, TripContent(sections: next));
      // Después del viaje, cada cambio queda en la fe de erratas con quién y cuándo.
      if (_phase == TripPhase.despues) await _recordErrata([...describeTripChanges(before, next), ...extraChanges]);
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

  /// poiId del catálogo de una parada (retroalimentación); null si es un lugar genérico.
  String? _catalogPoiOf(PlaceSection p) => (!_isSample && p.isLinkedToCatalog) ? p.poiId : null;

  Future<void> _markArrival(PlaceSection p) async {
    FeedbackService.visited(_catalogPoiOf(p), tripId: widget.tripId);
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

  // ---------------------------------------------------------------------------
  // Etapas del viaje
  // ---------------------------------------------------------------------------
  TripPhase get _phase {
    if (_isSample) {
      return switch (_sampleStage) {
        SampleStage.antes => TripPhase.antes,
        SampleStage.durante => TripPhase.durante,
        SampleStage.despues => TripPhase.despues,
      };
    }
    // Al terminar el viaje desde el modo viaje, ya es "después" aunque sea el mismo día.
    if (_trip?.finishedAt != null) return TripPhase.despues;
    final d = _trip?.travelDate;
    if (d == null) return TripPhase.antes;
    final now = DateTime.now();
    final day = DateTime(d.year, d.month, d.day);
    final today = DateTime(now.year, now.month, now.day);
    if (day.isAfter(today)) return TripPhase.antes;
    return day == today ? TripPhase.durante : TripPhase.despues;
  }

  bool get _isOwner => _isSample ? _sampleAsMember : (_trip != null && FirebaseAuth.instance.currentUser?.uid == _trip!.userId);

  List<PlaceSection> get _plannedStops => _sections.whereType<PlaceSection>().where((p) => !p.unplanned).toList();

  /// Rejilla de herramientas (4 por fila).
  Widget _toolGrid(bool isDark, List<(IconData, String, VoidCallback)> tools) {
    final Color fg = isDark ? Colors.white : const Color(0xFF1F2A2A);
    return LayoutBuilder(builder: (context, box) {
      final double w = ((box.maxWidth - 3 * 8) / 4).floorToDouble();
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final t in tools)
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
    });
  }

  /// Antes: horarios, presupuesto, invitar y guardar el itinerario.
  Widget _buildPlanCard(bool isDark, bool canEdit, {VoidCallback? onDone}) {
    final Color sub = isDark ? Colors.white60 : OhtliColors.subtleText;
    void run(Future<void> Function() f) {
      onDone?.call();
      f();
    }

    final stops = _plannedStops;
    final double budget = stops.fold<double>(0, (a, p) => a + p.cost) +
        _sections.whereType<TransferSection>().fold<double>(0, (a, t) => a + t.cost);
    final starts = stops.map((p) => _minutesOf(p.arrivalTime)).whereType<int>().toList();
    final ends = stops.map((p) => _minutesOf(p.departureTime) ?? _minutesOf(p.arrivalTime)).whereType<int>().toList();
    String hm(int m) => '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';
    final d = _trip?.travelDate;
    int? daysLeft;
    if (d != null) {
      final now = DateTime.now();
      daysLeft = DateTime(d.year, d.month, d.day).difference(DateTime(now.year, now.month, now.day)).inDays;
    }

    return _panelCard(isDark: isDark, icon: Icons.edit_calendar_rounded, title: 'PLANEAR EL VIAJE', children: [
      Text(
        daysLeft == null
            ? 'Aún no tiene fecha. Ajusten horarios y presupuesto, e inviten a quien falte.'
            : (daysLeft == 1 ? 'Es mañana. ' : 'Faltan $daysLeft días. ') + 'Ajusten horarios y presupuesto, e inviten a quien falte.',
        style: GoogleFonts.inter(fontSize: 12.5, height: 1.4, color: sub),
      ),
      const SizedBox(height: 10),
      Row(
        children: [
          Expanded(child: _planFact(isDark, Icons.schedule_rounded, starts.isEmpty ? 'Sin horario' : '${hm(starts.reduce(math.min))}–${hm(ends.reduce(math.max))}')),
          const SizedBox(width: 8),
          Expanded(child: _planFact(isDark, Icons.account_balance_wallet_rounded, budget > 0 ? '\$${budget.toStringAsFixed(0)} MXN' : 'Sin presupuesto')),
        ],
      ),
      const SizedBox(height: 12),
      _toolGrid(isDark, [
        if (_canEditContent) (Icons.schedule_rounded, 'Horarios', () => run(_editSchedule)),
        if (_canEditContent) (Icons.account_balance_wallet_rounded, 'Presupuesto', () => run(_editBudget)),
        (Icons.person_add_alt_1_rounded, 'Invitar', () => run(() => _inviteTravelers(canEdit))),
        (Icons.download_for_offline_rounded, 'Guardar', () => run(_saveItinerary)),
      ]),
    ]);
  }

  Widget _planFact(bool isDark, IconData icon, String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: OhtliColors.stormyTeal.withValues(alpha: isDark ? 0.16 : 0.07),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, size: 15, color: isDark ? Color.lerp(OhtliColors.stormyTeal, Colors.white, 0.5) : OhtliColors.stormyTeal),
            const SizedBox(width: 6),
            Expanded(
              child: Text(text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: isDark ? Colors.white : const Color(0xFF1F2A2A))),
            ),
          ],
        ),
      );

  /// Después: calificar, completar precios, modificar, portadas, fotos y convertir en crónica.
  Widget _buildAfterCard(bool isDark, bool canEdit, {VoidCallback? onDone}) {
    final Color fg = isDark ? Colors.white : const Color(0xFF1F2A2A);
    final Color sub = isDark ? Colors.white60 : OhtliColors.subtleText;
    void run(Future<void> Function() f) {
      onDone?.call();
      f();
    }

    final t = _trip!;
    final places = _sections.whereType<PlaceSection>().toList();
    final rated = places.where((p) => p.rating > 0).toList();
    final avg = rated.isEmpty ? 0.0 : rated.fold<int>(0, (a, p) => a + p.rating) / rated.length;
    final double spent = places.fold<double>(0, (a, p) => a + (p.realCost ?? 0));
    final bool isChronicle = t.status == 'published' && t.visibility == 'public';

    return _panelCard(isDark: isDark, icon: Icons.auto_stories_rounded, title: 'DESPUÉS DEL VIAJE', children: [
      if (rated.isNotEmpty) ...[
        Row(
          children: [
            ...List.generate(5, (i) => Icon(i < avg.round() ? Icons.star_rounded : Icons.star_outline_rounded, size: 19, color: Colors.amber)),
            const SizedBox(width: 6),
            Text(avg.toStringAsFixed(1), style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: fg)),
            const Spacer(),
            if (spent > 0) Text('Gastaron \$${spent.toStringAsFixed(0)}', style: GoogleFonts.inter(fontSize: 12, color: sub)),
          ],
        ),
        const SizedBox(height: 4),
        Text('${rated.length} de ${places.length} paradas calificadas.', style: GoogleFonts.inter(fontSize: 12, color: sub)),
      ] else
        Text('Ya pasó ${_formatSpanishDate(t.travelDate)}. Califiquen, completen lo que faltó y cuéntenlo como crónica.',
            style: GoogleFonts.inter(fontSize: 12.5, height: 1.4, color: fg)),
      const SizedBox(height: 12),
      _toolGrid(isDark, [
        if (canEdit) (Icons.star_rounded, 'Calificar', () => run(() async => _showReviewDialog(isDark))),
        if (_canEditContent) (Icons.receipt_long_rounded, 'Precios', () => run(_completePrices)),
        if (canEdit) (Icons.edit_rounded, 'Modificar', () => run(() async => _openEditorOrErrata(canEdit))),
        if (_canEditContent) (Icons.wallpaper_rounded, 'Portadas', () => run(_setCover)),
        if (_canEditContent) (Icons.photo_camera_rounded, 'Fotos', () => run(_addPhoto)),
        if (_isOwner) (Icons.auto_stories_rounded, isChronicle ? 'Crónica ✓' : 'Crónica', () => run(_convertToChronicle)),
        (Icons.history_edu_rounded, t.errataHistory.isEmpty ? 'Erratas' : 'Erratas (${t.errataHistory.length})', () => run(_showErrataLog)),
      ]),
      const SizedBox(height: 10),
      Text('Después del viaje todo se puede editar; cada cambio queda en la fe de erratas con quién y cuándo.',
          style: GoogleFonts.inter(fontSize: 11.5, height: 1.4, color: sub)),
    ]);
  }

  // ---------- acciones de planear
  Future<void> _editSchedule() async {
    final stops = _plannedStops;
    if (stops.isEmpty) return;
    final r = await askSchedule(context,
        stops: [for (final p in stops) (id: p.id, name: p.title.isEmpty ? 'Parada' : p.title, arrival: p.arrivalTime, departure: p.departureTime)],
        isDark: _dark);
    if (r == null) return;
    await _changeContent(
      (l) => [
        for (final s in l)
          if (s is PlaceSection && r.containsKey(s.id))
            s.copyWith(
              arrivalTime: r[s.id]!.$1,
              departureTime: r[s.id]!.$2,
              clearArrivalTime: r[s.id]!.$1 == null,
              clearDepartureTime: r[s.id]!.$2 == null,
            )
          else
            s,
      ],
      done: 'Horarios guardados',
    );
  }

  Future<void> _editBudget() async {
    final rows = <AmountRow>[
      for (final s in _sections)
        if (s is PlaceSection && !s.unplanned)
          (id: s.id, name: s.title.isEmpty ? 'Parada' : s.title, value: s.cost, isTransfer: false)
        else if (s is TransferSection)
          (id: s.id, name: describeTransfer(s), value: s.cost, isTransfer: true),
    ];
    if (rows.isEmpty) return;
    final r = await askAmounts(context,
        title: 'Presupuesto',
        subtitle: 'Cuánto calculan gastar en cada parada y traslado.',
        icon: Icons.account_balance_wallet_rounded,
        action: 'Guardar presupuesto',
        rows: rows,
        isDark: _dark);
    if (r == null) return;
    await _changeContent(
      (l) => [
        for (final s in l)
          if (s is PlaceSection && r.containsKey(s.id))
            s.copyWith(cost: r[s.id])
          else if (s is TransferSection && r.containsKey(s.id))
            s.copyWith(cost: r[s.id])
          else
            s,
      ],
      done: 'Presupuesto guardado',
    );
  }

  Future<void> _inviteTravelers(bool canEdit) async {
    final choice = await askChoice<String>(context,
        title: 'Invitar viajeros',
        subtitle: 'Quien se una puede escribir, reaccionar y usar las herramientas del viaje.',
        icon: Icons.person_add_alt_1_rounded,
        isDark: _dark,
        options: [
          (icon: Icons.ios_share_rounded, title: 'Compartir el enlace', subtitle: 'Por WhatsApp, correo o con código QR.', value: 'link'),
          if (canEdit) (icon: Icons.group_add_rounded, title: 'Agregar coautores', subtitle: 'Desde el editor, entre tus amigos de Ohtli.', value: 'coautores'),
        ]);
    if (!mounted || choice == null) return;
    if (choice == 'link') {
      _showShareDialog(_dark);
    } else {
      _openEditorOrErrata(canEdit);
    }
  }

  Future<void> _saveItinerary() async {
    final choice = await askChoice<String>(context,
        title: 'Guardar el itinerario',
        subtitle: 'Para tenerlo a la mano el día del viaje.',
        icon: Icons.download_for_offline_rounded,
        isDark: _dark,
        options: [
          (icon: Icons.picture_as_pdf_rounded, title: 'Descargar PDF', subtitle: 'Con mapa, horarios y un código QR al viaje.', value: 'pdf'),
          (icon: Icons.event_rounded, title: 'Agregar al calendario', subtitle: 'Cada parada como evento (archivo .ics).', value: 'ics'),
        ]);
    if (!mounted || choice == null) return;
    if (choice == 'pdf') {
      _exportPdf();
    } else {
      _downloadCalendar();
    }
  }

  void _downloadCalendar() {
    final t = _trip;
    if (t == null) return;
    final day = t.travelDate ?? DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    String stamp(DateTime x) => '${x.year}${two(x.month)}${two(x.day)}T${two(x.hour)}${two(x.minute)}00';
    String esc(String v) => v.replaceAll('\\', '\\\\').replaceAll(';', '\;').replaceAll(',', '\\,').replaceAll('\n', '\\n');
    final b = StringBuffer('BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//Ohtli//Viaje//ES\r\nCALSCALE:GREGORIAN\r\n');
    int count = 0;
    for (final p in _plannedStops) {
      final startMin = _minutesOf(p.arrivalTime);
      if (startMin == null) continue;
      final start = DateTime(day.year, day.month, day.day, startMin ~/ 60, startMin % 60);
      final endMin = _minutesOf(p.departureTime);
      final end = endMin != null && endMin > startMin
          ? DateTime(day.year, day.month, day.day, endMin ~/ 60, endMin % 60)
          : start.add(const Duration(hours: 1));
      final c = _coordsOf(p);
      b
        ..write('BEGIN:VEVENT\r\n')
        ..write('UID:${t.id}-${p.id}@ohtli.quest\r\n')
        ..write('DTSTAMP:${stamp(DateTime.now())}\r\n')
        ..write('DTSTART:${stamp(start)}\r\n')
        ..write('DTEND:${stamp(end)}\r\n')
        ..write('SUMMARY:${esc(p.title)}\r\n')
        ..write('DESCRIPTION:${esc('${t.title} · Ohtli')}\r\n');
      if (c != null) b.write('LOCATION:${c.$1}\\,${c.$2}\r\nGEO:${c.$1};${c.$2}\r\n');
      b.write('END:VEVENT\r\n');
      count++;
    }
    b.write('END:VCALENDAR\r\n');
    if (count == 0) {
      _notice('Agrega horarios a las paradas para poder pasarlas al calendario.');
      return;
    }
    downloadBytes(
      utf8.encode(b.toString()),
      '${t.title.isEmpty ? 'viaje' : t.title}.ics',
      'text/calendar',
    );
  }

  // ---------- acciones de después
  Future<void> _completePrices() async {
    final places = _sections.whereType<PlaceSection>().toList();
    if (places.isEmpty) return;
    final r = await askAmounts(context,
        title: 'Completar precios',
        subtitle: 'Lo que realmente gastaron en cada parada.',
        icon: Icons.receipt_long_rounded,
        action: 'Guardar precios',
        // Solo lo ya registrado: el estimado no se toma como gasto real.
        rows: [for (final p in places) (id: p.id, name: p.title.isEmpty ? 'Parada' : p.title, value: p.realCost ?? 0, isTransfer: false)],
        isDark: _dark);
    if (r == null) return;
    await _changeContent(
      (l) => [
        for (final s in l)
          if (s is PlaceSection && r.containsKey(s.id))
            (r[s.id]! > 0 ? s.copyWith(realCost: r[s.id]) : s.copyWith(clearRealCost: true))
          else
            s,
      ],
      done: 'Precios guardados',
    );
  }

  Future<void> _convertToChronicle() async {
    final t = _trip;
    if (t == null) return;
    final unvisited = _sections.whereType<PlaceSection>().where((p) => !p.unplanned && p.arrivedAt == null && !_visited.contains(p.id)).toList();
    final estimated = _sections.whereType<TransferSection>().where((x) => x.isEstimated).length;
    final o = await askChronicle(context,
        unvisited: [for (final p in unvisited) p.title],
        estimatedTransfers: estimated,
        alreadyPublic: t.visibility == 'public' && t.status == 'published',
        isDark: _dark);
    if (o == null) return;
    final removeIds = {if (o.removeUnvisited) ...unvisited.map((p) => p.id)};
    final bool willPublish = o.makePublic && !(t.visibility == 'public' && t.status == 'published');
    final ok = await _changeContent(extraChanges: [if (willPublish) 'Se convirtió en crónica pública'], (l) {
      final kept = <TripSection>[];
      for (final s in l) {
        if (removeIds.contains(s.id)) continue;
        if (o.removeEstimated && s is TransferSection && s.isEstimated) continue;
        // Al quitar una parada quedan dos traslados seguidos: se conserva el primero.
        if (s is TransferSection && kept.isNotEmpty && kept.last is TransferSection) continue;
        kept.add(s);
      }
      while (kept.isNotEmpty && kept.first is TransferSection) {
        kept.removeAt(0);
      }
      while (kept.isNotEmpty && kept.last is TransferSection) {
        kept.removeLast();
      }
      return kept;
    });
    if (!ok || !o.makePublic) {
      if (ok) _notice('Listo: el viaje quedó como crónica.');
      return;
    }
    try {
      if (!_isSample) {
        await FirebaseFirestore.instance.collection('users').doc(t.userId).collection('trips').doc(t.id).update({
          'status': 'published',
          'visibility': 'public',
          'updatedAt': Timestamp.now(),
        });
      }
      if (!mounted) return;
      setState(() => _trip = Trip.fromMap({...t.toMap(), 'status': 'published', 'visibility': 'public'}, t.id));
      _notice(_isSample ? 'Así se vería como crónica pública. En la muestra no se guarda.' : 'Listo: ya es una crónica pública y aparece en Explorar.');
    } catch (e) {
      _notice(friendlyError(e, fallback: 'Se limpió el plan, pero no se pudo publicar.'));
    }
  }

  // ---------------------------------------------------------------------------
  // Fe de erratas: después del viaje, cada cambio queda con quién, cuándo y qué
  // ---------------------------------------------------------------------------
  Future<void> _recordErrata(List<String> changes, {String note = ''}) async {
    final t = _trip;
    if (t == null || (changes.isEmpty && note.trim().isEmpty)) return;
    final entry = ErrataEntry(
      id: 'e${DateTime.now().microsecondsSinceEpoch}',
      note: note.trim(),
      date: DateTime.now(),
      authorId: _myUid ?? '',
      authorName: _myDisplayName,
      changes: changes,
    );
    try {
      if (!_isSample) {
        await FirebaseFirestore.instance.collection('users').doc(t.userId).collection('trips').doc(t.id).update({
          'errataHistory': FieldValue.arrayUnion([entry.toMap()]),
          'updatedAt': Timestamp.now(),
        });
      }
      if (!mounted) return;
      final current = _trip!;
      setState(() => _trip = Trip.fromMap({
            ...current.toMap(),
            'errataHistory': [...current.errataHistory.map((e) => e.toMap()), entry.toMap()],
          }, current.id));
    } catch (e) {
      _notice(friendlyError(e, fallback: 'El cambio se guardó, pero no quedó en la fe de erratas.'));
    }
  }

  /// Termina el viaje desde el modo viaje: desde ahí está en "después".
  Future<void> _finishTrip() async {
    final t = _trip;
    if (t == null) return;
    final isDark = _dark;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E1E22) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: Text('¿Terminar el viaje?', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
        content: SizedBox(
          width: 420,
          child: Text(
            'Sale el modo viaje y pasa a "después": calificar, completar precios, agregar portadas y fotos, y convertirlo en crónica. '
            'Desde ahí, cada cambio queda en la fe de erratas con quién y cuándo lo hizo.',
            style: GoogleFonts.inter(fontSize: 13.5, height: 1.45),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Seguir en el viaje')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: OhtliColors.stormyTeal, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Terminar el viaje'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final now = DateTime.now();
    try {
      if (_isSample) {
        _setSampleStage(SampleStage.despues);
        _notice('Viaje terminado: ya está en "después". En la muestra no se guarda.');
        return;
      }
      await FirebaseFirestore.instance.collection('users').doc(t.userId).collection('trips').doc(t.id).update({
        'finishedAt': Timestamp.fromDate(now),
        'updatedAt': Timestamp.fromDate(now),
      });
      // Éxito de la recomendación: la persona hizo el viaje.
      FeedbackService.itineraryCompleted(tripId: t.id, jobId: t.recommendationJobId);
      if (!mounted) return;
      _stopFollow();
      setState(() {
        _tripMode = false;
        _trip = Trip.fromMap({...t.toMap(), 'finishedAt': Timestamp.fromDate(now)}, t.id);
      });
      _notice('Viaje terminado. Ya pueden calificar, completar precios y convertirlo en crónica.');
    } catch (e) {
      _notice(friendlyError(e, fallback: 'No se pudo terminar el viaje.'));
    }
  }

  static String _errataStamp(DateTime d) {
    const months = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];
    return '${d.day} ${months[d.month - 1]} ${d.year} · ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  /// Ver fe de erratas: quién cambió qué y cuándo, lo más reciente primero.
  Future<void> _showErrataLog() async {
    final isDark = _dark;
    final Color fg = isDark ? Colors.white : const Color(0xFF1F2A2A);
    final Color sub = isDark ? Colors.white60 : OhtliColors.subtleText;
    final noteCtrl = TextEditingController();
    final bool canNote = _canEditContent;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final entries = (_trip?.errataHistory ?? const <ErrataEntry>[]).reversed.toList();
          return Dialog(
            backgroundColor: isDark ? const Color(0xFF1E1E22) : Colors.white,
            insetPadding: const EdgeInsets.all(16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560, maxHeight: 720),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.history_edu_rounded, color: OhtliColors.xoconostle),
                        const SizedBox(width: 10),
                        Expanded(child: Text('Fe de erratas', style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.bold, color: fg))),
                        IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close_rounded)),
                      ],
                    ),
                    Text('Lo que se cambió después del viaje, quién y cuándo.', style: GoogleFonts.inter(fontSize: 12.5, color: sub)),
                    const SizedBox(height: 14),
                    Flexible(
                      child: entries.isEmpty
                          ? Padding(
                              padding: const EdgeInsets.symmetric(vertical: 24),
                              child: Text('Todavía no hay cambios después del viaje.', textAlign: TextAlign.center, style: GoogleFonts.inter(color: sub)),
                            )
                          : ListView.separated(
                              shrinkWrap: true,
                              itemCount: entries.length,
                              separatorBuilder: (_, __) => Divider(height: 22, color: isDark ? Colors.white10 : OhtliColors.cardBorder),
                              itemBuilder: (_, i) {
                                final e = entries[i];
                                final who = e.authorName.isNotEmpty ? e.authorName : 'Autor del viaje';
                                return Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    CircleAvatar(
                                      radius: 15,
                                      backgroundColor: OhtliColors.xoconostle.withValues(alpha: 0.15),
                                      child: Text(who.characters.first.toUpperCase(),
                                          style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w800, color: OhtliColors.xoconostle)),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text.rich(TextSpan(children: [
                                            TextSpan(text: who, style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w700, color: fg)),
                                            TextSpan(text: '  ${_errataStamp(e.date)}', style: GoogleFonts.inter(fontSize: 12, color: sub)),
                                          ])),
                                          if (e.note.isNotEmpty) ...[
                                            const SizedBox(height: 4),
                                            Text(e.note, style: GoogleFonts.inter(fontSize: 13.5, height: 1.45, color: fg)),
                                          ],
                                          for (final c in e.changes)
                                            Padding(
                                              padding: const EdgeInsets.only(top: 4),
                                              child: Row(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Padding(
                                                    padding: const EdgeInsets.only(top: 7, right: 8),
                                                    child: Container(width: 5, height: 5, decoration: const BoxDecoration(color: OhtliColors.xoconostle, shape: BoxShape.circle)),
                                                  ),
                                                  Expanded(child: Text(c, style: GoogleFonts.inter(fontSize: 13, height: 1.4, color: fg.withValues(alpha: 0.85)))),
                                                ],
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                    ),
                    if (canNote) ...[
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: noteCtrl,
                              onChanged: (_) => setLocal(() {}),
                              minLines: 1,
                              maxLines: 3,
                              style: GoogleFonts.inter(fontSize: 13.5, color: fg),
                              decoration: InputDecoration(
                                hintText: 'Agregar una aclaración o corrección',
                                isDense: true,
                                filled: true,
                                fillColor: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF4F6F5),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          FilledButton(
                            onPressed: noteCtrl.text.trim().isEmpty
                                ? null
                                : () async {
                                    final text = noteCtrl.text.trim();
                                    noteCtrl.clear();
                                    await _recordErrata(const [], note: text);
                                    setLocal(() {});
                                  },
                            style: FilledButton.styleFrom(backgroundColor: OhtliColors.xoconostle, foregroundColor: Colors.white),
                            child: const Text('Publicar'),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
    noteCtrl.dispose();
  }

  /// Calificar la parada en curso desde el modo viaje.
  Future<void> _rateStop(PlaceSection p, int stars) async {
    // 4 o 5 estrellas en el lugar mismo: le gustó (no se usa la baja como "no me interesa")
    if (stars >= 4) FeedbackService.track('poi_like', poiId: _catalogPoiOf(p), tripId: widget.tripId, surface: 'trip');
    await _changeContent((l) => _updatePlace(l, p.id, (x) => x.copyWith(rating: stars)), done: '${p.title}: $stars ${stars == 1 ? 'estrella' : 'estrellas'}');
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

  /// Sombra de los bloques flotantes del panel lateral.
  static List<BoxShadow> _floatShadow(bool isDark) => [
        BoxShadow(color: Colors.black.withValues(alpha: isDark ? 0.42 : 0.10), blurRadius: 22, offset: const Offset(0, 8)),
        BoxShadow(color: Colors.black.withValues(alpha: isDark ? 0.22 : 0.04), blurRadius: 3, offset: const Offset(0, 1)),
      ];

  BoxDecoration _floatBlock(bool isDark, {double radius = 22}) => BoxDecoration(
        color: isDark ? const Color(0xFF1E1E22) : Colors.white,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: isDark ? Colors.white10 : OhtliColors.cardBorder.withValues(alpha: 0.7)),
        boxShadow: _floatShadow(isDark),
      );

  /// Bloque flotante independiente del panel (viajeros, planear, después, actividad…).
  Widget _panelCard({required bool isDark, required IconData icon, required String title, required List<Widget> children}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: _floatBlock(isDark),
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

    // Una tarjeta por etapa: antes se planea, durante va el modo viaje y después se cierra.
    final phase = _phase;
    if (phase == TripPhase.antes) cards.add(_buildPlanCard(isDark, canEdit, onDone: onDone));
    // Durante el viaje, el modo viaje vive abajo (flotante); en el panel lateral no se repite.
    // En el panel "Tu viaje" del teléfono sí queda el botón para activarlo.
    if (phase == TripPhase.durante && places.isNotEmpty && onDone != null) {
      cards.add(_panelCard(isDark: isDark, icon: Icons.near_me_rounded, title: 'MODO VIAJE', children: [
          Text(
            _tripMode
                ? 'El modo viaje está activo.'
                : 'Hoy es el viaje. En el modo viaje el panel te muestra lo que toca en cada momento: llegar, calificar, guardar fotos y gastos, desviarse.',
            style: GoogleFonts.inter(fontSize: 13, height: 1.45, color: fg),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () {
                onDone();
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
      ]));
    }
    if (phase == TripPhase.despues) cards.add(_buildAfterCard(isDark, canEdit, onDone: onDone));

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
                        Text.rich(heartSafeSpan(n.text, GoogleFonts.inter(fontSize: 12.5, height: 1.35, color: sub)), maxLines: 2, overflow: TextOverflow.ellipsis),
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
              downloadBytes(utf8.encode(svg), 'ohtli-viaje-qr.svg', 'image/svg+xml');
            },
            icon: const Icon(Icons.qr_code_2_rounded, size: 18),
            label: Text('Descargar QR', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextButton(
                onPressed: () {
                  FeedbackService.itineraryShared(tripId: _trip!.id, jobId: _trip!.recommendationJobId, channel: 'compartir');
                  Share.share('${_trip!.title} — ${_trip!.isReleaseNotes ? 'novedades de Ohtli' : 'mi viaje en Ohtli'}\n$url');
                },
                child: Text('Más…', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
              ),
              const SizedBox(width: 4),
              FilledButton.icon(
                onPressed: () async {
                  FeedbackService.itineraryShared(tripId: _trip!.id, jobId: _trip!.recommendationJobId, channel: 'enlace');
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

    final reviewChanges = _phase == TripPhase.despues ? describeTripChanges(_sections, updated) : const <String>[];
    if (_isSample) {
      final t = _trip!;
      setState(() {
        _sections = updated;
        _trip = Trip.fromMap({...t.toMap(), 'reviewedAt': Timestamp.now()}, t.id);
      });
      await _recordErrata(reviewChanges);
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
      await _recordErrata(reviewChanges);
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
      // Las notas de versión no tienen coautores (solo las escribe el administrador).
      if (_trip!.coAuthorIds.isNotEmpty && !_trip!.isReleaseNotes) {
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
    if (_errorCode == 404 && !web.window.navigator.onLine) {
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
    // Después del viaje, los coautores también editan todo; cada cambio queda en la fe de erratas.
    final bool canEdit = isOwner || (isCoAuthor && _trip != null && (_trip!.status == 'draft' || _phase == TripPhase.despues));

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
        return NotificationListener<ScrollNotification>(
          onNotification: _onCardScroll,
          child: SingleChildScrollView(
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
                      if (!_isNotes && !wideAside && _sections.any((s) => s is PlaceSection))
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
              // Espacio para que el panel flotante del modo viaje no tape el final.
              SizedBox(height: _tripMode ? 360 : 110),
            ],
          ),
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
              if (_tripMode && !isLocked)
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
              if (widget.presentedAsCard)
                Positioned(
                  top: MediaQuery.of(context).padding.top + 12,
                  left: 16,
                  child: Material(
                    color: (isDark ? const Color(0xFF1E1E22) : Colors.white).withValues(alpha: 0.9),
                    shape: const StadiumBorder(),
                    elevation: 3,
                    child: InkWell(
                      customBorder: const StadiumBorder(),
                      onTap: _closeCard,
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: isDesktop ? 14 : 9, vertical: 9),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.close_rounded, size: 18, color: isDark ? Colors.white : OhtliColors.onyx),
                            if (isDesktop) ...[
                              const SizedBox(width: 6),
                              Text('Cerrar',
                                  style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: isDark ? Colors.white : OhtliColors.onyx)),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                )
              else if (!widget.isPublicLink && !isDesktop)
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
              // Durante el viaje, si el modo viaje no está activo, el botón para activarlo va abajo.
              if (!isLocked && !_isNotes && !_tripMode && _isMember && _phase == TripPhase.durante && _sections.any((s) => s is PlaceSection))
                Positioned(
                  left: 16,
                  right: 16 + asideInset,
                  bottom: 16 + MediaQuery.of(context).padding.bottom + (isDesktop ? 0 : 64),
                  child: Center(
                    child: FilledButton.icon(
                      onPressed: () => _setTripMode(true),
                      style: FilledButton.styleFrom(
                        backgroundColor: OhtliColors.stormyTeal,
                        foregroundColor: Colors.white,
                        elevation: 8,
                        shadowColor: Colors.black.withValues(alpha: 0.35),
                        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
                        shape: const StadiumBorder(),
                      ),
                      icon: const Icon(Icons.near_me_rounded, size: 19),
                      label: Text('Estoy en el viaje', style: GoogleFonts.inter(fontSize: 14.5, fontWeight: FontWeight.w700)),
                    ),
                  ),
                ),
              // Barra de la muestra: abajo, salvo durante el viaje (ahí abajo va el modo viaje).
              if (_isSample && !isLocked)
                Positioned(
                  top: _phase == TripPhase.durante ? (isDesktop ? 14 : MediaQuery.of(context).padding.top + 58) : null,
                  bottom: _phase == TripPhase.durante ? null : 16 + MediaQuery.of(context).padding.bottom + (isDesktop ? 0 : 56),
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

    final Widget page = Scaffold(
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
    return widget.presentedAsCard ? _wrapPullToClose(page, isDark) : page;
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

  /// Al final del viaje: "Ver fe de erratas" con cuántos cambios y el más reciente.
  Widget _buildErrataHistorySection(bool isDark) {
    final errata = _trip?.errataHistory ?? [];
    if (errata.isEmpty) return const SizedBox.shrink();
    final last = errata.last;
    final Color fg = isDark ? Colors.white : const Color(0xFF1F2A2A);
    final Color sub = isDark ? Colors.white60 : OhtliColors.subtleText;
    final who = last.authorName.isNotEmpty ? last.authorName : 'Autor del viaje';
    return Padding(
      padding: const EdgeInsets.only(top: 28),
      child: Material(
        color: OhtliColors.xoconostle.withValues(alpha: isDark ? 0.14 : 0.06),
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: _showErrataLog,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(Icons.history_edu_rounded, color: OhtliColors.xoconostle),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Fe de erratas · ${errata.length} ${errata.length == 1 ? 'cambio' : 'cambios'}',
                          style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700, color: fg)),
                      const SizedBox(height: 2),
                      Text('Último: $who, ${_errataStamp(last.date)}', style: GoogleFonts.inter(fontSize: 12.5, color: sub)),
                    ],
                  ),
                ),
                Text('Ver', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: OhtliColors.xoconostle)),
                const Icon(Icons.chevron_right_rounded, color: OhtliColors.xoconostle),
              ],
            ),
          ),
        ),
      ),
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

  /// Datos de la portada de unas notas de versión: fecha y cuántas novedades de cada tipo.
  List<(IconData, String)> _releaseFacts() {
    final t = _trip!;
    final items = _sections.whereType<PlaceSection>().where((p) => !p.unplanned).toList();
    final upcoming = _sections.whereType<PlaceSection>().where((p) => p.unplanned).length;
    final facts = <(IconData, String)>[(Icons.event_rounded, _formatSpanishDate(t.travelDate ?? t.updatedAt).replaceFirst(RegExp(r'^el '), ''))];
    String count(String tag, int c) => switch (tag) {
          'mejora' => c == 1 ? '1 mejora' : '$c mejoras',
          'correccion' => c == 1 ? '1 corrección' : '$c correcciones',
          _ => c == 1 ? '1 función nueva' : '$c funciones nuevas',
        };
    for (final tag in kReleaseTags.keys) {
      final c = items.where((p) => (p.changeTag ?? 'nuevo') == tag).length;
      if (c > 0) facts.add((releaseTagIcon(tag), count(tag, c)));
    }
    if (upcoming > 0) facts.add((Icons.alt_route_rounded, '$upcoming en camino'));
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
    final facts = _isNotes ? _releaseFacts() : _coverFacts();

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
            if (_isNotes) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(color: OhtliColors.stormyTeal, borderRadius: BorderRadius.circular(20)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.new_releases_rounded, size: 15, color: Colors.white),
                    const SizedBox(width: 6),
                    Text('Notas de versión${t?.version != null ? ' · v${t!.version}' : ''}',
                        style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w800, letterSpacing: 0.2, color: Colors.white)),
                  ],
                ),
              ),
              const SizedBox(height: 14),
            ],
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
      blockContent = _isNotes ? _buildNoveltyViewer(section, isDark) : _buildPlaceBlockViewer(section, isDark, isDesktop);
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
      final visited = _visited.contains(section.id) || section.arrivedAt != null;
      final Widget action;
      if (_canEditContent) {
        // Para quien edita, la parada avanza: Llegué aquí → Ya me voy → Visitada.
        final bool arrived = section.arrivedAt != null;
        final bool left = section.leftAt != null;
        action = !arrived
            ? ActionChip(
                avatar: const Icon(Icons.flag_rounded, size: 16, color: OhtliColors.stormyTeal),
                label: Text('Llegué aquí', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: OhtliColors.stormyTeal)),
                onPressed: () => _markArrival(section),
                side: const BorderSide(color: OhtliColors.stormyTeal),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              )
            : !left
                ? ActionChip(
                    avatar: const Icon(Icons.logout_rounded, size: 16, color: Colors.white),
                    backgroundColor: OhtliColors.stormyTeal,
                    label: Text('Aquí desde las ${section.arrivedAt} · Ya me voy',
                        style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white)),
                    onPressed: () => _markLeave(section),
                    side: BorderSide.none,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  )
                : Chip(
                    avatar: const Icon(Icons.check_circle_rounded, size: 16, color: OhtliColors.stormyTeal),
                    label: Text('Visitada · ${section.arrivedAt}–${section.leftAt}',
                        style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: OhtliColors.stormyTeal)),
                    side: BorderSide(color: OhtliColors.stormyTeal.withValues(alpha: 0.3)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  );
      } else {
        action = FilterChip(
          selected: visited,
          onSelected: (_) => _toggleVisited(section.id),
          showCheckmark: true,
          checkmarkColor: Colors.white,
          selectedColor: OhtliColors.stormyTeal,
          label: Text(visited ? 'Visitada' : 'Marcar como visitada',
              style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: visited ? Colors.white : OhtliColors.stormyTeal)),
          side: const BorderSide(color: OhtliColors.stormyTeal),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        );
      }
      final bool dim = section.leftAt != null || (!_canEditContent && visited);
      blockContent = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(padding: const EdgeInsets.only(bottom: 10), child: SizedBox(height: 42, child: Align(alignment: Alignment.centerLeft, child: action))),
          Opacity(opacity: dim ? 0.6 : 1, child: blockContent),
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

  bool get _useTimeline => _isNotes ? _sections.isNotEmpty : _sections.any((s) => s is PlaceSection);

  /// Notas de versión: se leen como una crónica; las "paradas" son novedades.
  bool get _isNotes => _trip?.isReleaseNotes == true;

  Widget _buildTimeline(bool isDark, bool isDesktop) {
    final list = ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _sections.length,
      itemBuilder: (context, index) {
        final section = _sections[index];
        // Bloques vacíos (texto o imagen sin contenido) no ocupan lugar ni dejan un punto en la línea.
        final bool empty = (section is TextSection && section.markdownText.trim().isEmpty) ||
            (section is TextImageSection && section.markdownText.trim().isEmpty && section.imageUrl.isEmpty);
        if (empty) return SizedBox.shrink(key: _blockKeys.putIfAbsent(section.id, () => GlobalKey()));
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
    } else if (_useTimeline && _isNotes && section is! PlaceSection && section is! TransferSection) {
      // En las notas, cada bloque es una parada del recorrido: un punto sobre la línea.
      block = Stack(
        clipBehavior: Clip.none,
        children: [
          block,
          Positioned(
            left: -(_spineIndent - _spineX) - 6,
            top: 8,
            child: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isDark ? const Color(0xFF3A3A3E) : OhtliColors.cantera,
                border: Border.all(color: isDark ? const Color(0xFF121214) : OhtliColors.cloudDancer, width: 2),
              ),
            ),
          ),
        ],
      );
    } else if (_useTimeline && section is PlaceSection && _isNotes) {
      final items = _sections.whereType<PlaceSection>().where((p) => !p.unplanned).toList();
      final n = items.indexOf(section) + 1;
      final Color tag = releaseTagColor(section.changeTag);
      block = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Wrap(
                  spacing: 10,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      'NOVEDAD $n DE ${items.length}',
                      style: GoogleFonts.inter(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.6,
                        color: isDark ? Colors.white54 : OhtliColors.subtleText,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                      decoration: BoxDecoration(
                        color: tag.withValues(alpha: isDark ? 0.22 : 0.12),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: tag.withValues(alpha: 0.35)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(releaseTagIcon(section.changeTag), size: 12, color: isDark ? Color.lerp(tag, Colors.white, 0.4) : tag),
                          const SizedBox(width: 4),
                          Text(releaseTagLabel(section.changeTag),
                              style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w800, color: isDark ? Color.lerp(tag, Colors.white, 0.4) : tag)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                left: -(_spineIndent - _spineX) - 12,
                top: -4,
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: tag,
                    border: Border.all(color: isDark ? const Color(0xFF121214) : OhtliColors.cloudDancer, width: 3),
                  ),
                  child: Icon(releaseTagIcon(section.changeTag), size: 11, color: Colors.white),
                ),
              ),
            ],
          ),
          block,
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
      web.window.localStorage.setItem('ohtli_trip_aside_collapsed', v ? '1' : '0');
    } catch (_) {}
  }

  void _openEditorOrErrata(bool canEdit) {
    if (_isSample) {
      // Editor de muestra: se puede probar todo, pero no se guarda nada.
      Navigator.push(context, MaterialPageRoute(builder: (context) => TripEditorPage(trip: _trip!, sampleSections: List.of(_sections))));
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

    if (_asideCollapsed) {
      // Plegado: cada acceso es un botón flotante independiente (como los bloques del panel).
      Widget bubble(IconData icon, String tip, VoidCallback onTap, {bool accent = false}) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Tooltip(
              message: tip,
              child: DecoratedBox(
                decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: _floatShadow(isDark)),
                child: Material(
                  color: accent ? OhtliColors.stormyTeal : bg,
                  shape: CircleBorder(side: BorderSide(color: accent ? Colors.transparent : border)),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: onTap,
                    child: SizedBox(
                      width: 46,
                      height: 46,
                      child: Icon(icon, size: 21, color: accent ? Colors.white : (isDark ? Colors.white70 : OhtliColors.onyx.withValues(alpha: 0.75))),
                    ),
                  ),
                ),
              ),
            ),
          );
      final bubbles = <Widget>[
        bubble(Icons.keyboard_double_arrow_left_rounded, 'Abrir panel', () => _setAsideCollapsed(false), accent: true),
        if (!_isNotes && _sections.any((s) => s is PlaceSection)) bubble(Icons.map_rounded, 'Ruta completa', () => _showRouteModal(isDark)),
        bubble(Icons.toc_rounded, 'Índice', () => _setAsideCollapsed(false)),
        if (member) bubble(Icons.handyman_rounded, 'Herramientas del viaje', () => _setAsideCollapsed(false)),
        if (showEditAction)
          bubble(canEdit ? Icons.edit_rounded : Icons.history_edu_rounded, canEdit ? 'Editar' : 'Fe de erratas', () => _openEditorOrErrata(canEdit)),
      ];
      return SafeArea(
        left: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(_kAsideGap, _kAsideGap, _kAsideGap + 5, _kAsideGap),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [for (final (i, b) in bubbles.indexed) StaggerIn(index: i, from: const Offset(0, -10), child: b)],
          ),
        ),
      );
    }

    // Panel abierto: bloques flotantes independientes (encabezado, mini mapa, índice y
    // herramientas), cada uno con su sombra; entre ellos se ve la página.
    final header = Container(
      padding: const EdgeInsets.fromLTRB(18, 6, 6, 6),
      decoration: _floatBlock(isDark, radius: 20),
      child: Row(
        children: [
          Expanded(
            child: Text(_isNotes ? 'En esta versión' : (member ? 'Tu viaje' : 'Recorrido'), style: GoogleFonts.outfit(fontSize: 17, fontWeight: FontWeight.bold, color: fg)),
          ),
          if (showEditAction)
            FilledButton.icon(
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
          IconButton(
            tooltip: 'Plegar panel',
            onPressed: () => _setAsideCollapsed(true),
            icon: Icon(Icons.keyboard_double_arrow_right_rounded, color: isDark ? Colors.white60 : OhtliColors.subtleText),
          ),
        ],
      ),
    );
    final blocks = <Widget>[
      Padding(padding: const EdgeInsets.only(bottom: 14), child: header),
      if (!_isNotes && _sections.any((s) => s is PlaceSection))
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: DecoratedBox(
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), boxShadow: _floatShadow(isDark)),
            child: ClipRRect(borderRadius: BorderRadius.circular(18), child: _buildMiniMap(isDark)),
          ),
        ),
      Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.fromLTRB(10, 14, 10, 10),
        decoration: _floatBlock(isDark),
        child: _buildAsideIndex(isDark),
      ),
      if (member) ..._buildMemberPanelCards(isDark, canEdit),
    ];
    return SafeArea(
      left: false,
      child: SizedBox(
        width: _kAsideW + _kAsideGap * 2,
        child: ListView(
          // Sin recorte: las sombras de los bloques se ven completas.
          clipBehavior: Clip.none,
          padding: const EdgeInsets.fromLTRB(_kAsideGap, _kAsideGap, _kAsideGap, 28),
          children: [
            // Al desplegar el panel, los bloques entran uno tras otro.
            for (final (i, w) in blocks.indexed) StaggerIn(index: i, child: w),
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
              if (isPlace && _isNotes) ...[
                CircleAvatar(
                  radius: 11,
                  backgroundColor: detour ? OhtliColors.cempasuchil.withValues(alpha: 0.18) : releaseTagColor(s.changeTag),
                  child: Icon(detour ? Icons.alt_route_rounded : releaseTagIcon(s.changeTag),
                      size: 12, color: detour ? OhtliColors.cempasuchil : Colors.white),
                ),
                const SizedBox(width: 10),
              ] else if (isPlace) ...[
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

  /// Novedad de unas notas de versión: tarjeta con una franja del color de su etiqueta,
  /// título, texto y capturas.
  Widget _buildNoveltyViewer(PlaceSection item, bool isDark) {
    final bool upcoming = item.unplanned;
    final Color tag = upcoming ? OhtliColors.cempasuchil : releaseTagColor(item.changeTag);
    final photos = [item.mainPhotoUrl, ...item.secondaryPhotoUrls].where((u) => u.isNotEmpty).toList();
    Widget shot(String url, double ratio) => ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: AspectRatio(
            aspectRatio: ratio,
            child: Image(
              image: _getImageProvider(url),
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => ColoredBox(color: isDark ? const Color(0xFF26343A) : OhtliColors.cantera.withValues(alpha: 0.4)),
            ),
          ),
        );
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E22) : Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: isDark ? Colors.white10 : OhtliColors.cardBorder),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.05), blurRadius: 18, offset: const Offset(0, 6))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(height: 5, color: tag),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 18, 22, 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (upcoming) ...[
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.alt_route_rounded, size: 14, color: isDark ? Color.lerp(tag, Colors.white, 0.3) : tag),
                      const SizedBox(width: 6),
                      Text('PRÓXIMAMENTE · EN CAMINO',
                          style: GoogleFonts.inter(
                              fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: isDark ? Color.lerp(tag, Colors.white, 0.3) : tag)),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
                Text(
                  item.title.trim().isNotEmpty ? item.title.trim() : (upcoming ? 'Próximamente' : 'Novedad'),
                  style: GoogleFonts.outfit(fontSize: 21, fontWeight: FontWeight.bold, height: 1.15, color: isDark ? Colors.white : OhtliColors.onyx),
                ),
                if (item.description.trim().isNotEmpty) ...[
                  const SizedBox(height: 10),
                  OhtliMarkdownText(
                    text: item.description,
                    style: GoogleFonts.inter(fontSize: 14, height: 1.55, color: isDark ? Colors.white70 : OhtliColors.onyx.withValues(alpha: 0.82)),
                  ),
                ],
                if (photos.length == 1) ...[
                  const SizedBox(height: 16),
                  shot(photos.first, 16 / 9),
                ] else if (photos.length > 1) ...[
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final (i, u) in photos.indexed) ...[
                        if (i > 0) const SizedBox(width: 10),
                        Expanded(child: shot(u, 4 / 3)),
                      ],
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
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

  /// Nota, consejo o aviso: tarjeta tintada con franja de color, ícono y etiqueta.
  Widget _buildAlertBlockViewer(AlertData alert, bool isDark) {
    final (Color color, IconData icon, String name) = switch (alert.type) {
      AlertType.warning => (OhtliColors.xoconostle, Icons.warning_amber_rounded, 'AVISO'),
      AlertType.tip => (OhtliColors.cempasuchil, Icons.lightbulb_rounded, 'CONSEJO'),
      _ => (OhtliColors.stormyTeal, Icons.sticky_note_2_rounded, 'NOTA'),
    };
    final Color accent = isDark ? Color.lerp(color, Colors.white, 0.25)! : color;
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: Container(
        color: color.withValues(alpha: isDark ? 0.14 : 0.08),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 5, color: color),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 18, 16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(color: color.withValues(alpha: isDark ? 0.25 : 0.16), borderRadius: BorderRadius.circular(11)),
                        child: Icon(icon, size: 19, color: accent),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(name, style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.1, color: accent)),
                            if (alert.content.isNotEmpty) ...[
                              const SizedBox(height: 5),
                              OhtliMarkdownText(
                                text: alert.content,
                                style: GoogleFonts.inter(
                                  fontSize: 15,
                                  height: 1.6,
                                  color: isDark ? Colors.white.withValues(alpha: 0.88) : const Color(0xFF1F2A2A),
                                ),
                              ),
                            ],
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
      ),
    );
  }

  static String _money(double v) {
    final whole = v.round().abs().toString();
    final buf = StringBuffer();
    for (int i = 0; i < whole.length; i++) {
      if (i > 0 && (whole.length - i) % 3 == 0) buf.write(',');
      buf.write(whole[i]);
    }
    return '${v < 0 ? '-' : ''}\$${buf.toString()}';
  }

  /// Tabla en tarjeta: encabezado tintado, renglones alternados, números alineados a la
  /// derecha con cifras tabulares y el total destacado. Ocupa todo el ancho si cabe.
  Widget _buildTableBlockViewer(TableData table, bool isDark) {
    final cols = table.columns;
    if (cols.isEmpty) return const SizedBox.shrink();
    final bool showTotal = cols.any((c) => c.type == 'money' && c.isTotalEnabled);
    final Color fg = isDark ? Colors.white : const Color(0xFF1F2A2A);
    final Color line = isDark ? Colors.white10 : OhtliColors.cardBorder;
    const tabular = [FontFeature.tabularFigures()];
    bool numeric(TableColumn c) => c.type == 'money' || c.type == 'number';

    Widget pad(Widget child, {bool right = false}) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          child: Align(alignment: right ? Alignment.centerRight : Alignment.centerLeft, child: child),
        );

    final rows = <TableRow>[
      TableRow(
        decoration: BoxDecoration(color: OhtliColors.stormyTeal.withValues(alpha: isDark ? 0.18 : 0.08)),
        children: [
          for (final c in cols)
            pad(
              Text(
                c.type == 'money' ? '${c.name.toUpperCase()} · ${c.currency}' : c.name.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.7, color: isDark ? Color.lerp(OhtliColors.stormyTeal, Colors.white, 0.55) : OhtliColors.stormyTeal),
              ),
              right: numeric(c),
            ),
        ],
      ),
      for (int r = 0; r < table.rows.length; r++)
        TableRow(
          decoration: BoxDecoration(
            color: r.isOdd ? (isDark ? Colors.white.withValues(alpha: 0.03) : const Color(0xFFF7F9F8)) : Colors.transparent,
            border: Border(top: BorderSide(color: line)),
          ),
          children: [
            for (int c = 0; c < cols.length; c++)
              () {
                final raw = c < table.rows[r].length ? table.rows[r][c] : '';
                final col = cols[c];
                final num = double.tryParse(raw.replaceAll(RegExp(r'[^\d.-]'), ''));
                if (col.type == 'money' && num != null && raw.trim().isNotEmpty) {
                  return pad(Text(_money(num), style: GoogleFonts.inter(fontSize: 14, color: fg, fontFeatures: tabular)), right: true);
                }
                return pad(
                  OhtliMarkdownText(
                    text: raw,
                    textAlign: numeric(col) ? TextAlign.right : TextAlign.left,
                    style: GoogleFonts.inter(fontSize: 14, height: 1.35, color: c == 0 ? fg : fg.withValues(alpha: 0.85), fontFeatures: tabular),
                  ),
                  right: numeric(col),
                );
              }(),
          ],
        ),
      if (showTotal)
        TableRow(
          decoration: BoxDecoration(
            color: OhtliColors.stormyTeal.withValues(alpha: isDark ? 0.12 : 0.05),
            border: const Border(top: BorderSide(color: OhtliColors.stormyTeal, width: 1.5)),
          ),
          children: [
            for (int c = 0; c < cols.length; c++)
              if (cols[c].type == 'money' && cols[c].isTotalEnabled)
                pad(
                  Text(_money(_calculateTableTotal(table, c)),
                      style: GoogleFonts.outfit(fontSize: 17, fontWeight: FontWeight.bold, color: isDark ? Colors.white : OhtliColors.stormyTeal, fontFeatures: tabular)),
                  right: true,
                )
              else
                pad(c == 0 ? Text('Total', style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w800, color: fg)) : const SizedBox.shrink()),
          ],
        ),
    ];

    final double minWidth = cols.length * 130.0;
    Widget tableFor(double width) => SizedBox(
          width: width,
          child: Table(
            columnWidths: {for (int c = 0; c < cols.length; c++) c: FlexColumnWidth(numeric(cols[c]) ? 1 : 1.8)},
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            children: rows,
          ),
        );

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E22) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: line),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04), blurRadius: 14, offset: const Offset(0, 4))],
      ),
      child: LayoutBuilder(
        builder: (context, box) => box.maxWidth >= minWidth
            ? tableFor(box.maxWidth)
            : Scrollbar(
                child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: tableFor(minWidth)),
              ),
      ),
    );
  }


  /// Texto con tipografía de lectura: párrafos amplios, títulos (# o una línea en **negritas**)
  /// y listas con viñetas o números. El primer bloque del viaje va como entrada, más grande.
  Widget _buildTextBlockViewer(TextSection textSec, bool isDark) {
    final md = textSec.markdownText.trim();
    if (md.isEmpty) return const SizedBox.shrink();
    final bool lead = _sections.isNotEmpty && identical(_sections.first, textSec);
    final Color body = isDark ? Colors.white.withValues(alpha: 0.84) : const Color(0xFF1F2A2A).withValues(alpha: 0.88);
    final Color heading = isDark ? Colors.white : const Color(0xFF1F2A2A);
    final TextStyle para = GoogleFonts.inter(fontSize: lead ? 17.5 : 15.5, height: 1.7, color: body);
    final headingRe = RegExp(r'^(#{1,3})\s+(.+)$');
    final boldRe = RegExp(r'^\*\*([^*]+)\*\*$');
    final bulletRe = RegExp(r'^[-*•]\s+(.+)$');
    final numberRe = RegExp(r'^(\d+)[.)]\s+(.+)$');
    bool special(String t) => headingRe.hasMatch(t) || boldRe.hasMatch(t) || bulletRe.hasMatch(t) || numberRe.hasMatch(t);

    Widget item(Widget marker, String text) => Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 30, child: marker),
              Expanded(child: OhtliMarkdownText(text: text, style: para.copyWith(height: 1.6))),
            ],
          ),
        );

    final children = <Widget>[];
    final lines = md.split('\n');
    int i = 0;
    while (i < lines.length) {
      final t = lines[i].trim();
      if (t.isEmpty) {
        i++;
        continue;
      }
      final h = headingRe.firstMatch(t);
      final bold = boldRe.firstMatch(t);
      final bullet = bulletRe.firstMatch(t);
      final number = numberRe.firstMatch(t);
      if (h != null || bold != null) {
        final big = h != null && h.group(1)!.length == 1;
        children.add(Padding(
          padding: EdgeInsets.only(top: children.isEmpty ? 0 : 18, bottom: 2),
          child: Text(h?.group(2) ?? bold!.group(1)!,
              style: GoogleFonts.outfit(fontSize: big ? 26 : 21, fontWeight: FontWeight.bold, height: 1.2, color: heading)),
        ));
      } else if (bullet != null) {
        children.add(item(
          Padding(
            padding: EdgeInsets.only(top: lead ? 11 : 10, left: 6),
            child: Align(
              alignment: Alignment.topLeft,
              child: Container(width: 7, height: 7, decoration: const BoxDecoration(color: OhtliColors.cempasuchil, shape: BoxShape.circle)),
            ),
          ),
          bullet.group(1)!,
        ));
      } else if (number != null) {
        children.add(item(
          Align(
            alignment: Alignment.topLeft,
            child: Container(
              margin: const EdgeInsets.only(top: 2),
              width: 22,
              height: 22,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: OhtliColors.stormyTeal.withValues(alpha: isDark ? 0.3 : 0.12), shape: BoxShape.circle),
              child: Text(number.group(1)!,
                  style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w800, color: isDark ? Colors.white : OhtliColors.stormyTeal)),
            ),
          ),
          number.group(2)!,
        ));
      } else {
        // Párrafo: líneas seguidas hasta una línea vacía o un elemento especial.
        final buf = <String>[t];
        i++;
        while (i < lines.length) {
          final n = lines[i].trim();
          if (n.isEmpty || special(n)) break;
          buf.add(n);
          i++;
        }
        children.add(Padding(
          padding: EdgeInsets.only(top: children.isEmpty ? 0 : 12),
          child: OhtliMarkdownText(text: buf.join('\n'), style: para),
        ));
        continue;
      }
      i++;
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: children);
  }

  Widget _buildTextImageBlockViewer(TextImageSection section, bool isDark, bool isDesktop) {
    // El texto se ve igual que un bloque de texto (mismo tamaño, títulos y viñetas).
    final Widget textWidget = _buildTextBlockViewer(TextSection(id: section.id, markdownText: section.markdownText), isDark);
    if (section.imageUrl.isEmpty) return textWidget;

    // La foto, como una impresión pegada en la bitácora (marco claro, sombra y un leve giro).
    final bool isLeft = section.layout != 'right';
    Widget print({required double width, required double aspect}) => Transform.rotate(
          angle: (isLeft ? -1.6 : 1.6) * math.pi / 180,
          child: Container(
            width: width,
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 22),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF2A2A2E) : Colors.white,
              borderRadius: BorderRadius.circular(6),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.14), blurRadius: 16, offset: const Offset(0, 6)),
                BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 2, offset: const Offset(0, 1)),
              ],
            ),
            child: GestureDetector(
              onTap: () => _showImageLightbox(urls: [section.imageUrl], initialIndex: 0, title: 'Foto adjunta'),
              child: MouseRegion(
                cursor: SystemMouseCursors.zoomIn,
                child: AspectRatio(
                  aspectRatio: aspect,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: Image(
                      image: _getImageProvider(section.imageUrl),
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => ColoredBox(color: isDark ? const Color(0xFF26343A) : OhtliColors.cantera.withValues(alpha: 0.4)),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );

    if (isDesktop) {
      final photo = print(width: 230, aspect: 3 / 4);
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isLeft) ...[photo, const SizedBox(width: 30)],
          Expanded(child: Padding(padding: const EdgeInsets.only(top: 6), child: textWidget)),
          if (!isLeft) ...[const SizedBox(width: 30), photo],
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(child: print(width: 280, aspect: 4 / 3)),
        const SizedBox(height: 20),
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

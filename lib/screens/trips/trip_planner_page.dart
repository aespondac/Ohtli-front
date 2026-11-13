// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use, avoid_print

import 'dart:async';
import 'dart:html' as html;
import 'dart:ui' show lerpDouble;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/poi_model.dart';
import '../../models/trip_model.dart';
import '../../services/itinerary_blackboard_service.dart';
import '../../theme/cdmx_photos.dart';
import '../../theme/colors.dart';
import '../../widgets/osrm_map_widget.dart';
import '../../widgets/poi_detail_dialog.dart';
import '../construction_page.dart'; // RouteBackgroundPainter
import 'trip_viewer_page.dart';
import 'trip_editor_page.dart';

enum PlannerStep {
  bifurcation,
  startingPoint,
  preferences,
  blackboardProcessing,
  routeTriadCarousel,
}

class TripPlannerPage extends StatefulWidget {
  final Poi? initialOriginPoi;
  final VoidCallback? onManualPlanSelected;
  final List<Map<String, dynamic>>? initialGeneratedOptions;
  final String? initialActiveJobId;
  final String? originName;

  const TripPlannerPage({
    super.key,
    this.initialOriginPoi,
    this.onManualPlanSelected,
    this.initialGeneratedOptions,
    this.initialActiveJobId,
    this.originName,
  });

  static void open(
    BuildContext context, {
    Poi? initialOriginPoi,
    VoidCallback? onManualPlanSelected,
    List<Map<String, dynamic>>? initialGeneratedOptions,
    String? initialActiveJobId,
    String? originName,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => TripPlannerPage(
          initialOriginPoi: initialOriginPoi,
          onManualPlanSelected: onManualPlanSelected,
          initialGeneratedOptions: initialGeneratedOptions,
          initialActiveJobId: initialActiveJobId,
          originName: originName,
        ),
      ),
    );
  }

  @override
  State<TripPlannerPage> createState() => _TripPlannerPageState();
}

class _TripPlannerPageState extends State<TripPlannerPage> with SingleTickerProviderStateMixin {
  final ItineraryBlackboardService _blackboardService = ItineraryBlackboardService();
  final TextEditingController _originSearchController = TextEditingController();
  final TextEditingController _customMoodController = TextEditingController();

  PlannerStep _currentStep = PlannerStep.bifurcation;

  // Form State
  String _selectedOriginName = '';
  Map<String, double>? _selectedOriginCoords;
  List<Map<String, dynamic>> _userSavedAddresses = [];

  double _budgetMxn = 450.0;
  String _selectedMood = 'Bohemio y Cafés';
  String _selectedTopology = 'anillo'; // anillo, radio, elipse
  DateTime _selectedTravelDate = DateTime.now().add(const Duration(days: 1));

  String _formatDate(DateTime d) {
    const months = [
      'Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio',
      'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre'
    ];
    const weekdays = [
      'Lunes', 'Martes', 'Miércoles', 'Jueves', 'Viernes', 'Sábado', 'Domingo'
    ];
    final dayName = weekdays[d.weekday - 1];
    final monthName = months[d.month - 1];
    return '$dayName, ${d.day} de $monthName de ${d.year}';
  }

  DateTime _getNextWeekend() {
    final now = DateTime.now();
    int daysUntilSaturday = (DateTime.saturday - now.weekday + 7) % 7;
    if (daysUntilSaturday == 0) daysUntilSaturday = 7;
    return now.add(Duration(days: daysUntilSaturday));
  }

  Future<void> _pickTravelDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedTravelDate.isBefore(now) ? now : _selectedTravelDate,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: OhtliColors.stormyTeal,
              onPrimary: Colors.white,
              onSurface: OhtliColors.onyx,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() => _selectedTravelDate = picked);
    }
  }

  Widget _buildQuickDateChip(String label, DateTime targetDate) {
    final isSelected = _selectedTravelDate.year == targetDate.year &&
        _selectedTravelDate.month == targetDate.month &&
        _selectedTravelDate.day == targetDate.day;

    return ActionChip(
      label: Text(label),
      labelStyle: GoogleFonts.inter(
        fontSize: 11,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
        color: isSelected ? Colors.white : OhtliColors.onyx,
      ),
      backgroundColor: isSelected ? OhtliColors.stormyTeal : OhtliColors.cardBorder.withOpacity(0.2),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: isSelected ? OhtliColors.stormyTeal : OhtliColors.cardBorder,
        ),
      ),
      onPressed: () {
        setState(() => _selectedTravelDate = targetDate);
      },
    );
  }

  // Blackboard / SMA State
  String? _activeJobId;
  StreamSubscription<DocumentSnapshot>? _jobSubscription;
  int _blackboardProgress = 15;
  String _currentAgentName = 'Comparador';
  List<Map<String, dynamic>> _generatedOptions = [];
  bool _isSavingTrip = false;

  // Carrusel cinematográfico de multirutas
  PageController? _triadPageController;
  double _currentViewportFraction = 0.88;
  int _activeCarouselIndex = 1;
  bool _isDetailExpanded = false;
  final Map<int, ScrollController> _cardScrollControllers = {};

  // Transición tipo Apple TV: la tarjeta enfocada se transforma (morph) en la vista de detalle
  late final AnimationController _expandController = AnimationController(vsync: this, duration: const Duration(milliseconds: 560), reverseDuration: const Duration(milliseconds: 440));
  late final CurvedAnimation _expandCurve = CurvedAnimation(parent: _expandController, curve: Curves.easeOutQuart, reverseCurve: Curves.easeInOutCubic);
  // Bloqueo breve tras cada transición: evita que la inercia del trackpad/rueda
  // vuelva a disparar el gesto contrario (causa del parpadeo expandir↔contraer)
  DateTime _expandLockUntil = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime? _detailAtTopSince;
  double _wheelAccum = 0;
  double _pullDownAccum = 0;
  Timer? _wheelResetTimer;
  final ValueNotifier<Offset> _hoverTilt = ValueNotifier(Offset.zero);
  final FocusNode _carouselFocusNode = FocusNode(debugLabel: 'routeCarousel');

  ScrollController _getCardScrollController(int index) {
    return _cardScrollControllers.putIfAbsent(index, () => ScrollController(keepScrollOffset: false));
  }

  bool get _expandLocked => DateTime.now().isBefore(_expandLockUntil);

  void _setDetailExpanded(bool value) {
    if (value == _isDetailExpanded || _expandLocked) return;
    _expandLockUntil = DateTime.now().add(const Duration(milliseconds: 700));
    _wheelAccum = 0;
    _pullDownAccum = 0;
    _detailAtTopSince = DateTime.now();
    _hoverTilt.value = Offset.zero;
    setState(() => _isDetailExpanded = value);
    if (value) {
      _expandController.forward();
    } else {
      _expandController.reverse();
    }
  }

  void _accumulateWheel(double dy) {
    _wheelAccum += dy;
    _wheelResetTimer?.cancel();
    _wheelResetTimer = Timer(const Duration(milliseconds: 220), () => _wheelAccum = 0);
  }

  // Rueda/trackpad sobre la tarjeta compacta: scroll hacia abajo abre el detalle a pantalla completa
  void _handleCompactWheel(PointerSignalEvent event, bool isFocused) {
    if (!isFocused || _isDetailExpanded || event is! PointerScrollEvent) return;
    final dy = event.scrollDelta.dy;
    final dx = event.scrollDelta.dx;
    if (dx.abs() > dy.abs() || dy <= 0) {
      _wheelAccum = 0;
      return;
    }
    _accumulateWheel(dy);
    if (_wheelAccum > 60) _setDetailExpanded(true);
  }

  // Rueda/trackpad en el detalle: solo un "tirón" intencional hacia arriba estando ya en el tope cierra
  void _handleDetailWheel(PointerSignalEvent event) {
    if (!_isDetailExpanded || event is! PointerScrollEvent) return;
    final c = _cardScrollControllers[_activeCarouselIndex];
    final atTop = c == null || !c.hasClients || c.offset <= 0.5;
    final dy = event.scrollDelta.dy;
    final settledAtTop = atTop && _detailAtTopSince != null && DateTime.now().difference(_detailAtTopSince!) > const Duration(milliseconds: 320);
    if (!settledAtTop || dy >= 0) {
      _wheelAccum = 0;
      return;
    }
    _accumulateWheel(dy);
    if (_wheelAccum < -180) _setDetailExpanded(false);
  }

  // Gesto táctil: arrastrar hacia abajo desde el tope (no la inercia) cierra el detalle
  bool _handleDetailScrollNotification(ScrollNotification n) {
    if (n.depth != 0 || n.metrics.axis != Axis.vertical) return false;
    final px = n.metrics.pixels;
    if (px > 0.5) {
      _detailAtTopSince = null;
      _pullDownAccum = 0;
    } else {
      _detailAtTopSince ??= DateTime.now();
    }
    if (n is OverscrollNotification && n.dragDetails != null && n.overscroll < 0) {
      _pullDownAccum += -n.overscroll;
    } else if (n is ScrollUpdateNotification && n.dragDetails != null && px < 0) {
      _pullDownAccum = -px;
    } else if (n is ScrollEndNotification) {
      _pullDownAccum = 0;
    }
    if (_pullDownAccum > 90) _setDetailExpanded(false);
    return false;
  }

  KeyEventResult _handleCarouselKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (_isDetailExpanded) {
      if (key == LogicalKeyboardKey.escape || key == LogicalKeyboardKey.backspace) {
        _setDetailExpanded(false);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    final controller = _triadPageController;
    if (key == LogicalKeyboardKey.arrowRight && controller != null) {
      controller.nextPage(duration: const Duration(milliseconds: 380), curve: Curves.easeOutCubic);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft && controller != null) {
      controller.previousPage(duration: const Duration(milliseconds: 380), curve: Curves.easeOutCubic);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.arrowDown || key == LogicalKeyboardKey.space) {
      _setDetailExpanded(true);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  PageController _getTriadPageController(double targetFraction) {
    if (_triadPageController == null || (_currentViewportFraction - targetFraction).abs() > 0.01) {
      final initialPage = (_triadPageController?.hasClients == true)
          ? (_triadPageController!.page?.round() ?? _activeCarouselIndex)
          : (_generatedOptions.length > 2 ? 1 : _activeCarouselIndex);
      _triadPageController?.dispose();
      _triadPageController = PageController(
        viewportFraction: targetFraction,
        initialPage: initialPage,
      );
      _currentViewportFraction = targetFraction;
    }
    return _triadPageController!;
  }

  final List<Map<String, dynamic>> _cdmxKeyZones = [
    {
      'name': 'Centro Histórico (Zócalo)',
      'coords': {'lat': 19.4326, 'lng': -99.1332},
      'icon': Icons.account_balance_rounded,
    },
    {
      'name': 'Coyoacán (Jardín Centenario)',
      'coords': {'lat': 19.3497, 'lng': -99.1622},
      'icon': Icons.palette_rounded,
    },
    {
      'name': 'Roma / Condesa',
      'coords': {'lat': 19.4198, 'lng': -99.1599},
      'icon': Icons.local_cafe_rounded,
    },
    {
      'name': 'Polanco / Chapultepec',
      'coords': {'lat': 19.4260, 'lng': -99.1863},
      'icon': Icons.nature_people_rounded,
    },
  ];

  final List<String> _moodPresets = [
    'Bohemio y Cafés',
    'Muralismo e Historia',
    'Cantinas Tradicionales',
    'Senderos Verdes y Calma',
    'Gastronomía y Mercados',
    'Arquitectura y Museos',
  ];

  @override
  void initState() {
    super.initState();
    _loadUserSavedAddresses();

    if (widget.initialOriginPoi != null) {
      _selectedOriginName = widget.initialOriginPoi!.name;
      _selectedOriginCoords = {
        'lat': widget.initialOriginPoi!.location.lat,
        'lng': widget.initialOriginPoi!.location.lng,
      };
      _originSearchController.text = _selectedOriginName;
    }

    if (widget.initialActiveJobId != null && widget.initialActiveJobId!.isNotEmpty) {
      _activeJobId = widget.initialActiveJobId;
      _selectedOriginName = widget.originName ?? 'CDMX';
      _currentStep = PlannerStep.blackboardProcessing;
      _listenToBlackboardJob(widget.initialActiveJobId!);
    } else if (widget.initialGeneratedOptions != null && widget.initialGeneratedOptions!.isNotEmpty) {
      _generatedOptions = widget.initialGeneratedOptions!;
      _selectedOriginName = widget.originName ?? 'CDMX';
      _currentStep = PlannerStep.routeTriadCarousel;
      _activeCarouselIndex = _generatedOptions.length > 2 ? 1 : 0;
    }
  }

  @override
  void dispose() {
    _jobSubscription?.cancel();
    _triadPageController?.dispose();
    _expandCurve.dispose();
    _expandController.dispose();
    _wheelResetTimer?.cancel();
    _hoverTilt.dispose();
    _carouselFocusNode.dispose();
    for (final c in _cardScrollControllers.values) {
      c.dispose();
    }
    _originSearchController.dispose();
    _customMoodController.dispose();
    super.dispose();
  }

  Future<void> _loadUserSavedAddresses() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      if (doc.exists && doc.data() != null) {
        final list = doc.data()!['addresses'];
        if (list is List) {
          setState(() {
            _userSavedAddresses = list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
          });
        }
      }
    } catch (e) {
      debugPrint('Error cargando direcciones guardadas: $e');
    }
  }

  Future<void> _launchBlackboardJob() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Por favor inicia sesión para generar tu itinerario.', style: GoogleFonts.inter()),
          backgroundColor: OhtliColors.xoconostle,
        ),
      );
      return;
    }

    final coords = _selectedOriginCoords ?? {'lat': 19.4326, 'lng': -99.1332};
    final effectiveMood = _customMoodController.text.trim().isNotEmpty
        ? _customMoodController.text.trim()
        : _selectedMood;

    setState(() {
      _currentStep = PlannerStep.blackboardProcessing;
      _blackboardProgress = 15;
      _currentAgentName = 'Comparador';
    });

    try {
      final originTitle = _originSearchController.text.trim().isNotEmpty
          ? _originSearchController.text.trim()
          : (widget.originName ?? 'Ciudad de México');

      final jobId = await _blackboardService.requestItineraryJob(
        userId: user.uid,
        budget: _budgetMxn,
        origin: coords,
        originName: originTitle,
        topology: _selectedTopology,
        moodText: effectiveMood,
        travelDate: _selectedTravelDate,
      );

      _activeJobId = jobId;
      _listenToBlackboardJob(jobId);
    } catch (e) {
      debugPrint('Error solicitando job al Blackboard: $e');
      setState(() {
        _currentStep = PlannerStep.preferences;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al conectar con Yollotl Engine: $e', style: GoogleFonts.inter()),
            backgroundColor: OhtliColors.xoconostle,
          ),
        );
      }
    }
  }

  void _listenToBlackboardJob(String jobId) {
    _jobSubscription?.cancel();
    try {
      _jobSubscription = _blackboardService.streamJob(jobId).listen((snapshot) {
        if (!snapshot.exists || snapshot.data() == null) return;
        final data = snapshot.data() as Map<String, dynamic>;

        final progress = (data['progress_percent'] as num?)?.toInt() ?? 15;
        final agent = (data['current_agent'] ?? 'Comparador').toString();
        final status = data['status'];

        if (mounted) {
          setState(() {
            _blackboardProgress = progress;
            _currentAgentName = agent[0].toUpperCase() + agent.substring(1);
          });
        }

        if (status == 'completed' && data['result'] != null) {
          final res = data['result'] as Map<String, dynamic>;
          final rawOptions = res['options'] as List<dynamic>? ?? [];
          if (rawOptions.isNotEmpty && mounted) {
            _jobSubscription?.cancel();
            setState(() {
              _generatedOptions = rawOptions.map((e) => Map<String, dynamic>.from(e as Map)).toList();
              _currentStep = PlannerStep.routeTriadCarousel;
              _activeCarouselIndex = _generatedOptions.length > 2 ? 1 : 0;
              _triadPageController?.dispose();
              _triadPageController = null;
              _isDetailExpanded = false;
              _expandController.value = 0;
            });
          }
        }
      });
    } catch (e) {
      debugPrint('[TripPlanner] Error al escuchar job de Blackboard: $e');
    }
  }

  int _computeOptionTotalDuration(Map<String, dynamic> option) {
    final direct = (option['total_duration_mins'] as num?)?.toInt() ??
        (option['estimated_time_mins'] as num?)?.toInt();
    if (direct != null && direct > 0) return direct;

    final stops = option['route'] as List<dynamic>? ?? [];
    int staySum = 0;
    int travelSum = 0;
    for (final s in stops) {
      if (s is Map) {
        staySum += (s['stay_duration_mins'] as num?)?.toInt() ?? 60;
        travelSum += (s['travel_time_from_prev_mins'] as num?)?.toInt() ?? 0;
      }
    }
    final total = staySum + travelSum;
    return total > 0 ? total : 180;
  }

  // Fichas completas de lugares (Firestore) para que la descripción del itinerario
  // sea exactamente la misma que muestra el detalle del lugar.
  final Map<String, Poi> _poiCache = {};
  final Set<String> _poiRequested = {};

  String _stopPoiId(Map<String, dynamic> stop) => (stop['poi_id'] ?? stop['id'] ?? '').toString();

  void _prefetchStopPois(List<dynamic> stops) {
    final ids = <String>[];
    for (final s in stops) {
      if (s is! Map) continue;
      final id = _stopPoiId(Map<String, dynamic>.from(s));
      if (id.isNotEmpty && _poiRequested.add(id)) ids.add(id);
    }
    if (ids.isEmpty) return;
    final FirebaseFirestore db;
    try {
      db = FirebaseFirestore.instance;
    } catch (e) {
      debugPrint('[TripPlanner] Firestore no disponible: $e');
      return;
    }
    for (final id in ids) {
      db.collection('pois').doc(id).get().then((doc) {
        if (!mounted || !doc.exists || doc.data() == null) return;
        setState(() => _poiCache[id] = Poi.fromFirestore(doc));
      }).catchError((e) {
        _poiRequested.remove(id);
        debugPrint('[TripPlanner] No se pudo precargar POI $id: $e');
      });
    }
  }

  Poi _poiFromStop(Map<String, dynamic> stop) {
    final poiId = _stopPoiId(stop);
    final loc = stop['location'] ?? stop['coords'] ?? stop['coordinates'];
    double lat = 0.0;
    double lng = 0.0;
    if (loc is Map) {
      lat = (loc['lat'] as num?)?.toDouble() ?? (loc['latitude'] as num?)?.toDouble() ?? 0.0;
      lng = (loc['lng'] as num?)?.toDouble() ?? (loc['longitude'] as num?)?.toDouble() ?? 0.0;
    } else {
      lat = (stop['lat'] as num?)?.toDouble() ?? (stop['latitude'] as num?)?.toDouble() ?? 0.0;
      lng = (stop['lng'] as num?)?.toDouble() ?? (stop['longitude'] as num?)?.toDouble() ?? 0.0;
    }
    final poiMap = <String, dynamic>{
      'poi_id': poiId.isNotEmpty ? poiId : 'poi_${(stop['name'] ?? '').hashCode}',
      'name': stop['name'] ?? 'Lugar de interés',
      'category': stop['category'] ?? stop['type'] ?? 'cultural',
      'subcategories': stop['subcategories'] ?? [],
      'location': {'lat': lat, 'lng': lng},
      'price_level': stop['price_level'] ?? 1,
      'price_mxn_avg': (stop['price_mxn'] as num?)?.toDouble() ?? 0.0,
      'description': stop['description'] ?? stop['semantic_description'] ?? '',
      'editorial_summary': stop['editorial_summary'] ?? '',
      'semantic_description': stop['semantic_description'] ?? '',
      'photo_url': _resolveStopPhoto(stop, 0),
      'address': stop['address'] ?? stop['alcaldia'] ?? 'Ciudad de México',
      'opening_hours': stop['opening_hours'] ?? '',
      'rating': (stop['rating'] as num?)?.toDouble() ?? 4.8,
      'vibe_tags': stop['vibe_tags'] ?? [],
    };
    return Poi.fromMap(poiMap, poiId);
  }

  /// Misma descripción que "Sobre este lugar" en el detalle del lugar.
  String _stopDetailDescription(Map<String, dynamic> stop) {
    final cached = _poiCache[_stopPoiId(stop)];
    return (cached ?? _poiFromStop(stop)).cleanNarrative;
  }

  void _openStopPoiModal(Map<String, dynamic> stop) async {
    final poiId = _stopPoiId(stop);
    Poi? fullPoi = _poiCache[poiId];

    if (fullPoi == null && poiId.isNotEmpty) {
      try {
        final doc = await FirebaseFirestore.instance.collection('pois').doc(poiId).get();
        if (doc.exists && doc.data() != null) {
          fullPoi = Poi.fromFirestore(doc);
          _poiCache[poiId] = fullPoi;
        }
      } catch (e) {
        debugPrint('[TripPlanner] Error al consultar POI de Firestore: $e');
      }
    }

    fullPoi ??= _poiFromStop(stop);

    if (!mounted) return;
    PoiDetailDialog.show(
      context,
      fullPoi,
      isSaved: false,
    );
  }

  Future<void> _chooseRouteAndCreateTrip(Map<String, dynamic> option) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Inicia sesión para guardar este plan en tu perfil.', style: GoogleFonts.inter()),
          backgroundColor: OhtliColors.xoconostle,
        ),
      );
      return;
    }

    setState(() => _isSavingTrip = true);

    try {
      final trip = await _blackboardService.saveOptionAsTrip(
        userId: user.uid,
        chosenOption: option,
        defaultTitle: 'Ruta Ohtli IA',
        travelDate: _selectedTravelDate,
      );

      if (_activeJobId != null) {
        await FirebaseFirestore.instance.collection('itinerary_jobs').doc(_activeJobId!).set({
          'chosen_option_index': _activeCarouselIndex,
          'created_trip_id': trip.id,
          'status': 'chosen',
        }, SetOptions(merge: true));
      }

      if (mounted) {
        setState(() => _isSavingTrip = false);
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => TripViewerPage(
              tripId: trip.id,
              authorId: user.uid,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSavingTrip = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al persistir el viaje: $e', style: GoogleFonts.inter()),
            backgroundColor: OhtliColors.xoconostle,
          ),
        );
      }
    }
  }

  void _handleManualPlanSelected() {
    Navigator.of(context).pop();
    if (widget.onManualPlanSelected != null) {
      widget.onManualPlanSelected!();
    } else {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final newTrip = Trip(
          id: '',
          userId: user.uid,
          title: 'Nuevo Viaje',
          description: '',
          coverUrl: '',
          status: 'draft',
          visibility: 'private',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => TripEditorPage(trip: newTrip),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isMobile = screenSize.width < 768;
    final isDark = OhtliSettings.instance.isDarkMode;

    return Scaffold(
      backgroundColor: OhtliColors.cloudDancer,
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF1E1E22) : const Color(0xFFE4E1DA),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: OhtliColors.stormyTeal),
          onPressed: () {
            if (_currentStep == PlannerStep.routeTriadCarousel && _isDetailExpanded) {
              _expandLockUntil = DateTime.fromMillisecondsSinceEpoch(0);
              _setDetailExpanded(false);
            } else if (_currentStep == PlannerStep.preferences) {
              setState(() => _currentStep = PlannerStep.startingPoint);
            } else if (_currentStep == PlannerStep.startingPoint) {
              setState(() => _currentStep = PlannerStep.bifurcation);
            } else {
              Navigator.of(context).pop();
            }
          },
        ),
        title: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                color: OhtliColors.stormyTeal.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: SvgPicture.asset(
                'assets/icon_isologo.svg',
                colorFilter: const ColorFilter.mode(OhtliColors.stormyTeal, BlendMode.srcIn),
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Planea tu viaje',
                  style: GoogleFonts.outfit(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: OhtliColors.onyx,
                  ),
                ),
                Text(
                  _currentStep == PlannerStep.routeTriadCarousel
                      ? '3 multirutas temáticas calculadas por IA'
                      : 'Diseño inteligente de experiencias en CDMX',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: OhtliColors.subtleText,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          if (_currentStep == PlannerStep.blackboardProcessing)
            TextButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Tu itinerario se está calculando en segundo plano. Puedes consultarlo en Mis Viajes > Planes.',
                      style: GoogleFonts.inter(),
                    ),
                    backgroundColor: OhtliColors.stormyTeal,
                  ),
                );
              },
              icon: const Icon(Icons.explore_outlined, color: OhtliColors.stormyTeal, size: 16),
              label: Text(
                'Explorar en segundo plano',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: OhtliColors.stormyTeal,
                ),
              ),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: Stack(
        children: [
          // Background Route Canvas
          Positioned.fill(
            child: CustomPaint(
              painter: RouteBackgroundPainter(OhtliColors.cantera.withOpacity(0.95)),
            ),
          ),
          SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: _currentStep == PlannerStep.routeTriadCarousel ? double.infinity : 780,
                ),
                child: _currentStep == PlannerStep.routeTriadCarousel
                    // El selector de rutas ocupa todo el alto disponible (sin scroll externo)
                    ? Padding(
                        padding: EdgeInsets.only(top: isMobile ? 8 : 16),
                        child: _buildStepContent(isMobile),
                      )
                    : SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        padding: EdgeInsets.symmetric(
                          horizontal: isMobile ? 16 : 24,
                          vertical: isMobile ? 12 : 24,
                        ),
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 300),
                          child: _buildStepContent(isMobile),
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepContent(bool isMobile) {
    switch (_currentStep) {
      case PlannerStep.bifurcation:
        return _buildBifurcationStep(isMobile);
      case PlannerStep.startingPoint:
        return _buildStartingPointStep(isMobile);
      case PlannerStep.preferences:
        return _buildPreferencesStep(isMobile);
      case PlannerStep.blackboardProcessing:
        return _buildBlackboardProcessingStep(isMobile);
      case PlannerStep.routeTriadCarousel:
        return _buildRouteTriadCarouselStep(isMobile);
    }
  }

  // ==========================================
  // PASO 0: BIFURCACIÓN INICIAL
  // ==========================================
  Widget _buildBifurcationStep(bool isMobile) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const SizedBox(height: 12),
        Text(
          '¿Cómo deseas planear tu viaje?',
          textAlign: TextAlign.center,
          style: GoogleFonts.outfit(
            fontSize: isMobile ? 24 : 32,
            fontWeight: FontWeight.w800,
            color: OhtliColors.onyx,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Elige entre la asistencia de los agentes autónomos de Yollotl Engine o armar cada parada por tu cuenta.',
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(
            fontSize: 13,
            color: OhtliColors.subtleText,
          ),
        ),
        const SizedBox(height: 36),

        // Tarjeta 1: Obtener planes con IA
        _buildBifurcationCard(
          title: 'Obtener planes con IA',
          subtitle: 'El Sistema Multiagente cruza tus gustos culturales, optimiza traslados y maximiza tu presupuesto generando 3 rutas.',
          badge: 'RECOMENDADO',
          badgeColor: OhtliColors.stormyTeal,
          icon: Icons.explore_rounded,
          accentColor: OhtliColors.stormyTeal,
          onTap: () {
            setState(() {
              _currentStep = PlannerStep.startingPoint;
            });
          },
        ),
        const SizedBox(height: 18),

        // Tarjeta 2: Quiero hacerlo por mi cuenta
        _buildBifurcationCard(
          title: 'Quiero hacerlo por mi cuenta',
          subtitle: 'Crea un borrador en blanco para agregar lugares, fotos, notas personales y ajustar tus paradas de forma 100% manual.',
          icon: Icons.edit_note_rounded,
          accentColor: const Color(0xFF6C5CE7),
          onTap: _handleManualPlanSelected,
        ),
      ],
    );
  }

  Widget _buildBifurcationCard({
    required String title,
    required String subtitle,
    String? badge,
    Color? badgeColor,
    required IconData icon,
    required Color accentColor,
    required VoidCallback onTap,
  }) {
    final isDark = OhtliSettings.instance.isDarkMode;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E1E22) : Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: badge != null ? accentColor.withOpacity(0.5) : OhtliColors.cardBorder,
              width: badge != null ? 1.8 : 1.0,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 18,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: accentColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: accentColor, size: 26),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            title,
                            style: GoogleFonts.outfit(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: OhtliColors.onyx,
                            ),
                          ),
                        ),
                        if (badge != null) ...[
                          const SizedBox(width: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: badgeColor ?? accentColor,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              badge,
                              style: GoogleFonts.inter(
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.8,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      subtitle,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: OhtliColors.subtleText,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.arrow_forward_ios_rounded, size: 16, color: OhtliColors.subtleText),
            ],
          ),
        ),
      ),
    );
  }

  // ==========================================
  // PASO 1: PUNTO DE PARTIDA Y DIRECCIONES
  // ==========================================
  Widget _buildStartingPointStep(bool isMobile) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '¿Desde dónde inicia tu recorrido?',
          style: GoogleFonts.outfit(
            fontSize: isMobile ? 22 : 26,
            fontWeight: FontWeight.w800,
            color: OhtliColors.onyx,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Elige tu hotel, tu casa o cualquier punto de partida en la Ciudad de México para calcular traslados realistas.',
          style: GoogleFonts.inter(fontSize: 13, color: OhtliColors.subtleText),
        ),
        const SizedBox(height: 24),

        // Campo de búsqueda libre
        Container(
          decoration: BoxDecoration(
            color: OhtliColors.inputBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: OhtliColors.cardBorder),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            children: [
              const Icon(Icons.search_rounded, color: OhtliColors.stormyTeal, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _originSearchController,
                  style: GoogleFonts.inter(fontSize: 14, color: OhtliColors.onyx),
                  decoration: InputDecoration(
                    hintText: 'Ingresa una dirección, colonia o POI...',
                    hintStyle: GoogleFonts.inter(fontSize: 13, color: OhtliColors.subtleText),
                    border: InputBorder.none,
                  ),
                  onSubmitted: (val) {
                    if (val.trim().isNotEmpty) {
                      setState(() {
                        _selectedOriginName = val.trim();
                        _selectedOriginCoords = {'lat': 19.4326, 'lng': -99.1332};
                      });
                    }
                  },
                ),
              ),
              if (_originSearchController.text.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.clear_rounded, size: 18),
                  onPressed: () {
                    setState(() {
                      _originSearchController.clear();
                      _selectedOriginName = '';
                      _selectedOriginCoords = null;
                    });
                  },
                ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // Direcciones Guardadas del Usuario
        if (_userSavedAddresses.isNotEmpty) ...[
          Text(
            'TUS DIRECCIONES GUARDADAS',
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.0,
              color: OhtliColors.subtleText,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _userSavedAddresses.map((addr) {
              final label = (addr['label'] ?? addr['name'] ?? 'Dirección').toString();
              final addressStr = (addr['address'] ?? '').toString();
              final isSelected = _selectedOriginName == label || _selectedOriginName == addressStr;
              final lat = (addr['lat'] as num?)?.toDouble() ?? 19.4326;
              final lng = (addr['lng'] as num?)?.toDouble() ?? -99.1332;

              return ActionChip(
                avatar: Icon(
                  Icons.bookmark_rounded,
                  size: 15,
                  color: isSelected ? Colors.white : OhtliColors.stormyTeal,
                ),
                label: Text(
                  label,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                    color: isSelected ? Colors.white : OhtliColors.onyx,
                  ),
                ),
                backgroundColor: isSelected ? OhtliColors.stormyTeal : OhtliColors.innerCardBg,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                    color: isSelected ? OhtliColors.stormyTeal : OhtliColors.cardBorder,
                  ),
                ),
                onPressed: () {
                  setState(() {
                    _selectedOriginName = label;
                    _selectedOriginCoords = {'lat': lat, 'lng': lng};
                    _originSearchController.text = label;
                  });
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 24),
        ],

        // Zonas Clave sugeridas en CDMX
        Text(
          'O SELECCIONA UNA ZONA ICÓNICA DE CDMX',
          style: GoogleFonts.inter(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.0,
            color: OhtliColors.subtleText,
          ),
        ),
        const SizedBox(height: 12),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: isMobile ? 1 : 2,
            childAspectRatio: isMobile ? 4.2 : 3.4,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
          ),
          itemCount: _cdmxKeyZones.length,
          itemBuilder: (context, idx) {
            final zone = _cdmxKeyZones[idx];
            final name = zone['name'] as String;
            final icon = zone['icon'] as IconData;
            final coords = Map<String, double>.from(zone['coords'] as Map);
            final isSelected = _selectedOriginName == name;

            return InkWell(
              onTap: () {
                setState(() {
                  _selectedOriginName = name;
                  _selectedOriginCoords = coords;
                  _originSearchController.text = name;
                });
              },
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: isSelected ? OhtliColors.stormyTeal.withOpacity(0.08) : OhtliColors.innerCardBg,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isSelected ? OhtliColors.stormyTeal : OhtliColors.cardBorder,
                    width: isSelected ? 1.8 : 1.0,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: isSelected ? OhtliColors.stormyTeal : OhtliColors.cardBorder.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(icon, size: 18, color: isSelected ? Colors.white : OhtliColors.onyx),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        name,
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                          color: isSelected ? OhtliColors.stormyTeal : OhtliColors.onyx,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (isSelected)
                      const Icon(Icons.check_circle_rounded, color: OhtliColors.stormyTeal, size: 18),
                  ],
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 32),

        // Botón Continuar
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            ElevatedButton(
              onPressed: _selectedOriginName.trim().isEmpty
                  ? null
                  : () {
                      setState(() => _currentStep = PlannerStep.preferences);
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: OhtliColors.stormyTeal,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 15),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 0,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Continuar a Preferencias', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold)),
                  const SizedBox(width: 8),
                  const Icon(Icons.arrow_forward_rounded, size: 16),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ==========================================
  // PASO 2: PREFERENCIAS & PRESUPUESTO
  // ==========================================
  Widget _buildPreferencesStep(bool isMobile) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '¿Cuál es la vibra y presupuesto de tu día?',
          style: GoogleFonts.outfit(
            fontSize: isMobile ? 22 : 26,
            fontWeight: FontWeight.w800,
            color: OhtliColors.onyx,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Ajusta el estilo de experiencia deseado. Nuestro Sistema Multiagente optimizará tus opciones de viaje basándose en estos parámetros.',
          style: GoogleFonts.inter(fontSize: 13, color: OhtliColors.subtleText),
        ),
        const SizedBox(height: 24),

        // Fecha del Viaje
        Text(
          'FECHA DEL VIAJE',
          style: GoogleFonts.inter(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.0,
            color: OhtliColors.subtleText,
          ),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: OhtliColors.innerCardBg,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: OhtliColors.cardBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: OhtliColors.stormyTeal.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.calendar_today_rounded, color: OhtliColors.stormyTeal, size: 20),
                      ),
                      const SizedBox(width: 14),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _formatDate(_selectedTravelDate),
                            style: GoogleFonts.outfit(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: OhtliColors.onyx,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Fecha programada para el itinerario',
                            style: GoogleFonts.inter(fontSize: 11, color: OhtliColors.subtleText),
                          ),
                        ],
                      ),
                    ],
                  ),
                  TextButton.icon(
                    onPressed: _pickTravelDate,
                    icon: const Icon(Icons.edit_calendar_rounded, size: 16, color: OhtliColors.stormyTeal),
                    label: Text(
                      'Cambiar',
                      style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: OhtliColors.stormyTeal),
                    ),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      backgroundColor: OhtliColors.stormyTeal.withOpacity(0.08),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              // Chips de acceso rápido
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _buildQuickDateChip('Hoy', DateTime.now()),
                  _buildQuickDateChip('Mañana', DateTime.now().add(const Duration(days: 1))),
                  _buildQuickDateChip('Este Fin de Semana', _getNextWeekend()),
                  _buildQuickDateChip('En 1 semana', DateTime.now().add(const Duration(days: 7))),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // Slider de Presupuesto
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: OhtliColors.innerCardBg,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: OhtliColors.cardBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Presupuesto objetivo por persona',
                    style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold, color: OhtliColors.onyx),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(
                      color: OhtliColors.stormyTeal,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '\$${_budgetMxn.toStringAsFixed(0)} MXN',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: OhtliColors.stormyTeal,
                  inactiveTrackColor: OhtliColors.stormyTeal.withOpacity(0.15),
                  thumbColor: OhtliColors.stormyTeal,
                  overlayColor: OhtliColors.stormyTeal.withOpacity(0.12),
                ),
                child: Slider(
                  value: _budgetMxn,
                  min: 150.0,
                  max: 2000.0,
                  divisions: 37,
                  onChanged: (val) {
                    setState(() => _budgetMxn = val);
                  },
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Económico (\$150 MXN)', style: GoogleFonts.inter(fontSize: 11, color: OhtliColors.subtleText)),
                  Text('Experiencia Premium (\$2,000 MXN)', style: GoogleFonts.inter(fontSize: 11, color: OhtliColors.subtleText)),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // Moods Presets
        Text(
          'ESTILO / MOOD CULTURAL',
          style: GoogleFonts.inter(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.0,
            color: OhtliColors.subtleText,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _moodPresets.map((mood) {
            final isSelected = _selectedMood == mood && _customMoodController.text.trim().isEmpty;
            return ChoiceChip(
              label: Text(mood),
              labelStyle: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected ? Colors.white : OhtliColors.onyx,
              ),
              selected: isSelected,
              selectedColor: OhtliColors.stormyTeal,
              backgroundColor: OhtliColors.innerCardBg,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: isSelected ? OhtliColors.stormyTeal : OhtliColors.cardBorder,
                ),
              ),
              onSelected: (val) {
                if (val) {
                  setState(() {
                    _selectedMood = mood;
                    _customMoodController.clear();
                  });
                }
              },
            );
          }).toList(),
        ),
        const SizedBox(height: 14),

        // Custom Mood Input
        Container(
          decoration: BoxDecoration(
            color: OhtliColors.inputBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: OhtliColors.cardBorder),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: TextField(
            controller: _customMoodController,
            style: GoogleFonts.inter(fontSize: 13, color: OhtliColors.onyx),
            decoration: InputDecoration(
              hintText: 'O escribe tu vibra personalizada (ej. "librerías viejas y café solo")...',
              hintStyle: GoogleFonts.inter(fontSize: 12, color: OhtliColors.subtleText),
              border: InputBorder.none,
            ),
            onChanged: (val) {
              setState(() {});
            },
          ),
        ),
        const SizedBox(height: 24),

        // Topología de Ruta
        Text(
          'TOPOLOGÍA DE RECORRIDO',
          style: GoogleFonts.inter(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.0,
            color: OhtliColors.subtleText,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _buildTopologyOption(
                key: 'anillo',
                title: 'Ruta en Anillo',
                desc: 'Inicia y regresa cerca del mismo punto',
                icon: Icons.loop_rounded,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildTopologyOption(
                key: 'radio',
                title: 'Ruta Abierta',
                desc: 'Avanza explorando sin volver al origen',
                icon: Icons.trending_flat_rounded,
              ),
            ),
          ],
        ),
        const SizedBox(height: 32),

        // Botón Lanzar Generación con IA
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            ElevatedButton(
              onPressed: _launchBlackboardJob,
              style: ElevatedButton.styleFrom(
                backgroundColor: OhtliColors.stormyTeal,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 4,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Calcular Opciones de Viaje', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold)),
                  const SizedBox(width: 8),
                  const Icon(Icons.arrow_forward_rounded, size: 16),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTopologyOption({
    required String key,
    required String title,
    required String desc,
    required IconData icon,
  }) {
    final isSelected = _selectedTopology == key;
    return InkWell(
      onTap: () => setState(() => _selectedTopology = key),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected ? OhtliColors.stormyTeal.withOpacity(0.08) : OhtliColors.innerCardBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? OhtliColors.stormyTeal : OhtliColors.cardBorder,
            width: isSelected ? 1.8 : 1.0,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Icon(icon, color: isSelected ? OhtliColors.stormyTeal : OhtliColors.onyx, size: 20),
                if (isSelected)
                  const Icon(Icons.check_circle_rounded, color: OhtliColors.stormyTeal, size: 16),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              title,
              style: GoogleFonts.outfit(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: isSelected ? OhtliColors.stormyTeal : OhtliColors.onyx,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              desc,
              style: GoogleFonts.inter(fontSize: 11, color: OhtliColors.subtleText),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // PASO 3: PROCESAMIENTO SMA (BLACKBOARD)
  // ==========================================
  Widget _buildBlackboardProcessingStep(bool isMobile) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const SizedBox(height: 30),
        Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: 110,
              height: 110,
              child: CircularProgressIndicator(
                value: _blackboardProgress / 100.0,
                strokeWidth: 4,
                valueColor: const AlwaysStoppedAnimation<Color>(OhtliColors.stormyTeal),
                backgroundColor: OhtliColors.stormyTeal.withOpacity(0.12),
              ),
            ),
            Container(
              width: 78,
              height: 78,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: OhtliColors.stormyTeal.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: SvgPicture.asset(
                'assets/icon_isologo.svg',
                colorFilter: const ColorFilter.mode(OhtliColors.stormyTeal, BlendMode.srcIn),
              ),
            ),
          ],
        ),
        const SizedBox(height: 28),
        Text(
          'Agentes de Yollotl en Acción',
          textAlign: TextAlign.center,
          style: GoogleFonts.outfit(
            fontSize: isMobile ? 22 : 26,
            fontWeight: FontWeight.w800,
            color: OhtliColors.onyx,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Agente activo: $_currentAgentName · Calculando candidatos y optimizando traslados...',
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(fontSize: 13, color: OhtliColors.subtleText),
        ),
        const SizedBox(height: 36),

        // Steps Visualization
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: OhtliColors.innerCardBg,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: OhtliColors.cardBorder),
          ),
          child: Column(
            children: [
              _buildAgentStateRow(
                agentLabel: 'Agente Comparador',
                taskDesc: 'Prefiltro por vector de afinidad, presupuesto y MMR de diversidad',
                isActive: _currentAgentName == 'Comparador',
                isDone: _blackboardProgress > 35,
              ),
              const Divider(height: 24),
              _buildAgentStateRow(
                agentLabel: 'Agente Generador',
                taskDesc: 'Trazado topológico ($_selectedTopology) y optimización de fatiga de caminata',
                isActive: _currentAgentName == 'Generador',
                isDone: _blackboardProgress > 70,
              ),
              const Divider(height: 24),
              _buildAgentStateRow(
                agentLabel: 'Agente Recomendador',
                taskDesc: 'Curaduría editorial, sinopsis culturales y calibración de costos en MXN',
                isActive: _currentAgentName == 'Recomendador',
                isDone: _blackboardProgress >= 95,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAgentStateRow({
    required String agentLabel,
    required String taskDesc,
    required bool isActive,
    required bool isDone,
  }) {
    Color iconBg = isDone
        ? const Color(0xFF10B981)
        : (isActive ? OhtliColors.stormyTeal : OhtliColors.cardBorder);
    IconData icon = isDone
        ? Icons.check_rounded
        : (isActive ? Icons.sync_rounded : Icons.radio_button_unchecked_rounded);

    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: iconBg.withOpacity(0.15),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: iconBg, size: 18),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                agentLabel,
                style: GoogleFonts.outfit(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: isActive ? OhtliColors.stormyTeal : OhtliColors.onyx,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                taskDesc,
                style: GoogleFonts.inter(fontSize: 11, color: OhtliColors.subtleText),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ==========================================
  // PASO 4: SELECTOR CINEMATOGRÁFICO DE OPCIONES DE VIAJE
  // ==========================================

  static String _upgradeImageUrl(String url, {int width = 1200, int quality = 85}) {
    final clean = url.trim();
    if (clean.isEmpty) return clean;
    if (clean.contains('unsplash.com')) {
      final uri = Uri.tryParse(clean);
      if (uri != null) {
        final query = Map<String, String>.from(uri.queryParameters);
        query['auto'] = 'format';
        query['fit'] = 'crop';
        query['w'] = width.toString();
        query['q'] = quality.toString();
        return uri.replace(queryParameters: query).toString();
      }
    }
    return clean;
  }

  static String _resolveStopPhoto(Map<String, dynamic> stop, int idx) {
    final raw = (stop['photo_url'] ?? stop['main_photo_url'] ?? stop['image_url'] ?? stop['photo'] ?? '').toString().trim();
    if (raw.isNotEmpty) {
      return _upgradeImageUrl(raw, width: 800, quality: 85);
    }
    return CdmxPhotos.forCategory((stop['category'] ?? stop['type'] ?? '').toString(), idx);
  }

  static IconData _getStopCategoryIcon(String category) {
    final cat = category.toLowerCase().trim();
    switch (cat) {
      case 'cafe':
      case 'coffee':
        return Icons.local_cafe_rounded;
      case 'restaurant':
      case 'food':
        return Icons.restaurant_rounded;
      case 'fast_food':
        return Icons.fastfood_rounded;
      case 'bakery':
      case 'pastry':
        return Icons.bakery_dining_rounded;
      case 'museum':
        return Icons.museum_rounded;
      case 'park':
      case 'garden':
        return Icons.park_rounded;
      case 'artwork':
      case 'art':
      case 'monument':
        return Icons.palette_rounded;
      case 'bar':
      case 'cantina':
      case 'pub':
        return Icons.local_bar_rounded;
      case 'market':
      case 'marketplace':
        return Icons.storefront_rounded;
      case 'theatre':
      case 'theater':
      case 'cinema':
        return Icons.theater_comedy_rounded;
      case 'church':
      case 'cathedral':
        return Icons.church_rounded;
      default:
        return Icons.place_rounded;
    }
  }

  static Color _getStopCategoryColor(String category) {
    final cat = category.toLowerCase().trim();
    switch (cat) {
      case 'cafe':
      case 'coffee':
      case 'bakery':
        return const Color(0xFFD97706);
      case 'restaurant':
      case 'food':
        return const Color(0xFFEF4444);
      case 'museum':
      case 'artwork':
      case 'art':
        return OhtliColors.stormyTeal;
      case 'park':
      case 'garden':
        return const Color(0xFF10B981);
      case 'bar':
      case 'cantina':
      case 'pub':
        return const Color(0xFF8B5CF6);
      case 'market':
      case 'marketplace':
        return OhtliColors.cempasuchil;
      default:
        return OhtliColors.stormyTeal;
    }
  }

  // ==========================================
  // SELECTOR DE RUTAS (inspirado en la selección de opciones de Apple TV)
  // - La tarjeta enfocada se eleva y responde al cursor (parallax)
  // - Al abrirla, la misma tarjeta se transforma hasta ocupar toda la pantalla
  //   mientras el carrusel retrocede al fondo
  // ==========================================
  static const double _carouselHeaderHeight = 60.0;

  double _carouselFractionFor(double width, bool isMobile) {
    if (isMobile) return 0.90;
    if (width < 1100) return 0.86;
    if (width < 1500) return 0.82;
    return 0.78;
  }

  Widget _buildRouteTriadCarouselStep(bool isMobile) {
    if (_generatedOptions.isEmpty) {
      return const SizedBox.shrink();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final screen = MediaQuery.of(context).size;
        final double w = constraints.maxWidth.isFinite ? constraints.maxWidth : screen.width;
        final double h = constraints.maxHeight.isFinite ? constraints.maxHeight : screen.height * 0.85;

        final fraction = _carouselFractionFor(w, isMobile);
        final controller = _getTriadPageController(fraction);
        final double bottomGap = isMobile ? 8 : 20;
        final double pageH = (h - _carouselHeaderHeight - bottomGap).clamp(240.0, double.infinity);
        final double pageW = w * fraction;
        const double cardMarginH = 10;
        const double cardMarginV = 8;

        // Rectángulo exacto de la tarjeta enfocada dentro del carrusel (punto de partida del morph)
        final compactRect = Rect.fromLTWH((w - pageW) / 2 + cardMarginH, _carouselHeaderHeight + cardMarginV, pageW - cardMarginH * 2, pageH - cardMarginV * 2);
        // Rectángulo final: toda la pantalla disponible
        final double inset = isMobile ? 0 : 12;
        final fullRect = Rect.fromLTWH(inset, 0, w - inset * 2, h - (isMobile ? 0 : inset));

        final headerMaxWidth = isMobile ? double.infinity : pageW;

        // Capa base: encabezado + carrusel. Se construye una vez y se reutiliza en cada frame.
        final baseLayer = Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(height: _carouselHeaderHeight, child: _buildCarouselHeader(controller, headerMaxWidth)),
            SizedBox(height: pageH, child: _buildCarouselPager(controller, isMobile)),
          ],
        );

        final activeIndex = _activeCarouselIndex.clamp(0, _generatedOptions.length - 1);
        final activeOption = _generatedOptions[activeIndex];
        final detailContent = Padding(padding: EdgeInsets.all(isMobile ? 16 : 28), child: _buildInPageExpandedDetail(activeOption, activeIndex, isMobile, isEmbeddedInCard: true));

        return Focus(
          focusNode: _carouselFocusNode,
          autofocus: true,
          onKeyEvent: _handleCarouselKey,
          child: SizedBox(
            width: w,
            height: h,
            child: AnimatedBuilder(
              animation: _expandCurve,
              child: baseLayer,
              builder: (context, base) {
                final t = _expandCurve.value;
                final showOverlay = _expandController.value > 0.0005;
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // El carrusel retrocede (escala + atenuación) como en el home de Apple TV
                    Positioned.fill(
                      child: IgnorePointer(
                        ignoring: showOverlay,
                        child: Opacity(
                          opacity: (1 - t * 1.15).clamp(0.0, 1.0),
                          child: Transform.scale(scale: 1 - 0.06 * t, child: base),
                        ),
                      ),
                    ),
                    if (showOverlay)
                      Positioned.fromRect(
                        rect: Rect.lerp(compactRect, fullRect, t)!,
                        // Durante el morph se ignora la inercia del scroll para que la transición sea estable
                        child: IgnorePointer(
                          ignoring: _expandController.isAnimating,
                          child: _buildExpandedCard(option: activeOption, index: activeIndex, isMobile: isMobile, t: t, startHeight: compactRect.height, detailContent: detailContent),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildCarouselHeader(PageController controller, double headerMaxWidth) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: headerMaxWidth),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ALTERNATIVAS DISEÑADAS POR IA · ${_activeCarouselIndex + 1} DE ${_generatedOptions.length}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 1.4, color: OhtliColors.stormyTeal),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Elige tu ruta',
                      maxLines: 1,
                      style: GoogleFonts.outfit(fontSize: 24, fontWeight: FontWeight.w700, color: OhtliColors.onyx, height: 1.1),
                    ),
                  ],
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(_generatedOptions.length, (idx) {
                  final isSelected = _activeCarouselIndex == idx;
                  return InkWell(
                    onTap: () {
                      controller.animateToPage(idx, duration: const Duration(milliseconds: 380), curve: Curves.easeOutCubic);
                    },
                    borderRadius: BorderRadius.circular(4),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOutCubic,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: isSelected ? 28 : 10,
                      height: 8,
                      decoration: BoxDecoration(color: isSelected ? OhtliColors.stormyTeal : OhtliColors.cardBorder, borderRadius: BorderRadius.circular(4)),
                    ),
                  );
                }),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCarouselPager(PageController controller, bool isMobile) {
    return Stack(
      alignment: Alignment.center,
      children: [
        PageView.builder(
          controller: controller,
          itemCount: _generatedOptions.length,
          onPageChanged: (idx) {
            _hoverTilt.value = Offset.zero;
            setState(() => _activeCarouselIndex = idx);
          },
          itemBuilder: (context, index) {
            final isFocused = _activeCarouselIndex == index;
            // Escala/opacidad continuas según la posición real del PageView (sin saltos al soltar)
            return AnimatedBuilder(
              animation: controller,
              builder: (context, child) {
                double distance = (index - _activeCarouselIndex).abs().toDouble();
                if (controller.hasClients && controller.position.haveDimensions) {
                  distance = ((controller.page ?? _activeCarouselIndex.toDouble()) - index).abs();
                }
                final d = distance.clamp(0.0, 1.0);
                return Transform.scale(
                  scale: 1.0 - 0.12 * d,
                  child: Opacity(opacity: 1.0 - 0.48 * d, child: child),
                );
              },
              child: _buildCompactCard(option: _generatedOptions[index], isFocused: isFocused, isMobile: isMobile, index: index),
            );
          },
        ),
        if (!isMobile && _activeCarouselIndex > 0)
          Positioned(
            left: 20,
            child: _buildCarouselArrow(Icons.arrow_back_ios_new_rounded, () => controller.previousPage(duration: const Duration(milliseconds: 380), curve: Curves.easeOutCubic)),
          ),
        if (!isMobile && _activeCarouselIndex < _generatedOptions.length - 1)
          Positioned(
            right: 20,
            child: _buildCarouselArrow(Icons.arrow_forward_ios_rounded, () => controller.nextPage(duration: const Duration(milliseconds: 380), curve: Curves.easeOutCubic)),
          ),
      ],
    );
  }

  Widget _buildCarouselArrow(IconData icon, VoidCallback onTap) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.6),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white.withOpacity(0.2)),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 4))],
          ),
          child: Icon(icon, color: Colors.white, size: 18),
        ),
      ),
    );
  }

  ({String title, String summary, double cost, String timeStr, String coverUrl, List<dynamic> stops}) _routeCardData(Map<String, dynamic> option, int index) {
    final title = (option['editorial_headline'] ?? option['theme'] ?? 'Ruta ${index + 1}').toString();
    final summary = (option['narrative_summary'] ?? '').toString();
    final cost = (option['total_cost_mxn'] as num?)?.toDouble() ?? 250.0;
    final timeMins = _computeOptionTotalDuration(option);
    final List<dynamic> stops = option['route'] ?? [];

    String? rawCover = (option['cover_url'] as String?);
    if (rawCover == null || rawCover.trim().isEmpty) {
      if (stops.isNotEmpty) {
        final firstStop = stops[0];
        if (firstStop is Map) {
          final p = (firstStop['photo_url'] ?? firstStop['photo'] ?? firstStop['image_url'])?.toString().trim();
          if (p != null && p.isNotEmpty) {
            rawCover = p;
          }
        }
      }
    }
    final coverUrl = (rawCover != null && rawCover.trim().isNotEmpty) ? _upgradeImageUrl(rawCover, width: 1400, quality: 85) : CdmxPhotos.cover(index);

    final int hours = timeMins ~/ 60;
    final int minutes = timeMins % 60;
    final String timeStr = hours > 0 ? '$hours h $minutes min' : '$minutes min';
    return (title: title, summary: summary, cost: cost, timeStr: timeStr, coverUrl: coverUrl, stops: stops);
  }

  // Portada sin spinner: fondo oscuro estable + aparición suave (evita destellos al cambiar de vista)
  Widget _buildCoverImage(String url, {Offset parallax = Offset.zero}) {
    return Container(
      color: const Color(0xFF1E1E22),
      child: Transform.translate(
        offset: parallax,
        child: Transform.scale(
          scale: 1.0 + (parallax.distance / 12).clamp(0.0, 1.0) * 0.06,
          child: Image.network(
            url,
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
            gaplessPlayback: true,
            frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
              if (wasSynchronouslyLoaded) return child;
              return AnimatedOpacity(opacity: frame == null ? 0 : 1, duration: const Duration(milliseconds: 350), curve: Curves.easeOut, child: child);
            },
            errorBuilder: (context, error, stackTrace) => Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(colors: [Color(0xFF1F2937), Color(0xFF111827)], begin: Alignment.topLeft, end: Alignment.bottomRight),
              ),
              child: const Center(child: Icon(Icons.explore_rounded, size: 48, color: Colors.white24)),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOptionBadges(Map<String, dynamic> option, int index) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(color: OhtliColors.stormyTeal, borderRadius: BorderRadius.circular(8)),
          child: Text(
            'OPCIÓN ${index + 1}',
            style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.0, color: Colors.white),
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.45),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white.withOpacity(0.15)),
            ),
            child: Text(
              (option['theme'] ?? 'EXPERIENCIA').toString().toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.8, color: Colors.white.withOpacity(0.9)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBookmarkButton() {
    return IconButton(
      onPressed: () {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Esta opción permanecerá guardada en tu pestaña Planes.', style: GoogleFonts.inter()),
            backgroundColor: OhtliColors.stormyTeal,
          ),
        );
      },
      icon: const Icon(Icons.bookmark_add_outlined, color: Colors.white, size: 20),
      tooltip: 'Guardar alternativa en Planes',
      style: IconButton.styleFrom(backgroundColor: Colors.black.withOpacity(0.45), padding: const EdgeInsets.all(8)),
    );
  }

  Widget _buildChooseRouteButton(Map<String, dynamic> option, double cost, bool isMobile, {bool compact = false}) {
    return ElevatedButton.icon(
      onPressed: _isSavingTrip ? null : () => _chooseRouteAndCreateTrip(option),
      icon: _isSavingTrip
          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
          : Icon(Icons.play_arrow_rounded, color: Colors.black, size: compact ? 18 : 20),
      label: Text(
        _isSavingTrip ? (compact ? 'Creando...' : 'Creando viaje...') : (compact ? 'Elegir (\$${cost.toStringAsFixed(0)})' : 'Elegir esta ruta (\$${cost.toStringAsFixed(0)} MXN)'),
        style: GoogleFonts.outfit(fontSize: compact ? 13 : (isMobile ? 13 : 14.5), fontWeight: FontWeight.w800, color: Colors.black, letterSpacing: 0.2),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        padding: compact ? const EdgeInsets.symmetric(horizontal: 16, vertical: 12) : EdgeInsets.symmetric(horizontal: isMobile ? 18 : 26, vertical: isMobile ? 12 : 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
        elevation: 6,
      ),
    );
  }

  Widget _buildCompactCard({required Map<String, dynamic> option, required bool isFocused, required bool isMobile, required int index}) {
    final data = _routeCardData(option, index);
    double verticalDragDelta = 0;

    Widget card(Offset tilt) {
      final hovering = tilt != Offset.zero;
      // Inclinación 3D sutil + elevación al pasar el cursor (efecto de foco de Apple TV)
      final transform = Matrix4.identity()
        ..setEntry(3, 2, 0.0009)
        ..rotateX(-tilt.dy * 0.06)
        ..rotateY(tilt.dx * 0.06)
        ..scale(hovering ? 1.015 : 1.0);
      return Transform(
        alignment: Alignment.center,
        transform: transform,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: isFocused ? Colors.white.withOpacity(0.35) : Colors.white.withOpacity(0.08), width: isFocused ? 1.8 : 1.0),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(isFocused ? (hovering ? 0.45 : 0.35) : 0.15), blurRadius: isFocused ? (hovering ? 40 : 28) : 14, offset: Offset(0, hovering ? 18 : 10)),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: Stack(
              children: [
                Positioned.fill(child: _buildCoverImage(data.coverUrl, parallax: Offset(-tilt.dx * 14, -tilt.dy * 10))),
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.black.withOpacity(0.65), Colors.black.withOpacity(0.15), Colors.black.withOpacity(0.70), Colors.black.withOpacity(0.97)],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: const [0.0, 0.28, 0.62, 1.0],
                      ),
                    ),
                  ),
                ),
                // Brillo especular que sigue al cursor
                if (hovering)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: RadialGradient(center: Alignment(tilt.dx, tilt.dy), radius: 0.9, colors: [Colors.white.withOpacity(0.14), Colors.white.withOpacity(0.0)]),
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  top: isMobile ? 16 : 22,
                  left: isMobile ? 16 : 24,
                  right: isMobile ? 16 : 24,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(child: _buildOptionBadges(option, index)),
                      _buildBookmarkButton(),
                    ],
                  ),
                ),
                Positioned(
                  left: isMobile ? 16 : 26,
                  right: isMobile ? 16 : 26,
                  bottom: isMobile ? 16 : 24,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          _buildMetaPill(Icons.schedule_rounded, data.timeStr),
                          _buildMetaPill(Icons.payments_outlined, '\$${data.cost.toStringAsFixed(0)} MXN'),
                          _buildMetaPill(Icons.place_rounded, '${data.stops.length} paradas'),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        data.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.outfit(fontSize: isMobile ? 20 : 26, fontWeight: FontWeight.bold, color: Colors.white, height: 1.2),
                      ),
                      const SizedBox(height: 8),
                      if (data.summary.isNotEmpty)
                        Text(
                          data.summary,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(fontSize: isMobile ? 12 : 13.5, color: Colors.white.withOpacity(0.88), height: 1.35),
                        ),
                      const SizedBox(height: 14),
                      _buildCardRouteTrail(data.stops, option, index),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          _buildChooseRouteButton(option, data.cost, isMobile),
                          const Spacer(),
                          if (isFocused && isMobile)
                            const Icon(Icons.keyboard_arrow_up_rounded, color: Colors.white60, size: 22)
                          else if (isFocused)
                            Flexible(
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  Flexible(
                                    child: Text(
                                      'Desplázate para ver detalles',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.inter(fontSize: 11, color: Colors.white60),
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white60, size: 18),
                                ],
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
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) => Listener(
        onPointerSignal: (event) => _handleCompactWheel(event, isFocused),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onHover: (event) {
            if (!isFocused || isMobile || _isDetailExpanded) return;
            final size = constraints.biggest;
            if (size.isEmpty || !size.isFinite) return;
            final local = event.localPosition;
            _hoverTilt.value = Offset(((local.dx / size.width) * 2 - 1).clamp(-1.0, 1.0), ((local.dy / size.height) * 2 - 1).clamp(-1.0, 1.0));
          },
          onExit: (_) {
            if (isFocused) _hoverTilt.value = Offset.zero;
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              if (!isFocused) {
                _triadPageController?.animateToPage(index, duration: const Duration(milliseconds: 380), curve: Curves.easeOutCubic);
              } else {
                _setDetailExpanded(true);
              }
            },
            onVerticalDragUpdate: (details) {
              if (!isFocused) return;
              verticalDragDelta += details.primaryDelta ?? 0;
            },
            onVerticalDragEnd: (details) {
              final velocity = details.primaryVelocity ?? 0;
              // Deslizar hacia arriba abre el detalle a pantalla completa
              if (isFocused && (velocity < -200 || verticalDragDelta < -40)) {
                _setDetailExpanded(true);
              }
              verticalDragDelta = 0;
            },
            child: isFocused
                ? ValueListenableBuilder<Offset>(
                    valueListenable: _hoverTilt,
                    builder: (context, tilt, _) => TweenAnimationBuilder<Offset>(
                      tween: Tween(end: tilt),
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOut,
                      builder: (context, smoothTilt, _) => card(smoothTilt),
                    ),
                  )
                : card(Offset.zero),
          ),
        ),
      ),
    );
  }

  Widget _buildExpandedCard({required Map<String, dynamic> option, required int index, required bool isMobile, required double t, required double startHeight, required Widget detailContent}) {
    final isDark = OhtliSettings.instance.isDarkMode;
    final data = _routeCardData(option, index);
    final scrollController = _getCardScrollController(index);

    // La portada arranca ocupando toda la tarjeta y se reduce a banner mientras la tarjeta crece
    final double bannerTarget = isMobile ? 300 : 320;
    final double bannerH = lerpDouble(startHeight, bannerTarget, t)!.clamp(bannerTarget, double.infinity);
    final double radius = lerpDouble(24, isMobile ? 0 : 20, t)!;
    final double contentReveal = ((t - 0.35) / 0.65).clamp(0.0, 1.0);

    return Listener(
      onPointerSignal: _handleDetailWheel,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E22) : Colors.white,
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: Colors.white.withOpacity(0.35 * (1 - t)), width: 1.8),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.35 + 0.1 * t), blurRadius: 28 + 20 * t, offset: const Offset(0, 12))],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: NotificationListener<ScrollNotification>(
            onNotification: _handleDetailScrollNotification,
            child: CustomScrollView(
              controller: scrollController,
              physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
              slivers: [
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: bannerH,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        _buildCoverImage(data.coverUrl),
                        DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [Colors.black.withOpacity(0.60), Colors.black.withOpacity(0.15), Colors.black.withOpacity(0.90)],
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              stops: const [0.0, 0.45, 1.0],
                            ),
                          ),
                        ),
                        Positioned(
                          top: isMobile ? 14 : 22,
                          left: isMobile ? 16 : 24,
                          right: isMobile ? 16 : 24,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Flexible(child: _buildOptionBadges(option, index)),
                              _buildBookmarkButton(),
                            ],
                          ),
                        ),
                        Positioned(
                          left: isMobile ? 16 : 28,
                          right: isMobile ? 16 : 28,
                          bottom: isMobile ? 16 : 24,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Wrap(
                                      spacing: 6,
                                      runSpacing: 6,
                                      children: [
                                        _buildMetaPill(Icons.schedule_rounded, data.timeStr),
                                        _buildMetaPill(Icons.payments_outlined, '\$${data.cost.toStringAsFixed(0)} MXN'),
                                        _buildMetaPill(Icons.place_rounded, '${data.stops.length} paradas'),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      data.title,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.outfit(fontSize: lerpDouble(isMobile ? 20 : 26, isMobile ? 24 : 32, t), fontWeight: FontWeight.bold, color: Colors.white, height: 1.15),
                                    ),
                                    // En móvil el botón va debajo del título para no comprimirlo
                                    if (isMobile) ...[
                                      const SizedBox(height: 12),
                                      _buildChooseRouteButton(option, data.cost, isMobile),
                                    ],
                                  ],
                                ),
                              ),
                              if (!isMobile) ...[
                                const SizedBox(width: 12),
                                _buildChooseRouteButton(option, data.cost, isMobile),
                              ],
                            ],
                          ),
                        ),
                        // Indicador para regresar (arrastrar / desplazar hacia arriba en el tope)
                        Positioned(
                          top: 6,
                          left: 0,
                          right: 0,
                          child: IgnorePointer(
                            child: Opacity(
                              opacity: contentReveal,
                              child: Center(
                                child: Container(
                                  width: 40,
                                  height: 4,
                                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.55), borderRadius: BorderRadius.circular(2)),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Opacity(
                    opacity: contentReveal,
                    child: Transform.translate(offset: Offset(0, 24 * (1 - contentReveal)), child: detailContent),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Trazado visual de la ruta en la tarjeta del carrusel
  Widget _buildCardRouteTrail(List<dynamic> stops, Map<String, dynamic> option, int index) {
    if (stops.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.45),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.route_rounded, color: OhtliColors.stormyTeal, size: 14),
                  const SizedBox(width: 6),
                  Text(
                    'RUTA Y PARADAS',
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.0,
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
              InkWell(
                onTap: () => _setDetailExpanded(true),
                child: Row(
                  children: [
                    Text(
                      'Ver en Mapa',
                      style: GoogleFonts.inter(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: OhtliColors.stormyTeal,
                      ),
                    ),
                    const SizedBox(width: 2),
                    const Icon(Icons.arrow_forward_ios_rounded, color: OhtliColors.stormyTeal, size: 10),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: stops.asMap().entries.map((entry) {
                final i = entry.key;
                final stop = entry.value as Map<String, dynamic>;
                final stopName = (stop['name'] ?? 'Lugar').toString();
                final isLast = i == stops.length - 1;

                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    InkWell(
                      onTap: () {
                        _openStopPoiModal(stop);
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.white.withOpacity(0.12)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 16,
                              height: 16,
                              decoration: const BoxDecoration(
                                color: OhtliColors.stormyTeal,
                                shape: BoxShape.circle,
                              ),
                              child: Center(
                                child: Text(
                                  '${i + 1}',
                                  style: GoogleFonts.inter(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              stopName.length > 20 ? '${stopName.substring(0, 18)}...' : stopName,
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (!isLast) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: Icon(
                          Icons.arrow_forward_rounded,
                          color: Colors.white.withOpacity(0.4),
                          size: 13,
                        ),
                      ),
                    ],
                  ],
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // DETALLE COMPLETO EXPANDIDO EN LA PÁGINA (MAPA + CRONOLOGÍA)
  // ==========================================
  Widget _buildInPageExpandedDetail(
    Map<String, dynamic> option,
    int index,
    bool isMobile, {
    bool isEmbeddedInCard = false,
  }) {
    final isDark = OhtliSettings.instance.isDarkMode;
    final summary = (option['narrative_summary'] ?? '').toString();
    final cost = (option['total_cost_mxn'] as num?)?.toDouble() ?? 250.0;
    final List<dynamic> rawStops = option['route'] ?? [];
    _prefetchStopPois(rawStops);

    String fmtMins(int mins) {
      final h = mins ~/ 60;
      final m = mins % 60;
      if (h == 0) return '$m min';
      return m == 0 ? '$h h' : '$h h $m min';
    }

    final int timeMins = _computeOptionTotalDuration(option);
    int totalStayMins = 0;
    int totalWalkMins = 0;
    for (final s in rawStops) {
      if (s is Map) {
        totalStayMins += (s['stay_duration_mins'] as num?)?.toInt() ?? 60;
        totalWalkMins += (s['travel_time_from_prev_mins'] as num?)?.toInt() ?? 0;
      }
    }
    final walkingKm = (option['total_walking_km'] as num?)?.toDouble() ??
        (option['osm_route'] is Map ? (option['osm_route']['total_distance_km'] as num?)?.toDouble() : null) ??
        rawStops.fold<double>(0.0, (acc, s) => acc + (s is Map ? ((s['travel_distance_from_prev_km'] as num?)?.toDouble() ?? 0.0) : 0.0));

    // Enlace opcional a Google Maps con las paradas como waypoints
    final waypointNames = <String>[];
    for (int i = 0; i < rawStops.length; i++) {
      final s = rawStops[i] as Map<String, dynamic>;
      final stopName = (s['name'] ?? 'Parada ${i + 1}').toString();
      double? lat = (s['lat'] as num?)?.toDouble() ?? (s['latitude'] as num?)?.toDouble();
      double? lng = (s['lng'] as num?)?.toDouble() ?? (s['longitude'] as num?)?.toDouble();
      final loc = s['location'] ?? s['coords'] ?? s['coordinates'];
      if (loc != null) {
        if (loc is Map) {
          lat ??= (loc['lat'] as num?)?.toDouble() ?? (loc['latitude'] as num?)?.toDouble();
          lng ??= (loc['lng'] as num?)?.toDouble() ?? (loc['longitude'] as num?)?.toDouble();
        } else {
          try {
            lat ??= (loc as dynamic).latitude as double?;
            lng ??= (loc as dynamic).longitude as double?;
          } catch (_) {}
        }
      }
      waypointNames.add(lat != null && lng != null ? '$lat,$lng' : Uri.encodeComponent('$stopName, CDMX'));
    }
    String googleMapsDirectionsUrl = '';
    if (waypointNames.isNotEmpty) {
      final waypoints = waypointNames.length > 2 ? waypointNames.sublist(1, waypointNames.length - 1).join('|') : '';
      googleMapsDirectionsUrl = 'https://www.google.com/maps/dir/?api=1&origin=${waypointNames.first}'
          '&destination=${waypointNames.last}${waypoints.isNotEmpty ? '&waypoints=$waypoints' : ''}&travelmode=walking';
    }

    final textPrimary = isDark ? Colors.white : OhtliColors.onyx;
    final textSecondary = isDark ? Colors.white70 : OhtliColors.subtleText;
    final surface = isDark ? const Color(0xFF26262B) : OhtliColors.innerCardBg;
    final hairline = isDark ? Colors.white.withOpacity(0.08) : OhtliColors.cardBorder;

    Widget sectionHeader(String eyebrow, String title, {Widget? trailing}) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  eyebrow,
                  style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 1.6, color: OhtliColors.stormyTeal),
                ),
                const SizedBox(height: 4),
                Text(
                  title,
                  style: GoogleFonts.outfit(fontSize: isMobile ? 20 : 24, fontWeight: FontWeight.w700, color: textPrimary, height: 1.15),
                ),
              ],
            ),
          ),
          ?trailing,
        ],
      );
    }

    Widget statTile(IconData icon, String value, String label, Color accent) {
      return Container(
        padding: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 16, vertical: isMobile ? 12 : 14),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: hairline),
        ),
        child: Row(
          children: [
            Container(
              width: isMobile ? 30 : 36,
              height: isMobile ? 30 : 36,
              decoration: BoxDecoration(color: accent.withOpacity(0.14), borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, size: isMobile ? 16 : 18, color: accent),
            ),
            SizedBox(width: isMobile ? 10 : 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.outfit(fontSize: isMobile ? 15 : 17, fontWeight: FontWeight.w700, color: textPrimary),
                  ),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(fontSize: 11, color: textSecondary),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final stats = [
      statTile(Icons.schedule_rounded, fmtMins(timeMins), 'Duración total', OhtliColors.stormyTeal),
      statTile(Icons.payments_outlined, '\$${cost.toStringAsFixed(0)}', 'Costo (MXN)', OhtliColors.cempasuchil),
      statTile(Icons.place_rounded, '${rawStops.length} paradas', '${fmtMins(totalStayMins)} en sitio', OhtliColors.xoconostle),
      statTile(Icons.directions_walk_rounded, '${walkingKm.toStringAsFixed(1)} km', '${fmtMins(totalWalkMins)} caminando', const Color(0xFF3F8F5B)),
    ];

    Widget stopCard(int idx) {
      final stop = rawStops[idx] as Map<String, dynamic>;
      final stopName = (stop['name'] ?? 'Parada ${idx + 1}').toString();
      final arrival = stop['arrival_time']?.toString();
      final departure = stop['departure_time']?.toString();
      final stayMins = (stop['stay_duration_mins'] as num?)?.toInt() ?? 60;
      final stopPrice = (stop['price_mxn'] as num?)?.toDouble() ?? 0.0;
      final photo = _resolveStopPhoto(stop, idx);
      final category = (stop['category'] ?? stop['type'] ?? 'cultural').toString();
      final catIcon = _getStopCategoryIcon(category);
      final catColor = _getStopCategoryColor(category);
      final address = (stop['address'] ?? stop['alcaldia'] ?? 'Ciudad de México').toString();
      final rating = (stop['rating'] as num?)?.toDouble() ?? 4.8;
      final desc = _stopDetailDescription(stop);
      final photoSize = isMobile ? 92.0 : 128.0;
      Widget wrapInfo(Widget c) => isMobile ? c : Expanded(child: c);

      Widget chip(Widget child, Color color) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(20)),
            child: child,
          );

      return Material(
        color: surface,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: () => _openStopPoiModal(stop),
          borderRadius: BorderRadius.circular(18),
          mouseCursor: SystemMouseCursors.click,
          splashColor: OhtliColors.stormyTeal.withOpacity(0.10),
          highlightColor: OhtliColors.stormyTeal.withOpacity(0.05),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: hairline),
            ),
            // En móvil la foto va arriba a todo lo ancho para dar espacio a la descripción
            child: Flex(
              direction: isMobile ? Axis.vertical : Axis.horizontal,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: SizedBox(
                    width: isMobile ? double.infinity : photoSize,
                    height: isMobile ? 150 : photoSize,
                    child: Image.network(
                      photo,
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                      frameBuilder: (context, child, frame, sync) => sync
                          ? child
                          : AnimatedOpacity(opacity: frame == null ? 0 : 1, duration: const Duration(milliseconds: 300), child: child),
                      errorBuilder: (context, error, stackTrace) => Container(
                        color: catColor.withOpacity(0.10),
                        child: Center(child: Icon(catIcon, size: 30, color: catColor.withOpacity(0.6))),
                      ),
                    ),
                  ),
                ),
                SizedBox(width: 14, height: isMobile ? 12 : 0),
                wrapInfo(Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          chip(
                            Row(mainAxisSize: MainAxisSize.min, children: [
                              Icon(catIcon, size: 12, color: catColor),
                              const SizedBox(width: 4),
                              Text(category.toUpperCase(),
                                  style: GoogleFonts.inter(fontSize: 9.5, fontWeight: FontWeight.w800, letterSpacing: 0.6, color: catColor)),
                            ]),
                            catColor,
                          ),
                          chip(
                            Row(mainAxisSize: MainAxisSize.min, children: [
                              const Icon(Icons.star_rounded, size: 12, color: Color(0xFFE0A100)),
                              const SizedBox(width: 3),
                              Text(rating.toStringAsFixed(1),
                                  style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w700, color: const Color(0xFFB07E00))),
                            ]),
                            const Color(0xFFE0A100),
                          ),
                          chip(
                            Row(mainAxisSize: MainAxisSize.min, children: [
                              const Icon(Icons.schedule_rounded, size: 12, color: OhtliColors.cempasuchil),
                              const SizedBox(width: 4),
                              Text(
                                arrival != null ? '$arrival${departure != null ? ' – $departure' : ''} · $stayMins min' : '$stayMins min',
                                style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w700, color: OhtliColors.cempasuchil),
                              ),
                            ]),
                            OhtliColors.cempasuchil,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        stopName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.outfit(fontSize: isMobile ? 16 : 18, fontWeight: FontWeight.w700, color: textPrimary, height: 1.2),
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Icon(Icons.location_on_outlined, size: 13, color: textSecondary),
                          const SizedBox(width: 3),
                          Expanded(
                            child: Text(
                              address,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(fontSize: 11.5, color: textSecondary),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            stopPrice > 0 ? '\$${stopPrice.toStringAsFixed(0)} MXN' : 'Gratis',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: stopPrice > 0 ? textPrimary : const Color(0xFF3F8F5B),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      // Descripción idéntica a la del detalle del lugar
                      Text(
                        desc,
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(fontSize: 12.5, color: textSecondary, height: 1.5),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Ver detalles del lugar',
                            style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w700, color: OhtliColors.stormyTeal),
                          ),
                          const SizedBox(width: 4),
                          const Icon(Icons.arrow_forward_rounded, size: 14, color: OhtliColors.stormyTeal),
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

    Widget walkConnector(int idx) {
      final nextStop = rawStops[idx + 1] as Map<String, dynamic>;
      final nextWalkMins = (nextStop['travel_time_from_prev_mins'] as num?)?.toInt() ?? 10;
      final nextDistKm = (nextStop['travel_distance_from_prev_km'] as num?)?.toDouble() ?? 0.8;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            const Icon(Icons.directions_walk_rounded, size: 15, color: OhtliColors.stormyTeal),
            const SizedBox(width: 6),
            Text(
              '$nextWalkMins min · ${nextDistKm.toStringAsFixed(1)} km a pie',
              style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w600, color: textSecondary),
            ),
          ],
        ),
      );
    }

    final timeline = Column(
      children: List.generate(rawStops.length, (idx) {
        final isLast = idx == rawStops.length - 1;
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 32,
                child: Column(
                  children: [
                    const SizedBox(height: 14),
                    Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: OhtliColors.stormyTeal,
                        shape: BoxShape.circle,
                        border: Border.all(color: isDark ? const Color(0xFF1E1E22) : Colors.white, width: 3),
                        boxShadow: [BoxShadow(color: OhtliColors.stormyTeal.withOpacity(0.35), blurRadius: 8, offset: const Offset(0, 2))],
                      ),
                      child: Center(
                        child: Text('${idx + 1}', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.white)),
                      ),
                    ),
                    if (!isLast)
                      Expanded(
                        child: Container(
                          width: 2,
                          margin: const EdgeInsets.only(top: 4),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [OhtliColors.stormyTeal.withOpacity(0.45), OhtliColors.stormyTeal.withOpacity(0.15)],
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    stopCard(idx),
                    if (!isLast) walkConnector(idx) else const SizedBox(height: 4),
                  ],
                ),
              ),
            ],
          ),
        );
      }),
    );

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (summary.isNotEmpty) ...[
          Text(
            summary,
            style: GoogleFonts.inter(fontSize: isMobile ? 14.5 : 16, color: textPrimary.withOpacity(0.85), height: 1.6),
          ),
          const SizedBox(height: 22),
        ],
        LayoutBuilder(
          builder: (context, c) {
            final cols = c.maxWidth >= 900 ? 4 : 2;
            const gap = 10.0;
            final tileW = (c.maxWidth - gap * (cols - 1)) / cols;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: stats.map((t) => SizedBox(width: tileW, child: t)).toList(),
            );
          },
        ),
        const SizedBox(height: 36),
        sectionHeader(
          'RECORRIDO',
          'Mapa de la ruta',
          trailing: googleMapsDirectionsUrl.isEmpty
              ? null
              : TextButton.icon(
                  onPressed: () => html.window.open(googleMapsDirectionsUrl, '_blank'),
                  icon: const Icon(Icons.open_in_new_rounded, size: 15),
                  label: Text('Abrir en Google Maps', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700)),
                  style: TextButton.styleFrom(
                    foregroundColor: OhtliColors.stormyTeal,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  ),
                ),
        ),
        const SizedBox(height: 14),
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: hairline),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(isDark ? 0.3 : 0.06), blurRadius: 18, offset: const Offset(0, 6))],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: OsrmMapWidget(
              stops: rawStops,
              routeGeometry: (option['osm_route_geometry'] as List<dynamic>?) ??
                  (option['osm_route'] is Map ? (option['osm_route']['coordinates'] as List<dynamic>?) : null),
              height: isMobile ? 260 : 380,
              isDark: isDark,
              onStopSelected: (stop) => _openStopPoiModal(stop),
            ),
          ),
        ),
        const SizedBox(height: 40),
        sectionHeader(
          'ITINERARIO',
          'Cronología de paradas',
          trailing: isMobile
              ? null
              : Text(
                  '${fmtMins(totalStayMins)} de estancia · ${fmtMins(totalWalkMins)} de traslado',
                  style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: textSecondary),
                ),
        ),
        const SizedBox(height: 18),
        timeline,
        const SizedBox(height: 36),
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isSavingTrip ? null : () => _chooseRouteAndCreateTrip(option),
                icon: _isSavingTrip
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                label: Text(
                  _isSavingTrip ? 'Creando viaje...' : 'Elegir esta ruta · \$${cost.toStringAsFixed(0)} MXN',
                  style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: 0.3),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: OhtliColors.stormyTeal,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 18),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                  elevation: 6,
                  shadowColor: OhtliColors.stormyTeal.withOpacity(0.5),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
      ],
    );

    // Ancho de lectura cómodo en pantallas amplias
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1080),
        child: content,
      ),
    );
  }

  Widget _buildMetaPill(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: Colors.white),
          const SizedBox(width: 5),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}



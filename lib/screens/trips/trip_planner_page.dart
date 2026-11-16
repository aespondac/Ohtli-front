// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use, avoid_print

import '../../services/feedback_service.dart';
import '../../services/user_private_data.dart';
import '../../services/saved_places.dart';
import 'dart:async';
import 'dart:convert';
import 'package:uuid/uuid.dart';
import 'package:http/http.dart' as http;
import 'package:web/web.dart' as web;
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
import '../../services/friend_options.dart';
import '../../services/group_trip_service.dart';
import '../../services/manual_plan.dart';
import '../../services/trip_service.dart';
import '../../services/trip_transfers.dart';
import '../../theme/cdmx_photos.dart';
import '../../theme/colors.dart';
import '../../widgets/ohtli_ui.dart';
import '../../widgets/ohtli_service_icon.dart';
import '../../widgets/osrm_map_widget.dart';
import '../../widgets/place_search_field.dart';
import '../../utils/friendly_errors.dart';
import '../../widgets/poi_detail_dialog.dart';
import '../construction_page.dart'; // RouteBackgroundPainter
import '../places/places_page.dart';
import 'trip_viewer_page.dart';
import 'trip_editor_page.dart';
import 'group_trip_page.dart';

enum PlannerStep {
  bifurcation,
  startingPoint,
  companions,
  preferences,
  blackboardProcessing,
  routeTriadCarousel,
}

class TripPlannerPage extends StatefulWidget {
  final Poi? initialOriginPoi;

  /// Empieza directo en el plan hecho a mano (forma de ruta y puntos), sin la bifurcación.
  final bool startManual;

  /// Votación de un plan con IA en grupo: las 3 rutas salen del grupo y el botón vota.
  final String? groupTripId;
  final List<Map<String, dynamic>>? initialGeneratedOptions;
  final String? initialActiveJobId;

  /// Trabajo del que vienen [initialGeneratedOptions] (al abrir un plan listo desde la lista):
  /// sirve para marcarlo como elegido y para la retroalimentación.
  final String? optionsJobId;
  final String? originName;

  const TripPlannerPage({
    super.key,
    this.initialOriginPoi,
    this.startManual = false,
    this.groupTripId,
    this.initialGeneratedOptions,
    this.initialActiveJobId,
    this.optionsJobId,
    this.originName,
  });

  static void open(
    BuildContext context, {
    Poi? initialOriginPoi,
    bool startManual = false,
    List<Map<String, dynamic>>? initialGeneratedOptions,
    String? initialActiveJobId,
    String? optionsJobId,
    String? originName,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => TripPlannerPage(
          initialOriginPoi: initialOriginPoi,
          startManual: startManual,
          initialGeneratedOptions: initialGeneratedOptions,
          initialActiveJobId: initialActiveJobId,
          optionsJobId: optionsJobId,
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
  final TextEditingController _destinationSearchController = TextEditingController();
  // 'origin' o 'destination' cuando la persona reabre un punto ya elegido para corregirlo.
  String? _editingEndpoint;
  final TextEditingController _customMoodController = TextEditingController();
  final TextEditingController _budgetController = TextEditingController(text: '450');
  int _ideaIndex = 0;

  PlannerStep _currentStep = PlannerStep.bifurcation;

  // Plan hecho a mano: pasa por la forma de ruta, con quién y la fecha, y abre el editor.
  bool _manualMode = false;

  // ¿Con quién vas? 'solo', 'amigos' o 'sorpresa' (solo para un mejor amigo mutuo).
  String _companions = 'solo';
  List<FriendOption>? _friendOptions;
  bool _friendsLoading = false;
  final Set<String> _invitedIds = {};
  String? _surpriseTargetId;

  // Plan con IA en grupo: plazos para responder y votar (horas) y, en la votación, el grupo.
  int _respondHours = 6;
  int _voteHours = 6;
  GroupTrip? _group;
  StreamSubscription<GroupTrip?>? _groupSub;
  bool _leftForGroupTrip = false;

  // Form State
  String _selectedOriginName = '';
  Map<String, double>? _selectedOriginCoords;
  List<Map<String, dynamic>> _userSavedAddresses = [];
  // Lugares guardados en "Mis lugares" (máximo 3) como puntos de partida
  List<Poi> _savedPlaces = [];

  double _budgetMxn = 450.0;
  // Cómo usar el presupuesto: 'presupuesto' (entre 80 % y 100 %) o 'ahorro' (lo menos posible).
  String _budgetStrategy = 'presupuesto';
  // Qué limita el plan: el presupuesto por persona o cuántos lugares visitar.
  String _limitBy = 'budget';
  int _maxPlaces = 4;
  // Estilo del día: el texto libre manda; las etiquetas se detectan en él o se eligen.
  final Set<String> _pickedTags = {};
  final Set<String> _dismissedTags = {};
  String _selectedTopology = 'anillo'; // anillo (ida y vuelta) o radio (abierta)
  // Ruta abierta: qué extremos fija la persona (inicio, fin o ambos).
  String _openEnds = 'inicio';
  String _destinationName = '';
  Map<String, double>? _destinationCoords;
  // Medio de traslado para el motor (kPlannerModes). Arranca con la preferencia del perfil.
  String _selectedTransportMode = 'walking';
  bool _transportModeTouched = false;

  /// La persona ya movió el presupuesto: el de su perfil ya no lo reemplaza al cargar.
  bool _budgetTouched = false;
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
    return OhtliChoiceChip(
      label: label,
      selected: isSelected,
      onTap: () => setState(() => _selectedTravelDate = targetDate),
    );
  }

  // Blackboard / SMA State
  String? _activeJobId;
  StreamSubscription<DocumentSnapshot>? _jobSubscription;
  // Estado de fallo del trabajo de IA (error del motor, sin opciones, sin conexión o sin avance)
  String? _jobError;
  Timer? _jobWatchdog;
  DateTime _lastJobUpdateAt = DateTime.now();
  static const Duration _jobStallTimeout = Duration(minutes: 4);
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

  // Seis puntos de partida populares de la CDMX. Si la cuenta tiene direcciones o
  // lugares guardados, éstos ocupan los primeros lugares y se recorta esta lista.
  static const List<Map<String, dynamic>> _popularStartPoints = [
    {
      'name': 'Palacio de Bellas Artes',
      'area': 'Centro Histórico',
      'match': 'bellas artes',
      'coords': {'lat': 19.4352, 'lng': -99.1412},
      'icon': Icons.theater_comedy_rounded,
    },
    {
      'name': 'Museo Soumaya',
      'area': 'Plaza Carso, Polanco',
      'match': 'soumaya',
      'coords': {'lat': 19.4406, 'lng': -99.2047},
      'icon': Icons.museum_rounded,
    },
    {
      'name': 'Zócalo',
      'area': 'Plaza de la Constitución, Centro',
      'match': 'zócalo',
      'coords': {'lat': 19.4326, 'lng': -99.1332},
      'icon': Icons.account_balance_rounded,
    },
    {
      'name': 'Museo Nacional de Antropología',
      'area': 'Bosque de Chapultepec',
      'match': 'antropología',
      'coords': {'lat': 19.4260, 'lng': -99.1863},
      'icon': Icons.account_balance_outlined,
    },
    {
      'name': 'Ángel de la Independencia',
      'area': 'Paseo de la Reforma, Juárez',
      'match': 'ángel de la independencia',
      'coords': {'lat': 19.4270, 'lng': -99.1677},
      'icon': Icons.flag_rounded,
    },
    {
      'name': 'Museo Frida Kahlo',
      'area': 'Casa Azul, Coyoacán',
      'match': 'frida kahlo',
      'coords': {'lat': 19.3551, 'lng': -99.1625},
      'icon': Icons.palette_rounded,
    },
  ];

  /// Etiquetas del estilo del día y las palabras que las delatan en el texto (sin acentos).
  static const Map<String, List<String>> _moodTagKeywords = {
    'Cafés': ['cafe', 'cafeter', 'espresso', 'capuch', 'cafe de olla'],
    'Murales': ['mural', 'rivera', 'orozco', 'siqueiros'],
    'Historia': ['historia', 'histori', 'colonial', 'prehispan', 'centro historico', 'palacio'],
    'Museos': ['museo'],
    'Arquitectura': ['arquitect', 'edificio', 'barragan'],
    'Arte': ['arte', 'galeria', 'exposic', 'artist'],
    'Librerías': ['libreri', 'libro', 'leer', 'lectura'],
    'Cantinas': ['cantina', 'botana'],
    'Mezcal y pulque': ['mezcal', 'pulque', 'pulqueria', 'tequila', 'cerveza', 'trago'],
    'Mercados': ['mercado', 'tianguis'],
    'Antojitos': ['antojit', 'taco', 'torta', 'quesadill', 'tamal', 'garnacha', 'fonda', 'comida', 'comer'],
    'Postres': ['postre', 'pan dulce', 'helado', 'nieve', 'dulce', 'churro'],
    'Naturaleza': ['parque', 'bosque', 'jardin', 'lago', 'naturaleza', 'vivero', 'aire libre', 'verde'],
    'Miradores': ['mirador', 'vista', 'terraza', 'azotea', 'rooftop'],
    'Música en vivo': ['musica', 'concierto', 'jazz', 'mariachi', 'en vivo', 'son jarocho'],
    'Compras': ['compra', 'tienda', 'boutique', 'vinilo', 'diseño', 'artesan'],
    'Vida nocturna': ['noche', 'nocturn', 'bar ', 'bares', 'antro', 'fiesta'],
    'Tranquilo': ['tranquil', 'calma', 'relaj', 'sin prisa', 'desconect', 'pausa'],
    'Fotografía': ['foto', 'instagram'],
    'En familia': ['niño', 'nino', 'familia', 'hijos'],
  };

  static String _fold(String s) {
    const from = 'áéíóúüñÁÉÍÓÚÜÑ';
    const to = 'aeiouunaeiouun';
    final b = StringBuffer();
    for (final ch in s.toLowerCase().split('')) {
      final i = from.indexOf(ch);
      b.write(i >= 0 ? to[i] : ch);
    }
    return b.toString();
  }

  /// Etiquetas que aparecen en lo que escribió la persona.
  Set<String> get _detectedTags {
    final text = ' ${_fold(_customMoodController.text)} ';
    if (text.trim().isEmpty) return {};
    return {
      for (final e in _moodTagKeywords.entries)
        if (e.value.any((k) => text.contains(_fold(k)))) e.key,
    };
  }

  /// Etiquetas activas, en el orden del catálogo: las detectadas (salvo las que se quitaron) y las elegidas.
  List<String> get _activeTags {
    final detected = _detectedTags.difference(_dismissedTags);
    return [for (final t in _moodTagKeywords.keys) if (detected.contains(t) || _pickedTags.contains(t)) t];
  }

  /// Lo que se manda al motor como intención: el texto y, aparte, las etiquetas.
  String get _moodForEngine {
    final text = _customMoodController.text.trim();
    final tags = _activeTags;
    if (text.isEmpty && tags.isEmpty) return 'Conocer lo mejor de la Ciudad de México';
    if (tags.isEmpty) return text;
    if (text.isEmpty) return 'Intereses: ${tags.join(', ')}';
    return '$text\nIntereses: ${tags.join(', ')}';
  }

  @override
  void initState() {
    super.initState();
    _loadUserSavedAddresses();
    SavedPlaces.ensureStarted();
    SavedPlaces.ids.addListener(_loadSavedPlaces);
    _loadSavedPlaces();

    if (widget.initialOriginPoi != null) {
      _selectedOriginName = widget.initialOriginPoi!.name;
      _selectedOriginCoords = {
        'lat': widget.initialOriginPoi!.location.lat,
        'lng': widget.initialOriginPoi!.location.lng,
      };
      _originSearchController.text = _selectedOriginName;
    }

    if (widget.startManual) {
      _manualMode = true;
      _currentStep = PlannerStep.startingPoint;
    }
    if (widget.groupTripId != null) {
      _currentStep = PlannerStep.routeTriadCarousel;
      _groupSub = GroupTripService.watch(widget.groupTripId!).listen(_onGroupUpdate, onError: (_) {});
    }

    if (widget.initialActiveJobId != null && widget.initialActiveJobId!.isNotEmpty) {
      _activeJobId = widget.initialActiveJobId;
      _selectedOriginName = widget.originName ?? 'CDMX';
      _currentStep = PlannerStep.blackboardProcessing;
      _listenToBlackboardJob(widget.initialActiveJobId!);
    } else if (widget.initialGeneratedOptions != null && widget.initialGeneratedOptions!.isNotEmpty) {
      _generatedOptions = widget.initialGeneratedOptions!;
      _activeJobId = widget.optionsJobId;
      _selectedOriginName = widget.originName ?? 'CDMX';
      _currentStep = PlannerStep.routeTriadCarousel;
      _activeCarouselIndex = _generatedOptions.length > 2 ? 1 : 0;
      _reportOptionShown();
    }
  }

  /// Retroalimentación: qué opción generada vio la persona.
  void _reportOptionShown() {
    if (_activeCarouselIndex < 0 || _activeCarouselIndex >= _generatedOptions.length) return;
    FeedbackService.itineraryShown(_activeJobId, _activeCarouselIndex, _generatedOptions[_activeCarouselIndex]);
  }

  void _onGroupUpdate(GroupTrip? g) {
    if (!mounted || g == null) return;
    setState(() {
      _group = g;
      if (_generatedOptions.isEmpty && g.options.isNotEmpty) {
        _generatedOptions = g.options;
        _activeCarouselIndex = g.options.length > 2 ? 1 : 0;
      }
    });
    // Se cerró la votación: al viaje que salió.
    if (g.status == 'created' && g.tripId != null && !_leftForGroupTrip) {
      _leftForGroupTrip = true;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(g.winner != null ? 'Ganó la opción ${g.winner! + 1}. ¡Ya pueden editar el plan!' : '¡El plan quedó listo!',
            style: GoogleFonts.inter()),
        backgroundColor: OhtliColors.stormyTeal,
      ));
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => TripViewerPage(tripId: g.tripId!, authorId: g.hostId)),
      );
    }
  }

  int? get _myVote => _group?.votes[FirebaseAuth.instance.currentUser?.uid];

  /// Texto del botón de una ruta: elegir (solo) o votar (grupo).
  String _chooseLabel(Map<String, dynamic> option, double cost, {bool compact = false}) {
    if (widget.groupTripId != null) {
      final voted = _myVote != null && _myVote == _generatedOptions.indexOf(option);
      if (voted) return compact ? 'Tu voto' : 'Votaste por esta ruta';
      return compact ? 'Votar' : 'Votar por esta ruta';
    }
    if (_isSavingTrip) return compact ? 'Creando…' : 'Creando viaje…';
    return compact ? 'Elegir · \$${cost.toStringAsFixed(0)}' : 'Elegir esta ruta · \$${cost.toStringAsFixed(0)} MXN';
  }

  Future<void> _voteForOption(Map<String, dynamic> option) async {
    final g = _group;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (g == null || uid == null) return;
    void say(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text, style: GoogleFonts.inter())));
    if (g.status != 'voting') {
      say('La votación ya cerró.');
      return;
    }
    if (!g.voters.contains(uid)) {
      say('Votan quienes aceptaron el plan.');
      return;
    }
    final i = _generatedOptions.indexOf(option);
    if (i < 0) return;
    setState(() => _isSavingTrip = true);
    try {
      await GroupTripService.vote(g, i);
      if (mounted) say('Votaste por la opción ${i + 1}. Te avisamos cuando cierre la votación.');
    } catch (e) {
      if (mounted) say(friendlyError(e, fallback: 'No se pudo guardar tu voto.'));
    } finally {
      if (mounted) setState(() => _isSavingTrip = false);
    }
  }

  @override
  void dispose() {
    _groupSub?.cancel();
    _jobSubscription?.cancel();
    _jobWatchdog?.cancel();
    _triadPageController?.dispose();
    _expandCurve.dispose();
    _expandController.dispose();
    _wheelResetTimer?.cancel();
    _hoverTilt.dispose();
    _carouselFocusNode.dispose();
    for (final c in _cardScrollControllers.values) {
      c.dispose();
    }
    SavedPlaces.ids.removeListener(_loadSavedPlaces);
    _originSearchController.dispose();
    _destinationSearchController.dispose();
    _customMoodController.dispose();
    _budgetController.dispose();
    super.dispose();
  }

  Future<void> _loadUserSavedAddresses() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      // Las direcciones viven en el documento privado (users/{uid}/private/account)
      final data = await UserPrivateData.get(user.uid);
      if (data.isNotEmpty) {
        final profile = data['cultural_profile'];
        if (profile is Map && !_transportModeTouched && mounted) {
          setState(() => _selectedTransportMode =
              plannerModeFromPreference(profile['transport_preference']?.toString()));
        }
        // Gasto promedio por salida que estimó en el cuestionario de gustos
        final avgBudget = profile is Map ? profile['avg_budget_mxn'] : null;
        if (avgBudget is num && avgBudget > 0 && !_budgetTouched && mounted) {
          // Al paso del deslizador (150–2000, de 50 en 50)
          final value = (150.0 + ((avgBudget.toDouble() - 150.0) / 50).round() * 50.0).clamp(150.0, 2000.0);
          setState(() {
            _budgetMxn = value;
            _budgetController.text = value.toStringAsFixed(0);
          });
        }
        final list = data['addresses'];
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

  /// Lugares guardados de la cuenta (SavedPlaces, del más reciente al más antiguo) con datos del catálogo.
  Future<void> _loadSavedPlaces() async {
    try {
      final ids = SavedPlaces.ids.value;
      if (ids.isEmpty) {
        if (mounted && _savedPlaces.isNotEmpty) setState(() => _savedPlaces = []);
        return;
      }
      final catalog = await PlacesPage.loadCatalog();
      final byId = {for (final p in catalog) p.poiId: p};
      final places = <Poi>[];
      for (final id in ids) {
        final poi = byId[id];
        if (poi != null && poi.location.isValid) places.add(poi);
        if (places.length == 3) break;
      }
      if (mounted) setState(() => _savedPlaces = places);
    } catch (e) {
      debugPrint('Error cargando lugares guardados: $e');
    }
  }

  /// Tarjeta de punto de partida (dirección, lugar guardado o zona).
  Widget _buildOriginCard({
    required Widget leading,
    required String title,
    String? subtitle,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final card = OhtliSurface(
      selected: selected,
      radius: 16,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      onTap: onTap,
      child: Row(
        children: [
          SizedBox(width: 30, height: 30, child: FittedBox(child: leading)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.outfit(
                    fontSize: 13, height: 1.15, fontWeight: FontWeight.w700, color: OhtliColors.onyx)),
          ),
        ],
      ),
    );
    if (subtitle == null || subtitle.trim().isEmpty) return card;
    return Tooltip(message: subtitle, waitDuration: const Duration(milliseconds: 400), child: card);
  }

  Widget _thumb(String? url, IconData icon, Color color, bool selected) {
    final fallback = OhtliServiceIcon(icon: icon, color: color, size: 44, soft: !selected);
    if (url == null || url.isEmpty) return fallback;
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        width: 44,
        height: 44,
        // Miniatura de 44 px: la foto más pequeña de Wikimedia (antes 1280 px)
        child: Image.network(CdmxPhotos.sized(url, 44, 2), fit: BoxFit.cover, errorBuilder: (_, _, _) => fallback),
      ),
    );
  }

  /// Hasta 6 tarjetas: direcciones guardadas, lugares guardados (máx. 3) y,
  /// para completar, los puntos populares de la CDMX. Con [forDestination] eligen
  /// el punto final de una ruta abierta.
  List<Widget> _startPointCards({bool forDestination = false}) {
    const total = 6;
    final cards = <Widget>[];
    final current = forDestination ? _destinationName : _selectedOriginName;
    void select(String name, double lat, double lng) => setState(() {
          _editingEndpoint = null;
          if (forDestination) {
            _destinationName = name;
            _destinationCoords = {'lat': lat, 'lng': lng};
            _destinationSearchController.text = name;
            return;
          }
          _selectedOriginName = name;
          _selectedOriginCoords = {'lat': lat, 'lng': lng};
          _originSearchController.text = name;
        });

    for (final addr in _userSavedAddresses) {
      if (cards.length == total) break;
      final label = (addr['label'] ?? addr['name'] ?? 'Dirección').toString();
      final addressStr = (addr['address'] ?? '').toString();
      final lat = (addr['lat'] as num?)?.toDouble() ?? 19.4326;
      final lng = (addr['lng'] as num?)?.toDouble() ?? -99.1332;
      final lower = label.toLowerCase();
      final icon = lower.contains('casa') || lower.contains('home')
          ? Icons.home_rounded
          : (lower.contains('trabajo') || lower.contains('oficina') ? Icons.work_rounded : Icons.bookmark_rounded);
      final isSelected = current == label || current == addressStr;
      cards.add(_buildOriginCard(
        leading: OhtliServiceIcon(icon: icon, color: OhtliColors.stormyTeal, size: 44, soft: !isSelected),
        title: label,
        subtitle: addressStr.isEmpty ? 'Tu dirección guardada' : addressStr,
        selected: isSelected,
        onTap: () => select(label, lat, lng),
      ));
    }

    for (final poi in _savedPlaces.take(3)) {
      if (cards.length == total) break;
      final isSelected = current == poi.name;
      cards.add(_buildOriginCard(
        leading: _thumb(poi.imageUrl, poi.categoryIcon, poi.categoryColor, isSelected),
        title: poi.name,
        subtitle: 'Guardado · ${poi.coloniaAlcaldiaDisplay}',
        selected: isSelected,
        onTap: () => select(poi.name, poi.location.lat, poi.location.lng),
      ));
    }

    final taken = {for (final p in _savedPlaces) p.name.toLowerCase()};
    for (final point in _popularStartPoints) {
      if (cards.length == total) break;
      final name = point['name'] as String;
      if (taken.any((t) => t.contains((point['match'] as String)))) continue;
      final coords = point['coords'] as Map<String, double>;
      final isSelected = current == name;
      cards.add(_buildOriginCard(
        leading: OhtliServiceIcon(icon: point['icon'] as IconData, color: OhtliColors.stormyTeal, size: 44, soft: !isSelected),
        title: name,
        subtitle: point['area'] as String,
        selected: isSelected,
        onTap: () => select(name, coords['lat']!, coords['lng']!),
      ));
    }
    return cards;
  }

  /// Puntos de partida en una sola fila: en escritorio caben seis; si hay más, o en móvil,
  /// la fila se desliza de lado en vez de partirse en una cuadrícula descuadrada.
  Widget _buildOriginGrid(bool isMobile, List<Widget> cards) {
    const gap = 10.0;
    const height = 58.0;
    if (!isMobile && cards.length <= 6) {
      return SizedBox(
        height: height,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (int i = 0; i < 6; i++) ...[
              if (i > 0) const SizedBox(width: gap),
              Expanded(child: i < cards.length ? cards[i] : const SizedBox.shrink()),
            ],
          ],
        ),
      );
    }
    return SizedBox(
      height: height,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        physics: const BouncingScrollPhysics(),
        itemCount: cards.length,
        separatorBuilder: (_, _) => const SizedBox(width: gap),
        itemBuilder: (_, i) => SizedBox(width: isMobile ? 196 : 210, child: cards[i]),
      ),
    );
  }


  /// Lo que el motor necesita de la ruta: origen, forma (anillo, radio, fin o elipse, como en
  /// core/topology.py), destino e intención. Si falta el punto final, avisa y devuelve null.
  ({Map<String, double> origin, String originName, String topology, Map<String, double>? destination, String mood})?
      _engineRoute() {
    final coords = (!_fixesOrigin ? _destinationCoords : null) ?? _selectedOriginCoords ?? {'lat': 19.4326, 'lng': -99.1332};
    final bool needsDestination = _selectedTopology == 'radio' && _openEnds != 'inicio';
    if (needsDestination && _destinationCoords == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Elige dónde quieres terminar tu recorrido.', style: GoogleFonts.inter()),
          backgroundColor: OhtliColors.warning,
        ),
      );
      return null;
    }
    final topology = _selectedTopology == 'anillo'
        ? 'anillo'
        : (_openEnds == 'fin' ? 'fin' : (_openEnds == 'ambos' ? 'elipse' : 'radio'));
    final mood = _moodForEngine;
    final originName = !_fixesOrigin && _destinationName.isNotEmpty
        ? _destinationName
        : (_originSearchController.text.trim().isNotEmpty
            ? _originSearchController.text.trim()
            : (widget.originName ?? 'Ciudad de México'));
    return (
      origin: coords,
      originName: originName,
      topology: topology,
      destination: needsDestination ? _destinationCoords : null,
      mood: mood,
    );
  }

  bool get _isAiGroup => !_manualMode && _companions == 'amigos' && _invitedIds.isNotEmpty;

  /// Plan con IA en grupo: se crea la solicitud, se avisa a los invitados y se pasa a la sala
  /// del grupo. Las rutas las genera el motor con los gustos de quienes acepten.
  Future<void> _createAiGroup() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Inicia sesión para planear en grupo.', style: GoogleFonts.inter()), backgroundColor: OhtliColors.warning),
      );
      return;
    }
    final route = _engineRoute();
    final invitees = _invitedFriends;
    if (route == null || invitees.isEmpty) return;
    setState(() => _isSavingTrip = true);
    try {
      final d = _selectedTravelDate;
      const weekdays = ['lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado', 'domingo'];
      const months = ['enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre'];
      final id = await GroupTripService.createAi(
        title: 'Salida del ${weekdays[d.weekday - 1]} ${d.day} de ${months[d.month - 1]}',
        travelDate: d,
        params: {
          'budget': _budgetMxn,
          'origin': route.origin,
          'origin_name': route.originName,
          'destination': route.destination,
          'topology': route.topology,
          'mood_text': route.mood,
          'transport_mode': _selectedTransportMode,
          'budget_strategy': _budgetStrategy,
          'limit_by': _limitBy,
          if (_limitBy == 'places') 'max_places': _maxPlaces,
          'travel_date': d.toIso8601String(),
        },
        invitees: invitees,
        respondWindow: Duration(hours: _groupDeadlines.$1),
        voteWindow: Duration(hours: _groupDeadlines.$2),
      );
      if (!mounted) return;
      setState(() => _isSavingTrip = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          invitees.length == 1
              ? 'Invitamos a ${invitees.first.name}. Las rutas se arman cuando responda.'
              : 'Invitamos a ${invitees.length} amigos. Las rutas se arman cuando respondan.',
          style: GoogleFonts.inter(),
        ),
        backgroundColor: OhtliColors.stormyTeal,
      ));
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => GroupTripPage(groupId: id)));
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSavingTrip = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(friendlyError(e, fallback: 'No pudimos crear el plan en grupo. Intenta de nuevo.'), style: GoogleFonts.inter()),
          backgroundColor: OhtliColors.warning,
        ),
      );
    }
  }

  Future<void> _launchBlackboardJob() async {
    // Volver a generar con opciones en pantalla = no le convenció ninguna
    if (_generatedOptions.isNotEmpty) {
      FeedbackService.itineraryDiscarded(_activeJobId, reason: 'regenerar');
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Por favor inicia sesión para generar tu itinerario.', style: GoogleFonts.inter()),
          backgroundColor: OhtliColors.warning,
        ),
      );
      return;
    }

    final route = _engineRoute();
    if (route == null) return;
    final coords = route.origin;
    final bool needsDestination = route.destination != null;
    final String engineTopology = route.topology;
    final effectiveMood = route.mood;

    setState(() {
      _currentStep = PlannerStep.blackboardProcessing;
      _blackboardProgress = 15;
      _currentAgentName = 'Comparador';
      _jobError = null;
    });

    try {
      final originTitle = route.originName;

      final jobId = await _blackboardService.requestItineraryJob(
        userId: user.uid,
        budget: _budgetMxn,
        origin: coords,
        originName: originTitle,
        topology: engineTopology,
        destination: needsDestination ? _destinationCoords : null,
        moodText: effectiveMood,
        travelDate: _selectedTravelDate,
        transportMode: _selectedTransportMode,
        budgetStrategy: _budgetStrategy,
        limitBy: _limitBy,
        maxPlaces: _limitBy == 'places' ? _maxPlaces : null,
        // Sorpresa para un mejor amigo mutuo: el motor suma sus gustos a los tuyos.
        surpriseTargetId: _companions == 'sorpresa' ? _surpriseTargetId : null,
      );

      _activeJobId = jobId;
      _listenToBlackboardJob(jobId);
    } on ItineraryApiUnavailableException catch (e) {
      // El motor no aceptó la solicitud: se avisa con la opción de reintentar. Nunca se
      // muestra un itinerario que no haya calculado el motor.
      _activeJobId = e.jobId;
      _failJob(ItineraryBlackboardService.apiUnavailableMessage);
    } catch (e) {
      debugPrint('Error solicitando job al Blackboard: $e');
      setState(() {
        _currentStep = PlannerStep.preferences;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(friendlyError(e, fallback: 'No pudimos iniciar el cálculo de tu ruta. Intenta de nuevo.'), style: GoogleFonts.inter()),
            backgroundColor: OhtliColors.warning,
          ),
        );
      }
    }
  }

  void _failJob(String message) {
    _jobWatchdog?.cancel();
    if (!mounted) return;
    setState(() => _jobError = message);
  }

  void _listenToBlackboardJob(String jobId) {
    _jobSubscription?.cancel();
    _jobWatchdog?.cancel();
    _lastJobUpdateAt = DateTime.now();
    if (mounted && _jobError != null) setState(() => _jobError = null);

    // Si el motor deja de reportar avance, avisamos en lugar de girar para siempre
    _jobWatchdog = Timer.periodic(const Duration(seconds: 15), (_) {
      if (_jobError == null && DateTime.now().difference(_lastJobUpdateAt) > _jobStallTimeout) {
        _failJob('El cálculo está tardando más de lo normal. Puedes seguir esperando, reintentar o revisarlo más tarde en Mis Viajes > Planes.');
      }
    });

    try {
      _jobSubscription = _blackboardService.streamJob(jobId).listen(
        (snapshot) {
          if (!snapshot.exists || snapshot.data() == null) return;
          final data = snapshot.data() as Map<String, dynamic>;

          final progress = (data['progress_percent'] as num?)?.toInt() ?? 15;
          final agent = (data['current_agent'] ?? 'Comparador').toString();
          final status = (data['status'] ?? '').toString();

          if (progress != _blackboardProgress || agent.toLowerCase() != _currentAgentName.toLowerCase()) {
            _lastJobUpdateAt = DateTime.now();
          }

          if (status == 'error' || status == 'failed') {
            _jobSubscription?.cancel();
            if (data['error_code'] == 'api_unavailable') {
              _failJob(ItineraryBlackboardService.apiUnavailableMessage);
              return;
            }
            _failJob('No logramos armar tu ruta esta vez. Prueba de nuevo o ajusta tus preferencias (presupuesto, estilo o punto de partida).');
            return;
          }

          if (mounted) {
            setState(() {
              _blackboardProgress = progress;
              _currentAgentName = agent.isEmpty ? 'Comparador' : agent[0].toUpperCase() + agent.substring(1);
              // Si llegó avance después de un aviso por demora, el aviso deja de aplicar
              if (_jobError != null && status != 'completed') _jobError = null;
            });
          }

          if (status == 'completed') {
            final res = data['result'] as Map<String, dynamic>? ?? {};
            final rawOptions = res['options'] as List<dynamic>? ?? [];
            _jobSubscription?.cancel();
            if (rawOptions.isEmpty) {
              _failJob('No encontramos lugares que encajen con estas preferencias. Prueba con otro estilo, un presupuesto mayor o un punto de partida distinto.');
              return;
            }
            _jobWatchdog?.cancel();
            if (mounted) {
              setState(() {
                _jobError = null;
                _generatedOptions = rawOptions.map((e) => Map<String, dynamic>.from(e as Map)).toList();
                _currentStep = PlannerStep.routeTriadCarousel;
                _activeCarouselIndex = _generatedOptions.length > 2 ? 1 : 0;
                _reportOptionShown();
                _triadPageController?.dispose();
                _triadPageController = null;
                _isDetailExpanded = false;
                _expandController.value = 0;
              });
            }
          }
        },
        onError: (Object e) {
          _failJob(friendlyError(e, fallback: 'Perdimos la conexión con el cálculo de tu ruta. Revisa tu internet e intenta de nuevo.'));
        },
      );
    } catch (e) {
      _failJob(friendlyError(e, fallback: 'Perdimos la conexión con el cálculo de tu ruta. Revisa tu internet e intenta de nuevo.'));
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

  // Fichas completas de lugares para que la descripción del itinerario sea exactamente la misma
  // que muestra el detalle del lugar.
  final Map<String, Poi> _poiCache = {};
  final Set<String> _poiRequested = {};
  static const String _apiUrl = String.fromEnvironment('yollotlApiUrl', defaultValue: 'https://api.ohtli.quest');

  String _stopPoiId(Map<String, dynamic> stop) => (stop['poi_id'] ?? stop['id'] ?? '').toString();

  /// Fichas desde el motor (/v1/pois?ids=), con las reseñas, el precio y el horario al día. La base
  /// de Firestore de la app solo tiene los lugares de OSM (sin DENUE, SIC ni mercados) y no recibe
  /// lo que agrega el refresco del catálogo, así que queda como respaldo.
  Future<Map<String, Poi>> _fetchPoisFromEngine(List<String> ids) async {
    final out = <String, Poi>{};
    if (ids.isEmpty) return out;
    try {
      final uri = Uri.parse('$_apiUrl/v1/pois').replace(queryParameters: {'ids': ids.take(200).join(',')});
      final response = await http.get(uri).timeout(const Duration(seconds: 60));
      if (response.statusCode != 200) throw Exception('HTTP ${response.statusCode}');
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      for (final item in ((decoded as Map)['pois'] as List? ?? const [])) {
        final poi = Poi.fromMap(Map<String, dynamic>.from(item as Map));
        if (poi.poiId.isNotEmpty) out[poi.poiId] = poi;
      }
    } catch (e) {
      debugPrint('[TripPlanner] No se pudieron traer lugares del motor: $e');
    }
    return out;
  }

  void _prefetchStopPois(List<dynamic> stops) {
    final ids = <String>[];
    for (final s in stops) {
      if (s is! Map) continue;
      final id = _stopPoiId(Map<String, dynamic>.from(s));
      if (id.isNotEmpty && _poiRequested.add(id)) ids.add(id);
    }
    if (ids.isEmpty) return;
    _fetchPoisFromEngine(ids).then((found) {
      if (!mounted) return;
      if (found.isNotEmpty) setState(() => _poiCache.addAll(found));
      final rest = ids.where((id) => !found.containsKey(id)).toList();
      if (rest.isNotEmpty) _prefetchFromFirestore(rest);
    });
  }

  void _prefetchFromFirestore(List<String> ids) {
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
      'rating': (stop['rating'] as num?)?.toDouble(),
      'price_is_estimate': stop['price_is_estimate'] != false,
      'vibe_tags': stop['vibe_tags'] ?? [],
    };
    return Poi.fromMap(poiMap, poiId);
  }

  /// Misma descripción que "Sobre este lugar" en el detalle del lugar.
  /// Narración del Recomendador para una parada de la alternativa (highlight, historia, consejo).
  static Map<String, String> _stopNarration(Map<String, dynamic> option, Map<String, dynamic> stop) {
    final pid = stop['poi_id']?.toString();
    final idx = (stop['stop_index'] as num?)?.toInt();
    for (final n in (option['stops_narration'] as List?) ?? const []) {
      if (n is! Map) continue;
      if ((pid != null && n['poi_id']?.toString() == pid) || (idx != null && (n['stop_index'] as num?)?.toInt() == idx)) {
        return {
          'highlight': (n['highlight'] ?? '').toString().trim(),
          'story': (n['cultural_story'] ?? '').toString().trim(),
          'tip': (n['curator_tip'] ?? '').toString().trim(),
        };
      }
    }
    return const {};
  }

  String _stopDetailDescription(Map<String, dynamic> stop) {
    final cached = _poiCache[_stopPoiId(stop)];
    return (cached ?? _poiFromStop(stop)).cleanNarrative;
  }

  void _openStopPoiModal(Map<String, dynamic> stop) async {
    final poiId = _stopPoiId(stop);
    Poi? fullPoi = _poiCache[poiId];

    if (fullPoi == null && poiId.isNotEmpty) {
      fullPoi = (await _fetchPoisFromEngine([poiId]))[poiId];
      if (fullPoi != null) _poiCache[poiId] = fullPoi;
    }
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
      surface: 'itinerary',
    );
  }

  Future<void> _chooseRouteAndCreateTrip(Map<String, dynamic> option) async {
    if (widget.groupTripId != null) {
      await _voteForOption(option);
      return;
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Inicia sesión para guardar este plan en tu perfil.', style: GoogleFonts.inter()),
          backgroundColor: OhtliColors.warning,
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
        jobId: _activeJobId,
        optionIndex: _activeCarouselIndex,
        surpriseTargetId: _companions == 'sorpresa' ? _surpriseTarget?.uid : null,
        surpriseTargetName: _companions == 'sorpresa' ? _surpriseTarget?.name : null,
        routeShape: routeShapeOf(_selectedTopology, _openEnds),
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
            content: Text(friendlyError(e, fallback: 'No pudimos guardar este viaje. Intenta de nuevo.'), style: GoogleFonts.inter()),
            backgroundColor: OhtliColors.warning,
          ),
        );
      }
    }
  }

  FriendOption? get _surpriseTarget {
    for (final f in _friendOptions ?? const <FriendOption>[]) {
      if (f.uid == _surpriseTargetId) return f;
    }
    return null;
  }

  List<FriendOption> get _invitedFriends => [
        for (final f in _friendOptions ?? const <FriendOption>[])
          if (_invitedIds.contains(f.uid)) f,
      ];

  Future<void> _loadFriendOptions() async {
    if (_friendOptions != null || _friendsLoading) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => _friendOptions = const []);
      return;
    }
    setState(() => _friendsLoading = true);
    try {
      final list = await loadFriendOptions(user.uid);
      if (mounted) setState(() => _friendOptions = list);
    } catch (e) {
      debugPrint('[Planner] no se cargaron los amigos: $e');
      if (mounted) setState(() => _friendOptions = const []);
    } finally {
      if (mounted) setState(() => _friendsLoading = false);
    }
  }

  /// Plan hecho a mano: crea el viaje con el punto de partida (y el regreso o el punto de
  /// llegada, según la forma de la ruta), la fecha y con quién va, y abre el editor.
  Future<void> _createManualPlan() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Inicia sesión para crear tu plan.', style: GoogleFonts.inter()), backgroundColor: OhtliColors.warning),
      );
      return;
    }
    setState(() => _isSavingTrip = true);
    try {
      final now = DateTime.now();
      final shape = routeShapeOf(_selectedTopology, _openEnds);
      int n = 0;
      final sections = manualPlanSections(
        routeShape: shape,
        originName: _selectedOriginName,
        origin: _selectedOriginCoords,
        destinationName: _destinationName,
        destination: _destinationCoords,
        originPoi: widget.initialOriginPoi,
        newId: (tag) => 'sec_${now.millisecondsSinceEpoch}_${n++}_$tag',
      );
      final title = manualPlanTitle(routeShape: shape, originName: _selectedOriginName, destinationName: _destinationName);
      final surprise = _companions == 'sorpresa' ? _surpriseTarget : null;
      final invitees = _companions == 'amigos' ? _invitedFriends : const <FriendOption>[];
      final groupId = invitees.isNotEmpty ? GroupTripService.newId() : null;
      final poi = widget.initialOriginPoi;
      final cover = (poi != null && poi.name == _selectedOriginName.trim() && poi.imageUrl.isNotEmpty)
          ? poi.imageUrl
          : CdmxPhotos.cover(title.hashCode);
      // Con id propio: sin él, el editor no tiene dónde guardar ("Sin guardar").
      final trip = Trip(
        id: const Uuid().v4(),
        userId: user.uid,
        title: title,
        description: '',
        coverUrl: cover,
        status: 'draft',
        visibility: 'private',
        createdAt: now,
        updatedAt: now,
        travelDate: _selectedTravelDate,
        isSurprise: surprise != null,
        surpriseTargetIds: surprise != null ? [surprise.uid] : const [],
        surpriseTargetNames: surprise != null ? [surprise.name] : const [],
        unlockOnPublish: surprise != null,
        routeShape: shape,
        groupTripId: groupId,
      );
      final service = TripService();
      await service.createTrip(user.uid, trip);
      await service.updateTripContent(user.uid, trip.id, TripContent(sections: sections));
      if (groupId != null) {
        await GroupTripService.createManual(
          id: groupId,
          tripId: trip.id,
          title: title,
          travelDate: _selectedTravelDate,
          invitees: invitees,
        );
      }
      if (!mounted) return;
      setState(() => _isSavingTrip = false);
      if (invitees.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
            invitees.length == 1
                ? 'Invitamos a ${invitees.first.name}: cuando acepte, podrá editar contigo.'
                : 'Invitamos a ${invitees.length} amigos: quien acepte podrá editar contigo.',
            style: GoogleFonts.inter(),
          ),
          backgroundColor: OhtliColors.stormyTeal,
        ));
      }
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => TripEditorPage(trip: trip)),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSavingTrip = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(friendlyError(e, fallback: 'No pudimos crear tu plan. Intenta de nuevo.'), style: GoogleFonts.inter()),
          backgroundColor: OhtliColors.warning,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isMobile = ohtliIsMobileWidth(screenSize.width);
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
              setState(() => _currentStep = PlannerStep.companions);
            } else if (_currentStep == PlannerStep.companions) {
              setState(() => _currentStep = PlannerStep.startingPoint);
            } else if (_currentStep == PlannerStep.startingPoint && !widget.startManual) {
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
                  widget.groupTripId != null
                      ? (_group == null
                          ? 'Votación del grupo'
                          : 'Votación del grupo · votaron ${_group!.voters.where(_group!.votes.containsKey).length} de ${_group!.voters.length}')
                      : _currentStep == PlannerStep.routeTriadCarousel
                      ? '3 multirutas temáticas calculadas por IA'
                      : (_manualMode && _currentStep != PlannerStep.bifurcation
                          ? 'Tu plan, armado por ti'
                          : 'Diseño inteligente de experiencias en CDMX'),
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
              painter: RouteBackgroundPainter(OhtliColors.routeLine),
            ),
          ),
          SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: _currentStep == PlannerStep.routeTriadCarousel
                      ? double.infinity
                      : (_currentStep == PlannerStep.startingPoint ? 1080 : 780),
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
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 300),
                              child: _buildStepContent(isMobile),
                            ),
                          ],
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
      case PlannerStep.companions:
        return _buildCompanionsStep(isMobile);
      case PlannerStep.preferences:
        return _buildPreferencesStep(isMobile);
      case PlannerStep.blackboardProcessing:
        return _buildBlackboardProcessingStep(isMobile);
      case PlannerStep.routeTriadCarousel:
        return _buildRouteTriadCarouselStep(isMobile);
    }
  }

  Widget _buildJobErrorState(bool isMobile) {
    final stalled = _jobError!.startsWith('El cálculo está tardando');
    final offline = _jobError == ItineraryBlackboardService.apiUnavailableMessage;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const SizedBox(height: 30),
        Container(
          width: 84,
          height: 84,
          decoration: BoxDecoration(
            color: (stalled ? OhtliColors.warning : OhtliColors.accent).withOpacity(0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(
            stalled ? Icons.hourglass_top_rounded : (offline ? Icons.cloud_off_rounded : Icons.route_outlined),
            size: 38,
            color: stalled ? OhtliColors.warning : OhtliColors.accent,
          ),
        ),
        const SizedBox(height: 24),
        Text(
          stalled ? 'Esto está tardando' : (offline ? 'Sin conexión con el motor' : 'No pudimos armar tu ruta'),
          textAlign: TextAlign.center,
          style: GoogleFonts.outfit(
            fontSize: isMobile ? 22 : 26,
            fontWeight: FontWeight.w800,
            color: OhtliColors.onyx,
          ),
        ),
        const SizedBox(height: 10),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Text(
            _jobError!,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(fontSize: 13.5, color: OhtliColors.subtleText, height: 1.45),
          ),
        ),
        const SizedBox(height: 28),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 12,
          runSpacing: 12,
          children: [
            OhtliPrimaryButton(
              label: 'Reintentar',
              icon: Icons.refresh_rounded,
              onPressed: _launchBlackboardJob,
            ),
            OhtliSecondaryButton(
              label: 'Ajustar preferencias',
              icon: Icons.tune_rounded,
              onPressed: () {
                _jobSubscription?.cancel();
                _jobWatchdog?.cancel();
                setState(() {
                  _jobError = null;
                  _currentStep = PlannerStep.preferences;
                });
              },
            ),
            if (stalled)
              TextButton(
                onPressed: () {
                  _lastJobUpdateAt = DateTime.now();
                  if (_activeJobId != null) _listenToBlackboardJob(_activeJobId!);
                },
                child: Text('Seguir esperando', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: OhtliColors.subtleText)),
              ),
          ],
        ),
      ],
    );
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
          'Deja que la IA te proponga rutas o arma cada parada por tu cuenta.',
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
          subtitle: 'Te proponemos 3 rutas según tus gustos y presupuesto, con traslados bien calculados.',
          badge: 'RECOMENDADO',
          badgeColor: OhtliColors.stormyTeal,
          icon: Icons.explore_rounded,
          accentColor: OhtliColors.stormyTeal,
          onTap: () {
            setState(() {
              _manualMode = false;
              _currentStep = PlannerStep.startingPoint;
            });
          },
        ),
        const SizedBox(height: 18),

        // Tarjeta 2: Quiero hacerlo por mi cuenta
        _buildBifurcationCard(
          title: 'Quiero hacerlo por mi cuenta',
          subtitle: 'Eliges la forma de la ruta, el inicio y con quién vas; las paradas, fotos y notas las agregas tú en el editor.',
          icon: Icons.edit_note_rounded,
          accentColor: const Color(0xFF6C5CE7),
          onTap: () => setState(() {
            _manualMode = true;
            _currentStep = PlannerStep.startingPoint;
          }),
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
  bool get _fixesOrigin => !(_selectedTopology == 'radio' && _openEnds == 'fin');
  bool get _fixesDestination => _selectedTopology == 'radio' && _openEnds != 'inicio';

  /// Tipo de ruta (ida y vuelta o abierta) y, en la abierta, qué extremos fija la persona.
  Widget _buildRouteShapeSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('TIPO DE RUTA', style: OhtliUi.eyebrow(OhtliColors.subtleText)),
        const SizedBox(height: 12),
        LayoutBuilder(builder: (context, c) {
          final ring = _buildTopologyOption(
            key: 'anillo',
            title: 'Ida y vuelta',
            desc: 'Empiezas y terminas en el mismo punto',
            icon: Icons.loop_rounded,
          );
          final open = _buildTopologyOption(
            key: 'radio',
            title: 'Abierta',
            desc: 'No vuelves al inicio; tú eliges qué puntos fijar',
            icon: Icons.trending_flat_rounded,
          );
          // En pantallas angostas, una debajo de otra para que se lea completa la descripción
          if (c.maxWidth < 520) {
            return Column(children: [ring, const SizedBox(height: 10), open]);
          }
          return Row(children: [Expanded(child: ring), const SizedBox(width: 14), Expanded(child: open)]);
        }),
        if (_selectedTopology == 'radio') ...[
          const SizedBox(height: 18),
          Text('¿QUÉ PUNTOS QUIERES FIJAR?', style: OhtliUi.eyebrow(OhtliColors.subtleText)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final o in const [
                ('inicio', 'Solo el inicio', Icons.trip_origin_rounded),
                ('fin', 'Solo el final', Icons.flag_rounded),
                ('ambos', 'Inicio y final', Icons.route_rounded),
              ])
                OhtliChoiceChip(
                  label: o.$2,
                  icon: o.$3,
                  selected: _openEnds == o.$1,
                  onTap: () => setState(() {
                    _openEnds = o.$1;
                    _editingEndpoint = null;
                  }),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            _openEnds == 'inicio'
                ? 'Empiezas en tu punto de partida y terminas en la última parada.'
                : (_openEnds == 'fin'
                    ? 'Empiezas en la primera parada y terminas en el punto que elijas.'
                    : 'Empiezas en tu punto de partida y terminas en el punto que elijas.'),
            style: OhtliUi.body(size: 12.5),
          ),
        ],
      ],
    );
  }

  /// Inicio y final del recorrido. Cada punto se puede escribir (con sugerencias) o
  /// elegir entre las tarjetas; con ambos, una línea lateral une el punto 1 con el 2.
  Widget _buildEndpointsSection(bool isMobile) {
    final both = _fixesOrigin && _fixesDestination;
    final hasSaved = _userSavedAddresses.isNotEmpty || _savedPlaces.isNotEmpty;

    Widget marker(IconData icon, bool done) => Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: done ? OhtliColors.stormyTeal : OhtliColors.cardBg,
            shape: BoxShape.circle,
            border: Border.all(color: OhtliColors.stormyTeal, width: 2),
          ),
          child: Icon(icon, size: 15, color: done ? Colors.white : OhtliColors.stormyTeal),
        );

    Widget rail({required Widget mark, bool lineBelow = false}) => SizedBox(
          width: 30,
          child: Column(
            children: [
              mark,
              if (lineBelow)
                Expanded(
                  child: Container(
                    width: 2,
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [OhtliColors.stormyTeal, OhtliColors.stormyTeal.withValues(alpha: 0.45)],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );

    final originDone = _selectedOriginCoords != null && _selectedOriginName.trim().isNotEmpty;
    final destDone = _destinationCoords != null;
    // Solo un punto muestra buscador y opciones: el que se corrige o el primero pendiente.
    final String? active = _editingEndpoint ??
        (_fixesOrigin && !originDone ? 'origin' : (_fixesDestination && !destDone ? 'destination' : null));

    Widget chosen(String name, String key) => Align(
          alignment: Alignment.centerLeft,
          child: OhtliSurface(
            radius: 30,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            onTap: () => setState(() => _editingEndpoint = key),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.place_rounded, size: 18, color: OhtliColors.stormyTeal),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: OhtliColors.onyx)),
                ),
                const SizedBox(width: 14),
                Text('Cambiar',
                    style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w700, color: OhtliColors.accentText)),
              ],
            ),
          ),
        );

    Widget point({
      required String key,
      required String title,
      required IconData icon,
      required bool done,
      required String doneName,
      required String pendingHint,
      required bool lineBelow,
      required TextEditingController controller,
      required String hint,
      required void Function(String name, double lat, double lng) onSelected,
      required VoidCallback onCleared,
      required List<Widget> Function() cards,
    }) {
      final isActive = active == key;
      return IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            rail(mark: marker(icon, done), lineBelow: lineBelow),
            const SizedBox(width: 14),
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(bottom: lineBelow ? 28 : 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 7, bottom: 12),
                      child: Text(title, style: OhtliUi.eyebrow(OhtliColors.subtleText)),
                    ),
                    if (!isActive)
                      done ? chosen(doneName, key) : Text(pendingHint, style: OhtliUi.body(size: 12.5))
                    else ...[
                      PlaceSearchField(
                        controller: controller,
                        hintText: hint,
                        onSelected: onSelected,
                        onCleared: onCleared,
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                                hasSaved ? 'O elige uno de tus puntos o de los más populares' : 'O elige un punto popular',
                                style: OhtliUi.body(size: 12.5)),
                          ),
                          // Al corregir un punto ya elegido, "Listo" cierra las opciones sin cambiarlo.
                          if (done && _editingEndpoint == key)
                            TextButton.icon(
                              onPressed: () => setState(() => _editingEndpoint = null),
                              icon: const Icon(Icons.check_rounded, size: 16),
                              label: const Text('Listo'),
                              style: TextButton.styleFrom(
                                foregroundColor: OhtliColors.accentText,
                                backgroundColor: OhtliColors.stormyTeal.withValues(alpha: 0.10),
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                shape: const StadiumBorder(),
                                textStyle: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      _buildOriginGrid(isMobile, cards()),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_fixesOrigin)
          point(
            key: 'origin',
            title: both ? '1 · ¿DÓNDE EMPIEZAS?' : '¿DÓNDE EMPIEZAS?',
            icon: Icons.trip_origin_rounded,
            done: originDone,
            doneName: _selectedOriginName,
            pendingHint: 'Elige dónde empiezas.',
            lineBelow: both,
            controller: _originSearchController,
            hint: 'Escribe dónde empiezas: dirección, colonia o lugar…',
            onSelected: (name, lat, lng) => setState(() {
              _selectedOriginName = name;
              _selectedOriginCoords = {'lat': lat, 'lng': lng};
              _editingEndpoint = null;
            }),
            onCleared: () => setState(() {
              _selectedOriginName = '';
              _selectedOriginCoords = null;
            }),
            cards: () => _startPointCards(),
          ),
        if (_fixesDestination)
          point(
            key: 'destination',
            title: both ? '2 · ¿DÓNDE QUIERES TERMINAR?' : '¿DÓNDE QUIERES TERMINAR?',
            icon: Icons.flag_rounded,
            done: destDone,
            doneName: _destinationName,
            pendingHint: 'Cuando elijas el inicio, aquí eliges la llegada.',
            lineBelow: false,
            controller: _destinationSearchController,
            hint: 'Escribe dónde terminas: dirección, colonia o lugar…',
            onSelected: (name, lat, lng) => setState(() {
              _destinationName = name;
              _destinationCoords = {'lat': lat, 'lng': lng};
              _editingEndpoint = null;
            }),
            onCleared: () => setState(() {
              _destinationName = '';
              _destinationCoords = null;
            }),
            cards: () => _startPointCards(forDestination: true),
          ),
      ],
    );
  }

  Widget _buildStartingPointStep(bool isMobile) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('¿Desde dónde inicia tu recorrido?', style: OhtliUi.title(size: isMobile ? 24 : 30)),
        const SizedBox(height: 6),
        Text('Elige si vuelves al inicio o terminas en otro lugar, y los puntos de tu recorrido en la Ciudad de México.',
            style: OhtliUi.body(size: 14)),
        const SizedBox(height: 24),
        _buildRouteShapeSection(),
        const SizedBox(height: 28),

        _buildEndpointsSection(isMobile),
        const SizedBox(height: 28),

        // Medio de traslado entre paradas
        Text('¿CÓMO TE MUEVES?', style: OhtliUi.eyebrow(OhtliColors.subtleText)),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final m in kPlannerModes)
              OhtliChoiceChip(
                label: m.label,
                icon: m.icon,
                selected: _selectedTransportMode == m.id,
                onTap: () => setState(() {
                  _selectedTransportMode = m.id;
                  _transportModeTouched = true;
                }),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Text(_transportModeHint(_selectedTransportMode), style: OhtliUi.body(size: 12.5)),

        const SizedBox(height: 36),

        // Botón Continuar
        Align(
          alignment: Alignment.centerRight,
          child: OhtliPrimaryButton(
            label: 'Continuar',
            icon: Icons.arrow_forward_rounded,
            onPressed: (_fixesOrigin && _selectedOriginName.trim().isEmpty) ||
                    (_fixesDestination && _destinationCoords == null)
                ? null
                : () => setState(() => _currentStep = PlannerStep.companions),
          ),
        ),
      ],
    );
  }

  // ==========================================
  // PASO 1.5: ¿CON QUIÉN VAS?
  // ==========================================
  Widget _buildCompanionOption({
    required String key,
    required IconData icon,
    required String title,
    required String desc,
    bool enabled = true,
    String? badge,
  }) {
    final selected = _companions == key;
    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: OhtliSurface(
        radius: 20,
        padding: const EdgeInsets.all(16),
        selected: selected,
        accent: selected ? OhtliColors.stormyTeal : null,
        onTap: enabled
            ? () {
                setState(() => _companions = key);
                if (key != 'solo') _loadFriendOptions();
              }
            : null,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            OhtliServiceIcon(icon: icon, color: selected ? OhtliColors.stormyTeal : OhtliColors.subtleText, size: 42, soft: true),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(title, style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w700, color: OhtliColors.onyx)),
                      ),
                      if (badge != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: OhtliColors.accent.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(badge, style: GoogleFonts.inter(fontSize: 9.5, fontWeight: FontWeight.w800, letterSpacing: 0.6, color: OhtliColors.accent)),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(desc, style: OhtliUi.body(size: 12.5)),
                ],
              ),
            ),
            if (selected) const Icon(Icons.check_circle_rounded, color: OhtliColors.stormyTeal, size: 22),
          ],
        ),
      ),
    );
  }

  /// Un amigo como burbuja: su foto (o iniciales) y su nombre; al elegirlo se marca con un
  /// aro y una palomita. Los mejores amigos llevan su estrella, como en Amigos.
  Widget _buildFriendBubble(FriendOption f, {required bool selected, required VoidCallback onTap}) {
    const double size = 62;
    final first = f.name.split(' ').firstWhere((w) => w.isNotEmpty, orElse: () => f.name);
    return Semantics(
      button: true,
      selected: selected,
      label: f.isMutualCloseFriend ? '${f.name}, mejor amigo' : f.name,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        // Solo el aro marca la selección: sin la mancha del foco ni del toque.
        focusColor: Colors.transparent,
        highlightColor: Colors.transparent,
        hoverColor: Colors.transparent,
        splashColor: OhtliColors.stormyTeal.withValues(alpha: 0.12),
        child: SizedBox(
          width: 78,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: size + 8,
                height: size + 8,
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.center,
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      width: size + 8,
                      height: size + 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: selected ? OhtliColors.stormyTeal : Colors.transparent, width: 3),
                      ),
                    ),
                    CircleAvatar(
                      radius: size / 2,
                      backgroundColor: OhtliColors.stormyTeal.withValues(alpha: 0.15),
                      backgroundImage: f.photoUrl != null ? NetworkImage(f.photoUrl!) : null,
                      child: f.photoUrl == null
                          ? Text(f.initials, style: GoogleFonts.outfit(fontSize: 19, fontWeight: FontWeight.w700, color: OhtliColors.stormyTeal))
                          : null,
                    ),
                    if (f.isMutualCloseFriend)
                      Positioned(
                        top: 0,
                        right: 0,
                        child: Container(
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            color: OhtliColors.accentFill,
                            shape: BoxShape.circle,
                            border: Border.all(color: OhtliColors.cardBg, width: 2.5),
                          ),
                          child: const Icon(Icons.star_rounded, size: 12, color: Colors.white),
                        ),
                      ),
                    if (selected)
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            color: OhtliColors.stormyTeal,
                            shape: BoxShape.circle,
                            border: Border.all(color: OhtliColors.cardBg, width: 2.5),
                          ),
                          child: const Icon(Icons.check_rounded, size: 14, color: Colors.white),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Text(
                first,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 12.5,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? OhtliColors.onyx : OhtliColors.subtleText,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFriendPicker() {
    final surprise = _companions == 'sorpresa';
    final all = _friendOptions;
    if (_friendsLoading || all == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator(color: OhtliColors.stormyTeal)),
      );
    }
    final list = surprise ? all.where((f) => f.isMutualCloseFriend).toList() : all;
    if (list.isEmpty) {
      return OhtliSurface(
        radius: 18,
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(surprise ? Icons.star_outline_rounded : Icons.people_outline_rounded, color: OhtliColors.subtleText),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                surprise
                    ? 'Las sorpresas son solo para mejores amigos mutuos (los dos se tienen como mejor amigo en Amigos).'
                    : 'Aún no tienes amigos en Ohtli. Agrégalos desde Amigos para planear juntos.',
                style: OhtliUi.body(size: 13),
              ),
            ),
          ],
        ),
      );
    }
    return Wrap(
      spacing: 10,
      runSpacing: 14,
      children: [
          for (final f in list)
            _buildFriendBubble(
              f,
              selected: surprise ? _surpriseTargetId == f.uid : _invitedIds.contains(f.uid),
              onTap: () => setState(() {
                if (surprise) {
                  _surpriseTargetId = _surpriseTargetId == f.uid ? null : f.uid;
                } else if (!_invitedIds.remove(f.uid)) {
                  _invitedIds.add(f.uid);
                }
              }),
            ),
      ],
    );
  }

  // --- Plazos del plan con IA en grupo ---
  // Responder y votar tienen que terminar antes del día del plan (a más tardar a las 8:00),
  // si no el plan ocurriría antes de que el grupo vote.
  static const List<int> _deadlineChoices = [1, 6, 24];

  DateTime get _groupCloseLimit => DateTime(_selectedTravelDate.year, _selectedTravelDate.month, _selectedTravelDate.day, 8);

  int get _groupHoursAvailable => _groupCloseLimit.difference(DateTime.now()).inMinutes ~/ 60;

  /// Plazos que sí caben antes del día del plan: si no caben los elegidos, se acorta primero el mayor.
  (int, int) get _groupDeadlines {
    var r = _respondHours;
    var v = _voteHours;
    final avail = _groupHoursAvailable;
    int smaller(int h) => _deadlineChoices.lastWhere((c) => c < h, orElse: () => h);
    while (r + v > avail) {
      final nr = r >= v ? smaller(r) : r;
      final nv = r >= v ? v : smaller(v);
      if (nr == r && nv == v) {
        // El mayor ya es el mínimo: se acorta el otro
        final r2 = smaller(r), v2 = smaller(v);
        if (r2 == r && v2 == v) break;
        r = r2;
        v = v2;
      } else {
        r = nr;
        v = nv;
      }
    }
    return (r, v);
  }

  bool get _groupDeadlinesFit {
    final (r, v) = _groupDeadlines;
    return r + v <= _groupHoursAvailable;
  }

  String _shortWhen(DateTime d) {
    const days = ['lun', 'mar', 'mié', 'jue', 'vie', 'sáb', 'dom'];
    final hh = '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    return '${days[d.weekday - 1]} ${d.day}, $hh';
  }

  Widget _buildDeadlineRow(String label, int hours, int other, ValueChanged<int> onPick) {
    final avail = _groupHoursAvailable;
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      runSpacing: 8,
      children: [
        SizedBox(width: 118, child: Text(label, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: OhtliColors.onyx))),
        for (final o in const [(1, '1 hora'), (6, '6 horas'), (24, '1 día')])
          Opacity(
            // Opción que no cabe antes del día del plan
            opacity: o.$1 + other <= avail ? 1 : 0.4,
            child: OhtliChoiceChip(
              label: o.$2,
              selected: hours == o.$1,
              onTap: () {
                if (o.$1 + other <= avail) onPick(o.$1);
              },
            ),
          ),
      ],
    );
  }

  /// Plazos del plan en grupo, debajo de la fecha: primero el día del plan y luego cuánto tienen
  /// para responder y votar, siempre antes de ese día.
  Widget _buildGroupDeadlines() {
    final (r, v) = _groupDeadlines;
    final fits = _groupDeadlinesFit;
    final now = DateTime.now();
    final respondBy = now.add(Duration(hours: r));
    final voteBy = respondBy.add(Duration(hours: v));
    return OhtliSurface(
      radius: 22,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildDeadlineRow('Para responder', r, v, (h) => setState(() {
                _respondHours = h;
                _voteHours = v;
              })),
          const SizedBox(height: 10),
          _buildDeadlineRow('Para votar', v, r, (h) => setState(() {
                _voteHours = h;
                _respondHours = r;
              })),
          const SizedBox(height: 12),
          fits
              ? _plannerNote(Icons.event_available_rounded,
                  'Responden hasta el ${_shortWhen(respondBy)} y votan hasta el ${_shortWhen(voteBy)}, antes del día del plan. '
                  'Si todos responden o votan antes, no esperamos al plazo.')
              : _plannerNote(Icons.warning_amber_rounded,
                  'No da tiempo de responder y votar antes del día del plan. Elige una fecha más adelante.'),
        ],
      ),
    );
  }

  Widget _buildCompanionsStep(bool isMobile) {
    final surprise = _companions == 'sorpresa';
    final friends = _companions == 'amigos';
    const groupAvailable = true;
    final options = [
      _buildCompanionOption(key: 'solo', icon: Icons.person_rounded, title: 'Solo yo', desc: 'El plan es para ti.'),
      _buildCompanionOption(
        key: 'amigos',
        icon: Icons.groups_rounded,
        title: 'Con amigos',
        desc: _manualMode
            ? 'Los invitas y quien acepte edita el plan contigo.'
            : 'Cada quien acepta y suma su intención; las rutas salen de los gustos del grupo y votan.',
        enabled: groupAvailable,
      ),
      _buildCompanionOption(
        key: 'sorpresa',
        icon: Icons.card_giftcard_rounded,
        title: 'Sorpresa',
        desc: 'Para una ocasión especial con un mejor amigo: una cita, un cumpleaños…',
      ),
    ];
    final ready = _companions == 'solo' || (friends && _invitedIds.isNotEmpty) || (surprise && _surpriseTargetId != null);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('¿Con quién vas?', style: OhtliUi.title(size: isMobile ? 24 : 30)),
        const SizedBox(height: 6),
        Text(
          _manualMode
              ? 'Planea solo, con amigos que editen contigo o prepara una sorpresa.'
              : 'Las rutas se arman con tus gustos; en una sorpresa, también con los de tu mejor amigo.',
          style: OhtliUi.body(size: 14),
        ),
        const SizedBox(height: 24),
        for (final o in options) ...[o, const SizedBox(height: 12)],
        if (friends || surprise) ...[
          const SizedBox(height: 12),
          Text(surprise ? '¿PARA QUIÉN ES LA SORPRESA?' : '¿A QUIÉN INVITAS?', style: OhtliUi.eyebrow(OhtliColors.subtleText)),
          const SizedBox(height: 12),
          _buildFriendPicker(),
          if (surprise) ...[
            const SizedBox(height: 10),
            Text(
              'Es una sorpresa: no le avisamos hasta que la publiques. Como son mejores amigos, el plan puede tomar en cuenta sus gustos.',
              style: OhtliUi.body(size: 12.5),
            ),
          ],
        ],
        const SizedBox(height: 32),
        Align(
          alignment: Alignment.centerRight,
          child: OhtliPrimaryButton(
            label: 'Continuar',
            icon: Icons.arrow_forward_rounded,
            onPressed: ready ? () => setState(() => _currentStep = PlannerStep.preferences) : null,
          ),
        ),
      ],
    );
  }

  // ==========================================
  // PASO 2: PREFERENCIAS & PRESUPUESTO
  // ==========================================
  /// Fecha del viaje con atajos (hoy, mañana, fin de semana, en una semana).
  Widget _buildTravelDateSurface() {
    return OhtliSurface(
          radius: 22,
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const OhtliServiceIcon(icon: Icons.calendar_today_rounded, color: OhtliColors.stormyTeal, size: 46, soft: true),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_formatDate(_selectedTravelDate),
                            style: GoogleFonts.outfit(fontSize: 17, fontWeight: FontWeight.w700, color: OhtliColors.onyx)),
                        const SizedBox(height: 2),
                        Text('Fecha programada para el itinerario', style: OhtliUi.body(size: 12.5)),
                      ],
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _pickTravelDate,
                    icon: const Icon(Icons.edit_calendar_rounded, size: 16),
                    label: const Text('Cambiar'),
                    style: TextButton.styleFrom(
                      foregroundColor: OhtliColors.accentText,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      shape: const StadiumBorder(),
                      textStyle: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _buildQuickDateChip('Hoy', DateTime.now()),
                  _buildQuickDateChip('Mañana', DateTime.now().add(const Duration(days: 1))),
                  _buildQuickDateChip('Este fin de semana', _getNextWeekend()),
                  _buildQuickDateChip('En 1 semana', DateTime.now().add(const Duration(days: 7))),
                ],
              ),
            ],
          ),
        );
  }

  /// Plan hecho a mano: solo la fecha; las paradas se agregan en el editor.
  Widget _buildManualDateStep(bool isMobile) {
    final group = _companions == 'amigos' && _invitedIds.isNotEmpty;
    final surprise = _companions == 'sorpresa' ? _surpriseTarget : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('¿Cuándo es tu viaje?', style: OhtliUi.title(size: isMobile ? 24 : 30)),
        const SizedBox(height: 6),
        Text(
          surprise != null
              ? 'Elige la fecha de la sorpresa para ${surprise.name}. Las paradas las agregas tú en el editor.'
              : (group
                  ? 'Elige la fecha. Al crear el plan invitamos a tus amigos; quien acepte podrá editarlo contigo.'
                  : 'Elige la fecha. Las paradas, fotos y notas las agregas tú en el editor.'),
          style: OhtliUi.body(size: 14),
        ),
        const SizedBox(height: 28),
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text('FECHA DEL VIAJE', style: OhtliUi.eyebrow(OhtliColors.subtleText)),
        ),
        _buildTravelDateSurface(),
        const SizedBox(height: 36),
        Align(
          alignment: Alignment.centerRight,
          child: OhtliPrimaryButton(
            label: group ? 'Crear plan e invitar' : 'Crear mi plan',
            icon: Icons.edit_note_rounded,
            highlight: true,
            loading: _isSavingTrip,
            onPressed: _isSavingTrip ? null : _createManualPlan,
          ),
        ),
      ],
    );
  }

  Widget _buildPreferencesStep(bool isMobile) {
    if (_manualMode) return _buildManualDateStep(isMobile);
    Widget label(String text) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(text, style: OhtliUi.eyebrow(OhtliColors.subtleText)),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('¿Cuál es la vibra y el presupuesto de tu día?', style: OhtliUi.title(size: isMobile ? 24 : 30)),
        const SizedBox(height: 6),
        Text('Cuéntanos qué te late hoy y cuánto quieres gastar. Con eso te proponemos varias rutas para elegir.',
            style: OhtliUi.body(size: 14)),
        const SizedBox(height: 28),

        // Fecha del viaje
        label('FECHA DEL VIAJE'),
        _buildTravelDateSurface(),
        if (_isAiGroup) ...[
          const SizedBox(height: 18),
          label('PLAZOS DEL GRUPO'),
          _buildGroupDeadlines(),
        ],
        const SizedBox(height: 28),

        // Qué limita el plan: presupuesto o número de lugares
        label('¿QUÉ LIMITA TU PLAN?'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OhtliChoiceChip(
              label: 'Presupuesto',
              icon: Icons.payments_outlined,
              selected: _limitBy == 'budget',
              onTap: () => setState(() => _limitBy = 'budget'),
            ),
            OhtliChoiceChip(
              label: 'Número de lugares',
              icon: Icons.place_outlined,
              selected: _limitBy == 'places',
              onTap: () => setState(() => _limitBy = 'places'),
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (_limitBy == 'budget') ...[
          label('PRESUPUESTO POR PERSONA'),
        OhtliSurface(
          radius: 22,
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('¿Cuánto quieres gastar?',
                            style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w700, color: OhtliColors.onyx)),
                        const SizedBox(height: 2),
                        Text('Escribe el monto o usa la barra', style: OhtliUi.body(size: 12.5)),
                      ],
                    ),
                  ),
                  // Monto libre: cualquier cantidad, sincronizada con la barra
                  Container(
                    width: 150,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: OhtliColors.innerCardBg,
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(color: OhtliColors.cardBorder),
                    ),
                    child: Row(
                      children: [
                        Text('\$', style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.w800, color: OhtliColors.accentText)),
                        const SizedBox(width: 2),
                        Expanded(
                          child: TextField(
                            controller: _budgetController,
                            keyboardType: TextInputType.number,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
                            cursorColor: OhtliColors.stormyTeal,
                            style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.w800, color: OhtliColors.accentText),
                            decoration: const InputDecoration(border: InputBorder.none, isDense: true, contentPadding: EdgeInsets.symmetric(vertical: 12)),
                            onChanged: (v) {
                              final value = double.tryParse(v);
                              if (value != null && value > 0) {
                                setState(() {
                                  _budgetMxn = value;
                                  _budgetTouched = true;
                                });
                              }
                            },
                          ),
                        ),
                        Text('MXN', style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w700, color: OhtliColors.subtleText)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: OhtliColors.stormyTeal,
                  inactiveTrackColor: OhtliColors.stormyTeal.withValues(alpha: 0.15),
                  thumbColor: OhtliColors.stormyTeal,
                  overlayColor: OhtliColors.stormyTeal.withValues(alpha: 0.12),
                  trackHeight: 5,
                ),
                child: Slider(
                  value: _budgetMxn.clamp(150.0, 2000.0),
                  min: 150.0,
                  max: 2000.0,
                  divisions: 37,
                  onChanged: (val) => setState(() {
                    _budgetMxn = val;
                    _budgetTouched = true;
                    _budgetController.text = val.toStringAsFixed(0);
                  }),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Casual · \$150', style: OhtliUi.body(size: 12)),
                  Text('Serio · \$2,000', style: OhtliUi.body(size: 12)),
                ],
              ),
              const SizedBox(height: 10),
              // Modo ahorro: desmarcado, el plan aprovecha entre 80 % y 100 % del presupuesto.
              Semantics(
                checked: _budgetStrategy == 'ahorro',
                label: 'Modo ahorro',
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => setState(() => _budgetStrategy = _budgetStrategy == 'ahorro' ? 'presupuesto' : 'ahorro'),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 22,
                          height: 22,
                          child: Checkbox(
                            value: _budgetStrategy == 'ahorro',
                            onChanged: (v) => setState(() => _budgetStrategy = (v ?? false) ? 'ahorro' : 'presupuesto'),
                            activeColor: OhtliColors.stormyTeal,
                            side: BorderSide(color: OhtliColors.onyx.withValues(alpha: 0.45), width: 1.4),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Modo ahorro',
                                  style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700, color: OhtliColors.onyx)),
                              const SizedBox(height: 2),
                              Text(
                                _budgetStrategy == 'ahorro'
                                    ? 'Priorizamos lugares gratuitos y económicos sin sacrificar lo que más te interesa.'
                                    : 'Sin marcar, el plan aprovecha entre el 80 % y el 100 % de tu presupuesto, si es posible.',
                                style: OhtliUi.body(size: 12),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        ] else
          _buildPlacesLimitSurface(),
        const SizedBox(height: 10),
        _plannerNote(Icons.traffic_outlined, 'Las rutas consideran el tráfico del día de tu visita.'),
        const SizedBox(height: 28),

        // Estilo del día: el texto manda; las etiquetas se suman solas al detectarse o al elegirse
        label('ESTILO DEL DÍA'),
        _buildMoodComposer(isMobile),
        const SizedBox(height: 28),

        // Lanzar generación con IA
        Align(
          alignment: Alignment.centerRight,
          child: OhtliPrimaryButton(
            label: _isAiGroup ? 'Invitar y esperar respuestas' : 'Calcular opciones de viaje',
            icon: _isAiGroup ? Icons.groups_rounded : Icons.auto_awesome_rounded,
            highlight: true,
            loading: _isAiGroup && _isSavingTrip,
            onPressed: _isAiGroup ? (_isSavingTrip || !_groupDeadlinesFit ? null : _createAiGroup) : _launchBlackboardJob,
          ),
        ),
      ],
    );
  }

  Widget _plannerNote(IconData icon, String text) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: OhtliColors.subtleText),
          const SizedBox(width: 6),
          Expanded(child: Text(text, style: OhtliUi.body(size: 12))),
        ],
      );

  Widget _buildPlacesLimitSurface() {
    Widget stepButton(IconData icon, VoidCallback? onTap, String semantics) => IconButton.filledTonal(
          onPressed: onTap,
          tooltip: semantics,
          icon: Icon(icon, size: 20),
          style: IconButton.styleFrom(
            backgroundColor: OhtliColors.stormyTeal.withValues(alpha: 0.10),
            foregroundColor: OhtliColors.accentText,
          ),
        );
    return OhtliSurface(
      radius: 22,
      padding: const EdgeInsets.fromLTRB(20, 16, 14, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('¿Cuántos lugares quieres visitar?',
                        style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w700, color: OhtliColors.onyx)),
                    const SizedBox(height: 2),
                    Text('Sin tope de gasto; el costo estimado se muestra en cada opción.', style: OhtliUi.body(size: 12.5)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              stepButton(Icons.remove_rounded, _maxPlaces > 2 ? () => setState(() => _maxPlaces--) : null, 'Menos lugares'),
              SizedBox(
                width: 40,
                child: Text('$_maxPlaces',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.outfit(fontSize: 24, fontWeight: FontWeight.w800, color: OhtliColors.accentText)),
              ),
              stepButton(Icons.add_rounded, _maxPlaces < 8 ? () => setState(() => _maxPlaces++) : null, 'Más lugares'),
            ],
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            child: _maxPlaces > 4
                ? Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: _plannerNote(Icons.info_outline_rounded, 'Más de 4 lugares puede restar precisión a la recomendación.'),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }

  /// Estilo del día: un solo campo para escribir la idea; debajo, las etiquetas que se
  /// detectan en el texto (o que se eligen) y sugerencias en una fila que se desliza.
  Widget _buildMoodComposer(bool isMobile) {
    final active = _activeTags;
    final suggestions = [for (final t in _moodTagKeywords.keys) if (!active.contains(t)) t];
    return OhtliSurface(
      radius: 22,
      padding: const EdgeInsets.fromLTRB(18, 14, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _customMoodController,
            minLines: isMobile ? 3 : 2,
            maxLines: 6,
            style: GoogleFonts.inter(fontSize: 15, color: OhtliColors.onyx, height: 1.5),
            cursorColor: OhtliColors.stormyTeal,
            decoration: InputDecoration(
              hintText: 'Cuéntanos tu día ideal: qué quieres ver, comer o sentir…',
              hintStyle: GoogleFonts.inter(fontSize: 14.5, color: OhtliColors.subtleText),
              border: InputBorder.none,
              isDense: true,
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  active.isEmpty ? 'Las etiquetas aparecen solas al escribir, o elige abajo.' : 'Tu día incluye',
                  style: OhtliUi.body(size: 12),
                ),
              ),
              TextButton.icon(
                onPressed: _giveMoodIdea,
                icon: const Icon(Icons.auto_awesome_rounded, size: 16),
                label: const Text('Dame una idea'),
                style: TextButton.styleFrom(
                  foregroundColor: OhtliColors.accentText,
                  backgroundColor: OhtliColors.stormyTeal.withValues(alpha: 0.10),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  shape: const StadiumBorder(),
                  textStyle: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          if (active.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final t in active)
                  InputChip(
                    label: Text(t),
                    selected: true,
                    showCheckmark: false,
                    labelStyle: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w700, color: OhtliColors.accentText),
                    selectedColor: OhtliColors.stormyTeal.withValues(alpha: 0.14),
                    side: BorderSide(color: OhtliColors.stormyTeal.withValues(alpha: 0.35)),
                    shape: const StadiumBorder(),
                    deleteIcon: const Icon(Icons.close_rounded, size: 15),
                    deleteIconColor: OhtliColors.accentText,
                    deleteButtonTooltipMessage: 'Quitar $t',
                    onDeleted: () => setState(() {
                      _pickedTags.remove(t);
                      _dismissedTags.add(t);
                    }),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          SizedBox(
            height: 36,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              itemCount: suggestions.length,
              separatorBuilder: (_, _) => const SizedBox(width: 6),
              itemBuilder: (_, i) {
                final t = suggestions[i];
                return ActionChip(
                  avatar: Icon(Icons.add_rounded, size: 15, color: OhtliColors.subtleText),
                  label: Text(t),
                  labelStyle: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600, color: OhtliColors.onyx),
                  backgroundColor: OhtliColors.innerCardBg,
                  side: BorderSide(color: OhtliColors.cardBorder),
                  shape: const StadiumBorder(),
                  onPressed: () => setState(() {
                    _dismissedTags.remove(t);
                    _pickedTags.add(t);
                  }),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  String _transportModeHint(String id) {
    switch (id) {
      case 'bike':
        return 'Rutas más amplias pedaleando; los tramos cortos se hacen a pie.';
      case 'transit':
        return 'Metro, Metrobús y otros: llegas más lejos por unos pesos; lo cercano, a pie.';
      case 'mixto':
        return 'Caminas hasta unos 2 km y tomas transporte público para lo más lejano.';
      case 'taxi':
        return 'Traslados rápidos; el costo estimado del taxi se suma aparte.';
      case 'car':
        return 'Contamos tiempo para estacionar en cada parada.';
      default:
        return 'Todo el recorrido a pie, en un radio cercano a tu punto de partida.';
    }
  }

  // Ideas de ejemplo por estilo para "Dame una idea"
  static const Map<String, List<String>> _moodIdeas = {
    'Bohemio y Cafés': [
      'Una mañana tranquila entre cafés de especialidad, librerías de viejo y calles arboladas para caminar sin prisa.',
      'Café de olla para empezar, una galería pequeña y terminar con pan dulce en una terraza con buena vista.',
      'Barrios bohemios, cafeterías con historia y alguna tienda de vinilos para perderme un rato.',
    ],
    'Muralismo e Historia': [
      'Murales de Rivera y Orozco, edificios coloniales y un buen lugar para comer cerca del Centro.',
      'Quiero entender la historia de la ciudad a través de su arte público y sus museos más emblemáticos.',
      'Un recorrido por palacios y murales con pausas para un café y algo típico.',
    ],
    'Cantinas Tradicionales': [
      'Tarde de cantinas clásicas con botana, música en vivo y algo de historia entre una y otra.',
      'Probar pulque y mezcal en lugares de tradición, caminando entre barrios con carácter.',
      'Empezar con una comida corrida y terminar en una cantina con mucho ambiente.',
    ],
    'Senderos Verdes y Calma': [
      'Un día al aire libre entre parques, jardines y lagos, con poco tráfico y ritmo relajado.',
      'Caminar por bosques urbanos, sentarme a leer y comer algo ligero cerca de la naturaleza.',
      'Viveros, jardines botánicos y miradores para desconectarme de la ciudad.',
    ],
    'Gastronomía y Mercados': [
      'Recorrer mercados tradicionales probando antojitos, frutas y dulces mexicanos.',
      'Tacos, tortas y un buen postre, visitando fondas y mercados con historia.',
      'Comer como local: mercado por la mañana, fonda al mediodía y café por la tarde.',
    ],
    'Arquitectura y Museos': [
      'Museos de arte y arquitectura moderna con edificios icónicos y buenas vistas.',
      'Un día de museos con pausas en cafés de diseño y paseos por avenidas emblemáticas.',
      'Ver contrastes entre lo colonial y lo contemporáneo, terminando en un mirador.',
    ],
  };

  void _giveMoodIdea() {
    final all = [for (final l in _moodIdeas.values) ...l];
    // Primero las ideas que hablan de lo que ya marcó la persona
    final related = _activeTags.isEmpty
        ? all
        : all.where((idea) {
            final f = _fold(idea);
            return _activeTags.any((t) => _moodTagKeywords[t]!.any((k) => f.contains(_fold(k))));
          }).toList();
    final pool = related.isEmpty ? all : related;
    setState(() {
      _customMoodController.text = pool[_ideaIndex % pool.length];
      _ideaIndex++;
      _dismissedTags.clear();
    });
  }


  Widget _buildTopologyOption({
    required String key,
    required String title,
    required String desc,
    required IconData icon,
  }) {
    final isSelected = _selectedTopology == key;
    return OhtliSurface(
      selected: isSelected,
      radius: 20,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      onTap: () => setState(() => _selectedTopology = key),
      child: Row(
        children: [
          OhtliServiceIcon(icon: icon, color: OhtliColors.stormyTeal, size: 40, soft: !isSelected),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, style: GoogleFonts.outfit(fontSize: 15.5, fontWeight: FontWeight.w700, color: OhtliColors.onyx)),
                const SizedBox(height: 2),
                Text(desc, maxLines: 2, overflow: TextOverflow.ellipsis, style: OhtliUi.body(size: 12.5)),
              ],
            ),
          ),
          AnimatedOpacity(
            duration: const Duration(milliseconds: 200),
            opacity: isSelected ? 1 : 0,
            child: const Icon(Icons.check_circle_rounded, color: OhtliColors.stormyTeal, size: 20),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // PASO 3: PROCESAMIENTO SMA (BLACKBOARD)
  // ==========================================
  Widget _buildBlackboardProcessingStep(bool isMobile) {
    if (_jobError != null) {
      return _buildJobErrorState(isMobile);
    }
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
          'Estamos armando tus rutas',
          textAlign: TextAlign.center,
          style: GoogleFonts.outfit(
            fontSize: isMobile ? 22 : 26,
            fontWeight: FontWeight.w800,
            color: OhtliColors.onyx,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _currentAgentName == 'Generador'
              ? 'Trazando el recorrido y calculando los traslados ${_selectedTransportMode == 'walking' ? 'a pie' : '(${plannerModeOf(_selectedTransportMode).label.toLowerCase()})'}...'
              : (_currentAgentName == 'Recomendador'
                  ? 'Dando los últimos toques a cada propuesta...'
                  : 'Buscando los lugares que van con tu estilo...'),
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
                agentLabel: 'Elegimos los lugares',
                taskDesc: 'Según tu estilo y presupuesto, con variedad entre opciones',
                isActive: _currentAgentName == 'Comparador',
                isDone: _blackboardProgress > 35,
              ),
              const Divider(height: 24),
              _buildAgentStateRow(
                agentLabel: 'Trazamos el recorrido',
                taskDesc: _selectedTransportMode == 'walking'
                    ? 'Ordenamos las paradas para que camines lo justo'
                    : 'Ordenamos las paradas para que te traslades lo justo',
                isActive: _currentAgentName == 'Generador',
                isDone: _blackboardProgress > 70,
              ),
              const Divider(height: 24),
              _buildAgentStateRow(
                agentLabel: 'Preparamos cada propuesta',
                taskDesc: 'Descripción de cada parada y costo estimado en MXN',
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
        return OhtliColors.accent;
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
      return widget.groupTripId != null
          ? const Center(child: CircularProgressIndicator(color: OhtliColors.stormyTeal))
          : const SizedBox.shrink();
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
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.auto_awesome_rounded, size: 13, color: OhtliColors.accentText),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            'PROPUESTAS CON IA · ${_activeCarouselIndex + 1} DE ${_generatedOptions.length}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: OhtliUi.eyebrow(OhtliColors.accentText),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Elige tu ruta',
                      maxLines: 1,
                      style: GoogleFonts.outfit(fontSize: 26, fontWeight: FontWeight.w800, color: OhtliColors.onyx, height: 1.05, letterSpacing: -0.5),
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
                      decoration: BoxDecoration(color: isSelected ? OhtliColors.stormyTeal : OhtliColors.onyx.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(4)),
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
            _reportOptionShown();
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
    final pitch = (option['pitch'] ?? '').toString().trim();
    final summary = pitch.isNotEmpty ? pitch : (option['narrative_summary'] ?? '').toString();
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
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [Color(0xFF2C666E), Color(0xFF3E8A8F)]),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: Colors.white.withValues(alpha: 0.25), width: 0.8),
          ),
          child: Text(
            'Opción ${index + 1}',
            style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w800, color: Colors.white),
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.38),
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: Colors.white.withValues(alpha: 0.18), width: 0.8),
            ),
            child: Text(
              (option['theme'] ?? 'Experiencia').toString(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w700, color: Colors.white),
            ),
          ),
        ),
        if (_group != null && _group!.votersFor(index).isNotEmpty) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(color: OhtliColors.accentFill, borderRadius: BorderRadius.circular(30)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.how_to_vote_rounded, size: 13, color: Colors.white),
                const SizedBox(width: 4),
                Text('${_group!.votersFor(index).length}',
                    style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w800, color: Colors.white)),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildChooseRouteButton(Map<String, dynamic> option, double cost, bool isMobile, {bool compact = false}) {
    const fg = Colors.white;
    return ElevatedButton.icon(
      onPressed: _isSavingTrip ? null : () => _chooseRouteAndCreateTrip(option),
      icon: _isSavingTrip
          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: fg))
          : Icon(
              widget.groupTripId == null
                  ? Icons.alt_route_rounded
                  : (_myVote != null && _myVote == _generatedOptions.indexOf(option) ? Icons.check_rounded : Icons.how_to_vote_rounded),
              color: fg,
              size: compact ? 17 : 19),
      label: Text(
        _chooseLabel(option, cost, compact: compact),
        style: GoogleFonts.outfit(fontSize: compact ? 13.5 : (isMobile ? 14 : 15), fontWeight: FontWeight.w800, color: fg),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: OhtliColors.accentFill,
        foregroundColor: fg,
        disabledBackgroundColor: OhtliColors.accent.withValues(alpha: 0.6),
        padding: compact ? const EdgeInsets.symmetric(horizontal: 16, vertical: 12) : EdgeInsets.symmetric(horizontal: isMobile ? 20 : 26, vertical: isMobile ? 14 : 17),
        shape: const StadiumBorder(),
        elevation: 0,
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
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: isFocused ? Colors.white.withOpacity(0.35) : Colors.white.withOpacity(0.08), width: isFocused ? 1.8 : 1.0),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(isFocused ? (hovering ? 0.45 : 0.35) : 0.15), blurRadius: isFocused ? (hovering ? 40 : 28) : 14, offset: Offset(0, hovering ? 18 : 10)),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(28),
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
    final double radius = lerpDouble(28, isMobile ? 0 : 20, t)!;
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
        color: Colors.black.withValues(alpha: 0.38),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18), width: 0.8),
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
                      borderRadius: BorderRadius.circular(30),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(30),
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
    final optionMode = plannerModeOf(option['transport_mode']?.toString());
    final bool onFoot = optionMode.id == 'walking';
    final travelMins = (option['total_travel_mins'] as num?)?.toInt() ?? totalWalkMins;
    final travelKm = (option['total_travel_km'] as num?)?.toDouble();
    final transportCost = (option['total_transport_cost_mxn'] as num?)?.toDouble() ?? 0.0;
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
          '&destination=${waypointNames.last}${waypoints.isNotEmpty ? '&waypoints=$waypoints' : ''}'
          '&travelmode=${optionMode.googleTravelMode}';
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
      statTile(Icons.payments_outlined, '\$${(cost + transportCost).toStringAsFixed(0)}',
          transportCost > 0 ? 'Costo (incl. \$${transportCost.toStringAsFixed(0)} traslados)' : 'Costo (MXN)',
          OhtliColors.accent),
      statTile(Icons.place_rounded, '${rawStops.length} paradas', '${fmtMins(totalStayMins)} en sitio', OhtliColors.accent),
      onFoot
          ? statTile(Icons.directions_walk_rounded, '${walkingKm.toStringAsFixed(1)} km', '${fmtMins(totalWalkMins)} caminando', const Color(0xFF3F8F5B))
          : statTile(optionMode.icon, '${(travelKm ?? walkingKm).toStringAsFixed(1)} km',
              '${fmtMins(travelMins)} de traslado', const Color(0xFF3F8F5B)),
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
      // Sin calificación en el catálogo no se muestra ninguna (antes se rellenaba con 4.8)
      final rating = (stop['rating'] as num?)?.toDouble();
      final priceIsEstimate = stop['price_is_estimate'] != false;
      // Lo que escribió el Recomendador para esta parada; si no hay, la descripción del lugar.
      final nar = _stopNarration(option, stop);
      final narText = [nar['highlight'] ?? '', nar['story'] ?? ''].where((t) => t.isNotEmpty).join(' — ');
      final desc = narText.isNotEmpty ? narText : _stopDetailDescription(stop);
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
                          if (rating != null) chip(
                            Row(mainAxisSize: MainAxisSize.min, children: [
                              const Icon(Icons.star_rounded, size: 12, color: OhtliColors.rating),
                              const SizedBox(width: 3),
                              Text(rating.toStringAsFixed(1),
                                  style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w700, color: const Color(0xFFB07E00))),
                            ]),
                            OhtliColors.rating,
                          ),
                          chip(
                            Row(mainAxisSize: MainAxisSize.min, children: [
                              Icon(Icons.schedule_rounded, size: 12, color: OhtliColors.accent),
                              const SizedBox(width: 4),
                              Text(
                                arrival != null ? '$arrival${departure != null ? ' – $departure' : ''} · $stayMins min' : '$stayMins min',
                                style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w700, color: OhtliColors.accent),
                              ),
                            ]),
                            OhtliColors.accent,
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
                            stopPrice > 0
                                ? (priceIsEstimate ? '~\$${stopPrice.toStringAsFixed(0)} MXN (estimado)' : '\$${stopPrice.toStringAsFixed(0)} MXN')
                                : (priceIsEstimate ? 'Gratis (estimado)' : 'Gratis'),
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
      // Medio de este tramo según el motor (los tramos cortos van a pie aunque el medio sea otro).
      final legMode = plannerModeOf(nextStop['transport_mode']?.toString() ?? 'walking');
      final legCost = (nextStop['transport_cost_mxn'] as num?)?.toDouble() ?? 0.0;
      final legLabel = legMode.id == 'walking' ? 'a pie' : legMode.label.toLowerCase();
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Icon(legMode.icon, size: 15, color: OhtliColors.stormyTeal),
            const SizedBox(width: 6),
            Text(
              '$nextWalkMins min · ${nextDistKm.toStringAsFixed(1)} km $legLabel'
              '${legCost > 0 ? ' · ~\$${legCost.toStringAsFixed(0)}' : ''}',
              style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w600, color: textSecondary),
            ),
          ],
        ),
      );
    }

    Widget? finalConnector() {
      final leg = option['final_leg'];
      if (leg is! Map) return null;
      final mins = (leg['mins'] as num?)?.toInt() ?? 0;
      final km = (leg['km'] as num?)?.toDouble() ?? 0.0;
      final legMode = plannerModeOf(leg['transport_mode']?.toString() ?? 'walking');
      final cost = (leg['transport_cost_mxn'] as num?)?.toDouble() ?? 0.0;
      final toOrigin = leg['to'] == 'origin';
      final where = toOrigin ? 'Regreso al punto de partida' : 'Llegada al punto final';
      final how = km <= 0.05
          ? 'ya estás ahí'
          : '$mins min · ${km.toStringAsFixed(1)} km ${legMode.id == 'walking' ? 'a pie' : legMode.label.toLowerCase()}'
              '${cost > 0 ? ' · ~\$${cost.toStringAsFixed(0)}' : ''}';
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Icon(toOrigin ? Icons.u_turn_left_rounded : Icons.flag_rounded, size: 15, color: OhtliColors.stormyTeal),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                '$where · $how',
                style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w600, color: textSecondary),
              ),
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
                    if (!isLast) walkConnector(idx) else (finalConnector() ?? const SizedBox(height: 4)),
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
        // Por qué esta alternativa es para la persona y sus puntos fuertes (Recomendador).
        if ((option['pitch'] ?? '').toString().trim().isNotEmpty) ...[
          Text(
            (option['pitch']).toString().trim(),
            style: GoogleFonts.outfit(fontSize: isMobile ? 17 : 20, fontWeight: FontWeight.w700, color: textPrimary, height: 1.35),
          ),
          const SizedBox(height: 12),
        ],
        if (((option['highlights'] as List?) ?? const []).isNotEmpty) ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final h in (option['highlights'] as List).take(3))
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: OhtliColors.stormyTeal.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.check_circle_rounded, size: 15, color: OhtliColors.stormyTeal),
                    const SizedBox(width: 6),
                    Flexible(child: Text(h.toString(), style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600, color: textPrimary))),
                  ]),
                ),
            ],
          ),
          const SizedBox(height: 16),
        ],
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
                  onPressed: () => web.window.open(googleMapsDirectionsUrl, '_blank'),
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
              modeIcon: optionMode.icon,
              modeLabel: optionMode.label,
              googleTravelMode: optionMode.googleTravelMode,
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
                  _chooseLabel(option, cost),
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



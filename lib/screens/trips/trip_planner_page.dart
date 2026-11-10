// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use, avoid_print

import 'dart:async';
import 'dart:html' as html;
import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/poi_model.dart';
import '../../models/trip_model.dart';
import '../../services/itinerary_blackboard_service.dart';
import '../../theme/colors.dart';
import '../../widgets/osrm_map_widget.dart';
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

class _TripPlannerPageState extends State<TripPlannerPage> {
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

  ScrollController _getCardScrollController(int index) {
    return _cardScrollControllers.putIfAbsent(index, () => ScrollController());
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
            });
          }
        }
      });
    } catch (e) {
      debugPrint('Error escuchando job en el Blackboard: $e');
    }
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
            if (_currentStep == PlannerStep.preferences) {
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
                child: SingleChildScrollView(
                  physics: _currentStep == PlannerStep.routeTriadCarousel
                      ? const NeverScrollableScrollPhysics()
                      : const BouncingScrollPhysics(),
                  padding: EdgeInsets.symmetric(
                    horizontal: _currentStep == PlannerStep.routeTriadCarousel ? 0 : (isMobile ? 16 : 24),
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

  static const List<String> _highResCdmxCovers = [
    'https://images.unsplash.com/photo-1518638150340-f706e86654de?auto=format&fit=crop&w=1400&q=85', // Bellas Artes
    'https://images.unsplash.com/photo-1584551246679-0daf3d275d0f?auto=format&fit=crop&w=1400&q=85', // Paseo de la Reforma
    'https://images.unsplash.com/photo-1585464231875-d9ef1f5ad396?auto=format&fit=crop&w=1400&q=85', // Centro Histórico
    'https://images.unsplash.com/photo-1579783900882-c0d3dad7b119?auto=format&fit=crop&w=1400&q=85', // Coyoacán
    'https://images.unsplash.com/photo-1512813195386-6cf811ad3542?auto=format&fit=crop&w=1400&q=85', // Chapultepec
  ];

  static const Map<String, List<String>> _curatedCategoryPhotos = {
    'cafe': [
      'https://images.unsplash.com/photo-1501339847302-ac426a4a7cbb?auto=format&fit=crop&w=800&q=85',
      'https://images.unsplash.com/photo-1554118811-1e0d58224f24?auto=format&fit=crop&w=800&q=85',
    ],
    'restaurant': [
      'https://images.unsplash.com/photo-1517248135467-4c7edcad34c4?auto=format&fit=crop&w=800&q=85',
      'https://images.unsplash.com/photo-1555396273-367ea4eb4db5?auto=format&fit=crop&w=800&q=85',
    ],
    'museum': [
      'https://images.unsplash.com/photo-1566127444979-b3d2b654e3d7?auto=format&fit=crop&w=800&q=85',
      'https://images.unsplash.com/photo-1582555172866-f73bb12a2ab3?auto=format&fit=crop&w=800&q=85',
    ],
    'park': [
      'https://images.unsplash.com/photo-1519331379826-f10be5486c6f?auto=format&fit=crop&w=800&q=85',
      'https://images.unsplash.com/photo-1542601906990-b4d3fb778b09?auto=format&fit=crop&w=800&q=85',
    ],
    'artwork': [
      'https://images.unsplash.com/photo-1579783900882-c0d3dad7b119?auto=format&fit=crop&w=800&q=85',
      'https://images.unsplash.com/photo-1579783902614-a3fb3927b675?auto=format&fit=crop&w=800&q=85',
    ],
    'bar': [
      'https://images.unsplash.com/photo-1514933651103-005eec06c04b?auto=format&fit=crop&w=800&q=85',
      'https://images.unsplash.com/photo-1572116469696-31de0f17cc34?auto=format&fit=crop&w=800&q=85',
    ],
    'market': [
      'https://images.unsplash.com/photo-1533900298318-6b8da08a523e?auto=format&fit=crop&w=800&q=85',
      'https://images.unsplash.com/photo-1543083477-4f785aeafaa9?auto=format&fit=crop&w=800&q=85',
    ],
  };

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
    final cat = (stop['category'] ?? stop['type'] ?? 'general').toString().toLowerCase();
    final key = _curatedCategoryPhotos.containsKey(cat) ? cat : 'museum';
    final list = _curatedCategoryPhotos[key] ?? _curatedCategoryPhotos['museum']!;
    return list[idx % list.length];
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

  void _handleTriadPointerScroll(PointerScrollEvent pointerSignal) {
    final dy = pointerSignal.scrollDelta.dy;
    final dx = pointerSignal.scrollDelta.dx;

    // Descartar gestos horizontales del trackpad (para no confundir swipe lateral con scroll)
    if (dx.abs() > 8 || dy.abs() < dx.abs() * 2.0) {
      return;
    }

    const double threshold = 28.0;

    if (!_isDetailExpanded) {
      // EN EL CARRUSEL: Scroll up o vertical intencional abre el detalle
      if (dy.abs() > threshold) {
        setState(() => _isDetailExpanded = true);
      }
    } else {
      // EN EL DETALLE EXPANDIDO: Scroll down contrae el detalle
      // En trackpad macOS, swipe down con dos dedos (tirar hacia abajo) genera dy < -20
      if (dy < -22) {
        setState(() => _isDetailExpanded = false);
      }
    }
  }

  Widget _buildRouteTriadCarouselStep(bool isMobile) {
    if (_generatedOptions.isEmpty) {
      return const SizedBox.shrink();
    }

    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    // Escala amplia: en desktop la opción ocupa entre 80% y 88% del ancho de pantalla
    final double targetFraction = isMobile
        ? 0.92
        : (screenWidth < 1100
            ? 0.88
            : (screenWidth < 1500 ? 0.84 : 0.80));

    // Alto dinámico en la misma tarjeta sin cambiar de vista
    final double carouselCardHeight = _isDetailExpanded
        ? (isMobile ? (screenHeight * 0.90).clamp(580.0, 800.0) : (screenHeight * 0.92).clamp(720.0, 1020.0))
        : (isMobile ? (screenHeight * 0.86).clamp(520.0, 720.0) : (screenHeight * 0.90).clamp(640.0, 960.0));

    final headerMaxWidth = isMobile ? double.infinity : (screenWidth * targetFraction).clamp(760.0, 1300.0);
    final controller = _getTriadPageController(targetFraction);

    return _buildCarouselSelectorView(
      isMobile,
      controller,
      carouselCardHeight,
      headerMaxWidth,
    );
  }

  Widget _buildCarouselSelectorView(
    bool isMobile,
    PageController controller,
    double carouselCardHeight,
    double headerMaxWidth,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Indicador superior / Controles alineados al ancho de la tarjeta
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: headerMaxWidth),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ELIGE TU OPCIÓN DE VIAJE',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.5,
                        color: OhtliColors.onyx.withOpacity(0.7),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Alternativas temáticas diseñadas por IA (${_activeCarouselIndex + 1} de ${_generatedOptions.length})',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: OhtliColors.subtleText,
                      ),
                    ),
                  ],
                ),
                // Paginador interactivo
                Row(
                  children: List.generate(_generatedOptions.length, (idx) {
                    final isSelected = _activeCarouselIndex == idx;
                    return InkWell(
                      onTap: () {
                        controller.animateToPage(
                          idx,
                          duration: const Duration(milliseconds: 350),
                          curve: Curves.easeOutCubic,
                        );
                      },
                      borderRadius: BorderRadius.circular(4),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: isSelected ? 28 : 10,
                        height: 8,
                        decoration: BoxDecoration(
                          color: isSelected ? OhtliColors.stormyTeal : OhtliColors.cardBorder,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    );
                  }),
                ),
              ],
            ),
          ),
        ),

        // Carrusel cinematográfico amplio con altura al 90% del viewport
        Stack(
          alignment: Alignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 320),
              curve: Curves.easeOutCubic,
              height: carouselCardHeight,
              child: PageView.builder(
                controller: controller,
                itemCount: _generatedOptions.length,
                onPageChanged: (idx) {
                  setState(() => _activeCarouselIndex = idx);
                },
                itemBuilder: (context, index) {
                  final option = _generatedOptions[index];
                  final isFocused = _activeCarouselIndex == index;
                  return AnimatedScale(
                    scale: isFocused ? 1.0 : (_isDetailExpanded ? 0.94 : 0.88),
                    duration: const Duration(milliseconds: 320),
                    curve: Curves.easeOutCubic,
                    child: AnimatedOpacity(
                      opacity: isFocused ? 1.0 : (_isDetailExpanded ? 0.40 : 0.52),
                      duration: const Duration(milliseconds: 320),
                      child: GestureDetector(
                        onTap: () {
                          if (!isFocused) {
                            controller.animateToPage(
                              index,
                              duration: const Duration(milliseconds: 350),
                              curve: Curves.easeOutCubic,
                            );
                          } else if (!_isDetailExpanded) {
                            // Al hacer clic en la tarjeta enfocada, abre detalles completos en la misma tarjeta
                            setState(() => _isDetailExpanded = true);
                          }
                        },
                        child: _buildRouteCard(
                          option,
                          isFocused,
                          isMobile,
                          index,
                          isExpanded: _isDetailExpanded,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),

            // Flecha Izquierda (Desktop)
            if (!isMobile && _activeCarouselIndex > 0)
              Positioned(
                left: 20,
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () {
                      controller.previousPage(
                        duration: const Duration(milliseconds: 350),
                        curve: Curves.easeOutCubic,
                      );
                    },
                    borderRadius: BorderRadius.circular(24),
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.6),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white.withOpacity(0.2)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.3),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18),
                    ),
                  ),
                ),
              ),

            // Flecha Derecha (Desktop)
            if (!isMobile && _activeCarouselIndex < _generatedOptions.length - 1)
              Positioned(
                right: 20,
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () {
                      controller.nextPage(
                        duration: const Duration(milliseconds: 350),
                        curve: Curves.easeOutCubic,
                      );
                    },
                    borderRadius: BorderRadius.circular(24),
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.6),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white.withOpacity(0.2)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.3),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white, size: 18),
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildRouteCard(
    Map<String, dynamic> option,
    bool isFocused,
    bool isMobile,
    int index, {
    bool isExpanded = false,
  }) {
    final title = (option['editorial_headline'] ?? option['theme'] ?? 'Ruta ${index + 1}').toString();
    final summary = (option['narrative_summary'] ?? '').toString();
    final cost = (option['total_cost_mxn'] as num?)?.toDouble() ?? 250.0;
    final timeMins = (option['estimated_time_mins'] as num?)?.toInt() ?? 180;
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
    final coverUrl = (rawCover != null && rawCover.trim().isNotEmpty)
        ? _upgradeImageUrl(rawCover, width: 1400, quality: 85)
        : _highResCdmxCovers[index % _highResCdmxCovers.length];

    final int hours = timeMins ~/ 60;
    final int minutes = timeMins % 60;
    final String timeStr = hours > 0 ? '$hours h $minutes min' : '$minutes min';

    if (isExpanded) {
      return _buildExpandedCard(
        option: option,
        isFocused: isFocused,
        isMobile: isMobile,
        index: index,
        title: title,
        summary: summary,
        cost: cost,
        timeStr: timeStr,
        coverUrl: coverUrl,
        stops: stops,
      );
    }

    return _buildCompactCard(
      option: option,
      isFocused: isFocused,
      isMobile: isMobile,
      index: index,
      title: title,
      summary: summary,
      cost: cost,
      timeStr: timeStr,
      coverUrl: coverUrl,
      stops: stops,
    );
  }

  Widget _buildCompactCard({
    required Map<String, dynamic> option,
    required bool isFocused,
    required bool isMobile,
    required int index,
    required String title,
    required String summary,
    required double cost,
    required String timeStr,
    required String coverUrl,
    required List<dynamic> stops,
  }) {
    double verticalDragDelta = 0;

    return Listener(
      onPointerSignal: (pointerSignal) {
        if (!isFocused) return;
        if (pointerSignal is PointerScrollEvent) {
          final dy = pointerSignal.scrollDelta.dy;
          final dx = pointerSignal.scrollDelta.dx;
          if (dx.abs() > 8 || dy.abs() < dx.abs() * 1.5) return;
          // Scroll vertical intencional en la tarjeta abre detalles
          if (dy.abs() > 20) {
            setState(() => _isDetailExpanded = true);
          }
        }
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (!isFocused) {
            _triadPageController?.animateToPage(
              index,
              duration: const Duration(milliseconds: 350),
              curve: Curves.easeOutCubic,
            );
          } else if (!_isDetailExpanded) {
            // Click en la tarjeta enfocada abre detalles
            setState(() => _isDetailExpanded = true);
          }
        },
        onVerticalDragUpdate: (details) {
          if (!isFocused) return;
          if (details.primaryDelta != null) {
            verticalDragDelta += details.primaryDelta!;
          }
        },
        onVerticalDragEnd: (details) {
          if (!isFocused) {
            verticalDragDelta = 0;
            return;
          }
          final velocity = details.primaryVelocity ?? 0;
          // Gesto hacia arriba (scroll up / swipe up) abre detalles
          if ((velocity < -120 || verticalDragDelta < -25) && !_isDetailExpanded) {
            setState(() => _isDetailExpanded = true);
          }
          verticalDragDelta = 0;
        },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isFocused ? Colors.white.withOpacity(0.35) : Colors.white.withOpacity(0.08),
            width: isFocused ? 1.8 : 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(isFocused ? 0.35 : 0.15),
              blurRadius: isFocused ? 28 : 14,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Stack(
            children: [
              // 1. Fotografía de fondo cinematográfica a alto completo con calidad curada
              Positioned.fill(
                child: Image.network(
                  coverUrl,
                  fit: BoxFit.cover,
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) return child;
                    return Container(
                      color: const Color(0xFF1E1E22),
                      child: const Center(
                        child: SizedBox(
                          width: 28,
                          height: 28,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: OhtliColors.stormyTeal,
                          ),
                        ),
                      ),
                    );
                  },
                  errorBuilder: (context, error, stackTrace) => Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFF1F2937), Color(0xFF111827)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: const Center(
                      child: Icon(Icons.explore_rounded, size: 48, color: Colors.white24),
                    ),
                  ),
                ),
              ),

                // 2. Gradiente Cinematográfico equilibrado
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.black.withOpacity(0.65),
                          Colors.black.withOpacity(0.15),
                          Colors.black.withOpacity(0.70),
                          Colors.black.withOpacity(0.97),
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: const [0.0, 0.28, 0.62, 1.0],
                      ),
                    ),
                  ),
                ),

                // 3. Barra Superior (Badges a la izquierda, Chevron arriba al centro, Bookmark a la derecha)
                Positioned(
                  top: isMobile ? 16 : 22,
                  left: isMobile ? 16 : 24,
                  right: isMobile ? 16 : 24,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: OhtliColors.stormyTeal,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'OPCIÓN ${index + 1}',
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.0,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.45),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.white.withOpacity(0.15)),
                            ),
                            child: Text(
                              (option['theme'] ?? 'EXPERIENCIA').toString().toUpperCase(),
                              style: GoogleFonts.inter(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.8,
                                color: Colors.white.withOpacity(0.9),
                              ),
                            ),
                          ),
                        ],
                      ),

                      IconButton(
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
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.black.withOpacity(0.45),
                          padding: const EdgeInsets.all(8),
                        ),
                      ),
                    ],
                  ),
                ),

                // 4. Contenido Inferior (Metadatos, Título, Sinopsis, Trazado de Ruta y Acciones)
                Positioned(
                  left: isMobile ? 16 : 26,
                  right: isMobile ? 16 : 26,
                  bottom: isMobile ? 16 : 24,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Badges de Metadatos (Tiempo, Costo, Paradas)
                      Row(
                        children: [
                          _buildMetaPill(Icons.schedule_rounded, timeStr),
                          const SizedBox(width: 8),
                          _buildMetaPill(Icons.payments_outlined, '\$${cost.toStringAsFixed(0)} MXN'),
                          const SizedBox(width: 8),
                          _buildMetaPill(Icons.place_rounded, '${stops.length} paradas'),
                        ],
                      ),
                      const SizedBox(height: 10),

                      // Título con escala balanceada
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.outfit(
                          fontSize: isMobile ? 20 : 26,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 8),

                      // Sinopsis Narrativa
                      if (summary.isNotEmpty)
                        Text(
                          summary,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            fontSize: isMobile ? 12 : 13.5,
                            color: Colors.white.withOpacity(0.88),
                            height: 1.35,
                          ),
                        ),
                      const SizedBox(height: 14),

                      // Trazado Secuencial de la Ruta en la Tarjeta
                      _buildCardRouteTrail(stops, option, index),
                      const SizedBox(height: 16),

                      // Botones de Acción
                      Wrap(
                        spacing: 12,
                        runSpacing: 10,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          ElevatedButton.icon(
                            onPressed: _isSavingTrip ? null : () => _chooseRouteAndCreateTrip(option),
                            icon: _isSavingTrip
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                                  )
                                : const Icon(Icons.play_arrow_rounded, color: Colors.black, size: 20),
                            label: Text(
                              _isSavingTrip ? 'Creando viaje...' : 'Elegir esta ruta (\$${cost.toStringAsFixed(0)} MXN)',
                              style: GoogleFonts.outfit(
                                fontSize: isMobile ? 13 : 14.5,
                                fontWeight: FontWeight.w800,
                                color: Colors.black,
                                letterSpacing: 0.2,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: Colors.black,
                              padding: EdgeInsets.symmetric(
                                horizontal: isMobile ? 18 : 26,
                                vertical: isMobile ? 12 : 16,
                              ),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                              elevation: 6,
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

  Widget _buildExpandedCard({
    required Map<String, dynamic> option,
    required bool isFocused,
    required bool isMobile,
    required int index,
    required String title,
    required String summary,
    required double cost,
    required String timeStr,
    required String coverUrl,
    required List<dynamic> stops,
  }) {
    final isDark = OhtliSettings.instance.isDarkMode;
    final scrollController = _getCardScrollController(index);
    double verticalDragDelta = 0;

    return Listener(
      onPointerSignal: (pointerSignal) {
        if (!isFocused) return;
        if (pointerSignal is PointerScrollEvent) {
          final dy = pointerSignal.scrollDelta.dy;
          final dx = pointerSignal.scrollDelta.dx;
          if (dx.abs() > 10 || dy.abs() < dx.abs() * 1.5) return;
          // Si el scroll está en el tope de la tarjeta expandida y hay scroll down (desplazamiento hacia abajo), contraer
          final isAtTop = !scrollController.hasClients || scrollController.offset <= 2;
          if (isAtTop && dy < -10) {
            setState(() => _isDetailExpanded = false);
          }
        }
      },
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onVerticalDragUpdate: (details) {
          if (!isFocused) return;
          if (details.primaryDelta != null) {
            verticalDragDelta += details.primaryDelta!;
          }
        },
        onVerticalDragEnd: (details) {
          if (!isFocused) {
            verticalDragDelta = 0;
            return;
          }
          final velocity = details.primaryVelocity ?? 0;
          final isAtTop = !scrollController.hasClients || scrollController.offset <= 2;
          // Arrastre hacia abajo en el tope contrae y regresa a la tarjeta
          if (isAtTop && (velocity > 120 || verticalDragDelta > 25)) {
            setState(() => _isDetailExpanded = false);
          }
          verticalDragDelta = 0;
        },
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E1E22) : Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: isFocused ? OhtliColors.stormyTeal : (isDark ? Colors.white12 : OhtliColors.cardBorder),
              width: isFocused ? 1.8 : 1.0,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(isDark ? 0.35 : 0.12),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: NotificationListener<ScrollNotification>(
              onNotification: (notification) {
                // Overscroll hacia abajo desde el tope contrae inmediatamente
                if (notification is OverscrollNotification && notification.overscroll < -3) {
                  if (_isDetailExpanded) {
                    setState(() => _isDetailExpanded = false);
                  }
                  return true;
                }
                // Scroll update hacia abajo en el tope contrae
                if (notification is ScrollUpdateNotification) {
                  if (notification.metrics.pixels <= 0 && (notification.scrollDelta ?? 0) < -10) {
                    if (_isDetailExpanded) {
                      setState(() => _isDetailExpanded = false);
                    }
                    return true;
                  }
                }
                return false;
              },
              child: SingleChildScrollView(
                controller: scrollController,
                physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Banner superior compacto con foto de portada y controles
                    SizedBox(
                      height: isMobile ? 180 : 230,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.network(
                            coverUrl,
                            fit: BoxFit.cover,
                            loadingBuilder: (context, child, loadingProgress) {
                              if (loadingProgress == null) return child;
                              return Container(
                                color: const Color(0xFF1E1E22),
                                child: const Center(
                                  child: SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: OhtliColors.stormyTeal),
                                  ),
                                ),
                              );
                            },
                            errorBuilder: (context, error, stackTrace) => Container(
                              color: const Color(0xFF1F2937),
                              child: const Icon(Icons.explore_rounded, color: Colors.white24, size: 36),
                            ),
                          ),
                          Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Colors.black.withOpacity(0.60),
                                  Colors.black.withOpacity(0.20),
                                  Colors.black.withOpacity(0.85),
                                ],
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                stops: const [0.0, 0.45, 1.0],
                              ),
                            ),
                          ),
                          // Barra superior en el banner (Badges y Bookmark - CERO BOTONES DE COLAPSO)
                          Positioned(
                            top: 14,
                            left: 16,
                            right: 16,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: OhtliColors.stormyTeal,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        'OPCIÓN ${index + 1}',
                                        style: GoogleFonts.inter(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 1.0,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: Colors.black.withOpacity(0.45),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: Colors.white.withOpacity(0.2)),
                                      ),
                                      child: Text(
                                        (option['theme'] ?? 'EXPERIENCIA').toString().toUpperCase(),
                                        style: GoogleFonts.inter(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: 0.8,
                                          color: Colors.white.withOpacity(0.9),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                IconButton(
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
                                  style: IconButton.styleFrom(
                                    backgroundColor: Colors.black.withOpacity(0.45),
                                    padding: const EdgeInsets.all(8),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // Pie del banner: Título y Metadatos
                          Positioned(
                            left: 16,
                            right: 16,
                            bottom: 14,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: GoogleFonts.outfit(
                                          fontSize: isMobile ? 18 : 22,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Row(
                                        children: [
                                          _buildMetaPill(Icons.schedule_rounded, timeStr),
                                          const SizedBox(width: 6),
                                          _buildMetaPill(Icons.payments_outlined, '\$${cost.toStringAsFixed(0)} MXN'),
                                          const SizedBox(width: 6),
                                          _buildMetaPill(Icons.place_rounded, '${stops.length} paradas'),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 12),
                                ElevatedButton.icon(
                                  onPressed: _isSavingTrip ? null : () => _chooseRouteAndCreateTrip(option),
                                  icon: _isSavingTrip
                                      ? const SizedBox(
                                          width: 12,
                                          height: 12,
                                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                                        )
                                      : const Icon(Icons.play_arrow_rounded, color: Colors.black, size: 18),
                                  label: Text(
                                    _isSavingTrip ? 'Creando...' : 'Elegir (\$${cost.toStringAsFixed(0)})',
                                    style: GoogleFonts.outfit(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.black,
                                    ),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.white,
                                    foregroundColor: Colors.black,
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                    elevation: 4,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Contenido del detalle: Sinopsis, Mapa y Cronología
                    Padding(
                      padding: EdgeInsets.all(isMobile ? 16 : 24),
                      child: _buildInPageExpandedDetail(
                        option,
                        index,
                        isMobile,
                        isEmbeddedInCard: true,
                      ),
                    ),
                  ],
                ),
              ),
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
                onTap: () {
                  setState(() => _isDetailExpanded = true);
                },
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
                        setState(() => _isDetailExpanded = true);
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
    final title = (option['editorial_headline'] ?? option['theme'] ?? 'Ruta ${index + 1}').toString();
    final summary = (option['narrative_summary'] ?? '').toString();
    final cost = (option['total_cost_mxn'] as num?)?.toDouble() ?? 250.0;
    final timeMins = (option['estimated_time_mins'] as num?)?.toInt() ?? 180;
    final List<dynamic> rawStops = option['route'] ?? [];
    final List<dynamic> rawNarrations = option['stops_narration'] ?? [];

    final int hours = timeMins ~/ 60;
    final int minutes = timeMins % 60;
    final String timeStr = hours > 0 ? '$hours h $minutes min' : '$minutes min';

    const mapsApiKey = String.fromEnvironment('mapsApiKey');
    const apiKey = String.fromEnvironment('apiKey');
    final activeKey = mapsApiKey.isNotEmpty ? mapsApiKey : apiKey;

    // Extracción robusta de coordenadas para cada parada
    final validCoords = <Map<String, dynamic>>[];
    final waypointNames = <String>[];
    final markers = StringBuffer();
    final path = StringBuffer('&path=color:0x2C666Eff|weight:6');

    for (int i = 0; i < rawStops.length; i++) {
      final s = rawStops[i] as Map<String, dynamic>;
      final label = (i + 1).toString();
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

      if (lat != null && lng != null) {
        validCoords.add({'index': i + 1, 'name': stopName, 'lat': lat, 'lng': lng});
        markers.write('&markers=color:0xE26D5C|label:$label|$lat,$lng');
        path.write('|$lat,$lng');
        waypointNames.add('$lat,$lng');
      } else {
        final encodedName = Uri.encodeComponent('$stopName, CDMX');
        markers.write('&markers=color:0xE26D5C|label:$label|$encodedName');
        waypointNames.add(encodedName);
      }
    }

    final staticMapUrl = activeKey.isNotEmpty && validCoords.isNotEmpty
        ? 'https://maps.googleapis.com/maps/api/staticmap?size=1100x520&scale=2&maptype=roadmap$path$markers&key=$activeKey'
        : '';

    String googleMapsDirectionsUrl = '';
    if (waypointNames.isNotEmpty) {
      final origin = waypointNames.first;
      final destination = waypointNames.last;
      final waypoints = waypointNames.length > 2
          ? waypointNames.sublist(1, waypointNames.length - 1).join('|')
          : '';
      final waypointsParam = waypoints.isNotEmpty ? '&waypoints=$waypoints' : '';
      googleMapsDirectionsUrl =
          'https://www.google.com/maps/dir/?api=1&origin=$origin&destination=$destination$waypointsParam&travelmode=walking';
    }

    final innerContent = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!isEmbeddedInCard) ...[
          // Encabezado suelto (solo en modo no embebido)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: OhtliColors.stormyTeal,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'OPCIÓN ${index + 1}',
                      style: GoogleFonts.inter(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.0,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'ITINERARIO Y MAPA COMPLETO',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                      color: OhtliColors.stormyTeal,
                    ),
                  ),
                ],
              ),
              IconButton(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Esta opción permanecerá guardada en tu pestaña Planes.', style: GoogleFonts.inter()),
                      backgroundColor: OhtliColors.stormyTeal,
                    ),
                  );
                },
                icon: const Icon(Icons.bookmark_add_outlined, size: 20),
                tooltip: 'Guardar alternativa en Planes',
                color: isDark ? Colors.white70 : OhtliColors.onyx,
              ),
            ],
          ),
          const SizedBox(height: 8),

          Text(
            title,
            style: GoogleFonts.outfit(
              fontSize: isMobile ? 20 : 24,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : OhtliColors.onyx,
            ),
          ),
          const SizedBox(height: 12),

          // Badges de Metadatos
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildDialogMetaPill(Icons.schedule_rounded, timeStr, isDark),
              _buildDialogMetaPill(Icons.payments_outlined, '\$${cost.toStringAsFixed(0)} MXN', isDark),
              _buildDialogMetaPill(Icons.place_rounded, '${rawStops.length} paradas', isDark),
              _buildDialogMetaPill(
                Icons.directions_walk_rounded,
                '${((option['total_walking_km'] as num?)?.toDouble() ?? (option['osm_route'] is Map ? (option['osm_route']['total_distance_km'] as num?)?.toDouble() : null) ?? 0.0).toStringAsFixed(1)} km a pie',
                isDark,
              ),
            ],
          ),
        ],
        if (summary.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text(
            summary,
            style: GoogleFonts.inter(
              fontSize: 13,
              color: isDark ? Colors.white70 : OhtliColors.subtleText,
              height: 1.4,
            ),
          ),
        ],
        const SizedBox(height: 24),

          // Sección: Mapa de la Ruta con OpenStreetMap & OSRM
          Row(
            children: [
              const Icon(Icons.map_rounded, color: OhtliColors.stormyTeal, size: 20),
              const SizedBox(width: 8),
              Text(
                'Mapa de la Ruta',
                style: GoogleFonts.outfit(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : OhtliColors.onyx,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Visor cartográfico oficial OpenStreetMap & OSRM
          OsrmMapWidget(
            stops: rawStops,
            routeGeometry: (option['osm_route_geometry'] as List<dynamic>?) ??
                (option['osm_route'] is Map ? (option['osm_route']['coordinates'] as List<dynamic>?) : null),
            height: isMobile ? 260 : 360,
            isDark: isDark,
          ),
          const SizedBox(height: 32),

          // Sección: Cronología del Recorrido
          Row(
            children: [
              const Icon(Icons.timeline_rounded, color: OhtliColors.cempasuchil, size: 20),
              const SizedBox(width: 8),
              Text(
                'Cronología de Paradas',
                style: GoogleFonts.outfit(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : OhtliColors.onyx,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Timeline vertical de paradas
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: rawStops.length,
            itemBuilder: (context, idx) {
              final stop = rawStops[idx] as Map<String, dynamic>;
              final stopName = (stop['name'] ?? 'Parada ${idx + 1}').toString();
              final isLast = idx == rawStops.length - 1;
              final arrival = stop['arrival_time']?.toString();
              final departure = stop['departure_time']?.toString();
              final timeLabel = arrival != null
                  ? '$arrival${departure != null ? " - $departure" : ""}'
                  : 'Parada ${idx + 1}';
              final stopPrice = (stop['price_mxn'] as num?)?.toDouble() ?? 0.0;
              final photo = _resolveStopPhoto(stop, idx);
              final category = (stop['category'] ?? stop['type'] ?? 'general').toString();
              final catIcon = _getStopCategoryIcon(category);
              final catColor = _getStopCategoryColor(category);

              String desc = '';
              if (idx < rawNarrations.length && rawNarrations[idx] != null) {
                final n = rawNarrations[idx];
                if (n is Map) {
                  desc = (n['narration'] ?? n['why'] ?? '').toString();
                } else {
                  desc = n.toString();
                }
              }
              if (desc.isEmpty) {
                desc = (stop['semantic_description'] ?? '').toString();
              }

              return IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Columna Izquierda: Número y línea conectora
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

                    // Columna Derecha: Detalle de Parada
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(bottom: isLast ? 0 : 20),
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF26262B) : OhtliColors.innerCardBg,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: isDark ? Colors.white12 : OhtliColors.cardBorder,
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Fotografía estilizada alineada con la sección Lugares (PoiCard)
                              Container(
                                width: isMobile ? 74 : 86,
                                height: isMobile ? 74 : 86,
                                decoration: BoxDecoration(
                                  color: isDark ? const Color(0xFF16161A) : OhtliColors.innerCardBg,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: isDark ? Colors.white12 : OhtliColors.cardBorder,
                                  ),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      Image.network(
                                        photo,
                                        fit: BoxFit.cover,
                                        loadingBuilder: (context, child, loadingProgress) {
                                          if (loadingProgress == null) return child;
                                          return Container(
                                            color: isDark ? const Color(0xFF16161A) : OhtliColors.innerCardBg,
                                            child: const Center(
                                              child: SizedBox(
                                                width: 18,
                                                height: 18,
                                                child: CircularProgressIndicator(
                                                  strokeWidth: 2,
                                                  color: OhtliColors.stormyTeal,
                                                ),
                                              ),
                                            ),
                                          );
                                        },
                                        errorBuilder: (context, error, stackTrace) {
                                          return Container(
                                            color: isDark ? const Color(0xFF16161A) : OhtliColors.innerCardBg,
                                            child: Center(
                                              child: Icon(
                                                catIcon,
                                                size: 28,
                                                color: catColor.withOpacity(0.55),
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                      // Gradiente sutil inferior para contraste cinematográfico
                                      Positioned(
                                        bottom: 0,
                                        left: 0,
                                        right: 0,
                                        height: 24,
                                        child: DecoratedBox(
                                          decoration: BoxDecoration(
                                            gradient: LinearGradient(
                                              begin: Alignment.topCenter,
                                              end: Alignment.bottomCenter,
                                              colors: [
                                                Colors.transparent,
                                                Colors.black.withOpacity(0.35),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Expanded(
                                          child: Text(
                                            stopName,
                                            style: GoogleFonts.outfit(
                                              fontSize: 15,
                                              fontWeight: FontWeight.bold,
                                              color: isDark ? Colors.white : OhtliColors.onyx,
                                            ),
                                          ),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: OhtliColors.cempasuchil.withOpacity(0.12),
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Text(
                                            timeLabel,
                                            style: GoogleFonts.inter(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w700,
                                              color: OhtliColors.cempasuchil,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    if (stopPrice > 0) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        '\$${stopPrice.toStringAsFixed(0)} MXN',
                                        style: GoogleFonts.inter(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: OhtliColors.stormyTeal,
                                        ),
                                      ),
                                    ],
                                    if (desc.isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        desc,
                                        style: GoogleFonts.inter(
                                          fontSize: 12,
                                          color: isDark ? Colors.white60 : OhtliColors.subtleText,
                                          height: 1.35,
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
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 28),

          // Botón inferior grande para elegir esta ruta
          Center(
            child: ElevatedButton.icon(
              onPressed: _isSavingTrip ? null : () => _chooseRouteAndCreateTrip(option),
              icon: _isSavingTrip
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
              label: Text(
                _isSavingTrip ? 'Creando viaje...' : 'Elegir esta ruta (\$${cost.toStringAsFixed(0)} MXN)',
                style: GoogleFonts.outfit(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: 0.3,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: OhtliColors.stormyTeal,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                elevation: 4,
              ),
            ),
          ),
        ],
      );

    if (isEmbeddedInCard) {
      return innerContent;
    }

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E22) : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isDark ? Colors.white12 : OhtliColors.cardBorder,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.12),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: EdgeInsets.all(isMobile ? 18 : 28),
      child: innerContent,
    );
  }

  // Mapa Vectorial Cartográfico Real de la Ruta
  Widget _buildVectorRouteMapCanvas(
    List<dynamic> rawStops,
    List<Map<String, dynamic>> validCoords,
    bool isDark,
    bool isMobile,
    String googleMapsUrl,
  ) {
    return Container(
      width: double.infinity,
      height: isMobile ? 240 : 340,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF141418) : const Color(0xFFF1F3F4),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? Colors.white12 : OhtliColors.cardBorder),
      ),
      child: Stack(
        children: [
          // Cuadrícula y Trazado Vectorial de la Ruta
          Positioned.fill(
            child: CustomPaint(
              painter: _RouteVectorMapPainter(
                stops: validCoords.isNotEmpty
                    ? validCoords
                    : rawStops.asMap().entries.map((e) => {
                        'index': e.key + 1,
                        'name': (e.value as Map<String, dynamic>)['name'] ?? 'Lugar ${e.key + 1}',
                        'lat': 19.4326 - (e.key * 0.015),
                        'lng': -99.1332 + (e.key * 0.018),
                      }).toList(),
                isDark: isDark,
              ),
            ),
          ),

          // Badge Superior: Trazado Oficial de Google Maps
          Positioned(
            top: 12,
            left: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: (isDark ? Colors.black : Colors.white).withOpacity(0.85),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: OhtliColors.stormyTeal.withOpacity(0.3)),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 6),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.route_rounded, color: OhtliColors.stormyTeal, size: 14),
                  const SizedBox(width: 6),
                  Text(
                    'Ruta ${validCoords.length > 1 ? "${validCoords.length} paradas conectadas" : "secuencial"} · CDMX',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white : OhtliColors.onyx,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Botón Inferior: Abrir en Google Maps
          if (googleMapsUrl.isNotEmpty)
            Positioned(
              bottom: 12,
              right: 12,
              child: ElevatedButton.icon(
                onPressed: () {
                  html.window.open(googleMapsUrl, '_blank');
                },
                icon: const Icon(Icons.navigation_rounded, size: 14, color: Colors.white),
                label: Text(
                  'Ver ruta en Google Maps',
                  style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: OhtliColors.stormyTeal,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  elevation: 3,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDialogMetaPill(IconData icon, String label, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF26262B) : OhtliColors.innerCardBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: isDark ? Colors.white12 : OhtliColors.cardBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: OhtliColors.stormyTeal),
          const SizedBox(width: 6),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : OhtliColors.onyx,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetaPill(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.4),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white.withOpacity(0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: Colors.white70),
          const SizedBox(width: 4),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

// ==========================================
// PINTOR VECTORIAL CARTOGRÁFICO DE LA RUTA (FALLBACK Y ALTA FIDELIDAD)
// ==========================================
class _RouteVectorMapPainter extends CustomPainter {
  final List<Map<String, dynamic>> stops;
  final bool isDark;

  _RouteVectorMapPainter({
    required this.stops,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final bgPaint = Paint()
      ..color = isDark ? const Color(0xFF141418) : const Color(0xFFF1F3F4);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

    // 1. Cuadrícula cartográfica sutil
    final gridPaint = Paint()
      ..color = (isDark ? Colors.white : Colors.black).withOpacity(0.04)
      ..strokeWidth = 1.0;

    const gridSpacing = 40.0;
    for (double x = 0; x < size.width; x += gridSpacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (double y = 0; y < size.height; y += gridSpacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // 2. Líneas de arterias urbanas estilizadas (CDMX)
    final roadPaint = Paint()
      ..color = (isDark ? Colors.white : Colors.black).withOpacity(0.06)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    final roadPath = Path()
      ..moveTo(0, size.height * 0.3)
      ..quadraticBezierTo(size.width * 0.45, size.height * 0.25, size.width, size.height * 0.65)
      ..moveTo(size.width * 0.2, 0)
      ..quadraticBezierTo(size.width * 0.5, size.height * 0.6, size.width * 0.75, size.height);
    canvas.drawPath(roadPath, roadPaint);

    if (stops.isEmpty) return;

    // 3. Normalizar Coordenadas geográficas a puntos de pantalla
    double minLat = 90.0, maxLat = -90.0;
    double minLng = 180.0, maxLng = -180.0;

    for (final s in stops) {
      final lat = (s['lat'] as num?)?.toDouble() ?? 19.4326;
      final lng = (s['lng'] as num?)?.toDouble() ?? -99.1332;
      if (lat < minLat) minLat = lat;
      if (lat > maxLat) maxLat = lat;
      if (lng < minLng) minLng = lng;
      if (lng > maxLng) maxLng = lng;
    }

    if ((maxLat - minLat).abs() < 0.001) {
      maxLat += 0.01;
      minLat -= 0.01;
    }
    if ((maxLng - minLng).abs() < 0.001) {
      maxLng += 0.01;
      minLng -= 0.01;
    }

    const padding = 54.0;
    final drawWidth = size.width - (padding * 2);
    final drawHeight = size.height - (padding * 2);

    final points = <Offset>[];
    for (final s in stops) {
      final lat = (s['lat'] as num?)?.toDouble() ?? 19.4326;
      final lng = (s['lng'] as num?)?.toDouble() ?? -99.1332;

      // Invertir latitud porque Y crece hacia abajo en la pantalla
      final normalizedX = (lng - minLng) / (maxLng - minLng);
      final normalizedY = 1.0 - ((lat - minLat) / (maxLat - minLat));

      final px = padding + (normalizedX * drawWidth);
      final py = padding + (normalizedY * drawHeight);
      points.add(Offset(px, py));
    }

    // 4. Dibujar Polilínea de la Ruta con Gradiente Luminoso y Glow
    if (points.length > 1) {
      final glowPaint = Paint()
        ..color = OhtliColors.stormyTeal.withOpacity(0.35)
        ..strokeWidth = 10.0
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;

      final routePath = Path()..moveTo(points[0].dx, points[0].dy);
      for (int i = 1; i < points.length; i++) {
        routePath.lineTo(points[i].dx, points[i].dy);
      }
      canvas.drawPath(routePath, glowPaint);

      final linePaint = Paint()
        ..shader = LinearGradient(
          colors: const [OhtliColors.stormyTeal, Color(0xFFE26D5C)],
        ).createShader(Rect.fromPoints(points.first, points.last))
        ..strokeWidth = 5.0
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;

      canvas.drawPath(routePath, linePaint);

      // Flechas de dirección en la polilínea
      final arrowPaint = Paint()
        ..color = Colors.white.withOpacity(0.9)
        ..strokeWidth = 2.0
        ..style = PaintingStyle.stroke;

      for (int i = 0; i < points.length - 1; i++) {
        final p1 = points[i];
        final p2 = points[i + 1];
        final mid = Offset((p1.dx + p2.dx) / 2, (p1.dy + p2.dy) / 2);
        final angle = math.atan2(p2.dy - p1.dy, p2.dx - p1.dx);

        const arrowSize = 6.0;
        final left = Offset(
          mid.dx - arrowSize * math.cos(angle - math.pi / 6),
          mid.dy - arrowSize * math.sin(angle - math.pi / 6),
        );
        final right = Offset(
          mid.dx - arrowSize * math.cos(angle + math.pi / 6),
          mid.dy - arrowSize * math.sin(angle + math.pi / 6),
        );
        canvas.drawLine(left, mid, arrowPaint);
        canvas.drawLine(right, mid, arrowPaint);
      }
    }

    // 5. Dibujar Pines Numerados y Etiquetas
    for (int i = 0; i < points.length; i++) {
      final pt = points[i];
      final isLast = i == points.length - 1;
      final pinColor = isLast ? const Color(0xFFE26D5C) : OhtliColors.stormyTeal;

      // Sombra del marcador
      canvas.drawCircle(
        pt.translate(0, 3),
        15,
        Paint()
          ..color = Colors.black.withOpacity(0.35)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );

      // Círculo exterior blanco
      canvas.drawCircle(pt, 14, Paint()..color = Colors.white);

      // Círculo interior coloreado
      canvas.drawCircle(pt, 12, Paint()..color = pinColor);

      // Número de la parada
      final textPainter = TextPainter(
        text: TextSpan(
          text: '${i + 1}',
          style: GoogleFonts.inter(
            fontSize: 11,
            fontWeight: FontWeight.w900,
            color: Colors.white,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      textPainter.paint(
        canvas,
        Offset(pt.dx - textPainter.width / 2, pt.dy - textPainter.height / 2),
      );

      // Etiqueta de Texto con el nombre de la parada
      final stopName = (stops[i]['name'] ?? 'Parada ${i + 1}').toString();
      final labelSpan = TextSpan(
        text: stopName.length > 20 ? '${stopName.substring(0, 18)}...' : stopName,
        style: GoogleFonts.inter(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: isDark ? Colors.white : OhtliColors.onyx,
        ),
      );
      final labelPainter = TextPainter(
        text: labelSpan,
        textDirection: TextDirection.ltr,
      )..layout();

      final labelOffset = Offset(pt.dx + 18, pt.dy - labelPainter.height / 2);
      final labelRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          labelOffset.dx - 6,
          labelOffset.dy - 3,
          labelPainter.width + 12,
          labelPainter.height + 6,
        ),
        const Radius.circular(6),
      );

      // Fondo de la etiqueta
      canvas.drawRRect(
        labelRect,
        Paint()
          ..color = (isDark ? const Color(0xFF1E1E22) : Colors.white).withOpacity(0.92)
          ..style = PaintingStyle.fill,
      );
      canvas.drawRRect(
        labelRect,
        Paint()
          ..color = OhtliColors.stormyTeal.withOpacity(0.3)
          ..strokeWidth = 1.0
          ..style = PaintingStyle.stroke,
      );
      labelPainter.paint(canvas, labelOffset);
    }
  }

  @override
  bool shouldRepaint(covariant _RouteVectorMapPainter oldDelegate) {
    return oldDelegate.stops != stops || oldDelegate.isDark != isDark;
  }
}

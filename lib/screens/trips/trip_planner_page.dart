// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use, avoid_print

import 'dart:async';
import 'dart:html' as html;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/poi_model.dart';
import '../../models/trip_model.dart';
import '../../services/itinerary_blackboard_service.dart';
import '../../theme/colors.dart';
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
  late PageController _triadPageController;
  int _activeCarouselIndex = 0;

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
    _triadPageController = PageController(viewportFraction: 0.88);
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
    }
  }

  @override
  void dispose() {
    _jobSubscription?.cancel();
    _triadPageController.dispose();
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
              _activeCarouselIndex = 0;
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
                  maxWidth: _currentStep == PlannerStep.routeTriadCarousel ? 1160 : 780,
                ),
                child: SingleChildScrollView(
                  padding: EdgeInsets.symmetric(
                    horizontal: isMobile ? 16 : 24,
                    vertical: isMobile ? 16 : 28,
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
  // PASO 4: SELECTOR CINEMATOGRÁFICO DE MULTIRUTAS (TRÍADA)
  // ==========================================
  Widget _buildRouteTriadCarouselStep(bool isMobile) {
    if (_generatedOptions.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Indicador de Paginación superior / Controles
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
              Row(
                children: List.generate(_generatedOptions.length, (idx) {
                  final isSelected = _activeCarouselIndex == idx;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: isSelected ? 24 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: isSelected ? OhtliColors.stormyTeal : OhtliColors.cardBorder,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  );
                }),
              ),
            ],
          ),
        ),

        // Carrusel cinematográfico de multirutas
        SizedBox(
          height: isMobile ? 520 : 580,
          child: PageView.builder(
            controller: _triadPageController,
            itemCount: _generatedOptions.length,
            onPageChanged: (idx) {
              setState(() => _activeCarouselIndex = idx);
            },
            itemBuilder: (context, index) {
              final option = _generatedOptions[index];
              final isFocused = _activeCarouselIndex == index;
              return AnimatedScale(
                scale: isFocused ? 1.0 : 0.94,
                duration: const Duration(milliseconds: 350),
                curve: Curves.easeOutCubic,
                child: _buildRouteCard(option, isFocused, isMobile, index),
              );
            },
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildRouteCard(
    Map<String, dynamic> option,
    bool isFocused,
    bool isMobile,
    int index,
  ) {
    final title = (option['editorial_headline'] ?? option['theme'] ?? 'Ruta ${index + 1}').toString();
    final summary = (option['narrative_summary'] ?? '').toString();
    final cost = (option['total_cost_mxn'] as num?)?.toDouble() ?? 250.0;
    final timeMins = (option['estimated_time_mins'] as num?)?.toInt() ?? 180;
    final List<dynamic> stops = option['route'] ?? [];
    final coverUrl = option['cover_url'] ??
        (stops.isNotEmpty ? stops[0]['photo_url'] : null) ??
        'https://images.unsplash.com/photo-1518638150340-f706e86654de?auto=format&fit=crop&w=1200&q=80';

    final int hours = timeMins ~/ 60;
    final int minutes = timeMins % 60;
    final String timeStr = hours > 0 ? '$hours h $minutes min' : '$minutes min';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isFocused ? Colors.white.withOpacity(0.3) : Colors.white.withOpacity(0.08),
          width: isFocused ? 1.5 : 1.0,
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
            // 1. Fotografía de fondo
            Positioned.fill(
              child: Image.network(
                coverUrl,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Container(color: const Color(0xFF1E1E22)),
              ),
            ),

            // 2. Gradiente Cinematográfico Oscuro
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.black.withOpacity(0.2),
                      Colors.black.withOpacity(0.65),
                      Colors.black.withOpacity(0.95),
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: const [0.0, 0.45, 1.0],
                  ),
                ),
              ),
            ),

            // 3. Contenido de la Tarjeta
            Positioned.fill(
              child: Padding(
                padding: EdgeInsets.all(isMobile ? 18 : 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    // Badge Superior de Opción
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: OhtliColors.stormyTeal,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'OPCIÓN ${index + 1} · ${(option['theme'] ?? 'EXPERIENCIA').toString().toUpperCase()}',
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.0,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Título Grande y Bold
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
                    const SizedBox(height: 12),

                    // Sinopsis Narrativa / Storytelling
                    Text(
                      summary,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: Colors.white.withOpacity(0.85),
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Preview de Paradas Cronológicas
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: stops.asMap().entries.map((entry) {
                          final i = entry.key;
                          final stop = entry.value as Map<String, dynamic>;
                          final stopName = (stop['name'] ?? 'Lugar').toString();
                          return InkWell(
                            onTap: () => _showRouteMapAndChronologyDialog(option, index),
                            borderRadius: BorderRadius.circular(6),
                            child: Container(
                              margin: const EdgeInsets.only(right: 6),
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    '${i + 1}. ',
                                    style: GoogleFonts.inter(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                      color: OhtliColors.stormyTeal,
                                    ),
                                  ),
                                  Text(
                                    stopName.length > 20 ? '${stopName.substring(0, 18)}...' : stopName,
                                    style: GoogleFonts.inter(
                                      fontSize: 10,
                                      color: Colors.white,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: 18),

                    // Botones de Acción
                    Wrap(
                      spacing: 10,
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
                              fontSize: isMobile ? 13 : 15,
                              fontWeight: FontWeight.w800,
                              color: Colors.black,
                              letterSpacing: 0.2,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: Colors.black,
                            padding: EdgeInsets.symmetric(
                              horizontal: isMobile ? 16 : 22,
                              vertical: isMobile ? 12 : 15,
                            ),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                            elevation: 8,
                          ),
                        ),
                        ElevatedButton.icon(
                          onPressed: () => _showRouteMapAndChronologyDialog(option, index),
                          icon: const Icon(Icons.map_rounded, color: Colors.white, size: 16),
                          label: Text(
                            'Ver Mapa y Cronología',
                            style: GoogleFonts.inter(
                              fontSize: isMobile ? 12 : 13,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white.withOpacity(0.18),
                            foregroundColor: Colors.white,
                            padding: EdgeInsets.symmetric(
                              horizontal: isMobile ? 14 : 18,
                              vertical: isMobile ? 12 : 15,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30),
                              side: BorderSide(color: Colors.white.withOpacity(0.35)),
                            ),
                            elevation: 0,
                          ),
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
                          icon: const Icon(Icons.bookmark_add_outlined, color: Colors.white),
                          tooltip: 'Guardar alternativa',
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.white.withOpacity(0.12),
                            padding: const EdgeInsets.all(12),
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
      ),
    );
  }

  void _showRouteMapAndChronologyDialog(Map<String, dynamic> option, int index) {
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

    final markers = StringBuffer();
    final path = StringBuffer('&path=color:0x2F6B6Bff|weight:5');
    final waypointNames = <String>[];

    for (int i = 0; i < rawStops.length; i++) {
      final s = rawStops[i] as Map<String, dynamic>;
      final label = (i + 1).toString();
      double? lat = (s['lat'] as num?)?.toDouble();
      double? lng = (s['lng'] as num?)?.toDouble();
      if (lat == null && s['location'] is Map) {
        lat = (s['location']['lat'] as num?)?.toDouble();
        lng = (s['location']['lng'] as num?)?.toDouble();
      }

      if (lat != null && lng != null) {
        markers.write('&markers=color:0xE26D5C|label:$label|$lat,$lng');
        path.write('|$lat,$lng');
        waypointNames.add('$lat,$lng');
      } else {
        final stopName = Uri.encodeComponent('${s['name'] ?? 'Lugar'}, CDMX');
        markers.write('&markers=color:0xE26D5C|label:$label|$stopName');
        waypointNames.add(stopName);
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

    showDialog(
      context: context,
      builder: (ctx) {
        final isMobile = MediaQuery.of(ctx).size.width < 768;

        return Dialog(
          backgroundColor: isDark ? const Color(0xFF1E1E22) : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          insetPadding: EdgeInsets.symmetric(
            horizontal: isMobile ? 16 : 40,
            vertical: isMobile ? 24 : 40,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820, maxHeight: 780),
            child: Column(
              children: [
                // Header del Dialog
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 20, 16, 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: OhtliColors.stormyTeal,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                'OPCIÓN ${index + 1} · ${(option['theme'] ?? 'EXPERIENCIA').toString().toUpperCase()}',
                                style: GoogleFonts.inter(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1.0,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              title,
                              style: GoogleFonts.outfit(
                                fontSize: isMobile ? 18 : 22,
                                fontWeight: FontWeight.bold,
                                color: isDark ? Colors.white : OhtliColors.onyx,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        icon: Icon(Icons.close_rounded, color: isDark ? Colors.white70 : OhtliColors.onyx),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),

                // Contenido Scrollable
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Badges de Metadatos
                        Row(
                          children: [
                            _buildDialogMetaPill(Icons.schedule_rounded, timeStr, isDark),
                            const SizedBox(width: 8),
                            _buildDialogMetaPill(Icons.payments_outlined, '\$${cost.toStringAsFixed(0)} MXN', isDark),
                            const SizedBox(width: 8),
                            _buildDialogMetaPill(Icons.place_rounded, '${rawStops.length} paradas', isDark),
                          ],
                        ),
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

                        // Sección: Mapa de la Ruta
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
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
                            if (googleMapsDirectionsUrl.isNotEmpty)
                              TextButton.icon(
                                onPressed: () {
                                  html.window.open(googleMapsDirectionsUrl, '_blank');
                                },
                                icon: const Icon(Icons.open_in_new_rounded, size: 14),
                                label: Text(
                                  'Abrir en Google Maps',
                                  style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold),
                                ),
                                style: TextButton.styleFrom(
                                  foregroundColor: OhtliColors.stormyTeal,
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // Visual del Mapa
                        ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: staticMapUrl.isNotEmpty
                              ? Image.network(
                                  staticMapUrl,
                                  width: double.infinity,
                                  height: isMobile ? 200 : 260,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) =>
                                      _buildFallbackOptionMap(rawStops, isDark),
                                )
                              : _buildFallbackOptionMap(rawStops, isDark),
                        ),
                        const SizedBox(height: 28),

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

                        // Timeline vertical
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
                            final photo = (stop['photo_url'] ?? stop['main_photo_url'] ?? '').toString();

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

                                  // Columna Derecha: Detalle
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
                                            if (photo.isNotEmpty)
                                              ClipRRect(
                                                borderRadius: BorderRadius.circular(10),
                                                child: Image.network(
                                                  photo,
                                                  width: 56,
                                                  height: 56,
                                                  fit: BoxFit.cover,
                                                  errorBuilder: (context, error, stackTrace) =>
                                                      const SizedBox.shrink(),
                                                ),
                                              ),
                                            if (photo.isNotEmpty) const SizedBox(width: 12),
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
                      ],
                    ),
                  ),
                ),
                const Divider(height: 1),

                // Footer de Acciones
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        child: Text(
                          'Cerrar',
                          style: GoogleFonts.inter(
                            color: isDark ? Colors.white60 : OhtliColors.subtleText,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton.icon(
                        onPressed: _isSavingTrip
                            ? null
                            : () {
                                Navigator.of(ctx).pop();
                                _chooseRouteAndCreateTrip(option);
                              },
                        icon: const Icon(Icons.check_circle_rounded, size: 18),
                        label: Text(
                          'Elegir esta opción (\$${cost.toStringAsFixed(0)} MXN)',
                          style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: OhtliColors.stormyTeal,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          elevation: 0,
                        ),
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

  Widget _buildFallbackOptionMap(List<dynamic> stops, bool isDark) {
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
              'Ruta secuencial con ${stops.length} paradas programadas',
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

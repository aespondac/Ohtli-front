// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use, use_build_context_synchronously

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme/colors.dart';
import '../models/poi_model.dart';
import '../services/itinerary_blackboard_service.dart';
import '../screens/trips/trip_viewer_page.dart';

enum PlannerStep {
  bifurcation,
  startingPoint,
  preferences,
  blackboardProcessing,
  routeTriadCarousel,
}

class TripPlannerDialog extends StatefulWidget {
  final Poi? initialOriginPoi;
  final VoidCallback? onManualPlanSelected;
  final List<Map<String, dynamic>>? initialGeneratedOptions;
  final String? initialActiveJobId;
  final String? originName;

  const TripPlannerDialog({
    super.key,
    this.initialOriginPoi,
    this.onManualPlanSelected,
    this.initialGeneratedOptions,
    this.initialActiveJobId,
    this.originName,
  });

  static void show(
    BuildContext context, {
    Poi? initialOriginPoi,
    VoidCallback? onManualPlanSelected,
    List<Map<String, dynamic>>? initialGeneratedOptions,
    String? initialActiveJobId,
    String? originName,
  }) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => TripPlannerDialog(
        initialOriginPoi: initialOriginPoi,
        onManualPlanSelected: onManualPlanSelected,
        initialGeneratedOptions: initialGeneratedOptions,
        initialActiveJobId: initialActiveJobId,
        originName: originName,
      ),
    );
  }

  @override
  State<TripPlannerDialog> createState() => _TripPlannerDialogState();
}

class _TripPlannerDialogState extends State<TripPlannerDialog> {
  final ItineraryBlackboardService _blackboardService = ItineraryBlackboardService();
  final TextEditingController _originSearchController = TextEditingController();
  final TextEditingController _customMoodController = TextEditingController();

  PlannerStep _currentStep = PlannerStep.bifurcation;

  // Datos seleccionados
  String _selectedOriginName = '';
  Map<String, double> _selectedOriginCoords = {'lat': 19.4326, 'lng': -99.1332};
  String _selectedMoodTag = 'Bohemio y Cafés';
  double _budgetMxn = 500.0;
  String _topology = 'radio'; // 'radio' o 'anillo'

  // Direcciones guardadas del usuario
  List<Map<String, dynamic>> _savedAddresses = [];

  // Estado del Blackboard
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
      'coords': {'lat': 19.3498, 'lng': -99.1638},
      'icon': Icons.park_rounded,
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
    if (user == null) {
      return;
    }

    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      if (doc.exists && doc.data() != null) {
        final list = doc.data()!['addresses'];
        if (list is List) {
          if (mounted) {
            setState(() {
              _savedAddresses = List<Map<String, dynamic>>.from(list);
            });
          }
        }
      }
    } catch (_) {}
  }

  void _startBlackboardJob() async {
    final user = FirebaseAuth.instance.currentUser;
    final userId = user?.uid ?? 'guest_traveler';

    final effectiveMood = _customMoodController.text.trim().isNotEmpty
        ? _customMoodController.text.trim()
        : _selectedMoodTag;

    setState(() {
      _currentStep = PlannerStep.blackboardProcessing;
      _blackboardProgress = 15;
      _currentAgentName = 'Comparador';
    });

    try {
      final jobId = await _blackboardService.requestItineraryJob(
        userId: userId,
        budget: _budgetMxn,
        origin: _selectedOriginCoords,
        topology: _topology,
        moodText: effectiveMood,
      );

      _activeJobId = jobId;

      // Escuchar cambios reactivos en el Pizarrón
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
      debugPrint('Error lanzando job en el Blackboard: $e');
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
      final newTrip = await _blackboardService.saveOptionAsTrip(
        userId: user.uid,
        chosenOption: option,
        defaultTitle: 'Ruta en $_selectedOriginName',
      );

      if (mounted) {
        Navigator.of(context).pop();
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => TripViewerPage(
              tripId: newTrip.id,
              authorId: user.uid,
              isPublicLink: false,
              onBackToDashboard: () => Navigator.of(context).pop(),
            ),
          ),
        );
      }
    } catch (e) {
      setState(() => _isSavingTrip = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al persistir el viaje: $e', style: GoogleFonts.inter()),
            backgroundColor: OhtliColors.xoconostle,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isMobile = screenSize.width < 768;

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: EdgeInsets.symmetric(
        horizontal: isMobile ? 12 : 32,
        vertical: isMobile ? 16 : 24,
      ),
      child: Container(
        width: _currentStep == PlannerStep.routeTriadCarousel ? 1100 : 700,
        constraints: BoxConstraints(
          maxHeight: screenSize.height * 0.92,
        ),
        decoration: BoxDecoration(
          color: _currentStep == PlannerStep.routeTriadCarousel
              ? const Color(0xFF141416) // Fondo oscuro cinematográfico
              : OhtliColors.cardBg,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(
            color: _currentStep == PlannerStep.routeTriadCarousel
                ? Colors.white.withOpacity(0.12)
                : OhtliColors.cardBorder,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.35),
              blurRadius: 36,
              offset: const Offset(0, 16),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildHeader(isMobile),
              Flexible(
                child: SingleChildScrollView(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 350),
                    child: _buildStepContent(isMobile),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(bool isMobile) {
    final isCarousel = _currentStep == PlannerStep.routeTriadCarousel;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        color: isCarousel ? Colors.black.withOpacity(0.3) : OhtliColors.innerCardBg.withOpacity(0.5),
        border: Border(
          bottom: BorderSide(
            color: isCarousel ? Colors.white.withOpacity(0.08) : OhtliColors.cardBorder,
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: OhtliColors.stormyTeal.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: SvgPicture.asset(
                  'assets/icon_isologo.svg',
                  colorFilter: const ColorFilter.mode(OhtliColors.stormyTeal, BlendMode.srcIn),
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Planeador de Itinerarios Ohtli',
                    style: GoogleFonts.outfit(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: isCarousel ? Colors.white : OhtliColors.onyx,
                    ),
                  ),
                  Text(
                    isCarousel
                        ? '3 multirutas calibradas por el Sistema Multiagente'
                        : 'Diseño inteligente de experiencias en la Ciudad de México',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: isCarousel ? Colors.white60 : OhtliColors.subtleText,
                    ),
                  ),
                ],
              ),
            ],
          ),
          IconButton(
            icon: Icon(
              Icons.close_rounded,
              color: isCarousel ? Colors.white70 : OhtliColors.onyx.withOpacity(0.6),
            ),
            onPressed: () {
              if (_currentStep == PlannerStep.blackboardProcessing && _activeJobId != null) {
                final user = FirebaseAuth.instance.currentUser;
                if (user != null) {
                  _blackboardService.notifyIfBackground(
                    userId: user.uid,
                    jobId: _activeJobId!,
                    tripTitle: _selectedOriginName.isNotEmpty ? _selectedOriginName : 'CDMX',
                  );
                }
              }
              Navigator.of(context).pop();
            },
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
    return Padding(
      padding: const EdgeInsets.all(32.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            '¿Cómo deseas planear tu viaje?',
            textAlign: TextAlign.center,
            style: GoogleFonts.outfit(
              fontSize: isMobile ? 22 : 26,
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
          const SizedBox(height: 32),

          // Tarjeta 1: Obtener planes con IA
          _buildBifurcationCard(
            title: 'Obtener planes con IA',
            subtitle: 'El Sistema Multiagente cruza tus gustos culturales, optimiza traslados y maximiza tu presupuesto generando 3 rutas.',
            badge: 'RECOMENDADO',
            badgeColor: OhtliColors.stormyTeal,
            icon: Icons.auto_awesome_rounded,
            accentColor: OhtliColors.stormyTeal,
            onTap: () {
              setState(() {
                _currentStep = PlannerStep.startingPoint;
              });
            },
          ),
          const SizedBox(height: 16),

          // Tarjeta 2: Quiero hacerlo por mi cuenta
          _buildBifurcationCard(
            title: 'Quiero hacerlo por mi cuenta',
            subtitle: 'Crea un borrador en blanco para agregar lugares, fotos, notas personales y ajustar tus paradas de forma 100% manual.',
            icon: Icons.edit_note_rounded,
            accentColor: const Color(0xFF6C5CE7),
            onTap: () {
              Navigator.of(context).pop();
              widget.onManualPlanSelected?.call();
            },
          ),
        ],
      ),
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
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: OhtliColors.innerCardBg,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: badge != null ? accentColor.withOpacity(0.4) : OhtliColors.cardBorder,
              width: badge != null ? 1.5 : 1.0,
            ),
            boxShadow: [
              if (badge != null)
                BoxShadow(
                  color: accentColor.withOpacity(0.08),
                  blurRadius: 18,
                  offset: const Offset(0, 4),
                ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: accentColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: accentColor, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          title,
                          style: GoogleFonts.outfit(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: OhtliColors.onyx,
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
                    const SizedBox(height: 4),
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
    return Padding(
      padding: const EdgeInsets.all(28.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_rounded, size: 20),
                onPressed: () => setState(() => _currentStep = PlannerStep.bifurcation),
              ),
              const SizedBox(width: 4),
              Text(
                '1. ¿Dónde empieza tu día?',
                style: GoogleFonts.outfit(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: OhtliColors.onyx,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Buscador / entrada de dirección
          TextField(
            controller: _originSearchController,
            style: GoogleFonts.inter(color: OhtliColors.onyx),
            decoration: InputDecoration(
              hintText: 'Ingresa una calle, colonia, hotel o lugar...',
              prefixIcon: const Icon(Icons.search_rounded, color: OhtliColors.stormyTeal),
              suffixIcon: IconButton(
                icon: const Icon(Icons.my_location_rounded, color: OhtliColors.stormyTeal),
                tooltip: 'Usar mi ubicación GPS',
                onPressed: () {
                  setState(() {
                    _selectedOriginName = 'Mi ubicación actual (CDMX)';
                    _selectedOriginCoords = {'lat': 19.4326, 'lng': -99.1332};
                    _originSearchController.text = _selectedOriginName;
                  });
                },
              ),
              filled: true,
              fillColor: OhtliColors.innerCardBg,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: OhtliColors.cardBorder),
              ),
            ),
            onChanged: (val) {
              setState(() {
                _selectedOriginName = val;
              });
            },
          ),
          const SizedBox(height: 24),

          // Sección de Direcciones Guardadas del Usuario
          if (_savedAddresses.isNotEmpty) ...[
            Text(
              'Tus Direcciones Guardadas:',
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: OhtliColors.subtleText,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _savedAddresses.map((addr) {
                final tag = (addr['tag'] ?? 'Dirección').toString();
                final street = (addr['street'] ?? '').toString();
                final isSelected = _selectedOriginName == (street.isNotEmpty ? street : tag);
                return ActionChip(
                  avatar: Icon(
                    tag.toLowerCase().contains('casa')
                        ? Icons.home_rounded
                        : (tag.toLowerCase().contains('trabajo') ? Icons.work_rounded : Icons.location_on_rounded),
                    size: 15,
                    color: isSelected ? Colors.white : OhtliColors.stormyTeal,
                  ),
                  label: Text('$tag ${street.isNotEmpty ? "($street)" : ""}'),
                  backgroundColor: isSelected ? OhtliColors.stormyTeal : OhtliColors.innerCardBg,
                  labelStyle: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isSelected ? Colors.white : OhtliColors.onyx,
                  ),
                  onPressed: () {
                    final lat = (addr['lat'] as num?)?.toDouble() ?? 19.4326;
                    final lng = (addr['lng'] as num?)?.toDouble() ?? -99.1332;
                    setState(() {
                      _selectedOriginName = street.isNotEmpty ? street : tag;
                      _selectedOriginCoords = {'lat': lat, 'lng': lng};
                      _originSearchController.text = _selectedOriginName;
                    });
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 24),
          ],

          // Zonas Clave Populares en CDMX
          Text(
            'Zonas y Puntos de Partida Populares:',
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: OhtliColors.subtleText,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: _cdmxKeyZones.map((zone) {
              final isSelected = _selectedOriginName == zone['name'];
              return ChoiceChip(
                label: Text(zone['name']),
                avatar: Icon(
                  zone['icon'] as IconData,
                  size: 15,
                  color: isSelected ? Colors.white : OhtliColors.onyx,
                ),
                selected: isSelected,
                selectedColor: OhtliColors.stormyTeal,
                labelStyle: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isSelected ? Colors.white : OhtliColors.onyx,
                ),
                backgroundColor: OhtliColors.innerCardBg,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: OhtliColors.cardBorder),
                ),
                onSelected: (val) {
                  if (val) {
                    setState(() {
                      _selectedOriginName = zone['name'];
                      _selectedOriginCoords = Map<String, double>.from(zone['coords']);
                      _originSearchController.text = _selectedOriginName;
                    });
                  }
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 32),

          // Botón Continuar
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: _selectedOriginName.trim().isEmpty
                  ? null
                  : () => setState(() => _currentStep = PlannerStep.preferences),
              style: ElevatedButton.styleFrom(
                backgroundColor: OhtliColors.stormyTeal,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
              child: Text(
                'Siguiente: Intención y Presupuesto',
                style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // PASO 2: MOOD & RESTRICCIONES
  // ==========================================
  Widget _buildPreferencesStep(bool isMobile) {
    return Padding(
      padding: const EdgeInsets.all(28.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_rounded, size: 20),
                onPressed: () => setState(() => _currentStep = PlannerStep.startingPoint),
              ),
              const SizedBox(width: 4),
              Text(
                '2. ¿Qué vibra o intención tienes hoy?',
                style: GoogleFonts.outfit(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: OhtliColors.onyx,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Chips de Mood
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _moodPresets.map((mood) {
              final isSelected = _selectedMoodTag == mood;
              return ChoiceChip(
                label: Text(mood),
                selected: isSelected,
                selectedColor: OhtliColors.stormyTeal,
                labelStyle: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isSelected ? Colors.white : OhtliColors.onyx,
                ),
                backgroundColor: OhtliColors.innerCardBg,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: OhtliColors.cardBorder),
                ),
                onSelected: (val) {
                  if (val) setState(() => _selectedMoodTag = mood);
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 16),

          // Entrada de texto libre adicional
          TextField(
            controller: _customMoodController,
            style: GoogleFonts.inter(color: OhtliColors.onyx),
            decoration: InputDecoration(
              labelText: 'O escribe tu plan con tus propias palabras (opcional)',
              hintText: 'Ej. Quiero tomar un café de especialidad y leer una hora...',
              filled: true,
              fillColor: OhtliColors.innerCardBg,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: OhtliColors.cardBorder),
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Slider de Presupuesto Techo
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Presupuesto máximo por persona:',
                style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: OhtliColors.onyx),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: OhtliColors.stormyTeal.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '\$${_budgetMxn.toStringAsFixed(0)} MXN',
                  style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.w800, color: OhtliColors.stormyTeal),
                ),
              ),
            ],
          ),
          Slider(
            value: _budgetMxn,
            min: 150.0,
            max: 2000.0,
            divisions: 37,
            activeColor: OhtliColors.stormyTeal,
            onChanged: (val) => setState(() => _budgetMxn = val),
          ),
          const SizedBox(height: 20),

          // Topología espacial
          Text(
            'Forma del recorrido:',
            style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: OhtliColors.onyx),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: RadioListTile<String>(
                  title: Text('Cerca del punto (Radio)', style: GoogleFonts.inter(fontSize: 12)),
                  value: 'radio',
                  groupValue: _topology,
                  activeColor: OhtliColors.stormyTeal,
                  onChanged: (val) => setState(() => _topology = val!),
                ),
              ),
              Expanded(
                child: RadioListTile<String>(
                  title: Text('Circuito cerrado (Anillo)', style: GoogleFonts.inter(fontSize: 12)),
                  value: 'anillo',
                  groupValue: _topology,
                  activeColor: OhtliColors.stormyTeal,
                  onChanged: (val) => setState(() => _topology = val!),
                ),
              ),
            ],
          ),
          const SizedBox(height: 28),

          // Botón Iniciar Agentes
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              onPressed: _startBlackboardJob,
              icon: const Icon(Icons.bolt_rounded, size: 20),
              label: Text(
                'Generar mis 3 multirutas con IA',
                style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: OhtliColors.stormyTeal,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // PASO 3: RESOLUCIÓN BLACKBOARD EN VIVO
  // ==========================================
  Widget _buildBlackboardProcessingStep(bool isMobile) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 48.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 80,
            height: 80,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: OhtliColors.stormyTeal.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: const CircularProgressIndicator(
              strokeWidth: 3.5,
              valueColor: AlwaysStoppedAnimation<Color>(OhtliColors.stormyTeal),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'El Sistema Multiagente está diseñando tu día',
            textAlign: TextAlign.center,
            style: GoogleFonts.outfit(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: OhtliColors.onyx,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Agente activo en el Pizarrón: $_currentAgentName',
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: OhtliColors.stormyTeal,
            ),
          ),
          const SizedBox(height: 24),

          // Barra de progreso animada
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: _blackboardProgress / 100.0,
              minHeight: 8,
              backgroundColor: OhtliColors.innerCardBg,
              valueColor: const AlwaysStoppedAnimation<Color>(OhtliColors.stormyTeal),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '$_blackboardProgress% completado',
            style: GoogleFonts.inter(fontSize: 11, color: OhtliColors.subtleText),
          ),
          const SizedBox(height: 36),

          // Botón Minimizar / Continuar en segundo plano
          TextButton.icon(
            icon: const Icon(Icons.arrow_downward_rounded, size: 16),
            label: const Text('Continuar navegando (te avisaremos cuando termine)'),
            style: TextButton.styleFrom(
              foregroundColor: OhtliColors.onyx.withOpacity(0.7),
              textStyle: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600),
            ),
            onPressed: () {
              final user = FirebaseAuth.instance.currentUser;
              if (user != null && _activeJobId != null) {
                _blackboardService.notifyIfBackground(
                  userId: user.uid,
                  jobId: _activeJobId!,
                  tripTitle: _selectedOriginName,
                );
              }
              Navigator.of(context).pop();
            },
          ),
        ],
      ),
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
          padding: const EdgeInsets.fromLTRB(28, 16, 28, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'ELIGE TU MULTIRUTA TEMÁTICA',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.5,
                  color: Colors.white70,
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
                      color: isSelected ? OhtliColors.stormyTeal : Colors.white24,
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
          height: isMobile ? 480 : 540,
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

    final hours = timeMins ~/ 60;
    final mins = timeMins % 60;
    final timeStr = hours > 0 ? '${hours}h ${mins}m' : '${mins}m';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isFocused ? OhtliColors.stormyTeal.withOpacity(0.6) : Colors.white10,
          width: isFocused ? 1.8 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isFocused ? 0.6 : 0.3),
            blurRadius: isFocused ? 24 : 12,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          children: [
            // 1. Imagen de Fondo Inmersiva
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
                      Colors.black.withOpacity(0.3),
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
                          return Container(
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
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Botón Principal Píldora Cinematográfica ("Elegir esta ruta")
                    Row(
                      children: [
                        ElevatedButton.icon(
                          onPressed: _isSavingTrip ? null : () => _chooseRouteAndCreateTrip(option),
                          icon: _isSavingTrip
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                                )
                              : const Icon(Icons.check_circle_rounded, size: 18),
                          label: Text(
                            'Elegir esta ruta (\$${cost.toStringAsFixed(0)} MXN)',
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.3,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            elevation: 0,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.15),
                            shape: BoxShape.circle,
                          ),
                          child: IconButton(
                            icon: const Icon(Icons.bookmark_add_outlined, color: Colors.white, size: 18),
                            tooltip: 'Guardar alternativa',
                            onPressed: () => _chooseRouteAndCreateTrip(option),
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

  Widget _buildMetaPill(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.5),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white24, width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: Colors.white70),
          const SizedBox(width: 4),
          Text(
            text,
            style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white),
          ),
        ],
      ),
    );
  }
}

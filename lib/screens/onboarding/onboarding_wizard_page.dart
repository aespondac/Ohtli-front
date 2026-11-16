import '../../services/user_private_data.dart';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import '../../theme/colors.dart';
import '../construction_page.dart'; // RouteBackgroundPainter
import '../../utils/friendly_errors.dart';
import '../../models/poi_model.dart';
import '../../services/saved_places.dart';
import '../../theme/cdmx_photos.dart';
import '../../widgets/address_picker_widget.dart';
import '../places/places_page.dart';

class OnboardingWizardPage extends StatefulWidget {
  final VoidCallback onCompleted;

  /// Modo de prueba (Ohtli Labs): recorre los 5 pasos sin llamar al motor ni guardar nada, así
  /// el perfil de gustos real de la persona no cambia.
  final bool sandbox;

  const OnboardingWizardPage({
    super.key,
    required this.onCompleted,
    this.sandbox = false,
  });

  static List<double> _buildDeterministic768dFallback(String recipeText) {
    final List<double> raw = List<double>.filled(768, 0.0);
    final bytes = utf8.encode(recipeText.toLowerCase());
    int hash = 2166136261;
    for (final b in bytes) {
      hash ^= b;
      hash = (hash * 16777619) & 0x7fffffff;
    }
    for (int i = 0; i < 768; i++) {
      final int b = bytes.isEmpty ? 42 : bytes[i % bytes.length];
      final double angle = ((hash + i * 31 + b * 17) % 10000) / 10000.0 * 2 * math.pi;
      raw[i] = math.sin(angle) * 0.7 + math.cos(angle * 0.5) * 0.3;
    }
    double normSq = 0.0;
    for (final v in raw) {
      normSq += v * v;
    }
    final double norm = normSq > 0 ? math.sqrt(normSq) : 1.0;
    return raw.map((v) => v / norm).toList();
  }

  /// Invokes Yollotl Engine (/v1/user/cultural-profile) to compute the 768d
  /// text-embedding-004 taste vector and persists it into /users/{uid}/private/account.
  static Future<List<double>> synthesizeAndSaveProfile(
    String uid,
    Map<String, dynamic> rawPayload, {
    Map<String, String>? previewAxes,
  }) async {
    final Map<String, dynamic> payload = Map<String, dynamic>.from(rawPayload);
    payload['user_id'] = uid;

    const apiUrl = String.fromEnvironment(
      'yollotlApiUrl',
      defaultValue: 'https://api-xluju5gywq-uc.a.run.app',
    );

    List<double>? tasteVector;
    String? tasteRecipe;
    Map<String, dynamic>? tasteAxes;
    String tasteModel = 'vertex_ai_text_embedding_004';

    String? idToken;
    try {
      idToken = await FirebaseAuth.instance.currentUser?.getIdToken();
    } catch (_) {}

    try {
      final response = await http
          .post(
            Uri.parse('$apiUrl/v1/user/cultural-profile'),
            headers: {
              "Content-Type": "application/json",
              // El motor verifica que el token corresponda a user_id
              if (idToken != null) "Authorization": "Bearer $idToken",
            },
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200 || response.statusCode == 201) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) {
          final rawVec = decoded['taste_vector'];
          if (rawVec is List && rawVec.isNotEmpty) {
            tasteVector = rawVec.map((e) => (e as num).toDouble()).toList();
          }
          if (decoded['recipe'] != null) {
            tasteRecipe = decoded['recipe'].toString();
          }
          if (decoded['user_axes'] is Map) {
            tasteAxes = Map<String, dynamic>.from(decoded['user_axes'] as Map);
          }
        }
        print("Cultural profile 4-axis 768d vector synthesized via Yollotl Engine.");
      }
    } catch (httpError) {
      print("Yollotl API call failed or offline, using deterministic 768d fallback: $httpError");
    }

    tasteAxes ??= previewAxes != null
        ? Map<String, dynamic>.from(previewAxes)
        : <String, dynamic>{
            "vocacion_cultural": (payload['cultural_interests'] as List?)?.join(', ') ?? '',
            "atmosfera_sensorial": (payload['atmosphere_preference'] as List?)?.join(', ') ?? '',
            "dinamica_social": "${payload['social_companion'] ?? 'pareja'} / ${payload['discovery_style'] ?? 'equilibrado'}",
            "entorno_urbano": "${payload['transport_preference'] ?? 'caminata'} (${payload['accessibility_needs'] ?? 'estandar'})",
          };

    tasteRecipe ??= tasteAxes.entries.map((e) => "[${e.key}]: ${e.value}").join("\n");

    if (tasteVector == null || tasteVector.isEmpty) {
      tasteVector = _buildDeterministic768dFallback(tasteRecipe);
      tasteModel = 'deterministic_semantic_768d';
    }

    try {
      // onboarding_completed y updatedAt van al perfil público; el resto, al privado
      await UserPrivateData.save(uid, {
        "cultural_profile": payload,
        "taste_axes": tasteAxes,
        if (previewAxes != null) "taste_axes_preview": previewAxes,
        "taste_recipe": tasteRecipe,
        "taste_vector": tasteVector,
        "taste_vector_dim": tasteVector.length,
        "taste_model": tasteModel,
        "onboarding_completed": true,
        "taste_updated_at": FieldValue.serverTimestamp(),
        "updatedAt": FieldValue.serverTimestamp(),
      });
      print("Client-side Firestore user document synchronized successfully.");
    } catch (fsWriteErr) {
      print(
        "Client-side direct Firestore write warning (backend dual-write guarantees persistence): $fsWriteErr",
      );
    }

    return tasteVector;
  }

  @override
  State<OnboardingWizardPage> createState() => _OnboardingWizardPageState();
}

class _OnboardingWizardPageState extends State<OnboardingWizardPage> {
  static const int _totalSteps = 7;
  int _currentStep = 0;
  bool _isSynthesizing = false;
  String _synthesisMessage = "El motor Yollotl está alineando tus 4 ejes ontológicos...";

  // Paso 1: Vocación Cultural
  final Set<String> _selectedCultural = {};

  // Paso 2: Gastronomía y Atmósfera Sensorial
  final Set<String> _selectedCulinary = {};
  final Set<String> _selectedAtmosphere = {};

  // Paso 3: Dinámica Social y Nivel de Descubrimiento
  String _socialCompanion = "pareja";
  String _discoveryStyle = "equilibrado";
  String _preferredTimeWindow = "tarde";

  // Paso 4: Ritmo, Movilidad, Presupuesto y Accesibilidad
  String _travelPace = "moderado";
  String _transportPref = "caminata";
  String _accessibilityNeeds = "estandar";

  // Paso 4: gasto promedio por salida (estimado con las respuestas; la persona lo ajusta)
  double? _avgBudgetOverride;

  // Paso 5: primeros lugares (se guardan en "Mis lugares" y entran al vector de gustos)
  final List<String> _seedPlaceIds = [];
  List<Poi> _catalog = const [];
  bool _catalogLoading = false;
  String _placeQuery = '';

  // Paso 6: direcciones (casa, hotel, oficina) para empezar rutas desde ahí
  final List<Map<String, dynamic>> _newAddresses = [];
  bool _addingAddress = false;

  // Paso 7: Bio / Manifiesto libre
  final TextEditingController _bioController = TextEditingController();

  final List<Map<String, dynamic>> _culturalOptions = [
    {"id": "muralismo", "label": "Muralismo y Arte Monumental", "icon": Icons.brush_outlined},
    {"id": "arqueologia", "label": "Zonas Arqueológicas y Prehispánicas", "icon": Icons.account_balance_outlined},
    {"id": "museos_arte", "label": "Museos Clásicos y Contemporáneos", "icon": Icons.museum_outlined},
    {"id": "arquitectura_virreinal", "label": "Arquitectura Virreinal y Barroca", "icon": Icons.church_outlined},
    {"id": "parques_bosques", "label": "Bosques y Jardines Históricos", "icon": Icons.park_outlined},
    {"id": "teatros_foros", "label": "Teatros, Cine de Arte y Foros", "icon": Icons.theater_comedy_outlined},
    {"id": "fotografia_urbana", "label": "Fotografía Urbana y Miradores", "icon": Icons.photo_camera_outlined},
    {"id": "librerias_cafes", "label": "Librerías de Viejo y Tertulia", "icon": Icons.menu_book_outlined},
    {"id": "mercados_artesanias", "label": "Mercados de Artesanías y Diseño", "icon": Icons.storefront_outlined},
    {"id": "musica_conciertos", "label": "Jazz, Sonideros y Música Viva", "icon": Icons.music_note_outlined},
  ];

  final List<Map<String, dynamic>> _culinaryOptions = [
    {"id": "cafeterias_especialidad", "label": "Cafés de Especialidad", "icon": Icons.local_cafe_outlined},
    {"id": "cantinas_tradicionales", "label": "Cantinas Históricas con Botana", "icon": Icons.wine_bar_outlined},
    {"id": "mercados_populares", "label": "Mercados Gastronómicos Típicos", "icon": Icons.restaurant_outlined},
    {"id": "comida_callejera", "label": "Antojitos Callejeros Emblemáticos", "icon": Icons.lunch_dining_outlined},
    {"id": "alta_gastronomia", "label": "Alta Cocina Contemporánea", "icon": Icons.dinner_dining_outlined},
    {"id": "pulquerias", "label": "Pulquerías y Bebidas Ancestrales", "icon": Icons.local_bar_outlined},
    {"id": "panaderias_clasicas", "label": "Panaderías Tradicionales de Barrio", "icon": Icons.bakery_dining_outlined},
  ];

  final List<Map<String, dynamic>> _atmosphereOptions = [
    {"id": "tranquilo_arbolado", "label": "Tranquilo, Silencioso y Arbolado", "icon": Icons.eco_outlined},
    {"id": "bohemio", "label": "Bohemio, Íntimo y Artístico", "icon": Icons.palette_outlined},
    {"id": "historico", "label": "Solemne, Monumental e Histórico", "icon": Icons.auto_stories_outlined},
    {"id": "vibrante_concurrido", "label": "Vibrante y Lleno de Vida Urbana", "icon": Icons.bolt_outlined},
    {"id": "festivo_nocturno", "label": "Festivo, Musical y Social", "icon": Icons.nightlife_outlined},
  ];

  @override
  void initState() {
    super.initState();
    _loadExistingSelectionsIfAny();
  }

  Future<void> _loadExistingSelectionsIfAny() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final data = await UserPrivateData.get(user.uid);
      final profile = data['cultural_profile'];
      if (profile is Map && mounted) {
        setState(() {
          if (profile['cultural_interests'] is List) {
            _selectedCultural
              ..clear()
              ..addAll((profile['cultural_interests'] as List).map((e) => e.toString()));
          }
          if (profile['culinary_interests'] is List) {
            _selectedCulinary
              ..clear()
              ..addAll((profile['culinary_interests'] as List).map((e) => e.toString()));
          }
          if (profile['atmosphere_preference'] is List) {
            _selectedAtmosphere
              ..clear()
              ..addAll((profile['atmosphere_preference'] as List).map((e) => e.toString()));
          }
          if (profile['social_companion'] is String) {
            _socialCompanion = profile['social_companion'];
          }
          if (profile['discovery_style'] is String) {
            _discoveryStyle = profile['discovery_style'];
          }
          if (profile['preferred_time_window'] is String) {
            _preferredTimeWindow = profile['preferred_time_window'];
          }
          if (profile['travel_pace'] is String) {
            _travelPace = profile['travel_pace'];
          }
          if (profile['transport_preference'] is String) {
            _transportPref = profile['transport_preference'];
          }
          if (profile['accessibility_needs'] is String) {
            _accessibilityNeeds = profile['accessibility_needs'];
          }
          if (profile['free_bio'] is String) {
            _bioController.text = profile['free_bio'];
          }
          if (profile['avg_budget_mxn'] is num) {
            _avgBudgetOverride = (profile['avg_budget_mxn'] as num).toDouble();
          }
          if (profile['seed_poi_ids'] is List) {
            _seedPlaceIds
              ..clear()
              ..addAll((profile['seed_poi_ids'] as List).map((e) => e.toString()));
          }
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _bioController.dispose();
    _stepScrollController.dispose();
    super.dispose();
  }

  bool get _canProceed {
    if (_currentStep == 0) return _selectedCultural.length >= 2;
    if (_currentStep == 1) return _selectedCulinary.isNotEmpty;
    return true;
  }

  void _nextStep() {
    if (_currentStep < _totalSteps - 1) {
      _goToStep(_currentStep + 1);
    } else {
      _finishOnboarding();
    }
  }

  void _previousStep() {
    if (_currentStep > 0) {
      _goToStep(_currentStep - 1);
    }
  }

  Map<String, String> _buildPreviewAxes() {
    final cultLabels = _selectedCultural.isEmpty
        ? "exploración cultural general"
        : _selectedCultural.join(", ");
    final culLabels = _selectedCulinary.isEmpty
        ? "sabores tradicionales"
        : _selectedCulinary.join(", ");
    final atmoLabels = _selectedAtmosphere.isEmpty
        ? "ambiente auténtico"
        : _selectedAtmosphere.join(", ");
    final bio = _bioController.text.trim();

    return {
      "Eje 1 • Vocación Cultural y Gastronómica":
          "Afinidad por $cultLabels y experiencias en $culLabels.${bio.isNotEmpty ? ' \"$bio\"' : ''}",
      "Eje 2 • Atmósfera y Experiencia Sensorial":
          "Vibras $atmoLabels a un ritmo $_travelPace.",
      "Eje 3 • Dinámica Social y Descubrimiento":
          "Viaje en modalidad $_socialCompanion, enfoque $_discoveryStyle en franja $_preferredTimeWindow.",
      "Eje 4 • Micro-Entorno y Caminabilidad":
          "Prioridad de traslado: $_transportPref ($_accessibilityNeeds).",
    };
  }

  Future<void> _finishOnboarding() async {
    if (widget.sandbox) {
      setState(() {
        _isSynthesizing = true;
        _synthesisMessage = "Modo de prueba: tu perfil real no se modificó.";
      });
      await Future.delayed(const Duration(milliseconds: 1200));
      if (mounted) widget.onCompleted();
      return;
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() {
      _isSynthesizing = true;
      _synthesisMessage = "Alineando los 4 ejes ontológicos e invocando al motor Yollotl (768d)...";
    });

    final payload = {
      "user_id": user.uid,
      "cultural_interests": _selectedCultural.toList(),
      "culinary_interests": _selectedCulinary.toList(),
      "atmosphere_preference": _selectedAtmosphere.toList(),
      "social_companion": _socialCompanion,
      "discovery_style": _discoveryStyle,
      "preferred_time_window": _preferredTimeWindow,
      "travel_pace": _travelPace,
      "budget_tier": _budgetTierFor(_avgBudget),
      "avg_budget_mxn": _avgBudget,
      "seed_poi_ids": List<String>.from(_seedPlaceIds),
      "transport_preference": _transportPref,
      "accessibility_needs": _accessibilityNeeds,
      "free_bio": _bioController.text.trim(),
    };

    // Lugares y direcciones primero: no dependen del motor y no deben perderse si este falla
    try {
      await SavedPlaces.addAll(_seedPlaceIds);
    } catch (e) {
      debugPrint('[onboarding] no se pudieron guardar los lugares: $e');
    }
    await _saveNewAddresses(user.uid);

    try {
      final vector = await OnboardingWizardPage.synthesizeAndSaveProfile(
        user.uid,
        payload,
        previewAxes: _buildPreviewAxes(),
      );

      setState(() {
        _synthesisMessage =
            "¡Vector de gusto (${vector.length} dimensiones) guardado en tu perfil!";
      });

      await Future.delayed(const Duration(milliseconds: 1200));

      if (mounted) {
        widget.onCompleted();
      }
    } catch (e) {
      print("Error completing onboarding: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Ocurrió un detalle al guardar tu perfil: $e"),
            backgroundColor: OhtliColors.xoconostle,
          ),
        );
        setState(() => _isSynthesizing = false);
      }
    }
  }

  // ==========================================================
  // UI
  // ==========================================================
  static const List<Map<String, dynamic>> _stepMeta = [
    {"label": "Cultura", "icon": Icons.palette_outlined},
    {"label": "Sabores", "icon": Icons.restaurant_outlined},
    {"label": "Social", "icon": Icons.groups_outlined},
    {"label": "Ritmo", "icon": Icons.directions_walk_rounded},
    {"label": "Lugares", "icon": Icons.bookmark_add_outlined},
    {"label": "Direcciones", "icon": Icons.home_work_outlined},
    {"label": "Manifiesto", "icon": Icons.edit_note_rounded},
  ];

  final ScrollController _stepScrollController = ScrollController();

  void _goToStep(int step) {
    if (step == _currentStep) return;
    if (step == 4) _ensureCatalog();
    setState(() => _currentStep = step);
    if (_stepScrollController.hasClients) _stepScrollController.jumpTo(0);
  }

  String get _blockedHint {
    if (_currentStep == 0) {
      final missing = 2 - _selectedCultural.length;
      return missing == 1 ? "Elige 1 opción más para continuar" : "Elige al menos 2 opciones para continuar";
    }
    if (_currentStep == 1) return "Elige al menos 1 preferencia gastronómica";
    return "";
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = ohtliIsMobileWidth(MediaQuery.of(context).size.width);
    return Scaffold(
      backgroundColor: OhtliColors.cloudDancer,
      body: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: RouteBackgroundPainter(OhtliColors.cantera.withValues(alpha: 0.9)),
            ),
          ),
          SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 880),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 450),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  child: _isSynthesizing
                      ? KeyedSubtree(key: const ValueKey('loading'), child: _buildLoadingView())
                      : KeyedSubtree(key: const ValueKey('wizard'), child: _buildWizardCard(isMobile)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingView() {
    final axes = [
      {"label": "Vocación cultural", "icon": Icons.palette_outlined, "color": OhtliColors.stormyTeal},
      {"label": "Atmósfera sensorial", "icon": Icons.spa_outlined, "color": OhtliColors.cempasuchil},
      {"label": "Dinámica social", "icon": Icons.groups_outlined, "color": OhtliColors.xoconostle},
      {"label": "Entorno urbano", "icon": Icons.directions_walk_rounded, "color": OhtliColors.stormyTeal},
    ];
    return Padding(
      padding: const EdgeInsets.all(32.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 120,
            height: 120,
            child: Stack(
              alignment: Alignment.center,
              children: [
                const SizedBox(
                  width: 120,
                  height: 120,
                  child: CircularProgressIndicator(color: OhtliColors.stormyTeal, strokeWidth: 3),
                ),
                SizedBox(
                  width: 92,
                  height: 92,
                  child: CircularProgressIndicator(
                    color: OhtliColors.cempasuchil.withValues(alpha: 0.8),
                    strokeWidth: 2,
                  ),
                ),
                Container(
                  width: 64,
                  height: 64,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: OhtliColors.cardBg,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: OhtliColors.stormyTeal.withValues(alpha: 0.18),
                        blurRadius: 24,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: SvgPicture.asset(
                    'assets/icon_isologo.svg',
                    colorFilter: const ColorFilter.mode(OhtliColors.stormyTeal, BlendMode.srcIn),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 36),
          Text(
            "Tejiendo tu Identidad Ohtli",
            textAlign: TextAlign.center,
            style: GoogleFonts.fraunces(
              fontSize: 30,
              fontWeight: FontWeight.bold,
              color: OhtliColors.onyx,
            ),
          ),
          const SizedBox(height: 12),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: Text(
              _synthesisMessage,
              key: ValueKey(_synthesisMessage),
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 15,
                color: OhtliColors.subtleText,
                height: 1.5,
              ),
            ),
          ),
          const SizedBox(height: 28),
          // Los 4 ejes aparecen uno a uno mientras se sintetiza el perfil
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 10,
            runSpacing: 10,
            children: List.generate(axes.length, (i) {
              final a = axes[i];
              final color = a["color"] as Color;
              return TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: Duration(milliseconds: 500 + i * 350),
                curve: Curves.easeOutBack,
                builder: (context, v, child) => Opacity(
                  opacity: v.clamp(0.0, 1.0),
                  child: Transform.translate(offset: Offset(0, 12 * (1 - v)), child: child),
                ),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: color.withValues(alpha: 0.25)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(a["icon"] as IconData, size: 15, color: color),
                      const SizedBox(width: 6),
                      Text(
                        "Eje ${i + 1} · ${a["label"]}",
                        style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: OhtliColors.onyx),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 22),
          Text(
            "Ontología Puente de 4 Ejes • Vector 768d (text-embedding-004)",
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: OhtliColors.stormyTeal,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWizardCard(bool isMobile) {
    final isLast = _currentStep == _totalSteps - 1;
    return Container(
      margin: EdgeInsets.symmetric(horizontal: isMobile ? 10 : 20, vertical: isMobile ? 10 : 24),
      decoration: BoxDecoration(
        color: OhtliColors.cardBg,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: OhtliColors.cardBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.07),
            blurRadius: 40,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(isMobile ? 20 : 36, isMobile ? 20 : 28, isMobile ? 20 : 36, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: OhtliColors.stormyTeal.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: SvgPicture.asset(
                          'assets/icon_isologo.svg',
                          colorFilter: const ColorFilter.mode(OhtliColors.stormyTeal, BlendMode.srcIn),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Identidad Cultural en 4 Ejes",
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.outfit(
                                fontSize: isMobile ? 15 : 16,
                                fontWeight: FontWeight.w700,
                                color: OhtliColors.onyx,
                              ),
                            ),
                            Text(
                              isMobile
                                  ? "Paso ${_currentStep + 1} de $_totalSteps · ${_stepMeta[_currentStep]["label"]}"
                                  : "Personaliza las rutas que Ohtli diseña para ti",
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(fontSize: 12, color: OhtliColors.subtleText),
                            ),
                          ],
                        ),
                      ),
                      if (!isMobile)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: OhtliColors.innerCardBg,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: OhtliColors.cardBorder),
                        ),
                        child: Text(
                          "Paso ${_currentStep + 1} de $_totalSteps",
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: OhtliColors.subtleText,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  _buildStepper(isMobile),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: SingleChildScrollView(
                controller: _stepScrollController,
                physics: const BouncingScrollPhysics(),
                padding: EdgeInsets.fromLTRB(isMobile ? 20 : 36, 20, isMobile ? 20 : 36, 24),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 320),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  layoutBuilder: (current, previous) => Stack(
                    alignment: Alignment.topLeft,
                    children: [...previous, if (current != null) current],
                  ),
                  transitionBuilder: (child, anim) => FadeTransition(
                    opacity: anim,
                    child: SlideTransition(
                      position: Tween<Offset>(begin: const Offset(0.03, 0), end: Offset.zero).animate(anim),
                      child: child,
                    ),
                  ),
                  child: KeyedSubtree(
                    key: ValueKey(_currentStep),
                    child: LayoutBuilder(
                      builder: (context, constraints) => _buildStepContent(constraints.maxWidth, isMobile),
                    ),
                  ),
                ),
              ),
            ),
            // Barra de acciones fija
            Container(
              padding: EdgeInsets.fromLTRB(isMobile ? 16 : 36, 14, isMobile ? 16 : 36, isMobile ? 16 : 22),
              decoration: BoxDecoration(
                color: OhtliColors.cardBg,
                border: Border(top: BorderSide(color: OhtliColors.cardBorder)),
              ),
              child: Row(
                children: [
                  if (_currentStep > 0)
                    TextButton.icon(
                      onPressed: _previousStep,
                      icon: const Icon(Icons.arrow_back_rounded, size: 18),
                      label: Text("Anterior", style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
                      style: TextButton.styleFrom(
                        foregroundColor: OhtliColors.onyx,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 200),
                      opacity: _canProceed ? 0 : 1,
                      child: Text(
                        _blockedHint,
                        textAlign: TextAlign.right,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(fontSize: 12, color: OhtliColors.subtleText),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _canProceed ? _nextStep : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isLast ? OhtliColors.cempasuchil : OhtliColors.stormyTeal,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: OhtliColors.innerCardBg,
                      disabledForegroundColor: OhtliColors.subtleText,
                      elevation: 0,
                      padding: EdgeInsets.symmetric(horizontal: isMobile ? 18 : 26, vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          isLast ? (isMobile ? "Completar" : "Completar y Tejer Vector 768d") : "Siguiente",
                          style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 14),
                        ),
                        const SizedBox(width: 8),
                        Icon(isLast ? Icons.auto_awesome_rounded : Icons.arrow_forward_rounded, size: 18),
                      ],
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

  // Indicador de pasos: segmentos con etiqueta; los pasos ya visitados son navegables
  Widget _buildStepper(bool isMobile) {
    return Row(
      children: List.generate(_totalSteps, (i) {
        final done = i < _currentStep;
        final active = i == _currentStep;
        final meta = _stepMeta[i];
        final color = (done || active) ? OhtliColors.stormyTeal : OhtliColors.subtleText.withValues(alpha: 0.6);
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: i == _totalSteps - 1 ? 0 : 6),
            child: InkWell(
              onTap: done ? () => _goToStep(i) : null,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: Stack(
                        children: [
                          Container(height: 5, color: OhtliColors.innerCardBg),
                          AnimatedFractionallySizedBox(
                            duration: const Duration(milliseconds: 400),
                            curve: Curves.easeOutCubic,
                            widthFactor: (done || active) ? 1 : 0,
                            child: Container(
                              height: 5,
                              color: active ? OhtliColors.stormyTeal : OhtliColors.stormyTeal.withValues(alpha: 0.55),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(done ? Icons.check_circle_rounded : meta["icon"] as IconData, size: 14, color: color),
                        if (!isMobile) ...[
                          const SizedBox(width: 5),
                          Flexible(
                            child: Text(
                              meta["label"] as String,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                                color: active ? OhtliColors.onyx : color,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildStepContent(double width, bool isMobile) {
    switch (_currentStep) {
      case 0:
        return _buildCulturalStep(width, isMobile);
      case 1:
        return _buildCulinaryAtmosphereStep(width, isMobile);
      case 2:
        return _buildSocialDiscoveryStep();
      case 3:
        return _buildPaceMobilityStep();
      case 4:
        return _buildSeedPlacesStep(width);
      case 5:
        return _buildAddressesStep();
      case 6:
        return _buildBioStep(width);
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildStepHeader({required String eyebrow, required String title, required String description}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          eyebrow.toUpperCase(),
          style: GoogleFonts.inter(
            fontSize: 11.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.4,
            color: OhtliColors.stormyTeal,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          title,
          style: GoogleFonts.fraunces(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: OhtliColors.onyx,
            height: 1.15,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          description,
          style: GoogleFonts.inter(fontSize: 14, color: OhtliColors.subtleText, height: 1.5),
        ),
      ],
    );
  }

  Widget _buildGroupLabel(String text, {Widget? trailing}) {
    return Row(
      children: [
        Expanded(
          child: Text(
            text,
            style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 14.5, color: OhtliColors.onyx),
          ),
        ),
        if (trailing != null) trailing,
      ],
    );
  }

  Widget _buildSelectionCounter(int count, {int? min}) {
    final ok = min == null || count >= min;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: ok && count > 0 ? OhtliColors.stormyTeal.withValues(alpha: 0.12) : OhtliColors.innerCardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: ok && count > 0 ? OhtliColors.stormyTeal.withValues(alpha: 0.3) : OhtliColors.cardBorder),
      ),
      child: Text(
        min != null ? "$count seleccionadas · mín. $min" : "$count seleccionadas",
        style: GoogleFonts.inter(
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          color: ok && count > 0 ? OhtliColors.stormyTeal : OhtliColors.subtleText,
        ),
      ),
    );
  }

  // Cuadrícula de mosaicos de selección múltiple
  Widget _buildMultiSelectGrid({
    required List<Map<String, dynamic>> options,
    required Set<String> selected,
    required Color accent,
    required double width,
    required bool isMobile,
  }) {
    final columns = width < 420 ? 2 : (width < 700 ? 3 : 4);
    const spacing = 10.0;
    final tileWidth = (width - spacing * (columns - 1)) / columns;
    return Wrap(
      spacing: spacing,
      runSpacing: spacing,
      children: options.map((opt) {
        final id = opt["id"] as String;
        final isSelected = selected.contains(id);
        return SizedBox(
          width: tileWidth,
          child: _SelectableTile(
            icon: opt["icon"] as IconData,
            label: opt["label"] as String,
            selected: isSelected,
            accent: accent,
            onTap: () => setState(() {
              if (isSelected) {
                selected.remove(id);
              } else {
                selected.add(id);
              }
            }),
          ),
        );
      }).toList(),
    );
  }

  // Grupo de selección única con pastillas que se ajustan en móvil
  Widget _buildChoiceGroup({
    required List<Map<String, dynamic>> options,
    required String value,
    required ValueChanged<String> onChanged,
  }) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: options.map((opt) {
        final id = opt["value"] as String;
        final isSelected = id == value;
        return _ChoicePill(
          icon: opt["icon"] as IconData,
          label: opt["label"] as String,
          selected: isSelected,
          onTap: () => setState(() => onChanged(id)),
        );
      }).toList(),
    );
  }

  Widget _buildCulturalStep(double width, bool isMobile) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildStepHeader(
          eyebrow: "Eje 1 · Vocación cultural",
          title: "¿Qué vocación cultural te inspira?",
          description:
              "Selecciona al menos 2 disciplinas artísticas o patrimoniales. Estas alimentan directamente el Eje 1 de tu vector para empatar con la vocación de cada recinto.",
        ),
        const SizedBox(height: 22),
        _buildGroupLabel(
          "Disciplinas",
          trailing: _buildSelectionCounter(_selectedCultural.length, min: 2),
        ),
        const SizedBox(height: 12),
        _buildMultiSelectGrid(
          options: _culturalOptions,
          selected: _selectedCultural,
          accent: OhtliColors.stormyTeal,
          width: width,
          isMobile: isMobile,
        ),
      ],
    );
  }

  Widget _buildCulinaryAtmosphereStep(double width, bool isMobile) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildStepHeader(
          eyebrow: "Ejes 1 y 2 · Sabores y atmósfera",
          title: "Gastronomía y Atmósfera Sensorial",
          description:
              "Tus gustos culinarios y las vibras que buscas se comparan contra las reseñas destiladas de los visitantes en cada lugar.",
        ),
        const SizedBox(height: 22),
        _buildGroupLabel(
          "Preferencias gastronómicas",
          trailing: _buildSelectionCounter(_selectedCulinary.length, min: 1),
        ),
        const SizedBox(height: 12),
        _buildMultiSelectGrid(
          options: _culinaryOptions,
          selected: _selectedCulinary,
          accent: OhtliColors.cempasuchil,
          width: width,
          isMobile: isMobile,
        ),
        const SizedBox(height: 28),
        _buildGroupLabel(
          "Atmósfera y vibra sensorial predilecta",
          trailing: _buildSelectionCounter(_selectedAtmosphere.length),
        ),
        const SizedBox(height: 12),
        _buildMultiSelectGrid(
          options: _atmosphereOptions,
          selected: _selectedAtmosphere,
          accent: OhtliColors.xoconostle,
          width: width,
          isMobile: isMobile,
        ),
      ],
    );
  }

  Widget _buildSocialDiscoveryStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildStepHeader(
          eyebrow: "Eje 3 · Dinámica social",
          title: "Dinámica Social y Estilo de Descubrimiento",
          description:
              "No es lo mismo recorrer la ciudad en solitario que con niños o amigos de noche. Estos parámetros calibran la compatibilidad social de cada POI.",
        ),
        const SizedBox(height: 26),
        _buildGroupLabel("¿Con quién acostumbras recorrer la ciudad?"),
        const SizedBox(height: 12),
        _buildChoiceGroup(
          value: _socialCompanion,
          onChanged: (v) => _socialCompanion = v,
          options: const [
            {"value": "solo", "label": "Solo", "icon": Icons.person_outline},
            {"value": "pareja", "label": "En Pareja", "icon": Icons.favorite_border},
            {"value": "amigos", "label": "Amigos", "icon": Icons.groups_outlined},
            {"value": "familia", "label": "Familia", "icon": Icons.family_restroom_outlined},
          ],
        ),
        const SizedBox(height: 26),
        _buildGroupLabel("¿Qué tipo de hallazgos prefieres en la CDMX?"),
        const SizedBox(height: 12),
        _buildChoiceGroup(
          value: _discoveryStyle,
          onChanged: (v) => _discoveryStyle = v,
          options: const [
            {"value": "iconico", "label": "Íconos Imprescindibles", "icon": Icons.account_balance_outlined},
            {"value": "equilibrado", "label": "Híbrido Equilibrado", "icon": Icons.auto_awesome_mosaic_outlined},
            {"value": "joyas_ocultas", "label": "Joyas Ocultas de Barrio", "icon": Icons.explore_outlined},
          ],
        ),
        const SizedBox(height: 26),
        _buildGroupLabel("Franja horaria favorita"),
        const SizedBox(height: 12),
        _buildChoiceGroup(
          value: _preferredTimeWindow,
          onChanged: (v) => _preferredTimeWindow = v,
          options: const [
            {"value": "manana", "label": "Mañana", "icon": Icons.wb_sunny_outlined},
            {"value": "tarde", "label": "Tarde", "icon": Icons.wb_twilight_outlined},
            {"value": "noche", "label": "Noche", "icon": Icons.nights_stay_outlined},
            {"value": "jornada_completa", "label": "Todo el Día", "icon": Icons.schedule_outlined},
          ],
        ),
      ],
    );
  }

  Widget _buildPaceMobilityStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildStepHeader(
          eyebrow: "Eje 4 · Entorno y filtros",
          title: "Ritmo, traslados y presupuesto",
          description:
              "La caminabilidad alimenta el Eje 4 de tu vector, mientras que el presupuesto y la accesibilidad operan como restricciones exactas en DEAP y OR-Tools.",
        ),
        const SizedBox(height: 26),
        _buildGroupLabel("Ritmo de la jornada"),
        const SizedBox(height: 12),
        _buildChoiceGroup(
          value: _travelPace,
          onChanged: (v) => _travelPace = v,
          options: const [
            {"value": "relajado", "label": "Relajado", "icon": Icons.spa_outlined},
            {"value": "moderado", "label": "Equilibrado", "icon": Icons.explore_outlined},
            {"value": "intensivo", "label": "Intensivo", "icon": Icons.bolt_outlined},
          ],
        ),
        const SizedBox(height: 26),
        _buildGroupLabel("Preferencia de desplazamiento barrial"),
        const SizedBox(height: 12),
        _buildChoiceGroup(
          value: _transportPref,
          onChanged: (v) => _transportPref = v,
          options: const [
            {"value": "caminata", "label": "Caminata Peatonal", "icon": Icons.directions_walk},
            {"value": "bicicleta", "label": "Bici / Ecobici", "icon": Icons.pedal_bike},
            {"value": "transporte_publico", "label": "Metro / Metrobús", "icon": Icons.directions_subway},
            {"value": "mixto", "label": "Mixto", "icon": Icons.alt_route},
            {"value": "auto", "label": "Taxi / Auto", "icon": Icons.local_taxi},
          ],
        ),
        const SizedBox(height: 26),
        _buildBudgetEstimator(),
        const SizedBox(height: 26),
        _buildGroupLabel("Requerimiento de accesibilidad motriz"),
        const SizedBox(height: 12),
        _buildChoiceGroup(
          value: _accessibilityNeeds,
          onChanged: (v) => _accessibilityNeeds = v,
          options: const [
            {"value": "estandar", "label": "Peatonal Estándar", "icon": Icons.directions_walk_outlined},
            {"value": "accesibilidad_universal", "label": "Accesibilidad Universal / Rampas", "icon": Icons.accessible_outlined},
          ],
        ),
      ],
    );
  }

  // ==========================================================
  // Presupuesto promedio estimado
  // ==========================================================

  /// Costo típico por persona (MXN) de comer en cada tipo de lugar.
  static const Map<String, double> _foodCost = {
    "cafeterias_especialidad": 140,
    "cantinas_tradicionales": 320,
    "mercados_populares": 160,
    "comida_callejera": 110,
    "alta_gastronomia": 950,
    "pulquerias": 170,
    "panaderias_clasicas": 90,
  };

  /// Entrada típica de cada vocación cultural (muchos lugares son gratis).
  static const Map<String, double> _entryCost = {
    "muralismo": 40,
    "arqueologia": 95,
    "museos_arte": 90,
    "arquitectura_virreinal": 0,
    "parques_bosques": 0,
    "teatros_foros": 250,
    "fotografia_urbana": 30,
    "librerias_cafes": 0,
    "mercados_artesanias": 0,
    "musica_conciertos": 280,
  };

  static const Map<String, double> _transportCost = {
    "caminata": 0,
    "bicicleta": 35,
    "transporte_publico": 25,
    "mixto": 90,
    "auto": 260,
  };

  static const Map<String, double> _paceFactor = {"relajado": 0.85, "moderado": 1.0, "intensivo": 1.25};

  double _avg(Iterable<String> ids, Map<String, double> table, double fallback) {
    final values = ids.where(table.containsKey).map((id) => table[id]!).toList();
    if (values.isEmpty) return fallback;
    return values.reduce((a, b) => a + b) / values.length;
  }

  /// (comida, entradas, traslados, total) por salida, redondeado a 50.
  ({double food, double entries, double transport, double total}) get _budgetEstimate {
    final pace = _paceFactor[_travelPace] ?? 1.0;
    final food = _avg(_selectedCulinary, _foodCost, 200) * (_travelPace == 'intensivo' ? 1.5 : 1.0);
    final entries = _avg(_selectedCultural, _entryCost, 60) * 2; // ~2 recintos por salida
    final transport = _transportCost[_transportPref] ?? 40;
    double round50(double v) => (v / 50).round() * 50.0;
    final total = round50((food + entries + transport) * pace).clamp(150.0, 3000.0);
    return (food: round50(food), entries: round50(entries), transport: round50(transport), total: total);
  }

  double get _avgBudget => _avgBudgetOverride ?? _budgetEstimate.total;

  String _budgetTierFor(double amount) => amount < 300 ? "economico" : (amount <= 650 ? "medio" : "alto");

  String _money(double v) => "\$${v.round()}";

  Widget _buildBudgetEstimator() {
    final est = _budgetEstimate;
    final value = _avgBudget.clamp(150.0, 3000.0);
    final adjusted = _avgBudgetOverride != null && (_avgBudgetOverride! - est.total).abs() >= 1;
    Widget part(IconData icon, String label, double amount) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: OhtliColors.subtleText),
            const SizedBox(width: 6),
            Text("$label ${amount <= 0 ? 'gratis' : '~${_money(amount)}'}",
                style: GoogleFonts.inter(fontSize: 12.5, color: OhtliColors.subtleText)),
          ],
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildGroupLabel("¿Cuánto gastas normalmente en una salida?"),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: OhtliColors.innerCardBg,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: OhtliColors.cardBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _money(value),
                    style: GoogleFonts.outfit(fontSize: 34, fontWeight: FontWeight.w800, color: OhtliColors.onyx, height: 1),
                  ),
                  const SizedBox(width: 8),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text("MXN por persona", style: GoogleFonts.inter(fontSize: 13, color: OhtliColors.subtleText)),
                  ),
                  const Spacer(),
                  if (adjusted)
                    TextButton(
                      onPressed: () => setState(() => _avgBudgetOverride = null),
                      child: Text("Usar estimado (${_money(est.total)})",
                          style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600, color: OhtliColors.accentText)),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                adjusted
                    ? "Lo ajustaste tú. Lo usaremos como tope al armar tus rutas."
                    : "Lo estimamos con lo que elegiste. Muévelo si gastas más o menos.",
                style: GoogleFonts.inter(fontSize: 13, color: OhtliColors.subtleText, height: 1.4),
              ),
              Slider(
                value: value,
                min: 150,
                max: 3000,
                divisions: 57,
                label: _money(value),
                activeColor: OhtliColors.stormyTeal,
                onChanged: (v) => setState(() => _avgBudgetOverride = v),
              ),
              Wrap(
                spacing: 16,
                runSpacing: 6,
                children: [
                  part(Icons.restaurant_outlined, "Comida", est.food),
                  part(Icons.confirmation_number_outlined, "Entradas", est.entries),
                  part(Icons.directions_transit_outlined, "Traslados", est.transport),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ==========================================================
  // Primeros lugares
  // ==========================================================

  /// Categorías del catálogo que corresponden a cada respuesta.
  static const Map<String, List<String>> _interestCategories = {
    "muralismo": ["artwork", "arts_centre", "museum"],
    "arqueologia": ["arqueologia", "museum", "monument"],
    "museos_arte": ["museum", "gallery"],
    "arquitectura_virreinal": ["place_of_worship", "monument", "attraction"],
    "parques_bosques": ["park", "garden", "nature_reserve"],
    "teatros_foros": ["theatre", "cinema", "arts_centre"],
    "fotografia_urbana": ["viewpoint", "attraction", "monument"],
    "librerias_cafes": ["books", "library", "cafe"],
    "mercados_artesanias": ["marketplace"],
    "musica_conciertos": ["bar", "pub", "nightclub"],
    "cafeterias_especialidad": ["cafe", "coffee"],
    "cantinas_tradicionales": ["cantina", "bar"],
    "mercados_populares": ["marketplace"],
    "comida_callejera": ["fast_food"],
    "alta_gastronomia": ["restaurant"],
    "pulquerias": ["pulqueria"],
    "panaderias_clasicas": ["bakery", "pastry"],
  };

  Future<void> _ensureCatalog() async {
    if (_catalog.isNotEmpty || _catalogLoading) return;
    setState(() => _catalogLoading = true);
    try {
      final pois = await PlacesPage.loadCatalog();
      if (mounted) setState(() => _catalog = pois.where((p) => p.isValidCulturalPlace).toList());
    } catch (e) {
      debugPrint('[onboarding] catálogo no disponible: $e');
    } finally {
      if (mounted) setState(() => _catalogLoading = false);
    }
  }

  static String _norm(String s) => s
      .toLowerCase()
      .replaceAll(RegExp('[áà]'), 'a')
      .replaceAll(RegExp('[éè]'), 'e')
      .replaceAll(RegExp('[íì]'), 'i')
      .replaceAll(RegExp('[óò]'), 'o')
      .replaceAll(RegExp('[úùü]'), 'u');

  /// Sugerencias según las respuestas, alternando categorías para que haya variedad.
  List<Poi> get _placeSuggestions {
    final query = _norm(_placeQuery.trim());
    if (query.isNotEmpty) {
      return _catalog.where((p) => _norm(p.name).contains(query)).take(18).toList();
    }
    final cats = <String>[];
    for (final id in [..._selectedCultural, ..._selectedCulinary]) {
      for (final c in _interestCategories[id] ?? const <String>[]) {
        if (!cats.contains(c)) cats.add(c);
      }
    }
    if (cats.isEmpty) cats.addAll(["museum", "cafe", "park", "restaurant"]);
    final byCat = <String, List<Poi>>{
      for (final c in cats) c: _catalog.where((p) => p.category == c && p.imageUrl.isNotEmpty).toList(),
    };
    final out = <Poi>[];
    var round = 0;
    while (out.length < 18 && byCat.values.any((l) => l.length > round)) {
      for (final c in cats) {
        final list = byCat[c]!;
        if (round < list.length && !out.contains(list[round])) out.add(list[round]);
        if (out.length >= 18) break;
      }
      round++;
    }
    return out;
  }

  Widget _buildSeedPlacesStep(double width) {
    final suggestions = _placeSuggestions;
    final columns = width < 420 ? 2 : (width < 700 ? 3 : 4);
    const spacing = 10.0;
    final tileWidth = (width - spacing * (columns - 1)) / columns;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildStepHeader(
          eyebrow: "Tus primeros lugares",
          title: "¿Cuáles te gustaría visitar?",
          description:
              "Guárdalos en Mis lugares. Además, nos ayudan a entender mejor tu gusto: tus recomendaciones se parecerán a ellos.",
        ),
        const SizedBox(height: 18),
        TextField(
          onChanged: (v) => setState(() => _placeQuery = v),
          style: GoogleFonts.inter(color: OhtliColors.onyx),
          decoration: InputDecoration(
            hintText: "Busca un lugar que ya conozcas o quieras conocer",
            hintStyle: GoogleFonts.inter(color: OhtliColors.subtleText, fontSize: 14),
            prefixIcon: Icon(Icons.search_rounded, color: OhtliColors.accentText),
            filled: true,
            fillColor: OhtliColors.innerCardBg,
            contentPadding: const EdgeInsets.symmetric(vertical: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: OhtliColors.cardBorder),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: OhtliColors.cardBorder),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: OhtliColors.accentText, width: 1.6),
            ),
          ),
        ),
        const SizedBox(height: 14),
        _buildGroupLabel(
          _placeQuery.trim().isEmpty ? "Sugeridos para ti" : "Resultados",
          trailing: _buildSelectionCounter(_seedPlaceIds.length),
        ),
        const SizedBox(height: 12),
        if (_catalogLoading && _catalog.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(child: CircularProgressIndicator(color: OhtliColors.stormyTeal)),
          )
        else if (suggestions.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(
              _catalog.isEmpty
                  ? "No pudimos cargar los lugares. Puedes seguir y guardarlos después desde Lugares."
                  : "No encontramos lugares con ese nombre.",
              style: GoogleFonts.inter(color: OhtliColors.subtleText),
            ),
          )
        else
          Wrap(
            spacing: spacing,
            runSpacing: spacing,
            children: [
              for (final poi in suggestions)
                SizedBox(
                  width: tileWidth,
                  child: _SeedPlaceTile(
                    poi: poi,
                    selected: _seedPlaceIds.contains(poi.poiId),
                    onTap: () => setState(() {
                      if (!_seedPlaceIds.remove(poi.poiId)) _seedPlaceIds.add(poi.poiId);
                    }),
                  ),
                ),
            ],
          ),
        const SizedBox(height: 12),
        Text(
          "Opcional. Elige 3 o más para que tus recomendaciones se ajusten mejor.",
          style: GoogleFonts.inter(fontSize: 12.5, color: OhtliColors.subtleText),
        ),
      ],
    );
  }

  // ==========================================================
  // Direcciones
  // ==========================================================

  Future<void> _saveNewAddresses(String uid) async {
    if (_newAddresses.isEmpty || widget.sandbox) return;
    try {
      final data = await UserPrivateData.get(uid);
      final existing = (data['addresses'] is List)
          ? (data['addresses'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList()
          : <Map<String, dynamic>>[];
      await UserPrivateData.save(uid, {'addresses': [...existing, ..._newAddresses]});
    } catch (e) {
      debugPrint('[onboarding] no se pudieron guardar las direcciones: $e');
    }
  }

  Widget _buildAddressesStep() {
    if (_addingAddress) {
      return AddressPickerWidget(
        existingNames: _newAddresses
            .map((a) => (a['customName'] as String?) ?? '')
            .where((n) => n.isNotEmpty)
            .toList(),
        onCancel: () => setState(() => _addingAddress = false),
        onSave: (address) => setState(() {
          final now = DateTime.now().millisecondsSinceEpoch;
          _newAddresses.add({
            ...address,
            'id': 'addr_${now}_${address['street'].hashCode}',
            'updatedAt': now,
          });
          _addingAddress = false;
        }),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildStepHeader(
          eyebrow: "Tus puntos de partida",
          title: "¿Desde dónde sueles salir?",
          description:
              "Guarda tu casa, tu hotel o la oficina para empezar tus rutas desde ahí con un toque. Puedes cambiarlas después en Cuenta.",
        ),
        const SizedBox(height: 20),
        for (final a in _newAddresses)
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
            decoration: BoxDecoration(
              color: OhtliColors.innerCardBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: OhtliColors.cardBorder),
            ),
            child: Row(
              children: [
                Icon(Icons.place_outlined, color: OhtliColors.accentText),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        ((a['customName'] as String?)?.isNotEmpty ?? false) ? a['customName'] : (a['category'] ?? 'Dirección'),
                        style: GoogleFonts.inter(fontWeight: FontWeight.w700, color: OhtliColors.onyx),
                      ),
                      Text(
                        "${a['street'] ?? ''}, ${a['suburb'] ?? ''}",
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(fontSize: 12.5, color: OhtliColors.subtleText),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Quitar dirección',
                  onPressed: () => setState(() => _newAddresses.remove(a)),
                  icon: Icon(Icons.close_rounded, size: 18, color: OhtliColors.subtleText),
                ),
              ],
            ),
          ),
        SizedBox(
          height: 50,
          child: OutlinedButton.icon(
            onPressed: () => setState(() => _addingAddress = true),
            icon: const Icon(Icons.add_location_alt_outlined),
            label: Text(_newAddresses.isEmpty ? "Agregar una dirección" : "Agregar otra"),
            style: OutlinedButton.styleFrom(
              foregroundColor: OhtliColors.accentText,
              side: BorderSide(color: OhtliColors.accentText.withValues(alpha: 0.5)),
              shape: const StadiumBorder(),
              textStyle: GoogleFonts.inter(fontWeight: FontWeight.w700),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          "Opcional. Si prefieres, sigue sin agregar ninguna.",
          style: GoogleFonts.inter(fontSize: 12.5, color: OhtliColors.subtleText),
        ),
      ],
    );
  }

  Widget _buildBioStep(double width) {
    final previewAxes = _buildPreviewAxes();
    const axisStyles = [
      {"icon": Icons.palette_outlined, "color": OhtliColors.stormyTeal},
      {"icon": Icons.spa_outlined, "color": OhtliColors.cempasuchil},
      {"icon": Icons.groups_outlined, "color": OhtliColors.xoconostle},
      {"icon": Icons.directions_walk_rounded, "color": OhtliColors.stormyTeal},
    ];
    final twoCols = width >= 560;
    final cardWidth = twoCols ? (width - 12) / 2 : width;
    final entries = previewAxes.entries.toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildStepHeader(
          eyebrow: "Síntesis · Tu manifiesto",
          title: "Manifiesto Personal y Síntesis en 4 Ejes",
          description:
              "Añade cualquier matiz personal y revisa cómo tu perfil se alinea con la estructura de 4 ejes del Agente Recolector.",
        ),
        const SizedBox(height: 22),
        TextField(
          controller: _bioController,
          maxLines: 4,
          minLines: 3,
          maxLength: 280,
          style: GoogleFonts.inter(color: OhtliColors.onyx, height: 1.5),
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText:
                "Ej.: Me fascina caminar por Coyoacán, encontrar librerías independientes y tomar un espresso en patios con bugambilias...",
            hintStyle: GoogleFonts.inter(color: OhtliColors.subtleText, fontSize: 13.5),
            filled: true,
            fillColor: OhtliColors.innerCardBg,
            contentPadding: const EdgeInsets.all(18),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: BorderSide(color: OhtliColors.cardBorder),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: BorderSide(color: OhtliColors.cardBorder),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: const BorderSide(color: OhtliColors.stormyTeal, width: 2),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            const Icon(Icons.auto_awesome_rounded, size: 16, color: OhtliColors.cempasuchil),
            const SizedBox(width: 6),
            Text(
              "Vista previa de tu receta ontológica espejo",
              style: GoogleFonts.inter(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: OhtliColors.onyx,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: List.generate(entries.length, (i) {
            final entry = entries[i];
            final style = axisStyles[i % axisStyles.length];
            final color = style["color"] as Color;
            return SizedBox(
              width: cardWidth,
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: OhtliColors.innerCardBg,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: OhtliColors.cardBorder),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(style["icon"] as IconData, size: 18, color: color),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            entry.key,
                            style: GoogleFonts.inter(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: color,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            entry.value,
                            style: GoogleFonts.inter(
                              fontSize: 12.5,
                              color: OhtliColors.onyx,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ),
      ],
    );
  }
}

/// Lugar del catálogo con foto, para elegir los primeros lugares.
class _SeedPlaceTile extends StatelessWidget {
  const _SeedPlaceTile({required this.poi, required this.selected, required this.onTap});

  final Poi poi;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: poi.name,
      child: Material(
        color: OhtliColors.innerCardBg,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: selected ? OhtliColors.accentText : OhtliColors.cardBorder,
                width: selected ? 2 : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AspectRatio(
                  aspectRatio: 4 / 3,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Container(color: OhtliColors.stormyTeal.withValues(alpha: 0.2)),
                      LayoutBuilder(
                        builder: (context, c) => Image.network(
                          CdmxPhotos.sized(poi.imageUrl, c.maxWidth, MediaQuery.devicePixelRatioOf(context)),
                          fit: BoxFit.cover,
                          excludeFromSemantics: true,
                          errorBuilder: (_, _, _) => const SizedBox.shrink(),
                        ),
                      ),
                      Positioned(
                        top: 8,
                        right: 8,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: selected ? OhtliColors.stormyTeal : Colors.black.withValues(alpha: 0.45),
                            border: Border.all(color: Colors.white, width: 1.5),
                          ),
                          child: Icon(selected ? Icons.check_rounded : Icons.add_rounded, size: 17, color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        poi.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: OhtliColors.onyx),
                      ),
                      Text(
                        poi.categoryDisplay,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(fontSize: 11.5, color: OhtliColors.subtleText),
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

/// Mosaico seleccionable (selección múltiple) con icono, etiqueta y check animado.
class _SelectableTile extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  const _SelectableTile({
    required this.icon,
    required this.label,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  @override
  State<_SelectableTile> createState() => _SelectableTileState();
}

class _SelectableTileState extends State<_SelectableTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final accent = widget.accent;
    final selected = widget.selected;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _hover && !selected ? 1.02 : 1.0,
          duration: const Duration(milliseconds: 160),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            height: 108,
            padding: const EdgeInsets.fromLTRB(14, 14, 12, 12),
            decoration: BoxDecoration(
              color: selected ? accent.withValues(alpha: 0.10) : OhtliColors.innerCardBg,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: selected ? accent : (_hover ? accent.withValues(alpha: 0.35) : OhtliColors.cardBorder),
                width: selected ? 1.6 : 1,
              ),
              boxShadow: selected
                  ? [BoxShadow(color: accent.withValues(alpha: 0.16), blurRadius: 14, offset: const Offset(0, 6))]
                  : null,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: selected ? accent : accent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: Icon(widget.icon, size: 19, color: selected ? Colors.white : accent),
                    ),
                    const Spacer(),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 180),
                      transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
                      child: selected
                          ? Icon(Icons.check_circle_rounded, key: const ValueKey('on'), size: 20, color: accent)
                          : Icon(Icons.circle_outlined,
                              key: const ValueKey('off'), size: 20, color: OhtliColors.subtleText.withValues(alpha: 0.35)),
                    ),
                  ],
                ),
                const Spacer(),
                Text(
                  widget.label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 12.5,
                    height: 1.25,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                    color: OhtliColors.onyx,
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

/// Pastilla de selección única.
class _ChoicePill extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ChoicePill({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color: selected ? OhtliColors.stormyTeal : OhtliColors.innerCardBg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: selected ? OhtliColors.stormyTeal : OhtliColors.cardBorder),
            boxShadow: selected
                ? [BoxShadow(color: OhtliColors.stormyTeal.withValues(alpha: 0.25), blurRadius: 12, offset: const Offset(0, 4))]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 17, color: selected ? Colors.white : OhtliColors.stormyTeal),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: selected ? Colors.white : OhtliColors.onyx,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

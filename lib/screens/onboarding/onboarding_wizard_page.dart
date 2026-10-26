import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import '../../theme/colors.dart';

class OnboardingWizardPage extends StatefulWidget {
  final VoidCallback onCompleted;

  const OnboardingWizardPage({
    super.key,
    required this.onCompleted,
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
  /// text-embedding-004 taste vector and persists it directly into /users/{uid}.
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

    try {
      final response = await http
          .post(
            Uri.parse('$apiUrl/v1/user/cultural-profile'),
            headers: {"Content-Type": "application/json"},
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

    final userRef = FirebaseFirestore.instance.collection('users').doc(uid);
    await userRef.set({
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
    }, SetOptions(merge: true));

    return tasteVector;
  }

  @override
  State<OnboardingWizardPage> createState() => _OnboardingWizardPageState();
}

class _OnboardingWizardPageState extends State<OnboardingWizardPage> {
  static const int _totalSteps = 5;
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
  String _budgetTier = "medio";
  String _accessibilityNeeds = "estandar";

  // Paso 5: Bio / Manifiesto libre
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
      final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      final data = doc.data();
      final profile = data?['cultural_profile'];
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
          if (profile['budget_tier'] is String) {
            _budgetTier = profile['budget_tier'];
          }
          if (profile['accessibility_needs'] is String) {
            _accessibilityNeeds = profile['accessibility_needs'];
          }
          if (profile['free_bio'] is String) {
            _bioController.text = profile['free_bio'];
          }
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _bioController.dispose();
    super.dispose();
  }

  bool get _canProceed {
    if (_currentStep == 0) return _selectedCultural.length >= 2;
    if (_currentStep == 1) return _selectedCulinary.isNotEmpty;
    return true;
  }

  void _nextStep() {
    if (_currentStep < _totalSteps - 1) {
      setState(() => _currentStep++);
    } else {
      _finishOnboarding();
    }
  }

  void _previousStep() {
    if (_currentStep > 0) {
      setState(() => _currentStep--);
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
      "budget_tier": _budgetTier,
      "transport_preference": _transportPref,
      "accessibility_needs": _accessibilityNeeds,
      "free_bio": _bioController.text.trim(),
    };

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: OhtliColors.cloudDancer,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 840),
            child: _isSynthesizing ? _buildLoadingView() : _buildWizardCard(),
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingView() {
    return Padding(
      padding: const EdgeInsets.all(32.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: OhtliColors.cardBg,
              shape: BoxShape.circle,
              border: Border.all(color: OhtliColors.cardBorder),
              boxShadow: [
                BoxShadow(
                  color: OhtliColors.stormyTeal.withValues(alpha: 0.12),
                  blurRadius: 28,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: const CircularProgressIndicator(
              color: OhtliColors.stormyTeal,
              strokeWidth: 3.5,
            ),
          ),
          const SizedBox(height: 32),
          Text(
            "Tejiendo tu Identidad Ohtli",
            style: GoogleFonts.fraunces(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: OhtliColors.onyx,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            _synthesisMessage,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 16,
              color: OhtliColors.subtleText,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: OhtliColors.innerCardBg,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: OhtliColors.cardBorder),
            ),
            child: Text(
              "Ontología Puente de 4 Ejes • Vector 768d (text-embedding-004)",
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: OhtliColors.stormyTeal,
              ),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildWizardCard() {
    return Card(
      elevation: 0,
      color: OhtliColors.cardBg,
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: OhtliColors.cardBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: OhtliColors.stormyTeal,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Center(
                        child: Text(
                          "O",
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 20,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      "Identidad Cultural en 4 Ejes",
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: OhtliColors.stormyTeal,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
                Text(
                  "Paso ${_currentStep + 1} de $_totalSteps",
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: OhtliColors.subtleText,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: (_currentStep + 1) / _totalSteps,
                backgroundColor: OhtliColors.innerCardBg,
                valueColor: const AlwaysStoppedAnimation<Color>(
                  OhtliColors.stormyTeal,
                ),
                minHeight: 6,
              ),
            ),
            const SizedBox(height: 28),
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: _buildStepContent(),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (_currentStep > 0)
                  OutlinedButton.icon(
                    onPressed: _previousStep,
                    icon: const Icon(Icons.arrow_back, size: 18),
                    label: const Text("Anterior"),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: OhtliColors.onyx,
                      side: BorderSide(color: OhtliColors.cardBorder),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 14,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  )
                else
                  const SizedBox.shrink(),
                ElevatedButton.icon(
                  onPressed: _canProceed ? _nextStep : null,
                  icon: Icon(
                    _currentStep == _totalSteps - 1
                        ? Icons.check_circle
                        : Icons.arrow_forward,
                    size: 18,
                  ),
                  label: Text(
                    _currentStep == _totalSteps - 1
                        ? "Completar y Tejer Vector 768d"
                        : "Siguiente",
                    style: GoogleFonts.inter(fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: OhtliColors.stormyTeal,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: OhtliColors.innerCardBg,
                    disabledForegroundColor: OhtliColors.subtleText,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 28,
                      vertical: 16,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(
                        color: _canProceed ? Colors.transparent : OhtliColors.cardBorder,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStepContent() {
    switch (_currentStep) {
      case 0:
        return _buildCulturalStep();
      case 1:
        return _buildCulinaryAtmosphereStep();
      case 2:
        return _buildSocialDiscoveryStep();
      case 3:
        return _buildPaceMobilityStep();
      case 4:
        return _buildBioStep();
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildCulturalStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Eje 1: ¿Qué vocación cultural te inspira?",
          style: GoogleFonts.fraunces(
            fontSize: 26,
            fontWeight: FontWeight.bold,
            color: OhtliColors.onyx,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          "Selecciona al menos 2 disciplinas artísticas o patrimoniales. Estas alimentan directamente el Eje 1 de tu vector para empatar con la vocación de cada recinto.",
          style: GoogleFonts.inter(fontSize: 14, color: OhtliColors.subtleText),
        ),
        const SizedBox(height: 24),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: _culturalOptions.map((opt) {
            final isSelected = _selectedCultural.contains(opt["id"]);
            return FilterChip(
              avatar: Icon(
                opt["icon"] as IconData,
                size: 16,
                color: isSelected ? OhtliColors.stormyTeal : OhtliColors.onyx,
              ),
              label: Text(opt["label"] as String),
              selected: isSelected,
              selectedColor: OhtliColors.stormyTeal.withValues(alpha: 0.18),
              checkmarkColor: OhtliColors.stormyTeal,
              labelStyle: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                color: isSelected ? OhtliColors.stormyTeal : OhtliColors.onyx,
              ),
              backgroundColor: OhtliColors.innerCardBg,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(
                  color: isSelected ? OhtliColors.stormyTeal : OhtliColors.cardBorder,
                  width: isSelected ? 1.5 : 1,
                ),
              ),
              onSelected: (selected) {
                setState(() {
                  if (selected) {
                    _selectedCultural.add(opt["id"] as String);
                  } else {
                    _selectedCultural.remove(opt["id"] as String);
                  }
                });
              },
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildCulinaryAtmosphereStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Ejes 1 y 2: Gastronomía y Atmósfera Sensorial",
          style: GoogleFonts.fraunces(
            fontSize: 26,
            fontWeight: FontWeight.bold,
            color: OhtliColors.onyx,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          "Tus gustos culinarios y las vibras que buscas se comparan contra las reseñas destiladas de los visitantes en cada lugar.",
          style: GoogleFonts.inter(fontSize: 14, color: OhtliColors.subtleText),
        ),
        const SizedBox(height: 20),
        Text(
          "Preferencias Gastronómicas (Elige al menos 1)",
          style: GoogleFonts.inter(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: OhtliColors.onyx,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: _culinaryOptions.map((opt) {
            final isSelected = _selectedCulinary.contains(opt["id"]);
            return FilterChip(
              avatar: Icon(
                opt["icon"] as IconData,
                size: 16,
                color: isSelected ? OhtliColors.xoconostle : OhtliColors.onyx,
              ),
              label: Text(opt["label"] as String),
              selected: isSelected,
              selectedColor: OhtliColors.xoconostle.withValues(alpha: 0.18),
              checkmarkColor: OhtliColors.xoconostle,
              labelStyle: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                color: isSelected ? OhtliColors.xoconostle : OhtliColors.onyx,
              ),
              backgroundColor: OhtliColors.innerCardBg,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(
                  color: isSelected ? OhtliColors.xoconostle : OhtliColors.cardBorder,
                  width: isSelected ? 1.5 : 1,
                ),
              ),
              onSelected: (selected) {
                setState(() {
                  if (selected) {
                    _selectedCulinary.add(opt["id"] as String);
                  } else {
                    _selectedCulinary.remove(opt["id"] as String);
                  }
                });
              },
            );
          }).toList(),
        ),
        const SizedBox(height: 28),
        Text(
          "Atmósfera y Vibra Sensorial Predilecta",
          style: GoogleFonts.inter(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: OhtliColors.onyx,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: _atmosphereOptions.map((opt) {
            final isSelected = _selectedAtmosphere.contains(opt["id"]);
            return FilterChip(
              avatar: Icon(
                opt["icon"] as IconData,
                size: 16,
                color: isSelected ? OhtliColors.stormyTeal : OhtliColors.onyx,
              ),
              label: Text(opt["label"] as String),
              selected: isSelected,
              selectedColor: OhtliColors.stormyTeal.withValues(alpha: 0.18),
              checkmarkColor: OhtliColors.stormyTeal,
              labelStyle: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                color: isSelected ? OhtliColors.stormyTeal : OhtliColors.onyx,
              ),
              backgroundColor: OhtliColors.innerCardBg,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(
                  color: isSelected ? OhtliColors.stormyTeal : OhtliColors.cardBorder,
                  width: isSelected ? 1.5 : 1,
                ),
              ),
              onSelected: (selected) {
                setState(() {
                  if (selected) {
                    _selectedAtmosphere.add(opt["id"] as String);
                  } else {
                    _selectedAtmosphere.remove(opt["id"] as String);
                  }
                });
              },
            );
          }).toList(),
        ),
      ],
    );
  }

  ButtonStyle _segmentedButtonStyle() {
    return SegmentedButton.styleFrom(
      backgroundColor: OhtliColors.innerCardBg,
      selectedBackgroundColor: OhtliColors.stormyTeal.withValues(alpha: 0.18),
      foregroundColor: OhtliColors.onyx,
      selectedForegroundColor: OhtliColors.stormyTeal,
      side: BorderSide(color: OhtliColors.cardBorder),
      textStyle: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
  }

  Widget _buildSocialDiscoveryStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Eje 3: Dinámica Social y Estilo de Descubrimiento",
          style: GoogleFonts.fraunces(
            fontSize: 26,
            fontWeight: FontWeight.bold,
            color: OhtliColors.onyx,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          "No es lo mismo recorrer la ciudad en solitario que con niños o amigos de noche. Estos parámetros calibran la compatibilidad social de cada POI.",
          style: GoogleFonts.inter(fontSize: 14, color: OhtliColors.subtleText),
        ),
        const SizedBox(height: 24),
        Text(
          "¿Con quién acostumbras recorrer la ciudad?",
          style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 15, color: OhtliColors.onyx),
        ),
        const SizedBox(height: 10),
        SegmentedButton<String>(
          style: _segmentedButtonStyle(),
          segments: const [
            ButtonSegment(
              value: "solo",
              label: Text("Solo"),
              icon: Icon(Icons.person_outline),
            ),
            ButtonSegment(
              value: "pareja",
              label: Text("En Pareja"),
              icon: Icon(Icons.favorite_border),
            ),
            ButtonSegment(
              value: "amigos",
              label: Text("Amigos"),
              icon: Icon(Icons.groups_outlined),
            ),
            ButtonSegment(
              value: "familia",
              label: Text("Familia"),
              icon: Icon(Icons.family_restroom_outlined),
            ),
          ],
          selected: {_socialCompanion},
          onSelectionChanged: (val) => setState(() => _socialCompanion = val.first),
        ),
        const SizedBox(height: 24),
        Text(
          "¿Qué tipo de hallazgos prefieres en la CDMX?",
          style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 15, color: OhtliColors.onyx),
        ),
        const SizedBox(height: 10),
        SegmentedButton<String>(
          style: _segmentedButtonStyle(),
          segments: const [
            ButtonSegment(
              value: "iconico",
              label: Text("Íconos Imprescindibles"),
              icon: Icon(Icons.account_balance_outlined),
            ),
            ButtonSegment(
              value: "equilibrado",
              label: Text("Híbrido Equilibrado"),
              icon: Icon(Icons.auto_awesome_mosaic_outlined),
            ),
            ButtonSegment(
              value: "joyas_ocultas",
              label: Text("Joyas Ocultas de Barrio"),
              icon: Icon(Icons.explore_outlined),
            ),
          ],
          selected: {_discoveryStyle},
          onSelectionChanged: (val) => setState(() => _discoveryStyle = val.first),
        ),
        const SizedBox(height: 24),
        Text(
          "Franja Horaria Favorita",
          style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 15, color: OhtliColors.onyx),
        ),
        const SizedBox(height: 10),
        SegmentedButton<String>(
          style: _segmentedButtonStyle(),
          segments: const [
            ButtonSegment(
              value: "manana",
              label: Text("Mañana"),
              icon: Icon(Icons.wb_sunny_outlined),
            ),
            ButtonSegment(
              value: "tarde",
              label: Text("Tarde"),
              icon: Icon(Icons.wb_twilight_outlined),
            ),
            ButtonSegment(
              value: "noche",
              label: Text("Noche"),
              icon: Icon(Icons.nights_stay_outlined),
            ),
            ButtonSegment(
              value: "jornada_completa",
              label: Text("Todo el Día"),
              icon: Icon(Icons.schedule_outlined),
            ),
          ],
          selected: {_preferredTimeWindow},
          onSelectionChanged: (val) => setState(() => _preferredTimeWindow = val.first),
        ),
      ],
    );
  }

  Widget _buildPaceMobilityStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Eje 4 y Filtros Duros: Entorno, Ritmo y Presupuesto",
          style: GoogleFonts.fraunces(
            fontSize: 26,
            fontWeight: FontWeight.bold,
            color: OhtliColors.onyx,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          "La caminabilidad alimenta el Eje 4 de tu vector, mientras que el presupuesto y la accesibilidad operan como restricciones exactas en DEAP y OR-Tools.",
          style: GoogleFonts.inter(fontSize: 14, color: OhtliColors.subtleText),
        ),
        const SizedBox(height: 22),
        Text(
          "Ritmo de la Jornada",
          style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 15, color: OhtliColors.onyx),
        ),
        const SizedBox(height: 8),
        SegmentedButton<String>(
          style: _segmentedButtonStyle(),
          segments: const [
            ButtonSegment(
              value: "relajado",
              label: Text("Relajado"),
              icon: Icon(Icons.spa_outlined),
            ),
            ButtonSegment(
              value: "moderado",
              label: Text("Equilibrado"),
              icon: Icon(Icons.explore_outlined),
            ),
            ButtonSegment(
              value: "intensivo",
              label: Text("Intensivo"),
              icon: Icon(Icons.bolt_outlined),
            ),
          ],
          selected: {_travelPace},
          onSelectionChanged: (val) => setState(() => _travelPace = val.first),
        ),
        const SizedBox(height: 20),
        Text(
          "Preferencia de Desplazamiento Barrial",
          style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 15, color: OhtliColors.onyx),
        ),
        const SizedBox(height: 8),
        SegmentedButton<String>(
          style: _segmentedButtonStyle(),
          segments: const [
            ButtonSegment(
              value: "caminata",
              label: Text("Caminata Peatonal"),
              icon: Icon(Icons.directions_walk),
            ),
            ButtonSegment(
              value: "transporte_publico",
              label: Text("Metro / Ecobici"),
              icon: Icon(Icons.directions_subway),
            ),
            ButtonSegment(
              value: "mixto",
              label: Text("Mixto"),
              icon: Icon(Icons.alt_route),
            ),
          ],
          selected: {_transportPref},
          onSelectionChanged: (val) => setState(() => _transportPref = val.first),
        ),
        const SizedBox(height: 20),
        Text(
          "Sensibilidad Presupuestal (Filtro Knapsack)",
          style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 15, color: OhtliColors.onyx),
        ),
        const SizedBox(height: 8),
        SegmentedButton<String>(
          style: _segmentedButtonStyle(),
          segments: const [
            ButtonSegment(
              value: "economico",
              label: Text("Económico (<\$250)"),
              icon: Icon(Icons.monetization_on_outlined),
            ),
            ButtonSegment(
              value: "medio",
              label: Text("Medio (<\$500)"),
              icon: Icon(Icons.account_balance_wallet_outlined),
            ),
            ButtonSegment(
              value: "alto",
              label: Text("Holgado"),
              icon: Icon(Icons.diamond_outlined),
            ),
          ],
          selected: {_budgetTier},
          onSelectionChanged: (val) => setState(() => _budgetTier = val.first),
        ),
        const SizedBox(height: 20),
        Text(
          "Requerimiento de Accesibilidad Motriz",
          style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 15, color: OhtliColors.onyx),
        ),
        const SizedBox(height: 8),
        SegmentedButton<String>(
          style: _segmentedButtonStyle(),
          segments: const [
            ButtonSegment(
              value: "estandar",
              label: Text("Peatonal Estándar"),
              icon: Icon(Icons.directions_walk_outlined),
            ),
            ButtonSegment(
              value: "accesibilidad_universal",
              label: Text("Accesibilidad Universal / Rampas"),
              icon: Icon(Icons.accessible_outlined),
            ),
          ],
          selected: {_accessibilityNeeds},
          onSelectionChanged: (val) => setState(() => _accessibilityNeeds = val.first),
        ),
      ],
    );
  }

  Widget _buildBioStep() {
    final previewAxes = _buildPreviewAxes();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Manifiesto Personal y Síntesis en 4 Ejes",
          style: GoogleFonts.fraunces(
            fontSize: 26,
            fontWeight: FontWeight.bold,
            color: OhtliColors.onyx,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          "Añade cualquier matiz personal y revisa cómo tu perfil se alinea con la estructura de 4 ejes del Agente Recolector.",
          style: GoogleFonts.inter(fontSize: 14, color: OhtliColors.subtleText),
        ),
        const SizedBox(height: 18),
        TextField(
          controller: _bioController,
          maxLines: 3,
          maxLength: 280,
          style: GoogleFonts.inter(color: OhtliColors.onyx),
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText:
                "Ej.: Me fascina caminar por Coyoacán, encontrar librerías independientes y tomar un espresso en patios con bugambilias...",
            hintStyle: GoogleFonts.inter(color: OhtliColors.subtleText, fontSize: 13),
            filled: true,
            fillColor: OhtliColors.innerCardBg,
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
              borderSide: const BorderSide(color: OhtliColors.stormyTeal, width: 2),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          "Vista Previa de tu Receta Ontológica Espejo:",
          style: GoogleFonts.inter(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: OhtliColors.stormyTeal,
          ),
        ),
        const SizedBox(height: 8),
        ...previewAxes.entries.map(
          (entry) => Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: OhtliColors.innerCardBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: OhtliColors.cardBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.key,
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: OhtliColors.stormyTeal,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  entry.value,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: OhtliColors.onyx,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

import 'dart:convert';
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

  @override
  State<OnboardingWizardPage> createState() => _OnboardingWizardPageState();
}

class _OnboardingWizardPageState extends State<OnboardingWizardPage> {
  int _currentStep = 0;
  bool _isSynthesizing = false;
  String _synthesisMessage = "El motor Yollotl está analizando tus gustos...";

  // Paso 1: Intereses Culturales
  final Set<String> _selectedCultural = {};

  // Paso 2: Gastronomía y Atmósfera
  final Set<String> _selectedCulinary = {};
  final Set<String> _selectedAtmosphere = {};

  // Paso 3: Ritmo y Movilidad
  String _travelPace = "moderado";
  String _transportPref = "caminata";
  String _budgetTier = "medio";

  // Paso 4: Bio / Texto libre
  final TextEditingController _bioController = TextEditingController();

  final List<Map<String, String>> _culturalOptions = [
    {"id": "muralismo", "label": "Muralismo y Arte Monumental", "icon": "🎨"},
    {"id": "arqueologia", "label": "Zonas Arqueológicas y Prehispánicas", "icon": "🏛️"},
    {"id": "museos_arte", "label": "Museos Clásicos y Contemporáneos", "icon": "🖼️"},
    {"id": "arquitectura_virreinal", "label": "Arquitectura Virreinal y Barroca", "icon": "⛪"},
    {"id": "parques_bosques", "label": "Bosques y Áreas Verdes", "icon": "🌳"},
    {"id": "teatros_foros", "label": "Teatros y Artes Escénicas", "icon": "🎭"},
    {"id": "fotografia_urbana", "label": "Fotografía Urbana y Callejones", "icon": "📸"},
    {"id": "librerias_cafes", "label": "Librerías de Viejo y Tertulia", "icon": "📚"},
    {"id": "mercados_artesanias", "label": "Mercados Tradicionales y Artesanías", "icon": "🏺"},
    {"id": "musica_conciertos", "label": "Jazz, Sonideros y Música Viva", "icon": "🎷"},
  ];

  final List<Map<String, String>> _culinaryOptions = [
    {"id": "cafeterias_especialidad", "label": "Cafés de Especialidad", "icon": "☕"},
    {"id": "cantinas_tradicionales", "label": "Cantinas Históricas con Botana", "icon": "🍷"},
    {"id": "mercados_populares", "label": "Mercados Gastronómicos Típicos", "icon": "🌮"},
    {"id": "comida_callejera", "label": "Antojitos Callejeros Emblemáticos", "icon": "🥘"},
    {"id": "alta_gastronomia", "label": "Alta Cocina Contemporánea", "icon": "🍽️"},
    {"id": "pulquerias", "label": "Pulquerías y Bebidas Ancestrales", "icon": "🏺"},
    {"id": "panaderias_clasicas", "label": "Panaderías Tradicionales de Barrio", "icon": "🥐"},
  ];

  final List<Map<String, String>> _atmosphereOptions = [
    {"id": "tranquilo_arbolado", "label": "Tranquilo y Arbolado", "icon": "🌿"},
    {"id": "vibrante_concurrido", "label": "Vibrante y Llena de Vida", "icon": "⚡"},
    {"id": "bohemio", "label": "Bohemio y Artístico", "icon": "🎨"},
    {"id": "historico", "label": "Monumental e Histórico", "icon": "🏛️"},
  ];

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
    if (_currentStep < 3) {
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

  Future<void> _finishOnboarding() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() {
      _isSynthesizing = true;
      _synthesisMessage = "Sintetizando tu perfil e invocando al motor Yollotl...";
    });

    final payload = {
      "user_id": user.uid,
      "cultural_interests": _selectedCultural.toList(),
      "culinary_interests": _selectedCulinary.toList(),
      "atmosphere_preference": _selectedAtmosphere.toList(),
      "travel_pace": _travelPace,
      "budget_tier": _budgetTier,
      "transport_preference": _transportPref,
      "free_bio": _bioController.text.trim(),
    };

    try {
      // 1. Invocar endpoint del backend Yollotl Engine para generar el embedding 768d
      const apiUrl = String.fromEnvironment(
        'yollotlApiUrl',
        defaultValue: 'https://api.ohtli.quest',
      );

      try {
        final response = await http
            .post(
              Uri.parse('$apiUrl/v1/user/cultural-profile'),
              headers: {"Content-Type": "application/json"},
              body: jsonEncode(payload),
            )
            .timeout(const Duration(seconds: 8));

        if (response.statusCode == 200 || response.statusCode == 201) {
          print("Cultural profile vector successfully created by Yollotl API.");
        }
      } catch (httpError) {
        print("API endpoint call failed or offline, saving directly to Firestore: $httpError");
      }

      // 2. Persistencia en Cloud Firestore para asegurar que la app continúe
      final userRef = FirebaseFirestore.instance.collection('users').doc(user.uid);
      await userRef.set({
        "cultural_profile": payload,
        "onboarding_completed": true,
        "updatedAt": FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      setState(() {
        _synthesisMessage = "¡Tu identidad viajera ha sido tejida con éxito!";
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
            constraints: const BoxConstraints(maxWidth: 820),
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
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: OhtliColors.stormyTeal.withOpacity(0.12),
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
              color: Colors.black54,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: OhtliColors.cantera.withOpacity(0.35),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              "Vector denso de 768 dimensiones • text-embedding-004",
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
      color: Colors.white,
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: OhtliColors.cantera.withOpacity(0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Cabecera con indicador de progreso
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
                      "Perfil del Turista",
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
                  "Paso ${_currentStep + 1} de 4",
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: Colors.black45,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: (_currentStep + 1) / 4.0,
                backgroundColor: OhtliColors.cantera.withOpacity(0.4),
                valueColor: const AlwaysStoppedAnimation<Color>(
                  OhtliColors.stormyTeal,
                ),
                minHeight: 6,
              ),
            ),
            const SizedBox(height: 28),

            // Contenido dinámico del paso actual
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: _buildStepContent(),
              ),
            ),

            const SizedBox(height: 24),
            // Botones de Navegación
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
                      side: const BorderSide(color: OhtliColors.cantera),
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
                    _currentStep == 3 ? Icons.check_circle : Icons.arrow_forward,
                    size: 18,
                  ),
                  label: Text(
                    _currentStep == 3 ? "Completar y Tejer Perfil" : "Siguiente",
                    style: GoogleFonts.inter(fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: OhtliColors.stormyTeal,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: OhtliColors.cantera,
                    disabledForegroundColor: Colors.white70,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 28,
                      vertical: 16,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
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
        return _buildPaceMobilityStep();
      case 3:
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
          "¿Qué te inspira de la Ciudad de México?",
          style: GoogleFonts.fraunces(
            fontSize: 26,
            fontWeight: FontWeight.bold,
            color: OhtliColors.onyx,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          "Elige al menos 2 disciplinas y tipos de patrimonio que más despierten tu curiosidad.",
          style: GoogleFonts.inter(fontSize: 14, color: Colors.black54),
        ),
        const SizedBox(height: 24),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: _culturalOptions.map((opt) {
            final isSelected = _selectedCultural.contains(opt["id"]);
            return FilterChip(
              avatar: Text(opt["icon"] ?? ""),
              label: Text(opt["label"] ?? ""),
              selected: isSelected,
              selectedColor: OhtliColors.stormyTeal.withOpacity(0.15),
              checkmarkColor: OhtliColors.stormyTeal,
              labelStyle: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                color: isSelected ? OhtliColors.stormyTeal : OhtliColors.onyx,
              ),
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(
                  color: isSelected ? OhtliColors.stormyTeal : OhtliColors.cantera,
                  width: isSelected ? 1.5 : 1,
                ),
              ),
              onSelected: (selected) {
                setState(() {
                  if (selected) {
                    _selectedCultural.add(opt["id"]!);
                  } else {
                    _selectedCultural.remove(opt["id"]!);
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
          "Sabores y Atmósfera de Barrio",
          style: GoogleFonts.fraunces(
            fontSize: 26,
            fontWeight: FontWeight.bold,
            color: OhtliColors.onyx,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          "Define los momentos gastronómicos y el ambiente urbano en el que te sientes más pleno.",
          style: GoogleFonts.inter(fontSize: 14, color: Colors.black54),
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
              avatar: Text(opt["icon"] ?? ""),
              label: Text(opt["label"] ?? ""),
              selected: isSelected,
              selectedColor: OhtliColors.xoconostle.withOpacity(0.15),
              checkmarkColor: OhtliColors.xoconostle,
              labelStyle: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                color: isSelected ? OhtliColors.xoconostle : OhtliColors.onyx,
              ),
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(
                  color: isSelected ? OhtliColors.xoconostle : OhtliColors.cantera,
                  width: isSelected ? 1.5 : 1,
                ),
              ),
              onSelected: (selected) {
                setState(() {
                  if (selected) {
                    _selectedCulinary.add(opt["id"]!);
                  } else {
                    _selectedCulinary.remove(opt["id"]!);
                  }
                });
              },
            );
          }).toList(),
        ),
        const SizedBox(height: 28),
        Text(
          "Atmósfera Predilecta",
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
              avatar: Text(opt["icon"] ?? ""),
              label: Text(opt["label"] ?? ""),
              selected: isSelected,
              selectedColor: OhtliColors.stormyTeal.withOpacity(0.15),
              checkmarkColor: OhtliColors.stormyTeal,
              labelStyle: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                color: isSelected ? OhtliColors.stormyTeal : OhtliColors.onyx,
              ),
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(
                  color: isSelected ? OhtliColors.stormyTeal : OhtliColors.cantera,
                  width: isSelected ? 1.5 : 1,
                ),
              ),
              onSelected: (selected) {
                setState(() {
                  if (selected) {
                    _selectedAtmosphere.add(opt["id"]!);
                  } else {
                    _selectedAtmosphere.remove(opt["id"]!);
                  }
                });
              },
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildPaceMobilityStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Tu Ritmo, Movilidad y Presupuesto",
          style: GoogleFonts.fraunces(
            fontSize: 26,
            fontWeight: FontWeight.bold,
            color: OhtliColors.onyx,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          "Ajusta los parámetros operativos que usarán los algoritmos DEAP y OR-Tools.",
          style: GoogleFonts.inter(fontSize: 14, color: Colors.black54),
        ),
        const SizedBox(height: 24),
        Text(
          "Ritmo de la Jornada",
          style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 15),
        ),
        const SizedBox(height: 8),
        SegmentedButton<String>(
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
          onSelectionChanged: (val) {
            setState(() => _travelPace = val.first);
          },
        ),
        const SizedBox(height: 24),
        Text(
          "Preferencia de Desplazamiento",
          style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 15),
        ),
        const SizedBox(height: 8),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(
              value: "caminata",
              label: Text("Caminata Peatonal"),
              icon: Icon(Icons.directions_walk),
            ),
            ButtonSegment(
              value: "transporte_publico",
              label: Text("Metro / Metrobús"),
              icon: Icon(Icons.directions_subway),
            ),
            ButtonSegment(
              value: "mixto",
              label: Text("Mixto"),
              icon: Icon(Icons.alt_route),
            ),
          ],
          selected: {_transportPref},
          onSelectionChanged: (val) {
            setState(() => _transportPref = val.first);
          },
        ),
        const SizedBox(height: 24),
        Text(
          "Sensibilidad Presupuestal Habitual",
          style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 15),
        ),
        const SizedBox(height: 8),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(
              value: "economico",
              label: Text("Económico"),
              icon: Icon(Icons.monetization_on_outlined),
            ),
            ButtonSegment(
              value: "medio",
              label: Text("Medio"),
              icon: Icon(Icons.account_balance_wallet_outlined),
            ),
            ButtonSegment(
              value: "alto",
              label: Text("Holgado"),
              icon: Icon(Icons.diamond_outlined),
            ),
          ],
          selected: {_budgetTier},
          onSelectionChanged: (val) {
            setState(() => _budgetTier = val.first);
          },
        ),
      ],
    );
  }

  Widget _buildBioStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Tu Esencia Viajera (Opcional)",
          style: GoogleFonts.fraunces(
            fontSize: 26,
            fontWeight: FontWeight.bold,
            color: OhtliColors.onyx,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          "Cuéntanos en tus propias palabras qué hace inolvidable un recorrido para ti. El modelo de embeddings lo integrará a tu vector.",
          style: GoogleFonts.inter(fontSize: 14, color: Colors.black54),
        ),
        const SizedBox(height: 24),
        TextField(
          controller: _bioController,
          maxLines: 5,
          maxLength: 300,
          decoration: InputDecoration(
            hintText: "Ejemplo: Me fascina caminar por Coyoacán, encontrar librerías independientes y sentarme a tomar un café espresso en plazas tranquilas...",
            hintStyle: GoogleFonts.inter(color: Colors.black38, fontSize: 14),
            filled: true,
            fillColor: OhtliColors.cloudDancer.withOpacity(0.5),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: OhtliColors.cantera),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: OhtliColors.stormyTeal, width: 2),
            ),
          ),
        ),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: OhtliColors.stormyTeal.withOpacity(0.08),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: OhtliColors.stormyTeal.withOpacity(0.2)),
          ),
          child: Row(
            children: [
              const Icon(Icons.auto_awesome, color: OhtliColors.stormyTeal, size: 24),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  "Tus selecciones se sintetizarán con IA y se guardarán en tu perfil como un vector matemático inmutable, respetando tu privacidad según la LFPDPPP.",
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: OhtliColors.stormyTeal,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

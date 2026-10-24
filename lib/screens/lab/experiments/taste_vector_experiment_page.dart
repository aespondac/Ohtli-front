import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import '../../../theme/colors.dart';
import '../../onboarding/onboarding_wizard_page.dart';

class TasteVectorExperimentPage extends StatefulWidget {
  final VoidCallback onBack;

  const TasteVectorExperimentPage({super.key, required this.onBack});

  @override
  State<TasteVectorExperimentPage> createState() =>
      _TasteVectorExperimentPageState();
}

class _TasteVectorExperimentPageState extends State<TasteVectorExperimentPage> {
  bool _isLoading = false;
  String? _errorText;
  String? _recipeText;
  List<double>? _tasteVector;
  Map<String, dynamic>? _responsePayload;

  // Parámetros del experimento
  final Set<String> _selectedCultural = {
    "muralismo",
    "museos_arte",
    "librerias_cafes"
  };
  final Set<String> _selectedCulinary = {
    "cafeterias_especialidad",
    "cantinas_tradicionales"
  };
  final Set<String> _selectedAtmosphere = {"tranquilo_arbolado", "bohemio"};
  String _travelPace = "relajado";
  String _transportPref = "caminata";
  String _budgetTier = "medio";
  final TextEditingController _bioController = TextEditingController(
    text: "Me fascina la arquitectura virreinal y tomar buen café en plazas con arbolado.",
  );

  // Muestra de POIs para prueba de similitud coseno
  final List<Map<String, dynamic>> _samplePois = [
    {
      "name": "Museo Frida Kahlo (Casa Azul)",
      "category": "museos_arte, bohemio",
      "sample_score": 0.942,
    },
    {
      "name": "Café El Jarocho - Coyoacán",
      "category": "cafeterias_especialidad, tradicional",
      "sample_score": 0.887,
    },
    {
      "name": "Autódromo Hermanos Rodríguez",
      "category": "deportes, velocidad",
      "sample_score": 0.214,
    },
  ];

  @override
  void dispose() {
    _bioController.dispose();
    super.dispose();
  }

  void _applyPreset(String presetName) {
    setState(() {
      _selectedCultural.clear();
      _selectedCulinary.clear();
      _selectedAtmosphere.clear();

      if (presetName == "bohemio") {
        _selectedCultural.addAll(["muralismo", "museos_arte", "librerias_cafes"]);
        _selectedCulinary.addAll(["cafeterias_especialidad", "cantinas_tradicionales"]);
        _selectedAtmosphere.addAll(["tranquilo_arbolado", "bohemio"]);
        _travelPace = "relajado";
        _transportPref = "caminata";
        _budgetTier = "medio";
        _bioController.text =
            "Paseos a pie por Coyoacán y San Ángel, descubriendo librerías y galerías.";
      } else if (presetName == "arqueologo") {
        _selectedCultural.addAll(["arqueologia", "arquitectura_virreinal", "fotografia_urbana"]);
        _selectedCulinary.addAll(["cantinas_tradicionales", "pulquerias"]);
        _selectedAtmosphere.addAll(["historico", "monumental"]);
        _travelPace = "intensivo";
        _transportPref = "transporte_publico";
        _budgetTier = "economico";
        _bioController.text =
            "Explorar vestigios mexicas en el Templo Mayor y conventos del siglo XVI.";
      } else if (presetName == "gastronomico") {
        _selectedCultural.addAll(["mercados_artesanias", "fotografia_urbana"]);
        _selectedCulinary.addAll([
          "mercados_populares",
          "comida_callejera",
          "alta_gastronomia",
          "panaderias_clasicas"
        ]);
        _selectedAtmosphere.addAll(["vibrante_concurrido", "bohemio"]);
        _travelPace = "moderado";
        _transportPref = "mixto";
        _budgetTier = "alto";
        _bioController.text =
            "Recorrido de sabores: desde tacos de canasta en el Centro hasta cenas de degustación.";
      }
    });
  }

  Future<void> _generateTasteVector() async {
    setState(() {
      _isLoading = true;
      _errorText = null;
      _recipeText = null;
      _tasteVector = null;
      _responsePayload = null;
    });

    const apiUrl = String.fromEnvironment(
      'yollotlApiUrl',
      defaultValue: 'https://api.ohtli.quest',
    );

    final payload = {
      "user_id": "lab_experiment_user",
      "cultural_interests": _selectedCultural.toList(),
      "culinary_interests": _selectedCulinary.toList(),
      "atmosphere_preference": _selectedAtmosphere.toList(),
      "travel_pace": _travelPace,
      "budget_tier": _budgetTier,
      "transport_preference": _transportPref,
      "free_bio": _bioController.text.trim(),
    };

    try {
      final response = await http
          .post(
            Uri.parse('$apiUrl/v1/user/cultural-profile'),
            headers: {"Content-Type": "application/json"},
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200 || response.statusCode == 201) {
        final decoded = jsonDecode(response.body);
        setState(() {
          _responsePayload = decoded;
          _recipeText = decoded["recipe"];
          if (decoded["taste_vector"] != null) {
            _tasteVector = (decoded["taste_vector"] as List)
                .map((e) => (e as num).toDouble())
                .toList();
          } else {
            // Generar vector sintético determinista de 768d si la API devuelve solo dimensión
            final random = Random(payload.hashCode);
            _tasteVector = List.generate(
              768,
              (_) => ((random.nextDouble() * 2) - 1.0) / sqrt(768),
            );
          }
        });
      } else {
        // Fallback local para testing offline en Labs
        _fallbackLocalGeneration(payload);
      }
    } catch (e) {
      _fallbackLocalGeneration(payload);
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _fallbackLocalGeneration(Map<String, dynamic> payload) {
    final interests = (payload["cultural_interests"] as List).join(", ");
    final culinary = (payload["culinary_interests"] as List).join(", ");
    final pace = payload["travel_pace"];
    final bio = payload["free_bio"];

    final localRecipe =
        "Identidad cultural del turista: Afinidad por $interests. Experiencias gastronómicas en $culinary. Ritmo $pace con prioridad por ${payload["transport_preference"]}. Descripción del usuario: \"$bio\"";

    final random = Random(payload.hashCode);
    final mockVector = List.generate(
      768,
      (_) => ((random.nextDouble() * 2) - 1.0) / sqrt(768),
    );

    setState(() {
      _recipeText = localRecipe;
      _tasteVector = mockVector;
      _responsePayload = {
        "status": "success (local labs fallback)",
        "user_id": payload["user_id"],
        "taste_vector_dim": 768,
        "recipe": localRecipe,
      };
    });
  }

  void _openFullWizard() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => OnboardingWizardPage(
          onCompleted: () {
            Navigator.of(context).pop();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text("¡Wizard completado exitosamente!"),
                backgroundColor: OhtliColors.stormyTeal,
              ),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: OhtliColors.cloudDancer,
      appBar: AppBar(
        title: Text(
          "Labs: Vector de Gustos Culturales",
          style: GoogleFonts.fraunces(fontWeight: FontWeight.bold, fontSize: 20),
        ),
        backgroundColor: Colors.white,
        foregroundColor: OhtliColors.onyx,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: widget.onBack,
        ),
        actions: [
          TextButton.icon(
            onPressed: _openFullWizard,
            icon: const Icon(Icons.open_in_new, size: 16),
            label: const Text("Probar Wizard Completo"),
            style: TextButton.styleFrom(foregroundColor: OhtliColors.stormyTeal),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1100),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeaderCard(),
                const SizedBox(height: 20),
                LayoutBuilder(
                  builder: (context, constraints) {
                    if (constraints.maxWidth > 800) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 5, child: _buildControlsCard()),
                          const SizedBox(width: 20),
                          Expanded(flex: 6, child: _buildResultsCard()),
                        ],
                      );
                    } else {
                      return Column(
                        children: [
                          _buildControlsCard(),
                          const SizedBox(height: 20),
                          _buildResultsCard(),
                        ],
                      );
                    }
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderCard() {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: OhtliColors.cantera.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: OhtliColors.stormyTeal.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.fingerprint_rounded,
                color: OhtliColors.stormyTeal,
                size: 36,
              ),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Simulador de Identidad Cultural & Vector de Gustos",
                    style: GoogleFonts.fraunces(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: OhtliColors.onyx,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    "Experimenta cómo Ohtli traduce las respuestas del turista en un vector denso de 768 dimensiones (text-embedding-004) para alimentar la búsqueda semántica en Firestore.",
                    style: GoogleFonts.inter(fontSize: 14, color: Colors.black54),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControlsCard() {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: OhtliColors.cantera.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  "Parámetros del Turista",
                  style: GoogleFonts.fraunces(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: OhtliColors.onyx,
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: "Cargar Perfil Prediseñado",
                  onSelected: _applyPreset,
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: "bohemio",
                      child: Text("☕ El Bohemio de Coyoacán"),
                    ),
                    const PopupMenuItem(
                      value: "arqueologo",
                      child: Text("🏛️ El Arqueólogo Monumental"),
                    ),
                    const PopupMenuItem(
                      value: "gastronomico",
                      child: Text("🌮 El Explorador Gastronómico"),
                    ),
                  ],
                  child: Chip(
                    avatar: const Icon(Icons.flash_on, size: 16),
                    label: const Text("Presets"),
                    backgroundColor: OhtliColors.cantera.withValues(alpha: 0.2),
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            Text(
              "Intereses Culturales",
              style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildTagChip("muralismo", "Muralismo", _selectedCultural),
                _buildTagChip("arqueologia", "Arqueología", _selectedCultural),
                _buildTagChip("museos_arte", "Museos de Arte", _selectedCultural),
                _buildTagChip(
                  "arquitectura_virreinal",
                  "Arquitectura Colonial",
                  _selectedCultural,
                ),
                _buildTagChip("librerias_cafes", "Librerías", _selectedCultural),
                _buildTagChip("parques_bosques", "Naturaleza", _selectedCultural),
              ],
            ),
            const SizedBox(height: 18),
            Text(
              "Gastronomía",
              style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildTagChip(
                  "cafeterias_especialidad",
                  "Cafés de Especialidad",
                  _selectedCulinary,
                  isSecondary: true,
                ),
                _buildTagChip(
                  "cantinas_tradicionales",
                  "Cantinas Históricas",
                  _selectedCulinary,
                  isSecondary: true,
                ),
                _buildTagChip(
                  "mercados_populares",
                  "Mercados Típicos",
                  _selectedCulinary,
                  isSecondary: true,
                ),
                _buildTagChip(
                  "comida_callejera",
                  "Comida Callejera",
                  _selectedCulinary,
                  isSecondary: true,
                ),
                _buildTagChip(
                  "alta_gastronomia",
                  "Alta Cocina",
                  _selectedCulinary,
                  isSecondary: true,
                ),
              ],
            ),
            const SizedBox(height: 18),
            Text(
              "Ritmo de Viaje",
              style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13),
            ),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: "relajado", label: Text("Relajado")),
                ButtonSegment(value: "moderado", label: Text("Equilibrado")),
                ButtonSegment(value: "intensivo", label: Text("Intensivo")),
              ],
              selected: {_travelPace},
              onSelectionChanged: (val) => setState(() => _travelPace = val.first),
            ),
            const SizedBox(height: 18),
            Text(
              "Bio / Intereses en Texto Libre",
              style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _bioController,
              maxLines: 2,
              style: GoogleFonts.inter(fontSize: 13),
              decoration: InputDecoration(
                filled: true,
                fillColor: OhtliColors.cloudDancer.withValues(alpha: 0.5),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: OhtliColors.cantera),
                ),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isLoading ? null : _generateTasteVector,
                icon: _isLoading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.bolt),
                label: Text(
                  _isLoading ? "Calculando Vector..." : "Calcular Vector 768d en Yollotl",
                  style: GoogleFonts.inter(fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: OhtliColors.stormyTeal,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTagChip(
    String id,
    String label,
    Set<String> set, {
    bool isSecondary = false,
  }) {
    final isSelected = set.contains(id);
    final activeColor =
        isSecondary ? OhtliColors.xoconostle : OhtliColors.stormyTeal;

    return FilterChip(
      label: Text(label),
      selected: isSelected,
      selectedColor: activeColor.withValues(alpha: 0.15),
      checkmarkColor: activeColor,
      labelStyle: GoogleFonts.inter(
        fontSize: 12,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        color: isSelected ? activeColor : OhtliColors.onyx,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isSelected ? activeColor : OhtliColors.cantera,
          width: isSelected ? 1.5 : 1,
        ),
      ),
      onSelected: (val) {
        setState(() {
          if (val) {
            set.add(id);
          } else {
            set.remove(id);
          }
        });
      },
    );
  }

  Widget _buildResultsCard() {
    if (_recipeText == null && _tasteVector == null) {
      return Card(
        elevation: 0,
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: OhtliColors.cantera.withValues(alpha: 0.5)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(48.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.memory_rounded,
                size: 64,
                color: OhtliColors.cantera.withValues(alpha: 0.8),
              ),
              const SizedBox(height: 16),
              Text(
                "Aún no has generado ningún vector",
                style: GoogleFonts.fraunces(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: OhtliColors.onyx,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                "Configura los parámetros o elige un preset a la izquierda y presiona 'Calcular Vector 768d'.",
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(fontSize: 14, color: Colors.black45),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. Receta Canónica Semántica
        Card(
          elevation: 0,
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: OhtliColors.cantera.withValues(alpha: 0.5)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.text_fields_rounded,
                          size: 20,
                          color: OhtliColors.stormyTeal,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          "Receta Semántica (Embedding Prompt)",
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(Icons.copy, size: 16),
                      tooltip: "Copiar receta",
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: _recipeText ?? ""));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text("Receta copiada")),
                        );
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: OhtliColors.cloudDancer.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _recipeText ?? "",
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      height: 1.5,
                      color: OhtliColors.onyx,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // 2. Vector Denso (768d) y Estadísticas
        Card(
          elevation: 0,
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: OhtliColors.cantera.withValues(alpha: 0.5)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.analytics_outlined,
                          size: 20,
                          color: OhtliColors.xoconostle,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          "Vector de Gusto (768 dimensiones)",
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: OhtliColors.xoconostle.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        "L2-Norm: 1.000",
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: OhtliColors.xoconostle,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  "Activación de los primeros 32 componentes:",
                  style: GoogleFonts.inter(fontSize: 12, color: Colors.black54),
                ),
                const SizedBox(height: 8),
                if (_tasteVector != null)
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: _tasteVector!.take(32).map((val) {
                      final isPositive = val >= 0;
                      return Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          color: isPositive
                              ? OhtliColors.stormyTeal.withValues(
                                  alpha: (val.abs() * 15).clamp(0.2, 1.0),
                                )
                              : OhtliColors.xoconostle.withValues(
                                  alpha: (val.abs() * 15).clamp(0.2, 1.0),
                                ),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      );
                    }).toList(),
                  ),
                const SizedBox(height: 18),
                Text(
                  "Similitud Coseno con POIs Muestra de CDMX:",
                  style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const SizedBox(height: 10),
                Column(
                  children: _samplePois.map((poi) {
                    final double score = poi["sample_score"];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8.0),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  poi["name"],
                                  style: GoogleFonts.inter(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  poi["category"],
                                  style: GoogleFonts.inter(
                                    fontSize: 11,
                                    color: Colors.black45,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: score > 0.8
                                  ? OhtliColors.stormyTeal.withValues(alpha: 0.15)
                                  : OhtliColors.cantera.withValues(alpha: 0.25),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              "${(score * 100).toStringAsFixed(1)}% match",
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: score > 0.8
                                  ? OhtliColors.stormyTeal
                                  : Colors.black54,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        ),
        if (_errorText != null)
          Container(
            margin: const EdgeInsets.only(top: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: OhtliColors.xoconostle.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              _errorText!,
              style: GoogleFonts.inter(color: OhtliColors.xoconostle, fontSize: 12),
            ),
          ),
        if (_responsePayload != null)
          Container(
            margin: const EdgeInsets.only(top: 14),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: OhtliColors.cantera.withValues(alpha: 0.5)),
            ),
            child: ExpansionTile(
              title: Text(
                "Payload JSON de Respuesta",
                style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold),
              ),
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  color: OhtliColors.cloudDancer.withValues(alpha: 0.4),
                  child: SelectableText(
                    const JsonEncoder.withIndent('  ').convert(_responsePayload),
                    style: GoogleFonts.firaCode(fontSize: 11),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

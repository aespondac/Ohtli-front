import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import '../../../theme/colors.dart';
import '../widgets/lab_experiment_shell.dart';

class AgentsExperimentPage extends StatefulWidget {
  final VoidCallback onBack;

  const AgentsExperimentPage({super.key, required this.onBack});

  @override
  State<AgentsExperimentPage> createState() => _AgentsExperimentPageState();
}

class _AgentsExperimentPageState extends State<AgentsExperimentPage> {
  final TextEditingController _promptController = TextEditingController(
    text: 'Recomiéndame 3 cantinas históricas con buen ambiente en el Centro Histórico de la CDMX y explica el porqué.',
  );
  String _selectedAgent = 'Recolector';
  bool _isLoading = false;
  String? _rawResponse;
  String? _errorResponse;
  int? _latencyMs;

  final List<String> _presets = [
    'Cantinas históricas en Centro Histórico con ambiente bohemio',
    'Ruta de librerías y cafés de especialidad en Coyoacán',
    'Museos de arte moderno accesibles en transporte público',
    'Mercados gastronómicos tradicionales en Cuauhtémoc',
  ];

  @override
  void dispose() {
    _promptController.dispose();
    super.dispose();
  }

  Future<void> _runAgent() async {
    final prompt = _promptController.text.trim();
    if (prompt.isEmpty) return;

    setState(() {
      _isLoading = true;
      _rawResponse = null;
      _errorResponse = null;
      _latencyMs = null;
    });

    final stopwatch = Stopwatch()..start();

    try {
      final response = await http.post(
        Uri.parse('https://api.ohtli.quest/v1/agent/recolector/test'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'prompt': prompt,
          'agent_type': _selectedAgent.toLowerCase(),
          'sandbox_mode': true,
        }),
      ).timeout(const Duration(seconds: 8));

      stopwatch.stop();
      _latencyMs = stopwatch.elapsedMilliseconds;

      if (response.statusCode == 200) {
        setState(() {
          _rawResponse = response.body;
        });
      } else {
        throw Exception('Servidor respondió con código ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      stopwatch.stop();
      _latencyMs = stopwatch.elapsedMilliseconds;

      // Proveemos respuesta simulada controlada en sandbox para que el tester pueda
      // validar la estructura JSON esperada cuando el backend no esté desplegado
      setState(() {
        _errorResponse = 'Fallo de conexión o timeout al endpoint en Staging ($e).';
        _rawResponse = const JsonEncoder.withIndent('  ').convert({
          "agent": _selectedAgent,
          "sandbox_status": "MOCK_FALLBACK_TEST",
          "intent": "cultural_recommendation",
          "latency_simulated_ms": _latencyMs,
          "prompt_analyzed": prompt,
          "generated_recommendations": [
            {
              "name": "La Ópera Bar",
              "category": "cantinas_tradicionales, historico",
              "reason": "Techo dorado barroco y disparo de Pancho Villa en el techo.",
              "confidence_score": 0.96
            },
            {
              "name": "Cantina La Faena",
              "category": "cantinas_tradicionales, taurino",
              "reason": "Museo taurino popular y ambiente bohemio auténtico.",
              "confidence_score": 0.89
            }
          ]
        });
      });
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return LabExperimentShell(
      title: 'Consola de Agentes I/O',
      subtitle: 'Evaluación y calibración de prompts, schemas JSON y capacidad de razonamiento de agentes autónomos en Yollotl Engine antes de integrarse al asistente de Ohtli.quest.',
      category: 'Agentes IA',
      status: 'ALPHA v0.4',
      statusColor: const Color(0xFF6C5CE7),
      targetModule: 'Ohtli.quest / Asistente Virtual Inteligente',
      onBack: widget.onBack,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildControlsCard(),
          const SizedBox(height: 24),
          if (_isLoading || _rawResponse != null || _errorResponse != null)
            _buildResultsCard(),
        ],
      ),
    );
  }

  Widget _buildControlsCard() {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: OhtliColors.cardBg,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: OhtliColors.cardBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Configuración del Agente a Evaluar',
                style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w700, color: OhtliColors.onyx),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF6C5CE7).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  'Inspección I/O Cruda',
                  style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: const Color(0xFF6C5CE7)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Selector de Agente
          Text(
            'Selecciona el Rol del Agente:',
            style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: OhtliColors.subtleText),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            children: ['Recolector', 'Comparador', 'Generador de Itinerarios'].map((role) {
              final isSelected = _selectedAgent == role;
              return ChoiceChip(
                label: Text(role),
                selected: isSelected,
                onSelected: (val) {
                  if (val) setState(() => _selectedAgent = role);
                },
                selectedColor: const Color(0xFF6C5CE7),
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
              );
            }).toList(),
          ),
          const SizedBox(height: 20),

          // Presets de prompts
          Text(
            'Prompts de Prueba Recomendados:',
            style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: OhtliColors.subtleText),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _presets.map((preset) {
              return ActionChip(
                label: Text(preset),
                avatar: const Icon(Icons.bolt_rounded, size: 14, color: Color(0xFF6C5CE7)),
                onPressed: () => setState(() => _promptController.text = preset),
                backgroundColor: OhtliColors.innerCardBg,
                labelStyle: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500, color: OhtliColors.onyx),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: OhtliColors.cardBorder),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),

          TextField(
            controller: _promptController,
            style: GoogleFonts.inter(color: OhtliColors.onyx),
            decoration: InputDecoration(
              labelText: 'Prompt / Instrucción en Lenguaje Natural',
              labelStyle: GoogleFonts.inter(color: OhtliColors.subtleText),
              alignLabelWithHint: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              filled: true,
              fillColor: OhtliColors.innerCardBg,
            ),
            maxLines: 4,
          ),
          const SizedBox(height: 20),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isLoading ? null : _runAgent,
              icon: _isLoading
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.smart_toy_rounded, size: 20),
              label: Text(_isLoading ? 'Ejecutando Agente...' : 'Ejecutar Agente en Staging'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6C5CE7),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                textStyle: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultsCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: OhtliColors.cardBg,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: OhtliColors.cardBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Salida del Agente (JSON Crudo)',
                style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w700, color: OhtliColors.onyx),
              ),
              Row(
                children: [
                  if (_latencyMs != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(
                        color: OhtliColors.innerCardBg,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: OhtliColors.cardBorder),
                      ),
                      child: Text(
                        '${_latencyMs}ms',
                        style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: const Color(0xFF6C5CE7)),
                      ),
                    ),
                  if (_rawResponse != null)
                    IconButton(
                      icon: Icon(Icons.copy_rounded, size: 18, color: OhtliColors.subtleText),
                      tooltip: 'Copiar JSON',
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: _rawResponse!));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Payload copiado al portapapeles.')),
                        );
                      },
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),

          if (_errorResponse != null)
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: OhtliColors.cempasuchil.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: OhtliColors.cempasuchil.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, size: 20, color: Color(0xFFB85900)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Modo Simulado Activo: $_errorResponse Se muestra estructura de referencia.',
                      style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFFB85900), fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            ),

          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: OhtliColors.innerCardBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: OhtliColors.cardBorder),
            ),
            child: SelectableText(
              _rawResponse ?? 'Cargando respuesta...',
              style: GoogleFonts.firaCode(
                fontSize: 13,
                color: const Color(0xFF55EFC4),
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

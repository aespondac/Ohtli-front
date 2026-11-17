import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
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
  Map<String, dynamic>? _trace; // respuesta del motor: pasos de cada agente

  static const Map<String, String> _agentIds = {
    'Recolector': 'recolector',
    'Comparador': 'comparador',
    'Generador de Itinerarios': 'generador',
  };

  // Punto de partida, presupuesto y radio: el motor los acepta (AgentRunRequest) pero la consola
  // siempre mandaba los valores por omisión (Zócalo, $500, 3 km), así que no se podía probar otra zona.
  static const List<({String name, double lat, double lng})> _origins = [
    (name: 'Zócalo', lat: 19.4326, lng: -99.1332),
    (name: 'Coyoacán', lat: 19.3496, lng: -99.1623),
    (name: 'Roma Norte', lat: 19.4194, lng: -99.1606),
    (name: 'Polanco', lat: 19.4328, lng: -99.1915),
    (name: 'San Ángel', lat: 19.3466, lng: -99.1903),
  ];
  int _originIndex = 0;
  double _budget = 500;
  double _radiusKm = 3;

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
      _trace = null;
      _errorResponse = null;
      _latencyMs = null;
    });

    final stopwatch = Stopwatch()..start();

    try {
      // Agentes reales del motor (antes el endpoint no existía y se mostraba una respuesta inventada).
      final token = await FirebaseAuth.instance.currentUser?.getIdToken();
      final response = await http
          .post(
            Uri.parse('https://api-xluju5gywq-uc.a.run.app/v1/labs/agents/run'), // directo: el gateway corta a los 60 s
            headers: {'Content-Type': 'application/json', if (token != null) 'Authorization': 'Bearer $token'},
            body: jsonEncode({
              'agent': _agentIds[_selectedAgent] ?? 'comparador',
              'prompt': prompt,
              'origin': {'lat': _origins[_originIndex].lat, 'lng': _origins[_originIndex].lng},
              'budget': _budget.roundToDouble(),
              'radius_km': _radiusKm,
            }),
          )
          .timeout(const Duration(seconds: 90));

      stopwatch.stop();
      if (!mounted) return;
      _latencyMs = stopwatch.elapsedMilliseconds;

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        setState(() {
          _trace = decoded;
          _rawResponse = const JsonEncoder.withIndent('  ').convert(decoded);
        });
      } else {
        String detail = '';
        try {
          detail = '${(jsonDecode(response.body) as Map)['detail'] ?? ''}';
        } catch (_) {}
        setState(() => _errorResponse = switch (response.statusCode) {
              401 || 403 => detail.isNotEmpty ? detail : 'Necesitas una sesión de Ohtli Labs para usar la consola.',
              504 => 'El agente tardó demasiado. Intenta de nuevo.',
              _ => 'El motor respondió con un error (${response.statusCode}). $detail',
            });
      }
    } catch (e) {
      stopwatch.stop();
      if (!mounted) return;
      setState(() {
        _latencyMs = stopwatch.elapsedMilliseconds;
        _errorResponse = 'No pudimos contactar al motor. Revisa tu conexión e intenta de nuevo.';
      });
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// Resumen legible de un paso de la traza (la salida completa va en el JSON).
  List<String> _stepLines(Map<String, dynamic> step) {
    final out = Map<String, dynamic>.from((step['salida'] as Map?) ?? const {});
    switch (step['agente']) {
      case 'Interpretación':
        return ['Modelo: ${out['modelo']} · ${out['dimensiones']} dimensiones${out['respaldo'] == true ? ' (respaldo)' : ''}'];
      case 'Recolector':
        final cats = (out['por_categoria'] as Map? ?? {}).entries.take(4).map((e) => '${e.key} (${e.value})').join(', ');
        final near = (out['mas_cercanos'] as List? ?? []).take(5).map((p) => '${(p as Map)['nombre']} · ${p['distancia_km']} km').toList();
        return ['${out['en_radio']} de ${out['catalogo_total']} lugares del catálogo a ${out['radio_km']} km', if (cats.isNotEmpty) 'Categorías: $cats', ...near];
      case 'Comparador':
        final best = (out['mejores'] as List? ?? []).take(5).map((c) => '${(c as Map)['nombre']} · afinidad ${c['afinidad']}').toList();
        return ['${out['candidatos']} candidatos dentro de presupuesto y radio', ...best];
      case 'Generador':
        final alts = (out['alternativas'] as List? ?? []);
        if (alts.isEmpty) return ['No se pudo armar un itinerario con estos candidatos.'];
        return [
          for (final a in alts.cast<Map>())
            '${a['tema']}: ${(a['paradas'] as List? ?? []).map((p) => (p as Map)['nombre']).join(' → ')} · \$${a['costo_total_mxn']} · ${a['horario']}',
        ];
    }
    return const [];
  }

  Widget _buildTrace() {
    final steps = ((_trace?['steps'] as List?) ?? const []).cast<Map>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < steps.length; i++)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: OhtliColors.innerCardBg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: OhtliColors.cardBorder),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Text('${i + 1}. ${steps[i]['agente']}',
                    style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w800, color: const Color(0xFF6C5CE7))),
                Text('${steps[i]['titulo']}', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: OhtliColors.onyx)),
                Text('${steps[i]['ms']} ms', style: GoogleFonts.inter(fontSize: 11.5, color: OhtliColors.subtleText)),
              ]),
              const SizedBox(height: 6),
              for (final line in _stepLines(Map<String, dynamic>.from(steps[i])))
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text('• $line', style: GoogleFonts.inter(fontSize: 12.5, color: OhtliColors.onyx, height: 1.4)),
                ),
            ]),
          ),
        const SizedBox(height: 8),
      ],
    );
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
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              Text(
                'Configuración del agente',
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
                // En un teléfono los ejemplos largos se cortaban sin aviso: hasta dos líneas y "…".
                label: Text(preset, maxLines: 2, overflow: TextOverflow.ellipsis),
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

          Text(
            'Punto de partida:',
            style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: OhtliColors.subtleText),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var i = 0; i < _origins.length; i++)
                ChoiceChip(
                  label: Text(_origins[i].name),
                  avatar: Icon(Icons.location_on_rounded, size: 14,
                      color: i == _originIndex ? Colors.white : const Color(0xFF6C5CE7)),
                  selected: i == _originIndex,
                  onSelected: (v) {
                    if (v) setState(() => _originIndex = i);
                  },
                  selectedColor: const Color(0xFF6C5CE7),
                  labelStyle: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: i == _originIndex ? Colors.white : OhtliColors.onyx,
                  ),
                  backgroundColor: OhtliColors.innerCardBg,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: OhtliColors.cardBorder),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          _buildSlider(
            label: 'Presupuesto por persona',
            value: _budget,
            min: 0,
            max: 3000,
            divisions: 30,
            display: '\$${_budget.round()} MXN',
            onChanged: (v) => setState(() => _budget = v),
          ),
          _buildSlider(
            label: 'Radio de búsqueda',
            value: _radiusKm,
            min: 0.5,
            max: 15,
            divisions: 29,
            display: '${_radiusKm.toStringAsFixed(1)} km',
            onChanged: (v) => setState(() => _radiusKm = v),
          ),
          const SizedBox(height: 12),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isLoading ? null : _runAgent,
              icon: _isLoading
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.smart_toy_rounded, size: 20),
              label: Text(_isLoading ? 'Ejecutando agente…' : 'Ejecutar agente'),
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

  Widget _buildSlider({
    required String label,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required String display,
    required ValueChanged<double> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('$label:',
                  style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: OhtliColors.subtleText)),
            ),
            Text(display, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: OhtliColors.onyx)),
          ],
        ),
        Slider(
          value: value,
          min: min,
          max: max,
          divisions: divisions,
          activeColor: const Color(0xFF6C5CE7),
          label: display,
          onChanged: onChanged,
        ),
      ],
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
                      _errorResponse!,
                      style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFFB85900), fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            ),

          if (_trace != null) _buildTrace(),
          if (_rawResponse != null || _isLoading)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                // Fondo oscuro fijo: el texto verde sobre fondo claro era ilegible en tema claro.
                color: const Color(0xFF1E1E24),
                borderRadius: BorderRadius.circular(16),
              ),
              child: SelectableText(
                _rawResponse ?? 'Ejecutando agente…',
                style: GoogleFonts.firaCode(
                  fontSize: 12.5,
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

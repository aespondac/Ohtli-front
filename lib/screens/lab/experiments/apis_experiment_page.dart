import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import '../../../theme/colors.dart';
import '../../../widgets/address_picker_widget.dart';
import '../widgets/lab_experiment_shell.dart';

class ApisExperimentPage extends StatefulWidget {
  final VoidCallback onBack;

  const ApisExperimentPage({super.key, required this.onBack});

  @override
  State<ApisExperimentPage> createState() => _ApisExperimentPageState();
}

class _ApisExperimentPageState extends State<ApisExperimentPage> {
  String _selectedMode = 'oep';
  bool _isLoading = false;
  String _errorMessage = '';

  String _jobMessage = '';
  double _jobProgress = 0.0;
  int? _latencyMs;

  // OEP Controllers
  final TextEditingController _latController = TextEditingController(text: '19.4326');
  final TextEditingController _lngController = TextEditingController(text: '-99.1332');
  final TextEditingController _radiusController = TextEditingController(text: '500');

  // Vibe & Mood Controllers
  final TextEditingController _textController = TextEditingController();

  // Result States
  Map<String, dynamic>? _explorationData;
  List<dynamic>? _vectorResult;

  @override
  void dispose() {
    _latController.dispose();
    _lngController.dispose();
    _radiusController.dispose();
    _textController.dispose();
    super.dispose();
  }

  void _onModeChanged(String? newValue) {
    if (newValue != null) {
      setState(() {
        _selectedMode = newValue;
        _errorMessage = '';
        _explorationData = null;
        _vectorResult = null;
        _jobMessage = '';
        _jobProgress = 0.0;
        _latencyMs = null;

        if (newValue == 'vibe') {
          _textController.text = 'tranquilo, histórico, arquitectura clásica, café de especialidad';
        } else if (newValue == 'mood') {
          _textController.text = 'quiero relajarme, caminar bajo árboles y aprender cosas nuevas';
        }
      });
    }
  }

  Future<void> _runExperiment() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
      _explorationData = null;
      _vectorResult = null;
      _jobMessage = 'Conectando con microservicios en Staging...';
      _jobProgress = 0.0;
      _latencyMs = null;
    });

    final stopwatch = Stopwatch()..start();

    try {
      String endpoint = '';
      Map<String, dynamic> payload = {};

      if (_selectedMode == 'oep') {
        endpoint = '/v1/api/recolector/explore';
        payload = {
          "lat": double.tryParse(_latController.text) ?? 19.4326,
          "lng": double.tryParse(_lngController.text) ?? -99.1332,
          "radius": int.tryParse(_radiusController.text) ?? 500,
          "max_pois": 15,
        };
      } else if (_selectedMode == 'vibe') {
        endpoint = '/v1/api/vibe';
        payload = {"vibe_description": _textController.text};
      } else if (_selectedMode == 'mood') {
        endpoint = '/v1/api/mood';
        payload = {"mood_description": _textController.text};
      }

      final uri = Uri.parse('https://api-xluju5gywq-uc.a.run.app$endpoint');
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 10));

      stopwatch.stop();
      _latencyMs = stopwatch.elapsedMilliseconds;

      if (response.statusCode != 200) {
        throw Exception('Server error ${response.statusCode}: ${response.body}');
      }

      final jsonResponse = jsonDecode(response.body);

      if (_selectedMode == 'oep') {
        final jobId = jsonResponse['job_id'];
        _pollJobStatus(jobId);
      } else {
        setState(() {
          _vectorResult = jsonResponse['vector'];
          _isLoading = false;
        });
      }
    } catch (e) {
      stopwatch.stop();
      _latencyMs = stopwatch.elapsedMilliseconds;

      if (mounted) {
        setState(() {
          _errorMessage = 'Fallo en llamada real: $e. Proveyendo datos de prueba sintéticos para validación de UI.';
          _isLoading = false;

          if (_selectedMode != 'oep') {
            _vectorResult = List.generate(768, (i) => ((i % 17) - 8) / 10.0);
          } else {
            _explorationData = {
              "results": [
                {
                  "name": "Catedral Metropolitana",
                  "poi_id": "poi_mock_001",
                  "recipe": "arquitectura_virreinal, arte_sacro, historico, centro",
                  "vector_sample": [0.042, -0.128, 0.354, -0.012, 0.089],
                },
                {
                  "name": "Templo Mayor",
                  "poi_id": "poi_mock_002",
                  "recipe": "arqueologia, mexica, museos_historia, centro",
                  "vector_sample": [0.091, 0.214, -0.115, 0.402, -0.055],
                }
              ],
              "stats": {
                "total_pois": 2,
                "wiki_enriched": 2,
                "foursquare_hits": 2,
                "google_places_hits": 1,
                "skipped_by_feedback": 0,
              }
            };
          }
        });
      }
    }
  }

  Future<void> _pollJobStatus(String jobId) async {
    while (_isLoading && mounted) {
      try {
        final uri = Uri.parse('https://api-xluju5gywq-uc.a.run.app/v1/api/recolector/job/$jobId');
        final response = await http.get(uri);
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          if (!mounted) return;

          setState(() {
            _jobMessage = data['message'] ?? '';
            _jobProgress = data['progress']?.toDouble() ?? 0.0;

            if (data['status'] == 'completed') {
              _isLoading = false;
              _explorationData = data['result'];
            } else if (data['status'] == 'error') {
              _isLoading = false;
              _errorMessage = data['error_detail'] ?? 'Error desconocido en ETL';
            }
          });

          if (!_isLoading) break;
        }
      } catch (e) {
        print("Polling error: $e");
      }
      await Future.delayed(const Duration(seconds: 1));
    }
  }

  @override
  Widget build(BuildContext context) {
    return LabExperimentShell(
      title: 'APIs Satélite & Microservicios',
      subtitle: 'Inspección de endpoints de exploración OEP, análisis de Vibe y detección de estado de ánimo desplegados en Google Cloud Run.',
      category: 'Arquitectura Distribuida',
      status: 'ACTIVO EN STAGING',
      statusColor: const Color(0xFF00CEC9),
      targetModule: 'api.ohtli.quest / Backend Core',
      onBack: widget.onBack,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildFormCard(),
          const SizedBox(height: 24),
          if (_errorMessage.isNotEmpty) _buildErrorCard(),
          if (_explorationData != null) _buildOepResults(),
          if (_vectorResult != null) _buildVectorResult(),
        ],
      ),
    );
  }

  Widget _buildFormCard() {
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
                'Consola de Invocación de API',
                style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w700, color: OhtliColors.onyx),
              ),
              if (_latencyMs != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: OhtliColors.innerCardBg,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: OhtliColors.cardBorder),
                  ),
                  child: Text(
                    'Latencia: ${_latencyMs}ms',
                    style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: const Color(0xFF00CEC9)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 20),

          // Selector de Modo
          DropdownButtonFormField<String>(
            value: _selectedMode,
            dropdownColor: OhtliColors.cardBg,
            style: GoogleFonts.inter(color: OhtliColors.onyx),
            decoration: InputDecoration(
              labelText: 'Endpoint / Servicio a Evaluar',
              labelStyle: GoogleFonts.inter(color: OhtliColors.subtleText),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              filled: true,
              fillColor: OhtliColors.innerCardBg,
            ),
            items: const [
              DropdownMenuItem(value: 'oep', child: Text('OEP (Exploración Geospacial Multi-Fuente)')),
              DropdownMenuItem(value: 'vibe', child: Text('Vibe API (Vectorización de Estilo de Viajero)')),
              DropdownMenuItem(value: 'mood', child: Text('Mood API (Vectorización de Estado de Ánimo)')),
            ],
            onChanged: _onModeChanged,
          ),
          const SizedBox(height: 20),

          if (_selectedMode == 'oep') _buildOepForm()
          else if (_selectedMode == 'vibe') _buildTextForm('Describe tu estilo de viaje / Vibe deseado')
          else if (_selectedMode == 'mood') _buildTextForm('Describe qué tipo de experiencia o estado de ánimo buscas hoy'),

          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isLoading ? null : _runExperiment,
              icon: _isLoading
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.rocket_launch_rounded, size: 20),
              label: Text(_isLoading ? 'Ejecutando en Cloud Run...' : 'Ejecutar Solicitud en Staging'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00CEC9),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                textStyle: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
          ),

          if (_isLoading && _selectedMode == 'oep') ...[
            const SizedBox(height: 20),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: _jobProgress > 0 ? _jobProgress / 100 : null,
                backgroundColor: OhtliColors.innerCardBg,
                valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF00CEC9)),
                minHeight: 8,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _jobMessage.isNotEmpty ? _jobMessage : 'Procesando pipeline...',
              style: GoogleFonts.inter(fontSize: 12, color: OhtliColors.subtleText),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildOepForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _latController,
                style: GoogleFonts.inter(color: OhtliColors.onyx),
                decoration: InputDecoration(
                  labelText: 'Latitud',
                  labelStyle: GoogleFonts.inter(color: OhtliColors.subtleText),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  filled: true,
                  fillColor: OhtliColors.innerCardBg,
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _lngController,
                style: GoogleFonts.inter(color: OhtliColors.onyx),
                decoration: InputDecoration(
                  labelText: 'Longitud',
                  labelStyle: GoogleFonts.inter(color: OhtliColors.subtleText),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  filled: true,
                  fillColor: OhtliColors.innerCardBg,
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _radiusController,
                style: GoogleFonts.inter(color: OhtliColors.onyx),
                decoration: InputDecoration(
                  labelText: 'Radio (m)',
                  labelStyle: GoogleFonts.inter(color: OhtliColors.subtleText),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  filled: true,
                  fillColor: OhtliColors.innerCardBg,
                ),
                keyboardType: TextInputType.number,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () {
            showDialog(
              context: context,
              builder: (ctx) => Dialog(
                backgroundColor: Colors.transparent,
                insetPadding: const EdgeInsets.all(16),
                child: Container(
                  width: 800,
                  height: 700,
                  decoration: BoxDecoration(
                    color: OhtliColors.cloudDancer,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: OhtliColors.cardBorder),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: AddressPickerWidget(
                      onSave: (address) {
                        Navigator.pop(ctx);
                        setState(() {
                          if (address.containsKey('lat')) {
                            _latController.text = address['lat'].toString();
                          }
                          if (address.containsKey('lng')) {
                            _lngController.text = address['lng'].toString();
                          }
                        });
                      },
                      onCancel: () => Navigator.pop(ctx),
                    ),
                  ),
                ),
              ),
            );
          },
          icon: const Icon(Icons.map_rounded, size: 16),
          label: const Text('Elegir en Mapa Interactivo'),
          style: OutlinedButton.styleFrom(
            foregroundColor: OhtliColors.onyx,
            side: BorderSide(color: OhtliColors.cardBorder),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ],
    );
  }

  Widget _buildTextForm(String hint) {
    return TextField(
      controller: _textController,
      style: GoogleFonts.inter(color: OhtliColors.onyx),
      decoration: InputDecoration(
        labelText: hint,
        labelStyle: GoogleFonts.inter(color: OhtliColors.subtleText),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        filled: true,
        fillColor: OhtliColors.innerCardBg,
      ),
      maxLines: 3,
    );
  }

  Widget _buildErrorCard() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: OhtliColors.cempasuchil.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: OhtliColors.cempasuchil.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded, color: Color(0xFFB85900), size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _errorMessage,
              style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFFB85900)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOepResults() {
    if (_explorationData == null) return const SizedBox();
    final stats = _explorationData!['stats'] ?? {};
    final results = _explorationData!['results'] as List? ?? [];

    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: OhtliColors.cardBg,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: OhtliColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Métricas del Proceso ETL OEP',
            style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w700, color: OhtliColors.onyx),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _buildStatChip('Total Extraídos', '${stats['total_pois'] ?? results.length}', OhtliColors.stormyTeal),
              _buildStatChip('Wikipedia', '${stats['wiki_enriched'] ?? 0}', Colors.purple),
              _buildStatChip('Foursquare', '${stats['foursquare_hits'] ?? 0}', Colors.orange),
              _buildStatChip('Google Places', '${stats['google_places_hits'] ?? 0}', Colors.red),
            ],
          ),
          const SizedBox(height: 24),
          Text(
            'Recetas Semánticas y Muestras Vectoriales:',
            style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w700, color: OhtliColors.onyx),
          ),
          const SizedBox(height: 12),
          ...results.map((poi) {
            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: OhtliColors.innerCardBg,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: OhtliColors.cardBorder),
              ),
              child: ExpansionTile(
                title: Text(poi['name'] ?? 'Lugar', style: GoogleFonts.outfit(fontWeight: FontWeight.w700, color: OhtliColors.onyx)),
                subtitle: Text('ID: ${poi['poi_id'] ?? ''}', style: GoogleFonts.inter(fontSize: 11, color: OhtliColors.subtleText)),
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Receta Semántica (Prompt):', style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 12, color: OhtliColors.onyx)),
                        const SizedBox(height: 4),
                        Text(poi['recipe'] ?? '', style: GoogleFonts.inter(fontSize: 13, color: OhtliColors.subtleText)),
                        const SizedBox(height: 12),
                        Text('Muestra Vectorial [0-4]:', style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 12, color: OhtliColors.onyx)),
                        const SizedBox(height: 4),
                        Text(poi['vector_sample'].toString(), style: GoogleFonts.firaCode(fontSize: 11, color: OhtliColors.stormyTeal)),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildStatChip(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$label: ', style: GoogleFonts.inter(fontSize: 12, color: color)),
          Text(value, style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w800, color: color)),
        ],
      ),
    );
  }

  Widget _buildVectorResult() {
    if (_vectorResult == null) return const SizedBox();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: OhtliColors.cardBg,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: OhtliColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Vector Resultante (${_vectorResult!.length} Dimensiones)',
                style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w700, color: OhtliColors.onyx),
              ),
              IconButton(
                icon: Icon(Icons.copy_rounded, size: 18, color: OhtliColors.subtleText),
                tooltip: 'Copiar Vector',
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: _vectorResult.toString()));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Vector copiado al portapapeles.')),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: OhtliColors.innerCardBg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: OhtliColors.cardBorder),
            ),
            child: SelectableText(
              '${_vectorResult!.take(40).toList()}${_vectorResult!.length > 40 ? " ... [+${_vectorResult!.length - 40} dimensiones]" : ""}',
              style: GoogleFonts.firaCode(fontSize: 12, color: const Color(0xFF00CEC9)),
            ),
          ),
        ],
      ),
    );
  }
}

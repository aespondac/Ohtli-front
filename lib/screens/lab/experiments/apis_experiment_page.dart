import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import '../../../theme/colors.dart';
import '../../../widgets/address_picker_widget.dart';
import '../widgets/lab_experiment_shell.dart';
import '../../../labs/lab_access.dart';

class ApisExperimentPage extends StatefulWidget {
  final VoidCallback onBack;

  const ApisExperimentPage({super.key, required this.onBack});

  @override
  State<ApisExperimentPage> createState() => _ApisExperimentPageState();
}

class _ApisExperimentPageState extends State<ApisExperimentPage> {
  // La exploración (OEP) escribe en el catálogo y el motor solo la acepta de miembros del
  // laboratorio; a los testers se les muestran Vibe y Mood.
  final bool _canExplore = currentLabRole.isMember;
  late String _selectedMode = _canExplore ? 'oep' : 'vibe';
  // Cambia con cada ejecución o cambio de modo: un sondeo anterior se detiene al verlo distinto.
  int _runSeq = 0;
  static const int _maxPolls = 600; // ~10 min: la exploración tarda 10-15 s por lugar (el motor la detiene a los 9)
  bool _isLoading = false;
  String _errorMessage = '';

  String _jobMessage = '';
  double _jobProgress = 0.0;
  int? _latencyMs;

  // OEP Controllers
  final TextEditingController _latController = TextEditingController(text: '19.4326');
  final TextEditingController _lngController = TextEditingController(text: '-99.1332');
  final TextEditingController _radiusController = TextEditingController(text: '500');

  // Vibe & Mood Controllers (los testers empiezan en Vibe: lleva un ejemplo para probar de inmediato)
  late final TextEditingController _textController =
      TextEditingController(text: _canExplore ? '' : 'tranquilo, histórico, arquitectura clásica, café de especialidad');

  // Comparar: un vector suelto no dice nada a un tester; dos textos y su similitud coseno sí.
  final TextEditingController _compareController =
      TextEditingController(text: 'ruidoso, fiesta, antros y música electrónica hasta tarde');

  // Result States
  Map<String, dynamic>? _explorationData;
  List<dynamic>? _vectorResult;
  double? _similarity;

  @override
  void dispose() {
    _latController.dispose();
    _lngController.dispose();
    _radiusController.dispose();
    _textController.dispose();
    _compareController.dispose();
    super.dispose();
  }

  void _onModeChanged(String? newValue) {
    if (newValue != null) {
      setState(() {
        _runSeq++; // detiene el sondeo de una exploración anterior
        _isLoading = false;
        _selectedMode = newValue;
        _errorMessage = '';
        _explorationData = null;
        _vectorResult = null;
        _similarity = null;
        _jobMessage = '';
        _jobProgress = 0.0;
        _latencyMs = null;

        if (newValue == 'compare') {
          _textController.text = 'tranquilo, histórico, arquitectura clásica, café de especialidad';
        } else if (newValue == 'vibe') {
          _textController.text = 'tranquilo, histórico, arquitectura clásica, café de especialidad';
        } else if (newValue == 'mood') {
          _textController.text = 'quiero relajarme, caminar bajo árboles y aprender cosas nuevas';
        }
      });
    }
  }

  Future<void> _runExperiment() async {
    final seq = ++_runSeq;
    setState(() {
      _isLoading = true;
      _errorMessage = '';
      _explorationData = null;
      _vectorResult = null;
      _similarity = null;
      _jobMessage = 'Conectando con microservicios en Staging...';
      _jobProgress = 0.0;
      _latencyMs = null;
    });

    final stopwatch = Stopwatch()..start();

    try {
      if (_selectedMode == 'compare') {
        final vectors = await Future.wait([_vibeVector(_textController.text), _vibeVector(_compareController.text)]);
        stopwatch.stop();
        if (!mounted || seq != _runSeq) return;
        setState(() {
          _latencyMs = stopwatch.elapsedMilliseconds;
          _similarity = _cosine(vectors[0], vectors[1]);
          _vectorResult = vectors[0];
          _isLoading = false;
        });
        return;
      }
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
      // La exploración (OEP) solo la aceptan miembros de Ohtli Labs: el motor verifica el ID token.
      final token = await FirebaseAuth.instance.currentUser?.getIdToken();
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json', if (token != null) 'Authorization': 'Bearer $token'},
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 30)); // un arranque en frío de Cloud Run pasa de 10 s

      stopwatch.stop();
      if (!mounted || seq != _runSeq) return;
      _latencyMs = stopwatch.elapsedMilliseconds;

      if (response.statusCode == 401 || response.statusCode == 403) {
        throw Exception('solo los miembros del laboratorio pueden lanzar exploraciones');
      }
      if (response.statusCode != 200) {
        throw Exception('el servicio respondió ${response.statusCode}');
      }

      final jsonResponse = jsonDecode(response.body);

      if (_selectedMode == 'oep') {
        final jobId = jsonResponse['job_id'];
        _pollJobStatus(jobId, seq);
      } else {
        setState(() {
          _vectorResult = jsonResponse['vector'];
          _isLoading = false;
        });
      }
    } catch (e) {
      stopwatch.stop();
      if (!mounted || seq != _runSeq) return;
      // Sin datos inventados (antes se mostraba un vector de 768 valores y estadísticas falsas).
      setState(() {
        _latencyMs = stopwatch.elapsedMilliseconds;
        _errorMessage = 'No se pudo completar la prueba: ${e.toString().replaceFirst('Exception: ', '')}.';
        _isLoading = false;
      });
    }
  }

  static const _apiBase = 'https://api-xluju5gywq-uc.a.run.app';

  Future<List<double>> _vibeVector(String text) async {
    final response = await http
        .post(
          Uri.parse('$_apiBase/v1/api/vibe'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'vibe_description': text}),
        )
        .timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) throw Exception('el servicio respondió ${response.statusCode}');
    final vec = (jsonDecode(response.body) as Map)['vector'] as List?;
    if (vec == null || vec.isEmpty) throw Exception('el servicio no devolvió un vector');
    return vec.map((e) => (e as num).toDouble()).toList();
  }

  static double _cosine(List<double> a, List<double> b) {
    var dot = 0.0, na = 0.0, nb = 0.0;
    for (var i = 0; i < math.min(a.length, b.length); i++) {
      dot += a[i] * b[i];
      na += a[i] * a[i];
      nb += b[i] * b[i];
    }
    if (na < 1e-12 || nb < 1e-12) return 0;
    return (dot / (math.sqrt(na) * math.sqrt(nb))).clamp(-1.0, 1.0);
  }

  /// Sondea la exploración hasta que termina, falla, se cambia de modo o pasan ~10 min.
  Future<void> _pollJobStatus(String jobId, int seq) async {
    for (var i = 0; i < _maxPolls; i++) {
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted || seq != _runSeq) return;
      try {
        final uri = Uri.parse('https://api-xluju5gywq-uc.a.run.app/v1/api/recolector/job/$jobId');
        final response = await http.get(uri).timeout(const Duration(seconds: 8));
        if (!mounted || seq != _runSeq) return;
        if (response.statusCode != 200) continue;
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final status = data['status'];
        setState(() {
          _jobMessage = data['message'] ?? '';
          _jobProgress = (data['progress'] as num?)?.toDouble() ?? 0.0;
          if (status == 'completed') {
            _isLoading = false;
            _explorationData = data['result'];
          } else if (status == 'error') {
            _isLoading = false;
            _errorMessage = data['error_detail'] ?? 'La exploración terminó con error.';
          } else if (status == 'not_found') {
            _isLoading = false;
            _errorMessage = 'El motor no encontró la exploración. Intenta lanzarla de nuevo.';
          }
        });
        if (!_isLoading) return;
      } catch (_) {
        // un sondeo fallido no detiene la espera; el límite de intentos sí
      }
    }
    if (mounted && seq == _runSeq) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'La exploración no terminó en 10 minutos y el motor la detuvo. Prueba con un radio menor.';
      });
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
          if (_similarity != null) _buildSimilarityResult(),
          if (_vectorResult != null && _similarity == null) _buildVectorResult(),
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
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              Text(
                'Consola de invocación de API',
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
                    style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: const Color(0xFF00796B)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 20),

          // Selector de Modo
          DropdownButtonFormField<String>(
            value: _selectedMode,
            // El texto largo se encimaba con la flecha en un teléfono.
            isExpanded: true,
            dropdownColor: OhtliColors.cardBg,
            style: GoogleFonts.inter(color: OhtliColors.onyx),
            decoration: InputDecoration(
              labelText: 'Endpoint / Servicio a Evaluar',
              labelStyle: GoogleFonts.inter(color: OhtliColors.subtleText),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              filled: true,
              fillColor: OhtliColors.innerCardBg,
            ),
            items: [
              if (_canExplore)
                const DropdownMenuItem(value: 'oep', child: Text('OEP (exploración geoespacial multifuente)', overflow: TextOverflow.ellipsis)),
              const DropdownMenuItem(value: 'vibe', child: Text('Vibe API (vectorización del estilo de viaje)', overflow: TextOverflow.ellipsis)),
              const DropdownMenuItem(value: 'mood', child: Text('Mood API (vectorización del estado de ánimo)', overflow: TextOverflow.ellipsis)),
              const DropdownMenuItem(value: 'compare', child: Text('Comparar dos vibras (similitud semántica)', overflow: TextOverflow.ellipsis)),
            ],
            onChanged: _onModeChanged,
          ),
          const SizedBox(height: 20),

          if (_selectedMode == 'oep') _buildOepForm()
          else if (_selectedMode == 'vibe') _buildTextForm('Describe tu estilo de viaje / Vibe deseado')
          else if (_selectedMode == 'mood') _buildTextForm('Describe qué tipo de experiencia o estado de ánimo buscas hoy')
          else if (_selectedMode == 'compare') ...[
            _buildTextForm('Vibra A'),
            const SizedBox(height: 12),
            _buildTextForm('Vibra B', controller: _compareController),
          ],

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
                // Blanco sobre turquesa claro no se leía (≈2:1): turquesa oscuro.
                backgroundColor: const Color(0xFF00796B),
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
        LabFieldRow(
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

  Widget _buildTextForm(String hint, {TextEditingController? controller}) {
    return TextField(
      controller: controller ?? _textController,
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

  Widget _buildSimilarityResult() {
    final sim = _similarity!;
    // Medido con el servicio (que antepone "Vibras y ambiente deseado:" a todo texto): opuestos ≈0.70,
    // relacionados ≈0.78, paráfrasis ≈0.95.
    final (verdict, color) = sim >= 0.92
        ? ('Casi la misma vibra', OhtliColors.stormyTeal)
        : sim >= 0.80
            ? ('Vibras afines', const Color(0xFF00796B))
            : sim >= 0.75
                ? ('Algo en común', const Color(0xFFB85900))
                : ('Vibras distintas', OhtliColors.xoconostle);
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
          Text('Similitud coseno entre A y B',
              style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w700, color: OhtliColors.onyx)),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(sim.toStringAsFixed(3),
                  style: GoogleFonts.outfit(fontSize: 34, fontWeight: FontWeight.w800, color: color)),
              const SizedBox(width: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 7),
                  child: Text(verdict, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700, color: color)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: sim.clamp(0.0, 1.0),
              minHeight: 8,
              backgroundColor: OhtliColors.innerCardBg,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Es la misma medida que usa el Comparador para emparejar tus gustos con los lugares. '
            'Con este servicio nunca baja mucho: vibras opuestas quedan cerca de 0.70 y arriba de 0.92 dicen casi lo mismo.',
            style: GoogleFonts.inter(fontSize: 12, color: OhtliColors.subtleText, height: 1.45),
          ),
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
          LabCodeBlock(
            text: '${_vectorResult!.take(40).toList()}${_vectorResult!.length > 40 ? " ... [+${_vectorResult!.length - 40} dimensiones]" : ""}',
            color: const Color(0xFF00CEC9),
          ),
        ],
      ),
    );
  }
}

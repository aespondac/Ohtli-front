import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import '../../../theme/colors.dart';
import '../../../models/poi_model.dart';
import '../../places/places_page.dart';
import '../widgets/lab_experiment_shell.dart';
import '../../../labs/lab_access.dart';

class RecolectorExperimentPage extends StatefulWidget {
  final VoidCallback onBack;

  const RecolectorExperimentPage({super.key, required this.onBack});

  @override
  State<RecolectorExperimentPage> createState() => _RecolectorExperimentPageState();
}

class _RecolectorExperimentPageState extends State<RecolectorExperimentPage> {
  final TextEditingController _latController = TextEditingController(text: '19.432608');
  final TextEditingController _lngController = TextEditingController(text: '-99.133209');
  final TextEditingController _radiusController = TextEditingController(text: '1000');

  // Explorar y replicar escriben en el catálogo: el motor solo lo acepta de miembros del
  // laboratorio. Los testers ven el catálogo ya indexado.
  final bool _canWrite = currentLabRole.isMember;
  String? _currentJobId;
  Map<String, dynamic>? _job; // estado del trabajo de exploración (lo da el motor)
  int _pollSeq = 0;
  final Set<String> _selectedPois = {};
  bool _isReplicating = false;

  final List<Map<String, dynamic>> _presets = [
    {'name': 'Zócalo CDMX', 'lat': 19.432608, 'lng': -99.133209, 'radius': 1000},
    {'name': 'Coyoacán Centro', 'lat': 19.3496, 'lng': -99.1623, 'radius': 800},
    {'name': 'Roma Norte', 'lat': 19.4194, 'lng': -99.1606, 'radius': 800},
    {'name': 'Chapultepec', 'lat': 19.4204, 'lng': -99.1822, 'radius': 1200},
    {'name': 'Polanco', 'lat': 19.4328, 'lng': -99.1915, 'radius': 1000},
  ];

  @override
  void dispose() {
    _latController.dispose();
    _lngController.dispose();
    _radiusController.dispose();
    super.dispose();
  }

  void _applyPreset(Map<String, dynamic> preset) {
    setState(() {
      _latController.text = preset['lat'].toString();
      _lngController.text = preset['lng'].toString();
      _radiusController.text = preset['radius'].toString();
    });
  }

  void _runExploration() async {
    final lat = double.tryParse(_latController.text);
    final lng = double.tryParse(_lngController.text);
    final radius = int.tryParse(_radiusController.text);

    if (lat == null || lng == null || radius == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Por favor ingresa coordenadas válidas.')),
      );
      return;
    }

    // El trabajo lo encola el motor (antes se escribía en una colección del front que las reglas
    // bloquean y que el motor no escucha, así que la exploración siempre fallaba).
    try {
      final token = await FirebaseAuth.instance.currentUser?.getIdToken();
      final response = await http
          .post(
            Uri.parse('https://api.ohtli.quest/v1/api/recolector/explore'),
            headers: {'Content-Type': 'application/json', if (token != null) 'Authorization': 'Bearer $token'},
            body: jsonEncode({'lat': lat, 'lng': lng, 'radius': radius, 'max_pois': 20}),
          )
          .timeout(const Duration(seconds: 20));
      if (response.statusCode == 401 || response.statusCode == 403) {
        throw Exception('solo los miembros del laboratorio pueden explorar zonas');
      }
      if (response.statusCode != 200) throw Exception('el motor respondió ${response.statusCode}');
      final jobId = (jsonDecode(response.body) as Map)['job_id'] as String;
      if (!mounted) return;
      final seq = ++_pollSeq;
      setState(() {
        _currentJobId = jobId;
        _job = {'status': 'pending', 'progress': 0, 'message': 'Encolando en Yollotl Engine… (20 lugares tardan unos 5 minutos)'};
        _selectedPois.clear();
      });
      _pollJob(jobId, seq);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No se pudo iniciar la exploración: ${e.toString().replaceFirst('Exception: ', '')}.'),
            backgroundColor: OhtliColors.xoconostle,
          ),
        );
      }
    }
  }

  /// Sigue el trabajo en el motor hasta que termina, falla o pasan ~10 minutos (el motor lo
  /// detiene a los 9: enriquecer cada lugar toma 10-15 s, así que 20 lugares son ~5 min).
  Future<void> _pollJob(String jobId, int seq) async {
    for (var i = 0; i < 400; i++) {
      await Future.delayed(const Duration(milliseconds: 1500));
      if (!mounted || seq != _pollSeq) return;
      try {
        final res = await http
            .get(Uri.parse('https://api.ohtli.quest/v1/api/recolector/job/$jobId'))
            .timeout(const Duration(seconds: 10));
        if (!mounted || seq != _pollSeq) return;
        if (res.statusCode != 200) continue;
        final data = Map<String, dynamic>.from(jsonDecode(res.body) as Map);
        setState(() => _job = data);
        final status = data['status'];
        if (status == 'completed' || status == 'error' || status == 'not_found') return;
      } catch (_) {
        // un sondeo fallido no detiene la espera; el límite de intentos sí
      }
    }
    if (mounted && seq == _pollSeq) {
      setState(() => _job = {
            'status': 'error',
            'error_detail': 'La exploración no terminó en 10 minutos y el motor la detuvo. Prueba con un radio menor.',
          });
    }
  }

  Future<void> _replicateToProd() async {
    if (_selectedPois.isEmpty) return;

    setState(() => _isReplicating = true);

    try {
      // El motor solo acepta a miembros de Ohtli Labs (verifica el ID token).
      final token = await FirebaseAuth.instance.currentUser?.getIdToken();
      final response = await http.post(
        Uri.parse('https://api.ohtli.quest/v1/api/recolector/replicate'),
        headers: {'Content-Type': 'application/json', if (token != null) 'Authorization': 'Bearer $token'},
        body: jsonEncode({'poi_ids': _selectedPois.toList()}),
      );

      if (response.statusCode == 401 || response.statusCode == 403) {
        throw Exception('solo los miembros de Ohtli Labs pueden replicar lugares a producción');
      }
      if (response.statusCode == 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        final replicated = (body['replicated'] as num?)?.toInt() ?? 0;
        final rejected = (body['errors'] as List?)?.length ?? 0;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  'Replicación: $replicated de ${_selectedPois.length} lugares agregados a Ohtli.quest'
                  '${rejected > 0 ? ' ($rejected rechazados)' : ''}.',
                  style: GoogleFonts.inter()),
              backgroundColor: OhtliColors.stormyTeal,
            ),
          );
        }
      } else {
        throw Exception('Error del servidor: ${response.statusCode}');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Falló la replicación a producción: $e', style: GoogleFonts.inter()),
            backgroundColor: OhtliColors.xoconostle,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isReplicating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LabExperimentShell(
      title: 'Descubridor de lugares (Recolector geoespacial)',
      subtitle: 'Extracción multi-fuente de puntos de interés (POIs), normalización semántica y replicación selectiva a la base de producción de Ohtli.quest.',
      category: 'Geointeligencia',
      status: 'CANDIDATO A PROD v1.0',
      statusColor: const Color(0xFF10B981),
      targetModule: 'Ohtli.quest / Explorador de POIs',
      onBack: widget.onBack,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              color: OhtliColors.stormyTeal.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: OhtliColors.stormyTeal.withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                const Icon(Icons.travel_explore_rounded, color: OhtliColors.stormyTeal, size: 24),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Catálogo de Lugares ya Indexados',
                        style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.w700, color: OhtliColors.onyx),
                      ),
                      Text(
                        'Visualiza y filtra los lugares de la CDMX ya procesados por el Recolector con su tarjeta de información, vectores y receta semántica.',
                        style: GoogleFonts.inter(fontSize: 12, color: OhtliColors.subtleText),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => PlacesPage(
                          showBackButton: true,
                          onBack: () => Navigator.of(context).pop(),
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.grid_view_rounded, size: 16),
                  label: const Text('Ver Lugares'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: OhtliColors.stormyTeal,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    textStyle: GoogleFonts.outfit(fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          if (_canWrite) ...[
            _buildForm(),
            const SizedBox(height: 32),
            if (_currentJobId != null) _buildJobStream(),
          ] else
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: OhtliColors.cardBg,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: OhtliColors.cardBorder),
              ),
              child: Row(children: [
                Icon(Icons.lock_outline_rounded, color: OhtliColors.subtleText),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Explorar zonas nuevas y publicar lugares en Ohtli es trabajo del equipo del laboratorio. '
                    'Como tester puedes revisar el catálogo que ya procesó el Recolector y contarnos qué falta o qué está mal.',
                    style: GoogleFonts.inter(fontSize: 13, color: OhtliColors.subtleText, height: 1.45),
                  ),
                ),
              ]),
            ),
        ],
      ),
    );
  }

  Widget _buildForm() {
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
                'Parámetros de exploración geoespacial',
                style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w700, color: OhtliColors.onyx),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: OhtliColors.stormyTeal.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  'Máx. 20 POIs en sandbox',
                  style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: OhtliColors.stormyTeal),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Presets rápidos
          Text(
            'Presets de Ubicación CDMX para Prueba Rápida:',
            style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: OhtliColors.subtleText),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _presets.map((preset) {
              return ActionChip(
                label: Text(preset['name']),
                avatar: const Icon(Icons.location_on_rounded, size: 14, color: OhtliColors.stormyTeal),
                onPressed: () => _applyPreset(preset),
                backgroundColor: OhtliColors.innerCardBg,
                labelStyle: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: OhtliColors.onyx),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: OhtliColors.cardBorder),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),

          // Campos de texto
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
                ),
              ),
              const SizedBox(width: 16),
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
                ),
              ),
              const SizedBox(width: 16),
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
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _runExploration,
              icon: const Icon(Icons.travel_explore_rounded, size: 20),
              label: const Text('Iniciar Prueba de Exploración'),
              style: ElevatedButton.styleFrom(
                backgroundColor: OhtliColors.stormyTeal,
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

  Widget _buildJobStream() {
    return Builder(
      builder: (context) {
        final data = _job ?? const <String, dynamic>{};
        final status = data['status'] ?? 'pending';
        final progress = data['progress'] ?? 0;
        final message = data['message'] ?? '';

        if (status == 'completed' && data.containsKey('result')) {
          final rawResults = data['result']['results'] as List? ?? [];
          final results = rawResults.where((r) {
            if (r is! Map) return false;
            final id = (r['poi_id'] ?? '').toString();
            final name = (r['name'] ?? '').toString();
            final cat = (r['category'] ?? '').toString();
            return Poi.isValidPoiNameAndId(name, id, cat);
          }).toList();
          return _buildResults(results);
        }

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: OhtliColors.cardBg,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: OhtliColors.cardBorder),
          ),
          child: Column(
            children: [
              if (status == 'error' || status == 'not_found')
                Text(
                  status == 'not_found'
                      ? 'El motor no encontró esta exploración. Lánzala de nuevo.'
                      : 'Error en ejecución: ${data['error_detail'] ?? 'Detalle no provisto'}',
                  style: GoogleFonts.firaCode(color: OhtliColors.xoconostle),
                )
              else ...[
                CircularProgressIndicator(
                  value: progress > 0 ? progress / 100 : null,
                  color: OhtliColors.stormyTeal,
                  strokeWidth: 3,
                ),
                const SizedBox(height: 20),
                Text('$progress%', style: GoogleFonts.outfit(fontSize: 32, fontWeight: FontWeight.w800, color: OhtliColors.onyx)),
                const SizedBox(height: 8),
                Text(message, style: GoogleFonts.inter(fontSize: 14, color: OhtliColors.subtleText)),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildResults(List results) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'POIs Extraídos en Sandbox (${results.length})',
                  style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.w800, color: OhtliColors.onyx),
                ),
                Text(
                  'Selecciona los lugares verificados para certificar y replicar a la base de producción de Ohtli.quest.',
                  style: GoogleFonts.inter(fontSize: 13, color: OhtliColors.subtleText),
                ),
              ],
            ),
            if (_selectedPois.isNotEmpty)
              ElevatedButton.icon(
                onPressed: _isReplicating ? null : _replicateToProd,
                icon: _isReplicating
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.cloud_upload_rounded, size: 16),
                label: Text('Replicar a Ohtli.quest (${_selectedPois.length})'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: OhtliColors.cempasuchil,
                  foregroundColor: Colors.black,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  textStyle: GoogleFonts.outfit(fontWeight: FontWeight.w700),
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),

        Row(
          children: [
            TextButton(
              onPressed: () {
                setState(() {
                  _selectedPois.clear();
                  for (var r in results) {
                    final id = r['poi_id'] ?? '';
                    if (id.isNotEmpty) _selectedPois.add(id);
                  }
                });
              },
              child: const Text('Seleccionar Todos'),
            ),
            const SizedBox(width: 12),
            TextButton(
              onPressed: () => setState(() => _selectedPois.clear()),
              child: const Text('Limpiar Selección'),
            ),
          ],
        ),
        const SizedBox(height: 12),

        ...results.map((r) {
          final id = r['poi_id'] ?? '';
          final name = r['name'] ?? 'Lugar sin nombre';
          final recipe = r['recipe'] ?? 'Sin receta semántica';
          final address = r['address'] ?? '';
          final isSelected = _selectedPois.contains(id);

          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: OhtliColors.cardBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isSelected ? OhtliColors.stormyTeal : OhtliColors.cardBorder,
                width: isSelected ? 2 : 1,
              ),
            ),
            child: CheckboxListTile(
              value: isSelected,
              onChanged: (val) {
                setState(() {
                  if (val == true) {
                    _selectedPois.add(id);
                  } else {
                    _selectedPois.remove(id);
                  }
                });
              },
              title: Text(name, style: GoogleFonts.outfit(fontWeight: FontWeight.w700, fontSize: 16, color: OhtliColors.onyx)),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (address.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(address, style: GoogleFonts.inter(fontSize: 12, color: OhtliColors.subtleText)),
                  ],
                  const SizedBox(height: 6),
                  Text(
                    recipe,
                    style: GoogleFonts.firaCode(fontSize: 11, color: OhtliColors.stormyTeal),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
              activeColor: OhtliColors.stormyTeal,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            ),
          );
        }),
      ],
    );
  }
}

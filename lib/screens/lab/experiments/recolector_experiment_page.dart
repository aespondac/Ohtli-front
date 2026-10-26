import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import '../../../theme/colors.dart';
import '../../places/places_page.dart';
import '../widgets/lab_experiment_shell.dart';

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

  String? _currentJobId;
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

    try {
      final docRef = await FirebaseFirestore.instance.collection('recolector_jobs').add({
        'status': 'pending',
        'progress': 0,
        'message': 'Encolando en Yollotl Engine...',
        'created_at': FieldValue.serverTimestamp(),
        'request': {
          'lat': lat,
          'lng': lng,
          'radius': radius,
          'max_pois': 20,
        }
      });

      setState(() {
        _currentJobId = docRef.id;
        _selectedPois.clear();
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al crear job en Firestore: $e'),
            backgroundColor: OhtliColors.xoconostle,
          ),
        );
      }
    }
  }

  Future<void> _replicateToProd() async {
    if (_selectedPois.isEmpty) return;

    setState(() => _isReplicating = true);

    try {
      final response = await http.post(
        Uri.parse('https://api.ohtli.quest/v1/api/recolector/replicate'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'poi_ids': _selectedPois.toList()}),
      );

      if (response.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Replicación exitosa: ${_selectedPois.length} POIs agregados a Ohtli.quest.', style: GoogleFonts.inter()),
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
      title: 'Caza Lugares (Motor Recolector Geospacial)',
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
          _buildForm(),
          const SizedBox(height: 32),
          if (_currentJobId != null) _buildJobStream(),
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Parámetros de Prueba Geospacial',
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
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('recolector_jobs').doc(_currentJobId).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || !snapshot.data!.exists) {
          return const Center(child: CircularProgressIndicator(color: OhtliColors.stormyTeal));
        }

        final data = snapshot.data!.data() as Map<String, dynamic>;
        final status = data['status'] ?? 'pending';
        final progress = data['progress'] ?? 0;
        final message = data['message'] ?? '';

        if (status == 'completed' && data.containsKey('result')) {
          final results = data['result']['results'] as List? ?? [];
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
              if (status == 'error')
                Text(
                  'Error en ejecución: ${data['error_detail'] ?? 'Detalle no provisto'}',
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

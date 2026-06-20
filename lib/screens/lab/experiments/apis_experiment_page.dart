import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../theme/colors.dart';
import '../../../widgets/address_picker_widget.dart';

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
  
  // OEP Controllers
  final TextEditingController _latController = TextEditingController(text: '19.4326');
  final TextEditingController _lngController = TextEditingController(text: '-99.1332');
  final TextEditingController _radiusController = TextEditingController(text: '500');
  
  // Vibe & Mood Controllers
  final TextEditingController _textController = TextEditingController();
  
  // Result States
  Map<String, dynamic>? _explorationData;
  List<dynamic>? _vectorResult;

  void _onModeChanged(String? newValue) {
    if (newValue != null) {
      setState(() {
        _selectedMode = newValue;
        _errorMessage = '';
        _explorationData = null;
        _vectorResult = null;
        _jobMessage = '';
        _jobProgress = 0.0;
        
        if (newValue == 'vibe') {
          _textController.text = 'tranquilo, histórico, arquitectura clásica';
        } else if (newValue == 'mood') {
          _textController.text = 'quiero relajarme y aprender cosas nuevas';
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
      _jobMessage = 'Conectando con Yollotl Engine...';
      _jobProgress = 0.0;
    });

    try {
      String endpoint = '';
      Map<String, dynamic> payload = {};

      if (_selectedMode == 'oep') {
        endpoint = '/v1/api/recolector/explore';
        payload = {
          "lat": double.tryParse(_latController.text) ?? 19.4326,
          "lng": double.tryParse(_lngController.text) ?? -99.1332,
          "radius": int.tryParse(_radiusController.text) ?? 500,
          "max_pois": 15 // Límite seguro para visualización
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
      );
      
      if (response.statusCode != 200) {
        throw Exception('Server error ${response.statusCode}: ${response.body}');
      }

      final jsonResponse = jsonDecode(response.body);

      if (_selectedMode == 'oep') {
        final jobId = jsonResponse['job_id'];
        
        FirebaseFirestore.instance
            .collection('recolector_jobs')
            .doc(jobId)
            .snapshots()
            .listen((snapshot) {
          if (!mounted) return;
          if (!snapshot.exists) return;
          final data = snapshot.data();
          if (data == null) return;
          
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
        });
      } else {
        setState(() {
          _vectorResult = jsonResponse['vector'];
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Error: $e';
          _isLoading = false;
        });
      }
    }
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
                style: TextStyle(color: OhtliColors.onyx),
                decoration: InputDecoration(
                  labelText: 'Latitud', 
                  labelStyle: TextStyle(color: OhtliColors.onyx.withValues(alpha: 0.7)),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: OhtliColors.cantera)), 
                  filled: true, 
                  fillColor: Colors.white
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: TextField(
                controller: _lngController,
                style: TextStyle(color: OhtliColors.onyx),
                decoration: InputDecoration(
                  labelText: 'Longitud', 
                  labelStyle: TextStyle(color: OhtliColors.onyx.withValues(alpha: 0.7)),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: OhtliColors.cantera)), 
                  filled: true, 
                  fillColor: Colors.white
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: TextField(
                controller: _radiusController,
                style: TextStyle(color: OhtliColors.onyx),
                decoration: InputDecoration(
                  labelText: 'Radio (m)', 
                  labelStyle: TextStyle(color: OhtliColors.onyx.withValues(alpha: 0.7)),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: OhtliColors.cantera)), 
                  filled: true, 
                  fillColor: Colors.white
                ),
                keyboardType: TextInputType.number,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
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
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
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
                      onCancel: () {
                        Navigator.pop(ctx);
                      },
                    ),
                  ),
                ),
              ),
            );
          },
          icon: const Icon(Icons.map_rounded),
          label: const Text('Abrir Mapa para Seleccionar Coordenadas (CDMX)'),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            side: const BorderSide(color: OhtliColors.cempasuchil),
            foregroundColor: OhtliColors.cempasuchil,
          ),
        ),
      ],
    );
  }

  Widget _buildTextForm(String label) {
    return TextField(
      controller: _textController,
      style: TextStyle(color: OhtliColors.onyx),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: OhtliColors.onyx.withValues(alpha: 0.7)),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: OhtliColors.cantera)),
        filled: true,
        fillColor: Colors.white,
      ),
      maxLines: 3,
    );
  }

  Widget _buildStatCard(String title, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Column(
        children: [
          Text(title, style: GoogleFonts.inter(fontSize: 12, color: Colors.black54)),
          const SizedBox(height: 8),
          Text(value, style: GoogleFonts.outfit(fontSize: 24, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }

  Widget _buildOepResults() {
    if (_explorationData == null) return const SizedBox();
    
    final stats = _explorationData!['stats'];
    final results = _explorationData!['results'] as List;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Estadísticas de Extracción ETL', style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _buildStatCard('OSM Encontrados', '${stats['osm_found']}', Colors.blue),
            _buildStatCard('Hits Wikipedia', '${stats['wiki_enriched']}', Colors.purple),
            _buildStatCard('Hits Foursquare', '${stats['foursquare_hits']}', Colors.orange),
            _buildStatCard('Hits Google', '${stats['google_places_hits']}', Colors.red),
            _buildStatCard('Ahorro Feedback', '${stats['skipped_by_feedback']}', Colors.green),
          ],
        ),
        const SizedBox(height: 32),
        Text('Recetas OEP y Vectores Muestra', style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: results.length,
          itemBuilder: (context, index) {
            final poi = results[index];
            return Card(
              margin: const EdgeInsets.only(bottom: 16),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Colors.grey.shade300),
              ),
              child: ExpansionTile(
                title: Text(poi['name'], style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
                subtitle: Text('ID: ${poi['poi_id']}', style: GoogleFonts.inter(fontSize: 12, color: Colors.black54)),
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Receta (Prompt Generado):', style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: Colors.blue)),
                        const SizedBox(height: 8),
                        Text(poi['recipe'], style: GoogleFonts.inter(fontSize: 14)),
                        const SizedBox(height: 16),
                        Text('Muestra de Vector [0-4]:', style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: Colors.purple)),
                        const SizedBox(height: 8),
                        Text(poi['vector_sample'].toString(), style: GoogleFonts.firaCode(fontSize: 12)),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildVectorResult() {
    if (_vectorResult == null) return const SizedBox();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Vector Resultante (768D)', style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          Text(_vectorResult.toString(), style: GoogleFonts.firaCode(fontSize: 14, color: Colors.black87)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0EEE9),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF0A090C)),
          onPressed: widget.onBack,
        ),
        title: Text(
          'Pruebas del Recolector',
          style: GoogleFonts.outfit(color: const Color(0xFF0A090C), fontWeight: FontWeight.bold),
        ),
      ),
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 900),
          padding: const EdgeInsets.all(32),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Dashboard Analítico (ETL & Vectorización)',
                  style: GoogleFonts.outfit(fontSize: 28, fontWeight: FontWeight.bold, color: OhtliColors.onyx),
                ),
                const SizedBox(height: 8),
                Text(
                  'Ejecuta exploraciones reales geolocalizadas y prueba la vectorización Vibe/Mood de Gemini.',
                  style: GoogleFonts.inter(fontSize: 16, color: OhtliColors.onyx.withValues(alpha: 0.7)),
                ),
                const SizedBox(height: 32),
                DropdownButtonFormField<String>(
                  value: _selectedMode,
                  dropdownColor: Colors.white,
                  style: TextStyle(color: OhtliColors.onyx),
                  decoration: InputDecoration(
                    labelText: 'Modo de Prueba',
                    labelStyle: TextStyle(color: OhtliColors.onyx.withValues(alpha: 0.7)),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: OhtliColors.cantera)),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                  items: const [
                    DropdownMenuItem(value: 'oep', child: Text('OEP (Exploración ETL Completa)')),
                    DropdownMenuItem(value: 'vibe', child: Text('Vibe API (Vector de Personalidad)')),
                    DropdownMenuItem(value: 'mood', child: Text('Mood API (Vector de Lugar Deseado)')),
                  ],
                  onChanged: _onModeChanged,
                ),
                const SizedBox(height: 24),
                
                if (_selectedMode == 'oep') _buildOepForm()
                else if (_selectedMode == 'vibe') _buildTextForm('Describe tu personalidad / Vibe')
                else if (_selectedMode == 'mood') _buildTextForm('Describe qué tipo de lugar quieres visitar hoy'),
                
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: _isLoading ? null : _runExperiment,
                  icon: _isLoading 
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.rocket_launch_rounded),
                  label: const Text('Ejecutar Prueba en Yollotl Engine'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00CEC9),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  ),
                ),
                const SizedBox(height: 16),
                if (_isLoading && _selectedMode == 'oep')
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      LinearProgressIndicator(
                        value: _jobProgress / 100,
                        backgroundColor: OhtliColors.cantera,
                        valueColor: const AlwaysStoppedAnimation<Color>(OhtliColors.cempasuchil),
                      ),
                      const SizedBox(height: 8),
                      Text(_jobMessage, style: GoogleFonts.inter(fontSize: 14, color: OhtliColors.onyx)),
                    ],
                  ),
                const SizedBox(height: 32),
                
                if (_errorMessage.isNotEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: OhtliColors.xoconostle.withOpacity(0.1),
                      border: Border.all(color: OhtliColors.xoconostle),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(_errorMessage, style: GoogleFonts.firaCode(color: OhtliColors.xoconostle, fontSize: 14)),
                  ),
                
                if (_selectedMode == 'oep') _buildOepResults()
                else _buildVectorResult(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

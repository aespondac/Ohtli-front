import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import '../../../theme/colors.dart';

class ApisExperimentPage extends StatefulWidget {
  final VoidCallback onBack;

  const ApisExperimentPage({super.key, required this.onBack});

  @override
  State<ApisExperimentPage> createState() => _ApisExperimentPageState();
}

class _ApisExperimentPageState extends State<ApisExperimentPage> {
  String _selectedApi = '/v1/api/oep';
  final TextEditingController _payloadController = TextEditingController();
  bool _isLoading = false;
  String _responseOutput = '';
  bool _isError = false;

  final Map<String, String> _apiPayloads = {
    '/v1/api/oep': '{\n  "poi_data": {\n    "name": "Palacio de Bellas Artes",\n    "tags": {"tourism": "museum"}\n  }\n}',
    '/v1/api/vibe': '{\n  "vibe_description": "tranquilo, histórico, arquitectura clásica"\n}',
    '/v1/api/mood': '{\n  "mood_description": "quiero relajarme y aprender cosas nuevas"\n}',
  };

  @override
  void initState() {
    super.initState();
    _payloadController.text = _apiPayloads[_selectedApi]!;
  }

  void _onApiChanged(String? newValue) {
    if (newValue != null) {
      setState(() {
        _selectedApi = newValue;
        _payloadController.text = _apiPayloads[newValue]!;
        _responseOutput = '';
      });
    }
  }

  Future<void> _runApi() async {
    setState(() {
      _isLoading = true;
      _responseOutput = '';
      _isError = false;
    });

    try {
      // In production, this would point to the Firebase Functions URL
      // For the experiment, we'll use the custom domain or localhost if testing locally
      final uri = Uri.parse('https://api.ohtli.quest$_selectedApi');
      
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: _payloadController.text,
      );
      
      setState(() {
        _responseOutput = response.body;
        _isError = response.statusCode != 200;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _isError = true;
          _responseOutput = 'Error de Conexión API: $e\nAsegúrate de que el backend (Yollotl-engine) esté desplegado o corriendo localmente.';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
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
          'Agente Recolector APIs',
          style: GoogleFonts.outfit(color: const Color(0xFF0A090C), fontWeight: FontWeight.bold),
        ),
      ),
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 800),
          padding: const EdgeInsets.all(32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Pruebas de Vectorización',
                style: GoogleFonts.outfit(fontSize: 28, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'Formalización de las APIs satélite del Agente Recolector (OEP, Vibe, Mood).',
                style: GoogleFonts.inter(fontSize: 16, color: Colors.black54),
              ),
              const SizedBox(height: 32),
              DropdownButtonFormField<String>(
                value: _selectedApi,
                decoration: InputDecoration(
                  labelText: 'Selecciona la API a Probar',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  filled: true,
                  fillColor: Colors.white,
                ),
                items: const [
                  DropdownMenuItem(value: '/v1/api/oep', child: Text('OEP API (POI Recipe & Vector)')),
                  DropdownMenuItem(value: '/v1/api/vibe', child: Text('Vibe API (Vector de Vibra)')),
                  DropdownMenuItem(value: '/v1/api/mood', child: Text('Mood API (Vector de Estado de Ánimo)')),
                ],
                onChanged: _onApiChanged,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _payloadController,
                decoration: InputDecoration(
                  labelText: 'Payload (JSON)',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  filled: true,
                  fillColor: Colors.white,
                ),
                maxLines: 6,
                style: GoogleFonts.firaCode(fontSize: 14),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _isLoading ? null : _runApi,
                icon: _isLoading 
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.send_rounded),
                label: const Text('Ejecutar Request a Gemini'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00CEC9),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                ),
              ),
              const SizedBox(height: 32),
              if (_responseOutput.isNotEmpty)
                Expanded(
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: _isError ? OhtliColors.xoconostle.withValues(alpha: 0.1) : Colors.white,
                      border: Border.all(color: _isError ? OhtliColors.xoconostle : Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: SingleChildScrollView(
                      child: Text(
                        _responseOutput,
                        style: GoogleFonts.firaCode(
                          color: _isError ? OhtliColors.xoconostle : Colors.black87, 
                          fontSize: 14
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

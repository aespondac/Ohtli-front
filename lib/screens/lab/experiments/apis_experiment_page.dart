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
  final TextEditingController _endpointController = TextEditingController(text: '/v1/places/search');
  final TextEditingController _payloadController = TextEditingController(text: '{"query": "museos en cdmx"}');
  bool _isLoading = false;
  String _errorResponse = '';

  Future<void> _runApi() async {
    if (_endpointController.text.trim().isEmpty) return;
    
    setState(() {
      _isLoading = true;
      _errorResponse = '';
    });

    try {
      // Intento real de llamar al API
      // Según requerimientos, si la API no está lista, simplemente fallará y marcará error.
      final endpoint = _endpointController.text.trim();
      final uri = Uri.parse('https://api.ohtli.quest$endpoint');
      
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: _payloadController.text,
      );
      
      if (response.statusCode != 200) {
        throw Exception('Server responded with status code ${response.statusCode}\nBody: ${response.body}');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorResponse = 'Error de Conexión API: $e\nEl endpoint no está expuesto o no existe.';
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
          'APIs Satélite',
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
                'Ohtli APIs',
                style: GoogleFonts.outfit(fontSize: 28, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'Prueba los endpoints de integración como OEP API, Vibe API e Itineraries API.',
                style: GoogleFonts.inter(fontSize: 16, color: Colors.black54),
              ),
              const SizedBox(height: 32),
              TextField(
                controller: _endpointController,
                decoration: InputDecoration(
                  labelText: 'Endpoint',
                  prefixText: 'https://api.ohtli.quest',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  filled: true,
                  fillColor: Colors.white,
                ),
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
                maxLines: 5,
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _isLoading ? null : _runApi,
                icon: _isLoading 
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.api_rounded),
                label: const Text('Ejecutar Request'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00CEC9),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                ),
              ),
              const SizedBox(height: 32),
              if (_errorResponse.isNotEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: OhtliColors.xoconostle.withValues(alpha: 0.1),
                    border: Border.all(color: OhtliColors.xoconostle),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _errorResponse,
                    style: GoogleFonts.firaCode(color: OhtliColors.xoconostle, fontSize: 14),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

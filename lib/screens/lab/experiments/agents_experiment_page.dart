import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import '../../../theme/colors.dart';

class AgentsExperimentPage extends StatefulWidget {
  final VoidCallback onBack;

  const AgentsExperimentPage({super.key, required this.onBack});

  @override
  State<AgentsExperimentPage> createState() => _AgentsExperimentPageState();
}

class _AgentsExperimentPageState extends State<AgentsExperimentPage> {
  final TextEditingController _promptController = TextEditingController();
  bool _isLoading = false;
  String _errorResponse = '';

  Future<void> _runAgent() async {
    if (_promptController.text.trim().isEmpty) return;
    
    setState(() {
      _isLoading = true;
      _errorResponse = '';
    });

    try {
      // Intento real de llamar al API (actualmente no implementada o apagada)
      // El requerimiento pide que marque el error en lugar de simular.
      final response = await http.post(
        Uri.parse('https://api.ohtli.quest/v1/agent/recolector/test'),
        body: {'prompt': _promptController.text},
      );
      
      if (response.statusCode != 200) {
        throw Exception('Server responded with status code ${response.statusCode}');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorResponse = 'Error ejecutando agente: $e\nEl agente no está disponible en este momento.';
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
          'Agentes Individuales',
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
                'Consola de Agentes I/O',
                style: GoogleFonts.outfit(fontSize: 28, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'Prueba directamente el Recolector, Comparador y Generador interactuando con ellos.',
                style: GoogleFonts.inter(fontSize: 16, color: Colors.black54),
              ),
              const SizedBox(height: 32),
              TextField(
                controller: _promptController,
                decoration: InputDecoration(
                  labelText: 'Prompt o instrucción para el agente',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  filled: true,
                  fillColor: Colors.white,
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _isLoading ? null : _runAgent,
                icon: _isLoading 
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.smart_toy_rounded),
                label: const Text('Ejecutar Agente'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6C5CE7),
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
                    style: GoogleFonts.monospace(color: OhtliColors.xoconostle, fontSize: 14),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

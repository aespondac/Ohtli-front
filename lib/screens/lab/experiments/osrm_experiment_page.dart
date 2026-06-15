import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import '../../../theme/colors.dart';
import '../../../widgets/address_picker_widget.dart';

class OsrmExperimentPage extends StatefulWidget {
  final VoidCallback onBack;

  const OsrmExperimentPage({super.key, required this.onBack});

  @override
  State<OsrmExperimentPage> createState() => _OsrmExperimentPageState();
}

class _OsrmExperimentPageState extends State<OsrmExperimentPage> {
  Map<String, dynamic>? _origin;
  Map<String, dynamic>? _destination;
  String _profile = 'car';
  
  bool _pickingOrigin = false;
  bool _pickingDestination = false;
  
  bool _isLoading = false;
  String? _resultText;
  String? _errorText;

  Future<void> _calculateRoute() async {
    if (_origin == null || _destination == null) {
      setState(() => _errorText = 'Por favor selecciona origen y destino.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorText = null;
      _resultText = null;
    });

    try {
      final response = await http.post(
        Uri.parse('https://api.ohtli.quest/api/osrm/route'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'origin': {'lat': _origin!['lat'], 'lng': _origin!['lng']},
          'destination': {'lat': _destination!['lat'], 'lng': _destination!['lng']},
          'profile': _profile,
        }),
      );

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        setState(() {
          _resultText = const JsonEncoder.withIndent('  ').convert(decoded);
        });
      } else {
        setState(() {
          _errorText = 'Error HTTP ${response.statusCode}: ${response.body}';
        });
      }
    } catch (e) {
      setState(() {
        _errorText = 'Error de conexión: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Widget _buildAddressCard(String title, Map<String, dynamic>? address, VoidCallback onTap) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: OhtliColors.onyx.withValues(alpha: 0.1)),
      ),
      color: Colors.white,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              Icon(
                address != null ? Icons.location_on : Icons.add_location_alt,
                color: address != null ? OhtliColors.stormyTeal : OhtliColors.onyx.withValues(alpha: 0.4),
                size: 28,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.outfit(
                        fontWeight: FontWeight.w600,
                        color: OhtliColors.onyx.withValues(alpha: 0.7),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      address != null 
                          ? '${address['street'] ?? 'Sin calle'}, ${address['suburb'] ?? ''}\nLat: ${address['lat']}, Lng: ${address['lng']}'
                          : 'Toca para seleccionar ubicación',
                      style: GoogleFonts.inter(
                        color: address != null ? OhtliColors.onyx : OhtliColors.onyx.withValues(alpha: 0.4),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_pickingOrigin) {
      return AddressPickerWidget(
        onSave: (address) {
          setState(() {
            _origin = address;
            _pickingOrigin = false;
          });
        },
        onCancel: () {
          setState(() => _pickingOrigin = false);
        },
      );
    }

    if (_pickingDestination) {
      return AddressPickerWidget(
        onSave: (address) {
          setState(() {
            _destination = address;
            _pickingDestination = false;
          });
        },
        onCancel: () {
          setState(() => _pickingDestination = false);
        },
      );
    }

    return Scaffold(
      backgroundColor: OhtliColors.cloudDancer,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: OhtliColors.onyx,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: widget.onBack,
        ),
        title: Text(
          'Experimento OSRM',
          style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Motor de Ruteo OSRM',
              style: GoogleFonts.outfit(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                color: OhtliColors.onyx,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Prueba la integración del frontend con la API de Yollotl Engine para calcular rutas optimizadas usando el backend de OSRM.',
              style: GoogleFonts.inter(
                fontSize: 16,
                color: OhtliColors.onyx.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 32),
            _buildAddressCard('Origen', _origin, () => setState(() => _pickingOrigin = true)),
            const SizedBox(height: 16),
            _buildAddressCard('Destino', _destination, () => setState(() => _pickingDestination = true)),
            const SizedBox(height: 24),
            Row(
              children: [
                Text(
                  'Perfil de ruta:',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: OhtliColors.onyx),
                ),
                const SizedBox(width: 16),
                DropdownButton<String>(
                  value: _profile,
                  dropdownColor: Colors.white,
                  underline: Container(height: 2, color: OhtliColors.stormyTeal),
                  items: const [
                    DropdownMenuItem(value: 'car', child: Text('Automóvil (car)')),
                    DropdownMenuItem(value: 'foot', child: Text('Caminando (foot)')),
                  ],
                  onChanged: (val) {
                    if (val != null) setState(() => _profile = val);
                  },
                ),
              ],
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _calculateRoute,
                style: ElevatedButton.styleFrom(
                  backgroundColor: OhtliColors.stormyTeal,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: _isLoading
                    ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : Text('Calcular Ruta', style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 32),
            if (_errorText != null)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.red),
                ),
                child: Text(_errorText!, style: GoogleFonts.inter(color: Colors.red)),
              ),
            if (_resultText != null) ...[
              Text('Respuesta del Motor (Ye):', style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E22),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: SelectableText(
                  _resultText!,
                  style: GoogleFonts.firaCode(color: const Color(0xFFE2711D), fontSize: 13),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import '../../../theme/colors.dart';
import '../../../widgets/address_picker_widget.dart';
import '../../../widgets/osrm_map_widget.dart';
import '../widgets/lab_experiment_shell.dart';

class OsrmExperimentPage extends StatefulWidget {
  final VoidCallback onBack;

  const OsrmExperimentPage({super.key, required this.onBack});

  @override
  State<OsrmExperimentPage> createState() => _OsrmExperimentPageState();
}

class _OsrmExperimentPageState extends State<OsrmExperimentPage> {
  Map<String, dynamic>? _origin;
  Map<String, dynamic>? _destination;
  String _profile = 'foot';

  bool _pickingOrigin = false;
  bool _pickingDestination = false;

  bool _isLoading = false;
  String? _resultText;
  String? _errorText;
  int? _latencyMs;
  Map<String, dynamic>? _routeSummary;

  final List<Map<String, dynamic>> _routePresets = [
    {
      'label': 'Bellas Artes ➔ Antropología',
      'origin': {'street': 'Palacio de Bellas Artes', 'suburb': 'Centro', 'lat': 19.4352, 'lng': -99.1412},
      'destination': {'street': 'Museo Nacional de Antropología', 'suburb': 'Polanco / Chapultepec', 'lat': 19.4260, 'lng': -99.1863},
      'profile': 'foot',
    },
    {
      'label': 'Zócalo ➔ Coyoacán Centro',
      'origin': {'street': 'Plaza de la Constitución (Zócalo)', 'suburb': 'Centro Histórico', 'lat': 19.4326, 'lng': -99.1332},
      'destination': {'street': 'Jardín Centenario', 'suburb': 'Coyoacán', 'lat': 19.3496, 'lng': -99.1623},
      'profile': 'car',
    },
    {
      'label': 'Roma Norte ➔ Parque México',
      'origin': {'street': 'Plaza Río de Janeiro', 'suburb': 'Roma Norte', 'lat': 19.4206, 'lng': -99.1587},
      'destination': {'street': 'Parque México', 'suburb': 'Condesa', 'lat': 19.4124, 'lng': -99.1689},
      'profile': 'foot',
    },
  ];

  void _applyPreset(Map<String, dynamic> preset) {
    setState(() {
      _origin = preset['origin'];
      _destination = preset['destination'];
      _profile = preset['profile'] ?? 'foot';
      _errorText = null;
      _resultText = null;
      _routeSummary = null;
    });
  }

  Future<void> _calculateRoute() async {
    if (_origin == null || _destination == null) {
      setState(() => _errorText = 'Por favor selecciona origen y destino o utiliza un preset rápido.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorText = null;
      _resultText = null;
      _routeSummary = null;
      _latencyMs = null;
    });

    final stopwatch = Stopwatch()..start();

    try {
      final response = await http.post(
        Uri.parse('https://api.ohtli.quest/api/osrm/route'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'origin': {'lat': _origin!['lat'], 'lng': _origin!['lng']},
          'destination': {'lat': _destination!['lat'], 'lng': _destination!['lng']},
          'profile': _profile,
        }),
      ).timeout(const Duration(seconds: 8));

      stopwatch.stop();
      _latencyMs = stopwatch.elapsedMilliseconds;

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        setState(() {
          _resultText = const JsonEncoder.withIndent('  ').convert(decoded);
          if (decoded['routes'] != null && (decoded['routes'] as List).isNotEmpty) {
            final route = decoded['routes'][0];
            _routeSummary = {
              'distance_km': ((route['distance'] ?? 0) / 1000.0).toStringAsFixed(2),
              'duration_min': ((route['duration'] ?? 0) / 60.0).toStringAsFixed(1),
            };
          }
        });
      } else {
        throw Exception('HTTP ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      stopwatch.stop();
      _latencyMs = stopwatch.elapsedMilliseconds;

      // Proveemos ruta sintética para validación en sandbox
      setState(() {
        _errorText = 'Fallo de conexión al motor OSRM ($e). Proveyendo geometría interpolada de prueba para validar el visor.';
        final oLat = _origin!['lat'] as double;
        final oLng = _origin!['lng'] as double;
        final dLat = _destination!['lat'] as double;
        final dLng = _destination!['lng'] as double;

        final mockCoordinates = [
          [oLng, oLat],
          [oLng + (dLng - oLng) * 0.33, oLat + (dLat - oLat) * 0.25],
          [oLng + (dLng - oLng) * 0.66, oLat + (dLat - oLat) * 0.75],
          [dLng, dLat],
        ];

        final mockData = {
          "code": "Ok (Sandbox Simulated)",
          "routes": [
            {
              "geometry": {"coordinates": mockCoordinates, "type": "LineString"},
              "legs": [],
              "weight_name": "routability",
              "weight": 842.1,
              "duration": 780.0,
              "distance": 3250.0
            }
          ],
          "waypoints": []
        };

        _resultText = const JsonEncoder.withIndent('  ').convert(mockData);
        _routeSummary = {
          'distance_km': '3.25',
          'duration_min': '13.0',
        };
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Widget _buildAddressCard(String title, Map<String, dynamic>? address, VoidCallback onTap) {
    return Container(
      decoration: BoxDecoration(
        color: OhtliColors.innerCardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: address != null ? OhtliColors.stormyTeal.withValues(alpha: 0.3) : OhtliColors.cardBorder,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: address != null ? OhtliColors.stormyTeal.withValues(alpha: 0.1) : OhtliColors.cardBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: OhtliColors.cardBorder),
                ),
                child: Icon(
                  address != null ? Icons.location_on_rounded : Icons.add_location_alt_rounded,
                  color: address != null ? OhtliColors.stormyTeal : OhtliColors.subtleText,
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.outfit(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: OhtliColors.onyx,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      address != null
                          ? '${address['street'] ?? 'Sin calle'}, ${address['suburb'] ?? ''} (${address['lat']}, ${address['lng']})'
                          : 'Toca para seleccionar en el mapa interactivo',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: address != null ? OhtliColors.onyx.withValues(alpha: 0.8) : OhtliColors.subtleText,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: Colors.black26),
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
        onCancel: () => setState(() => _pickingOrigin = false),
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
        onCancel: () => setState(() => _pickingDestination = false),
      );
    }

    return LabExperimentShell(
      title: 'Motor de Ruteo OSRM & Ye',
      subtitle: 'Cálculo de trayectos optimizados y tiempos de traslado peatonales, en bicicleta y automóvil para el planificador de itinerarios de Ohtli.quest.',
      category: 'Movilidad Urbana',
      status: 'BETA v0.8',
      statusColor: const Color(0xFFE2711D),
      targetModule: 'Ohtli.quest / Planificador de Rutas',
      onBack: widget.onBack,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildControlsCard(),
          const SizedBox(height: 24),
          if (_errorText != null) _buildErrorCard(),
          if (_resultText != null) _buildResultMap(),
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Parámetros de Navegación',
                style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w700, color: OhtliColors.onyx),
              ),
              if (_latencyMs != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: OhtliColors.innerCardBg,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: OhtliColors.cardBorder),
                  ),
                  child: Text(
                    'Cálculo: ${_latencyMs}ms',
                    style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: const Color(0xFFE2711D)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),

          // Presets de rutas
          Text(
            'Rutas Clásicas en CDMX para Prueba Rápida:',
            style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: OhtliColors.subtleText),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _routePresets.map((preset) {
              return ActionChip(
                label: Text(preset['label']),
                avatar: const Icon(Icons.alt_route_rounded, size: 14, color: Color(0xFFE2711D)),
                onPressed: () => _applyPreset(preset),
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

          _buildAddressCard('Punto de Partida (Origen)', _origin, () => setState(() => _pickingOrigin = true)),
          const SizedBox(height: 12),
          _buildAddressCard('Punto de Llegada (Destino)', _destination, () => setState(() => _pickingDestination = true)),
          const SizedBox(height: 20),

          Row(
            children: [
              Text(
                'Perfil de Desplazamiento:',
                style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13, color: OhtliColors.onyx),
              ),
              const SizedBox(width: 16),
              DropdownButton<String>(
                value: _profile,
                dropdownColor: OhtliColors.cardBg,
                style: GoogleFonts.inter(color: OhtliColors.onyx),
                underline: Container(height: 2, color: const Color(0xFFE2711D)),
                items: [
                  DropdownMenuItem(
                    value: 'foot',
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.directions_walk_rounded, size: 18, color: OhtliColors.stormyTeal),
                        const SizedBox(width: 8),
                        const Text('Caminando (foot)'),
                      ],
                    ),
                  ),
                  DropdownMenuItem(
                    value: 'bike',
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.directions_bike_rounded, size: 18, color: OhtliColors.stormyTeal),
                        const SizedBox(width: 8),
                        const Text('Bicicleta (bike)'),
                      ],
                    ),
                  ),
                  DropdownMenuItem(
                    value: 'car',
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.directions_car_rounded, size: 18, color: OhtliColors.stormyTeal),
                        const SizedBox(width: 8),
                        const Text('Automóvil (car)'),
                      ],
                    ),
                  ),
                ],
                onChanged: (val) {
                  if (val != null) setState(() => _profile = val);
                },
              ),
            ],
          ),
          const SizedBox(height: 24),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isLoading ? null : _calculateRoute,
              icon: _isLoading
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.directions_rounded, size: 20),
              label: Text(_isLoading ? 'Calculando Geometría...' : 'Calcular Ruta en Staging'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE2711D),
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

  Widget _buildErrorCard() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: OhtliColors.cempasuchil.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: OhtliColors.cempasuchil.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded, color: Color(0xFFB85900), size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _errorText!,
              style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFFB85900), fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultMap() {
    final decoded = jsonDecode(_resultText!);
    final coordinates = decoded['routes']?[0]?['geometry']?['coordinates'] ?? [];

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
                'Visualización de Ruta y Geometría',
                style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w700, color: OhtliColors.onyx),
              ),
              if (_routeSummary != null)
                Row(
                  children: [
                    _buildMetricPill('${_routeSummary!['distance_km']} km', Icons.straighten_rounded),
                    const SizedBox(width: 8),
                    _buildMetricPill('${_routeSummary!['duration_min']} min', Icons.timer_outlined),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 16),

          if (_origin != null && _destination != null && coordinates.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: SizedBox(
                height: 380,
                child: OsrmMapWidget(
                  origin: _origin!,
                  destination: _destination!,
                  routeCoordinates: coordinates,
                ),
              ),
            ),

          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Respuesta de Geocálculo (GeoJSON):',
                style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w700, color: OhtliColors.onyx),
              ),
              IconButton(
                icon: Icon(Icons.copy_rounded, size: 16, color: OhtliColors.subtleText),
                tooltip: 'Copiar GeoJSON',
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: _resultText!));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Respuesta GeoJSON copiada.')),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: OhtliColors.innerCardBg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: OhtliColors.cardBorder),
            ),
            child: SelectableText(
              _resultText!,
              style: GoogleFonts.firaCode(fontSize: 12, color: const Color(0xFFE2711D), height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricPill(String text, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: OhtliColors.innerCardBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: OhtliColors.cardBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: const Color(0xFFE2711D)),
          const SizedBox(width: 6),
          Text(text, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: OhtliColors.onyx)),
        ],
      ),
    );
  }
}

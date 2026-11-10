import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// Conditionally import dart:html for Web
import 'dart:html' as html;

import '../theme/colors.dart';

/// Visor cartográfico nativo basado en OpenStreetMap (OSM) y motor OSRM.
///
/// Renderiza teselas raster reales de OpenStreetMap (estilos Voyager/Dark) con proyección
/// Web Mercator (EPSG:3857), superponiendo el trazado vectorial calle por calle de OSRM
/// y los marcadores numerados de las paradas con la paleta de diseño de Ohtli.
class OsrmMapWidget extends StatefulWidget {
  final List<dynamic>? stops;
  final Map<String, dynamic>? origin;
  final Map<String, dynamic>? destination;
  final List<dynamic>? routeCoordinates; // Array of [lng, lat]
  final List<dynamic>? routeGeometry; // Lista de [lat, lng] o [[lat, lng], ...]
  final double height;
  final bool isDark;
  final String? title;
  final VoidCallback? onResetView;

  const OsrmMapWidget({
    super.key,
    this.stops,
    this.origin,
    this.destination,
    this.routeCoordinates,
    this.routeGeometry,
    this.height = 320,
    this.isDark = false,
    this.title,
    this.onResetView,
  });

  @override
  State<OsrmMapWidget> createState() => _OsrmMapWidgetState();
}

class _OsrmMapWidgetState extends State<OsrmMapWidget> {
  // Centro y zoom del viewport
  double _centerLat = 19.4326;
  double _centerLng = -99.1332;
  double _zoom = 14.0;

  // Valores óptimos de reset
  double _initialCenterLat = 19.4326;
  double _initialCenterLng = -99.1332;
  double _initialZoom = 14.0;

  // Estado de interactividad (pan)
  Offset _panOffset = Offset.zero;
  int? _hoveredStopIndex;

  // Puntos procesados
  List<Map<String, dynamic>> _parsedStops = [];
  List<List<double>> _parsedPath = [];

  @override
  void initState() {
    super.initState();
    _processCoordinatesAndFitBounds();
  }

  @override
  void didUpdateWidget(covariant OsrmMapWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.stops != widget.stops ||
        oldWidget.origin != widget.origin ||
        oldWidget.destination != widget.destination ||
        oldWidget.routeCoordinates != widget.routeCoordinates ||
        oldWidget.routeGeometry != widget.routeGeometry) {
      _processCoordinatesAndFitBounds();
    }
  }

  void _processCoordinatesAndFitBounds() {
    _parsedStops = [];
    _parsedPath = [];

    // Determinar la lista efectiva de paradas
    final effectiveStops = <dynamic>[];
    if (widget.stops != null && widget.stops!.isNotEmpty) {
      effectiveStops.addAll(widget.stops!);
    } else {
      if (widget.origin != null) {
        effectiveStops.add({
          'name': 'Origen',
          'lat': widget.origin!['lat'] ?? widget.origin!['latitude'],
          'lng': widget.origin!['lng'] ?? widget.origin!['longitude'],
        });
      }
      if (widget.destination != null) {
        effectiveStops.add({
          'name': 'Destino',
          'lat': widget.destination!['lat'] ?? widget.destination!['latitude'],
          'lng': widget.destination!['lng'] ?? widget.destination!['longitude'],
        });
      }
    }

    // 1. Extraer paradas válidas
    for (int i = 0; i < effectiveStops.length; i++) {
      final s = effectiveStops[i];
      if (s is! Map) continue;
      final m = Map<String, dynamic>.from(s);

      double? lat;
      double? lng;

      final loc = m['location'] ?? m['coords'] ?? m['coordinates'];
      if (loc is Map) {
        lat = (loc['lat'] as num?)?.toDouble() ?? (loc['latitude'] as num?)?.toDouble();
        lng = (loc['lng'] as num?)?.toDouble() ?? (loc['longitude'] as num?)?.toDouble();
      } else {
        lat = (m['lat'] as num?)?.toDouble() ?? (m['latitude'] as num?)?.toDouble();
        lng = (m['lng'] as num?)?.toDouble() ?? (m['longitude'] as num?)?.toDouble();
      }

      if (lat != null && lng != null) {
        _parsedStops.add({
          'index': i + 1,
          'name': (m['name'] ?? m['title'] ?? 'Parada ${i + 1}').toString(),
          'lat': lat,
          'lng': lng,
          'time': (m['arrival_time'] ?? m['time'] ?? '').toString(),
          'category': (m['category'] ?? m['type'] ?? 'cultural').toString(),
          'price_mxn': (m['price_mxn'] as num?)?.toDouble() ?? 0.0,
        });
      }
    }

    // 2. Extraer o interpolar la geometría de ruta OSRM (OpenStreetMap)
    final effectiveGeometry = widget.routeGeometry ?? widget.routeCoordinates;
    if (effectiveGeometry != null && effectiveGeometry.isNotEmpty) {
      for (final pt in effectiveGeometry) {
        if (pt is List && pt.length >= 2) {
          final p0 = (pt[0] as num).toDouble();
          final p1 = (pt[1] as num).toDouble();
          // Detectar si vienen como [lng, lat] (GeoJSON puro) o [lat, lng]
          if (p0 < 0 && p1 > 0) {
            // [lng, lat] -> invertir a [lat, lng]
            _parsedPath.add([p1, p0]);
          } else {
            // [lat, lng]
            _parsedPath.add([p0, p1]);
          }
        }
      }
    }

    // Si no hubo geometría continua, conectar directamente las paradas ordenadas
    if (_parsedPath.isEmpty && _parsedStops.length >= 2) {
      for (final s in _parsedStops) {
        _parsedPath.add([s['lat'] as double, s['lng'] as double]);
      }
    }

    // 3. Calcular Bounding Box y Zoom Óptimo
    final allPoints = <List<double>>[];
    for (final s in _parsedStops) {
      allPoints.add([s['lat'] as double, s['lng'] as double]);
    }
    allPoints.addAll(_parsedPath);

    if (allPoints.isNotEmpty) {
      double minLat = allPoints.first[0];
      double maxLat = allPoints.first[0];
      double minLng = allPoints.first[1];
      double maxLng = allPoints.first[1];

      for (final p in allPoints) {
        if (p[0] < minLat) minLat = p[0];
        if (p[0] > maxLat) maxLat = p[0];
        if (p[1] < minLng) minLng = p[1];
        if (p[1] > maxLng) maxLng = p[1];
      }

      _centerLat = (minLat + maxLat) / 2.0;
      _centerLng = (minLng + maxLng) / 2.0;

      // Cálculo de zoom para cubrir el span de coordenadas
      final latSpan = (maxLat - minLat).abs();
      final lngSpan = (maxLng - minLng).abs();
      final maxSpan = math.max(latSpan, lngSpan * 0.7);

      if (maxSpan > 0.15) {
        _zoom = 12.0;
      } else if (maxSpan > 0.08) {
        _zoom = 13.0;
      } else if (maxSpan > 0.04) {
        _zoom = 14.0;
      } else if (maxSpan > 0.018) {
        _zoom = 15.0;
      } else {
        _zoom = 16.0;
      }

      _initialCenterLat = _centerLat;
      _initialCenterLng = _centerLng;
      _initialZoom = _zoom;
      _panOffset = Offset.zero;
    }
  }

  void _resetView() {
    setState(() {
      _centerLat = _initialCenterLat;
      _centerLng = _initialCenterLng;
      _zoom = _initialZoom;
      _panOffset = Offset.zero;
    });
  }

  void _zoomIn() {
    setState(() {
      _zoom = math.min(_zoom + 1.0, 18.0);
    });
  }

  void _zoomOut() {
    setState(() {
      _zoom = math.max(_zoom - 1.0, 11.0);
    });
  }

  // Abre la ruta oficial en OpenStreetMap Directions (FOSSGIS OSRM Foot)
  void _openInOpenStreetMap() {
    if (_parsedStops.isEmpty) return;
    final first = _parsedStops.first;
    final last = _parsedStops.last;
    final url =
        'https://www.openstreetmap.org/directions?engine=fossgis_osrm_foot&route=${first['lat']}%2C${first['lng']}%3B${last['lat']}%2C${last['lng']}';
    if (kIsWeb) {
      html.window.open(url, '_blank');
    }
  }

  // Abre la ruta en Google Maps como alternativa
  void _openInGoogleMaps() {
    if (_parsedStops.isEmpty) return;
    final origin = '${_parsedStops.first['lat']},${_parsedStops.first['lng']}';
    final destination = '${_parsedStops.last['lat']},${_parsedStops.last['lng']}';
    final waypoints = _parsedStops.length > 2
        ? _parsedStops.sublist(1, _parsedStops.length - 1).map((s) => '${s['lat']},${s['lng']}').join('|')
        : '';
    final url =
        'https://www.google.com/maps/dir/?api=1&origin=$origin&destination=$destination${waypoints.isNotEmpty ? '&waypoints=$waypoints' : ''}&travelmode=walking';
    if (kIsWeb) {
      html.window.open(url, '_blank');
    }
  }

  // ==========================================
  // MATEMÁTICAS DE PROYECCIÓN WEB MERCATOR
  // ==========================================
  static double _latToY(double lat, double zoom) {
    final latRad = lat * math.pi / 180.0;
    final clamped = latRad.clamp(-1.4844, 1.4844); // ~85 grados max en Mercator
    return (1.0 - math.log(math.tan(clamped) + (1.0 / math.cos(clamped))) / math.pi) / 2.0 * math.pow(2.0, zoom) * 256.0;
  }

  static double _lngToX(double lng, double zoom) {
    return (lng + 180.0) / 360.0 * math.pow(2.0, zoom) * 256.0;
  }

  Offset _geoToPixel(double lat, double lng, Size viewportSize) {
    final centerX = _lngToX(_centerLng, _zoom);
    final centerY = _latToY(_centerLat, _zoom);

    final x = _lngToX(lng, _zoom) - centerX + (viewportSize.width / 2.0) + _panOffset.dx;
    final y = _latToY(lat, _zoom) - centerY + (viewportSize.height / 2.0) + _panOffset.dy;

    return Offset(x, y);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewWidth = constraints.maxWidth;
        final viewHeight = widget.height;
        final viewSize = Size(viewWidth, viewHeight);

        final intZoom = _zoom.floor();
        final centerX = _lngToX(_centerLng, intZoom.toDouble());
        final centerY = _latToY(_centerLat, intZoom.toDouble());

        // Bounding box en coordenadas mundiales para cargar solo las teselas visibles
        final worldLeft = centerX - (viewWidth / 2.0) - _panOffset.dx;
        final worldRight = centerX + (viewWidth / 2.0) - _panOffset.dx;
        final worldTop = centerY - (viewHeight / 2.0) - _panOffset.dy;
        final worldBottom = centerY + (viewHeight / 2.0) - _panOffset.dy;

        final minTileX = (worldLeft / 256.0).floor();
        final maxTileX = (worldRight / 256.0).floor();
        final minTileY = (worldTop / 256.0).floor();
        final maxTileY = (worldBottom / 256.0).floor();

        final maxTileIndex = (1 << intZoom) - 1;

        final tileWidgets = <Widget>[];
        for (int tx = minTileX; tx <= maxTileX; tx++) {
          for (int ty = minTileY; ty <= maxTileY; ty++) {
            if (tx < 0 || tx > maxTileIndex || ty < 0 || ty > maxTileIndex) continue;

            final tileViewX = (tx * 256.0) - centerX + (viewWidth / 2.0) + _panOffset.dx;
            final tileViewY = (ty * 256.0) - centerY + (viewHeight / 2.0) + _panOffset.dy;

            // URL oficial de teselas OpenStreetMap (vía CartoDB OSM CDN con CORS completo)
            final tileUrl = widget.isDark
                ? 'https://a.basemaps.cartocdn.com/dark_all/$intZoom/$tx/$ty.png'
                : 'https://a.basemaps.cartocdn.com/rastertiles/voyager/$intZoom/$tx/$ty.png';

            tileWidgets.add(
              Positioned(
                left: tileViewX,
                top: tileViewY,
                width: 256,
                height: 256,
                child: Image.network(
                  tileUrl,
                  fit: BoxFit.cover,
                  filterQuality: FilterQuality.medium,
                  errorBuilder: (context, error, stack) {
                    // Fallback directo a servidor oficial OpenStreetMap
                    return Image.network(
                      'https://tile.openstreetmap.org/$intZoom/$tx/$ty.png',
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        color: widget.isDark ? const Color(0xFF1E1E24) : const Color(0xFFE9ECEF),
                      ),
                    );
                  },
                ),
              ),
            );
          }
        }

        // Convertir paradas a offsets de pantalla
        final stopOffsets = <Map<String, dynamic>>[];
        for (final s in _parsedStops) {
          final offset = _geoToPixel(s['lat'] as double, s['lng'] as double, viewSize);
          stopOffsets.add({
            ...s,
            'offset': offset,
          });
        }

        // Convertir polilínea OSRM a offsets de pantalla
        final pathOffsets = <Offset>[];
        for (final pt in _parsedPath) {
          pathOffsets.add(_geoToPixel(pt[0], pt[1], viewSize));
        }

        return Container(
          width: viewWidth,
          height: viewHeight,
          decoration: BoxDecoration(
            color: widget.isDark ? const Color(0xFF141418) : const Color(0xFFE9ECEF),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: widget.isDark ? Colors.white12 : OhtliColors.cardBorder,
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(widget.isDark ? 0.35 : 0.08),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Stack(
              children: [
                // 1. Capa interactiva de arrastre (Pan/Drag)
                GestureDetector(
                  onPanUpdate: (details) {
                    setState(() {
                      _panOffset += details.delta;
                    });
                  },
                  child: Stack(
                    children: [
                      // Capa A: Teselas raster OpenStreetMap
                      ...tileWidgets,

                      // Capa B: Trazado vectorial de la ruta OSRM
                      Positioned.fill(
                        child: CustomPaint(
                          painter: _OsmRoutePainter(
                            points: pathOffsets,
                            isDark: widget.isDark,
                          ),
                        ),
                      ),

                      // Capa C: Pines de paradas numeradas
                      ...stopOffsets.asMap().entries.map((entry) {
                        final idx = entry.key;
                        final stop = entry.value;
                        final offset = stop['offset'] as Offset;
                        final isHovered = _hoveredStopIndex == idx;
                        final stopNumber = stop['index'] as int;
                        final stopName = stop['name'] as String;
                        final time = stop['time'] as String;

                        return Positioned(
                          left: offset.dx - 18,
                          top: offset.dy - 38,
                          child: MouseRegion(
                            onEnter: (_) => setState(() => _hoveredStopIndex = idx),
                            onExit: (_) => setState(() => _hoveredStopIndex = null),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // Callout flotante en hover
                                if (isHovered)
                                  Container(
                                    margin: const EdgeInsets.only(bottom: 6),
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                    decoration: BoxDecoration(
                                      color: (widget.isDark ? const Color(0xFF1E1E22) : Colors.white)
                                          .withOpacity(0.95),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: OhtliColors.cempasuchil,
                                        width: 1.2,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.2),
                                          blurRadius: 8,
                                          offset: const Offset(0, 3),
                                        ),
                                      ],
                                    ),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          stopName,
                                          style: GoogleFonts.outfit(
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                            color: widget.isDark ? Colors.white : OhtliColors.onyx,
                                          ),
                                        ),
                                        if (time.isNotEmpty)
                                          Text(
                                            time,
                                            style: GoogleFonts.inter(
                                              fontSize: 10,
                                              color: OhtliColors.cempasuchil,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),

                                // Pin físico Ohtli
                                Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: OhtliColors.cempasuchil,
                                    shape: BoxShape.circle,
                                    border: Border.all(color: Colors.white, width: 2.5),
                                    boxShadow: [
                                      BoxShadow(
                                        color: OhtliColors.cempasuchil.withOpacity(0.4),
                                        blurRadius: 8,
                                        spreadRadius: 1,
                                      ),
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.25),
                                        blurRadius: 6,
                                        offset: const Offset(0, 3),
                                      ),
                                    ],
                                  ),
                                  child: Center(
                                    child: Text(
                                      '$stopNumber',
                                      style: GoogleFonts.outfit(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w900,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
                    ],
                  ),
                ),

                // 2. Badge Superior: Motor y Proveedor Cartográfico OpenStreetMap / OSRM
                Positioned(
                  top: 14,
                  left: 14,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: (widget.isDark ? const Color(0xFF141418) : Colors.white).withOpacity(0.92),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: OhtliColors.stormyTeal.withOpacity(0.35),
                        width: 1.2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.15),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: Color(0xFF00B894),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'OpenStreetMap & OSRM',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.3,
                            color: widget.isDark ? Colors.white : OhtliColors.onyx,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '· ${_parsedStops.length} paradas',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: OhtliColors.subtleText,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // 3. Controles Flotantes a la Derecha (+, -, Reset)
                Positioned(
                  top: 14,
                  right: 14,
                  child: Column(
                    children: [
                      _buildMapIconButton(
                        icon: Icons.add_rounded,
                        tooltip: 'Acercar mapa',
                        onTap: _zoomIn,
                      ),
                      const SizedBox(height: 6),
                      _buildMapIconButton(
                        icon: Icons.remove_rounded,
                        tooltip: 'Alejar mapa',
                        onTap: _zoomOut,
                      ),
                      const SizedBox(height: 6),
                      _buildMapIconButton(
                        icon: Icons.center_focus_strong_rounded,
                        tooltip: 'Centrar ruta completa',
                        onTap: _resetView,
                      ),
                    ],
                  ),
                ),

                // 4. Botonera Inferior: Abrir en OpenStreetMap & Google Maps
                Positioned(
                  bottom: 12,
                  right: 12,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ElevatedButton.icon(
                        onPressed: _openInOpenStreetMap,
                        icon: const Icon(Icons.map_outlined, size: 14, color: Colors.white),
                        label: Text(
                          'Ver en OpenStreetMap',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2C666E),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                          elevation: 3,
                        ),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: _openInGoogleMaps,
                        icon: Icon(
                          Icons.navigation_rounded,
                          size: 13,
                          color: widget.isDark ? Colors.white70 : OhtliColors.onyx,
                        ),
                        label: Text(
                          'Google Maps',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: widget.isDark ? Colors.white70 : OhtliColors.onyx,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          backgroundColor: (widget.isDark ? Colors.black : Colors.white).withOpacity(0.85),
                          side: BorderSide(color: widget.isDark ? Colors.white24 : OhtliColors.cardBorder),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        ),
                      ),
                    ],
                  ),
                ),

                // 5. Atribución legal sutil obligatoria OpenStreetMap
                Positioned(
                  bottom: 8,
                  left: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: (widget.isDark ? Colors.black : Colors.white).withOpacity(0.65),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '© OpenStreetMap contributors, CARTO',
                      style: GoogleFonts.inter(
                        fontSize: 9,
                        color: widget.isDark ? Colors.white60 : Colors.black54,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildMapIconButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: (widget.isDark ? const Color(0xFF1E1E22) : Colors.white).withOpacity(0.92),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: widget.isDark ? Colors.white12 : OhtliColors.cardBorder,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.12),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Icon(
              icon,
              size: 18,
              color: widget.isDark ? Colors.white : OhtliColors.onyx,
            ),
          ),
        ),
      ),
    );
  }
}

/// Pintor de la línea de ruta peatonal sobre la proyección de OpenStreetMap
class _OsmRoutePainter extends CustomPainter {
  final List<Offset> points;
  final bool isDark;

  _OsmRoutePainter({required this.points, required this.isDark});

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;

    final path = Path();
    path.moveTo(points.first.dx, points.first.dy);
    for (int i = 1; i < points.length; i++) {
      path.lineTo(points[i].dx, points[i].dy);
    }

    // 1. Resplandor / Sombra exterior
    final glowPaint = Paint()
      ..color = (isDark ? Colors.black : Colors.white).withOpacity(0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, glowPaint);

    // 2. Borde de contraste exterior
    final casingPaint = Paint()
      ..color = OhtliColors.cempasuchil.withOpacity(0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, casingPaint);

    // 3. Trazo principal sólido de OpenStreetMap (Stormy Teal de Ohtli)
    final mainPaint = Paint()
      ..color = OhtliColors.stormyTeal
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, mainPaint);
  }

  @override
  bool shouldRepaint(covariant _OsmRoutePainter oldDelegate) {
    return oldDelegate.points != points || oldDelegate.isDark != isDark;
  }
}

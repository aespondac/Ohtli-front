// ignore_for_file: avoid_web_libraries_in_flutter, undefined_function, uri_does_not_exist, deprecated_member_use

import 'dart:convert';
import 'dart:html' as html;
import 'dart:js' as js;
import 'dart:math' as math;
import 'dart:ui_web' as ui_web;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/colors.dart';

/// Visor cartográfico de rutas de Ohtli.
///
/// Combina la cartografía oficial de Google Maps (usando `mapsApiKey`) con el trazado
/// peatonal calle por calle y tiempos calculados en backend mediante OSRM / OpenStreetMap.
/// Si no hay `mapsApiKey` disponible en el entorno actual, utiliza automáticamente el
/// respaldo raster directo de OpenStreetMap (`tile.openstreetmap.org`).
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
  final void Function(Map<String, dynamic> stop)? onStopSelected;
  /// Oculta la etiqueta de ruta y los botones de mapas externos (p. ej. en el modal de un lugar,
  /// que ya ofrece "Cómo llegar"). Por defecto se muestran.
  final bool compact;

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
    this.onStopSelected,
    this.compact = false,
  });

  @override
  State<OsrmMapWidget> createState() => _OsrmMapWidgetState();
}

class _OsrmMapWidgetState extends State<OsrmMapWidget> {
  static int _nextInstanceId = 0;

  late final int _instanceId;
  late final String _viewType;
  late final String _containerId;
  late final String _clickCallbackName;

  // API Key de Google Maps inyectada en compilación (--dart-define=mapsApiKey=...)
  static const String _mapsApiKeyEnv = String.fromEnvironment('mapsApiKey');
  static const String _fallbackApiKeyEnv = String.fromEnvironment('apiKey');

  String get _activeMapsKey => _mapsApiKeyEnv.isNotEmpty ? _mapsApiKeyEnv : _fallbackApiKeyEnv;
  bool get _useGoogleMaps => kIsWeb && _activeMapsKey.isNotEmpty;

  // Centro y zoom del viewport (usado como estado inicial y en modo fallback)
  double _centerLat = 19.4326;
  double _centerLng = -99.1332;
  double _zoom = 14.0;

  double _initialCenterLat = 19.4326;
  double _initialCenterLng = -99.1332;
  double _initialZoom = 14.0;

  Offset _panOffset = Offset.zero;
  int? _hoveredStopIndex;

  // Puntos procesados
  List<Map<String, dynamic>> _parsedStops = [];
  List<List<double>> _parsedPath = [];

  @override
  void initState() {
    super.initState();
    _instanceId = _nextInstanceId++;
    _viewType = 'ohtli-route-gmap-$_instanceId';
    _containerId = 'ohtli-route-gmap-container-$_instanceId';
    _clickCallbackName = 'ohtliRouteMapClick_$_instanceId';

    _processCoordinatesAndFitBounds();

    if (_useGoogleMaps) {
      _registerGoogleMapPlatformView();
      _ensureGoogleMapsScriptAndHelpers();
      _registerMarkerClickCallback();
      WidgetsBinding.instance.addPostFrameCallback((_) => _renderGoogleMap());
    }
  }

  @override
  void didUpdateWidget(covariant OsrmMapWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    final dataChanged = oldWidget.stops != widget.stops ||
        oldWidget.origin != widget.origin ||
        oldWidget.destination != widget.destination ||
        oldWidget.routeCoordinates != widget.routeCoordinates ||
        oldWidget.routeGeometry != widget.routeGeometry;
    final themeChanged = oldWidget.isDark != widget.isDark;

    if (dataChanged) {
      _processCoordinatesAndFitBounds();
    }
    if (_useGoogleMaps && (dataChanged || themeChanged)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _renderGoogleMap());
    }
  }

  @override
  void dispose() {
    if (kIsWeb) {
      try {
        js.context.deleteProperty(_clickCallbackName);
        if (js.context.hasProperty('destroyOhtliRouteMap')) {
          js.context.callMethod('destroyOhtliRouteMap', [_containerId]);
        }
      } catch (_) {}
    }
    super.dispose();
  }

  void _registerGoogleMapPlatformView() {
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int viewId) {
      final element = html.DivElement()
        ..id = _containerId
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.margin = '0'
        ..style.padding = '0';
      return element;
    });
  }

  void _registerMarkerClickCallback() {
    js.context[_clickCallbackName] = js.allowInterop((dynamic idxArg) {
      if (!mounted) return;
      final idx = (idxArg is num) ? idxArg.toInt() : int.tryParse(idxArg.toString());
      if (idx != null && idx >= 0 && idx < _parsedStops.length) {
        widget.onStopSelected?.call(_parsedStops[idx]);
      }
    });
  }

  void _ensureGoogleMapsScriptAndHelpers() {
    final key = _activeMapsKey;
    if (key.isEmpty) return;

    if (html.document.getElementById('google-maps-places-script') == null) {
      final script = html.ScriptElement()
        ..id = 'google-maps-places-script'
        ..src = 'https://maps.googleapis.com/maps/api/js?key=$key&libraries=places&language=es&region=MX'
        ..async = true;
      html.document.head?.append(script);
    }

    if (html.document.getElementById('ohtli-route-gmap-helpers') == null ||
        !js.context.hasProperty('renderOhtliRouteMap')) {
      html.document.getElementById('ohtli-route-gmap-helpers')?.remove();
      final helperScript = html.ScriptElement()
        ..id = 'ohtli-route-gmap-helpers'
        ..text = '''
        window.ohtliRouteMaps = window.ohtliRouteMaps || {};

        window.destroyOhtliRouteMap = function(containerId) {
          const state = window.ohtliRouteMaps[containerId];
          if (state) {
            state.markers.forEach(m => m.setMap(null));
            state.polylines.forEach(p => p.setMap(null));
            delete window.ohtliRouteMaps[containerId];
          }
        };

        window.renderOhtliRouteMap = function(containerId, configJson, clickCallbackName) {
          const cfg = JSON.parse(configJson);
          const tryMount = function(attemptsLeft) {
            const el = document.getElementById(containerId);
            if (!el || el.offsetWidth === 0 || el.offsetHeight === 0 || !window.google || !window.google.maps) {
              if (attemptsLeft > 0) {
                setTimeout(function() { tryMount(attemptsLeft - 1); }, 120);
              }
              return;
            }

            const darkStyles = [
              { elementType: "geometry", stylers: [{ color: "#1a1b20" }] },
              { elementType: "labels.text.fill", stylers: [{ color: "#9095a0" }] },
              { elementType: "labels.text.stroke", stylers: [{ color: "#141418" }] },
              { featureType: "administrative", elementType: "geometry", stylers: [{ color: "#2c2e36" }] },
              { featureType: "poi", elementType: "geometry", stylers: [{ color: "#22232a" }] },
              { featureType: "poi.park", elementType: "geometry", stylers: [{ color: "#1b2b26" }] },
              { featureType: "poi.business", stylers: [{ visibility: "off" }] },
              { featureType: "road", elementType: "geometry", stylers: [{ color: "#2c2e38" }] },
              { featureType: "road.arterial", elementType: "geometry", stylers: [{ color: "#353846" }] },
              { featureType: "road.highway", elementType: "geometry", stylers: [{ color: "#414658" }] },
              { featureType: "transit", elementType: "geometry", stylers: [{ color: "#252730" }] },
              { featureType: "water", elementType: "geometry", stylers: [{ color: "#13292d" }] },
              { featureType: "water", elementType: "labels.text.fill", stylers: [{ color: "#4e7c84" }] }
            ];

            const lightStyles = [
              { featureType: "all", elementType: "geometry", stylers: [{ saturation: -12 }] },
              { featureType: "poi.business", elementType: "all", stylers: [{ visibility: "off" }] },
              { featureType: "landscape", elementType: "geometry", stylers: [{ color: "#F0EEE9" }] },
              { featureType: "poi.park", elementType: "geometry", stylers: [{ color: "#dce8df" }] },
              { featureType: "road", elementType: "geometry", stylers: [{ color: "#FFFFFF" }] },
              { featureType: "road.highway", elementType: "geometry", stylers: [{ color: "#D8D4CB" }] },
              { featureType: "water", elementType: "geometry", stylers: [{ color: "#2C666E" }] },
              { featureType: "water", elementType: "labels.text.fill", stylers: [{ color: "#FFFFFF" }] }
            ];

            const styles = cfg.isDark ? darkStyles : lightStyles;
            const bgColor = cfg.isDark ? "#141418" : "#F0EEE9";

            let state = window.ohtliRouteMaps[containerId];
            if (!state || state.el !== el) {
              const map = new google.maps.Map(el, {
                center: { lat: cfg.centerLat, lng: cfg.centerLng },
                zoom: cfg.zoom || 14,
                styles: styles,
                disableDefaultUI: true,
                zoomControl: true,
                fullscreenControl: true,
                gestureHandling: "cooperative",
                clickableIcons: false,
                backgroundColor: bgColor
              });
              state = { map: map, el: el, markers: [], polylines: [] };
              window.ohtliRouteMaps[containerId] = state;
            } else {
              state.map.setOptions({ styles: styles, backgroundColor: bgColor });
              state.markers.forEach(m => m.setMap(null));
              state.polylines.forEach(p => p.setMap(null));
              state.markers = [];
              state.polylines = [];
            }

            const map = state.map;
            const bounds = new google.maps.LatLngBounds();
            let hasBounds = false;

            if (cfg.path && cfg.path.length >= 2) {
              const latLngPath = cfg.path.map(pt => {
                const ll = { lat: pt[0], lng: pt[1] };
                bounds.extend(ll);
                hasBounds = true;
                return ll;
              });

              const casing = new google.maps.Polyline({
                path: latLngPath,
                geodesic: true,
                strokeColor: cfg.isDark ? "#0A090C" : "#FFFFFF",
                strokeOpacity: 0.78,
                strokeWeight: 7.5,
                zIndex: 1
              });
              casing.setMap(map);
              state.polylines.push(casing);

              const routeLine = new google.maps.Polyline({
                path: latLngPath,
                geodesic: true,
                strokeColor: "#2C666E",
                strokeOpacity: 0.96,
                strokeWeight: 4.5,
                zIndex: 2,
                icons: [{
                  icon: {
                    path: google.maps.SymbolPath.FORWARD_CLOSED_ARROW,
                    scale: 2.4,
                    strokeColor: "#F59E0B",
                    fillColor: "#F59E0B",
                    fillOpacity: 1
                  },
                  offset: "24px",
                  repeat: "95px"
                }]
              });
              routeLine.setMap(map);
              state.polylines.push(routeLine);
            }

            if (cfg.stops && cfg.stops.length > 0) {
              const total = cfg.stops.length;
              cfg.stops.forEach((s, idx) => {
                const pos = { lat: s.lat, lng: s.lng };
                bounds.extend(pos);
                hasBounds = true;

                const isLast = (idx === total - 1 && total > 1);
                const fillColor = isLast ? "#E26D5C" : "#2C666E";

                const marker = new google.maps.Marker({
                  position: pos,
                  map: map,
                  title: s.index + ". " + s.name + (s.time ? " (" + s.time + ")" : ""),
                  zIndex: 10 + idx,
                  label: {
                    text: String(s.index),
                    color: "#FFFFFF",
                    fontWeight: "bold",
                    fontSize: "12px"
                  },
                  icon: {
                    path: google.maps.SymbolPath.CIRCLE,
                    scale: 13,
                    fillColor: fillColor,
                    fillOpacity: 1,
                    strokeColor: "#FFFFFF",
                    strokeWeight: 2.5
                  }
                });

                marker.addListener("click", function() {
                  if (clickCallbackName && typeof window[clickCallbackName] === "function") {
                    window[clickCallbackName](idx);
                  }
                });

                state.markers.push(marker);
              });
            }

            if (hasBounds) {
              if (cfg.stops && cfg.stops.length === 1 && (!cfg.path || cfg.path.length < 2)) {
                map.setCenter({ lat: cfg.stops[0].lat, lng: cfg.stops[0].lng });
                map.setZoom(15);
              } else {
                map.fitBounds(bounds, { top: 36, right: 28, bottom: 36, left: 28 });
              }
            }
          };
          tryMount(50);
        };
        ''';
      html.document.head?.append(helperScript);
    }
  }

  void _renderGoogleMap() {
    if (!mounted || !_useGoogleMaps) return;
    if (!js.context.hasProperty('renderOhtliRouteMap')) return;

    final config = <String, dynamic>{
      'centerLat': _centerLat,
      'centerLng': _centerLng,
      'zoom': _zoom,
      'isDark': widget.isDark,
      'stops': _parsedStops
          .map((s) => {
                'index': s['index'],
                'name': s['name'],
                'lat': s['lat'],
                'lng': s['lng'],
                'time': s['time'],
              })
          .toList(),
      'path': _parsedPath,
    };

    try {
      js.context.callMethod(
        'renderOhtliRouteMap',
        [_containerId, json.encode(config), _clickCallbackName],
      );
    } catch (_) {}
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

    // 1. Extraer paradas válidas conservando todos los metadatos para el modal de lugar
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
          ...m,
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
          if (p0 < 0 && p1 > 0) {
            _parsedPath.add([p1, p0]);
          } else {
            _parsedPath.add([p0, p1]);
          }
        }
      }
    }

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
    if (_useGoogleMaps) {
      _renderGoogleMap();
    } else {
      setState(() {
        _centerLat = _initialCenterLat;
        _centerLng = _initialCenterLng;
        _zoom = _initialZoom;
        _panOffset = Offset.zero;
      });
    }
    widget.onResetView?.call();
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
  // MATEMÁTICAS DE PROYECCIÓN WEB MERCATOR (MODO FALLBACK)
  // ==========================================
  static double _latToY(double lat, double zoom) {
    final latRad = lat * math.pi / 180.0;
    final clamped = latRad.clamp(-1.4844, 1.4844);
    return (1.0 - math.log(math.tan(clamped) + (1.0 / math.cos(clamped))) / math.pi) /
        2.0 *
        math.pow(2.0, zoom) *
        256.0;
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
    if (_useGoogleMaps) {
      return _buildGoogleMapsContainer();
    }
    return _buildOsmFallbackContainer();
  }

  /// Visor interactivo Google Maps API con ruta OSRM y barra de estado inferior
  Widget _buildGoogleMapsContainer() {
    return Container(
      height: widget.height,
      width: double.infinity,
      decoration: BoxDecoration(
        color: widget.isDark ? const Color(0xFF141418) : const Color(0xFFF0EEE9),
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
        borderRadius: BorderRadius.circular(17),
        child: Column(
          children: [
            // Área cartográfica principal de Google Maps
            Expanded(
              child: HtmlElementView(viewType: _viewType),
            ),

            // Barra inferior compacta con controles fuera del PlatformView para garantizar clics
            if (!widget.compact)
            Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: widget.isDark ? const Color(0xFF1A1B20) : Colors.white,
                border: Border(
                  top: BorderSide(
                    color: widget.isDark ? Colors.white12 : OhtliColors.cardBorder,
                  ),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.directions_walk_rounded,
                    color: OhtliColors.stormyTeal,
                    size: 16,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      widget.title ?? 'Caminando · Ruta OSRM · ${_parsedStops.length} paradas',
                      style: GoogleFonts.inter(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: widget.isDark ? Colors.white70 : OhtliColors.onyx,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Tooltip(
                    message: 'Centrar ruta completa',
                    child: InkWell(
                      onTap: _resetView,
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.center_focus_strong_rounded,
                              size: 14,
                              color: widget.isDark ? Colors.white70 : OhtliColors.onyx,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Centrar',
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: widget.isDark ? Colors.white70 : OhtliColors.onyx,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  InkWell(
                    onTap: _openInOpenStreetMap,
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                      child: Text(
                        'OSM',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: OhtliColors.stormyTeal,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  InkWell(
                    onTap: _openInGoogleMaps,
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: OhtliColors.stormyTeal,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.navigation_rounded, size: 12, color: Colors.white),
                          const SizedBox(width: 4),
                          Text(
                            'Google Maps',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Respaldo nativo directo sobre OpenStreetMap (tile.openstreetmap.org) si no hay API key
  Widget _buildOsmFallbackContainer() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewWidth = constraints.maxWidth;
        final viewHeight = widget.height;
        final viewSize = Size(viewWidth, viewHeight);

        final intZoom = _zoom.floor();
        final centerX = _lngToX(_centerLng, intZoom.toDouble());
        final centerY = _latToY(_centerLat, intZoom.toDouble());

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

            final tileUrl = 'https://tile.openstreetmap.org/$intZoom/$tx/$ty.png';

            Widget tileImage = Image.network(
              tileUrl,
              fit: BoxFit.cover,
              filterQuality: FilterQuality.medium,
              errorBuilder: (_, _, _) => Container(
                color: widget.isDark ? const Color(0xFF1E1E24) : const Color(0xFFE9ECEF),
              ),
            );

            if (widget.isDark) {
              tileImage = ColorFiltered(
                colorFilter: const ColorFilter.matrix(<double>[
                  -0.75, 0, 0, 0, 225,
                  0, -0.75, 0, 0, 225,
                  0, 0, -0.75, 0, 230,
                  0, 0, 0, 1, 0,
                ]),
                child: tileImage,
              );
            }

            tileWidgets.add(
              Positioned(
                left: tileViewX,
                top: tileViewY,
                width: 256,
                height: 256,
                child: tileImage,
              ),
            );
          }
        }

        final stopOffsets = <Map<String, dynamic>>[];
        for (final s in _parsedStops) {
          final offset = _geoToPixel(s['lat'] as double, s['lng'] as double, viewSize);
          stopOffsets.add({
            ...s,
            'offset': offset,
          });
        }

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
            borderRadius: BorderRadius.circular(17),
            child: Stack(
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    onPanUpdate: (details) {
                      setState(() {
                        _panOffset += details.delta;
                      });
                    },
                    child: Stack(
                      children: [
                        ...tileWidgets,
                        if (pathOffsets.length >= 2)
                          Positioned.fill(
                            child: CustomPaint(
                              painter: _OsmRoutePainter(
                                points: pathOffsets,
                                isDark: widget.isDark,
                              ),
                            ),
                          ),
                        ...stopOffsets.asMap().entries.map((entry) {
                          final idx = entry.key;
                          final s = entry.value;
                          final Offset pt = s['offset'] as Offset;
                          final bool isLast = idx == stopOffsets.length - 1;
                          final bool isFirst = idx == 0;
                          final bool isHovered = _hoveredStopIndex == idx;

                          final Color pinColor = isLast
                              ? const Color(0xFFE26D5C)
                              : (isFirst ? const Color(0xFF2C666E) : OhtliColors.cempasuchil);

                          return Positioned(
                            left: pt.dx - 16,
                            top: pt.dy - 16,
                            child: MouseRegion(
                              cursor: SystemMouseCursors.click,
                              onEnter: (_) => setState(() => _hoveredStopIndex = idx),
                              onExit: (_) => setState(() => _hoveredStopIndex = null),
                              child: GestureDetector(
                                onTap: () {
                                  if (idx < _parsedStops.length) {
                                    widget.onStopSelected?.call(_parsedStops[idx]);
                                  }
                                },
                                child: AnimatedScale(
                                  scale: isHovered ? 1.18 : 1.0,
                                  duration: const Duration(milliseconds: 160),
                                  child: Tooltip(
                                    message: '${s['index']}. ${s['name']}',
                                    child: Container(
                                      width: 32,
                                      height: 32,
                                      decoration: BoxDecoration(
                                        color: pinColor,
                                        shape: BoxShape.circle,
                                        border: Border.all(color: Colors.white, width: 2.5),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withOpacity(0.45),
                                            blurRadius: 8,
                                            offset: const Offset(0, 3),
                                          ),
                                        ],
                                      ),
                                      child: Center(
                                        child: Text(
                                          '${s['index']}',
                                          style: GoogleFonts.inter(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w900,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                ),

                if (!widget.compact)
                Positioned(
                  top: 12,
                  left: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: (widget.isDark ? const Color(0xFF141418) : Colors.white).withOpacity(0.92),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: OhtliColors.stormyTeal.withOpacity(0.35)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.14),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.directions_walk_rounded,
                          color: OhtliColors.stormyTeal,
                          size: 14,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          widget.title ?? 'Caminando · OpenStreetMap & OSRM',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: widget.isDark ? Colors.white : OhtliColors.onyx,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '· ${_parsedStops.length} paradas',
                          style: GoogleFonts.inter(
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                            color: widget.isDark ? Colors.white60 : OhtliColors.subtleText,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                Positioned(
                  top: 12,
                  right: 12,
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

                if (!widget.compact)
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
                      '© OpenStreetMap contributors',
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

/// Pintor de la línea de ruta peatonal sobre la proyección de OpenStreetMap (modo fallback)
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

    final glowPaint = Paint()
      ..color = (isDark ? Colors.black : Colors.white).withOpacity(0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, glowPaint);

    final casingPaint = Paint()
      ..color = OhtliColors.cempasuchil.withOpacity(0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, casingPaint);

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

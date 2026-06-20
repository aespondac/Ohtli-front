// ignore_for_file: avoid_web_libraries_in_flutter, undefined_function, uri_does_not_exist, deprecated_member_use

import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:js' as js;
import 'dart:ui_web' as ui_web;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../theme/colors.dart';


class OsrmMapWidget extends StatefulWidget {
  final Map<String, dynamic> origin;
  final Map<String, dynamic> destination;
  final List<dynamic> routeCoordinates; // Array of [lng, lat]

  const OsrmMapWidget({
    super.key,
    required this.origin,
    required this.destination,
    required this.routeCoordinates,
  });

  @override
  State<OsrmMapWidget> createState() => _OsrmMapWidgetState();
}

class _OsrmMapWidgetState extends State<OsrmMapWidget> {
  String _mapDivId = 'osrm-map-container';

  @override
  void initState() {
    super.initState();
    // Unique ID to allow multiple renders
    _mapDivId = 'osrm-map-container-${DateTime.now().millisecondsSinceEpoch}';
    _registerMapPlatformView();
    // Use a slight delay to ensure the DOM element is mounted before running JS
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 500), _initMap);
    });
  }

  void _registerMapPlatformView() {
    if (kIsWeb) {
      ui_web.platformViewRegistry.registerViewFactory(_mapDivId, (int viewId) {
        final element = html.DivElement()
          ..id = _mapDivId
          ..style.width = '100%'
          ..style.height = '100%'
          ..style.borderRadius = '16px'
          ..style.overflow = 'hidden';
        return element;
      });
    }
  }

  void _initMap() {
    if (!kIsWeb) return;

    // Convert GeoJSON [lng, lat] to Google Maps {lat, lng}
    final pathJson = jsonEncode(
      widget.routeCoordinates.map((coord) => {'lat': coord[1], 'lng': coord[0]}).toList(),
    );

    final originLat = widget.origin['lat'];
    final originLng = widget.origin['lng'];
    final destLat = widget.destination['lat'];
    final destLng = widget.destination['lng'];

    final script = '''
      (function() {
        const mapDiv = document.getElementById('$_mapDivId');
        if (mapDiv && window.google && window.google.maps) {
          const map = new google.maps.Map(mapDiv, {
            mapTypeControl: false,
            streetViewControl: false,
            fullscreenControl: false,
            zoomControl: true,
            styles: [
              { "elementType": "geometry", "stylers": [{ "color": "#242f3e" }] },
              { "elementType": "labels.text.stroke", "stylers": [{ "color": "#242f3e" }] },
              { "elementType": "labels.text.fill", "stylers": [{ "color": "#746855" }] },
              { "featureType": "administrative.locality", "elementType": "labels.text.fill", "stylers": [{ "color": "#d59563" }] },
              { "featureType": "poi", "elementType": "labels.text.fill", "stylers": [{ "color": "#d59563" }] },
              { "featureType": "poi.park", "elementType": "geometry", "stylers": [{ "color": "#263c3f" }] },
              { "featureType": "poi.park", "elementType": "labels.text.fill", "stylers": [{ "color": "#6b9a76" }] },
              { "featureType": "road", "elementType": "geometry", "stylers": [{ "color": "#38414e" }] },
              { "featureType": "road", "elementType": "geometry.stroke", "stylers": [{ "color": "#212a37" }] },
              { "featureType": "road", "elementType": "labels.text.fill", "stylers": [{ "color": "#9ca5b3" }] },
              { "featureType": "road.highway", "elementType": "geometry", "stylers": [{ "color": "#746855" }] },
              { "featureType": "road.highway", "elementType": "geometry.stroke", "stylers": [{ "color": "#1f2835" }] },
              { "featureType": "road.highway", "elementType": "labels.text.fill", "stylers": [{ "color": "#f3d19c" }] },
              { "featureType": "transit", "elementType": "geometry", "stylers": [{ "color": "#2f3948" }] },
              { "featureType": "transit.station", "elementType": "labels.text.fill", "stylers": [{ "color": "#d59563" }] },
              { "featureType": "water", "elementType": "geometry", "stylers": [{ "color": "#17263c" }] },
              { "featureType": "water", "elementType": "labels.text.fill", "stylers": [{ "color": "#515c6d" }] },
              { "featureType": "water", "elementType": "labels.text.stroke", "stylers": [{ "color": "#17263c" }] }
            ]
          });

          const path = $pathJson;

          const polyline = new google.maps.Polyline({
            path: path,
            geodesic: true,
            strokeColor: '#E2711D', // Ohtli Flame Orange
            strokeOpacity: 0.8,
            strokeWeight: 6,
          });

          polyline.setMap(map);

          // Custom pins for Origin and Destination
          new google.maps.Marker({
            position: {lat: $originLat, lng: $originLng},
            map: map,
            title: 'Origen',
            icon: 'http://maps.google.com/mapfiles/ms/icons/green-dot.png'
          });

          new google.maps.Marker({
            position: {lat: $destLat, lng: $destLng},
            map: map,
            title: 'Destino',
            icon: 'http://maps.google.com/mapfiles/ms/icons/red-dot.png'
          });

          // Fit bounds
          const bounds = new google.maps.LatLngBounds();
          path.forEach((p) => bounds.extend(p));
          map.fitBounds(bounds);
        }
      })();
    ''';

    js.context.callMethod('eval', [script]);
  }

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      height: 400,
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E22),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: OhtliColors.stormyTeal.withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: HtmlElementView(viewType: _mapDivId),
      ),
    );
  }
}

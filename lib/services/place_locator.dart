// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use, undefined_function

import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:js' as js;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/trip_model.dart';

/// Encuentra la ubicación de una parada que no la trae guardada: primero en el catálogo
/// (o en la sugerencia de la que salió) y, si no, buscando su nombre en Google Places
/// dentro de la Ciudad de México. Solo sirve para dibujarla; no se guarda en el viaje.
class PlaceLocator {
  PlaceLocator._();

  static final Map<String, (double, double)?> _cache = {};

  static (double, double)? _fromLocation(dynamic loc) {
    if (loc is GeoPoint) return (loc.latitude, loc.longitude);
    if (loc is Map) {
      final lat = (loc['lat'] ?? loc['latitude']) as num?;
      final lng = (loc['lng'] ?? loc['longitude']) as num?;
      if (lat != null && lng != null && (lat != 0 || lng != 0)) return (lat.toDouble(), lng.toDouble());
    }
    return null;
  }

  static Future<(double, double)?> locate(PlaceSection p) async {
    if (p.lat != null && p.lng != null) return (p.lat!, p.lng!);
    final key = '${p.poiSource ?? ''}|${p.poiId ?? ''}|${p.title.trim().toLowerCase()}';
    if (_cache.containsKey(key)) return _cache[key];

    (double, double)? found;
    if (p.poiId != null && p.poiId!.isNotEmpty) {
      try {
        final col = p.isSuggestion ? 'poi_suggestions' : 'pois';
        final doc = await FirebaseFirestore.instance.collection(col).doc(p.poiId).get();
        found = _fromLocation(doc.data()?['location']);
      } catch (_) {}
    }
    if (found == null && p.title.trim().isNotEmpty) {
      found = await _searchByName('${p.title.trim()}, Ciudad de México');
    }
    _cache[key] = found;
    return found;
  }

  static const String _mapsKey = String.fromEnvironment('mapsApiKey');
  static const String _fallbackKey = String.fromEnvironment('apiKey');

  static Future<(double, double)?> _searchByName(String query) async {
    if (!kIsWeb) return null;
    final storageKey = 'ohtli_geo_${query.toLowerCase()}';
    try {
      final saved = html.window.localStorage[storageKey];
      if (saved != null) {
        final parts = saved.split(',');
        if (parts.length == 2) return (double.parse(parts[0]), double.parse(parts[1]));
        return null;
      }
    } catch (_) {}

    final key = _mapsKey.isNotEmpty ? _mapsKey : _fallbackKey;
    if (key.isEmpty) return null;
    _ensureScripts(key);

    final completer = Completer<(double, double)?>();
    try {
      js.context.callMethod('ohtliFindPlaceLocation', [
        query,
        js.allowInterop((String raw) {
          if (completer.isCompleted) return;
          try {
            final data = jsonDecode(raw) as Map<String, dynamic>;
            final lat = (data['lat'] as num?)?.toDouble();
            final lng = (data['lng'] as num?)?.toDouble();
            completer.complete(lat != null && lng != null ? (lat, lng) : null);
          } catch (_) {
            completer.complete(null);
          }
        }),
      ]);
    } catch (_) {
      return null;
    }
    final result = await completer.future.timeout(const Duration(seconds: 10), onTimeout: () => null);
    if (result != null) {
      try {
        html.window.localStorage[storageKey] = '${result.$1},${result.$2}';
      } catch (_) {}
    }
    return result;
  }

  static void _ensureScripts(String key) {
    if (html.document.getElementById('google-maps-places-script') == null) {
      html.document.head?.append(html.ScriptElement()
        ..id = 'google-maps-places-script'
        ..src = 'https://maps.googleapis.com/maps/api/js?key=$key&libraries=places&language=es&region=MX'
        ..async = true);
    }
    if (js.context.hasProperty('ohtliFindPlaceLocation')) return;
    html.document.head?.append(html.ScriptElement()
      ..id = 'ohtli-place-locator'
      ..text = '''
      window.ohtliFindPlaceLocation = function(query, callback) {
        var tries = 0;
        var run = function() {
          if (!window.google || !google.maps || !google.maps.places) {
            if (tries++ < 50) { setTimeout(run, 200); } else { callback(JSON.stringify({ error: 'sin-api' })); }
            return;
          }
          var service = new google.maps.places.PlacesService(document.createElement('div'));
          service.findPlaceFromQuery({
            query: query,
            fields: ['geometry'],
            locationBias: { center: { lat: 19.4326, lng: -99.1332 }, radius: 30000 }
          }, function(results, status) {
            if (status === google.maps.places.PlacesServiceStatus.OK && results && results.length && results[0].geometry) {
              var loc = results[0].geometry.location;
              callback(JSON.stringify({ lat: loc.lat(), lng: loc.lng() }));
            } else {
              callback(JSON.stringify({ error: String(status) }));
            }
          });
        };
        run();
      };
      ''');
  }
}

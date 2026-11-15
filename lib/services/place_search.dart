import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

/// Sugerencia de Google Places para un texto escrito por la persona.
class PlaceSuggestion {
  final String placeId;
  final String title;
  final String subtitle;
  const PlaceSuggestion(this.placeId, this.title, this.subtitle);
}

/// Lugar resuelto: nombre corto y coordenadas.
class ResolvedPlace {
  final String name;
  final double lat;
  final double lng;
  const ResolvedPlace(this.name, this.lat, this.lng);
}

/// Busca direcciones, colonias y lugares de la Ciudad de México con Google Places
/// (autocompletado sesgado a la CDMX). Sin llave de Maps o fuera de web no sugiere nada.
class PlaceSearch {
  PlaceSearch._();

  static const String _mapsKey = String.fromEnvironment('mapsApiKey');
  static const String _fallbackKey = String.fromEnvironment('apiKey');
  static String get _key => _mapsKey.isNotEmpty ? _mapsKey : _fallbackKey;

  static bool get available => kIsWeb && _key.isNotEmpty;

  static Future<List<PlaceSuggestion>> suggest(String query) async {
    final q = query.trim();
    if (!available || q.length < 3) return const [];
    final raw = await _call('ohtliPlaceSuggest', q);
    if (raw == null) return const [];
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final list = (data['predictions'] as List?) ?? const [];
      return [
        for (final p in list)
          if (p is Map)
            PlaceSuggestion(
              (p['placeId'] ?? '').toString(),
              (p['main'] ?? p['description'] ?? '').toString(),
              (p['secondary'] ?? '').toString(),
            ),
      ];
    } catch (_) {
      return const [];
    }
  }

  static Future<ResolvedPlace?> resolve(PlaceSuggestion s) async {
    if (!available || s.placeId.isEmpty) return null;
    final raw = await _call('ohtliPlaceResolve', s.placeId);
    if (raw == null) return null;
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final lat = (data['lat'] as num?)?.toDouble();
      final lng = (data['lng'] as num?)?.toDouble();
      if (lat == null || lng == null) return null;
      final name = (data['name'] ?? s.title).toString();
      return ResolvedPlace(name.isEmpty ? s.title : name, lat, lng);
    } catch (_) {
      return null;
    }
  }

  static Future<String?> _call(String fn, String arg) async {
    _ensureScripts();
    final completer = Completer<String?>();
    try {
      globalContext.callMethodVarArgs(fn.toJS, <JSAny?>[
        arg.toJS,
        ((JSString raw) {
          if (!completer.isCompleted) completer.complete(raw.toDart);
        }).toJS,
      ]);
    } catch (_) {
      return null;
    }
    return completer.future.timeout(const Duration(seconds: 10), onTimeout: () => null);
  }

  static void _ensureScripts() {
    final hasPlaces = globalContext.has('google') &&
        web.document.querySelector('script[src*="maps.googleapis.com/maps/api/js"]') != null;
    if (!hasPlaces && web.document.getElementById('google-maps-places-script') == null) {
      web.document.head?.append(web.HTMLScriptElement()
        ..id = 'google-maps-places-script'
        ..src = 'https://maps.googleapis.com/maps/api/js?key=$_key&libraries=places&language=es&region=MX'
        ..async = true);
    }
    if (globalContext.has('ohtliPlaceSuggest')) return;
    web.document.head?.append(web.HTMLScriptElement()
      ..id = 'ohtli-place-search'
      ..text = '''
      (function() {
        var CDMX = { north: 19.60, south: 19.04, east: -98.94, west: -99.37 };
        var token = null;
        function ready(cb, fail) {
          var tries = 0;
          (function run() {
            if (window.google && google.maps && google.maps.places) return cb();
            if (tries++ < 50) return setTimeout(run, 200);
            fail();
          })();
        }
        window.ohtliPlaceSuggest = function(query, callback) {
          ready(function() {
            if (!token) token = new google.maps.places.AutocompleteSessionToken();
            new google.maps.places.AutocompleteService().getPlacePredictions({
              input: query,
              sessionToken: token,
              bounds: CDMX,
              componentRestrictions: { country: 'mx' }
            }, function(preds, status) {
              var out = (preds || []).slice(0, 5).map(function(p) {
                var f = p.structured_formatting || {};
                return { placeId: p.place_id, description: p.description,
                         main: f.main_text || p.description, secondary: f.secondary_text || '' };
              });
              callback(JSON.stringify({ predictions: out, status: String(status) }));
            });
          }, function() { callback(JSON.stringify({ predictions: [], status: 'sin-api' })); });
        };
        window.ohtliPlaceResolve = function(placeId, callback) {
          ready(function() {
            new google.maps.places.PlacesService(document.createElement('div')).getDetails({
              placeId: placeId, fields: ['geometry', 'name'], sessionToken: token
            }, function(place, status) {
              token = null;
              if (status === google.maps.places.PlacesServiceStatus.OK && place && place.geometry) {
                var loc = place.geometry.location;
                callback(JSON.stringify({ lat: loc.lat(), lng: loc.lng(), name: place.name || '' }));
              } else {
                callback(JSON.stringify({ error: String(status) }));
              }
            });
          }, function() { callback(JSON.stringify({ error: 'sin-api' })); });
        };
      })();
      ''');
  }
}

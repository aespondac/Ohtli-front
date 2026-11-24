// ignore_for_file: deprecated_member_use

import 'dart:async';
import 'dart:convert';
import 'package:web/web.dart' as web;
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/trip_model.dart';
import '../theme/cdmx_photos.dart';

/// Encuentra la ubicación de una parada que no la trae guardada: primero en el catálogo
/// (o en la sugerencia de la que salió) y, si no, buscando su nombre en Google Places
/// dentro de la Ciudad de México. Solo sirve para dibujarla; no se guarda en el viaje.
class PlaceLocator {
  PlaceLocator._();

  static final Map<String, (double, double)?> _cache = {};
  static final Map<String, Future<Map<String, dynamic>?>> _poiDocs = {};

  /// Documento del lugar en el catálogo (o de la sugerencia), leído una sola vez.
  static Future<Map<String, dynamic>?> _poiDoc(PlaceSection p) {
    final id = p.poiId;
    if (id == null || id.isEmpty) return Future.value(null);
    final col = p.isSuggestion ? 'poi_suggestions' : 'pois';
    return _poiDocs.putIfAbsent('$col/$id', () async {
      try {
        return (await FirebaseFirestore.instance.collection(col).doc(id).get()).data();
      } catch (_) {
        return null; // sin permiso (sugerencia ajena) o sin conexión
      }
    });
  }

  static const String _apiUrl = String.fromEnvironment('yollotlApiUrl', defaultValue: 'https://api.ohtli.quest');
  static final Map<String, Future<Map<String, dynamic>?>> _engineDocs = {};

  /// Ficha del lugar en el catálogo del motor (/v1/pois?ids=): trae las fotos de Wikimedia Commons
  /// con su crédito y los lugares de DENUE, SIC y mercados, que la base de la app no tiene.
  static Future<Map<String, dynamic>?> _engineDoc(String id) {
    return _engineDocs.putIfAbsent(id, () async {
      try {
        final uri = Uri.parse('$_apiUrl/v1/pois').replace(queryParameters: {'ids': id});
        final res = await http.get(uri).timeout(const Duration(seconds: 8));
        if (res.statusCode != 200) return null;
        final decoded = jsonDecode(res.body);
        final list = decoded is Map ? decoded['pois'] : null;
        if (list is List && list.isNotEmpty && list.first is Map) return Map<String, dynamic>.from(list.first as Map);
      } catch (_) {}
      return null;
    });
  }

  /// Foto del propio lugar (y su crédito) según el catálogo, o null. Nunca una foto de referencia
  /// de otro lugar.
  static Future<({String url, String credit})?> catalogPhoto(PlaceSection p) async {
    final id = p.poiId;
    if (id == null || id.isEmpty) return null;
    for (final load in [if (!p.isSuggestion) () => _engineDoc(id), () => _poiDoc(p)]) {
      final d = await load();
      if (d == null) continue;
      String photo = (d['photo_url'] ?? d['image_url'] ?? d['photo'] ?? '').toString();
      if (photo.isEmpty && d['photos'] is List && (d['photos'] as List).isNotEmpty) {
        photo = (d['photos'] as List).first.toString();
      }
      if (photo.startsWith('http') && !CdmxPhotos.isReference(photo)) {
        return (url: photo, credit: (d['photo_credit'] ?? '').toString());
      }
    }
    return null;
  }

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
      found = _fromLocation((await _poiDoc(p))?['location']);
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
      final saved = web.window.localStorage.getItem(storageKey);
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
      globalContext.callMethodVarArgs('ohtliFindPlaceLocation'.toJS, <JSAny?>[(query).jsify(), (((String raw) {
          if (completer.isCompleted) return;
          try {
            final data = jsonDecode(raw) as Map<String, dynamic>;
            final lat = (data['lat'] as num?)?.toDouble();
            final lng = (data['lng'] as num?)?.toDouble();
            completer.complete(lat != null && lng != null ? (lat, lng) : null);
          } catch (_) {
            completer.complete(null);
          }
        })).toJS]);
    } catch (_) {
      return null;
    }
    final result = await completer.future.timeout(const Duration(seconds: 10), onTimeout: () => null);
    if (result != null) {
      try {
        web.window.localStorage.setItem(storageKey, '${result.$1},${result.$2}');
      } catch (_) {}
    }
    return result;
  }

  static void _ensureScripts(String key) {
    if (web.document.getElementById('google-maps-places-script') == null) {
      web.document.head?.append(web.HTMLScriptElement()
        ..id = 'google-maps-places-script'
        ..src = 'https://maps.googleapis.com/maps/api/js?key=$key&libraries=places&language=es&region=MX'
        ..async = true);
    }
    if (globalContext.has('ohtliFindPlaceLocation')) return;
    web.document.head?.append(web.HTMLScriptElement()
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

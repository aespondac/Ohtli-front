import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/poi_model.dart';

/// Lugares recomendados según el perfil de gustos de la cuenta, calculados por el motor
/// Yollotl (similitud coseno de los vectores de 768 dimensiones). Solo ordenan las
/// recomendaciones: la app no muestra el porcentaje. Si la cuenta no tiene un perfil de gustos
/// válido, la lista queda vacía.
class PlaceAffinity {
  PlaceAffinity._();

  static const String _apiUrl =
      String.fromEnvironment('yollotlApiUrl', defaultValue: 'https://api.ohtli.quest');

  static String? _uid;
  static Future<List<Poi>>? _inflight;

  /// Lugares del más al menos afín, en caché por cuenta durante la sesión.
  static Future<List<Poi>> load({bool refresh = false}) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return Future.value(const []);
    if (refresh || _uid != user.uid || _inflight == null) {
      _uid = user.uid;
      _inflight = _fetch(user).then((pois) {
        if (pois.isEmpty) _inflight = null; // reintentar en la próxima visita
        return pois;
      });
    }
    return _inflight!;
  }

  static Future<List<Poi>> _fetch(User user) async {
    try {
      final token = await user.getIdToken();
      final response = await http.get(
        Uri.parse('$_apiUrl/v1/user/${user.uid}/affinity?top_k=60'),
        headers: {'Authorization': 'Bearer $token'},
      ).timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) {
        debugPrint('[PlaceAffinity] HTTP ${response.statusCode}');
        return const [];
      }
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map || decoded['status'] != 'success' || decoded['scores'] is! List) {
        return const [];
      }
      final pois = <Poi>[];
      for (final s in decoded['scores'] as List) {
        if (s is! Map || s['poi'] is! Map) continue;
        final poi = Poi.fromMap(Map<String, dynamic>.from(s['poi'] as Map));
        if (poi.isValidCulturalPlace) pois.add(poi);
      }
      return pois;
    } catch (e) {
      debugPrint('[PlaceAffinity] no disponible: $e');
      return const [];
    }
  }
}

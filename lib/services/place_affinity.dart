import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Afinidad real entre el perfil de gustos de la cuenta y cada lugar, calculada por el motor
/// Yollotl (similitud coseno de los vectores de 768 dimensiones, en porcentaje y sin
/// reescalar). Si la cuenta no tiene un perfil de gustos válido, el mapa queda vacío y la app
/// no muestra ningún porcentaje.
class PlaceAffinity {
  PlaceAffinity._();

  static const String _apiUrl =
      String.fromEnvironment('yollotlApiUrl', defaultValue: 'https://api.ohtli.quest');

  static String? _uid;
  static Future<Map<String, int>>? _inflight;

  /// Lugares más afines (poi_id → %), en caché por cuenta durante la sesión.
  static Future<Map<String, int>> load({bool refresh = false}) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return Future.value(const {});
    if (refresh || _uid != user.uid || _inflight == null) {
      _uid = user.uid;
      _inflight = _fetch(user).then((scores) {
        if (scores.isEmpty) _inflight = null; // reintentar en la próxima visita
        return scores;
      });
    }
    return _inflight!;
  }

  static Future<Map<String, int>> _fetch(User user) async {
    try {
      final token = await user.getIdToken();
      final response = await http.get(
        Uri.parse('$_apiUrl/v1/user/${user.uid}/affinity?top_k=400'),
        headers: {'Authorization': 'Bearer $token'},
      ).timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        debugPrint('[PlaceAffinity] HTTP ${response.statusCode}');
        return const {};
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map || decoded['status'] != 'success' || decoded['scores'] is! List) {
        return const {};
      }
      return {
        for (final s in decoded['scores'] as List)
          if (s is Map && s['poi_id'] != null && s['affinity'] is num)
            s['poi_id'].toString(): (s['affinity'] as num).round(),
      };
    } catch (e) {
      debugPrint('[PlaceAffinity] no disponible: $e');
      return const {};
    }
  }
}

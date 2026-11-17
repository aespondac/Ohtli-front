import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Progreso de un logro (lo calcula el motor: POST /v1/achievements/evaluate).
class AchievementProgress {
  final int value;
  final int goal;
  final bool earned;
  const AchievementProgress(this.value, this.goal, this.earned);

  double get ratio => goal <= 0 ? 1 : (value / goal).clamp(0, 1).toDouble();
}

/// Logros de viajero. El motor los calcula con los viajes de la persona y su catálogo de lugares
/// y otorga los títulos (Admin SDK); la app solo pide que se revisen y muestra el progreso.
class AchievementsService {
  AchievementsService._();
  static final AchievementsService instance = AchievementsService._();

  static const String _apiUrl = String.fromEnvironment('yollotlApiUrl', defaultValue: 'https://api.ohtli.quest');

  final ValueNotifier<Map<String, AchievementProgress>> progress = ValueNotifier(const {});

  /// Títulos que se acaban de ganar (para avisarle a la persona).
  final ValueNotifier<List<String>> justGranted = ValueNotifier(const []);

  Timer? _debounce;
  bool _busy = false;

  /// Revisa en unos segundos (tras terminar, reseñar o publicar un viaje).
  void evaluateSoon() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 3), evaluate);
  }

  Future<void> evaluate() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || _busy) return;
    _busy = true;
    try {
      final token = await user.getIdToken();
      final res = await http
          .post(Uri.parse('$_apiUrl/v1/achievements/evaluate'), headers: {'Authorization': 'Bearer $token'})
          .timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) return;
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      progress.value = parseProgress(body['progress']);
      final granted = [for (final g in (body['granted'] as List?) ?? const []) g.toString()];
      if (granted.isNotEmpty) justGranted.value = granted;
    } catch (e) {
      debugPrint('[Logros] no se pudieron revisar: $e');
    } finally {
      _busy = false;
    }
  }

  static Map<String, AchievementProgress> parseProgress(dynamic raw) {
    if (raw is! Map) return const {};
    return {
      for (final e in raw.entries)
        if (e.value is Map)
          e.key.toString(): AchievementProgress(
            ((e.value as Map)['value'] as num?)?.toInt() ?? 0,
            ((e.value as Map)['goal'] as num?)?.toInt() ?? 1,
            (e.value as Map)['earned'] == true,
          ),
    };
  }
}

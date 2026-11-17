import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import 'itinerary_blackboard_service.dart';

/// "Dame una idea": el motor le pide a Gemini la intención del día con todo lo que ya se eligió
/// en el planificador (POST /v1/mood-idea). null si no hay sesión o el motor no responde: el
/// planificador usa entonces sus ideas de respaldo.
class MoodIdeaService {
  static Future<String?> fetch(Map<String, dynamic> plan) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    String? token;
    try {
      token = await user.getIdToken();
    } catch (_) {}
    if (token == null) return null;
    for (final base in ItineraryBlackboardService.apiBases) {
      try {
        final res = await http
            .post(Uri.parse('$base/v1/mood-idea'),
                headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
                body: jsonEncode(plan))
            .timeout(const Duration(seconds: 20));
        if (res.statusCode == 200) {
          final idea = (jsonDecode(utf8.decode(res.bodyBytes)) as Map)['idea']?.toString().trim();
          if (idea != null && idea.isNotEmpty) return idea;
        }
        if (res.statusCode >= 400 && res.statusCode < 500) return null;
      } catch (_) {}
    }
    return null;
  }
}

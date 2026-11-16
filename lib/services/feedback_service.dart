import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import 'package:web/web.dart' as web;

/// Retroalimentación del comportamiento (RF-12): lo que la persona hace con las
/// recomendaciones y con los lugares se manda al motor Yollotl en lotes
/// (`POST /v1/feedback/events`).
///
/// El motor lo usa de dos formas: para esta cuenta (no vuelve a proponer lo marcado como
/// "No me interesa" y acerca las recomendaciones a lo que guarda o elige) y, de forma anónima
/// y agregada, para calificar cada lugar (aceptación, reemplazo, resiliencia y CTR).
///
/// Los eventos se encolan y se mandan cada pocos segundos; si no hay red se guardan en el
/// navegador y salen en la siguiente visita. Nunca bloquean la interfaz ni lanzan errores.
class FeedbackService {
  FeedbackService._();

  static const String _apiUrl =
      String.fromEnvironment('yollotlApiUrl', defaultValue: 'https://api.ohtli.quest');
  static const String _storageKey = 'ohtli_feedback_queue_v1';
  static const int _maxBatch = 100;
  static const int _maxQueued = 400;
  static const Duration _flushDelay = Duration(seconds: 4);

  static final List<Map<String, dynamic>> _queue = [];
  static final Set<String> _impressed = {};
  static Timer? _timer;
  static bool _sending = false;
  static bool _restored = false;
  static const _uuid = Uuid();

  /// Lugares que esta cuenta marcó con 👍 / "No me interesa" (estado de los botones).
  static final ValueNotifier<Set<String>> liked = ValueNotifier(<String>{});
  static final ValueNotifier<Set<String>> disliked = ValueNotifier(<String>{});
  static String? _loadedFor;

  // ---------------------------------------------------------------------------
  // Lugares
  // ---------------------------------------------------------------------------

  /// La tarjeta del lugar se mostró. Se manda una vez por lugar y superficie en la sesión.
  static void impression(String? poiId, {required String surface, int? position}) {
    if (poiId == null || poiId.isEmpty) return;
    if (!_impressed.add('$surface|$poiId')) return;
    track('poi_impression', poiId: poiId, surface: surface, position: position);
  }

  static void opened(String? poiId, {required String surface, int? position}) =>
      track('poi_open', poiId: poiId, surface: surface, position: position);

  /// Tiempo que la persona tuvo abierto el detalle de un lugar.
  static void dwell(String? poiId, Duration d, {String? surface}) {
    if (d.inMilliseconds < 1500) return; // abrir y cerrar sin leer no dice nada
    track('poi_dwell', poiId: poiId, surface: surface, value: d.inMilliseconds / 1000.0);
  }

  static void saved(String? poiId, bool isSaved, {String? surface}) =>
      track(isSaved ? 'poi_save' : 'poi_unsave', poiId: poiId, surface: surface);

  /// 👍: le interesa. Toca otra vez para quitarlo.
  static void toggleLike(String poiId, {String? surface}) {
    final on = !liked.value.contains(poiId);
    liked.value = {...liked.value}..remove(poiId);
    if (on) {
      liked.value = {...liked.value, poiId};
      disliked.value = {...disliked.value}..remove(poiId);
    }
    track(on ? 'poi_like' : 'poi_unlike', poiId: poiId, surface: surface);
  }

  /// "No me interesa": el motor deja de proponerlo a esta cuenta.
  static void toggleDislike(String poiId, {String? surface}) {
    final on = !disliked.value.contains(poiId);
    disliked.value = {...disliked.value}..remove(poiId);
    if (on) {
      disliked.value = {...disliked.value, poiId};
      liked.value = {...liked.value}..remove(poiId);
    }
    track(on ? 'poi_dislike' : 'poi_undislike', poiId: poiId, surface: surface);
  }

  static void shared(String? poiId, {String? surface}) => track('poi_share', poiId: poiId, surface: surface);
  static void directions(String? poiId, {String? surface}) =>
      track('poi_directions', poiId: poiId, surface: surface);
  static void visited(String? poiId, {String? tripId}) => track('poi_visited', poiId: poiId, tripId: tripId);

  /// Reporte de datos: `closed` (cerró) o `wrong` (precio, horario o ubicación equivocados).
  static void report(String? poiId, {required bool closed, String? reason}) =>
      track(closed ? 'poi_report_closed' : 'poi_report_wrong', poiId: poiId, reason: reason);

  // ---------------------------------------------------------------------------
  // Recomendaciones (itinerarios del motor)
  // ---------------------------------------------------------------------------

  static List<String> stopIds(Map<String, dynamic> option) {
    final route = option['route'];
    if (route is! List) return const [];
    final ids = <String>[];
    for (final s in route) {
      if (s is! Map) continue;
      final id = (s['poi_id'] ?? s['poiId'] ?? s['id'])?.toString();
      if (id != null && id.isNotEmpty && !ids.contains(id)) ids.add(id);
    }
    return ids;
  }

  static final Set<String> _shownOptions = {};

  /// La persona vio una de las opciones generadas (una vez por opción y trabajo).
  static void itineraryShown(String? jobId, int optionIndex, Map<String, dynamic> option) {
    final ids = stopIds(option);
    if (ids.isEmpty || !_shownOptions.add('${jobId ?? '-'}|$optionIndex')) return;
    track('itinerary_shown', jobId: jobId, optionIndex: optionIndex, poiIds: ids, surface: 'itinerary');
  }

  static void itineraryChosen(String? jobId, int? optionIndex, Map<String, dynamic> option, {String? tripId}) {
    final ids = stopIds(option);
    if (ids.isEmpty) return;
    track('itinerary_chosen', jobId: jobId, tripId: tripId, optionIndex: optionIndex, poiIds: ids,
        surface: 'itinerary');
  }

  /// Hizo el viaje (lo terminó). Mide el éxito de la recomendación junto con elegir, no modificar y
  /// compartir (Agente Crítico del motor). `jobId` es el de la recomendación, si la hubo.
  static void itineraryCompleted({required String? tripId, String? jobId}) {
    if ((tripId ?? '').isEmpty) return;
    track('itinerary_completed', jobId: jobId, tripId: tripId, surface: 'trip');
  }

  /// Compartió el viaje: enlace, copia del enlace o publicación (`channel` dice cuál).
  static void itineraryShared({required String? tripId, String? jobId, required String channel}) {
    if ((tripId ?? '').isEmpty) return;
    track('itinerary_shared', jobId: jobId, tripId: tripId, surface: 'trip', reason: channel);
  }

  /// Volvió a generar o descartó las opciones sin elegir ninguna.
  static void itineraryDiscarded(String? jobId, {String? reason}) =>
      track('itinerary_discarded', jobId: jobId, reason: reason);

  /// `origin`: `engine` si la parada la propuso el motor, `manual` si la agregó la persona.
  static void stopRemoved(String? poiId, {String? tripId, String? origin}) =>
      track('stop_removed', poiId: poiId, tripId: tripId, origin: origin);

  static void stopReplaced(String? poiId, String? replacedBy, {String? tripId, String? origin}) {
    if (replacedBy == null || replacedBy.isEmpty || replacedBy == poiId) return;
    track('stop_replaced', poiId: poiId, replacedBy: replacedBy, tripId: tripId, origin: origin);
  }

  static void stopAdded(String? poiId, {String? tripId}) => track('stop_added', poiId: poiId, tripId: tripId);

  static void stopReordered({String? tripId}) => track('stop_reordered', tripId: tripId);

  // ---------------------------------------------------------------------------
  // Cola y envío
  // ---------------------------------------------------------------------------

  static void track(
    String type, {
    String? poiId,
    String? surface,
    int? position,
    num? value,
    String? jobId,
    String? tripId,
    int? optionIndex,
    List<String>? poiIds,
    String? replacedBy,
    String? origin,
    String? reason,
  }) {
    try {
      if (FirebaseAuth.instance.currentUser == null) return; // sin cuenta no hay a quién atribuirlo
      if (_isPoiEvent(type) && (poiId == null || poiId.isEmpty)) return;
      _restore();
      _queue.add({
        'type': type,
        'client_event_id': _uuid.v4(),
        'ts': DateTime.now().toUtc().toIso8601String(),
        if (poiId != null) 'poi_id': poiId,
        if (surface != null) 'surface': surface,
        if (position != null) 'position': position,
        if (value != null) 'value': value,
        if (jobId != null) 'job_id': jobId,
        if (tripId != null) 'trip_id': tripId,
        if (optionIndex != null) 'option_index': optionIndex,
        if (poiIds != null) 'poi_ids': poiIds,
        if (replacedBy != null) 'replaced_by': replacedBy,
        if (origin != null) 'origin': origin,
        if (reason != null) 'reason': reason,
      });
      if (_queue.length > _maxQueued) _queue.removeRange(0, _queue.length - _maxQueued);
      _persist();
      _schedule(_queue.length >= 20 ? Duration.zero : _flushDelay);
    } catch (e) {
      debugPrint('[Feedback] no se pudo encolar $type: $e');
    }
  }

  static bool _isPoiEvent(String type) =>
      type.startsWith('poi_') || type == 'stop_removed' || type == 'stop_replaced' || type == 'stop_added';

  static void _schedule(Duration d) {
    _timer?.cancel();
    _timer = Timer(d, flush);
  }

  /// Manda lo pendiente. Se llama sola; también conviene al cerrar una pantalla.
  static Future<void> flush() async {
    if (_sending || _queue.isEmpty) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    _sending = true;
    final batch = _queue.take(_maxBatch).toList();
    try {
      final token = await user.getIdToken();
      final res = await http
          .post(Uri.parse('$_apiUrl/v1/feedback/events'),
              headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
              body: jsonEncode({'events': batch}))
          .timeout(const Duration(seconds: 30));
      // 2xx: recibido. 4xx (salvo 401/429): el lote no sirve, no se reintenta.
      final drop = (res.statusCode >= 200 && res.statusCode < 300) ||
          (res.statusCode >= 400 && res.statusCode < 500 && res.statusCode != 401 && res.statusCode != 429);
      if (drop) {
        _queue.removeRange(0, batch.length);
        _persist();
      } else {
        debugPrint('[Feedback] HTTP ${res.statusCode}; se reintenta después');
      }
    } catch (e) {
      debugPrint('[Feedback] sin conexión con el motor: $e');
    } finally {
      _sending = false;
    }
    if (_queue.isNotEmpty) _schedule(const Duration(seconds: 30));
  }

  static void _persist() {
    try {
      web.window.localStorage.setItem(_storageKey, jsonEncode(_queue));
    } catch (_) {}
  }

  static void _restore() {
    if (_restored) return;
    _restored = true;
    try {
      final raw = web.window.localStorage.getItem(_storageKey);
      if (raw == null || raw.isEmpty) return;
      final list = jsonDecode(raw);
      if (list is List) {
        _queue.insertAll(0, list.whereType<Map>().map((m) => Map<String, dynamic>.from(m)));
      }
    } catch (_) {}
  }

  /// Carga el estado de 👍 / "No me interesa" de la cuenta y manda lo que quedó pendiente.
  static Future<void> ensureStarted() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || _loadedFor == user.uid) return;
    _loadedFor = user.uid;
    _restore();
    if (_queue.isNotEmpty) _schedule(const Duration(seconds: 2));
    try {
      final token = await user.getIdToken();
      final res = await http.get(Uri.parse('$_apiUrl/v1/feedback/me'),
          headers: {'Authorization': 'Bearer $token'}).timeout(const Duration(seconds: 60));
      if (res.statusCode != 200) return;
      final d = jsonDecode(utf8.decode(res.bodyBytes));
      if (d is! Map) return;
      liked.value = {...((d['liked'] as List?) ?? const []).map((e) => e.toString())};
      disliked.value = {...((d['disliked'] as List?) ?? const []).map((e) => e.toString())};
    } catch (e) {
      _loadedFor = null;
      debugPrint('[Feedback] estado no disponible: $e');
    }
  }

  /// Borra lo que el motor aprendió del uso de esta cuenta (derechos ARCO).
  static Future<bool> deleteMine() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;
    _queue.clear();
    _persist();
    try {
      final token = await user.getIdToken();
      final res = await http.delete(Uri.parse('$_apiUrl/v1/feedback/me'),
          headers: {'Authorization': 'Bearer $token'}).timeout(const Duration(seconds: 60));
      if (res.statusCode == 200) {
        liked.value = {};
        disliked.value = {};
        return true;
      }
    } catch (_) {}
    return false;
  }
}

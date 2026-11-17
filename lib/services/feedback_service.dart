import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import 'package:web/web.dart' as web;

import '../config/app_version.dart';
import 'app_diagnostics.dart';

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
  // Comentarios ("Enviar comentarios")
  // ---------------------------------------------------------------------------

  /// Colección donde se guardan los comentarios escritos a mano. La Cloud Function
  /// `feedbackEmail` (functions/feedback.js) los manda por correo al equipo de Ohtli, y el
  /// administrador los revisa en "Comentarios de la app" (lib/screens/admin/app_feedback_page.dart).
  static const String commentsCollection = 'app_feedback';

  /// Tipos de comentario que acepta firestore.rules.
  static const List<String> commentCategories = ['idea', 'bug', 'other'];
  static const int commentMinLength = 3;
  static const int commentMaxLength = 2000;

  /// Capturas o fotos por comentario y tamaño máximo de cada una (igual que storage.rules).
  static const int maxAttachments = 3;
  static const int maxAttachmentBytes = 5 * 1024 * 1024;

  /// Estado de revisión: nuevo → revisado → resuelto.
  static const String statusNew = 'new';
  static const String statusReviewed = 'reviewed';
  static const String statusResolved = 'resolved';

  /// El comentario se convirtió en un arreglo publicado (da el logro Amini a quien lo envió).
  static const String statusFixed = 'fixed';
  static const List<String> commentStatuses = [statusNew, statusReviewed, statusResolved, statusFixed];

  /// Navegador y sistema en pocas palabras ("Chrome · macOS").
  static String describeBrowser(String userAgent) => AppDiagnostics.describeBrowserOf(userAgent);

  static String _clip(String v, int max) => v.length > max ? v.substring(0, max) : v;

  static Map<String, String> _clipMap(Map<String, String>? m, {int maxKeys = 20, int maxValue = 300}) {
    final out = <String, String>{};
    m?.forEach((k, v) {
      if (out.length >= maxKeys || k.isEmpty || v.isEmpty) return;
      out[_clip(k, 40)] = _clip(v, maxValue);
    });
    return out;
  }

  /// Documento que se guarda en [commentsCollection]. [device], [system], [user] y [errors] solo
  /// van si la persona deja marcada "Incluir info del dispositivo"; los lee solo el administrador.
  static Map<String, dynamic> buildComment({
    required String uid,
    required String message,
    required String category,
    required String screen,
    String? browser,
    String? viewport,
    String? language,
    Map<String, String>? context,
    Map<String, String>? device,
    Map<String, String>? system,
    Map<String, String>? user,
    List<Map<String, String>>? errors,
    List<String>? screenshots,
    Object? createdAt,
  }) {
    final ctx = _clipMap(context, maxKeys: 8, maxValue: 200);
    final dev = _clipMap(device);
    final sys = _clipMap(system, maxKeys: 15);
    final usr = _clipMap(user, maxKeys: 10)..['uid'] = uid;
    final errs = [
      for (final e in (errors ?? const <Map<String, String>>[]).reversed.take(10).toList().reversed)
        _clipMap(e, maxKeys: 4),
    ];
    final shots = [for (final p in (screenshots ?? const <String>[]).take(maxAttachments)) _clip(p, 200)];
    return {
      'uid': uid,
      'message': _clip(message.trim(), commentMaxLength),
      'category': commentCategories.contains(category) ? category : 'other',
      'screen': _clip(screen, 80),
      'appVersion': kAppVersion,
      'status': statusNew,
      if (browser != null) 'browser': _clip(browser, 80),
      if (viewport != null) 'viewport': _clip(viewport, 20),
      if (language != null) 'language': _clip(language, 20),
      if (ctx.isNotEmpty) 'context': ctx,
      if (dev.isNotEmpty) 'device': dev,
      if (sys.isNotEmpty) 'system': sys,
      'user': usr,
      if (errs.isNotEmpty) 'errors': errs,
      if (shots.isNotEmpty) 'screenshots': shots,
      'createdAt': createdAt ?? FieldValue.serverTimestamp(),
    };
  }

  /// Guarda un comentario de la persona con sesión. Lanza si no hay sesión o si falla.
  /// `screen` dice desde dónde se mandó (p. ej. `onboarding`); `context` agrega datos útiles
  /// (paso, id del trabajo de la IA). Las [attachments] (capturas o fotos) se suben primero a
  /// Storage, en una carpeta que solo lee el administrador.
  static Future<void> sendComment({
    required String message,
    required String category,
    required String screen,
    Map<String, String>? context,
    List<FeedbackAttachment> attachments = const [],
    bool includeDiagnostics = true,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('Inicia sesión para enviar comentarios.');
    final ref = FirebaseFirestore.instance.collection(commentsCollection).doc();
    final paths = <String>[];
    var i = 0;
    for (final a in attachments.take(maxAttachments)) {
      if (a.bytes.isEmpty || a.bytes.length > maxAttachmentBytes) continue;
      i++;
      final path = 'app_feedback/${user.uid}/${ref.id}/$i.${a.extension}';
      await FirebaseStorage.instance.ref(path).putData(a.bytes, SettableMetadata(contentType: a.mimeType));
      paths.add(path);
    }
    final device = includeDiagnostics ? AppDiagnostics.device() : const <String, String>{};
    await ref.set(buildComment(
      uid: user.uid,
      message: message,
      category: category,
      screen: screen,
      browser: device['navegador'],
      viewport: device['ventana'],
      language: device['idioma'],
      context: context,
      device: includeDiagnostics ? device : null,
      system: includeDiagnostics ? AppDiagnostics.system() : {'version': kAppVersion},
      user: AppDiagnostics.user(),
      errors: includeDiagnostics ? AppDiagnostics.recentErrors : null,
      screenshots: paths,
    ));
  }

  // --- Administrador ---

  static CollectionReference<Map<String, dynamic>> get _comments =>
      FirebaseFirestore.instance.collection(commentsCollection);

  static Stream<List<AppFeedback>> watchComments() => _comments
      .orderBy('createdAt', descending: true)
      .limit(300)
      .snapshots()
      .map((q) => [for (final d in q.docs) AppFeedback.fromMap(d.id, d.data())]);

  static Stream<int> watchNewCount() =>
      _comments.where('status', isEqualTo: statusNew).snapshots().map((q) => q.size);

  static Future<void> setCommentStatus(String id, String status, {String? note}) => _comments.doc(id).update({
        'status': status,
        if (note != null) 'reviewNote': _clip(note.trim(), 1000),
        'reviewedAt': FieldValue.serverTimestamp(),
      });

  static final Map<String, Future<String>> _urls = {};

  /// URL de una captura (solo el administrador tiene permiso de leerlas).
  static Future<String> attachmentUrl(String path) =>
      _urls.putIfAbsent(path, () => FirebaseStorage.instance.ref(path).getDownloadURL());

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

/// Captura o foto que acompaña un comentario.
class FeedbackAttachment {
  final Uint8List bytes;
  final String mimeType;
  /// true si es la captura automática de la pantalla.
  final bool isScreenCapture;
  const FeedbackAttachment(this.bytes, this.mimeType, {this.isScreenCapture = false});

  String get extension => switch (mimeType) {
        'image/png' => 'png',
        'image/webp' => 'webp',
        'image/gif' => 'gif',
        _ => 'jpg',
      };
}

/// Un comentario guardado en `app_feedback`, como lo ve el administrador.
class AppFeedback {
  final String id;
  final String uid;
  final String message;
  final String category;
  final String screen;
  final String status;
  final String appVersion;
  final String? reviewNote;
  final DateTime? createdAt;
  final Map<String, String> context;
  final Map<String, String> device;
  final Map<String, String> system;
  final Map<String, String> user;
  final List<Map<String, String>> errors;
  final List<String> screenshots;

  const AppFeedback({
    required this.id,
    required this.uid,
    required this.message,
    required this.category,
    required this.screen,
    required this.status,
    this.appVersion = '',
    this.reviewNote,
    this.createdAt,
    this.context = const {},
    this.device = const {},
    this.system = const {},
    this.user = const {},
    this.errors = const [],
    this.screenshots = const [],
  });

  bool get isNew => status == FeedbackService.statusNew;
  String get userName => user['nombre'] ?? user['correo'] ?? 'Viajero Ohtli';

  static Map<String, String> _strings(Object? v) =>
      v is Map ? {for (final e in v.entries) e.key.toString(): e.value?.toString() ?? ''} : const {};

  factory AppFeedback.fromMap(String id, Map<String, dynamic> d) {
    final device = _strings(d['device']);
    return AppFeedback(
      id: id,
      uid: (d['uid'] ?? '').toString(),
      message: (d['message'] ?? '').toString(),
      category: (d['category'] ?? 'other').toString(),
      screen: (d['screen'] ?? '').toString(),
      status: (d['status'] ?? FeedbackService.statusNew).toString(),
      appVersion: (d['appVersion'] ?? '').toString(),
      reviewNote: d['reviewNote']?.toString(),
      createdAt: d['createdAt'] is Timestamp ? (d['createdAt'] as Timestamp).toDate() : null,
      context: _strings(d['context']),
      // Comentarios anteriores solo traían navegador, ventana e idioma sueltos
      device: device.isNotEmpty
          ? device
          : {
              if (d['browser'] != null) 'navegador': d['browser'].toString(),
              if (d['viewport'] != null) 'ventana': d['viewport'].toString(),
              if (d['language'] != null) 'idioma': d['language'].toString(),
            },
      system: _strings(d['system']),
      user: {..._strings(d['user']), if (d['uid'] != null) 'uid': d['uid'].toString()},
      errors: [for (final e in (d['errors'] as List?) ?? const []) _strings(e)],
      screenshots: [for (final p in (d['screenshots'] as List?) ?? const []) p.toString()],
    );
  }
}

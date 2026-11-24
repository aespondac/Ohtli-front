import 'user_private_data.dart';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:uuid/uuid.dart';
import '../models/trip_model.dart';
import 'feedback_service.dart';
import 'option_trip.dart';
import 'trip_transfers.dart';
import 'trip_service.dart';

class ItineraryBlackboardService {
  static const String _primaryApiUrl = String.fromEnvironment(
    'yollotlApiUrl',
    defaultValue: 'https://api-xluju5gywq-uc.a.run.app',
  );
  static const String _secondaryApiUrl = 'https://api.ohtli.quest';

  /// Servidores del motor, en orden (el segundo es el respaldo).
  static const List<String> apiBases = [_primaryApiUrl, _secondaryApiUrl];

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final TripService _tripService = TripService();

  /// Solicita el cálculo de un itinerario al Sistema Multi-Agente (SMA)
  /// retornando el [job_id] único del Blackboard en tiempo récord (<300ms).
  Future<String> requestItineraryJob({
    required String userId,
    required double budget,
    required Map<String, double> origin,
    Map<String, double>? destination,
    String topology = 'radio',
    required String moodText,
    String? originName,
    String? destinationName,
    String? transportMode,
    // 'presupuesto' (usar entre 80 % y 100 %) o 'ahorro' (gastar lo menos posible).
    String? budgetStrategy,
    // Qué limita el plan: 'budget' (presupuesto, por defecto) o 'places' (número de lugares).
    String? limitBy,
    int? maxPlaces,
    List<double>? customTasteVector,
    DateTime? travelDate,
    // Plan sorpresa para un mejor amigo mutuo: el motor promedia sus gustos con los tuyos
    // (solo si de verdad son mejores amigos mutuos).
    String? surpriseTargetId,
  }) async {
    final jobId = 'job_${const Uuid().v4()}';
    final nowUtc = DateTime.now().toUtc();

    // 1. Obtener o resolver el taste_vector del usuario
    List<double> tasteVec = customTasteVector ?? [];
    if (tasteVec.isEmpty) {
      try {
        final data = await UserPrivateData.get(userId);
        {
          final rawVec = data['taste_vector'];
          if (rawVec is List && rawVec.isNotEmpty) {
            tasteVec = rawVec.map((e) => (e as num).toDouble()).toList();
          }
        }
      } catch (e) {
        debugPrint('[BlackboardService] Error leyendo taste_vector: $e');
      }
    }

    // Sin perfil completo no se inventa un vector: se envía vacío y el motor resuelve el
    // taste_vector desde /users o vectoriza mood_text con text-embedding-004.
    if (tasteVec.length != 768) {
      tasteVec = <double>[];
    }

    final effectiveOriginName = (originName != null && originName.trim().isNotEmpty)
        ? originName.trim()
        : 'Ciudad de México';

    final payload = {
      'job_id': jobId,
      'user_id': userId,
      'userId': userId,
      'budget': budget,
      'origin': origin,
      'origin_name': effectiveOriginName,
      'destination': destination ?? origin,
      'destination_name': ?destinationName,
      'topology': topology,
      // mood_vector vacío: el motor vectoriza mood_text para representar la intención de la
      // jornada (antes se enviaba el mismo vector de gusto y la fusión 0.65/0.35 no tenía efecto).
      'mood_vector': <double>[],
      'vibe_vector': tasteVec,
      'mood_text': moodText,
      'travel_date': travelDate?.toIso8601String(),
      // Medio de traslado (walking, bike, transit, mixto, taxi, car); sin él el motor usa el
      // del perfil cultural.
      'transport_mode': ?transportMode,
      'budget_strategy': ?budgetStrategy,
      'limit_by': ?limitBy,
      'max_places': ?maxPlaces,
      'surprise_target_id': ?surpriseTargetId,
      'created_at': nowUtc.toIso8601String(),
    };

    // 2. Estado inicial del Pizarrón en Firestore
    final initState = {
      'job_id': jobId,
      'user_id': userId,
      'userId': userId,
      'origin_name': effectiveOriginName,
      'status': 'processing',
      'current_agent': 'comparador',
      'progress_percent': 15,
      'travel_date': travelDate?.toIso8601String(),
      'request': payload,
      'created_at': FieldValue.serverTimestamp(),
      'updated_at': FieldValue.serverTimestamp(),
      'steps': {
        'comparador': {'status': 'running', 'started_at': nowUtc.toIso8601String()},
        'generador': {'status': 'pending'},
        'recomendador': {'status': 'pending'}
      },
      'result': null,
      'error_detail': null
    };

    try {
      await _firestore.collection('itinerary_jobs').doc(jobId).set(initState);
      debugPrint('[BlackboardService] Job registrado exitosamente en Firestore: $jobId');
    } catch (e) {
      debugPrint('[BlackboardService] Error registrando init_state en Firestore: $e');
    }

    // 3. Invocar al backend en Cloud Run / Gateway
    bool callSuccess = false;
    final headers = await _authHeaders(json: true);
    for (final base in [_primaryApiUrl, _secondaryApiUrl]) {
      try {
        // El motor responde 202 en cuanto registra el job (la ejecución corre en el trigger);
        // 12 s cubren el arranque en frío de Cloud Functions.
        final res = await http.post(
          Uri.parse('$base/v1/itinerary'),
          headers: headers,
          body: jsonEncode(payload),
        ).timeout(const Duration(seconds: 12));

        if (res.statusCode == 200 || res.statusCode == 201 || res.statusCode == 202) {
          callSuccess = true;
          break;
        }
      } catch (err) {
        debugPrint('[BlackboardService] Falló intento contra $base: $err');
      }
    }

    // Si ningún endpoint aceptó la solicitud, el job queda en error: el cliente nunca
    // inventa un itinerario. La pantalla muestra el aviso y deja reintentar.
    if (!callSuccess) {
      await markJobUnavailable(jobId);
      throw ItineraryApiUnavailableException(jobId);
    }

    return jobId;
  }

  /// Mensaje que ve el usuario cuando el motor no acepta la solicitud.
  static const String apiUnavailableMessage =
      'No pudimos comunicarnos con el motor de rutas. Revisa tu conexión e intenta de nuevo en un momento.';

  /// Deja el job en error (sin resultado) para que Mis Viajes lo muestre como fallido con
  /// opción de reintentar. Si Firestore tampoco responde, el error solo vive en la pantalla.
  Future<void> markJobUnavailable(String jobId) async {
    try {
      await _firestore.collection('itinerary_jobs').doc(jobId).set({
        'status': 'error',
        'error_code': 'api_unavailable',
        'error_detail': apiUnavailableMessage,
        'current_agent': null,
        'result': null,
        'updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('[BlackboardService] No se pudo marcar el job $jobId en error: $e');
    }
  }

  /// Encabezados con el ID token de Firebase: el motor lo exige (REQUIRE_AUTH=1) en las
  /// rutas de itinerario y solo devuelve trabajos del usuario autenticado.
  Future<Map<String, String>> _authHeaders({bool json = false}) async {
    String? idToken;
    try {
      idToken = await FirebaseAuth.instance.currentUser?.getIdToken();
    } catch (e) {
      debugPrint('[BlackboardService] No se pudo obtener el ID token: $e');
    }
    return {
      if (json) 'Content-Type': 'application/json',
      if (idToken != null) 'Authorization': 'Bearer $idToken',
    };
  }

  /// Escucha en tiempo real el Pizarrón Compartido en Firestore
  Stream<DocumentSnapshot> streamJob(String jobId) {
    return _firestore.collection('itinerary_jobs').doc(jobId).snapshots();
  }

  /// Consulta directa y recuperable de un job tanto en Firestore como en Yollotl Engine
  Future<Map<String, dynamic>?> fetchJobDirect(String jobId) async {
    try {
      final doc = await _firestore.collection('itinerary_jobs').doc(jobId).get();
      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        if (data['status'] == 'completed') return data;
      }
    } catch (e) {
      debugPrint('[BlackboardService] Error leyendo job de Firestore: $e');
    }

    // Consultar a los endpoints REST de Yollotl Engine
    for (final base in [_primaryApiUrl, _secondaryApiUrl]) {
      try {
        final res = await http.get(Uri.parse('$base/v1/itinerary/$jobId'), headers: await _authHeaders()).timeout(const Duration(seconds: 4));
        if (res.statusCode == 200) {
          final data = jsonDecode(res.body) as Map<String, dynamic>;
          // Replicar en Firestore para persistencia local y trazabilidad
          try {
            await _firestore.collection('itinerary_jobs').doc(jobId).set(data, SetOptions(merge: true));
          } catch (_) {}
          return data;
        }
      } catch (err) {
        debugPrint('[BlackboardService] Falló fetchJobDirect contra $base: $err');
      }
    }
    return null;
  }

  /// Sincroniza y recupera todos los jobs del usuario desde el motor de agentes hacia Firestore
  Future<void> syncUserJobsFromBackend(String userId) async {
    for (final base in [_primaryApiUrl, _secondaryApiUrl]) {
      try {
        final res = await http.get(Uri.parse('$base/v1/itinerary/user/$userId'), headers: await _authHeaders()).timeout(const Duration(seconds: 5));
        if (res.statusCode == 200) {
          final body = jsonDecode(res.body) as Map<String, dynamic>;
          final jobs = body['jobs'] as List<dynamic>? ?? [];
          for (final j in jobs) {
            final jobMap = Map<String, dynamic>.from(j as Map);
            final jId = jobMap['job_id']?.toString();
            if (jId != null && jId.isNotEmpty) {
              await _firestore.collection('itinerary_jobs').doc(jId).set(jobMap, SetOptions(merge: true));
            }
          }
          break;
        }
      } catch (err) {
        debugPrint('[BlackboardService] syncUserJobsFromBackend falló contra $base: $err');
      }
    }
  }

  /// Notifica al usuario en la campana de la app si minimizó el modal
  Future<void> notifyIfBackground({
    required String userId,
    required String jobId,
    required String tripTitle,
  }) async {
    try {
      final notifRef = _firestore.collection('users').doc(userId).collection('notifications').doc();
      await notifRef.set({
        'type': 'itinerary_ready',
        'title': '¡Tus 3 multirutas con IA están listas!',
        'message': 'Ohtli diseñó 3 alternativas temáticas para "$tripTitle".',
        'job_id': jobId,
        'status': 'unread',
        'read': false,
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('[BlackboardService] Error enviando notificación background: $e');
    }
  }

  /// Convierte la opción de ruta elegida por el usuario a un [Trip] oficial en Firestore
  Future<Trip> saveOptionAsTrip({
    required String userId,
    required Map<String, dynamic> chosenOption,
    required String defaultTitle,
    DateTime? travelDate,
    String? jobId,
    int? optionIndex,
    String? surpriseTargetId,
    String? surpriseTargetName,
    String? routeShape,
    Map<String, dynamic>? startPoint,
    Map<String, dynamic>? endPoint,
  }) async {
    final tripId = const Uuid().v4();
    final now = DateTime.now();

    final title = (chosenOption['editorial_headline'] ?? chosenOption['theme'] ?? defaultTitle).toString();
    final summary = (chosenOption['narrative_summary'] ?? '').toString();
    final pitch = (chosenOption['pitch'] ?? '').toString().trim();
    final highlights = ((chosenOption['highlights'] as List?) ?? const [])
        .map((e) => e.toString().trim())
        .where((e) => e.isNotEmpty)
        .toList();
    // Descripción del viaje: por qué es para la persona (pitch) o, si no, el resumen.
    final description = pitch.isNotEmpty ? pitch : summary;

    // Extraer paradas
    final List<dynamic> rawStops = chosenOption['route'] ?? [];
    final List<dynamic> rawNarrations = chosenOption['stops_narration'] ?? [];
    // La narración de cada parada se busca por poi_id o por stop_index (no por posición).
    final narrationByPoi = <String, Map>{};
    final narrationByIndex = <int, Map>{};
    for (final n in rawNarrations) {
      if (n is! Map) continue;
      final pid = n['poi_id']?.toString();
      if (pid != null && pid.isNotEmpty) narrationByPoi[pid] = n;
      final idx = (n['stop_index'] as num?)?.toInt();
      if (idx != null) narrationByIndex[idx] = n;
    }

    final List<TripSection> sections = [];

    // Salida: del punto de partida a la primera parada (el motor la cuenta en sus totales).
    final departure = departureLeg(chosenOption, id: 'sec_${const Uuid().v4()}');
    if (departure != null) sections.add(departure);

    for (int i = 0; i < rawStops.length; i++) {
      final stop = rawStops[i] as Map<String, dynamic>;
      final stopName = stop['name'] ?? 'Parada ${i + 1}';
      // Solo la foto del lugar. Sin ella la parada queda sin foto y el visor muestra una de
      // referencia avisada como tal: guardada aquí, pasaba por foto del lugar (el Museo Soumaya
      // en el Museo de Sitio Sor Juana) y hasta salía entre los momentos del viaje.
      final photo = ownStopPhoto(stop);

      // Prellenado con lo que escribió el Recomendador: historia, por qué destaca y consejo.
      // Antes se buscaban campos que el motor no envía (narration/why) y cada parada quedaba con
      // la receta técnica de ejes del embedding.
      final n = narrationByPoi[stop['poi_id']?.toString()] ??
          narrationByIndex[(stop['stop_index'] as num?)?.toInt() ?? i + 1] ??
          const {};
      final story = (n['cultural_story'] ?? '').toString().trim();
      final hl = (n['highlight'] ?? '').toString().trim();
      final tip = (n['curator_tip'] ?? '').toString().trim();
      final parts = <String>[
        if (hl.isNotEmpty) '**$hl**',
        if (story.isNotEmpty) story,
        if (tip.isNotEmpty) '**Consejo:** $tip',
      ];
      String stopDesc = parts.join('\n\n');
      if (stopDesc.isEmpty) {
        final own = (stop['description'] ?? '').toString().trim();
        stopDesc = own.isNotEmpty && !own.startsWith('[EJE') ? own : '';
      }

      double? lat = (stop['lat'] as num?)?.toDouble();
      double? lng = (stop['lng'] as num?)?.toDouble();
      if (lat == null && stop['location'] is Map) {
        lat = (stop['location']['lat'] as num?)?.toDouble();
        lng = (stop['location']['lng'] as num?)?.toDouble();
      }
      final arrivalTime = stop['arrival_time']?.toString();
      final departureTime = stop['departure_time']?.toString();

      // Traslado desde la parada anterior, tal como lo calculó el motor (OSRM).
      if (i > 0) {
        final mins = (stop['travel_time_from_prev_mins'] as num?)?.toInt();
        final km = (stop['travel_distance_from_prev_km'] as num?)?.toDouble();
        if (mins != null || km != null) {
          sections.add(TransferSection(
            id: 'sec_${const Uuid().v4()}',
            mode: normalizeTransferMode(
                (stop['transport_mode'] ?? chosenOption['transport_mode'])?.toString()),
            durationMins: mins,
            distanceKm: km,
            cost: (stop['transport_cost_mxn'] as num?)?.toDouble() ?? 0.0,
            isEstimated: true,
          ));
        }
      }

      sections.add(
        PlaceSection(
          id: 'sec_${const Uuid().v4()}',
          title: stopName,
          description: stopDesc,
          // Sin calificar hasta que la persona visite el lugar (0, como en los planes manuales):
          // las 5 estrellas prellenadas contaban como "me gustó" en la retroalimentación.
          rating: 0,
          mainPhotoUrl: photo.toString(),
          secondaryPhotoUrls: [],
          cost: (stop['price_mxn'] as num?)?.toDouble() ?? 0.0,
          currency: 'MXN',
          lat: lat,
          lng: lng,
          arrivalTime: arrivalTime,
          departureTime: departureTime,
          // Vínculo con el lugar de la base que eligió el motor
          poiId: (stop['poi_id'] ?? stop['poiId'])?.toString(),
          poiSource: (stop['poi_id'] ?? stop['poiId']) != null ? kPlaceSourceCatalog : null,
        ),
      );
    }

    // Último tramo: regreso al punto de partida (ida y vuelta) o llegada al punto final.
    final finalLeg = chosenOption['final_leg'];
    if (finalLeg is Map && rawStops.isNotEmpty && ((finalLeg['km'] as num?)?.toDouble() ?? 0) > 0.05) {
      sections.add(TransferSection(
        id: 'sec_${const Uuid().v4()}',
        mode: normalizeTransferMode(finalLeg['transport_mode']?.toString()),
        durationMins: (finalLeg['mins'] as num?)?.toInt(),
        distanceKm: (finalLeg['km'] as num?)?.toDouble(),
        cost: (finalLeg['transport_cost_mxn'] as num?)?.toDouble() ?? 0.0,
        notes: finalLeg['to'] == 'origin' ? 'Regreso al punto de partida' : 'Llegada al punto final',
        isEstimated: true,
      ));
    }

    // Introducción del viaje: el resumen del Recomendador y sus puntos fuertes, listos para
    // publicarse sin reescribirlos.
    // Por qué la ruta va en ese orden (Recomendador), para que no parezca que da vueltas.
    final rationale = (chosenOption['route_rationale'] ?? '').toString().trim();
    final intro = <String>[
      if (summary.isNotEmpty) summary,
      if (highlights.isNotEmpty) highlights.map((h) => '- $h').join('\n'),
      if (rationale.isNotEmpty) '**El orden del recorrido:** $rationale',
    ].join('\n\n');
    if (intro.isNotEmpty) {
      sections.insert(
        0,
        TextSection(
          id: 'sec_${const Uuid().v4()}',
          markdownText: intro,
        ),
      );
    }
    // La misma portada que mostró el planificador: foto propia de una parada o postal de la zona.
    final coverUrl = optionCover(chosenOption, seed: optionCoverSeed(chosenOption));

    // Qué propuso el motor (retroalimentación: el editor compara contra esto)
    final recommended = FeedbackService.stopIds(chosenOption);

    final newTrip = Trip(
      id: tripId,
      userId: userId,
      title: title,
      description: description,
      coverUrl: coverUrl,
      status: 'draft',
      visibility: 'private',
      createdAt: now,
      updatedAt: now,
      travelDate: travelDate ?? now,
      isSurprise: surpriseTargetId != null,
      surpriseTargetIds: surpriseTargetId != null ? [surpriseTargetId] : const [],
      surpriseTargetNames: surpriseTargetId != null ? [surpriseTargetName ?? 'Viajero Ohtli'] : const [],
      unlockOnPublish: surpriseTargetId != null,
      routeShape: routeShape,
      startPoint: startPoint,
      endPoint: endPoint,
      // En memoria también (el editor abre este objeto): así sabe que salió de la IA.
      recommendedPoiIds: recommended,
      recommendationJobId: recommended.isNotEmpty ? jobId : null,
    );

    // 1. Crear documento principal del viaje
    await _tripService.createTrip(userId, newTrip);

    // 2. Guardar las paradas en su subcolección de contenido
    await _tripService.updateTripContent(
      userId,
      tripId,
      TripContent(sections: sections),
    );

    // 3. Qué propuso el motor (se guarda aparte: Trip.toMap no lo escribe)
    if (recommended.isNotEmpty) {
      try {
        await FirebaseFirestore.instance.collection('users').doc(userId).collection('trips').doc(tripId).set({
          'recommendation': {
            'poi_ids': recommended,
            if (jobId != null) 'job_id': jobId,
            if (optionIndex != null) 'option_index': optionIndex,
          },
        }, SetOptions(merge: true));
      } catch (e) {
        debugPrint('[Blackboard] no se guardó la recomendación del viaje: $e');
      }
    }
    FeedbackService.itineraryChosen(jobId, optionIndex, chosenOption, tripId: tripId);

    return newTrip;
  }
}

/// El motor no aceptó la solicitud (sin red, caído o sin respuesta en 12 s). El job ya
/// quedó marcado en error en Firestore.
class ItineraryApiUnavailableException implements Exception {
  final String jobId;
  const ItineraryApiUnavailableException(this.jobId);

  @override
  String toString() => ItineraryBlackboardService.apiUnavailableMessage;
}

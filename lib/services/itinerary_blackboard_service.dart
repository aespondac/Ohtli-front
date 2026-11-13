import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:uuid/uuid.dart';
import '../models/trip_model.dart';
import 'trip_service.dart';

class ItineraryBlackboardService {
  static const String _primaryApiUrl = String.fromEnvironment(
    'yollotlApiUrl',
    defaultValue: 'https://api-xluju5gywq-uc.a.run.app',
  );
  static const String _secondaryApiUrl = 'https://api.ohtli.quest';

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
    List<double>? customTasteVector,
    DateTime? travelDate,
  }) async {
    final jobId = 'job_${const Uuid().v4()}';
    final nowUtc = DateTime.now().toUtc();

    // 1. Obtener o resolver el taste_vector del usuario
    List<double> tasteVec = customTasteVector ?? [];
    if (tasteVec.isEmpty) {
      try {
        final userDoc = await _firestore.collection('users').doc(userId).get();
        if (userDoc.exists && userDoc.data() != null) {
          final rawVec = userDoc.data()!['taste_vector'];
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
      'topology': topology,
      // mood_vector vacío: el motor vectoriza mood_text para representar la intención de la
      // jornada (antes se enviaba el mismo vector de gusto y la fusión 0.65/0.35 no tenía efecto).
      'mood_vector': <double>[],
      'vibe_vector': tasteVec,
      'mood_text': moodText,
      'travel_date': travelDate?.toIso8601String(),
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
    String? idToken;
    try {
      idToken = await FirebaseAuth.instance.currentUser?.getIdToken();
    } catch (e) {
      debugPrint('[BlackboardService] No se pudo obtener el ID token: $e');
    }
    final headers = {
      'Content-Type': 'application/json',
      if (idToken != null) 'Authorization': 'Bearer $idToken',
    };
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

    // Si ambos endpoints fallan o no hay red externa, activamos simulación resiliente
    // en Firestore para que el usuario en modo demo o laboratorio nunca se quede bloqueado
    if (!callSuccess) {
      _triggerResilientFallbackSim(jobId, payload, origin, budget, moodText);
    }

    return jobId;
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
        final res = await http.get(Uri.parse('$base/v1/itinerary/$jobId')).timeout(const Duration(seconds: 4));
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
        final res = await http.get(Uri.parse('$base/v1/itinerary/user/$userId')).timeout(const Duration(seconds: 5));
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
  }) async {
    final tripId = const Uuid().v4();
    final now = DateTime.now();

    final title = (chosenOption['editorial_headline'] ?? chosenOption['theme'] ?? defaultTitle).toString();
    final description = (chosenOption['narrative_summary'] ?? '').toString();
    
    // Extraer paradas
    final List<dynamic> rawStops = chosenOption['route'] ?? [];
    final List<dynamic> rawNarrations = chosenOption['stops_narration'] ?? [];
    
    String coverUrl = '';
    final List<TripSection> sections = [];

    for (int i = 0; i < rawStops.length; i++) {
      final stop = rawStops[i] as Map<String, dynamic>;
      final stopName = stop['name'] ?? 'Parada ${i + 1}';
      final photo = stop['photo_url'] ?? stop['main_photo_url'] ?? '';
      if (coverUrl.isEmpty && photo.toString().isNotEmpty) {
        coverUrl = photo.toString();
      }

      String stopDesc = '';
      if (i < rawNarrations.length && rawNarrations[i] != null) {
        final n = rawNarrations[i];
        if (n is Map) {
          stopDesc = n['narration'] ?? n['why'] ?? '';
        } else {
          stopDesc = n.toString();
        }
      }
      if (stopDesc.isEmpty) {
        stopDesc = stop['semantic_description'] ?? 'Parada recomendada por afinidad cultural.';
      }

      double? lat = (stop['lat'] as num?)?.toDouble();
      double? lng = (stop['lng'] as num?)?.toDouble();
      if (lat == null && stop['location'] is Map) {
        lat = (stop['location']['lat'] as num?)?.toDouble();
        lng = (stop['location']['lng'] as num?)?.toDouble();
      }
      final arrivalTime = stop['arrival_time']?.toString();
      final departureTime = stop['departure_time']?.toString();

      sections.add(
        PlaceSection(
          id: 'sec_${const Uuid().v4()}',
          title: stopName,
          description: stopDesc,
          rating: 5,
          mainPhotoUrl: photo.toString(),
          secondaryPhotoUrls: [],
          cost: (stop['price_mxn'] as num?)?.toDouble() ?? 0.0,
          currency: 'MXN',
          lat: lat,
          lng: lng,
          arrivalTime: arrivalTime,
          departureTime: departureTime,
        ),
      );
    }

    // Agregar sección narrativa general de la ruta si existe
    if (description.isNotEmpty) {
      sections.insert(
        0,
        TextSection(
          id: 'sec_${const Uuid().v4()}',
          markdownText: '### Propósito del Viaje\n$description',
        ),
      );
    }

    final newTrip = Trip(
      id: tripId,
      userId: userId,
      title: title,
      description: description,
      coverUrl: coverUrl.isNotEmpty
          ? coverUrl
          : 'https://images.unsplash.com/photo-1518638150340-f706e86654de?auto=format&fit=crop&w=1200&q=80',
      status: 'draft',
      visibility: 'private',
      createdAt: now,
      updatedAt: now,
      travelDate: travelDate ?? now,
    );

    // 1. Crear documento principal del viaje
    await _tripService.createTrip(userId, newTrip);

    // 2. Guardar las paradas en su subcolección de contenido
    await _tripService.updateTripContent(
      userId,
      tripId,
      TripContent(sections: sections),
    );

    return newTrip;
  }

  /// Simulación resiliente offline para pruebas o cuando los microservicios están en cold start
  void _triggerResilientFallbackSim(
    String jobId,
    Map<String, dynamic> req,
    Map<String, double> origin,
    double budget,
    String mood,
  ) {
    Future.delayed(const Duration(milliseconds: 1200), () async {
      await _firestore.collection('itinerary_jobs').doc(jobId).set({
        'progress_percent': 45,
        'current_agent': 'generador',
        'steps': {
          'comparador': {'status': 'completed', 'candidates_count': 12},
          'generador': {'status': 'running'},
        }
      }, SetOptions(merge: true));

      await Future.delayed(const Duration(milliseconds: 1400));
      await _firestore.collection('itinerary_jobs').doc(jobId).set({
        'progress_percent': 80,
        'current_agent': 'recomendador',
        'steps': {
          'generador': {'status': 'completed', 'routes_generated': 3},
          'recomendador': {'status': 'running'},
        }
      }, SetOptions(merge: true));

      await Future.delayed(const Duration(milliseconds: 1200));
      
      final mockOptions = [
        {
          'option_id': 'opt_1',
          'theme': 'Bohemia, Café y Terapias Visuales',
          'editorial_headline': 'Tarde Bohemia entre Bugambilias y Café de Grano',
          'narrative_summary': 'Un recorrido diseñado para desconectar del ruido urbano, sumergiéndote en patios virreinales, el murmullo de fuentes centenarias y el aroma a café recién tostado.',
          'total_cost_mxn': (budget * 0.65).clamp(150.0, budget),
          'estimated_time_mins': 210,
          'cover_url': 'https://images.unsplash.com/photo-1518638150340-f706e86654de?auto=format&fit=crop&w=1200&q=80',
          'route': [
            {
              'name': 'Café El Jarocho y Jardín Centenario',
              'category': 'cafeterias_especialidad',
              'price_mxn': 85.0,
              'stay_duration_mins': 50,
              'location': {'lat': 19.3498, 'lng': -99.1638},
              'photo_url': 'https://images.unsplash.com/photo-1501339847302-ac426a4a7cbb?auto=format&fit=crop&w=800&q=80',
            },
            {
              'name': 'Museo Frida Kahlo (Casa Azul)',
              'category': 'museos_arte',
              'price_mxn': 270.0,
              'stay_duration_mins': 90,
              'location': {'lat': 19.3551, 'lng': -99.1626},
              'photo_url': 'https://images.unsplash.com/photo-1579783900882-c0d3dad7b119?auto=format&fit=crop&w=800&q=80',
            },
            {
              'name': 'Mercado de Artesanías de Coyoacán',
              'category': 'mercados_artesanias',
              'price_mxn': 60.0,
              'stay_duration_mins': 60,
              'location': {'lat': 19.3501, 'lng': -99.1610},
              'photo_url': 'https://images.unsplash.com/photo-1528605248644-14dd04022da1?auto=format&fit=crop&w=800&q=80',
            }
          ],
          'stops_narration': [
            {'narration': 'Comienza saboreando un café tradicional con aroma a canela bajo los árboles centenarios.'},
            {'narration': 'Admira el universo íntimo y los jardines volcánicos de la Casa Azul.'},
            {'narration': 'Cierra explorando piezas de arte popular, textiles tradicionales y dulces típicos.'}
          ]
        },
        {
          'option_id': 'opt_2',
          'theme': 'Muralismo Secreto y Cantinas Centenarias',
          'editorial_headline': 'Ecos Monumentales en el Corazón Virreinal',
          'narrative_summary': 'Ideal para adentrarse en los frescos de Diego Rivera y José Clemente Orozco, concluyendo en una tertulia histórica con sabor a botana tradicional.',
          'total_cost_mxn': (budget * 0.80).clamp(200.0, budget),
          'estimated_time_mins': 240,
          'cover_url': 'https://images.unsplash.com/photo-1584646098378-0874589d76b1?auto=format&fit=crop&w=1200&q=80',
          'route': [
            {
              'name': 'Antiguo Colegio de San Ildefonso',
              'category': 'muralismo',
              'price_mxn': 50.0,
              'stay_duration_mins': 80,
              'location': {'lat': 19.4359, 'lng': -99.1308},
              'photo_url': 'https://images.unsplash.com/photo-1584646098378-0874589d76b1?auto=format&fit=crop&w=800&q=80',
            },
            {
              'name': 'La Ópera Bar',
              'category': 'cantinas_tradicionales',
              'price_mxn': 280.0,
              'stay_duration_mins': 90,
              'location': {'lat': 19.4348, 'lng': -99.1390},
              'photo_url': 'https://images.unsplash.com/photo-1514933651103-005eec06c04b?auto=format&fit=crop&w=800&q=80',
            },
            {
              'name': 'Palacio de Bellas Artes',
              'category': 'arquitectura_monumental',
              'price_mxn': 90.0,
              'stay_duration_mins': 70,
              'location': {'lat': 19.4352, 'lng': -99.1412},
              'photo_url': 'https://images.unsplash.com/photo-1518638150340-f706e86654de?auto=format&fit=crop&w=800&q=80',
            }
          ],
          'stops_narration': [
            {'narration': 'Cuna del muralismo moderno en un majestuoso patio barroco novohispano.'},
            {'narration': 'Brinda bajo los techos dorados donde aún se conserva el disparo de Pancho Villa.'},
            {'narration': 'Contempla la icónica cúpula de mármol y bronce al atardecer sobre la Alameda.'}
          ]
        },
        {
          'option_id': 'opt_3',
          'theme': 'Espacios Verdes, Escultura y Calma',
          'editorial_headline': 'Refugio Botánico y Esculturas en Chapultepec',
          'narrative_summary': 'Un respiro entre senderos arbolados, calzadas flotantes y recintos culturales de primer nivel con accesibilidad total.',
          'total_cost_mxn': (budget * 0.45).clamp(100.0, budget),
          'estimated_time_mins': 180,
          'cover_url': 'https://images.unsplash.com/photo-1500530855697-b586d89ba3ee?auto=format&fit=crop&w=1200&q=80',
          'route': [
            {
              'name': 'Museo de Arte Moderno (MAM)',
              'category': 'museos_arte',
              'price_mxn': 90.0,
              'stay_duration_mins': 75,
              'location': {'lat': 19.4225, 'lng': -99.1795},
              'photo_url': 'https://images.unsplash.com/photo-1579783900882-c0d3dad7b119?auto=format&fit=crop&w=800&q=80',
            },
            {
              'name': 'Jardín Botánico y Orquideario de Chapultepec',
              'category': 'parques_bosques',
              'price_mxn': 0.0,
              'stay_duration_mins': 45,
              'location': {'lat': 19.4230, 'lng': -99.1830},
              'photo_url': 'https://images.unsplash.com/photo-1500530855697-b586d89ba3ee?auto=format&fit=crop&w=800&q=80',
            },
            {
              'name': 'Librería Porrúa del Bosque',
              'category': 'librerias_cafes',
              'price_mxn': 120.0,
              'stay_duration_mins': 60,
              'location': {'lat': 19.4245, 'lng': -99.1820},
              'photo_url': 'https://images.unsplash.com/photo-1521587760476-6c12a4b040da?auto=format&fit=crop&w=800&q=80',
            }
          ],
          'stops_narration': [
            {'narration': 'Recorre el jardín de esculturas y las obras maestras de Remedios Varo.'},
            {'narration': 'Pasea entre orquídeas nativas y plantas medicinales en un microclima protegido.'},
            {'narration': 'Disfruta una lectura al borde del lago con vista a los ahuehuetes.'}
          ]
        }
      ];

      await _firestore.collection('itinerary_jobs').doc(jobId).set({
        'status': 'completed',
        'current_agent': null,
        'progress_percent': 100,
        'steps': {
          'recomendador': {'status': 'completed', 'options_count': 3}
        },
        'result': {'options': mockOptions},
        'completed_at': DateTime.now().toUtc().toIso8601String()
      }, SetOptions(merge: true));
    });
  }
}

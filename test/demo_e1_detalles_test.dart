// Detalles que salieron al grabar la demo E1 (24-nov-2026): Zócalo, ida y vuelta a pie, $500,
// "Arte novohispano y museos virreinales". Ver option_trip.dart y CdmxPhotos.
import 'package:flutter_test/flutter_test.dart';
import 'package:othli_front/models/poi_model.dart';
import 'package:othli_front/models/profile_moment.dart';
import 'package:othli_front/models/trip_model.dart';
import 'package:othli_front/services/option_trip.dart';
import 'package:othli_front/services/trip_transfers.dart';
import 'package:othli_front/theme/cdmx_photos.dart';
import 'package:othli_front/widgets/photo_credit.dart';

const _own = 'https://firebasestorage.googleapis.com/v0/b/x/o/sor_juana.jpg?alt=media';

/// Parada como la manda el motor (Generador + Recomendador).
Map<String, dynamic> _stop(String name, String category, double lat, double lng,
        {String arrival = '10:13', String departure = '11:13', int mins = 0, double km = 0, String photo = ''}) =>
    {
      'poi_id': name,
      'name': name,
      'category': category,
      'location': {'lat': lat, 'lng': lng},
      'arrival_time': arrival,
      'departure_time': departure,
      'travel_time_from_prev_mins': mins,
      'travel_distance_from_prev_km': km,
      'transport_mode': 'walking',
      'photo_url': photo,
    };

/// La alternativa de la demo: salida del Zócalo y regreso a él.
Map<String, dynamic> _demoOption({String firstPhoto = ''}) => {
      'editorial_headline': 'De Museo de Sitio Sor Juana a Casa de Leona Vicario',
      'transport_mode': 'walking',
      'total_duration_mins': 327,
      'total_walking_km': 4.1,
      'route': [
        _stop('Museo de Sitio Sor Juana Inés de la Cruz', 'museum', 19.42765, -99.13807,
            arrival: '10:13', departure: '11:28', mins: 13, km: 0.9, photo: firstPhoto),
        _stop('Casa de Leona Vicario', 'museum', 19.4383488, -99.1332193, arrival: '14:40', departure: '15:16', mins: 20, km: 2.6),
      ],
      'final_leg': {'mins': 11, 'km': 0.6, 'transport_mode': 'walking', 'to': 'origin'},
    };

void main() {
  final soumaya = CdmxPhotos.byCategory['museum']!.first;
  final casaAzul = CdmxPhotos.byCategory['museum']![1];

  group('fotos de referencia', () {
    test('se reconocen en cualquier tamaño (el motor las guarda a 1280 px)', () {
      expect(CdmxPhotos.isReference(soumaya), isTrue);
      expect(CdmxPhotos.isReference(soumaya.replaceFirst('/500px-', '/1280px-')), isTrue);
      expect(CdmxPhotos.isReference(CdmxPhotos.sized(soumaya, 44, 2)), isTrue);
      expect(CdmxPhotos.isReference(_own), isFalse);
      expect(CdmxPhotos.isReference(''), isFalse);
      expect(CdmxPhotos.isReference(null), isFalse);
    });

    test('todas las del catálogo de fotos se reconocen', () {
      for (final u in [...CdmxPhotos.covers, for (final l in CdmxPhotos.byCategory.values) ...l]) {
        expect(CdmxPhotos.isReference(u), isTrue, reason: u);
      }
    });

    test('las de categoría no son postal de portada; las postales sí sirven de portada', () {
      expect(CdmxPhotos.isCategoryReference(casaAzul), isTrue);
      expect(CdmxPhotos.isCategoryReference(soumaya), isTrue);
      for (final c in CdmxPhotos.covers) {
        expect(CdmxPhotos.isCategoryReference(c), isFalse, reason: c);
      }
    });

    test('portada de un viaje guardado antes con la Casa Azul: se muestra una postal', () {
      expect(CdmxPhotos.covers, contains(CdmxPhotos.tripCover(casaAzul, 3)));
      expect(CdmxPhotos.tripCover(_own, 3), _own);
      expect(CdmxPhotos.covers, contains(CdmxPhotos.tripCover('', 3)));
    });

    test('la postal de la zona: un recorrido por el Centro no sale con Xochimilco ni Chapultepec', () {
      final centro = {for (var s = 0; s < 40; s++) CdmxPhotos.coverNear(19.433, -99.136, s)};
      bool isCentro(String u) {
        final l = u.toLowerCase();
        return l.contains('bellas_artes') || l.contains('catedral') || l.contains('azulejos');
      }

      expect(centro.every(isCentro), isTrue,
          reason: centro.join('\n'));
      expect(CdmxPhotos.coverNear(19.26, -99.10), contains('Xochimilco'));
    });
  });

  group('foto de cada parada', () {
    test('la parada del motor sin foto propia no hereda una de referencia', () {
      expect(ownStopPhoto({'photo_url': ''}), '');
      expect(ownStopPhoto({'photo_url': soumaya}), '', reason: 'una referencia no es foto del lugar');
      expect(ownStopPhoto({'photo_url': _own}), _own);
      expect(ownStopPhoto({'image_url': _own}), _own);
    });

    test('ownMainPhotoUrl ignora la foto de referencia de los viajes guardados antes', () {
      PlaceSection place(String main) =>
          PlaceSection(id: 'p', title: 'Museo de Sitio Sor Juana', description: '', rating: 0, mainPhotoUrl: main, secondaryPhotoUrls: const []);
      expect(place(soumaya.replaceFirst('/500px-', '/1280px-')).ownMainPhotoUrl, '');
      expect(place(_own).ownMainPhotoUrl, _own);
    });

    test('los momentos del viaje no ofrecen la foto de otro lugar', () {
      final trip = Trip.fromMap({'title': 'Centro', 'coverUrl': '', 'userId': 'u'}, 't');
      final content = TripContent(sections: [
        PlaceSection(id: 'p1', title: 'Museo de Sitio Sor Juana', description: '', rating: 0, mainPhotoUrl: soumaya, secondaryPhotoUrls: const []),
        PlaceSection(id: 'p2', title: 'Casa de Leona Vicario', description: '', rating: 0, mainPhotoUrl: _own, secondaryPhotoUrls: const []),
      ]);
      expect(momentCandidates(trip, content).map((m) => m.url), [_own]);
    });
  });

  group('portada de la alternativa y del viaje guardado', () {
    test('sin fotos propias: postal del Centro, no la Casa Azul ni el Soumaya', () {
      final o = _demoOption();
      final cover = optionCover(o, seed: optionCoverSeed(o));
      expect(CdmxPhotos.isCategoryReference(cover), isFalse);
      expect(CdmxPhotos.covers, contains(cover));
      expect(cover.contains('Xochimilco') || cover.contains('Chapultepec'), isFalse, reason: cover);
    });

    test('con foto propia en una parada, esa es la portada', () {
      expect(optionCover(_demoOption(firstPhoto: _own)), _own);
    });

    test('planificador y viaje guardado eligen la misma (misma semilla)', () {
      final o = _demoOption();
      expect(optionCover(o, seed: optionCoverSeed(o)), optionCover(Map.of(o), seed: optionCoverSeed(Map.of(o))));
    });
  });

  group('duración y distancia: propuesta = viaje guardado', () {
    test('el tramo de salida del Zócalo se guarda con sus minutos y kilómetros', () {
      final leg = departureLeg(_demoOption(), id: 't0')!;
      expect(leg.durationMins, 13);
      expect(leg.distanceKm, 0.9);
      expect(leg.mode, 'walking');
      expect(leg.notes, 'Salida desde el punto de partida');
    });

    test('sin punto de partida (la ruta empieza en la primera parada) no hay tramo de salida', () {
      final o = _demoOption();
      (o['route'] as List).first['travel_time_from_prev_mins'] = 0;
      (o['route'] as List).first['travel_distance_from_prev_km'] = 0.0;
      expect(departureLeg(o, id: 't0'), isNull);
    });

    test('jornada y km del viaje guardado coinciden con los de la propuesta', () {
      // Como queda tras saveOptionAsTrip: salida, parada, traslado, parada, regreso.
      final sections = <TripSection>[
        TextSection(id: 'intro', markdownText: 'Resumen'),
        departureLeg(_demoOption(), id: 't0')!,
        PlaceSection(id: 'p1', title: 'Sor Juana', description: '', rating: 0, mainPhotoUrl: '', secondaryPhotoUrls: const [],
            arrivalTime: '10:13', departureTime: '11:28'),
        TransferSection(id: 't1', durationMins: 20, distanceKm: 2.6),
        PlaceSection(id: 'p2', title: 'Leona Vicario', description: '', rating: 0, mainPhotoUrl: '', secondaryPhotoUrls: const [],
            arrivalTime: '14:40', departureTime: '15:16'),
        TransferSection(id: 't2', durationMins: 11, distanceKm: 0.6, notes: 'Regreso al punto de partida'),
      ];
      final span = tripTimeSpan(sections)!;
      expect(formatClock(span.start), '10:00');
      expect(formatClock(span.end), '15:27');
      expect(span.end - span.start, 327, reason: 'lo que decía la propuesta: 5 h 27 min');
      expect(formatDuration(span.end - span.start), '5 h 27 min');
      expect(tripTransfersKm(sections), closeTo(4.1, 1e-9));
    });

    test('sin traslados de ida y vuelta, la jornada es de la primera llegada a la última salida', () {
      final sections = <TripSection>[
        PlaceSection(id: 'p1', title: 'A', description: '', rating: 0, mainPhotoUrl: '', secondaryPhotoUrls: const [],
            arrivalTime: '10:00', departureTime: '11:00'),
        TransferSection(id: 't1', durationMins: 15),
        PlaceSection(id: 'p2', title: 'B', description: '', rating: 0, mainPhotoUrl: '', secondaryPhotoUrls: const [],
            arrivalTime: '11:15', departureTime: '12:00'),
      ];
      final span = tripTimeSpan(sections)!;
      expect((span.start, span.end), (600, 720));
      expect(tripTimeSpan([TextSection(id: 'x', markdownText: '')]), isNull);
    });
  });

  group('categoría en español', () {
    test('las claves crudas del motor salen como en la ficha del lugar', () {
      expect(Poi.categoryLabel('MUSEUM'), 'Museo');
      expect(Poi.categoryLabel('ARTS_CENTRE'), 'Centro de las Artes');
      expect(Poi.categoryLabel('place_of_worship'), 'Templo / Iglesia');
      expect(Poi.categoryLabel('bakery;pastry'), 'Panadería');
      expect(Poi.categoryLabel('fast_food; drive-through'), 'Comida Rápida');
      expect(Poi.categoryLabel(null), 'Punto de Interés');
    });

    test('ninguna categoría del catálogo (snapshot del 23-nov) queda en inglés', () {
      const catalog = [
        'restaurant', 'cafe', 'park', 'fast_food', 'artwork', 'marketplace', 'community_centre', 'books', 'bakery', 'bar',
        'place_of_worship', 'museum', 'gallery', 'theatre', 'arts_centre', 'garden', 'monument', 'library', 'ice_cream',
        'attraction', 'cantina', 'pastry', 'pub', 'pulqueria', 'nature_reserve', 'cinema', 'nightclub', 'arqueologia',
        'viewpoint', 'coffee', 'zoo', 'historic', 'art', 'food_court', 'theme_park', 'water_park', 'aquarium',
        'music_venue', 'biergarten', 'public_building', 'resort', 'confectionery',
      ];
      // El respaldo pone en mayúscula la clave en inglés ("Place Of Worship"): no debe usarse.
      String fallback(String c) => c.split(RegExp(r'[_\-\s]+')).map((w) => '${w[0].toUpperCase()}${w.substring(1)}').join(' ');
      const sameInSpanish = {'cantina'};
      for (final c in catalog) {
        final label = Poi.categoryLabel(c);
        if (sameInSpanish.contains(c)) continue;
        expect(label, isNot(fallback(c)), reason: '$c → $label');
      }
    });
  });

  // Regrabación del 24-nov: "Madero y el pulso histórico del Centro" (aventura). El motor salía a
  // las 09:30 (inicio del tema) y esperaba 24 min a que "abriera" Calle Madero (10:00).
  group('regrabación: duración de la propuesta = viaje guardado', () {
    Map<String, dynamic> aventura() => {
          'total_duration_mins': 455, // lo que decía el motor: 09:30–17:05
          'start_time': '09:30',
          'end_time': '17:05',
          'route': [
            _stop('Calle Madero', 'attraction', 19.4334, -99.1358, arrival: '10:00', departure: '11:00', mins: 6, km: 0.386),
            _stop('Casa de los Azulejos', 'museum', 19.4342, -99.1403, arrival: '11:07', departure: '12:07', mins: 7, km: 0.5),
            _stop('Comida callejera mexicana', 'restaurant', 19.4307, -99.1268, arrival: '15:55', departure: '16:55', mins: 15, km: 1.107),
          ],
          'final_leg': {'mins': '10', 'km': 0.735, 'transport_mode': 'walking', 'to': 'origin'},
        };

    test('la tarjeta cuenta desde la salida real (09:54), no desde la hora del tema', () {
      final span = optionTimeSpan(aventura())!;
      expect(formatClock(span.start), '09:54');
      expect(formatClock(span.end), '17:05');
      expect(formatDuration(span.end - span.start), '7 h 11 min');
    });

    test('y coincide con lo que muestra el viaje guardado', () {
      final o = aventura();
      final route = o['route'] as List;
      final sections = <TripSection>[
        departureLeg(o, id: 't0')!,
        for (final (i, s) in route.indexed) ...[
          if (i > 0) TransferSection(id: 't$i', durationMins: s['travel_time_from_prev_mins'] as int),
          PlaceSection(id: 'p$i', title: s['name'] as String, description: '', rating: 0, mainPhotoUrl: '',
              secondaryPhotoUrls: const [], arrivalTime: s['arrival_time'] as String, departureTime: s['departure_time'] as String),
        ],
        TransferSection(id: 'tf', durationMins: 10, notes: 'Regreso al punto de partida'),
      ];
      final saved = tripTimeSpan(sections)!;
      final proposal = optionTimeSpan(o)!;
      expect((saved.start, saved.end), (proposal.start, proposal.end));
    });

    test('sin horarios no hay jornada', () {
      expect(optionTimeSpan({'route': []}), isNull);
      expect(optionTimeSpan({'route': [{'name': 'x'}]}), isNull);
    });
  });

  group('regrabación: fotos del propio lugar con crédito', () {
    const credit = 'Foto: Jane Doe · CC BY-SA 4.0 · Wikimedia Commons';
    const commons = 'https://upload.wikimedia.org/wikipedia/commons/thumb/a/ab/Hemiciclo_a_Juarez.jpg/1280px-Hemiciclo_a_Juarez.jpg';

    test('la ficha del lugar trae el crédito de su foto', () {
      final poi = Poi.fromMap({'poi_id': 'osm_992941278', 'name': 'Hemiciclo a Juárez', 'category': 'attraction',
        'location': {'lat': 19.435, 'lng': -99.144}, 'photo_url': commons, 'photo_credit': credit});
      expect(poi.hasOwnPhoto, isTrue);
      expect(poi.photoCredit, credit);
      expect(Poi.fromMap({'poi_id': 'x', 'name': 'Calle Madero', 'location': {'lat': 19.43, 'lng': -99.13}}).photoCredit, '');
    });

    test('el crédito corto cabe en la miniatura', () {
      expect(PhotoCredit.short(credit), 'Jane Doe · CC BY-SA 4.0');
    });

    test('la parada guardada conserva el crédito, y lo pierde si cambia la foto', () {
      final p = PlaceSection(id: 'p', title: 'Hemiciclo a Juárez', description: '', rating: 0, mainPhotoUrl: commons,
          secondaryPhotoUrls: const [], mainPhotoCredit: credit);
      final back = PlaceSection.fromMap(p.toMap());
      expect(back.mainPhotoCredit, credit);
      expect(p.copyWith(title: 'Hemiciclo').mainPhotoCredit, credit);
      expect(p.copyWith(mainPhotoUrl: _own).mainPhotoCredit, isNull);
      expect(PlaceSection.fromMap({'id': 'q', 'title': 'Sin foto'}).mainPhotoCredit, isNull);
    });

    test('una foto de Commons del propio lugar no se toma por foto de referencia', () {
      expect(CdmxPhotos.isReference(commons), isFalse);
      expect(ownStopPhoto({'photo_url': commons, 'photo_credit': credit}), commons);
    });
  });
}

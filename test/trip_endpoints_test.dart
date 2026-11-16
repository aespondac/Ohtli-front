import 'package:flutter_test/flutter_test.dart';
import 'package:othli_front/models/trip_model.dart';
import 'package:othli_front/services/manual_plan.dart';
import 'package:othli_front/services/trip_endpoints.dart';

PlaceSection place(String id, String title, double? lat, double? lng, {bool unplanned = false}) => PlaceSection(
      id: id,
      title: title,
      description: '',
      rating: 0,
      mainPhotoUrl: '',
      secondaryPhotoUrls: const [],
      lat: lat,
      lng: lng,
      unplanned: unplanned,
    );

void main() {
  const zocalo = {'lat': 19.4326, 'lng': -99.1332};
  const coyoacan = {'lat': 19.3497, 'lng': -99.1622};
  final bellas = place('b', 'Bellas Artes', 19.4352, -99.1412);
  final museo = place('m', 'Museo Frida Kahlo', 19.3551, -99.1626);

  test('sin inicio ni fin guardados: primera y última parada con ubicación', () {
    final e = routeEndpointsOf(sections: [place('x', 'Sin lugar', null, null), bellas, museo, place('d', 'Desvío', 19.4, -99.1, unplanned: true)]);
    expect(e.start!.sectionId, 'b');
    expect(e.end!.sectionId, 'm');
    expect(e.start!.derived, isTrue);
    expect(e.roundTrip, isFalse);
    expect(e.labelFor('b'), 'Inicio');
    expect(e.labelFor('m'), 'Fin');
  });

  test('una sola parada es inicio y fin', () {
    final e = routeEndpointsOf(sections: [bellas]);
    expect(e.labelFor('b'), 'Inicio y fin');
    expect(e.roundTrip, isTrue);
  });

  test('inicio y fin guardados aparte de las paradas', () {
    final e = routeEndpointsOf(
      startPoint: {'name': 'Casa', ...zocalo},
      endPoint: {'name': 'Coyoacán', ...coyoacan},
      sections: [bellas, museo],
    );
    expect(e.start!.name, 'Casa');
    expect(e.start!.sectionId, isNull);
    expect(e.end!.sectionId, isNull);
    expect(e.start!.derived, isFalse);
  });

  test('el inicio guardado en la primera parada la marca', () {
    final e = routeEndpointsOf(startPoint: {'name': '', 'lat': 19.43521, 'lng': -99.14121}, sections: [bellas, museo]);
    expect(e.start!.sectionId, 'b');
    expect(e.start!.name, 'Bellas Artes');
  });

  test('plan con IA de ida y vuelta: termina con el regreso al punto de partida', () {
    final e = routeEndpointsOf(
      startPoint: {'name': 'Hotel', ...zocalo},
      sections: [bellas, museo, TransferSection(id: 't', notes: 'Regreso al punto de partida')],
    );
    expect(e.end!.name, 'Hotel');
    expect(e.end!.sectionId, isNull);
    expect(e.roundTrip, isTrue);
  });

  test('plan a mano: las paradas de partida y llegada', () {
    int n = 0;
    final s = manualPlanSections(
      routeShape: 'ambos',
      originName: 'Zócalo',
      origin: zocalo,
      destinationName: 'Coyoacán',
      destination: coyoacan,
      newId: (tag) => 's${n++}_$tag',
    );
    final e = routeEndpointsOf(sections: [s.first, bellas, s.last]);
    expect(e.start!.name, 'Zócalo');
    expect(e.labelFor(s.first.id), 'Inicio');
    expect(e.labelFor(s.last.id), 'Fin');
  });

  test('sin paradas con ubicación no hay inicio ni fin', () {
    expect(routeEndpointsOf(sections: [place('x', 'Sin lugar', null, null)]).isEmpty, isTrue);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:othli_front/models/trip_model.dart';
import 'package:othli_front/services/trip_transfers.dart';

PlaceSection place(String id, {double? lat, double? lng, String? a, String? d}) => PlaceSection(
      id: id,
      title: id,
      description: '',
      rating: 5,
      mainPhotoUrl: '',
      secondaryPhotoUrls: const [],
      lat: lat,
      lng: lng,
      arrivalTime: a,
      departureTime: d,
    );

void main() {
  // Bellas Artes → Zócalo → Templo Mayor (CDMX)
  final bellas = place('bellas', lat: 19.4352, lng: -99.1412, a: '10:00', d: '11:00');
  final zocalo = place('zocalo', lat: 19.4326, lng: -99.1332);
  final templo = place('templo', lat: 19.4351, lng: -99.1314, a: '15:00', d: '16:30');

  test('TransferSection sobrevive toMap/fromMap', () {
    final t = TransferSection(id: 't1', mode: 'metro', durationMins: 18, distanceKm: 3.2, notes: 'Línea 2', cost: 5, isEstimated: true);
    final back = TripSection.fromMap(t.toMap()) as TransferSection;
    expect(back.mode, 'metro');
    expect(back.durationMins, 18);
    expect(back.distanceKm, 3.2);
    expect(back.notes, 'Línea 2');
    expect(back.isEstimated, true);
  });

  test('un tipo desconocido no rompe la carga y se conserva', () {
    final content = TripContent.fromMap({
      'sections': [
        {'id': 'x', 'type': 'video', 'url': 'https://example.com'},
      ],
    });
    expect(content.sections.single, isA<UnknownSection>());
    expect(content.sections.single.toMap()['url'], 'https://example.com');
  });

  test('completar traslados inserta uno entre cada par de paradas', () {
    int n = 0;
    final (list, added) = fillMissingTransfers([bellas, zocalo, templo], 'walking', () => 'g${n++}');
    expect(added, 2);
    expect(list.map((s) => s.type).toList(), ['place', 'transfer', 'place', 'transfer', 'place']);
    final first = list[1] as TransferSection;
    expect(first.isEstimated, true);
    expect(first.distanceKm, greaterThan(0.8));
    expect(first.distanceKm, lessThan(1.5));
  });

  test('no duplica traslados existentes', () {
    final existing = TransferSection(id: 't', mode: 'metro', durationMins: 10);
    final (list, added) = fillMissingTransfers([bellas, existing, zocalo], 'walking', () => 'g');
    expect(added, 0);
    expect(list.length, 3);
  });

  test('ajustar horarios encadena estancias y traslados', () {
    final out = recalculateSchedule([
      bellas,
      TransferSection(id: 't1', durationMins: 15),
      zocalo,
      TransferSection(id: 't2', durationMins: 10),
      templo,
    ]);
    final places = out.whereType<PlaceSection>().toList();
    expect(places[0].arrivalTime, '10:00');
    expect(places[0].departureTime, '11:00');
    expect(places[1].arrivalTime, '11:15'); // 11:00 + 15 min
    expect(places[1].departureTime, '12:15'); // estancia por defecto 60
    expect(places[2].arrivalTime, '12:25'); // 12:15 + 10
    expect(places[2].departureTime, '13:55'); // conserva su estancia de 90 min
  });

  test('normaliza los modos del motor', () {
    expect(normalizeTransferMode('walking'), 'walking');
    expect(normalizeTransferMode('foot'), 'walking');
    expect(normalizeTransferMode('Metrobús'), 'metrobus');
    expect(normalizeTransferMode(null), 'walking');
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:othli_front/models/trip_model.dart';

void main() {
  final original = PlaceSection(
    id: 'sec_1',
    title: 'Museo Frida Kahlo',
    description: 'Casa Azul',
    rating: 5,
    mainPhotoUrl: 'https://example.com/a.jpg',
    secondaryPhotoUrls: const [],
    cost: 320,
    lat: 19.3551,
    lng: -99.1625,
    arrivalTime: '10:00',
    departureTime: '11:30',
  );

  test('copyWith conserva coordenadas y horarios al editar otros campos', () {
    final edited = original.copyWith(title: 'Casa Azul', cost: 350);
    expect(edited.title, 'Casa Azul');
    expect(edited.cost, 350);
    expect(edited.id, 'sec_1');
    expect(edited.lat, 19.3551);
    expect(edited.lng, -99.1625);
    expect(edited.arrivalTime, '10:00');
    expect(edited.departureTime, '11:30');
  });

  test('copyWith + toMap/fromMap no pierde datos de la parada', () {
    final restored = PlaceSection.fromMap(
      original.copyWith(mainPhotoUrl: 'https://example.com/b.jpg').toMap(),
    );
    expect(restored.mainPhotoUrl, 'https://example.com/b.jpg');
    expect(restored.lat, original.lat);
    expect(restored.lng, original.lng);
    expect(restored.arrivalTime, original.arrivalTime);
    expect(restored.departureTime, original.departureTime);
  });

  test('Trip conserva tipo y versión de las notas de versión', () {
    final now = DateTime(2026, 11, 13);
    final notes = Trip(
      id: 't',
      userId: 'u',
      title: 'Novedades',
      description: '',
      coverUrl: '',
      status: 'published',
      visibility: 'public',
      createdAt: now,
      updatedAt: now,
      kind: kTripKindReleaseNotes,
      version: '1.4.0',
    );
    final back = Trip.fromMap(notes.toMap(), 't');
    expect(back.isReleaseNotes, true);
    expect(back.version, '1.4.0');
    // Los viajes existentes (sin campo kind) siguen siendo viajes
    final legacy = Trip.fromMap({'title': 'Viejo'}, 'x');
    expect(legacy.kind, kTripKindTrip);
    expect(legacy.isReleaseNotes, false);
  });
}

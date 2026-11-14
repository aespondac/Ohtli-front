import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:othli_front/models/trip_model.dart';
import 'package:othli_front/screens/trips/trip_sample.dart';
import 'package:othli_front/services/trip_transfers.dart';
import 'package:othli_front/widgets/trip_mini_map.dart';

void main() {
  test('el viaje de muestra trae todos los tipos de bloque', () {
    final sections = TripSample.sections(SampleStage.durante);
    expect(sections.whereType<TextSection>(), isNotEmpty);
    expect(sections.whereType<TextImageSection>(), isNotEmpty);
    final places = sections.whereType<PlaceSection>().toList();
    expect(places.where((p) => p.secondaryPhotoUrls.length >= 2), isNotEmpty, reason: 'parada con varias fotos');
    expect(places.where((p) => p.mainPhotoUrl.isEmpty), isNotEmpty, reason: 'parada sin fotos');
    expect(places.every((p) => p.lat != null && p.lng != null), isTrue, reason: 'todas se dibujan en el mapa');
    // Desvío, horas reales, gasto real, tabla y nota.
    expect(places.where((p) => p.unplanned), hasLength(1));
    expect(places.where((p) => p.arrivedAt != null && p.leftAt == null), hasLength(1), reason: 'parada en curso');
    expect(places.where((p) => p.realCost != null), isNotEmpty);
    expect(sections.whereType<TextSection>().where((t) => t.markdownText.startsWith('|')), isNotEmpty);
    expect(sections.whereType<TextSection>().where((t) => t.markdownText.startsWith('> [!')), isNotEmpty);
    expect(TripSample.sections(SampleStage.antes).whereType<PlaceSection>().where((p) => p.unplanned), isEmpty);
    final modes = sections.whereType<TransferSection>().map((t) => t.mode).toSet();
    expect(modes.length, greaterThanOrEqualTo(4));
    // Cada mensaje apunta a un bloque que existe.
    final ids = sections.map((s) => s.id).toSet();
    for (final n in TripSample.notes(SampleStage.durante)) {
      expect(ids, contains(n.blockId));
    }
    expect(TripSample.reactions.keys.every(ids.contains), isTrue);
  });

  test('se califica cada parada al visitarla; antes del viaje no hay calificaciones', () {
    int rated(SampleStage st) => TripSample.sections(st).whereType<PlaceSection>().where((p) => p.rating > 0).length;
    expect(rated(SampleStage.antes), 0);
    final durante = TripSample.sections(SampleStage.durante).whereType<PlaceSection>();
    expect(durante.where((p) => p.rating > 0).every((p) => TripSample.visited(SampleStage.durante).contains(p.id)), isTrue);
    expect(rated(SampleStage.despues), greaterThan(rated(SampleStage.durante)));
    expect(TripSample.trip(SampleStage.despues).reviewedAt, isNotNull);
    expect(TripSample.trip(SampleStage.antes).travelDate!.isAfter(DateTime.now()), isTrue);
  });

  test('los mensajes y reacciones de la muestra viven en memoria', () async {
    final social = SampleTripSocialService(TripSample.notes(SampleStage.durante), TripSample.reactions);
    final notes = social.notesStream();
    final initial = await notes.first;
    await social.addNote(blockId: 'p6', authorId: kSampleMyUid, authorName: kSampleMyName, text: '  ¿Dominó?  ');
    final after = await social.notesStream().first;
    expect(after.length, initial.length + 1);
    expect(after.last.text, '¿Dominó?');

    await social.reactToNote(after.last.id, 'muestra-luis', 'haha');
    expect((await social.notesStream().first).last.reactions, {'muestra-luis': 'haha'});

    await social.reactToBlock('p6', kSampleMyUid, 'fire');
    expect((await social.reactionsStream().first)['p6'], {kSampleMyUid: 'fire'});
    await social.reactToBlock('p6', kSampleMyUid, null);
    expect((await social.reactionsStream().first)['p6'], isEmpty);
  });

  test('el mini mapa acerca más cuando las paradas están juntas', () {
    const size = Size(304, 168);
    const near = [MiniMapStop(lat: 19.4189, lng: -99.1627, number: 1), MiniMapStop(lat: 19.4116, lng: -99.1693, number: 2)];
    const far = [MiniMapStop(lat: 19.4189, lng: -99.1627, number: 1), MiniMapStop(lat: 19.3497, lng: -99.1622, number: 2)];
    expect(TripMiniMap.fitZoom(near, size), greaterThan(TripMiniMap.fitZoom(far, size)));
    expect(TripMiniMap.fitZoom(const [MiniMapStop(lat: 19.4, lng: -99.1, number: 1)], size), 15);
    expect(TripMiniMap.fitZoom(far, size), inInclusiveRange(3, 16));
  });

  test('los campos del viajero se guardan y se leen', () {
    final p = PlaceSection(
      id: 'x',
      title: 'Desvío',
      description: '',
      rating: 0,
      mainPhotoUrl: '',
      secondaryPhotoUrls: const [],
      unplanned: true,
      arrivedAt: '11:01',
      leftAt: '11:15',
      realCost: 70,
    );
    final back = PlaceSection.fromMap(p.toMap());
    expect(back.unplanned, isTrue);
    expect(back.arrivedAt, '11:01');
    expect(back.leftAt, '11:15');
    expect(back.realCost, 70);
    // Una parada normal no escribe los campos nuevos.
    final plain = PlaceSection(id: 'y', title: 'A', description: '', rating: 0, mainPhotoUrl: '', secondaryPhotoUrls: const []);
    expect(plain.toMap().containsKey('unplanned'), isFalse);
    expect(plain.copyWith(arrivedAt: '10:00').copyWith(clearArrivedAt: true).arrivedAt, isNull);
  });

  test('modos de traslado nuevos', () {
    for (final id in ['cablebus', 'trolebus', 'tren_ligero', 'suburbano', 'scooter', 'trajinera']) {
      expect(transferModeOf(id).id, id);
    }
    expect(normalizeTransferMode('Trolebús línea 2'), 'trolebus');
    expect(normalizeTransferMode('Cablebús'), 'cablebus');
    expect(normalizeTransferMode('metrobús'), 'metrobus');
  });
}

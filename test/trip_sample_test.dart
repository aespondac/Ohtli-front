import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:othli_front/models/trip_model.dart';
import 'package:othli_front/screens/trips/trip_sample.dart';
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
    final modes = sections.whereType<TransferSection>().map((t) => t.mode).toSet();
    expect(modes.length, greaterThanOrEqualTo(4));
    // Cada mensaje apunta a un bloque que existe.
    final ids = sections.map((s) => s.id).toSet();
    for (final n in TripSample.notes(SampleStage.durante)) {
      expect(ids, contains(n.blockId));
    }
    expect(TripSample.reactions.keys.every(ids.contains), isTrue);
  });

  test('las calificaciones solo aparecen después del viaje', () {
    int rated(SampleStage st) => TripSample.sections(st).whereType<PlaceSection>().where((p) => p.rating > 0).length;
    expect(rated(SampleStage.antes), 0);
    expect(rated(SampleStage.durante), 0);
    expect(rated(SampleStage.despues), greaterThan(0));
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
}

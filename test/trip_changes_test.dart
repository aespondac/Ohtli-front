import 'package:flutter_test/flutter_test.dart';
import 'package:othli_front/models/trip_model.dart';
import 'package:othli_front/services/trip_changes.dart';

PlaceSection place(String id, String title, {double cost = 0, double? real, int rating = 0, String? cover, bool unplanned = false, String? from, String? to}) =>
    PlaceSection(
      id: id,
      title: title,
      description: '',
      rating: rating,
      mainPhotoUrl: '',
      secondaryPhotoUrls: const [],
      cost: cost,
      realCost: real,
      coverUrl: cover,
      unplanned: unplanned,
      arrivalTime: from,
      departureTime: to,
    );

void main() {
  test('describe presupuesto, gasto, calificación, portada y horario', () {
    final before = [place('a', 'Tacos', cost: 180, rating: 4, from: '13:00', to: '14:00')];
    final after = [place('a', 'Tacos', cost: 200, real: 236, rating: 5, cover: 'https://x/p.jpg', from: '13:30', to: '14:00')];
    final c = describeTripChanges(before, after);
    expect(c, contains('Presupuesto de «Tacos»: \$180 → \$200'));
    expect(c, contains('Gasto real de «Tacos»: sin registrar → \$236'));
    expect(c, contains('Calificación de «Tacos»: 4 ★ → 5 ★'));
    expect(c, contains('Cambió la portada de «Tacos»'));
    expect(c, contains('Horario de «Tacos»: 13:00–14:00 → 13:30–14:00'));
  });

  test('describe desvíos, bloques agregados, quitados y cambio de orden', () {
    final before = [place('a', 'Café'), TextSection(id: 't', markdownText: 'Hola'), place('b', 'Parque')];
    final after = [
      place('b', 'Parque'),
      place('a', 'Café'),
      place('d', 'Paletas', unplanned: true),
      TextSection(id: 'n', markdownText: '> [!TIP]\n> Lleven agua'),
      TransferSection(id: 'x', mode: 'cablebus', durationMins: 12),
    ];
    final c = describeTripChanges(before, after);
    expect(c, contains('Se agregó el desvío «Paletas»'));
    expect(c.any((l) => l.startsWith('Se agregó la nota')), isTrue);
    expect(c.any((l) => l.startsWith('Se agregó el traslado')), isTrue);
    expect(c, contains('Se quitó el texto «Hola»'));
    expect(c, contains('Se cambió el orden de los bloques'));
  });

  test('sin cambios no hay nada que registrar y la lista se corta', () {
    final same = [place('a', 'Café', cost: 10)];
    expect(describeTripChanges(same, same), isEmpty);
    final many = [for (int i = 0; i < 30; i++) place('p$i', 'P$i')];
    final c = describeTripChanges(const [], many, limit: 5);
    expect(c, hasLength(5));
    expect(c.last, 'y 26 cambios más');
  });

  test('la errata guarda autor y cambios, y lee las antiguas sin ellos', () {
    final e = ErrataEntry(id: '1', note: '', date: DateTime(2026, 11, 14, 21), authorId: 'u', authorName: 'Ana', changes: const ['x']);
    final back = ErrataEntry.fromMap(e.toMap());
    expect(back.authorName, 'Ana');
    expect(back.changes, ['x']);
    final old = ErrataEntry.fromMap({'id': '2', 'note': 'Corrección', 'date': null});
    expect(old.authorName, '');
    expect(old.changes, isEmpty);
  });

  test('describe las propuestas de lugares', () {
    const tacos = ProposalCandidate(id: 'c1', title: 'Tacos El Güero');
    const pozole = ProposalCandidate(id: 'c2', title: 'Pozolería');
    final before = [ProposalSection(id: 'v', question: '', candidates: const [tacos])];
    final after = [ProposalSection(id: 'v', question: '¿Dónde comemos?', candidates: const [pozole])];
    final c = describeTripChanges(before, after);
    expect(c, contains('Cambió la pregunta de la propuesta de lugares a «¿Dónde comemos?»'));
    expect(c, contains('Se propuso «Pozolería» en la propuesta «¿Dónde comemos?»'));
    expect(c, contains('Se quitó «Tacos El Güero» de la propuesta «¿Dónde comemos?»'));
    expect(describeTripChanges(const [], before), contains('Se agregó una propuesta de lugares'));
  });

  test('describe la separación del grupo y quién va a cada parada', () {
    final before = [
      SplitSection(id: 's', branches: const [
        TripBranch(id: 'a', name: 'Grupo 1', memberIds: ['ana']),
        TripBranch(id: 'b', name: 'Grupo 2'),
      ]),
      place('p', 'Museo'),
      place('q', 'Café'),
    ];
    final after = [
      SplitSection(id: 's', branches: const [
        TripBranch(id: 'a', name: 'Museos', memberIds: ['ana', 'beto']),
        TripBranch(id: 'c', name: 'Mercado', rejoins: false),
      ]),
      PlaceSection(id: 'p', title: 'Museo', description: '', rating: 0, mainPhotoUrl: '', secondaryPhotoUrls: const [], branchId: 'a'),
      PlaceSection(id: 'q', title: 'Café', description: '', rating: 0, mainPhotoUrl: '', secondaryPhotoUrls: const [], meetup: true),
    ];
    final c = describeTripChanges(before, after);
    expect(c, contains('Se renombró el grupo «Grupo 1» como «Museos»'));
    expect(c, contains('Cambió quién va en «Museos»'));
    expect(c, contains('Se agregó el grupo «Mercado»'));
    expect(c, contains('Se quitó el grupo «Grupo 2»'));
    expect(c, contains('Cambió quién va a «Museo»'));
    expect(c, contains('«Café» es ahora el punto de reencuentro'));
    expect(describeTripChanges(const [], [before.first]), contains('Se agregó una separación del grupo'));
  });
}

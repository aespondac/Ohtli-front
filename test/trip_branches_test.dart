import 'package:flutter_test/flutter_test.dart';
import 'package:othli_front/models/trip_model.dart';
import 'package:othli_front/services/proposal_votes.dart';
import 'package:othli_front/services/trip_branches.dart';

PlaceSection p(String id, {String? branch, bool meetup = false, String? from, String? to, double lat = 19.43, double lng = -99.13}) =>
    PlaceSection(
      id: id,
      title: id,
      description: '',
      rating: 0,
      mainPhotoUrl: '',
      secondaryPhotoUrls: const [],
      branchId: branch,
      meetup: meetup,
      arrivalTime: from,
      departureTime: to,
      lat: lat,
      lng: lng,
    );

TransferSection t(String id, int mins, {String? branch}) => TransferSection(id: id, durationMins: mins, branchId: branch);

SplitSection split({bool bRejoins = true}) => SplitSection(id: 'split', branches: [
      const TripBranch(id: 'a', name: 'Museos', memberIds: ['ana']),
      TripBranch(id: 'b', name: 'Mercado', memberIds: const ['beto'], rejoins: bRejoins),
    ]);

void main() {
  group('Ramas', () {
    test('sin separarse: cada parada viene de la anterior y termina en la última', () {
      final l = branchLayout([p('1'), t('t1', 10), p('2'), p('3')]);
      expect(l.from['1'], isEmpty);
      expect(l.from['2'], ['1']);
      expect(l.from['3'], ['2']);
      expect(l.endIds, ['3']);
    });

    test('se separan y se reencuentran', () {
      final l = branchLayout([
        p('inicio'),
        split(),
        p('a1', branch: 'a'),
        p('a2', branch: 'a'),
        p('b1', branch: 'b'),
        p('juntos', meetup: true),
        p('fin'),
      ]);
      expect(l.from['a1'], ['inicio']);
      expect(l.from['a2'], ['a1']);
      expect(l.from['b1'], ['inicio']);
      expect(l.from['juntos'], ['a2', 'b1']);
      expect(l.laneOfPlace['a2'], 'a');
      expect(l.laneOfPlace['juntos'], '');
      expect(l.endIds, ['fin']);
    });

    test('reencontrarse es opcional: varios puntos de llegada', () {
      final sinReencuentro = branchLayout([p('inicio'), split(), p('a1', branch: 'a'), p('b1', branch: 'b'), p('b2', branch: 'b')]);
      expect(sinReencuentro.endIds, ['a1', 'b2']);

      // La rama b no se reencuentra: termina en b1; a llega al reencuentro.
      final parcial = branchLayout([p('inicio'), split(bRejoins: false), p('a1', branch: 'a'), p('b1', branch: 'b'), p('juntos', meetup: true)]);
      expect(parcial.from['juntos'], ['a1']);
      expect(parcial.endIds, containsAll(['b1', 'juntos']));
      expect(parcial.endIds, hasLength(2));
    });

    test('horarios: cada rama su reloj y el reencuentro espera a la más tardía', () {
      final out = recalculateScheduleByBranch([
        p('inicio', from: '10:00', to: '11:00'),
        split(),
        t('ta', 10, branch: 'a'),
        p('a1', branch: 'a'), // 11:10–12:10
        t('tb', 30, branch: 'b'),
        p('b1', branch: 'b', from: '00:00', to: '02:00'), // 11:30–13:30 (estancia de 2 h)
        t('ta2', 15, branch: 'a'),
        t('tb2', 5, branch: 'b'),
        p('juntos', meetup: true), // a llega 12:25, b 13:35 → 13:35
      ]).whereType<PlaceSection>().toList();
      String at(String id) => out.firstWhere((x) => x.id == id).arrivalTime!;
      expect(at('a1'), '11:10');
      expect(at('b1'), '11:30');
      expect(at('juntos'), '13:35');
    });

    test('traslados que faltan: uno por rama y uno por rama hacia el reencuentro', () {
      int n = 0;
      final (list, added) = fillMissingTransfersByBranch(
        [
          p('inicio', lat: 19.430, lng: -99.130),
          split(),
          p('a1', branch: 'a', lat: 19.435, lng: -99.140),
          p('b1', branch: 'b', lat: 19.420, lng: -99.160),
          p('juntos', meetup: true, lat: 19.400, lng: -99.150),
        ],
        'walking',
        () => 'n${n++}',
      );
      expect(added, 4);
      final transfers = list.whereType<TransferSection>().map((x) => x.branchId).toList();
      expect(transfers, ['a', 'b', 'a', 'b']);
      // El de b1 va antes de b1 y los dos del reencuentro justo antes de él.
      final ids = list.map((x) => x.id).toList();
      expect(ids.indexOf('juntos') - 2, ids.indexOf(list.whereType<TransferSection>().elementAt(2).id));
    });

    test('cada quien ve las paradas de su rama', () {
      final s = [p('inicio'), split(), p('a1', branch: 'a'), p('b1', branch: 'b'), p('juntos', meetup: true)];
      expect(placesFor(s, 'ana').map((x) => x.id), ['inicio', 'a1', 'juntos']);
      expect(placesFor(s, 'beto').map((x) => x.id), ['inicio', 'b1', 'juntos']);
      expect(placesFor(s, 'nadie').map((x) => x.id), ['inicio', 'a1', 'b1', 'juntos']);
    });

    test('qué separación rige cada bloque y de qué rama es cada traslado', () {
      final s = [p('inicio'), split(), t('ta', 10), p('a1', branch: 'a'), t('tb', 5), p('b1', branch: 'b'), t('tj', 5), p('juntos', meetup: true), t('tf', 5), p('fin')];
      expect(splitBefore(s, 0), isNull);
      expect(splitBefore(s, 3)?.id, 'split');
      // El reencuentro cierra la separación, pero él mismo todavía elige «¿quién va?».
      expect(splitBefore(s, 7)?.id, 'split');
      expect(splitBefore(s, 9), isNull);
      expect(transferBranchFor(s, 2), 'a');
      expect(transferBranchFor(s, 4), 'b');
      // Rumbo al reencuentro: el traslado es de la rama de la que sale.
      expect(transferBranchFor(s, 6), 'b');
      expect(transferBranchFor(s, 8), isNull);
      expect(branchIndexes(s), {'a': 0, 'b': 1});
      expect(branchesById(s)['b']!.name, 'Mercado');
      expect(hasBranches(s), isTrue);
      expect(hasBranches([p('x')]), isFalse);
    });

    test('la rama de cada bloque, los reencuentros y las llegadas', () {
      final s = [
        p('inicio', branch: 'a'), // con rama pero antes de separarse: es de todos
        split(bRejoins: false),
        t('ta', 5, branch: 'a'),
        p('a1', branch: 'a'),
        p('b1', branch: 'b'),
        p('juntos', meetup: true),
        p('fin', branch: 'b'), // ya se reencontraron: es de todos
      ];
      expect(blockLanes(s), {'ta': 'a', 'a1': 'a', 'b1': 'b'});
      expect(meetupIds(s), {'juntos'});
      final v = BranchView.of(s);
      expect(v.branchOf('a1')!.name, 'Museos');
      expect(v.branchOf('inicio'), isNull);
      expect(v.indexOf('b'), 1);
      expect(v.isMeetup('juntos'), isTrue);
      // b no se reencuentra: termina en b1; el resto, en la última parada.
      expect(v.isEnd('b1'), isTrue);
      expect(v.isEnd('fin'), isTrue);
      expect(v.isEnd('a1'), isFalse);
      // Sin separarse no se marca ninguna llegada.
      expect(BranchView.of([p('x'), p('y')]).isEnd('y'), isFalse);
    });

    test('las puntas de un traslado siguen su rama', () {
      final s = [
        p('inicio'),
        split(),
        p('a1', branch: 'a'),
        t('tb', 5, branch: 'b'),
        p('b1', branch: 'b'),
        t('ta', 5, branch: 'a'),
        t('tb2', 5, branch: 'b'),
        p('juntos', meetup: true),
      ];
      String ends((PlaceSection?, PlaceSection?) e) => '${e.$1?.id}→${e.$2?.id}';
      // b todavía no tiene paradas: sale de donde se separaron.
      expect(ends(transferEnds(s, 3)), 'inicio→b1');
      expect(ends(transferEnds(s, 5)), 'a1→juntos');
      expect(ends(transferEnds(s, 6)), 'b1→juntos');
      // Sin ramas, las vecinas de siempre.
      expect(ends(transferEnds([p('x'), t('t', 5), p('y')], 1)), 'x→y');
    });

    test('los bloques nuevos se guardan y se leen igual', () {
      final s = split(bRejoins: false);
      final back = TripSection.fromMap(s.toMap()) as SplitSection;
      expect(back.branches.map((b) => b.name), ['Museos', 'Mercado']);
      expect(back.branches.last.rejoins, isFalse);
      expect(back.branches.first.memberIds, ['ana']);

      final place = TripSection.fromMap(p('x', branch: 'a', meetup: true).toMap()) as PlaceSection;
      expect(place.branchId, 'a');
      expect(place.meetup, isTrue);
      expect(p('y').toMap().containsKey('branchId'), isFalse);

      final prop = ProposalSection(id: 'pr', question: '¿Dónde comemos?', candidates: const [
        ProposalCandidate(id: 'c1', title: 'Fonda', lat: 19.4, lng: -99.1, poiId: 'poi_1', proposedBy: 'ana', proposedByName: 'Ana'),
      ]);
      final propBack = TripSection.fromMap(prop.toMap()) as ProposalSection;
      expect(propBack.question, '¿Dónde comemos?');
      expect(propBack.candidates.single.proposedByName, 'Ana');
      final winner = propBack.candidates.single.toPlace('sec_1');
      expect(winner.title, 'Fonda');
      expect(winner.poiSource, kPlaceSourceCatalog);
    });
  });

  group('Propuestas de lugares', () {
    const fonda = ProposalCandidate(id: 'fonda', title: 'Fonda');
    const tacos = ProposalCandidate(id: 'tacos', title: 'Tacos');
    const cafe = ProposalCandidate(id: 'cafe', title: 'Café');

    test('gana el más votado y sin votos no gana nadie', () {
      expect(proposalWinner([fonda, tacos], {}), isNull);
      expect(proposalWinner([fonda, tacos], {'a': 'tacos', 'b': 'tacos', 'c': 'fonda'})!.id, 'tacos');
      // Un voto por un lugar que ya no está no cuenta.
      expect(proposalWinner([fonda, tacos], {'a': 'borrado', 'b': 'fonda'})!.id, 'fonda');
    });

    test('empate: decide el voto de quien organiza; si no, el primero propuesto', () {
      final votes = {'dueno': 'cafe', 'b': 'tacos'};
      expect(proposalWinner([fonda, tacos, cafe], votes, tieBreakerUid: 'dueno')!.id, 'cafe');
      expect(proposalWinner([fonda, tacos, cafe], votes)!.id, 'tacos');
    });

    test('ya votaron todos', () {
      expect(everyoneVotedOn({'a': 'x', 'b': 'y'}, ['a', 'b']), isTrue);
      expect(everyoneVotedOn({'a': 'x'}, ['a', 'b']), isFalse);
      expect(everyoneVotedOn({}, const []), isFalse);
    });

    test('quién votó por cada lugar y votos que ya no cuentan', () {
      final votes = {'a': 'tacos', 'b': 'fonda', 'c': 'tacos', 'd': 'borrado'};
      expect(votersOf(votes, 'tacos'), ['a', 'c']);
      expect(votersOf(votes, 'cafe'), isEmpty);
      final valid = validVotes(votes, [fonda, tacos]);
      expect(valid, {'a': 'tacos', 'b': 'fonda', 'c': 'tacos'});
      // Quien votó por un lugar quitado todavía no cuenta como «ya votó».
      expect(everyoneVotedOn(valid, ['a', 'b', 'c', 'd']), isFalse);
    });

    test('resumen de cuántos votaron y quién falta', () {
      final names = {'dueno': 'Ana López', 'b': 'Beto', 'c': 'Caro'};
      expect(proposalTally({'dueno': 'x', 'b': 'y', 'c': 'x'}, ['dueno', 'b', 'c'], names), 'Ya votaron todos');
      expect(proposalTally({'dueno': 'x'}, ['dueno', 'b', 'c'], names, myUid: 'dueno'), '1 de 3 ya votaron · faltan Beto y Caro');
      expect(proposalTally({'b': 'x', 'c': 'x'}, ['dueno', 'b', 'c'], names, myUid: 'dueno'), '2 de 3 ya votaron · falta tu voto');
      expect(proposalTally({'c': 'x'}, ['dueno', 'b', 'c'], names, myUid: 'b'), '1 de 3 ya votaron · faltan Ana López y tú');
    });
  });
}

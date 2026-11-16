import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:othli_front/models/trip_model.dart';
import 'package:othli_front/services/group_trip_service.dart';
import 'package:othli_front/services/manual_plan.dart';

void main() {
  const zocalo = {'lat': 19.4326, 'lng': -99.1332};
  const coyoacan = {'lat': 19.3497, 'lng': -99.1622};
  int n = 0;
  String id(String tag) => 's${n++}_$tag';

  group('Plan hecho a mano', () {
    test('forma de la ruta', () {
      expect(routeShapeOf('anillo', 'fin'), 'anillo');
      expect(routeShapeOf('radio', 'inicio'), 'inicio');
      expect(routeShapeOf('radio', 'ambos'), 'ambos');
    });

    test('ida y vuelta: sale y regresa al mismo punto', () {
      final s = manualPlanSections(routeShape: 'anillo', originName: 'Zócalo', origin: zocalo, newId: id).cast<PlaceSection>();
      expect(s.map((p) => p.title), ['Zócalo', 'Zócalo']);
      expect(s.first.description, 'Punto de partida');
      expect(s.last.description, 'Regreso al punto de partida');
      expect(s.last.lat, zocalo['lat']);
    });

    test('abierta: solo el inicio, solo el final o ambos', () {
      final inicio = manualPlanSections(routeShape: 'inicio', originName: 'Zócalo', origin: zocalo, destination: coyoacan, newId: id);
      expect(inicio.cast<PlaceSection>().map((p) => p.title), ['Zócalo']);

      final fin = manualPlanSections(
          routeShape: 'fin', originName: 'Zócalo', origin: zocalo, destinationName: 'Coyoacán', destination: coyoacan, newId: id);
      expect(fin.cast<PlaceSection>().map((p) => p.title), ['Coyoacán']);
      expect((fin.single as PlaceSection).description, 'Punto de llegada');

      final ambos = manualPlanSections(
          routeShape: 'ambos', originName: 'Zócalo', origin: zocalo, destinationName: 'Coyoacán', destination: coyoacan, newId: id);
      expect(ambos.cast<PlaceSection>().map((p) => p.title), ['Zócalo', 'Coyoacán']);
    });

    test('ids distintos y título según la forma', () {
      final s = manualPlanSections(routeShape: 'anillo', originName: 'Zócalo', origin: zocalo, newId: id);
      expect(s.first.id, isNot(s.last.id));
      expect(manualPlanTitle(routeShape: 'anillo', originName: 'Zócalo'), 'Ruta desde Zócalo');
      expect(manualPlanTitle(routeShape: 'fin', originName: 'Zócalo', destinationName: 'Coyoacán'), 'Ruta hacia Coyoacán');
      expect(manualPlanTitle(routeShape: 'inicio'), 'Nuevo viaje');
    });

    test('la forma y el grupo se guardan solo si existen', () {
      Trip trip({String? shape, String? group}) => Trip(
            id: 't',
            userId: 'u',
            title: 'x',
            description: '',
            coverUrl: '',
            status: 'draft',
            visibility: 'private',
            createdAt: DateTime(2026),
            updatedAt: DateTime(2026),
            routeShape: shape,
            groupTripId: group,
          );
      expect(trip().toMap().containsKey('routeShape'), isFalse);
      expect(trip().toMap().containsKey('groupTripId'), isFalse);
      final m = trip(shape: 'anillo', group: 'grp_1').toMap();
      expect(Trip.fromMap(m, 't').routeShape, 'anillo');
      expect(Trip.fromMap(m, 't').groupTripId, 'grp_1');
    });
  });

  group('Viaje en grupo', () {
    test('respuestas: solo cuentan las de quien está invitado', () {
      final g = GroupTrip.fromMap('grp_1', {
        'kind': 'manual',
        'hostId': 'h',
        'hostName': 'Ana',
        'title': 'Sábado en Coyoacán',
        'tripId': 't1',
        'travelDate': Timestamp.fromDate(DateTime(2026, 11, 21)),
        'invitedIds': ['a', 'b', 'c'],
        'members': {
          'a': {'name': 'Beto'},
          'b': {'name': 'Caro', 'photo': ''},
        },
        'responses': {'a': 'accepted', 'b': 'declined', 'z': 'accepted'},
        'votes': {'a': 1, 'h': 2.0},
      });
      expect(g.isManual, isTrue);
      expect(g.acceptedIds, ['a']);
      expect(g.pendingIds, ['c']);
      expect(g.responseOf('b'), 'declined');
      expect(g.responseOf('nadie'), 'pending');
      expect(g.nameOf('h'), 'Ana');
      expect(g.nameOf('a'), 'Beto');
      expect(g.members['b']!.photo, isNull);
      expect(g.votes, {'a': 1, 'h': 2});
      expect(g.travelDate, DateTime(2026, 11, 21));
    });

    test('votación: votan el organizador y quienes aceptaron', () {
      GroupTrip g(Map<String, dynamic> extra) => GroupTrip.fromMap('grp_2', {
            'kind': 'ai',
            'hostId': 'h',
            'invitedIds': ['a', 'b', 'c'],
            'responses': {'a': 'accepted', 'b': 'declined'},
            'status': 'voting',
            'options': [
              {'theme': 'Cafés'},
              {'theme': 'Museos'},
              'no es una ruta',
            ],
            ...extra,
          });
      final sinMotor = g({'votes': {'h': 1}});
      expect(sinMotor.isManual, isFalse);
      expect(sinMotor.options.map((o) => o['theme']), ['Cafés', 'Museos']);
      expect(sinMotor.voters, ['h', 'a']);
      expect(sinMotor.everyoneVoted, isFalse);
      expect(sinMotor.everyoneResponded, isFalse); // c no ha respondido

      // El motor fija quiénes votan; un voto de alguien que no participa no cuenta.
      final conMotor = g({
        'participantIds': ['h', 'a'],
        'votes': {'h': 1, 'a': 1, 'b': 0},
        'winner': 1,
      });
      expect(conMotor.votersFor(1), ['h', 'a']);
      expect(conMotor.votersFor(0), isEmpty);
      expect(conMotor.everyoneVoted, isTrue);
      expect(conMotor.winner, 1);
    });
  });
}

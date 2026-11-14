import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:othli_front/services/trip_social_service.dart';

void main() {
  test('resume reacciones en el orden de los tapbacks e ignora desconocidas', () {
    final summary = summarizeReactions({'a': 'like', 'b': 'heart', 'c': 'heart', 'd': 'nuevo-raro'});
    expect(summary.map((e) => e.key.id).toList(), ['heart', 'like']);
    expect(summary.first.value, 2);
    expect(summarizeReactions({}), isEmpty);
  });

  test('TripNote.fromMap tolera campos faltantes y convierte fechas', () {
    final when = DateTime(2026, 11, 14, 10, 12);
    final n = TripNote.fromMap('n1', {
      'blockId': 'b1',
      'authorId': 'u1',
      'text': 'Apartado',
      'createdAt': Timestamp.fromDate(when),
      'reactions': {'u2': 'heart'},
    });
    expect(n.authorName, 'Viajero');
    expect(n.createdAt, when);
    expect(n.editedAt, isNull);
    expect(n.reactions, {'u2': 'heart'});

    final pending = TripNote.fromMap('n2', {'blockId': 'b1', 'authorId': 'u1', 'text': 'x', 'createdAt': null});
    expect(pending.createdAt, isNull);
    expect(pending.reactions, isEmpty);
  });

  test('tapbackOf reconoce los ocho tipos', () {
    expect(kTapbacks.length, 8);
    for (final t in kTapbacks) {
      expect(tapbackOf(t.id), same(t));
    }
    expect(tapbackOf(null), isNull);
  });
}

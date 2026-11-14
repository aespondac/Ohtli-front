import 'package:flutter_test/flutter_test.dart';
import 'package:othli_front/labs/lab_aggregates.dart';
import 'package:othli_front/labs/lab_studies.dart';

Map<String, dynamic> sus(String uid, int at, {List<dynamic>? values}) => {
      'studyId': 'sus',
      'uid': uid,
      'createdAt': DateTime.fromMillisecondsSinceEpoch(at),
      'sus': values ?? List.filled(10, 4),
      'satisfaction': [5, 4, 4, 3, 5],
    };

Map<String, dynamic> rel(String uid, int at, int row, int opt, List<dynamic> grades) => {
      'studyId': 'relevancia',
      'uid': uid,
      'createdAt': DateTime.fromMillisecondsSinceEpoch(at),
      'runId': 'r1',
      'rowIndex': row,
      'optionIndex': opt,
      'grades': grades,
    };

void main() {
  test('IDs deterministas: una respuesta por persona', () {
    expect(susResponseId('u1'), 'sus_u1');
    expect(relevanceResponseId('u1', 'run9', 3, 1), 'rel_u1_run9_3_1');
  });

  group('likertList', () {
    test('acepta calificaciones 1–5', () {
      expect(likertList([1, 5, 3]), [1, 5, 3]);
      expect(likertList([4.0, 2]), [4, 2]);
      expect(likertList(List.filled(10, 3), length: 10), hasLength(10));
    });

    test('descarta valores inválidos en vez de romper el panel', () {
      expect(likertList(['x', 3]), isNull);
      expect(likertList([0, 3]), isNull);
      expect(likertList([6]), isNull);
      expect(likertList([2.5]), isNull);
      expect(likertList([]), isNull);
      expect(likertList(null), isNull);
      expect(likertList([1, 2], length: 10), isNull);
    });
  });

  group('cleanResponses', () {
    test('SUS: la más reciente por persona y sin respuestas inválidas', () {
      final docs = [
        sus('a', 1, values: List.filled(10, 1)),
        sus('a', 3, values: List.filled(10, 5)),
        sus('b', 2),
        sus('c', 4, values: ['x', ...List.filled(9, 3)]),
      ];
      final clean = cleanResponses(LabStudyKind.sus, docs);
      expect(clean, hasLength(2));
      expect(clean.firstWhere((d) => d['uid'] == 'a')['sus'], List.filled(10, 5));
      expect(aggregateSus(clean)['n'], 2);
    });

    test('relevancia: una por persona y alternativa', () {
      final docs = [
        rel('a', 1, 0, 0, [1, 1]),
        rel('a', 2, 0, 0, [5, 5]), // misma alternativa recalificada tras recargar
        rel('a', 3, 0, 1, [3]),
        rel('b', 4, 0, 0, [4, 4]),
        rel('b', 5, 1, 0, [100]), // inválida
      ];
      final clean = cleanResponses(LabStudyKind.relevance, docs);
      expect(clean, hasLength(3));
      final agg = aggregateRelevance(clean);
      expect(agg['judgments'], 3);
      expect(agg['judges'], 2);
    });
  });

  test('anonymizeResponses quita el uid y numera participantes por orden de llegada', () {
    final out = anonymizeResponses([sus('zeta', 5), sus('alfa', 9), sus('zeta', 7)]);
    expect(out.every((d) => !d.containsKey('uid')), isTrue);
    expect(out.map((d) => d['participante']).toList(), ['P001', 'P002', 'P001']);
  });
}

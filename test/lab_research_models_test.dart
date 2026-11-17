import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:othli_front/labs/research/lab_codenames.dart';
import 'package:othli_front/labs/research/lab_models.dart';

void main() {
  group('Validación de participantes', () {
    List<MemberCheckVote> votes(int si, int parte, int no) => [
          ...List.filled(si, MemberCheckVote.si),
          ...List.filled(parte, MemberCheckVote.enParte),
          ...List.filled(no, MemberCheckVote.no),
        ];

    test('quórum: max(3, 30 %) sin pasar de los inscritos', () {
      expect(memberCheckQuorum(2), 2);
      expect(memberCheckQuorum(5), 3);
      expect(memberCheckQuorum(10), 3);
      expect(memberCheckQuorum(20), 6);
      expect(memberCheckQuorum(101), 31);
    });

    test('se aprueba con quórum, apoyo ≥ 2/3 y "no" < 1/3', () {
      expect(memberCheck(votes(4, 2, 0), 20).approved, isTrue); // 6 votos, apoyo 0.83
      expect(memberCheck(votes(3, 0, 0), 5).approved, isTrue);
    });

    test('"no" de un tercio o más reprueba aunque el apoyo alcance', () {
      final r = memberCheck(votes(2, 0, 1), 10);
      expect(r.support, closeTo(2 / 3, 1e-9));
      expect(r.approved, isFalse);
    });

    test('sin quórum no se aprueba', () {
      final r = memberCheck(votes(2, 0, 0), 20);
      expect(r.quorumMet, isFalse);
      expect(r.approved, isFalse);
    });

    test('"en parte" cuenta medio', () {
      final r = memberCheck(votes(2, 2, 0), 10);
      expect(r.support, closeTo(0.75, 1e-9));
      expect(r.approved, isTrue);
    });
  });

  group('Dictámenes', () {
    test('avanza con el mínimo y sin cambios mayores ni rechazo', () {
      expect(reviewOutcome([ReviewDecision.aceptar], minReviews: 1), ReviewOutcome.avanza);
      expect(reviewOutcome([ReviewDecision.cambiosMenores], minReviews: 1), ReviewOutcome.avanza);
      expect(reviewOutcome([ReviewDecision.aceptar], minReviews: 2), ReviewOutcome.pendiente);
    });
    test('cambios mayores o rechazo regresan a borrador', () {
      expect(reviewOutcome([ReviewDecision.aceptar, ReviewDecision.cambiosMayores], minReviews: 1), ReviewOutcome.regresa);
      expect(reviewOutcome([ReviewDecision.rechazar], minReviews: 2), ReviewOutcome.regresa);
    });
  });

  group('Etapas', () {
    test('el paper solo pasa por las etapas que configura el estudio', () {
      expect(paperPipeline(const StudyConfig(participantValidation: false)), [
        PaperStage.borrador,
        PaperStage.revisionInterna,
        PaperStage.aprobado,
        PaperStage.publicado,
      ]);
      const full = StudyConfig(externalReview: true, participantValidation: true);
      expect(nextPaperStage(PaperStage.revisionInterna, full), PaperStage.revisionExterna);
      expect(nextPaperStage(PaperStage.revisionExterna, full), PaperStage.validacionParticipantes);
      expect(nextPaperStage(PaperStage.publicado, full), isNull);
    });

    test('el estudio no se salta pasos', () {
      expect(canTransition(StudyStatus.borrador, StudyStatus.preregistrado), isTrue);
      expect(canTransition(StudyStatus.borrador, StudyStatus.reclutando), isFalse);
      expect(canTransition(StudyStatus.enRevision, StudyStatus.analisis), isTrue);
      expect(canTransition(StudyStatus.cancelado, StudyStatus.borrador), isFalse);
      expect(StudyStatusX.parse('en_curso'), StudyStatus.enCurso);
    });
  });

  group('Funcionalidades', () {
    const beta = LabFeature(key: 'x', name: 'X', stage: FeatureStage.beta, studyIds: ['s1']);
    test('beta: solo inscritos a un estudio en curso, y el laboratorio', () {
      expect(featureVisible(feature: beta, isLabMember: false, enrolledStudyIds: {'s1'}, liveStudyIds: {'s1'}), isTrue);
      expect(featureVisible(feature: beta, isLabMember: false, enrolledStudyIds: {'s1'}, liveStudyIds: {}), isFalse);
      expect(featureVisible(feature: beta, isLabMember: false, enrolledStudyIds: {}, liveStudyIds: {'s1'}), isFalse);
      expect(featureVisible(feature: beta, isLabMember: true, enrolledStudyIds: {}, liveStudyIds: {}), isTrue);
    });
    test('oficial para todos; retirada para nadie', () {
      const of = LabFeature(key: 'x', name: 'X', stage: FeatureStage.oficial);
      const ret = LabFeature(key: 'x', name: 'X', stage: FeatureStage.retirada, studyIds: ['s1']);
      expect(featureVisible(feature: of, isLabMember: false, enrolledStudyIds: {}, liveStudyIds: {}), isTrue);
      expect(featureVisible(feature: ret, isLabMember: true, enrolledStudyIds: {'s1'}, liveStudyIds: {'s1'}), isFalse);
    });
  });

  group('Nombres en clave', () {
    test('no repite y, si se agota el banco, numera', () {
      final taken = <String>{};
      for (var i = 0; i < kCodenameBank.length; i++) {
        taken.add(pickCodename(taken, random: Random(i)));
      }
      expect(taken.length, kCodenameBank.length);
      expect(pickCodename(taken, random: Random(1)), endsWith(' 2'));
      expect(kCodenameBank.toSet().length, kCodenameBank.length);
    });
  });

  group('Encuestas', () {
    test('valida cada tipo de respuesta', () {
      const lik = SurveyQuestion(id: 'a', type: SurveyQuestionType.likert5, text: '');
      const one = SurveyQuestion(id: 'b', type: SurveyQuestionType.single, text: '', options: ['x', 'y']);
      const opt = SurveyQuestion(id: 'c', type: SurveyQuestionType.text, text: '', required: false);
      expect(lik.accepts(3), isTrue);
      expect(lik.accepts(6), isFalse);
      expect(lik.accepts(null), isFalse);
      expect(one.accepts('z'), isFalse);
      expect(opt.accepts(null), isTrue);
    });
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:othli_front/labs/lab_title.dart';
import 'package:othli_front/services/labs_invite.dart';
import 'package:othli_front/widgets/labs_invite_page.dart';

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  group('LabsInvite.shouldShow', () {
    test('la primera vez de cada momento sí se muestra', () {
      expect(LabsInvite.shouldShow(null, LabsInviteMoment.aiTrip, isLabParticipant: false, answeredStudy: false), isTrue);
      expect(LabsInvite.shouldShow({'ai_trip': 1}, LabsInviteMoment.aiGroup, isLabParticipant: false, answeredStudy: false), isTrue);
    });

    test('cada momento solo una vez', () {
      expect(LabsInvite.shouldShow({'ai_trip': 1}, LabsInviteMoment.aiTrip, isLabParticipant: false, answeredStudy: false), isFalse);
      expect(LabsInvite.shouldShow({'ai_group': 1}, LabsInviteMoment.aiGroup, isLabParticipant: false, answeredStudy: false), isFalse);
    });

    test('quien aceptó, ya es tester o ya contestó no vuelve a ser molestado', () {
      for (final m in LabsInviteMoment.values) {
        expect(LabsInvite.shouldShow({'accepted': 1}, m, isLabParticipant: false, answeredStudy: false), isFalse);
        expect(LabsInvite.shouldShow({'done': 1}, m, isLabParticipant: false, answeredStudy: false), isFalse);
        expect(LabsInvite.shouldShow(null, m, isLabParticipant: true, answeredStudy: false), isFalse);
        expect(LabsInvite.shouldShow(null, m, isLabParticipant: false, answeredStudy: true), isFalse);
      }
    });
  });

  test('isAiTrip: viajes que salieron de una opción elegida de la IA', () {
    expect(LabsInvite.isAiTrip(recommendationJobId: 'job_1'), isTrue);
    expect(LabsInvite.isAiTrip(recommendedPoiIds: const ['a']), isTrue);
    expect(LabsInvite.isAiTrip(), isFalse);
    expect(LabsInvite.isAiTrip(recommendationJobId: ''), isFalse);
  });

  test('withLabTitle agrega Altepetlahtolli sin perder los demás', () {
    expect(LabTitle.withLabTitle(null), ['viajero', kLabTitleId]);
    expect(LabTitle.withLabTitle(['viajero', 'cronista']), ['viajero', 'cronista', kLabTitleId]);
    expect(LabTitle.withLabTitle(['viajero', kLabTitleId]), ['viajero', kLabTitleId]);
  });

  Future<bool?> openInvite(WidgetTester tester, Future<void> Function() onAccept,
      {LabsInviteMoment moment = LabsInviteMoment.aiTrip}) async {
    bool? result;
    var done = false;
    await tester.binding.setSurfaceSize(const Size(420, 900));
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async {
                result = await Navigator.of(context).push<bool>(MaterialPageRoute(
                  fullscreenDialog: true,
                  builder: (_) => LabsInvitePage(moment: moment, onAccept: onAccept),
                ));
                done = true;
              },
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    addTearDown(() => tester.binding.setSurfaceSize(null));
    return done ? result : null;
  }

  testWidgets('aceptar registra como tester y devuelve true', (tester) async {
    var accepted = 0;
    await openInvite(tester, () async => accepted++);
    expect(find.text('Ya armaste tu primer viaje con la IA de Ohtli'), findsOneWidget);
    expect(find.textContaining(kLabTitleName), findsWidgets);
    await tester.ensureVisible(find.text('Acepto, quiero responder'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Acepto, quiero responder'));
    await tester.pumpAndSettle();
    expect(accepted, 1);
    expect(find.byType(LabsInvitePage), findsNothing);
  });

  testWidgets('"Ahora no" cierra sin registrar', (tester) async {
    var accepted = 0;
    await openInvite(tester, () async => accepted++, moment: LabsInviteMoment.aiGroup);
    expect(find.text('Ya armaste tu primer plan con IA con tus amigos'), findsOneWidget);
    await tester.ensureVisible(find.text('Ahora no'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ahora no'));
    await tester.pumpAndSettle();
    expect(accepted, 0);
    expect(find.byType(LabsInvitePage), findsNothing);
  });

  testWidgets('si el alta falla, avisa y deja reintentar', (tester) async {
    await openInvite(tester, () async => throw Exception('sin red'));
    await tester.ensureVisible(find.text('Acepto, quiero responder'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Acepto, quiero responder'));
    await tester.pumpAndSettle();
    expect(find.byType(LabsInvitePage), findsOneWidget);
    expect(find.textContaining('No pudimos registrarte'), findsOneWidget);
  });
}

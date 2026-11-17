import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:othli_front/screens/admin/app_feedback_page.dart';
import 'package:othli_front/services/feedback_service.dart';

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  final sample = AppFeedback.fromMap('f1', {
    'uid': 'uid_muy_largo_1234567890abcdef',
    'message': 'El mapa se cierra cuando elijo la segunda ruta y no puedo volver. ' * 4,
    'category': 'bug',
    'screen': 'planear_con_ia',
    'status': 'new',
    'appVersion': '1.1.0',
    'context': {'paso': 'routeTriadCarousel', 'job_id': 'job_abc'},
    'user': {'nombre': 'Ana López', 'correo': 'ana@correo.test', 'correoVerificado': 'sí', 'acceso': 'password, google.com'},
    'device': {
      'navegador': 'Safari · iOS',
      'pantalla': '390x844',
      'red': '4g · 10 Mb/s',
      'userAgent': 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0',
    },
    'system': {'version': '1.1.0', 'tema': 'oscuro', 'ruta': '/mis-viajes'},
    'errors': [
      {'at': '2026-11-16T10:00:00.000', 'where': 'rendering library', 'message': 'A RenderFlex overflowed by 12 pixels on the right.'},
    ],
  });

  for (final size in const [Size(375, 800), Size(1000, 800)]) {
    testWidgets('el detalle de un comentario se ve sin desbordes en ${size.width.toInt()} px', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: AppFeedbackDetail(feedback: sample))));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('Marcar revisado'), findsOneWidget);
      expect(find.text('Responder'), findsOneWidget);
      expect(find.text('ERRORES RECIENTES · 1'), findsOneWidget);
      expect(find.text('DISPOSITIVO'), findsOneWidget);
    });
  }
}

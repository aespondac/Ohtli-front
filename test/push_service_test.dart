import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:othli_front/services/push_service.dart';
import 'package:othli_front/widgets/push_toggle.dart';

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: SizedBox(width: 440, child: child)));

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;
  final status = PushService.instance.status;

  test('la clave VAPID está configurada', () {
    expect(PushService.instance.configured, isTrue);
    expect(kFcmVapidKey, startsWith('B'));
  });

  group('activar desde Avisos y Cuenta', () {
    tearDown(() => status.value = PushStatus.unsupported);

    testWidgets('banner: invita a activar, explica iPhone y se esconde si ya están', (tester) async {
      status.value = PushStatus.off;
      await tester.pumpWidget(_host(const PushInviteBanner()));
      expect(find.text('Recibe tus avisos aunque Ohtli esté cerrado'), findsOneWidget);
      expect(find.text('Activar'), findsOneWidget);
      expect(find.text('Ahora no'), findsOneWidget);

      status.value = PushStatus.needsInstall;
      await tester.pump();
      expect(find.text('Avisos en iPhone'), findsOneWidget);
      expect(find.text('Activar'), findsNothing);
      expect(find.text('Entendido'), findsOneWidget);

      for (final s in [PushStatus.on, PushStatus.denied, PushStatus.unsupported]) {
        status.value = s;
        await tester.pump();
        expect(find.text('Activar'), findsNothing, reason: s.name);
      }
    });

    testWidgets('interruptor: refleja el estado y solo se mueve cuando se puede', (tester) async {
      status.value = PushStatus.on;
      await tester.pumpWidget(_host(const PushSettingTile()));
      expect(find.text('Avisos en este dispositivo'), findsOneWidget);
      expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value, isTrue);
      expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).onChanged, isNotNull);

      status.value = PushStatus.denied;
      await tester.pump();
      expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value, isFalse);
      expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).onChanged, isNull);
      expect(find.textContaining('Bloqueaste'), findsOneWidget);
    });
  });

  group('plataforma del dispositivo', () {
    test('iPhone, iPad (que se presenta como Mac), Android y escritorio', () {
      expect(pushPlatformOf('Mozilla/5.0 (iPhone; CPU iPhone OS 18_1 like Mac OS X) AppleWebKit/605.1.15'), 'web-ios');
      expect(pushPlatformOf('Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15', maxTouchPoints: 5), 'web-ios');
      expect(pushPlatformOf('Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15'), 'web-desktop');
      expect(pushPlatformOf('Mozilla/5.0 (Linux; Android 15; Pixel 9) AppleWebKit/537.36 Chrome/131.0 Mobile'), 'web-android');
      expect(pushPlatformOf('Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/131.0'), 'web-desktop');
    });
  });

  group('cuándo reescribir el token', () {
    const day = 24 * 60 * 60 * 1000;
    test('nuevo, distinto, de otra cuenta o de hace más de un día', () {
      expect(pushTokenNeedsSync(token: 't', uid: 'a', nowMs: 1000), isTrue);
      expect(pushTokenNeedsSync(token: 't2', uid: 'a', savedToken: 't', savedUid: 'a', savedAtMs: 0, nowMs: 1000), isTrue);
      expect(pushTokenNeedsSync(token: 't', uid: 'b', savedToken: 't', savedUid: 'a', savedAtMs: 0, nowMs: 1000), isTrue);
      expect(pushTokenNeedsSync(token: 't', uid: 'a', savedToken: 't', savedUid: 'a', savedAtMs: 0, nowMs: day + 1), isTrue);
    });
    test('el mismo token del mismo día no se vuelve a escribir', () {
      expect(pushTokenNeedsSync(token: 't', uid: 'a', savedToken: 't', savedUid: 'a', savedAtMs: 0, nowMs: day - 1), isFalse);
    });
  });

  test('cada estado tiene su explicación', () {
    for (final s in PushStatus.values) {
      expect(pushStatusHint(s), isNotEmpty);
    }
    expect(pushStatusHint(PushStatus.needsInstall), contains('pantalla de inicio'));
  });
}

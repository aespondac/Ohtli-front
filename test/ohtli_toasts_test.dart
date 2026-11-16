import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:othli_front/widgets/ohtli_toasts.dart';

Widget _app(void Function(BuildContext) onTap) => MaterialApp(
      builder: (context, child) => OhtliToastMessenger(child: child!),
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(onPressed: () => onTap(context), child: const Text('Avisar')),
          ),
        ),
      ),
    );

void main() {
  // Sin red en las pruebas: las fuentes de Google se quedan con la de respaldo
  GoogleFonts.config.allowRuntimeFetching = false;

  testWidgets('showSnackBar sale como toast arriba y se va solo', (tester) async {
    await tester.pumpWidget(_app((c) => ScaffoldMessenger.of(c).showSnackBar(const SnackBar(content: Text('Guardado')))));
    await tester.tap(find.text('Avisar'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Guardado'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing, reason: 'ya no hay barra abajo');
    expect(tester.getTopLeft(find.text('Guardado')).dy, lessThan(120), reason: 'está arriba');
    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Guardado'), findsNothing);
  });

  testWidgets('la acción del aviso funciona y lo cierra', (tester) async {
    var undone = false;
    await tester.pumpWidget(_app((c) => ScaffoldMessenger.of(c).showSnackBar(SnackBar(
          content: const Text('Eliminado'),
          action: SnackBarAction(label: 'Deshacer', onPressed: () => undone = true),
        ))));
    await tester.tap(find.text('Avisar'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Deshacer'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(undone, isTrue);
    expect(find.text('Eliminado'), findsNothing);
  });

  testWidgets('hideCurrentSnackBar cierra el toast y se pueden encadenar varios', (tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(_app((c) => ctx = c));
    await tester.tap(find.text('Avisar'));
    final m = ScaffoldMessenger.of(ctx);
    m.showSnackBar(const SnackBar(content: Text('Uno')));
    m.showSnackBar(const SnackBar(content: Text('Dos')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Uno'), findsOneWidget);
    expect(find.text('Dos'), findsOneWidget);
    m.hideCurrentSnackBar();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Dos'), findsNothing);
    expect(find.text('Uno'), findsOneWidget);
  });

  testWidgets('con un toast visible, el resto de la pantalla sigue respondiendo', (tester) async {
    var taps = 0;
    await tester.pumpWidget(_app((c) {
      taps++;
      ScaffoldMessenger.of(c).showSnackBar(const SnackBar(content: Text('Hola')));
    }));
    await tester.tap(find.text('Avisar'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Hola'), findsOneWidget);
    await tester.tap(find.text('Avisar'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(taps, 2);
  });
}

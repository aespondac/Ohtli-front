import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:othli_front/labs/research/lab_iam.dart';
import 'package:othli_front/labs/shell/lab_resource_page.dart';

/// Contador con estado: si se destruye, vuelve a 0.
class _Counter extends StatefulWidget {
  const _Counter();
  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  int n = 0;
  @override
  Widget build(BuildContext context) => TextButton(onPressed: () => setState(() => n++), child: Text('corrida $n'));
}

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;
  const tabs = [
    LabTabSpec('run', 'Ejecutar', Icons.play_arrow, _run, keepAlive: true),
    LabTabSpec('config', 'Configuración', Icons.settings, _config),
  ];

  test('pestaña y sección desde la ubicación', () {
    expect(labTabOf(null, tabs), 'run');
    expect(labTabOf('config.iam', tabs), 'config');
    expect(labTabOf('nada', tabs), 'run');
    expect(labSectionOf('config.iam'), 'iam');
    expect(labSectionOf('config'), isNull);
    expect(labSectionOf(null), isNull);
  });

  Widget host(String? tab, ValueChanged<String> onTab) => MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: LabResourcePage(
              breadcrumbs: const [('Proyecto', null), ('Experimentos', null), ('Batería', null)],
              title: 'Batería de 30',
              icon: Icons.science,
              role: LabIamRole.editor,
              tabs: tabs,
              tab: tab,
              onTab: onTab,
            ),
          ),
        ),
      );

  void desktop(WidgetTester tester) {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  testWidgets('la pestaña de ejecución sigue viva al ir a Configuración', (tester) async {
    desktop(tester);
    String? tab;
    await tester.pumpWidget(StatefulBuilder(builder: (context, set) => host(tab, (t) => set(() => tab = t))));
    expect(find.text('Tu rol: Editor'), findsOneWidget);
    await tester.tap(find.text('corrida 0'));
    await tester.pump();
    expect(find.text('corrida 1'), findsOneWidget);

    await tester.tap(find.text('Configuración'));
    await tester.pumpAndSettle();
    expect(find.text('Sección general'), findsOneWidget);
    expect(find.text('corrida 1'), findsNothing); // oculta, no visible

    await tester.tap(find.text('Ejecutar'));
    await tester.pumpAndSettle();
    expect(find.text('corrida 1'), findsOneWidget); // no se reinició
  });

  testWidgets('Configuración abre la sección pedida', (tester) async {
    desktop(tester);
    String? section;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: LabSettingsLayout(
          current: 'audit',
          onSection: (s) => section = s,
          sections: [
            ('iam', 'Accesos (IAM)', () => const Text('cuerpo iam')),
            ('audit', 'Bitácora', () => const Text('cuerpo bitácora')),
          ],
        ),
      ),
    ));
    expect(find.text('cuerpo bitácora'), findsOneWidget);
    await tester.tap(find.text('Accesos (IAM)'));
    expect(section, 'iam');
  });
}

Widget _run() => const _Counter();
Widget _config() => const Text('Sección general');

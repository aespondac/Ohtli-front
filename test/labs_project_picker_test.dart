import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:othli_front/labs/research/lab_iam.dart';
import 'package:othli_front/labs/research/lab_models.dart';
import 'package:othli_front/labs/shell/lab_location_store.dart';
import 'package:othli_front/labs/shell/lab_project_picker.dart';

const _tt = LabProject(id: 'trabajo_terminal', name: 'Trabajo Terminal');
const _plat = LabProject(id: 'ohtli_plataforma', name: 'Ohtli.quest (plataforma)');
const _secret = LabProject(id: 'x9', name: 'Proyecto Tecolotl', confidential: true, codename: 'Tecolotl');

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  test('búsqueda por nombre visible, nombre en clave o id', () {
    final all = [_tt, _plat, _secret];
    expect(filterProjects(all, ''), all);
    expect(filterProjects(all, 'terminal'), [_tt]);
    expect(filterProjects(all, 'PLATAFORMA'), [_plat]);
    expect(filterProjects(all, 'tecolotl'), [_secret]);
    expect(filterProjects(all, 'x9'), [_secret]);
    expect(filterProjects(all, 'nada'), isEmpty);
  });

  test('recientes primero y el resto por nombre', () {
    expect(orderProjects([_tt, _secret, _plat], ['x9']).map((p) => p.id), ['x9', 'ohtli_plataforma', 'trabajo_terminal']);
    expect(orderProjects([_tt, _plat], ['borrado', 'trabajo_terminal']).map((p) => p.id), ['trabajo_terminal', 'ohtli_plataforma']);
  });

  test('recientes: sin repetidos y como máximo cinco', () {
    final r = <String>[];
    for (final id in ['a', 'b', 'c', 'a', 'd', 'e', 'f']) {
      updateRecent(r, id);
    }
    expect(r, ['f', 'e', 'd', 'a', 'c']);
  });

  test('la memoria guarda el último proyecto', () {
    final s = MemoryLocationStore();
    s.save('p:a/overview', projectId: 'a');
    s.save('participa');
    expect(s.lastProjectId, 'a');
    expect(s.recentProjects, ['a']);
    expect(s.saved, ['p:a/overview', 'participa']);
  });

  testWidgets('el selector filtra, muestra el rol y devuelve el proyecto elegido', (tester) async {
    LabPickerResult? result;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showLabProjectPicker(
                context,
                projects: const [_tt, _plat, _secret],
                recent: const ['trabajo_terminal'],
                currentId: 'ohtli_plataforma',
                roleOf: (p) => p.id == 'trabajo_terminal' ? LabIamRole.editor : LabIamRole.viewer,
              );
            },
            child: const Text('abrir'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();

    expect(find.text('Selecciona un proyecto'), findsOneWidget);
    expect(find.text('Editor'), findsOneWidget);
    expect(find.text('Confidencial'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'teco');
    await tester.pumpAndSettle();
    expect(find.text('Trabajo Terminal'), findsNothing);
    expect(find.text('Proyecto Tecolotl'), findsOneWidget);

    await tester.tap(find.text('Proyecto Tecolotl'));
    await tester.pumpAndSettle();
    expect(result, isA<LabPickedProject>());
    expect((result! as LabPickedProject).id, 'x9');
  });

  testWidgets('"Crear proyecto" devuelve la acción de crear', (tester) async {
    LabPickerResult? result;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showLabProjectPicker(context,
                  projects: const [_tt], recent: const [], currentId: null, roleOf: (_) => LabIamRole.owner);
            },
            child: const Text('abrir'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Crear proyecto'));
    await tester.pumpAndSettle();
    expect(result, isA<LabCreateProject>());
  });
}

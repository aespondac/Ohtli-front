import 'package:flutter_test/flutter_test.dart';
import 'package:othli_front/labs/research/lab_import.dart';

void main() {
  const names = {'p1': 'Movilidad', 'p2': 'Gastronomía'};
  LabImportSplit split(List<LabImportable> items, {List<String> selected = const []}) => splitImportables(
        projectId: 'p1',
        builtins: const {'bateria_30': 'Batería de 30'},
        items: items,
        projectNames: names,
        selected: selected,
      );

  test('del proyecto: integrados y los suyos', () {
    final s = split(const [LabImportable(id: 'e1', title: 'Rutas en bici', projectId: 'p1')]);
    expect(s.own, {'bateria_30': 'Batería de 30', 'e1': 'Rutas en bici'});
    expect(s.shared, isEmpty);
  });

  test('de otros proyectos solo lo compartido y nunca lo clasificado', () {
    final s = split(const [
      LabImportable(id: 'e2', title: 'Tacos', projectId: 'p2', shared: true),
      LabImportable(id: 'e3', title: 'Privado', projectId: 'p2'),
      LabImportable(id: 'e4', title: 'Secreto', projectId: 'p2', shared: true, confidential: true),
      LabImportable(id: 'e5', title: 'Viejo', projectId: null),
    ]);
    expect(s.shared, {'e2': 'Tacos · de Gastronomía', 'e5': 'Viejo · biblioteca pública'});
    expect(s.own.keys, ['bateria_30']);
  });

  test('si el origen deja de compartirlo, sigue en el estudio con aviso', () {
    final s = split(const [LabImportable(id: 'e3', title: 'Tacos', projectId: 'p2')], selected: const ['e3']);
    expect(s.stale, {'e3': 'Tacos'});
    expect(s.labelOf('e3'), 'Tacos (ya no está compartido)');
    expect(s.labelOf('bateria_30'), 'Batería de 30');
    expect(s.labelOf('borrado'), 'borrado');
  });

  test('un integrado del proyecto no se duplica aunque tenga documento', () {
    final s = split(const [LabImportable(id: 'bateria_30', title: 'Otro título', projectId: 'p1')]);
    expect(s.own, {'bateria_30': 'Batería de 30'});
  });
}

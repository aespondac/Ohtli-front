import 'package:flutter_test/flutter_test.dart';
import 'package:othli_front/screens/lab/experiments/taste_vector_experiment_page.dart';

void main() {
  test('usa oep_axes cuando el lugar los trae', () {
    final axes = poiAxesOf({
      'oep_axes': {'vocacion_cultural': 'Museo', 'entorno_urbano': 'Caminable'},
      'semantic_description': '[EJE 1 - X]: otra cosa',
    });
    expect(axes, {'vocacion_cultural': 'Museo', 'entorno_urbano': 'Caminable'});
  });

  test('sin oep_axes, separa los 4 ejes de semantic_description (como los manda el motor)', () {
    final axes = poiAxesOf({
      'oep_axes': {},
      'semantic_description': '[EJE 1 - VOCACIÓN CULTURAL Y GASTRONÓMICA]: Su vocación es artística.\n'
          '[EJE 2 - ATMÓSFERA Y EXPERIENCIA SENSORIAL]: Serena y reflexiva.\n'
          '[EJE 3 - DINÁMICA SOCIAL Y PERFIL DE VISITANTE]: Parejas y solitarios.\n'
          '[EJE 4 - MICRO-ENTORNO URBANO Y CAMINABILIDAD]: Centro peatonal.',
    });
    expect(axes['vocacion_cultural'], 'Su vocación es artística.');
    expect(axes['atmosfera_sensorial'], 'Serena y reflexiva.');
    expect(axes['dinamica_social'], 'Parejas y solitarios.');
    expect(axes['entorno_urbano'], 'Centro peatonal.');
  });

  test('sin datos devuelve vacío', () {
    expect(poiAxesOf({}), isEmpty);
    expect(poiAxesOf({'semantic_description': 'texto libre sin ejes'}), isEmpty);
  });
}

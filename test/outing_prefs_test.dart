import 'package:flutter_test/flutter_test.dart';
import 'package:othli_front/services/outing_prefs.dart';
import 'package:othli_front/services/trip_transfers.dart';

void main() {
  group('OutingPref', () {
    test('lee la lista nueva', () {
      expect(OutingPref.companion.read({'social_companions': ['solo', 'amigos'], 'social_companion': 'solo'}),
          ['solo', 'amigos']);
    });

    test('perfiles viejos con un solo valor siguen leyéndose', () {
      expect(OutingPref.timeWindow.read({'preferred_time_window': 'noche'}), ['noche']);
      expect(OutingPref.pace.read({'travel_pace': ['relajado']}), ['relajado']);
    });

    test('sin datos usa el valor por defecto', () {
      expect(OutingPref.transport.read(null), ['caminata']);
      expect(OutingPref.transport.read({'transport_preferences': []}), ['caminata']);
    });

    test('guarda la lista y la primera opción en el campo viejo', () {
      expect(OutingPref.transport.write(['bicicleta', 'auto', 'bicicleta']), {
        'transport_preferences': ['bicicleta', 'auto'],
        'transport_preference': 'bicicleta',
      });
      expect(OutingPref.pace.write(const []), {'travel_paces': ['moderado'], 'travel_pace': 'moderado'});
    });

    test('joinOptions', () {
      expect(joinOptions(['solo']), 'solo');
      expect(joinOptions(['solo', 'amigos', 'familia']), 'solo, amigos y familia');
    });
  });

  test('plannerModeFromPreferences', () {
    expect(plannerModeFromPreferences(['bicicleta']), 'bike');
    expect(plannerModeFromPreferences(['caminata', 'transporte_publico']), 'mixto');
    expect(plannerModeFromPreferences(const []), 'walking');
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:othli_front/widgets/place_details_form.dart';
import 'package:othli_front/services/poi_suggestion_service.dart';

void main() {
  test('un formulario vacío no envía nada', () {
    final d = PlaceDetailsDraft();
    expect(d.isEmpty, isTrue);
    expect(d.toMap(), isEmpty);
  });

  test('solo se envía lo que la persona respondió ("No sé" se omite)', () {
    final d = PlaceDetailsDraft()
      ..offers = 'café de especialidad,  postres , '
      ..vibes.addAll(['tranquilo', 'bohemio'])
      ..idealFor.add('pareja')
      ..priceLevel = 2
      ..openingHours = ' L-D 9:00-20:00 '
      ..tip = 'Pide el café de olla';
    d.yesNo['wheelchair_accessible'] = true;
    d.yesNo['musica_en_vivo'] = false;
    final m = d.toMap();
    expect(m['subcategories'], ['café de especialidad', 'postres']);
    expect(m['vibe_tags'], containsAll(['tranquilo', 'bohemio']));
    expect(m['ideal_for'], ['pareja']);
    expect(m['price_level'], 2);
    expect(m['opening_hours'], 'L-D 9:00-20:00');
    expect(m['wheelchair_accessible'], isTrue);
    expect(m['musica_en_vivo'], isFalse);
    expect(m.containsKey('consumo_alcohol'), isFalse); // quedó en "No sé"
    expect(m['tips'], ['Pide el café de olla']);
  });

  test('los campos coinciden con los que aceptan las reglas y el motor', () {
    final d = PlaceDetailsDraft()
      ..offers = 'x'
      ..vibes.add('tranquilo')
      ..idealFor.add('solo')
      ..priceLevel = 0
      ..openingHours = 'h'
      ..tip = 't';
    for (final k in kPlaceYesNo.keys) {
      d.yesNo[k] = true;
    }
    for (final key in d.toMap().keys) {
      expect(kSuggestionDetailKeys.contains(key), isTrue, reason: '$key no está permitido');
    }
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:othli_front/services/notification_text.dart';

void main() {
  test('el aviso de rutas dice desde dónde salen', () {
    final job = {'origin_name': 'Coyoacán', 'result': {'options': [1, 2, 3]}};
    expect(itineraryJobMessage(job, failed: false), '¡Listo! Tienes 3 rutas con IA desde Coyoacán para elegir.');
    expect(itineraryJobMessage(job, failed: true), 'No pudimos terminar tus rutas desde Coyoacán. Intenta de nuevo.');
  });

  test('con el origen genérico usa lo que se pidió, recortado', () {
    final job = {
      'origin_name': 'Ciudad de México',
      'request': {'mood_text': 'Una tarde tranquila de museos y café con mi abuela en el centro'},
    };
    final label = itineraryJobLabel(job)!;
    expect(label, startsWith('para «Una tarde tranquila'));
    expect(label, endsWith('…»'));
  });

  test('sin nada que la distinga, el texto general', () {
    expect(itineraryJobMessage({'origin_name': 'Ciudad de México'}, failed: false), '¡Listo! Tienes 3 rutas con IA para elegir.');
  });

  test('avisos repetidos se agrupan en uno', () {
    expect(itineraryGroupedMessage('itinerary_ready', 3), contains('3 búsquedas'));
    expect(itineraryGroupedMessage('itinerary_failed', 2), startsWith('No pudimos terminar 2'));
  });
}

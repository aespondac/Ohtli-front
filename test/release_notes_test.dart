import 'package:flutter_test/flutter_test.dart';
import 'package:othli_front/models/trip_model.dart';
import 'package:othli_front/screens/trips/release_notes_admin_page.dart' show compareVersions;
import 'package:othli_front/screens/trips/trip_sample.dart';

void main() {
  group('Novedades de las notas de versión', () {
    PlaceSection item({String? tag}) => PlaceSection(
          id: 'n1',
          title: 'Traslados con un solo botón',
          description: '',
          rating: 0,
          mainPhotoUrl: '',
          secondaryPhotoUrls: const [],
          changeTag: tag,
        );

    test('la etiqueta se guarda y se lee', () {
      final map = item(tag: 'mejora').toMap();
      expect(map['changeTag'], 'mejora');
      expect(PlaceSection.fromMap(map).changeTag, 'mejora');
    });

    test('sin etiqueta no se escribe el campo', () {
      expect(item().toMap().containsKey('changeTag'), isFalse);
    });

    test('una etiqueta desconocida se ignora', () {
      final map = item().toMap()..['changeTag'] = 'otra';
      expect(PlaceSection.fromMap(map).changeTag, isNull);
    });

    test('copyWith cambia la etiqueta y conserva lo demás', () {
      final c = item(tag: 'nuevo').copyWith(changeTag: 'correccion');
      expect(c.changeTag, 'correccion');
      expect(c.title, 'Traslados con un solo botón');
      expect(item(tag: 'nuevo').copyWith(title: 'x').changeTag, 'nuevo');
    });
  });

  test('compareVersions ordena por número, no por texto', () {
    expect(compareVersions('1.10.0', '1.9.2'), greaterThan(0));
    expect(compareVersions('1.0.0', '1.0'), 0);
    expect(compareVersions('0.9.9', '1.0.0'), lessThan(0));
  });

  test('la muestra de notas de versión trae novedades de los tres tipos', () {
    final trip = TripSample.releaseNotes();
    expect(trip.isReleaseNotes, isTrue);
    expect(trip.version, isNotEmpty);
    final tags = TripSample.releaseNotesSections().whereType<PlaceSection>().map((p) => p.changeTag).toSet();
    expect(tags, containsAll(kReleaseTags.keys));
  });
}

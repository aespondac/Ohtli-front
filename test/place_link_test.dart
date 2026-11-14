import 'package:flutter_test/flutter_test.dart';
import 'package:othli_front/models/trip_model.dart';
import 'package:othli_front/config/admin.dart';

PlaceSection _place({String? poiId, String? poiSource}) => PlaceSection(
      id: 's1',
      title: 'Museo Frida Kahlo',
      description: '',
      rating: 5,
      mainPhotoUrl: '',
      secondaryPhotoUrls: const [],
      lat: 19.355,
      lng: -99.162,
      poiId: poiId,
      poiSource: poiSource,
    );

void main() {
  group('Vínculo de la parada con la base de Ohtli', () {
    test('un lugar sin poiId es genérico y no guarda campos de vínculo', () {
      final p = _place();
      expect(p.isGeneric, isTrue);
      final map = p.toMap();
      expect(map.containsKey('poiId'), isFalse);
      expect(map.containsKey('poiSource'), isFalse);
    });

    test('vinculado al catálogo se conserva al guardar y leer', () {
      final p = PlaceSection.fromMap(_place(poiId: 'osm_123', poiSource: kPlaceSourceCatalog).toMap());
      expect(p.poiId, 'osm_123');
      expect(p.isLinkedToCatalog, isTrue);
      expect(p.isSuggestion, isFalse);
    });

    test('una sugerencia se conserva como sugerencia', () {
      final p = PlaceSection.fromMap(_place(poiId: 'sug_abc', poiSource: kPlaceSourceSuggestion).toMap());
      expect(p.isSuggestion, isTrue);
      expect(p.isGeneric, isFalse);
    });

    test('paradas antiguas con poi_id del motor se leen como vinculadas al catálogo', () {
      final p = PlaceSection.fromMap({'id': 'x', 'type': 'place', 'title': 'Bellas Artes', 'poi_id': 'osm_9'});
      expect(p.poiId, 'osm_9');
      expect(p.isLinkedToCatalog, isTrue);
    });

    test('copyWith conserva el vínculo y clearPoi lo quita', () {
      final p = _place(poiId: 'osm_1', poiSource: kPlaceSourceCatalog);
      expect(p.copyWith(title: 'Otro nombre').poiId, 'osm_1');
      final cleared = p.copyWith(clearPoi: true);
      expect(cleared.poiId, isNull);
      expect(cleared.isGeneric, isTrue);
    });
  });

  test('solo el correo del superusuario es superusuario', () {
    expect(isSuperUserEmail('daniesponda120@gmail.com'), isTrue);
    expect(isSuperUserEmail(' DaniEsponda120@gmail.com '), isTrue);
    expect(isSuperUserEmail('otra@gmail.com'), isFalse);
    expect(isSuperUserEmail(null), isFalse);
  });
}

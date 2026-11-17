import 'package:flutter_test/flutter_test.dart';
import 'package:othli_front/services/public_profiles.dart';

void main() {
  test('claves por palabra, sin acentos ni mayúsculas, y del usertag', () {
    final keys = PublicProfiles.searchKeysFor('Alfredo Esponda Cervantes', 'alfredo.esponda');
    for (final k in ['al', 'alfredo', 'esp', 'esponda', 'cerv', 'alfredo.espon']) {
      expect(keys, contains(k));
    }
    // Igual que el motor (api/admin_places.py search_keys_for)
    expect(PublicProfiles.searchKeysFor('Ángel Núñez', null).take(3), ['an', 'ang', 'ange']);
    expect(PublicProfiles.searchKeysFor('', null), isEmpty);
    expect(PublicProfiles.fold('ÁNGEL'), 'angel');
  });
}

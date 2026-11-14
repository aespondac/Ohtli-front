import 'package:flutter_test/flutter_test.dart';
import 'package:othli_front/services/user_private_data.dart';

void main() {
  group('UserPrivateData.split', () {
    test('contacto, privacidad y perfil de gustos van al documento privado', () {
      final parts = UserPrivateData.split({
        'displayName': 'Ana',
        'photoURL': 'https://x/y.jpg',
        'email': 'ana@example.com',
        'phone': '5555555555',
        'addresses': [
          {'street': 'Calle 1'},
        ],
        'privacy_public': true,
        'taste_vector': [0.1, 0.2],
        'cultural_profile': {'a': 1},
      });
      expect(parts.public.keys, unorderedEquals(['displayName', 'photoURL']));
      expect(
        parts.private.keys,
        unorderedEquals(['email', 'phone', 'addresses', 'privacy_public', 'taste_vector', 'cultural_profile']),
      );
    });

    test('ningún dato sensible se queda en el perfil público', () {
      final data = {for (final f in UserPrivateData.fields) f: 'x'};
      final parts = UserPrivateData.split(data);
      expect(parts.public, isEmpty);
      expect(parts.private.length, UserPrivateData.fields.length);
    });

    test('la lista de campos privados incluye lo esencial', () {
      expect(
        UserPrivateData.fields,
        containsAll(['email', 'phone', 'addresses', 'taste_vector', 'embedding_vector', 'isDeleted']),
      );
    });
  });
}

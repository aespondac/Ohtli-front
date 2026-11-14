import 'package:flutter_test/flutter_test.dart';
import 'package:othli_front/services/app_url.dart';

void main() {
  group('AppUrl', () {
    test('cada pestaña tiene su ruta y se puede volver a leer', () {
      for (final e in AppUrl.homeTabPaths.entries) {
        expect(AppUrl.homeTabForPath(e.value), e.key, reason: e.value);
      }
      expect(AppUrl.homeTabForPath('/mis-viajes'), 1);
      expect(AppUrl.homeTabForPath('/lugares'), 5);
    });

    test('acepta mayúsculas, diagonal final y el alias /places', () {
      expect(AppUrl.homeTabForPath('/Lugares/'), 5);
      expect(AppUrl.homeTabForPath('/places'), 5);
      expect(AppUrl.homeTabForPath('/EXPLORAR'), 0);
    });

    test('rutas que no son pestañas', () {
      expect(AppUrl.homeTabForPath('/'), isNull);
      expect(AppUrl.homeTabForPath('/cuenta'), isNull);
      expect(AppUrl.homeTabForPath('/viajes'), isNull);
      expect(AppUrl.homeTabForPath('/lugaresx'), isNull);
    });

    test('normalize', () {
      expect(AppUrl.normalize(''), '/');
      expect(AppUrl.normalize('/'), '/');
      expect(AppUrl.normalize('/Mis-Viajes///'), '/mis-viajes');
    });

    test('ninguna pestaña choca con las reescrituras de Hosting', () {
      // firebase.json manda /viajes/**, /api/**, /v1/** y /health a funciones
      for (final path in AppUrl.homeTabPaths.values) {
        for (final reserved in ['/viajes', '/api', '/v1', '/health', '/__sso']) {
          expect(path == reserved || path.startsWith('$reserved/'), isFalse, reason: path);
        }
      }
      // rutas únicas
      expect(AppUrl.homeTabPaths.values.toSet().length, AppUrl.homeTabPaths.length);
    });
  });
}

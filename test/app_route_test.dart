import 'package:flutter_test/flutter_test.dart';
import 'package:othli_front/services/app_route.dart';

void main() {
  group('routeMatches', () {
    test('coincide por segmentos completos', () {
      expect(routeMatches('/news', path: '/news'), isTrue);
      expect(routeMatches('/news', path: '/news/mi-articulo'), isTrue);
      expect(routeMatches('/news', path: '/news/'), isTrue);
      expect(routeMatches('/labs/osrm', path: '/labs/osrm'), isTrue);
      expect(routeMatches('/labs/osrm', path: '/LABS/osrm'), isTrue);
    });

    test('un artículo no abre otra pantalla por contener su nombre', () {
      for (final r in ['/eval', '/lugares', '/places', '/privacidad', '/cookies', '/terminos-api', '/tyc', '/resultados']) {
        expect(routeMatches(r, path: '/news/evaluacion-con-usuarios-lugares-privacidad-cookies-terminos-api-tyc-resultados'), isFalse,
            reason: r);
      }
    });

    test('no coincide con prefijos de texto ni rutas anidadas', () {
      expect(routeMatches('/news', path: '/newsletter'), isFalse);
      expect(routeMatches('/tyc', path: '/labs/tyc'), isFalse);
      expect(routeMatches('/eval', path: '/evaluacion'), isFalse);
      expect(routeMatches('/', path: '/'), isFalse);
    });

    test('acepta rutas en el fragmento (#/labs/tyc)', () {
      expect(routeMatches('/labs/tyc', path: '/', fragment: '/labs/tyc'), isTrue);
      expect(routeMatches('/news', path: '/', fragment: '/news/x?y=1'), isTrue);
    });
  });

  group('newsSlugFrom', () {
    test('toma la ruta del artículo', () {
      expect(newsSlugFrom(path: '/news/evaluacion-con-usuarios'), 'evaluacion-con-usuarios');
      expect(newsSlugFrom(path: '/', fragment: '/news/abc-1'), 'abc-1');
    });

    test('sin artículo o con caracteres inválidos', () {
      expect(newsSlugFrom(path: '/news'), isNull);
      expect(newsSlugFrom(path: '/resultados'), isNull);
      expect(newsSlugFrom(path: '/news/<script>'), isNull);
    });
  });

  test('título por sitio', () {
    expect(appTitleForHost('labs.ohtli.quest'), 'Ohtli Labs');
    expect(appTitleForHost('lab.ohtli.quest'), 'Ohtli Labs');
    expect(appTitleForHost('api.ohtli.quest'), 'Ohtli API');
    expect(appTitleForHost('www.ohtli.quest'), 'Ohtli | El viaje empieza aquí');
  });
}

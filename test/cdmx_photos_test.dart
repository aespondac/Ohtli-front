import 'package:flutter_test/flutter_test.dart';
import 'package:othli_front/theme/cdmx_photos.dart';

const _url =
    'https://thumb.wikimedia.org/wikipedia/commons/thumb/c/c5/Palacio_de_Bellas_Artes_00_%282%29.JPG/1280px-Palacio_de_Bellas_Artes_00_%282%29.JPG';

String _width(String url) => RegExp(r'/(\d+)px-').firstMatch(url)!.group(1)!;

void main() {
  group('CdmxPhotos.sized', () {
    test('pide el ancho estándar más pequeño que cubre la foto', () {
      expect(_width(CdmxPhotos.sized(_url, 44, 2)), '250');
      expect(_width(CdmxPhotos.sized(_url, 200, 2)), '330');
      expect(_width(CdmxPhotos.sized(_url, 330, 3)), '500', reason: 'tarjeta en teléfono: 1.5x');
      expect(_width(CdmxPhotos.sized(_url, 420, 2)), '960');
      expect(_width(CdmxPhotos.sized(_url, 560, 2)), '1280');
    });

    test('solo usa anchos que Wikimedia sirve (640 responde 400)', () {
      for (var w = 10.0; w < 1400; w += 37) {
        final width = _width(CdmxPhotos.sized(_url, w, 1.5));
        expect(['250', '330', '500', '960', '1280'], contains(width), reason: '$w');
      }
    });

    test('nunca pide más grande que la original ni cambia el resto de la URL', () {
      expect(CdmxPhotos.sized(_url, 4000, 3), _url);
      final small = CdmxPhotos.sized(_url, 100, 1);
      expect(small.replaceFirst('/250px-', '/1280px-'), _url);
    });

    test('las fotos de 500 px se agrandan cuando hace falta (portadas)', () {
      final small = _url.replaceFirst('/1280px-', '/500px-');
      expect(_width(CdmxPhotos.sized(small, 560, 2)), '1280');
      expect(_width(CdmxPhotos.sized(small, 400, 2)), '960');
      expect(CdmxPhotos.sized(small, 240, 2), small);
    });

    test('las fotos por categoría vienen ligeras (500 px)', () {
      for (final u in CdmxPhotos.covers) {
        expect(u, contains('/500px-'));
      }
    });

    test('la densidad se limita a 2x', () {
      expect(CdmxPhotos.sized(_url, 200, 3), CdmxPhotos.sized(_url, 200, 2));
    });

    test('otras URLs se devuelven igual', () {
      const other = 'https://firebasestorage.googleapis.com/v0/b/x/o/foto.jpg?alt=media';
      expect(CdmxPhotos.sized(other, 100, 2), other);
      const noThumb = 'https://upload.wikimedia.org/wikipedia/commons/c/c5/Foto.JPG';
      expect(CdmxPhotos.sized(noThumb, 100, 2), noThumb);
    });

    test('todas las fotos del catálogo vienen a 500 px y se pueden reducir o agrandar', () {
      final all = [...CdmxPhotos.covers, for (final l in CdmxPhotos.byCategory.values) ...l];
      expect(all, isNotEmpty);
      for (final url in all) {
        expect(url, contains('/500px-'), reason: url);
        expect(_width(CdmxPhotos.sized(url, 100, 2)), '250', reason: url);
        expect(_width(CdmxPhotos.sized(url, 640, 2)), '1280', reason: url);
      }
    });
  });
}

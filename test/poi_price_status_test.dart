import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:othli_front/models/poi_model.dart';
import 'package:othli_front/widgets/poi_card.dart';
import 'package:othli_front/widgets/poi_status_badge.dart';

/// Lugares como los entrega hoy `/v1/pois` (El Bajío y Fonda Castillo, 14-nov-2026).
Map<String, dynamic> _elBajio() => {
      'poi_id': 'denue_10012148',
      'name': 'Restaurante el Bajio',
      'category': 'restaurant',
      'location': {'lat': 19.43, 'lng': -99.13},
      'price_mxn_avg': 400.0,
      'price_level': 3,
      'price_range_mxn': {'min': 200.0, 'max': 600.0},
      'price_source': 'google_rango',
      'price_is_estimate': false,
      'operational_status': 'operational',
    };

Map<String, dynamic> _fondaCastillo() => {
      'poi_id': 'denue_1000665',
      'name': 'Fonda Castillo',
      'category': 'restaurant',
      'location': {'lat': 19.43, 'lng': -99.13},
      'price_mxn_avg': 85.0,
      'price_level': 1,
      'price_range_mxn': null,
      'price_source': 'foursquare_nivel',
      'price_is_estimate': true,
      'operational_status': 'closed_temporarily',
    };

Widget _host(Widget child) => MaterialApp(
      home: Material(child: Center(child: child)),
    );

void main() {
  // Sin red en las pruebas: las fuentes caen a la del sistema
  GoogleFonts.config.allowRuntimeFetching = false;

  group('Poi: rango de precio', () {
    test('lee el rango de Google y no lo marca como estimado', () {
      final poi = Poi.fromMap(_elBajio());
      expect(poi.priceRangeMxn?.min, 200);
      expect(poi.priceRangeMxn?.max, 600);
      expect(poi.priceSource, 'google_rango');
      expect(poi.priceIsEstimate, isFalse);
      expect(poi.priceRangeLabel, '\$200–600 por persona');
      expect(poi.priceRangeEstimate, '\$200–600 por persona');
      expect(poi.priceShort, '\$200–600');
    });

    test('google_rango nunca se marca como estimado aunque llegue la bandera', () {
      final poi = Poi.fromMap({..._elBajio(), 'price_is_estimate': true});
      expect(poi.priceIsEstimate, isFalse);
      expect(poi.priceRangeEstimate.contains('estimado'), isFalse);
    });

    test('sin máximo se lee "desde" con separador de miles', () {
      final poi = Poi.fromMap({
        ..._elBajio(),
        'price_range_mxn': {'min': 1000, 'max': null},
      });
      expect(poi.priceShort, '\$1,000+');
      expect(poi.priceRangeLabel, '\$1,000+ por persona');
    });

    test('miles en ambos extremos y extremos iguales', () {
      expect(const PoiPriceRange(min: 500, max: 1000).label, '\$500–1,000');
      expect(const PoiPriceRange(min: 300, max: 300).label, '\$300');
    });

    test('un rango inválido o ausente se ignora y queda el precio de antes', () {
      for (final raw in [null, 'x', {'max': 300}, {'min': 500, 'max': 100}, {'min': -1}]) {
        final poi = Poi.fromMap({..._fondaCastillo(), 'price_range_mxn': raw});
        expect(poi.priceRangeMxn, isNull, reason: '$raw');
      }
      final poi = Poi.fromMap(_fondaCastillo());
      expect(poi.priceShort, '\$');
      expect(poi.priceIsEstimate, isTrue);
      expect(poi.priceRangeEstimate, contains('estimado'));
    });
  });

  group('Poi: estado del lugar', () {
    test('closed_temporarily se reconoce', () {
      final poi = Poi.fromMap(_fondaCastillo());
      expect(poi.operationalStatus, 'closed_temporarily');
      expect(poi.isClosedTemporarily, isTrue);
    });

    test('sin estado se toma como abierto', () {
      final data = _elBajio()..remove('operational_status');
      final poi = Poi.fromMap(data);
      expect(poi.operationalStatus, 'operational');
      expect(poi.isClosedTemporarily, isFalse);
      expect(Poi.fromMap(_elBajio()).isClosedTemporarily, isFalse);
    });
  });

  group('Tarjetas de lugar', () {
    for (final variant in PoiCardVariant.values) {
      testWidgets('${variant.name}: muestra el rango en lugar de los signos', (tester) async {
        final poi = Poi.fromMap(_elBajio());
        await tester.pumpWidget(_host(PoiCard(poi: poi, variant: variant, width: 360, height: variant == PoiCardVariant.compact ? 96 : 480)));
        expect(find.textContaining('\$200–600'), findsOneWidget);
        expect(find.textContaining('\$\$\$'), findsNothing);
        expect(find.text(kClosedTemporarilyLabel), findsNothing);
      });

      testWidgets('${variant.name}: avisa "Cerrado temporalmente"', (tester) async {
        final poi = Poi.fromMap(_fondaCastillo());
        await tester.pumpWidget(_host(PoiCard(poi: poi, variant: variant, width: 360, height: variant == PoiCardVariant.compact ? 96 : 480)));
        expect(find.byType(PoiClosedBadge), findsOneWidget);
        expect(find.text(kClosedTemporarilyLabel), findsOneWidget);
      });
    }
  });

  testWidgets('el aviso del detalle explica el cierre temporal', (tester) async {
    await tester.pumpWidget(_host(const SizedBox(width: 480, child: PoiClosedNotice())));
    expect(find.text(kClosedTemporarilyLabel), findsOneWidget);
    expect(find.textContaining('Confirma antes de ir'), findsOneWidget);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:othli_front/screens/trips/trip_sample.dart';
import 'package:othli_front/services/trip_pdf_builder.dart';
import 'package:pdf/widgets.dart' as pw;

TripPdfFonts _fallbackFonts() => TripPdfFonts(
      display: pw.Font.helveticaBold(),
      heading: pw.Font.helveticaBold(),
      headingBold: pw.Font.helveticaBold(),
      body: pw.Font.helvetica(),
      bodyMedium: pw.Font.helvetica(),
      bodySemiBold: pw.Font.helveticaBold(),
      bodyBold: pw.Font.helveticaBold(),
      bodyItalic: pw.Font.helveticaOblique(),
    );

void main() {
  for (final (stage, edition) in [
    (SampleStage.antes, TripPdfEdition.guide),
    (SampleStage.despues, TripPdfEdition.memory),
  ]) {
    test('${edition.name}: se genera aunque no haya red (sin mapa base ni fotos)', () async {
      final bytes = await TripPdfBuilder.build(
        trip: TripSample.trip(stage),
        sections: TripSample.sections(stage),
        fonts: _fallbackFonts(),
        fetch: (_) async => null,
        authorName: 'Ana López',
        edition: edition,
        nearby: (lat, lng) async => const [
          TripPdfNearby(name: 'Café de prueba', kind: 'Cafetería', meters: 120),
        ],
      );
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      expect(bytes.length, greaterThan(10000));
    });
  }

  test('guía antes y durante el viaje, crónica después', () {
    final now = DateTime(2026, 11, 15, 12);
    expect(TripPdfBuilder.editionFor(TripSample.trip(SampleStage.antes), now: DateTime(2000)), TripPdfEdition.guide);
    final despues = TripSample.trip(SampleStage.despues);
    expect(TripPdfBuilder.editionFor(despues, now: despues.travelDate!.add(const Duration(days: 2))), TripPdfEdition.memory);
    expect(now.year, 2026);
  });

  test('un viaje sin paradas también produce PDF', () async {
    final bytes = await TripPdfBuilder.build(
      trip: TripSample.trip(SampleStage.antes),
      sections: const [],
      fonts: _fallbackFonts(),
      fetch: (_) async => null,
    );
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  });

  test('montos con separador de miles', () {
    expect(TripPdfBuilder.money(1095), r'$1,095');
    expect(TripPdfBuilder.money(90), r'$90');
  });
}

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
  test('la guía de ruta se genera aunque no haya red (sin mapa base ni fotos)', () async {
    final bytes = await TripPdfBuilder.build(
      trip: TripSample.trip(SampleStage.antes),
      sections: TripSample.sections(SampleStage.antes),
      fonts: _fallbackFonts(),
      fetch: (_) async => null,
      authorName: 'Ana López',
    );
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    expect(bytes.length, greaterThan(10000));
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

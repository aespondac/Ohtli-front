import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/trip_model.dart';
import 'trip_pdf_builder.dart';

/// Guía de ruta en PDF de un viaje (portada, mapa tipo atlas, itinerario e índice).
/// El diseño vive en [TripPdfBuilder]; aquí se cargan tipografías e imágenes en la app.
class PdfExportService {
  PdfExportService._();

  static TripPdfFonts? _fonts;

  static Future<TripPdfFonts> _loadFonts() async {
    if (_fonts != null) return _fonts!;
    try {
      final f = await Future.wait([
        PdfGoogleFonts.outfitBlack(),
        PdfGoogleFonts.outfitExtraBold(),
        PdfGoogleFonts.outfitBold(),
        PdfGoogleFonts.interRegular(),
        PdfGoogleFonts.interMedium(),
        PdfGoogleFonts.interSemiBold(),
        PdfGoogleFonts.interBold(),
        PdfGoogleFonts.interItalic(),
      ]);
      return _fonts = TripPdfFonts(
        display: f[0],
        heading: f[1],
        headingBold: f[2],
        body: f[3],
        bodyMedium: f[4],
        bodySemiBold: f[5],
        bodyBold: f[6],
        bodyItalic: f[7],
      );
    } catch (_) {
      // Sin red para las fuentes: Helvetica, para que el PDF salga de todos modos
      return TripPdfFonts(
        display: pw.Font.helveticaBold(),
        heading: pw.Font.helveticaBold(),
        headingBold: pw.Font.helveticaBold(),
        body: pw.Font.helvetica(),
        bodyMedium: pw.Font.helvetica(),
        bodySemiBold: pw.Font.helveticaBold(),
        bodyBold: pw.Font.helveticaBold(),
        bodyItalic: pw.Font.helveticaOblique(),
      );
    }
  }

  static Future<Uint8List?> _fetch(String url) async {
    try {
      final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 12));
      return res.statusCode == 200 ? res.bodyBytes : null;
    } catch (_) {
      return null;
    }
  }

  /// Genera los bytes del PDF.
  static Future<Uint8List> generateTripPdf({
    required Trip trip,
    required List<TripSection> sections,
    String? authorName,
    List<String>? coAuthors,
    String? qrBaseUrl,
  }) async {
    return TripPdfBuilder.build(
      trip: trip,
      sections: sections,
      fonts: await _loadFonts(),
      fetch: _fetch,
      authorName: authorName,
      coAuthors: coAuthors,
      qrUrl: qrBaseUrl,
    );
  }

  /// Descarga el PDF en el navegador o lo comparte en el dispositivo.
  static Future<void> downloadTripPdf({
    required Trip trip,
    required List<TripSection> sections,
    String? authorName,
    List<String>? coAuthors,
    String? qrBaseUrl,
  }) async {
    final bytes = await generateTripPdf(
      trip: trip,
      sections: sections,
      authorName: authorName,
      coAuthors: coAuthors,
      qrBaseUrl: qrBaseUrl,
    );
    final clean = trip.title.trim().isNotEmpty
        ? trip.title.trim().replaceAll(RegExp(r'[^\w\s-]'), '').replaceAll(RegExp(r'\s+'), '_')
        : 'Guia_de_ruta';
    await Printing.sharePdf(bytes: bytes, filename: '${clean}_Ohtli.pdf');
  }

  /// Abre el diálogo de impresión con la vista previa del PDF.
  static Future<void> printTripPdf({
    required Trip trip,
    required List<TripSection> sections,
    String? authorName,
    List<String>? coAuthors,
    String? qrBaseUrl,
  }) async {
    await Printing.layoutPdf(
      name: 'Ohtli · ${trip.title}',
      onLayout: (PdfPageFormat format) => generateTripPdf(
        trip: trip,
        sections: sections,
        authorName: authorName,
        coAuthors: coAuthors,
        qrBaseUrl: qrBaseUrl,
      ),
    );
  }
}

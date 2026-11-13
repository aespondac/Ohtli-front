import 'dart:typed_data';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../models/trip_model.dart';
import 'trip_transfers.dart';

class PdfExportService {
  // Paleta de colores institucional Ohtli (Estilo Editorial Mexicano)
  static final PdfColor stormyTeal = PdfColor.fromHex('#2C666E');
  static final PdfColor onyx = PdfColor.fromHex('#0A090C');
  static final PdfColor cloudDancer = PdfColor.fromHex('#F7F6F3');
  static final PdfColor cantera = PdfColor.fromHex('#E4E1DA');
  static final PdfColor canteraBorder = PdfColor.fromHex('#D4CFC6');
  static final PdfColor cempasuchil = PdfColor.fromHex('#F4D06F');
  static final PdfColor xoconostle = PdfColor.fromHex('#BA3B46');

  // SVGs Institucionales vectoriales para garantizar fidelidad y evitar problemas de fuentes
  static const String _ohtliLogoSvg = '''
  <svg viewBox="0 0 177 53" width="70" height="21">
    <path d="M25.88,0.01C60.43,-1.03 60.12,53.07 25.88,52.23C-8.74,53.38 -8.51,-0.87 25.88,0.01ZM32.64,24.01C17.2,-1.04 18.91,3.21 19.69,28.98C34.3,52.46 33,49.06 32.64,24.02L32.64,24.01Z" fill="#2C666E"/>
    <path d="M25.85,23.32C29.52,23.11 29.49,29.11 25.85,28.93C22.17,29.15 22.2,23.13 25.85,23.32Z" fill="#2C666E"/>
    <g transform="matrix(1,0,0,1,43,0)">
      <path d="M70.79,50.67C67.12,50.67 64.22,49.82 62.1,48.11C59.98,46.4 58.93,43.61 58.93,39.75L58.93,25.73C58.93,24.81 58.73,24.12 58.32,23.67C57.91,23.22 57.44,22.85 56.9,22.56C56.36,22.27 55.89,21.92 55.48,21.5C55.07,21.08 54.87,20.44 54.87,19.58C54.87,18.72 55.18,18.01 55.8,17.5C56.42,17 57.15,16.74 57.99,16.74L59.44,16.74C60.06,16.74 60.68,16.42 61.29,15.79C61.9,15.16 62.52,14.37 63.16,13.42C63.79,12.47 64.46,11.53 65.16,10.6C65.86,9.67 66.6,8.88 67.4,8.25C68.19,7.62 69.07,7.3 70.01,7.3C71.08,7.3 71.92,7.6 72.52,8.2C73.12,8.8 73.42,9.64 73.42,10.71L73.42,16.74L80.74,16.74C81.56,16.74 82.25,16.93 82.83,17.32C83.41,17.71 83.7,18.35 83.7,19.25C83.7,20.45 83.32,21.37 82.56,21.99C81.8,22.61 80.88,23.03 79.8,23.23C78.73,23.43 77.72,23.54 76.77,23.54L73.42,23.54L73.42,36.3C73.42,37.35 73.62,38.35 74.03,39.28C74.44,40.21 75.28,40.68 76.54,40.68C77.38,40.68 78.09,40.44 78.68,39.95C79.27,39.47 79.83,38.99 80.36,38.52C80.89,38.05 81.45,37.81 82.05,37.81C82.61,37.81 83,38.08 83.23,38.62C83.46,39.16 83.57,39.64 83.57,40.07C83.57,42.24 82.91,44.12 81.6,45.71C80.29,47.3 78.65,48.52 76.69,49.38C74.72,50.24 72.75,50.67 70.78,50.67L70.79,50.67Z" fill="#2C666E"/>
    </g>
    <g transform="matrix(1,0,0,1,-33,0)">
      <path d="M101.67,1.27C102.55,1.27 103.23,1.58 103.7,2.19C104.17,2.8 104.41,3.52 104.41,4.33L104.41,21.76C106.13,20.19 108.01,18.79 110.07,17.55C112.12,16.31 114.18,15.7 116.24,15.7C118.3,15.7 120.07,16.21 121.48,17.23C122.89,18.25 123.94,19.59 124.65,21.24C125.36,22.89 125.71,24.69 125.71,26.62L125.71,40.03C125.71,40.78 125.73,41.36 125.77,41.77C125.81,42.18 125.95,42.55 126.17,42.88C126.39,43.21 126.77,43.67 127.28,44.25C127.71,44.72 128.01,45.1 128.18,45.38C128.35,45.66 128.44,46.13 128.44,46.8C128.44,47.75 128.15,48.47 127.57,48.97C126.99,49.47 126.24,49.73 125.31,49.73L111.71,49.73C110.81,49.73 110.11,49.46 109.62,48.92C109.13,48.38 108.88,47.67 108.88,46.79C108.88,45.97 109.07,45.35 109.46,44.92C109.85,44.49 110.23,44.01 110.62,43.49C111.01,42.96 111.2,42.18 111.2,41.15L111.2,30.1C111.2,29.05 110.99,28.05 110.57,27.1C110.15,26.15 109.31,25.68 108.04,25.68C107.27,25.68 106.59,25.83 106.01,26.12C105.43,26.41 104.89,26.78 104.4,27.23L104.4,40.86C104.4,41.85 104.52,42.6 104.75,43.1C104.99,43.6 105.26,44.01 105.57,44.31C105.88,44.61 106.16,44.93 106.39,45.28C106.62,45.63 106.74,46.13 106.74,46.79C106.74,47.67 106.49,48.38 106,48.92C105.51,49.46 104.81,49.73 103.91,49.73L90.31,49.73C89.39,49.73 88.63,49.48 88.04,48.99C87.45,48.5 87.15,47.77 87.15,46.8C87.15,46.07 87.29,45.51 87.57,45.11C87.85,44.71 88.17,44.36 88.52,44.05C88.87,43.74 89.19,43.34 89.47,42.84C89.75,42.35 89.89,41.64 89.89,40.71L89.89,14.32C89.89,13.35 89.73,12.63 89.42,12.14C89.11,11.66 88.74,11.28 88.32,11C87.9,10.72 87.53,10.41 87.22,10.07C86.91,9.73 86.75,9.2 86.75,8.49C86.75,7.65 87.03,6.99 87.59,6.51C88.15,6.03 88.77,5.65 89.46,5.37L96.49,2.57C97.31,2.25 98.14,1.95 99,1.68C99.86,1.41 100.74,1.28 101.64,1.28L101.67,1.27Z" fill="#2C666E"/>
    </g>
    <path d="M146.75,1.27C147.63,1.27 148.31,1.57 148.8,2.17C149.28,2.77 149.52,3.49 149.52,4.33L149.52,40.04C149.52,40.66 149.55,41.27 149.62,41.86C149.68,42.45 149.95,42.98 150.43,43.46C151.01,44.04 151.51,44.51 151.93,44.86C152.35,45.21 152.56,45.86 152.56,46.81C152.56,47.76 152.26,48.51 151.66,49C151.06,49.49 150.3,49.74 149.37,49.74L135.19,49.74C134.27,49.74 133.5,49.49 132.9,49C132.3,48.51 132,47.78 132,46.81C132,45.99 132.15,45.4 132.45,45.02C132.75,44.64 133.11,44.32 133.51,44.04C133.92,43.76 134.27,43.37 134.57,42.86C134.87,42.36 135.02,41.55 135.02,40.46L135.02,14.32C135.02,13.29 134.85,12.54 134.5,12.06C134.16,11.59 133.75,11.23 133.29,10.98C132.83,10.73 132.43,10.44 132.08,10.11C131.74,9.78 131.56,9.23 131.56,8.48C131.56,7.62 131.84,6.95 132.4,6.48C132.96,6.01 133.59,5.63 134.3,5.35L141.49,2.55C142.35,2.21 143.21,1.91 144.07,1.65C144.93,1.39 145.82,1.26 146.74,1.26L146.75,1.27Z" fill="#2C666E"/>
    <path d="M170.53,15.7C171.41,15.7 172.09,16 172.58,16.6C173.06,17.2 173.3,17.92 173.3,18.76L173.3,40.03C173.3,40.63 173.33,41.24 173.38,41.85C173.43,42.46 173.68,42.99 174.11,43.45C174.67,44.05 175.14,44.52 175.51,44.87C175.88,45.22 176.07,45.86 176.07,46.8C176.07,47.74 175.77,48.47 175.18,48.97C174.59,49.47 173.83,49.73 172.91,49.73L159.21,49.73C158.29,49.73 157.53,49.48 156.94,48.99C156.35,48.5 156.05,47.77 156.05,46.8C156.05,45.83 156.23,45.23 156.6,44.85C156.97,44.47 157.44,44.01 158.02,43.45C158.45,43.02 158.69,42.48 158.74,41.84C158.79,41.2 158.82,40.59 158.82,40.04L158.82,28.79C158.82,28.36 158.79,27.91 158.72,27.45C158.66,26.99 158.47,26.6 158.17,26.27C158.08,26.16 157.98,26.08 157.86,26.01C157.74,25.95 157.64,25.87 157.55,25.78C157.08,25.29 156.64,24.88 156.25,24.57C155.85,24.26 155.65,23.71 155.65,22.91C155.65,22.05 155.92,21.38 156.46,20.91C157,20.44 157.63,20.06 158.36,19.78L165.32,16.98C166.14,16.66 166.99,16.36 167.87,16.09C168.75,15.82 169.63,15.69 170.51,15.69L170.53,15.7ZM165.7,15.57C164.32,15.57 162.94,15.37 161.54,14.96C160.14,14.55 158.98,13.87 158.04,12.91C157.11,11.95 156.64,10.66 156.64,9.03C156.64,7.4 157.11,6.11 158.06,5.18C159.01,4.25 160.18,3.58 161.57,3.2C162.96,2.82 164.34,2.62 165.69,2.62C167.04,2.62 168.42,2.81 169.83,3.2C171.24,3.59 172.42,4.25 173.37,5.18C174.32,6.11 174.8,7.4 174.8,9.03C174.8,10.66 174.33,11.99 173.38,12.95C172.43,13.91 171.26,14.58 169.85,14.98C168.44,15.38 167.05,15.58 165.68,15.58L165.7,15.57Z" fill="#2C666E"/>
  </svg>
  ''';

  static const String _starFilledSvg = '''
  <svg viewBox="0 0 24 24"><path fill="#F4D06F" d="M12 17.27L18.18 21l-1.64-7.03L22 9.24l-7.19-.61L12 2 9.19 8.63 2 9.24l5.46 4.73L5.82 21z"/></svg>
  ''';

  static const String _starEmptySvg = '''
  <svg viewBox="0 0 24 24"><path fill="#D4CFC6" d="M12 17.27L18.18 21l-1.64-7.03L22 9.24l-7.19-.61L12 2 9.19 8.63 2 9.24l5.46 4.73L5.82 21z"/></svg>
  ''';

  static const String _tipIconSvg = '''
  <svg viewBox="0 0 24 24"><path fill="#B78103" d="M9 21c0 .55.45 1 1 1h4c.55 0 1-.45 1-1v-1H9v1zm3-19C8.14 2 5 5.14 5 9c0 2.38 1.19 4.47 3 5.74V17c0 .55.45 1 1 1h6c.55 0 1-.45 1-1v-2.26c1.81-1.27 3-3.36 3-5.74 0-3.86-3.14-7-7-7z"/></svg>
  ''';

  static const String _noteIconSvg = '''
  <svg viewBox="0 0 24 24"><path fill="#2C666E" d="M3 17.25V21h3.75L17.81 9.94l-3.75-3.75L3 17.25zM20.71 7.04c.39-.39.39-1.02 0-1.41l-2.34-2.34c-.39-.39-1.02-.39-1.41 0l-1.83 1.83 3.75 3.75 1.83-1.83z"/></svg>
  ''';

  static const String _warningIconSvg = '''
  <svg viewBox="0 0 24 24"><path fill="#BA3B46" d="M1 21h22L12 2 1 21zm12-3h-2v-2h2v2zm0-4h-2v-4h2v4z"/></svg>
  ''';

  /// Genera los bytes del documento PDF con diseño editorial de Ohtli.
  static Future<Uint8List> generateTripPdf({
    required Trip trip,
    required List<TripSection> sections,
    String? authorName,
    List<String>? coAuthors,
    String? qrBaseUrl,
  }) async {
    // Carga de tipografía Inter desde Google Fonts con fallback seguro a Helvetica
    pw.Font fontRegular = pw.Font.helvetica();
    pw.Font fontBold = pw.Font.helveticaBold();
    pw.Font fontItalic = pw.Font.helveticaOblique();

    try {
      fontRegular = await PdfGoogleFonts.interRegular();
      fontBold = await PdfGoogleFonts.interBold();
      fontItalic = await PdfGoogleFonts.interItalic();
    } catch (_) {
      // Fallback transparente sin fallos de red
    }

    final pdf = pw.Document(
      title: 'Ohtli - ${trip.title.isNotEmpty ? trip.title : "Itinerario de Viaje"}',
      author: authorName ?? 'Viajero Ohtli',
      subject: 'Itinerario de viaje cultural en la Ciudad de México',
      creator: 'Ohtli Platform (ohtli.quest)',
      theme: pw.ThemeData.withFont(
        base: fontRegular,
        bold: fontBold,
        italic: fontItalic,
      ),
    );

    // Formateo seguro de fecha de viaje sin dependencias de locale externa
    String travelDateStr = 'Fecha flexible / No definida';
    if (trip.travelDate != null) {
      final months = [
        'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio',
        'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre'
      ];
      final d = trip.travelDate!;
      travelDateStr = '${d.day} de ${months[d.month - 1]} de ${d.year}';
    }

    // Cálculo de estadísticas del viaje
    final places = sections.whereType<PlaceSection>().toList();
    final double totalCost = places.fold(0.0, (acc, p) => acc + p.cost);
    final String currency = places.isNotEmpty ? places.first.currency : 'MXN';

    // URL pública para el código QR
    final String effectiveQrUrl = qrBaseUrl != null && qrBaseUrl.isNotEmpty
        ? qrBaseUrl
        : 'https://ohtli.quest/?tripId=${trip.id}&authorId=${trip.userId}';

    // Lista consolidada de autores
    final List<String> allAuthorsList = [
      if (authorName != null && authorName.isNotEmpty) authorName else 'Viajero Ohtli',
      ...?coAuthors?.where((a) => a.isNotEmpty),
    ];

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.letter,
        margin: const pw.EdgeInsets.symmetric(horizontal: 40, vertical: 36),
        header: (pw.Context context) => _buildPageHeader(context, trip),
        footer: (pw.Context context) => _buildPageFooter(context),
        build: (pw.Context context) {
          int placeIndex = 0;

          return [
            // Cabecera Editorial del Itinerario con Logo e Isologo
            _buildItineraryHero(
              trip: trip,
              authorDisplay: allAuthorsList.join(', '),
              travelDateStr: travelDateStr,
              placesCount: places.length,
              totalCost: totalCost,
              currency: currency,
              qrUrl: effectiveQrUrl,
            ),

            pw.SizedBox(height: 20),

            // Resumen de ruta / Manifiesto
            if (trip.description.isNotEmpty) ...[
              _buildStorytellingBox(trip.description),
              pw.SizedBox(height: 24),
            ],

            // Título de la sección de paradas
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text(
                  'CRONOGRAMA DE PARADAS',
                  style: pw.TextStyle(
                    fontSize: 13,
                    fontWeight: pw.FontWeight.bold,
                    color: stormyTeal,
                    letterSpacing: 1.2,
                  ),
                ),
                pw.Text(
                  '${places.length} ${places.length == 1 ? "lugar" : "lugares"} en ruta',
                  style: const pw.TextStyle(
                    fontSize: 10,
                    color: PdfColors.grey700,
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 6),
            pw.Divider(color: stormyTeal, thickness: 1.5),
            pw.SizedBox(height: 14),

            // Iteración de Secciones (Lugares, Alertas, Tablas y Bloques de Bitácora)
            ...sections.expand((section) {
              if (section is PlaceSection) {
                placeIndex++;
                return [_buildPlaceItem(section, placeIndex)];
              } else if (section is TextSection) {
                return _buildMarkdownBlocks(section.markdownText);
              } else if (section is TextImageSection) {
                return _buildMarkdownBlocks(section.markdownText);
              } else if (section is TransferSection) {
                return [_buildTransferItem(section)];
              }
              return <pw.Widget>[];
            }),

            // Fe de Erratas (si existen modificaciones registradas)
            if (trip.errataHistory.isNotEmpty) ...[
              pw.SizedBox(height: 18),
              _buildErrataSection(trip.errataHistory),
            ],

            pw.SizedBox(height: 16),

            // Llamado al escaneo del QR al final de la ruta
            _buildQrCallout(effectiveQrUrl),
          ];
        },
      ),
    );

    return pdf.save();
  }

  /// Encabezado superior repetido en páginas subsiguientes
  static pw.Widget _buildPageHeader(pw.Context context, Trip trip) {
    if (context.pageNumber == 1) {
      return pw.SizedBox.shrink();
    }
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 16),
      padding: const pw.EdgeInsets.only(bottom: 6),
      decoration: pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: canteraBorder, width: 0.8)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Row(
            children: [
              pw.Text(
                'OHTLI',
                style: pw.TextStyle(
                  fontSize: 8.5,
                  fontWeight: pw.FontWeight.bold,
                  color: stormyTeal,
                  letterSpacing: 1.2,
                ),
              ),
              pw.SizedBox(width: 6),
              pw.Container(
                width: 3,
                height: 3,
                decoration: pw.BoxDecoration(shape: pw.BoxShape.circle, color: stormyTeal),
              ),
              pw.SizedBox(width: 6),
              pw.Text(
                trip.title.toUpperCase(),
                style: pw.TextStyle(
                  fontSize: 8.5,
                  fontWeight: pw.FontWeight.bold,
                  color: onyx,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
          pw.Text(
            'Guía de Viaje Portátil',
            style: const pw.TextStyle(
              fontSize: 8,
              color: PdfColors.grey600,
            ),
          ),
        ],
      ),
    );
  }

  /// Pie de página institucional con numeración
  static pw.Widget _buildPageFooter(pw.Context context) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 16),
      padding: const pw.EdgeInsets.only(top: 6),
      decoration: pw.BoxDecoration(
        border: pw.Border(top: pw.BorderSide(color: canteraBorder, width: 0.8)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Row(
            children: [
              pw.Text(
                'Ohtli',
                style: pw.TextStyle(
                  fontSize: 8,
                  color: stormyTeal,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.Text(
                ' | El viaje empieza aquí | ohtli.quest',
                style: const pw.TextStyle(
                  fontSize: 8,
                  color: PdfColors.grey700,
                ),
              ),
            ],
          ),
          pw.Text(
            'Página ${context.pageNumber} de ${context.pagesCount}',
            style: const pw.TextStyle(
              fontSize: 8,
              color: PdfColors.grey600,
            ),
          ),
        ],
      ),
    );
  }

  /// Hero / Portada del Itinerario con Logo de Ohtli, QR y Métricas
  static pw.Widget _buildItineraryHero({
    required Trip trip,
    required String authorDisplay,
    required String travelDateStr,
    required int placesCount,
    required double totalCost,
    required String currency,
    required String qrUrl,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(16),
      decoration: pw.BoxDecoration(
        color: cloudDancer,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(12)),
        border: pw.Border.all(color: canteraBorder, width: 1),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          // Datos Principales
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Row(
                  children: [
                    pw.SvgImage(
                      svg: _ohtliLogoSvg,
                      width: 65,
                      height: 20,
                    ),
                    pw.SizedBox(width: 10),
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: pw.BoxDecoration(
                        color: stormyTeal,
                        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                      ),
                      child: pw.Text(
                        'ITINERARIO CULTURAL / CDMX',
                        style: pw.TextStyle(
                          fontSize: 7.5,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.white,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                  ],
                ),
                pw.SizedBox(height: 10),
                pw.Text(
                  trip.title.isNotEmpty ? trip.title : 'Viaje por la Ciudad de México',
                  style: pw.TextStyle(
                    fontSize: 22,
                    fontWeight: pw.FontWeight.bold,
                    color: onyx,
                    letterSpacing: 0.3,
                  ),
                ),
                pw.SizedBox(height: 6),
                pw.Row(
                  children: [
                    pw.Text(
                      'Por: $authorDisplay',
                      style: const pw.TextStyle(
                        fontSize: 9.5,
                        color: PdfColors.grey800,
                      ),
                    ),
                    pw.SizedBox(width: 8),
                    pw.Container(
                      width: 3,
                      height: 3,
                      decoration: pw.BoxDecoration(
                        shape: pw.BoxShape.circle,
                        color: PdfColors.grey600,
                      ),
                    ),
                    pw.SizedBox(width: 8),
                    pw.Text(
                      travelDateStr,
                      style: const pw.TextStyle(
                        fontSize: 9.5,
                        color: PdfColors.grey700,
                      ),
                    ),
                  ],
                ),
                pw.SizedBox(height: 14),

                // Fila de Indicadores Clave (Pills)
                pw.Row(
                  children: [
                    _buildMetricBadge(
                      label: 'PARADAS',
                      value: '$placesCount ${placesCount == 1 ? "lugar" : "lugares"}',
                    ),
                    pw.SizedBox(width: 10),
                    _buildMetricBadge(
                      label: 'PRESUPUESTO ESTIMADO',
                      value: totalCost > 0
                          ? '\$${totalCost.toStringAsFixed(0)} $currency'
                          : 'Entrada libre',
                    ),
                    pw.SizedBox(width: 10),
                    _buildMetricBadge(
                      label: 'MODALIDAD',
                      value: trip.isSurprise ? 'Viaje Sorpresa' : 'Ruta Cultural',
                    ),
                  ],
                ),
              ],
            ),
          ),

          pw.SizedBox(width: 16),

          // Código QR de Validación / Acceso Dinámico
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Container(
                padding: const pw.EdgeInsets.all(6),
                decoration: pw.BoxDecoration(
                  color: PdfColors.white,
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
                  border: pw.Border.all(color: canteraBorder, width: 1),
                ),
                child: pw.BarcodeWidget(
                  barcode: pw.Barcode.qrCode(),
                  data: qrUrl,
                  width: 72,
                  height: 72,
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                'Escanear en móvil',
                style: const pw.TextStyle(
                  fontSize: 7.5,
                  color: PdfColors.grey700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Insignia para métricas destacadas
  static pw.Widget _buildMetricBadge({required String label, required String value}) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
        border: pw.Border.all(color: canteraBorder, width: 0.8),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            label,
            style: const pw.TextStyle(
              fontSize: 6.5,
              color: PdfColors.grey600,
            ),
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            value,
            style: pw.TextStyle(
              fontSize: 9.5,
              fontWeight: pw.FontWeight.bold,
              color: stormyTeal,
            ),
          ),
        ],
      ),
    );
  }

  /// Caja editorial con el storytelling o reseña del viaje
  static pw.Widget _buildStorytellingBox(String description) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
        border: pw.Border(left: pw.BorderSide(color: stormyTeal, width: 3.5)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'MANIFIESTO Y PROPÓSITO DEL VIAJE',
            style: pw.TextStyle(
              fontSize: 8,
              fontWeight: pw.FontWeight.bold,
              color: stormyTeal,
              letterSpacing: 1.0,
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            description,
            style: const pw.TextStyle(
              fontSize: 9.5,
              color: PdfColors.grey800,
              lineSpacing: 1.8,
            ),
          ),
        ],
      ),
    );
  }

  /// Elemento individual de parada (Lugar / POI) con estrellas vectoriales
  /// Traslado entre paradas: una línea discreta con modo, tiempo, costo e indicaciones.
  static pw.Widget _buildTransferItem(TransferSection t) {
    final cost = t.cost > 0 ? '  ·  \$${t.cost.toStringAsFixed(t.cost % 1 == 0 ? 0 : 2)} ${t.currency}' : '';
    return pw.Container(
      margin: const pw.EdgeInsets.only(left: 18, bottom: 12),
      padding: const pw.EdgeInsets.only(left: 12, top: 2, bottom: 2),
      decoration: pw.BoxDecoration(
        border: pw.Border(left: pw.BorderSide(color: stormyTeal, width: 2)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'Traslado: ${describeTransfer(t)}$cost${t.isEstimated ? '  (estimado)' : ''}',
            style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold, color: stormyTeal),
          ),
          if (t.notes.trim().isNotEmpty)
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 2),
              child: pw.Text(t.notes.trim(), style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
            ),
        ],
      ),
    );
  }

  static pw.Widget _buildPlaceItem(PlaceSection place, int index) {
    final hasCost = place.cost > 0;
    final costStr = hasCost ? '\$${place.cost.toStringAsFixed(0)} ${place.currency}' : 'Acceso Libre';

    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 12),
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
        border: pw.Border.all(color: canteraBorder, width: 0.8),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          // Número de parada con estilo circular
          pw.Container(
            width: 26,
            height: 26,
            alignment: pw.Alignment.center,
            decoration: pw.BoxDecoration(
              color: stormyTeal,
              shape: pw.BoxShape.circle,
            ),
            child: pw.Text(
              '$index',
              style: pw.TextStyle(
                fontSize: 11,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.white,
              ),
            ),
          ),

          pw.SizedBox(width: 12),

          // Detalles del Lugar
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Expanded(
                      child: pw.Text(
                        place.title.isNotEmpty ? place.title : 'Punto de interés',
                        style: pw.TextStyle(
                          fontSize: 13,
                          fontWeight: pw.FontWeight.bold,
                          color: onyx,
                        ),
                      ),
                    ),
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: pw.BoxDecoration(
                        color: hasCost ? cloudDancer : PdfColor.fromHex('#E8F5E9'),
                        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                        border: pw.Border.all(
                          color: hasCost ? canteraBorder : PdfColor.fromHex('#C8E6C9'),
                          width: 0.8,
                        ),
                      ),
                      child: pw.Text(
                        costStr,
                        style: pw.TextStyle(
                          fontSize: 8.5,
                          fontWeight: pw.FontWeight.bold,
                          color: hasCost ? stormyTeal : PdfColor.fromHex('#2E7D32'),
                        ),
                      ),
                    ),
                  ],
                ),

                if (place.rating > 0) ...[
                  pw.SizedBox(height: 4),
                  pw.Row(
                    children: [
                      // Estrellas vectoriales nítidas
                      ...List.generate(5, (starIdx) {
                        return pw.Padding(
                          padding: const pw.EdgeInsets.only(right: 2),
                          child: pw.SvgImage(
                            svg: starIdx < place.rating ? _starFilledSvg : _starEmptySvg,
                            width: 10,
                            height: 10,
                          ),
                        );
                      }),
                      pw.SizedBox(width: 4),
                      pw.Text(
                        '(${place.rating}/5 estrellas)',
                        style: const pw.TextStyle(
                          fontSize: 8,
                          color: PdfColors.grey600,
                        ),
                      ),
                    ],
                  ),
                ],

                if (place.description.isNotEmpty) ...[
                  pw.SizedBox(height: 6),
                  pw.Text(
                    place.description,
                    style: const pw.TextStyle(
                      fontSize: 9.5,
                      color: PdfColors.grey800,
                      lineSpacing: 1.5,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Parser y renderizador inteligente de bloques Markdown (Alertas, Tablas, Párrafos)
  static List<pw.Widget> _buildMarkdownBlocks(String markdownText) {
    if (markdownText.trim().isEmpty) return [];

    final List<pw.Widget> widgets = [];
    final lines = markdownText.split('\n');

    int i = 0;
    while (i < lines.length) {
      final line = lines[i].trim();

      if (line.isEmpty) {
        i++;
        continue;
      }

      // 1. Bloque de Alerta / Callout (> [!TIP], > [!NOTE], > [!WARNING], > [!IMPORTANT], > [!CAUTION])
      if (line.startsWith('>') && line.contains('[!')) {
        final alertMatch = RegExp(r'>\s*\[!(TIP|NOTE|WARNING|IMPORTANT|CAUTION)\]', caseSensitive: false).firstMatch(line);
        final alertType = alertMatch?.group(1)?.toUpperCase() ?? 'NOTE';

        final List<String> bodyLines = [];
        i++;
        while (i < lines.length && lines[i].trim().startsWith('>')) {
          bodyLines.add(lines[i].trim().replaceFirst(RegExp(r'^>\s*'), ''));
          i++;
        }

        widgets.add(_buildAlertCallout(alertType, bodyLines.join('\n')));
        continue;
      }

      // 2. Bloque de Tabla Markdown (| Columna 1 | Columna 2 |)
      if (line.startsWith('|') && line.endsWith('|')) {
        final List<String> tableLines = [];
        while (i < lines.length && lines[i].trim().startsWith('|') && lines[i].trim().endsWith('|')) {
          tableLines.add(lines[i].trim());
          i++;
        }

        final tableWidget = _buildTableFromMarkdown(tableLines);
        if (tableWidget != null) {
          widgets.add(tableWidget);
        }
        continue;
      }

      // 3. Bloque regular de párrafo / Apunte de bitácora
      final List<String> paraLines = [];
      while (i < lines.length &&
          lines[i].trim().isNotEmpty &&
          !lines[i].trim().startsWith('>') &&
          !(lines[i].trim().startsWith('|') && lines[i].trim().endsWith('|'))) {
        paraLines.add(lines[i].trim());
        i++;
      }

      if (paraLines.isNotEmpty) {
        final text = paraLines.join('\n');
        widgets.add(_buildEditorialNote(text));
      }
    }

    return widgets;
  }

  /// Renderiza un Callout box con diseño editorial para notas, tips y advertencias
  static pw.Widget _buildAlertCallout(String alertType, String body) {
    PdfColor accentColor;
    PdfColor bgColor;
    String title;
    String iconSvg;

    switch (alertType) {
      case 'TIP':
        accentColor = PdfColor.fromHex('#B78103');
        bgColor = PdfColor.fromHex('#FFFDF5');
        title = 'CONSEJO / RECOMENDACIÓN';
        iconSvg = _tipIconSvg;
        break;
      case 'WARNING':
      case 'CAUTION':
        accentColor = xoconostle;
        bgColor = PdfColor.fromHex('#FDF4F4');
        title = 'ADVERTENCIA / AVISO';
        iconSvg = _warningIconSvg;
        break;
      case 'IMPORTANT':
        accentColor = stormyTeal;
        bgColor = PdfColor.fromHex('#F0F7F7');
        title = 'IMPORTANTE';
        iconSvg = _noteIconSvg;
        break;
      case 'NOTE':
      default:
        accentColor = stormyTeal;
        bgColor = PdfColor.fromHex('#F0F7F7');
        title = 'NOTA DEL VIAJERO';
        iconSvg = _noteIconSvg;
        break;
    }

    final cleanBody = body
        .replaceAll(RegExp(r'#+\s*'), '')
        .replaceAll(RegExp(r'\*\*'), '')
        .replaceAll(RegExp(r'\*'), '')
        .trim();

    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 12),
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: bgColor,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
        border: pw.Border(
          left: pw.BorderSide(color: accentColor, width: 3.5),
          top: pw.BorderSide(color: canteraBorder, width: 0.8),
          right: pw.BorderSide(color: canteraBorder, width: 0.8),
          bottom: pw.BorderSide(color: canteraBorder, width: 0.8),
        ),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            children: [
              pw.SvgImage(svg: iconSvg, width: 12, height: 12),
              pw.SizedBox(width: 6),
              pw.Text(
                title,
                style: pw.TextStyle(
                  fontSize: 8.5,
                  fontWeight: pw.FontWeight.bold,
                  color: accentColor,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 6),
          pw.Text(
            cleanBody,
            style: const pw.TextStyle(
              fontSize: 9.5,
              color: PdfColors.grey900,
              lineSpacing: 1.6,
            ),
          ),
        ],
      ),
    );
  }

  /// Parsea y renderiza una tabla Markdown a un pw.Table estilizado
  static pw.Widget? _buildTableFromMarkdown(List<String> tableLines) {
    if (tableLines.length < 2) return null;

    List<String> splitCells(String line) {
      final stripped = line.trim();
      final inner = stripped.substring(1, stripped.length - 1);
      return inner.split('|').map((c) => c.trim()).toList();
    }

    final rawHeaders = splitCells(tableLines[0]);
    // Limpiar etiquetas de tipo como [text], [money:MXN], etc.
    final headers = rawHeaders.map((h) => h.replaceAll(RegExp(r'\[.*?\]'), '').trim()).toList();

    // Detectar columnas de moneda / precio
    final moneyCols = <int>{};
    for (int col = 0; col < rawHeaders.length; col++) {
      final hLower = rawHeaders[col].toLowerCase();
      if (hLower.contains('money') || hLower.contains('precio') || hLower.contains('costo')) {
        moneyCols.add(col);
      }
    }

    final List<List<String>> dataRows = [];
    for (int r = 1; r < tableLines.length; r++) {
      final rowStr = tableLines[r];
      // Saltar fila separadora
      if (rowStr.contains('---') || rowStr.contains('===')) continue;

      final cells = splitCells(rowStr);
      final formattedCells = <String>[];
      for (int c = 0; c < cells.length; c++) {
        var cellVal = cells[c];
        if (moneyCols.contains(c)) {
          final numVal = double.tryParse(cellVal.replaceAll(RegExp(r'[^\d.]'), ''));
          if (numVal != null && !cellVal.contains('\$')) {
            cellVal = '\$${numVal.toStringAsFixed(0)} MXN';
          }
        }
        formattedCells.add(cellVal);
      }
      dataRows.add(formattedCells);
    }

    if (dataRows.isEmpty) return null;

    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 12),
      decoration: pw.BoxDecoration(
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
        border: pw.Border.all(color: canteraBorder, width: 0.8),
      ),
      child: pw.ClipRRect(
        horizontalRadius: 8,
        verticalRadius: 8,
        child: pw.Table(
          border: pw.TableBorder.symmetric(
            inside: pw.BorderSide(color: canteraBorder, width: 0.5),
          ),
          children: [
            // Fila de Encabezados con Stormy Teal
            pw.TableRow(
              decoration: pw.BoxDecoration(color: stormyTeal),
              children: headers.map((h) {
                return pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  child: pw.Text(
                    h.toUpperCase(),
                    style: pw.TextStyle(
                      fontSize: 8.5,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.white,
                      letterSpacing: 0.6,
                    ),
                  ),
                );
              }).toList(),
            ),
            // Filas de Datos alternadas
            ...dataRows.asMap().entries.map((entry) {
              final idx = entry.key;
              final row = entry.value;
              return pw.TableRow(
                decoration: pw.BoxDecoration(
                  color: idx % 2 == 0 ? cloudDancer : PdfColors.white,
                ),
                children: row.asMap().entries.map((cEntry) {
                  final cIdx = cEntry.key;
                  final cellText = cEntry.value;
                  final isMoney = moneyCols.contains(cIdx);
                  return pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    child: pw.Text(
                      cellText,
                      textAlign: isMoney ? pw.TextAlign.right : pw.TextAlign.left,
                      style: pw.TextStyle(
                        fontSize: 9,
                        fontWeight: isMoney ? pw.FontWeight.bold : pw.FontWeight.normal,
                        color: isMoney ? stormyTeal : PdfColors.grey900,
                      ),
                    ),
                  );
                }).toList(),
              );
            }),
          ],
        ),
      ),
    );
  }

  /// Apunte de bitácora estilizado para párrafos y reflexiones
  static pw.Widget _buildEditorialNote(String text) {
    final cleanText = text
        .replaceAll(RegExp(r'#+\s*'), '')
        .replaceAll(RegExp(r'\*\*'), '')
        .replaceAll(RegExp(r'\*'), '')
        .trim();

    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 10),
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: cloudDancer,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
        border: pw.Border.all(color: canteraBorder, width: 0.8),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Container(
            margin: const pw.EdgeInsets.only(top: 2),
            padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: pw.BoxDecoration(
              color: stormyTeal,
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
            ),
            child: pw.Text(
              'APUNTE',
              style: pw.TextStyle(
                fontSize: 6.5,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.white,
                letterSpacing: 0.5,
              ),
            ),
          ),
          pw.SizedBox(width: 10),
          pw.Expanded(
            child: pw.Text(
              cleanText,
              style: const pw.TextStyle(
                fontSize: 9.5,
                color: PdfColors.grey900,
                lineSpacing: 1.6,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Sección de Fe de Erratas para transparencia del documento
  static pw.Widget _buildErrataSection(List<ErrataEntry> errataHistory) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: PdfColor.fromHex('#FFF9E6'),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
        border: pw.Border.all(color: PdfColor.fromHex('#FFE082'), width: 0.8),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'FE DE ERRATAS Y ACTUALIZACIONES DE RUTA',
            style: pw.TextStyle(
              fontSize: 8.5,
              fontWeight: pw.FontWeight.bold,
              color: PdfColor.fromHex('#B78103'),
              letterSpacing: 1.0,
            ),
          ),
          pw.SizedBox(height: 8),
          ...errataHistory.map((e) {
            String dateStr = '';
            try {
              dateStr = DateFormat("d/MM/yyyy HH:mm").format(e.date);
            } catch (_) {
              dateStr = e.date.toString();
            }
            return pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 4),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Container(
                    margin: const pw.EdgeInsets.only(top: 4, right: 6),
                    width: 4,
                    height: 4,
                    decoration: pw.BoxDecoration(
                      shape: pw.BoxShape.circle,
                      color: PdfColor.fromHex('#B78103'),
                    ),
                  ),
                  pw.Expanded(
                    child: pw.RichText(
                      text: pw.TextSpan(
                        children: [
                          pw.TextSpan(
                            text: '[$dateStr] ',
                            style: pw.TextStyle(
                              fontWeight: pw.FontWeight.bold,
                              color: PdfColor.fromHex('#B78103'),
                              fontSize: 8.5,
                            ),
                          ),
                          pw.TextSpan(
                            text: e.note,
                            style: const pw.TextStyle(
                              color: PdfColors.grey900,
                              fontSize: 8.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  /// Llamado visual para recordar el escaneo del código QR
  static pw.Widget _buildQrCallout(String qrUrl) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: cloudDancer,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
        border: pw.Border.all(color: canteraBorder, width: 0.8),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            '¿Deseas navegación en vivo o ajustar este itinerario?',
            style: pw.TextStyle(
              fontSize: 9.5,
              fontWeight: pw.FontWeight.bold,
              color: stormyTeal,
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            'Escanea el código QR de la cabecera en tu teléfono o visita ohtli.quest para abrir este viaje con mapas interactivos y navegación paso a paso.',
            style: const pw.TextStyle(
              fontSize: 8,
              color: PdfColors.grey700,
              lineSpacing: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  /// Descarga directa del archivo PDF en el navegador o dispositivo
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

    final cleanTitle = trip.title.trim().isNotEmpty
        ? trip.title.trim().replaceAll(RegExp(r'[^\w\s-]'), '').replaceAll(RegExp(r'\s+'), '_')
        : 'Itinerario_Ohtli';

    await Printing.sharePdf(
      bytes: bytes,
      filename: '${cleanTitle}_Ohtli.pdf',
    );
  }

  /// Abre el diálogo interactivo de impresión / vista previa de PDF
  static Future<void> printTripPdf({
    required Trip trip,
    required List<TripSection> sections,
    String? authorName,
    List<String>? coAuthors,
    String? qrBaseUrl,
  }) async {
    await Printing.layoutPdf(
      name: 'Ohtli - ${trip.title}',
      onLayout: (PdfPageFormat format) async {
        return generateTripPdf(
          trip: trip,
          sections: sections,
          authorName: authorName,
          coAuthors: coAuthors,
          qrBaseUrl: qrBaseUrl,
        );
      },
    );
  }
}

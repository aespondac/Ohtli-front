import 'dart:typed_data';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../models/trip_model.dart';

class PdfExportService {
  // Paleta de colores institucional Ohtli (Estilo Editorial Mexicano)
  static final PdfColor stormyTeal = PdfColor.fromHex('#2C666E');
  static final PdfColor onyx = PdfColor.fromHex('#0A090C');
  static final PdfColor cloudDancer = PdfColor.fromHex('#F7F6F3');
  static final PdfColor cantera = PdfColor.fromHex('#E4E1DA');
  static final PdfColor canteraBorder = PdfColor.fromHex('#D4CFC6');
  static final PdfColor cempasuchil = PdfColor.fromHex('#F4D06F');
  static final PdfColor xoconostle = PdfColor.fromHex('#BA3B46');

  /// Genera los bytes del documento PDF con diseño editorial de Ohtli.
  static Future<Uint8List> generateTripPdf({
    required Trip trip,
    required List<TripSection> sections,
    String? authorName,
    List<String>? coAuthors,
    String? qrBaseUrl,
  }) async {
    final pdf = pw.Document(
      title: 'Ohtli - ${trip.title.isNotEmpty ? trip.title : "Itinerario de Viaje"}',
      author: authorName ?? 'Viajero Ohtli',
      subject: 'Itinerario de viaje cultural en la Ciudad de México',
      creator: 'Ohtli Platform (ohtli.quest)',
    );

    // Formateo de fecha de viaje
    String travelDateStr = 'Fecha flexible / No definida';
    if (trip.travelDate != null) {
      try {
        travelDateStr = DateFormat("d 'de' MMMM, yyyy", 'es_ES').format(trip.travelDate!);
      } catch (_) {
        travelDateStr = DateFormat("yyyy-MM-dd").format(trip.travelDate!);
      }
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
            // Cabecera Editorial del Itinerario
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

            // Resumen de ruta / Storytelling
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
                    fontSize: 14,
                    fontWeight: pw.FontWeight.bold,
                    color: stormyTeal,
                    letterSpacing: 1.5,
                  ),
                ),
                pw.Text(
                  '${places.length} lugares en ruta',
                  style: pw.TextStyle(
                    fontSize: 10,
                    color: PdfColors.grey700,
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 6),
            pw.Divider(color: stormyTeal, thickness: 1.5),
            pw.SizedBox(height: 14),

            // Iteración de Secciones (Lugares, Notas y Textos)
            ...sections.map((section) {
              if (section is PlaceSection) {
                placeIndex++;
                return _buildPlaceItem(section, placeIndex);
              } else if (section is TextSection) {
                return _buildNoteItem(section.markdownText);
              } else if (section is TextImageSection) {
                return _buildNoteItem(section.markdownText);
              }
              return pw.SizedBox.shrink();
            }),

            // Fe de Erratas (si existen modificaciones registradas)
            if (trip.errataHistory.isNotEmpty) ...[
              pw.SizedBox(height: 20),
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
          pw.Text(
            'OHTLI  •  ${trip.title.toUpperCase()}',
            style: pw.TextStyle(
              fontSize: 8.5,
              fontWeight: pw.FontWeight.bold,
              color: stormyTeal,
              letterSpacing: 1.2,
            ),
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
          pw.Text(
            'Ohtli  |  El viaje empieza aquí  •  ohtli.quest',
            style: pw.TextStyle(
              fontSize: 8,
              color: stormyTeal,
              fontWeight: pw.FontWeight.bold,
            ),
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

  /// Hero / Portada del Itinerario con QR y Métricas
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
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: pw.BoxDecoration(
                    color: stormyTeal,
                    borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                  ),
                  child: pw.Text(
                    'ITINERARIO CULTURAL • CDMX',
                    style: pw.TextStyle(
                      fontSize: 7.5,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.white,
                      letterSpacing: 1.0,
                    ),
                  ),
                ),
                pw.SizedBox(height: 8),
                pw.Text(
                  trip.title.isNotEmpty ? trip.title : 'Viaje por la Ciudad de México',
                  style: pw.TextStyle(
                    fontSize: 22,
                    fontWeight: pw.FontWeight.bold,
                    color: onyx,
                    letterSpacing: 0.5,
                  ),
                ),
                pw.SizedBox(height: 6),
                pw.Text(
                  'Por: $authorDisplay  •  $travelDateStr',
                  style: const pw.TextStyle(
                    fontSize: 9.5,
                    color: PdfColors.grey700,
                  ),
                ),
                pw.SizedBox(height: 14),

                // Fila de Indicadores Clave (Pills)
                pw.Row(
                  children: [
                    _buildMetricBadge(
                      label: 'PARADAS',
                      value: '$placesCount lugares',
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
                  width: 68,
                  height: 68,
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
              lineSpacing: 2.0,
            ),
          ),
        ],
      ),
    );
  }

  /// Elemento individual de parada (Lugar / POI)
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
                      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
                  pw.SizedBox(height: 3),
                  pw.Row(
                    children: [
                      pw.Text(
                        '★ ' * place.rating,
                        style: pw.TextStyle(
                          fontSize: 10,
                          color: cempasuchil,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.Text(
                        ' (${place.rating}/5 estrellas)',
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

  /// Elemento de notas del viaje / reflexiones
  static pw.Widget _buildNoteItem(String markdownText) {
    if (markdownText.trim().isEmpty) return pw.SizedBox.shrink();

    // Limpiar etiquetas básicas de markdown para renderizado en texto plano legible
    final cleanText = markdownText
        .replaceAll(RegExp(r'#+\s*'), '')
        .replaceAll(RegExp(r'\*\*'), '')
        .replaceAll(RegExp(r'\*'), '')
        .trim();

    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 12),
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: cloudDancer,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
        border: pw.Border.all(color: canteraBorder, width: 0.6),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            '✎ ',
            style: pw.TextStyle(fontSize: 10, color: stormyTeal),
          ),
          pw.Expanded(
            child: pw.Text(
              cleanText,
              style: const pw.TextStyle(
                fontSize: 9,
                color: PdfColors.grey800,
                lineSpacing: 1.5,
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
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: PdfColor.fromHex('#FFF9E6'),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
        border: pw.Border.all(color: PdfColor.fromHex('#FFE082'), width: 0.8),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'FE DE ERRATAS Y ACTUALIZACIONES DE RUTA',
            style: pw.TextStyle(
              fontSize: 8,
              fontWeight: pw.FontWeight.bold,
              color: PdfColor.fromHex('#B78103'),
              letterSpacing: 1.0,
            ),
          ),
          pw.SizedBox(height: 6),
          ...errataHistory.map((e) {
            String dateStr = '';
            try {
              dateStr = DateFormat("d/MM/yyyy HH:mm").format(e.date);
            } catch (_) {
              dateStr = e.date.toString();
            }
            return pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 3),
              child: pw.Text(
                '• [$dateStr] ${e.note}',
                style: const pw.TextStyle(
                  fontSize: 8.5,
                  color: PdfColors.grey900,
                ),
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
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: cloudDancer,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
        border: pw.Border.all(color: canteraBorder, width: 0.8),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  '¿Deseas navegación en vivo o ajustar este itinerario?',
                  style: pw.TextStyle(
                    fontSize: 9,
                    fontWeight: pw.FontWeight.bold,
                    color: stormyTeal,
                  ),
                ),
                pw.SizedBox(height: 2),
                pw.Text(
                  'Escanea el código QR de la cabecera o ingresa a $qrUrl para abrirlo en Ohtli con mapas interactivos OSRM.',
                  style: const pw.TextStyle(
                    fontSize: 7.5,
                    color: PdfColors.grey700,
                  ),
                ),
              ],
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

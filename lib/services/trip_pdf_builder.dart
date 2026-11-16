import 'dart:math' as math;
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/trip_model.dart';

/// Tipografías del PDF (Outfit para títulos, Inter para texto), cargadas por quien lo genera.
class TripPdfFonts {
  const TripPdfFonts({
    required this.display,
    required this.heading,
    required this.headingBold,
    required this.body,
    required this.bodyMedium,
    required this.bodySemiBold,
    required this.bodyBold,
    required this.bodyItalic,
  });

  /// Outfit 900, 800 y 700
  final pw.Font display;
  final pw.Font heading;
  final pw.Font headingBold;

  /// Inter 400, 500, 600, 700 e itálica
  final pw.Font body;
  final pw.Font bodyMedium;
  final pw.Font bodySemiBold;
  final pw.Font bodyBold;
  final pw.Font bodyItalic;
}

/// Descarga los bytes de una imagen (null si no se pudo).
typedef TripPdfFetcher = Future<Uint8List?> Function(String url);

/// Qué versión del PDF: guía de bolsillo para hacer el viaje o crónica para recordarlo.
enum TripPdfEdition { guide, memory }

/// Lugar cercano a una parada ("Cerca de ahí").
class TripPdfNearby {
  const TripPdfNearby({required this.name, required this.kind, required this.meters});
  final String name;
  final String kind;
  final double meters;
}

/// Busca lugares cerca de un punto (los más cercanos primero).
typedef TripPdfNearbyFinder = Future<List<TripPdfNearby>> Function(double lat, double lng);

/// Guía de ruta imprimible de un viaje, al estilo de un atlas de calles:
/// portada, mapa con cuadrícula, itinerario parada por parada e índice final.
class TripPdfBuilder {
  TripPdfBuilder._(this.trip, this.sections, this.fonts, this.fetch, this.authorLine, this.qrUrl, this.edition,
      this.nearbyFinder);

  final TripPdfEdition edition;
  final TripPdfNearbyFinder? nearbyFinder;
  final Map<int, List<TripPdfNearby>> _nearby = {};

  bool get _isGuide => edition == TripPdfEdition.guide;

  /// Igual que el visor del viaje: terminado o con fecha pasada es "después" (crónica).
  static TripPdfEdition editionFor(Trip trip, {DateTime? now}) {
    if (trip.finishedAt != null) return TripPdfEdition.memory;
    final d = trip.travelDate;
    if (d == null) return TripPdfEdition.guide;
    final n = now ?? DateTime.now();
    return DateTime(d.year, d.month, d.day).isBefore(DateTime(n.year, n.month, n.day))
        ? TripPdfEdition.memory
        : TripPdfEdition.guide;
  }

  final Trip trip;
  final List<TripSection> sections;
  final TripPdfFonts fonts;
  final TripPdfFetcher fetch;
  final String authorLine;
  final String qrUrl;

  // ───────────────────────── Paleta (la de la app) ─────────────────────────
  static final PdfColor teal = PdfColor.fromHex('#2C666E');
  static final PdfColor tealDeep = PdfColor.fromHex('#173A3F');
  static final PdfColor cempasuchil = PdfColor.fromHex('#E2711D');
  static final PdfColor xoconostle = PdfColor.fromHex('#6C3953');
  static final PdfColor onyx = PdfColor.fromHex('#0A090C');
  static final PdfColor cream = PdfColor.fromHex('#F0EEE9');
  static final PdfColor paper = PdfColor.fromHex('#FBFAF7');
  static final PdfColor line = PdfColor.fromHex('#E4E0D8');
  static final PdfColor muted = PdfColor.fromHex('#5F5B55');

  /// Un color por parada, como las rutas de un atlas.
  static final List<PdfColor> stopColors = [
    PdfColor.fromHex('#2C666E'),
    PdfColor.fromHex('#E2711D'),
    PdfColor.fromHex('#6C3953'),
    PdfColor.fromHex('#3A7D44'),
    PdfColor.fromHex('#2E5AAC'),
    PdfColor.fromHex('#C2185B'),
    PdfColor.fromHex('#B7791F'),
  ];

  /// Un solo acento, como en la app: todas las paradas en turquesa (el número las distingue).
  static PdfColor colorFor(int index) => teal;

  static const String _months =
      'enero,febrero,marzo,abril,mayo,junio,julio,agosto,septiembre,octubre,noviembre,diciembre';

  // ───────────────────────── Datos derivados ─────────────────────────
  late final List<PlaceSection> places = sections.whereType<PlaceSection>().toList();
  late final List<TransferSection> transfers = sections.whereType<TransferSection>().toList();
  late final List<PlaceSection> mappable =
      places.where((p) => p.lat != null && p.lng != null && (p.lat != 0 || p.lng != 0)).toList();

  final Map<String, pw.ImageProvider> _images = {};
  _AtlasMap? _map;

  String get _dateText {
    final d = trip.travelDate;
    if (d == null) return 'Fecha libre';
    return '${d.day} de ${_months.split(',')[d.month - 1]} de ${d.year}';
  }

  String? get _timeWindow {
    final start = places.map((p) => p.arrivalTime).firstWhere((t) => t != null && t.isNotEmpty, orElse: () => null);
    final end = places.reversed
        .map((p) => p.departureTime ?? p.arrivalTime)
        .firstWhere((t) => t != null && t.isNotEmpty, orElse: () => null);
    if (start == null) return null;
    return end == null || end == start ? start : '$start – $end';
  }

  /// Lo que de verdad se gastó (solo si se registró en alguna parada).
  double? get _realSpent =>
      places.any((p) => p.realCost != null) ? places.fold<double>(0, (a, p) => a + (p.realCost ?? 0)) : null;

  double get _placesCost => places.fold(0.0, (a, p) => a + p.cost);
  double get _transfersCost => transfers.fold(0.0, (a, t) => a + t.cost);

  /// Kilómetros del recorrido: los de los traslados o, si no hay, la distancia entre paradas.
  double? get _distanceKm {
    final known = transfers.where((t) => (t.distanceKm ?? 0) > 0).fold(0.0, (a, t) => a + t.distanceKm!);
    if (known > 0) return known;
    if (mappable.length < 2) return null;
    var total = 0.0;
    for (var i = 1; i < mappable.length; i++) {
      total += _haversineKm(mappable[i - 1].lat!, mappable[i - 1].lng!, mappable[i].lat!, mappable[i].lng!);
    }
    return total * 1.25; // las calles no van en línea recta
  }

  static double _haversineKm(double la1, double lo1, double la2, double lo2) {
    const r = 6371.0;
    final dLa = (la2 - la1) * math.pi / 180, dLo = (lo2 - lo1) * math.pi / 180;
    final a = math.pow(math.sin(dLa / 2), 2) +
        math.cos(la1 * math.pi / 180) * math.cos(la2 * math.pi / 180) * math.pow(math.sin(dLo / 2), 2);
    return 2 * r * math.asin(math.sqrt(a));
  }

  static String money(double v) {
    final s = v.round().toString();
    final out = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) out.write(',');
      out.write(s[i]);
    }
    return '\$$out';
  }

  String _gridOf(PlaceSection p) => _map?.gridRef(p.lat!, p.lng!) ?? '';

  // ───────────────────────── Estilos ─────────────────────────
  pw.TextStyle _t(double size, {pw.Font? font, PdfColor? color, double? spacing, double? height}) => pw.TextStyle(
        font: font ?? fonts.body,
        fontSize: size,
        color: color ?? onyx,
        letterSpacing: spacing,
        lineSpacing: height,
      );

  pw.Widget _eyebrow(String text, {PdfColor? color}) =>
      pw.Text(text.toUpperCase(), style: _t(8, font: fonts.bodyBold, color: color ?? teal, spacing: 1.6));

  // ───────────────────────── Imágenes ─────────────────────────
  static bool _decodable(Uint8List b) =>
      b.length > 8 &&
      ((b[0] == 0xFF && b[1] == 0xD8) || (b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47));

  /// Miniatura de Wikimedia en el ancho que se va a imprimir (no la foto original).
  static String _sized(String url, int width) {
    final m = RegExp(r'/(\d+)px-').firstMatch(url);
    if (m == null) return url;
    return url.replaceFirst(m.group(0)!, '/${width}px-');
  }

  Future<void> _loadImage(String key, String url) async {
    if (url.isEmpty) return;
    try {
      final bytes = await fetch(url);
      if (bytes != null && _decodable(bytes)) _images[key] = pw.MemoryImage(bytes);
    } catch (_) {}
  }

  String get _coverUrl {
    if (trip.coverUrl.isNotEmpty) return trip.coverUrl;
    for (final p in places) {
      final u = (p.coverUrl?.isNotEmpty ?? false) ? p.coverUrl! : p.mainPhotoUrl;
      if (u.isNotEmpty) return u;
    }
    return '';
  }

  // ───────────────────────── Construcción ─────────────────────────
  static Future<Uint8List> build({
    required Trip trip,
    required List<TripSection> sections,
    required TripPdfFonts fonts,
    required TripPdfFetcher fetch,
    String? authorName,
    List<String>? coAuthors,
    String? qrUrl,
    TripPdfEdition? edition,
    TripPdfNearbyFinder? nearby,
  }) async {
    final authors = [
      if (authorName != null && authorName.trim().isNotEmpty) authorName.trim() else 'Viajero Ohtli',
      ...?coAuthors?.where((a) => a.trim().isNotEmpty),
    ];
    final b = TripPdfBuilder._(
      trip,
      sections,
      fonts,
      fetch,
      authors.join(', '),
      (qrUrl != null && qrUrl.isNotEmpty) ? qrUrl : 'https://ohtli.quest/?tripId=${trip.id}&authorId=${trip.userId}',
      edition ?? editionFor(trip),
      nearby,
    );
    return b._build();
  }

  Future<Uint8List> _build() async {
    final stopNames = places.map((p) => _title(p).toLowerCase()).toSet();
    final loads = <Future<void>>[
      if (!_isGuide) _loadImage('cover', _sized(_coverUrl, 1280)),
      for (var i = 0; i < places.length; i++)
        _loadImage('place$i', _sized(_photoOf(places[i]), _isGuide ? 330 : 500)),
      if (!_isGuide) ...[
        for (final s in sections.whereType<TextImageSection>()) _loadImage('img:${s.id}', _sized(s.imageUrl, 500)),
        for (final (key, url) in _albumUrls) _loadImage(key, _sized(url, 500)),
      ],
      // "Cerca de ahí": lugares del catálogo a unos pasos de cada parada (sin repetir paradas)
      if (_isGuide && nearbyFinder != null)
        for (var i = 0; i < places.length; i++)
          if (places[i].lat != null && places[i].lng != null)
            () async {
              try {
                final found = await nearbyFinder!(places[i].lat!, places[i].lng!);
                _nearby[i] = found.where((n) => !_sameAsAStop(n.name, stopNames)).take(4).toList();
              } catch (_) {}
            }(),
    ];
    if (mappable.isNotEmpty) {
      double mapHeight;
      if (_isGuide) {
        mapHeight = 300;
      } else {
        // El mapa ocupa lo que deja la leyenda (dos columnas, ~22 pt por renglón)
        final legendRows = (places.length / 2).ceil();
        mapHeight = (640.0 - 64 - legendRows * 22).clamp(400.0, 580.0);
      }
      _map = _AtlasMap(mappable.map((p) => (p.lat!, p.lng!)).toList(), width: 520, height: mapHeight);
      loads.add(_map!.loadTiles(fetch));
    }
    await Future.wait(loads);

    final doc = pw.Document(
      title: 'Ohtli · ${trip.title.isNotEmpty ? trip.title : 'Guía de ruta'}',
      author: authorLine,
      subject: _isGuide ? 'Guía de bolsillo para recorrer la ruta' : 'Crónica del viaje',
      creator: 'Ohtli (ohtli.quest)',
      theme: pw.ThemeData.withFont(
        base: fonts.body,
        bold: fonts.bodyBold,
        italic: fonts.bodyItalic,
        boldItalic: fonts.bodyBold,
      ),
    );

    if (_isGuide) {
      doc.addPage(_guidePages());
    } else {
      doc.addPage(_coverPage());
      if (_map != null) doc.addPage(_mapPage());
      doc.addPage(_itineraryPages());
      if (_albumKeys.length >= 3) doc.addPage(_albumPage());
      doc.addPage(_closingPage());
    }
    return doc.save();
  }

  static String _key(String s) => s
      .toLowerCase()
      .replaceAll(RegExp('[áà]'), 'a')
      .replaceAll(RegExp('[éè]'), 'e')
      .replaceAll(RegExp('[íì]'), 'i')
      .replaceAll(RegExp('[óò]'), 'o')
      .replaceAll(RegExp('[úü]'), 'u')
      .replaceAll(RegExp(r'[^a-z0-9ñ ]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  /// "Museo del Palacio de Bellas Artes" junto a la parada "Palacio de Bellas Artes" es el
  /// mismo lugar: no va en "Cerca de ahí".
  static bool _sameAsAStop(String name, Set<String> stops) {
    final n = _key(name);
    return stops.map(_key).any((s) => s.isNotEmpty && (n.contains(s) || s.contains(n)));
  }

  String _photoOf(PlaceSection p) => (p.coverUrl?.isNotEmpty ?? false) ? p.coverUrl! : p.mainPhotoUrl;

  /// Fotos del álbum (crónica): la principal y las secundarias de cada parada, hasta 12.
  late final List<(String, String)> _albumUrls = () {
    final out = <(String, String)>[];
    for (var i = 0; i < places.length && out.length < 12; i++) {
      final urls = {_photoOf(places[i]), places[i].mainPhotoUrl, ...places[i].secondaryPhotoUrls}..removeWhere((u) => u.isEmpty);
      var k = 0;
      for (final u in urls) {
        if (out.length >= 12) break;
        out.add(('album:$i:${k++}', u));
      }
    }
    return out;
  }();

  List<String> get _albumKeys => _albumUrls.map((e) => e.$1).where(_images.containsKey).take(10).toList();

  // ───────────────────────── Guía de bolsillo (antes y durante) ─────────────────────────
  pw.MultiPage _guidePages() {
    final time = _timeWindow;
    final total = _placesCost + _transfersCost;
    final km = _distanceKm;
    var placeIndex = -1;
    final body = <pw.Widget>[];
    for (final s in sections) {
      if (s is PlaceSection) {
        placeIndex++;
        body.add(_guideStop(s, placeIndex));
      } else if (s is TransferSection) {
        body.add(_guideTransfer(s));
      } else if (s is TextSection) {
        body.addAll(_guideNotes(s.markdownText));
      } else if (s is TextImageSection) {
        body.addAll(_guideNotes(s.markdownText));
      }
    }

    return pw.MultiPage(
      pageFormat: PdfPageFormat.letter,
      margin: const pw.EdgeInsets.fromLTRB(36, 28, 36, 24),
      header: (context) => context.pageNumber == 1 ? pw.SizedBox() : _runningHeader(),
      footer: (context) => _runningFooter(context),
      build: (context) => [
        // Encabezado de la guía
        pw.Container(
          padding: const pw.EdgeInsets.fromLTRB(18, 16, 14, 16),
          decoration: pw.BoxDecoration(
            color: cream,
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(16)),
          ),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Row(children: [
                      pw.SvgImage(svg: _logoSvg('#2C666E'), width: 52),
                      pw.SizedBox(width: 10),
                      _eyebrow('Guía de bolsillo · $_dateText'),
                    ]),
                    pw.SizedBox(height: 8),
                    pw.Text(
                      trip.title.isNotEmpty ? trip.title : 'Mi ruta por la ciudad',
                      maxLines: 2,
                      style: _t(22, font: fonts.display, color: onyx, height: 1.5),
                    ),
                    pw.SizedBox(height: 10),
                    pw.Row(children: [
                      _coverStat('${places.length}', places.length == 1 ? 'parada' : 'paradas'),
                      if (time != null) _coverStat(time, 'horario'),
                      _coverStat(total > 0 ? money(total) : 'Gratis', 'por persona'),
                      if (km != null) _coverStat('${km.toStringAsFixed(1)} km', 'recorrido', last: true),
                    ]),
                  ],
                ),
              ),
              _qrCard(62, 'Mapa en vivo'),
            ],
          ),
        ),
        pw.SizedBox(height: 12),
        // Mapa y horario lado a lado no caben en carta: mapa completo y debajo el resumen
        if (_map != null) ...[
          _map!.widget(
            pins: [
              for (var i = 0; i < mappable.length; i++) (mappable[i].lat!, mappable[i].lng!, places.indexOf(mappable[i])),
            ],
            colorFor: colorFor,
            labelStyle: _t(8.5, font: fonts.bodyBold, color: PdfColors.white),
            gridStyle: _t(7, font: fonts.bodyBold, color: muted),
            smallStyle: _t(6, color: muted),
          ),
          pw.SizedBox(height: 12),
        ],
        _eyebrow('El día de un vistazo'),
        pw.SizedBox(height: 5),
        pw.Table(
          columnWidths: const {
            0: pw.FixedColumnWidth(22),
            1: pw.FixedColumnWidth(70),
            2: pw.FlexColumnWidth(),
            3: pw.FixedColumnWidth(36),
            4: pw.FixedColumnWidth(56),
          },
          border: pw.TableBorder(horizontalInside: pw.BorderSide(color: line, width: 0.5)),
          children: [
            for (var i = 0; i < places.length; i++)
              pw.TableRow(
                verticalAlignment: pw.TableCellVerticalAlignment.middle,
                children: [
                  pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 3), child: pw.Align(alignment: pw.Alignment.centerLeft, child: _pinBadge(i, 14))),
                  pw.Text(
                    [places[i].arrivalTime, places[i].departureTime].where((t) => t != null && t.isNotEmpty).join('–'),
                    style: _t(8.5, font: fonts.bodySemiBold),
                  ),
                  pw.Text(_title(places[i]), maxLines: 1, style: _t(8.5)),
                  pw.Text(places[i].lat != null ? _gridOf(places[i]) : '', style: _t(8, font: fonts.bodyBold, color: muted)),
                  pw.Text(places[i].cost > 0 ? money(places[i].cost) : 'Libre',
                      textAlign: pw.TextAlign.right, style: _t(8.5)),
                ],
              ),
          ],
        ),
        pw.NewPage(),
        _eyebrow('Parada por parada'),
        pw.SizedBox(height: 6),
        ...body,
        pw.SizedBox(height: 10),
        _guideUseful(),
      ],
    );
  }

  pw.Widget _guideStop(PlaceSection p, int index) {
    final color = colorFor(index);
    final photo = _images['place$index'];
    final time = [p.arrivalTime, p.departureTime].where((t) => t != null && t.isNotEmpty).join(' – ');
    final grid = p.lat != null ? _gridOf(p) : '';
    final description = _plain(p.description);
    final near = _nearby[index] ?? const <TripPdfNearby>[];
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 4),
      padding: const pw.EdgeInsets.fromLTRB(10, 9, 10, 9),
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(12)),
        border: pw.Border.all(color: line, width: 0.8),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _pinBadge(index, 22),
          pw.SizedBox(width: 9),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Expanded(child: pw.Text(_title(p), style: _t(12.5, font: fonts.heading, height: 1.4))),
                    // Casilla para palomear en papel
                    pw.Row(children: [
                      pw.Container(
                        width: 10,
                        height: 10,
                        decoration: pw.BoxDecoration(border: pw.Border.all(color: muted, width: 0.8)),
                      ),
                      pw.SizedBox(width: 3),
                      pw.Text('Visitado', style: _t(7, color: muted)),
                    ]),
                  ],
                ),
                pw.SizedBox(height: 3),
                pw.Wrap(children: [
                  if (time.isNotEmpty) _chip(time, fill: color, color: PdfColors.white, font: fonts.bodyBold),
                  if (grid.isNotEmpty) _chip('Mapa $grid'),
                  _chip(p.cost > 0 ? '${money(p.cost)} ${p.currency}' : 'Entrada libre',
                      color: p.cost > 0 ? onyx : PdfColor.fromHex('#2E6B3A'),
                      fill: p.cost > 0 ? cream : PdfColor.fromHex('#E3F1E2')),
                ]),
                if (description.isNotEmpty)
                  pw.Text(description, maxLines: 3, style: _t(8.5, color: PdfColor.fromHex('#2C2A27'), height: 1.8)),
                if (near.isNotEmpty) ...[
                  pw.SizedBox(height: 5),
                  pw.Container(
                    padding: const pw.EdgeInsets.fromLTRB(8, 5, 8, 5),
                    decoration: pw.BoxDecoration(
                      color: paper,
                      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('CERCA DE AHÍ', style: _t(6.5, font: fonts.bodyBold, color: color, spacing: 1.2)),
                        pw.SizedBox(height: 2),
                        pw.Wrap(
                          spacing: 12,
                          runSpacing: 2,
                          children: [
                            for (final n in near)
                              pw.RichText(
                                text: pw.TextSpan(children: [
                                  pw.TextSpan(text: n.name, style: _t(8, font: fonts.bodySemiBold)),
                                  pw.TextSpan(
                                    text: '  ${n.kind} · ${_walk(n.meters)}',
                                    style: _t(7.5, color: muted),
                                  ),
                                ]),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (photo != null) ...[
            pw.SizedBox(width: 9),
            pw.ClipRRect(
              horizontalRadius: 6,
              verticalRadius: 6,
              child: pw.SizedBox(width: 78, height: 58, child: pw.Image(photo, fit: pw.BoxFit.cover)),
            ),
          ],
        ],
      ),
    );
  }

  static String _walk(double m) {
    final minutes = (m / 80).ceil();
    final dist = m < 1000 ? '${(m / 10).round() * 10} m' : '${(m / 1000).toStringAsFixed(1)} km';
    return '$dist, $minutes min a pie';
  }

  pw.Widget _guideTransfer(TransferSection t) {
    final parts = <String>[
      _modeLabel(t.mode.toLowerCase()),
      if ((t.durationMins ?? 0) > 0) '${t.durationMins} min',
      if ((t.distanceKm ?? 0) > 0) '${t.distanceKm!.toStringAsFixed(t.distanceKm! < 10 ? 1 : 0)} km',
      if (t.cost > 0) money(t.cost),
    ];
    final notes = _plain(t.notes);
    return pw.Padding(
      padding: const pw.EdgeInsets.fromLTRB(20, 1, 0, 5),
      child: pw.RichText(
        text: pw.TextSpan(children: [
          pw.TextSpan(text: 'Siguiente: ', style: _t(8, font: fonts.bodyBold, color: muted)),
          pw.TextSpan(text: parts.join(' · '), style: _t(8, font: fonts.bodyBold, color: teal)),
          if (notes.isNotEmpty) pw.TextSpan(text: '  —  $notes', style: _t(8, color: muted)),
        ]),
      ),
    );
  }

  /// En la guía solo van los consejos y avisos (lo útil en la calle), compactos.
  List<pw.Widget> _guideNotes(String md) {
    final out = <pw.Widget>[];
    final lines = md.split('\n');
    var i = 0;
    while (i < lines.length) {
      final l = lines[i].trim();
      if (l.startsWith('>')) {
        final type = RegExp(r'\[!(\w+)\]').firstMatch(l)?.group(1)?.toUpperCase() ?? 'NOTE';
        final body = <String>[];
        final first = l.replaceFirst(RegExp(r'^>\s*(\[!\w+\])?\s*'), '');
        if (first.isNotEmpty) body.add(first);
        i++;
        while (i < lines.length && lines[i].trim().startsWith('>')) {
          body.add(lines[i].trim().replaceFirst(RegExp(r'^>\s*'), ''));
          i++;
        }
        final color = type == 'WARNING' || type == 'CAUTION' ? PdfColor.fromHex('#B3261E') : cempasuchil;
        out.add(pw.Padding(
          padding: const pw.EdgeInsets.fromLTRB(20, 0, 0, 6),
          child: pw.RichText(
            text: pw.TextSpan(children: [
              pw.TextSpan(
                text: '${type == 'WARNING' || type == 'CAUTION' ? 'OJO' : 'TIP'}  ',
                style: _t(7, font: fonts.bodyBold, color: color, spacing: 1),
              ),
              pw.TextSpan(text: _plain(body.join(' ')), style: _t(8, height: 1.6)),
            ]),
          ),
        ));
        continue;
      }
      i++;
    }
    return out;
  }

  pw.Widget _guideUseful() => pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            child: pw.Container(
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                color: cream,
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(10)),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  _eyebrow('Útil durante el día'),
                  pw.SizedBox(height: 6),
                  for (final (k, v) in const [
                    ('Emergencias', '911'),
                    ('Locatel CDMX (información y extravíos)', '55 5658 1111'),
                    ('Cambios a la ruta', 'Escanea el QR de arriba'),
                  ])
                    pw.Padding(
                      padding: const pw.EdgeInsets.only(bottom: 3),
                      child: pw.Row(children: [
                        pw.Expanded(child: pw.Text(k, style: _t(8.5, color: muted))),
                        pw.Text(v, style: _t(8.5, font: fonts.bodyBold)),
                      ]),
                    ),
                ],
              ),
            ),
          ),
          pw.SizedBox(width: 12),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                _eyebrow('Notas'),
                for (var k = 0; k < 4; k++)
                  pw.Container(
                    height: 18,
                    decoration: pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: line, width: 0.7))),
                  ),
              ],
            ),
          ),
        ],
      );

  // ───────────────────────── Álbum (crónica) ─────────────────────────
  pw.Page _albumPage() {
    final keys = _albumKeys;
    int stopOf(String key) => int.parse(key.split(':')[1]);
    return pw.Page(
      pageFormat: PdfPageFormat.letter,
      margin: const pw.EdgeInsets.fromLTRB(40, 34, 40, 30),
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _sectionHeading('Álbum', 'Lo que vimos'),
          pw.SizedBox(height: 12),
          pw.Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var k = 0; k < keys.length; k++)
                pw.SizedBox(
                  width: k == 0 ? 532 : 172,
                  height: k == 0 ? 230 : 128,
                  child: pw.Stack(
                    fit: pw.StackFit.expand,
                    children: [
                      pw.ClipRRect(
                        horizontalRadius: 8,
                        verticalRadius: 8,
                        child: pw.Image(_images[keys[k]]!, fit: pw.BoxFit.cover),
                      ),
                      pw.Positioned(left: 6, bottom: 6, child: _pinBadge(stopOf(keys[k]), 16)),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  // ───────────────────────── 1. Portada ─────────────────────────
  pw.Page _coverPage() {
    final cover = _images['cover'];
    final time = _timeWindow;
    final km = _distanceKm;
    final total = _placesCost + _transfersCost;
    return pw.Page(
      pageTheme: pw.PageTheme(
        pageFormat: PdfPageFormat.letter,
        margin: const pw.EdgeInsets.fromLTRB(46, 40, 46, 36),
        buildBackground: (context) => pw.FullPage(ignoreMargins: true, child: pw.Container(color: cream)),
      ),
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(children: [
            pw.SvgImage(svg: _logoSvg('#2C666E'), width: 92),
            pw.Spacer(),
            _eyebrow('Crónica del viaje'),
          ]),
          pw.SizedBox(height: 22),
          pw.ClipRRect(
            horizontalRadius: 22,
            verticalRadius: 22,
            child: pw.SizedBox(
              height: 340,
              width: double.infinity,
              child: cover != null
                  ? pw.Image(cover, fit: pw.BoxFit.cover)
                  : pw.Container(color: teal, child: pw.CustomPaint(painter: _contourPainter)),
            ),
          ),
          pw.SizedBox(height: 28),
          _eyebrow('Ciudad de México · $_dateText', color: cempasuchil),
          pw.SizedBox(height: 8),
          pw.Text(
            trip.title.isNotEmpty ? trip.title : 'Mi ruta por la ciudad',
            maxLines: 3,
            style: _t(trip.title.length > 38 ? 30 : 38, font: fonts.display, color: onyx, height: 2),
          ),
          if (trip.description.trim().isNotEmpty) ...[
            pw.SizedBox(height: 10),
            pw.Text(_plain(trip.description), maxLines: 3, style: _t(11, color: muted, height: 3)),
          ],
          pw.Spacer(),
          pw.Container(height: 0.8, color: PdfColor.fromHex('#CFCAC0')),
          pw.SizedBox(height: 16),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Row(children: [
                      _coverStat('${places.length}', places.length == 1 ? 'parada' : 'paradas'),
                      if (time != null) _coverStat(time, 'horario'),
                      if (_realSpent != null)
                        _coverStat(money(_realSpent!), 'gastado')
                      else
                        _coverStat(total > 0 ? money(total) : 'Gratis', 'por persona'),
                      if (km != null) _coverStat('${km.toStringAsFixed(1)} km', 'recorrido', last: true),
                    ]),
                    pw.SizedBox(height: 14),
                    pw.Text('Por $authorLine', style: _t(9.5, font: fonts.bodySemiBold, color: muted)),
                  ],
                ),
              ),
              _qrCard(64, 'Ábrelo en tu teléfono'),
            ],
          ),
        ],
      ),
    );
  }

  pw.Widget _qrCard(double size, String label) => pw.Container(
        padding: const pw.EdgeInsets.all(7),
        decoration: pw.BoxDecoration(
          color: PdfColors.white,
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(12)),
          border: pw.Border.all(color: line, width: 0.8),
        ),
        child: pw.Column(children: [
          pw.BarcodeWidget(barcode: pw.Barcode.qrCode(), data: qrUrl, width: size, height: size, color: onyx, drawText: false),
          pw.SizedBox(height: 4),
          pw.Text(label, style: _t(6.5, font: fonts.bodySemiBold, color: muted)),
        ]),
      );

  /// Cifra con su etiqueta, separadas por una línea fina como en la app.
  pw.Widget _coverStat(String value, String label, {bool last = false}) => pw.Container(
        margin: const pw.EdgeInsets.only(right: 18),
        padding: const pw.EdgeInsets.only(right: 18),
        decoration: last
            ? null
            : pw.BoxDecoration(border: pw.Border(right: pw.BorderSide(color: PdfColor.fromHex('#CFCAC0'), width: 0.8))),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(value, style: _t(17, font: fonts.heading, color: onyx)),
            pw.SizedBox(height: 2),
            pw.Text(label.toUpperCase(), style: _t(6.5, font: fonts.bodyBold, color: teal, spacing: 1.2)),
          ],
        ),
      );

  /// Líneas topográficas de respaldo cuando no hay foto de portada.
  void _contourPainter(PdfGraphics canvas, PdfPoint size) {
    canvas.setStrokeColor(PdfColor.fromHex('#3E7C84'));
    canvas.setLineWidth(1.2);
    for (var k = 0; k < 14; k++) {
      final y0 = size.y * (k / 14);
      canvas.moveTo(0, y0);
      for (var x = 0.0; x <= size.x; x += 12) {
        canvas.lineTo(x, y0 + math.sin(x / 60 + k) * 14 + math.cos(x / 23 + k * 0.7) * 6);
      }
      canvas.strokePath();
    }
  }

  // ───────────────────────── 2. Mapa de la ruta ─────────────────────────
  pw.Page _mapPage() {
    final map = _map!;
    return pw.Page(
      pageFormat: PdfPageFormat.letter,
      margin: const pw.EdgeInsets.fromLTRB(36, 30, 36, 26),
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _sectionHeading('Mapa de la ruta', 'Así se recorre', right: 'Cuadrícula para ubicar cada parada'),
          pw.SizedBox(height: 10),
          map.widget(
            pins: [
              for (var i = 0; i < mappable.length; i++) (mappable[i].lat!, mappable[i].lng!, places.indexOf(mappable[i])),
            ],
            colorFor: colorFor,
            labelStyle: _t(8.5, font: fonts.bodyBold, color: PdfColors.white),
            gridStyle: _t(7, font: fonts.bodyBold, color: muted),
            smallStyle: _t(6, color: muted),
          ),
          pw.SizedBox(height: 12),
          // Leyenda
          pw.Wrap(
            spacing: 10,
            runSpacing: 6,
            children: [
              for (var i = 0; i < places.length; i++)
                pw.SizedBox(
                  width: 264,
                  child: pw.Row(
                    children: [
                      _pinBadge(i, 16),
                      pw.SizedBox(width: 6),
                      pw.Expanded(
                        child: pw.Text(
                          _title(places[i]),
                          maxLines: 1,
                          style: _t(8.5, font: fonts.bodySemiBold),
                        ),
                      ),
                      if (places[i].lat != null) _gridChip(_gridOf(places[i])),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  pw.Widget _pinBadge(int index, double size) => pw.Container(
        width: size,
        height: size,
        alignment: pw.Alignment.center,
        decoration: pw.BoxDecoration(color: colorFor(index), shape: pw.BoxShape.circle),
        child: pw.Text('${index + 1}', style: _t(size * 0.5, font: fonts.bodyBold, color: PdfColors.white)),
      );

  pw.Widget _gridChip(String ref) => ref.isEmpty
      ? pw.SizedBox()
      : pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: muted, width: 0.6),
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(3)),
          ),
          child: pw.Text(ref, style: _t(7, font: fonts.bodyBold, color: muted)),
        );

  pw.Widget _sectionHeading(String eyebrow, String title, {String? right}) => pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                _eyebrow(eyebrow),
                pw.SizedBox(height: 3),
                pw.Text(title, style: _t(24, font: fonts.heading)),
              ],
            ),
          ),
          if (right != null) pw.Text(right, style: _t(8, color: muted)),
        ],
      );

  // ───────────────────────── 3. Itinerario ─────────────────────────
  pw.MultiPage _itineraryPages() {
    var placeIndex = -1;
    final widgets = <pw.Widget>[
      _sectionHeading('Itinerario', 'Parada por parada', right: _timeWindow),
      pw.SizedBox(height: 14),
    ];
    for (final s in sections) {
      if (s is PlaceSection) {
        placeIndex++;
        widgets.add(_stopCard(s, placeIndex));
      } else if (s is TransferSection) {
        widgets.add(_transferRow(s));
      } else if (s is TextImageSection) {
        widgets.addAll(_markdown(s.markdownText));
        final img = _images['img:${s.id}'];
        if (img != null) {
          widgets.add(pw.Padding(
            padding: const pw.EdgeInsets.only(left: 44, bottom: 12),
            child: pw.ClipRRect(
              horizontalRadius: 10,
              verticalRadius: 10,
              child: pw.SizedBox(height: 170, child: pw.Image(img, fit: pw.BoxFit.cover)),
            ),
          ));
        }
      } else if (s is TextSection) {
        widgets.addAll(_markdown(s.markdownText));
      }
    }
    if (trip.errataHistory.isNotEmpty) {
      widgets
        ..add(pw.SizedBox(height: 10))
        ..add(_errata());
    }

    return pw.MultiPage(
      pageFormat: PdfPageFormat.letter,
      margin: const pw.EdgeInsets.fromLTRB(40, 30, 40, 26),
      header: (context) => _runningHeader(),
      footer: (context) => _runningFooter(context),
      build: (context) => widgets,
    );
  }

  pw.Widget _runningHeader() => pw.Container(
        margin: const pw.EdgeInsets.only(bottom: 14),
        padding: const pw.EdgeInsets.only(bottom: 6),
        decoration: pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: line, width: 0.7))),
        child: pw.Row(
          children: [
            pw.SvgImage(svg: _logoSvg('#2C666E'), width: 46),
            pw.SizedBox(width: 10),
            pw.Expanded(
              child: pw.Text(trip.title, maxLines: 1, style: _t(8, font: fonts.bodySemiBold, color: muted)),
            ),
            pw.Text('${_isGuide ? 'Guía de bolsillo' : 'Crónica'} · $_dateText', style: _t(8, color: muted)),
          ],
        ),
      );

  pw.Widget _runningFooter(pw.Context context) => pw.Column(
        children: [
          pw.SizedBox(height: 8),
          pw.Row(
            children: [
              pw.Text('ohtli.quest', style: _t(7.5, font: fonts.bodyBold, color: teal)),
              pw.Text('  ·  El viaje empieza aquí', style: _t(7.5, color: muted)),
              pw.Spacer(),
              pw.Text('${context.pageNumber}', style: _t(9, font: fonts.heading, color: onyx)),
            ],
          ),
          pw.SizedBox(height: 5),
          pw.Container(height: 0.8, color: teal),
        ],
      );

  String _title(PlaceSection p) => p.title.trim().isNotEmpty ? p.title.trim() : 'Parada';

  pw.Widget _chip(String text, {PdfColor? color, PdfColor? fill, pw.Font? font}) => pw.Container(
        margin: const pw.EdgeInsets.only(right: 5, bottom: 4),
        padding: const pw.EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
        decoration: pw.BoxDecoration(
          color: fill ?? cream,
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(10)),
        ),
        child: pw.Text(text, style: _t(7.5, font: font ?? fonts.bodySemiBold, color: color ?? onyx)),
      );

  pw.Widget _stopCard(PlaceSection p, int index) {
    final color = colorFor(index);
    final photo = _images['place$index'];
    final real = [p.arrivedAt, p.leftAt].where((t) => t != null && t.isNotEmpty).join(' – ');
    final time = real.isNotEmpty ? real : [p.arrivalTime, p.departureTime].where((t) => t != null && t.isNotEmpty).join(' – ');
    final grid = p.lat != null ? _gridOf(p) : '';
    final description = _plain(p.description);
    final spent = p.realCost;
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 6),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          // Número grande de la parada
          pw.SizedBox(
            width: 44,
            child: pw.Column(children: [
              pw.Container(
                width: 34,
                height: 34,
                alignment: pw.Alignment.center,
                decoration: pw.BoxDecoration(color: color, shape: pw.BoxShape.circle),
                child: pw.Text('${index + 1}', style: _t(15, font: fonts.display, color: PdfColors.white)),
              ),
            ]),
          ),
          pw.Expanded(
            child: pw.Container(
              decoration: pw.BoxDecoration(
                color: PdfColors.white,
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(16)),
                border: pw.Border.all(color: line, width: 0.8),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                children: [
                  pw.Padding(
                    padding: const pw.EdgeInsets.fromLTRB(14, 10, 14, 12),
                    child: pw.Row(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Expanded(
                          child: pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: [
                              pw.Wrap(children: [
                                if (time.isNotEmpty) _chip(time, fill: color, color: PdfColors.white, font: fonts.bodyBold),
                                if (p.unplanned) _chip('Desvío', fill: xoconostle, color: PdfColors.white, font: fonts.bodyBold),
                                if (grid.isNotEmpty) _chip('Mapa $grid'),
                                if (spent != null)
                                  _chip('Gastaron ${money(spent)}')
                                else
                                  _chip(p.cost > 0 ? '${money(p.cost)} ${p.currency}' : 'Entrada libre',
                                      color: p.cost > 0 ? onyx : PdfColor.fromHex('#2E6B3A'),
                                      fill: p.cost > 0 ? cream : PdfColor.fromHex('#E3F1E2')),
                              ]),
                              pw.SizedBox(height: 3),
                              pw.Text(_title(p), style: _t(16, font: fonts.heading, height: 1.5)),
                              if (p.rating > 0) ...[
                                pw.SizedBox(height: 3),
                                pw.Row(children: [
                                  for (var k = 0; k < 5; k++)
                                    pw.Padding(
                                      padding: const pw.EdgeInsets.only(right: 1.5),
                                      child: pw.SvgImage(svg: _star(k < p.rating), width: 9, height: 9),
                                    ),
                                ]),
                              ],
                              if (description.isNotEmpty) ...[
                                pw.SizedBox(height: 6),
                                pw.Text(description, style: _t(9, color: PdfColor.fromHex('#2C2A27'), height: 2.4)),
                              ],
                              if (p.secondaryPhotoUrls.isNotEmpty && photo == null) pw.SizedBox(),
                            ],
                          ),
                        ),
                        if (photo != null) ...[
                          pw.SizedBox(width: 12),
                          pw.ClipRRect(
                            horizontalRadius: 8,
                            verticalRadius: 8,
                            child: pw.SizedBox(width: 150, height: 108, child: pw.Image(photo, fit: pw.BoxFit.cover)),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _modeLabel(String mode) => switch (mode) {
        'walk' || 'walking' || 'caminata' => 'A pie',
        'bike' || 'bicycle' || 'bicicleta' || 'ecobici' => 'En bici',
        'metro' || 'subway' => 'Metro',
        'metrobus' => 'Metrobús',
        'transit' || 'transporte_publico' || 'bus' => 'Transporte público',
        'car' || 'auto' || 'drive' || 'driving' => 'En auto',
        'taxi' || 'uber' || 'rideshare' => 'Taxi / app',
        _ => mode.isEmpty ? 'Traslado' : mode[0].toUpperCase() + mode.substring(1),
      };

  pw.Widget _transferRow(TransferSection t) {
    final parts = <String>[
      _modeLabel(t.mode.toLowerCase()),
      if ((t.durationMins ?? 0) > 0) '${t.durationMins} min',
      if ((t.distanceKm ?? 0) > 0) '${t.distanceKm!.toStringAsFixed(t.distanceKm! < 10 ? 1 : 0)} km',
      if (t.cost > 0) money(t.cost),
    ];
    return pw.Padding(
      padding: const pw.EdgeInsets.only(left: 16, bottom: 6),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Container(
            width: 2,
            height: t.notes.trim().isEmpty ? 22 : 34,
            margin: const pw.EdgeInsets.only(right: 24),
            color: line,
          ),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.SizedBox(height: 4),
                pw.Text(
                  '${parts.join('  ·  ')}${t.isEstimated ? '  (estimado)' : ''}',
                  style: _t(8.5, font: fonts.bodyBold, color: teal),
                ),
                if (t.notes.trim().isNotEmpty)
                  pw.Text(_plain(t.notes), maxLines: 2, style: _t(8, color: muted, height: 1.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ───────────────────────── Notas en Markdown ─────────────────────────
  static String _plain(String md) => md
      .replaceAll(RegExp(r'!\[[^\]]*\]\([^)]*\)'), '')
      .replaceAllMapped(RegExp(r'\[([^\]]+)\]\([^)]*\)'), (m) => m[1]!)
      .replaceAll(RegExp(r'^#+\s*', multiLine: true), '')
      .replaceAll(RegExp(r'\*\*|__|\*|`'), '')
      .replaceAll(RegExp(r'^\s*[-•]\s+', multiLine: true), '• ')
      .trim();

  List<pw.Widget> _markdown(String text) {
    final out = <pw.Widget>[];
    final lines = text.split('\n');
    var i = 0;
    while (i < lines.length) {
      final l = lines[i].trim();
      if (l.isEmpty) {
        i++;
        continue;
      }
      if (l.startsWith('>')) {
        final type = RegExp(r'\[!(\w+)\]').firstMatch(l)?.group(1)?.toUpperCase() ?? 'NOTE';
        final body = <String>[];
        final first = l.replaceFirst(RegExp(r'^>\s*(\[!\w+\])?\s*'), '');
        if (first.isNotEmpty) body.add(first);
        i++;
        while (i < lines.length && lines[i].trim().startsWith('>')) {
          body.add(lines[i].trim().replaceFirst(RegExp(r'^>\s*'), ''));
          i++;
        }
        out.add(_callout(type, _plain(body.join('\n'))));
        continue;
      }
      if (l.startsWith('|') && l.endsWith('|')) {
        final rows = <String>[];
        while (i < lines.length && lines[i].trim().startsWith('|')) {
          rows.add(lines[i].trim());
          i++;
        }
        final table = _table(rows);
        if (table != null) out.add(table);
        continue;
      }
      final para = <String>[];
      while (i < lines.length && lines[i].trim().isNotEmpty && !lines[i].trim().startsWith('>') && !lines[i].trim().startsWith('|')) {
        para.add(lines[i].trim());
        i++;
      }
      out.add(_note(_plain(para.join('\n'))));
    }
    return out;
  }

  pw.Widget _note(String text) => pw.Padding(
        padding: const pw.EdgeInsets.only(left: 44, bottom: 10),
        child: pw.Container(
          padding: const pw.EdgeInsets.fromLTRB(12, 9, 12, 10),
          decoration: pw.BoxDecoration(
            color: paper,
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(10)),
            border: pw.Border.all(color: line, width: 0.6),
          ),
          child: pw.Text(text, style: _t(9, font: fonts.bodyItalic, color: PdfColor.fromHex('#2C2A27'), height: 2.4)),
        ),
      );

  pw.Widget _callout(String type, String body) {
    final (color, label) = switch (type) {
      'TIP' => (cempasuchil, 'Consejo'),
      'WARNING' || 'CAUTION' => (PdfColor.fromHex('#B3261E'), 'Ojo'),
      'IMPORTANT' => (xoconostle, 'Importante'),
      _ => (teal, 'Nota'),
    };
    return pw.Padding(
      padding: const pw.EdgeInsets.only(left: 44, bottom: 10),
      child: pw.Container(
        decoration: pw.BoxDecoration(
          color: paper,
          border: pw.Border(left: pw.BorderSide(color: color, width: 3)),
        ),
        padding: const pw.EdgeInsets.fromLTRB(12, 8, 12, 9),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(label.toUpperCase(), style: _t(7, font: fonts.bodyBold, color: color, spacing: 1.2)),
            pw.SizedBox(height: 3),
            pw.Text(body, style: _t(9, height: 2.2)),
          ],
        ),
      ),
    );
  }

  pw.Widget? _table(List<String> rows) {
    List<String> cells(String r) =>
        r.substring(1, r.length - 1).split('|').map((c) => c.replaceAll(RegExp(r'\[.*?\]'), '').trim()).toList();
    final data = rows.where((r) => !RegExp(r'^\|[\s:|-]+\|$').hasMatch(r)).map(cells).toList();
    if (data.length < 2) return null;
    return pw.Padding(
      padding: const pw.EdgeInsets.only(left: 44, bottom: 12),
      child: pw.TableHelper.fromTextArray(
        headers: data.first,
        data: data.sublist(1),
        headerStyle: _t(7.5, font: fonts.bodyBold, color: PdfColors.white),
        headerDecoration: pw.BoxDecoration(color: teal),
        cellStyle: _t(8.5),
        oddRowDecoration: pw.BoxDecoration(color: paper),
        border: pw.TableBorder(horizontalInside: pw.BorderSide(color: line, width: 0.5)),
        cellPadding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      ),
    );
  }

  pw.Widget _errata() => pw.Container(
        padding: const pw.EdgeInsets.all(12),
        decoration: pw.BoxDecoration(
          color: PdfColor.fromHex('#FFF6E9'),
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(10)),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            _eyebrow('Fe de erratas', color: cempasuchil),
            pw.SizedBox(height: 6),
            for (final e in trip.errataHistory)
              pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 3),
                child: pw.Text(
                  '${e.date.day}/${e.date.month}/${e.date.year} · ${e.note}',
                  style: _t(8.5, height: 1.5),
                ),
              ),
          ],
        ),
      );

  // ───────────────────────── 4. Índice, presupuesto y notas ─────────────────────────
  pw.Page _closingPage() {
    final total = _placesCost + _transfersCost;
    return pw.Page(
      pageFormat: PdfPageFormat.letter,
      margin: const pw.EdgeInsets.fromLTRB(40, 34, 40, 26),
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          _sectionHeading('Índice', 'Paradas de la ruta'),
          pw.SizedBox(height: 10),
          pw.Table(
            columnWidths: const {
              0: pw.FixedColumnWidth(26),
              1: pw.FlexColumnWidth(),
              2: pw.FixedColumnWidth(78),
              3: pw.FixedColumnWidth(40),
              4: pw.FixedColumnWidth(70),
            },
            border: pw.TableBorder(horizontalInside: pw.BorderSide(color: line, width: 0.5)),
            children: [
              pw.TableRow(
                decoration: pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: onyx, width: 1))),
                children: [
                  for (final h in ['#', 'Lugar', 'Horario', 'Mapa', 'Costo'])
                    pw.Padding(
                      padding: pw.EdgeInsets.fromLTRB(h == 'Lugar' ? 4 : 0, 5, 0, 5),
                      child: pw.Text(h.toUpperCase(), style: _t(7, font: fonts.bodyBold, color: muted, spacing: 1)),
                    ),
                ],
              ),
              for (var i = 0; i < places.length; i++)
                pw.TableRow(
                  verticalAlignment: pw.TableCellVerticalAlignment.middle,
                  children: [
                    pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 5), child: pw.Align(alignment: pw.Alignment.centerLeft, child: _pinBadge(i, 15))),
                    pw.Padding(
                      padding: const pw.EdgeInsets.only(left: 4),
                      child: pw.Text(_title(places[i]), maxLines: 1, style: _t(9, font: fonts.bodySemiBold)),
                    ),
                    pw.Text(
                      () {
                        final real = [places[i].arrivedAt, places[i].leftAt].where((t) => t != null && t.isNotEmpty).join('–');
                        return real.isNotEmpty
                            ? real
                            : [places[i].arrivalTime, places[i].departureTime].where((t) => t != null && t.isNotEmpty).join('–');
                      }(),
                      style: _t(8.5, color: muted),
                    ),
                    pw.Text(places[i].lat != null ? _gridOf(places[i]) : '—', style: _t(8.5, font: fonts.bodyBold, color: muted)),
                    pw.Text(places[i].cost > 0 ? money(places[i].cost) : 'Libre', textAlign: pw.TextAlign.right, style: _t(8.5)),
                  ],
                ),
            ],
          ),
          pw.SizedBox(height: 18),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Presupuesto
              pw.Expanded(
                child: pw.Container(
                  padding: const pw.EdgeInsets.all(14),
                  decoration: pw.BoxDecoration(
                    color: cream,
                    borderRadius: const pw.BorderRadius.all(pw.Radius.circular(12)),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      _eyebrow('Presupuesto por persona'),
                      pw.SizedBox(height: 8),
                      _budgetRow('Entradas y consumo', _placesCost),
                      _budgetRow('Traslados', _transfersCost),
                      if (places.any((p) => p.realCost != null))
                        _budgetRow('Lo que de verdad gastaron',
                            places.fold(0.0, (a, p) => a + (p.realCost ?? 0))),
                      pw.Divider(color: line, thickness: 0.7),
                      pw.Row(children: [
                        pw.Text('Total aproximado', style: _t(10, font: fonts.bodyBold)),
                        pw.Spacer(),
                        pw.Text(total > 0 ? money(total) : 'Gratis', style: _t(16, font: fonts.heading, color: teal)),
                      ]),
                    ],
                  ),
                ),
              ),
              pw.SizedBox(width: 14),
              // QR
              pw.Container(
                width: 170,
                padding: const pw.EdgeInsets.all(14),
                decoration: pw.BoxDecoration(
                  color: tealDeep,
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(12)),
                ),
                child: pw.Column(
                  children: [
                    pw.Container(
                      padding: const pw.EdgeInsets.all(6),
                      color: PdfColors.white,
                      child: pw.BarcodeWidget(barcode: pw.Barcode.qrCode(), data: qrUrl, width: 92, height: 92, color: tealDeep, drawText: false),
                    ),
                    pw.SizedBox(height: 8),
                    pw.Text(
                      'Mapa en vivo, cambios y la crónica del viaje',
                      textAlign: pw.TextAlign.center,
                      style: _t(8, font: fonts.bodySemiBold, color: PdfColors.white, height: 1.5),
                    ),
                  ],
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 18),
          _eyebrow('Para recordar'),
          pw.SizedBox(height: 4),
          pw.Expanded(
            child: pw.LayoutBuilder(builder: (context, c) {
              final count = ((c?.maxHeight ?? 200) / 24).floor().clamp(3, 14);
              return pw.Column(children: [
                for (var k = 0; k < count; k++)
                  pw.Container(
                    height: 24,
                    decoration: pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: line, width: 0.7))),
                  ),
              ]);
            }),
          ),
          pw.SizedBox(height: 10),
          pw.Row(
            children: [
              pw.SvgImage(svg: _logoSvg('#2C666E'), width: 54),
              pw.SizedBox(width: 10),
              pw.Expanded(
                child: pw.Text(
                  'Hecho con Ohtli · ohtli.quest${_map != null ? '   ·   Mapa base © Esri, HERE, Garmin y colaboradores de OpenStreetMap' : ''}',
                  style: _t(7, color: muted),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  pw.Widget _budgetRow(String label, double amount) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 5),
        child: pw.Row(children: [
          pw.Text(label, style: _t(9, color: muted)),
          pw.Spacer(),
          pw.Text(amount > 0 ? money(amount) : '—', style: _t(9.5, font: fonts.bodySemiBold)),
        ]),
      );

  // ───────────────────────── Gráficos ─────────────────────────
  static String _star(bool filled) =>
      '<svg viewBox="0 0 24 24"><path fill="${filled ? '#E2711D' : '#DCD8CF'}" d="M12 17.27L18.18 21l-1.64-7.03L22 9.24l-7.19-.61L12 2 9.19 8.63 2 9.24l5.46 4.73L5.82 21z"/></svg>';

  /// Logotipo de Ohtli (trazos del isotipo y la palabra) en el color pedido.
  static String _logoSvg(String color) => '''
<svg viewBox="0 0 177 53"><g fill="$color">
<path d="M25.88,0.01C60.43,-1.03 60.12,53.07 25.88,52.23C-8.74,53.38 -8.51,-0.87 25.88,0.01ZM32.64,24.01C17.2,-1.04 18.91,3.21 19.69,28.98C34.3,52.46 33,49.06 32.64,24.02L32.64,24.01Z"/>
<path d="M25.85,23.32C29.52,23.11 29.49,29.11 25.85,28.93C22.17,29.15 22.2,23.13 25.85,23.32Z"/>
<g transform="matrix(1,0,0,1,43,0)"><path d="M70.79,50.67C67.12,50.67 64.22,49.82 62.1,48.11C59.98,46.4 58.93,43.61 58.93,39.75L58.93,25.73C58.93,24.81 58.73,24.12 58.32,23.67C57.91,23.22 57.44,22.85 56.9,22.56C56.36,22.27 55.89,21.92 55.48,21.5C55.07,21.08 54.87,20.44 54.87,19.58C54.87,18.72 55.18,18.01 55.8,17.5C56.42,17 57.15,16.74 57.99,16.74L59.44,16.74C60.06,16.74 60.68,16.42 61.29,15.79C61.9,15.16 62.52,14.37 63.16,13.42C63.79,12.47 64.46,11.53 65.16,10.6C65.86,9.67 66.6,8.88 67.4,8.25C68.19,7.62 69.07,7.3 70.01,7.3C71.08,7.3 71.92,7.6 72.52,8.2C73.12,8.8 73.42,9.64 73.42,10.71L73.42,16.74L80.74,16.74C81.56,16.74 82.25,16.93 82.83,17.32C83.41,17.71 83.7,18.35 83.7,19.25C83.7,20.45 83.32,21.37 82.56,21.99C81.8,22.61 80.88,23.03 79.8,23.23C78.73,23.43 77.72,23.54 76.77,23.54L73.42,23.54L73.42,36.3C73.42,37.35 73.62,38.35 74.03,39.28C74.44,40.21 75.28,40.68 76.54,40.68C77.38,40.68 78.09,40.44 78.68,39.95C79.27,39.47 79.83,38.99 80.36,38.52C80.89,38.05 81.45,37.81 82.05,37.81C82.61,37.81 83,38.08 83.23,38.62C83.46,39.16 83.57,39.64 83.57,40.07C83.57,42.24 82.91,44.12 81.6,45.71C80.29,47.3 78.65,48.52 76.69,49.38C74.72,50.24 72.75,50.67 70.78,50.67L70.79,50.67Z"/></g>
<g transform="matrix(1,0,0,1,-33,0)"><path d="M101.67,1.27C102.55,1.27 103.23,1.58 103.7,2.19C104.17,2.8 104.41,3.52 104.41,4.33L104.41,21.76C106.13,20.19 108.01,18.79 110.07,17.55C112.12,16.31 114.18,15.7 116.24,15.7C118.3,15.7 120.07,16.21 121.48,17.23C122.89,18.25 123.94,19.59 124.65,21.24C125.36,22.89 125.71,24.69 125.71,26.62L125.71,40.03C125.71,40.78 125.73,41.36 125.77,41.77C125.81,42.18 125.95,42.55 126.17,42.88C126.39,43.21 126.77,43.67 127.28,44.25C127.71,44.72 128.01,45.1 128.18,45.38C128.35,45.66 128.44,46.13 128.44,46.8C128.44,47.75 128.15,48.47 127.57,48.97C126.99,49.47 126.24,49.73 125.31,49.73L111.71,49.73C110.81,49.73 110.11,49.46 109.62,48.92C109.13,48.38 108.88,47.67 108.88,46.79C108.88,45.97 109.07,45.35 109.46,44.92C109.85,44.49 110.23,44.01 110.62,43.49C111.01,42.96 111.2,42.18 111.2,41.15L111.2,30.1C111.2,29.05 110.99,28.05 110.57,27.1C110.15,26.15 109.31,25.68 108.04,25.68C107.27,25.68 106.59,25.83 106.01,26.12C105.43,26.41 104.89,26.78 104.4,27.23L104.4,40.86C104.4,41.85 104.52,42.6 104.75,43.1C104.99,43.6 105.26,44.01 105.57,44.31C105.88,44.61 106.16,44.93 106.39,45.28C106.62,45.63 106.74,46.13 106.74,46.79C106.74,47.67 106.49,48.38 106,48.92C105.51,49.46 104.81,49.73 103.91,49.73L90.31,49.73C89.39,49.73 88.63,49.48 88.04,48.99C87.45,48.5 87.15,47.77 87.15,46.8C87.15,46.07 87.29,45.51 87.57,45.11C87.85,44.71 88.17,44.36 88.52,44.05C88.87,43.74 89.19,43.34 89.47,42.84C89.75,42.35 89.89,41.64 89.89,40.71L89.89,14.32C89.89,13.35 89.73,12.63 89.42,12.14C89.11,11.66 88.74,11.28 88.32,11C87.9,10.72 87.53,10.41 87.22,10.07C86.91,9.73 86.75,9.2 86.75,8.49C86.75,7.65 87.03,6.99 87.59,6.51C88.15,6.03 88.77,5.65 89.46,5.37L96.49,2.57C97.31,2.25 98.14,1.95 99,1.68C99.86,1.41 100.74,1.28 101.64,1.28L101.67,1.27Z"/></g>
<path d="M146.75,1.27C147.63,1.27 148.31,1.57 148.8,2.17C149.28,2.77 149.52,3.49 149.52,4.33L149.52,40.04C149.52,40.66 149.55,41.27 149.62,41.86C149.68,42.45 149.95,42.98 150.43,43.46C151.01,44.04 151.51,44.51 151.93,44.86C152.35,45.21 152.56,45.86 152.56,46.81C152.56,47.76 152.26,48.51 151.66,49C151.06,49.49 150.3,49.74 149.37,49.74L135.19,49.74C134.27,49.74 133.5,49.49 132.9,49C132.3,48.51 132,47.78 132,46.81C132,45.99 132.15,45.4 132.45,45.02C132.75,44.64 133.11,44.32 133.51,44.04C133.92,43.76 134.27,43.37 134.57,42.86C134.87,42.36 135.02,41.55 135.02,40.46L135.02,14.32C135.02,13.29 134.85,12.54 134.5,12.06C134.16,11.59 133.75,11.23 133.29,10.98C132.83,10.73 132.43,10.44 132.08,10.11C131.74,9.78 131.56,9.23 131.56,8.48C131.56,7.62 131.84,6.95 132.4,6.48C132.96,6.01 133.59,5.63 134.3,5.35L141.49,2.55C142.35,2.21 143.21,1.91 144.07,1.65C144.93,1.39 145.82,1.26 146.74,1.26L146.75,1.27Z"/>
<path d="M170.53,15.7C171.41,15.7 172.09,16 172.58,16.6C173.06,17.2 173.3,17.92 173.3,18.76L173.3,40.03C173.3,40.63 173.33,41.24 173.38,41.85C173.43,42.46 173.68,42.99 174.11,43.45C174.67,44.05 175.14,44.52 175.51,44.87C175.88,45.22 176.07,45.86 176.07,46.8C176.07,47.74 175.77,48.47 175.18,48.97C174.59,49.47 173.83,49.73 172.91,49.73L159.21,49.73C158.29,49.73 157.53,49.48 156.94,48.99C156.35,48.5 156.05,47.77 156.05,46.8C156.05,45.83 156.23,45.23 156.6,44.85C156.97,44.47 157.44,44.01 158.02,43.45C158.45,43.02 158.69,42.48 158.74,41.84C158.79,41.2 158.82,40.59 158.82,40.04L158.82,28.79C158.82,28.36 158.79,27.91 158.72,27.45C158.66,26.99 158.47,26.6 158.17,26.27C158.08,26.16 157.98,26.08 157.86,26.01C157.74,25.95 157.64,25.87 157.55,25.78C157.08,25.29 156.64,24.88 156.25,24.57C155.85,24.26 155.65,23.71 155.65,22.91C155.65,22.05 155.92,21.38 156.46,20.91C157,20.44 157.63,20.06 158.36,19.78L165.32,16.98C166.14,16.66 166.99,16.36 167.87,16.09C168.75,15.82 169.63,15.69 170.51,15.69L170.53,15.7ZM165.7,15.57C164.32,15.57 162.94,15.37 161.54,14.96C160.14,14.55 158.98,13.87 158.04,12.91C157.11,11.95 156.64,10.66 156.64,9.03C156.64,7.4 157.11,6.11 158.06,5.18C159.01,4.25 160.18,3.58 161.57,3.2C162.96,2.82 164.34,2.62 165.69,2.62C167.04,2.62 168.42,2.81 169.83,3.2C171.24,3.59 172.42,4.25 173.37,5.18C174.32,6.11 174.8,7.4 174.8,9.03C174.8,10.66 174.33,11.99 173.38,12.95C172.43,13.91 171.26,14.58 169.85,14.98C168.44,15.38 167.05,15.58 165.68,15.58L165.7,15.57Z"/>
</g></svg>''';
}

/// Mapa estilo atlas: teselas de calles, cuadrícula A–F × 1–8, ruta, pines, escala y norte.
class _AtlasMap {
  _AtlasMap(this.points, {required this.width, required this.height}) {
    _fit();
  }

  final List<(double, double)> points;
  final double width;
  final double height;
  static const int cols = 6;
  static const int rows = 8;
  static const double tile = 256;

  late int zoom;

  /// Acercamiento intermedio entre dos niveles del mapa (1–2): la ruta llena el recuadro.
  late double k;
  late double originX; // píxel mundial de la esquina superior izquierda
  late double originY;
  final Map<String, pw.ImageProvider> _tiles = {};
  final Map<String, pw.ImageProvider> _labels = {};

  static double _wx(double lng, int z) => (lng + 180) / 360 * tile * math.pow(2, z);
  static double _wy(double lat, int z) {
    final s = math.sin(lat * math.pi / 180);
    return (0.5 - math.log((1 + s) / (1 - s)) / (4 * math.pi)) * tile * math.pow(2, z);
  }

  void _fit() {
    final lats = points.map((p) => p.$1), lngs = points.map((p) => p.$2);
    final minLat = lats.reduce(math.min), maxLat = lats.reduce(math.max);
    final minLng = lngs.reduce(math.min), maxLng = lngs.reduce(math.max);
    zoom = 12;
    for (var z = 17; z >= 10; z--) {
      final w = _wx(maxLng, z) - _wx(minLng, z);
      final h = _wy(minLat, z) - _wy(maxLat, z);
      if (w <= width * 0.72 && h <= height * 0.72) {
        zoom = z;
        break;
      }
    }
    final w = _wx(maxLng, zoom) - _wx(minLng, zoom);
    final h = _wy(minLat, zoom) - _wy(maxLat, zoom);
    k = math.min(w > 0 ? width * 0.8 / w : 2.0, h > 0 ? height * 0.8 / h : 2.0).clamp(1.0, 1.95);
    final cx = (_wx(minLng, zoom) + _wx(maxLng, zoom)) / 2 * k;
    final cy = (_wy(minLat, zoom) + _wy(maxLat, zoom)) / 2 * k;
    originX = cx - width / 2;
    originY = cy - height / 2;
  }

  /// Posición en el recuadro del mapa (origen arriba a la izquierda).
  (double, double) pos(double lat, double lng) => (_wx(lng, zoom) * k - originX, _wy(lat, zoom) * k - originY);

  /// Tamaño en el PDF de cada tesela (se piden un nivel más cerca: medio cuadro, escalado).
  double get tileSize => tile / 2 * k;

  String gridRef(double lat, double lng) {
    final (x, y) = pos(lat, lng);
    final c = (x / (width / cols)).floor().clamp(0, cols - 1);
    final r = (y / (height / rows)).floor().clamp(0, rows - 1);
    return '${String.fromCharCode(65 + c)}${r + 1}';
  }

  /// Mapa base gris claro de Esri un nivel más cerca (calles nítidas al imprimir) y encima su
  /// capa de nombres, también un nivel más cerca: letra chica y nombres de calles y colonias.
  Future<void> loadTiles(TripPdfFetcher fetch) async {
    const base = 'https://server.arcgisonline.com/ArcGIS/rest/services/Canvas';
    final jobs = <Future<void>>[];
    void grid(int z, String layer, Map<String, pw.ImageProvider> into) {
      final left = originX / tileSize, top = originY / tileSize;
      final right = (originX + width) / tileSize, bottom = (originY + height) / tileSize;
      for (var x = left.floor(); x <= right.floor(); x++) {
        for (var y = top.floor(); y <= bottom.floor(); y++) {
          final url = '$base/$layer/MapServer/tile/$z/$y/$x';
          jobs.add(() async {
            try {
              final bytes = await fetch(url);
              if (bytes != null && TripPdfBuilder._decodable(bytes)) into['$x/$y'] = pw.MemoryImage(bytes);
            } catch (_) {}
          }());
        }
      }
    }

    grid(zoom + 1, 'World_Light_Gray_Base', _tiles);
    grid(zoom + 1, 'World_Light_Gray_Reference', _labels);
    await Future.wait(jobs);
  }

  List<(double, double)> _pinSpots(List<(double, double, int)> pins) {
    final spots = <(double, double)>[];
    for (final p in pins) {
      var (x, y) = pos(p.$1, p.$2);
      var tries = 0;
      while (tries++ < 6 && spots.any((s) => (s.$1 - x).abs() < 18 && (s.$2 - y).abs() < 18)) {
        x += 15;
        y -= 7;
      }
      spots.add((x, y));
    }
    return spots;
  }

  /// Metros que mide un punto del PDF en la latitud del centro.
  double get _metersPerPt {
    final lat = points.map((p) => p.$1).reduce((a, b) => a + b) / points.length;
    return 156543.03392 * math.cos(lat * math.pi / 180) / math.pow(2, zoom) / k;
  }

  pw.Widget widget({
    required List<(double, double, int)> pins,
    required PdfColor Function(int) colorFor,
    required pw.TextStyle labelStyle,
    required pw.TextStyle gridStyle,
    required pw.TextStyle smallStyle,
  }) {
    const gutter = 14.0;
    final cellW = width / cols, cellH = height / rows;

    // Escala: un número redondo cercano a 1/5 del ancho
    final targetM = _metersPerPt * width / 5;
    final steps = [100, 200, 250, 500, 1000, 2000, 2500, 5000];
    final meters = steps.lastWhere((m) => m <= targetM, orElse: () => steps.first);
    final barW = meters / _metersPerPt;

    final map = pw.SizedBox(
      width: width,
      height: height,
      child: pw.Stack(
        overflow: pw.Overflow.clip,
        children: [
          pw.Container(color: PdfColor.fromHex('#EDEDEB')),
          for (final e in _tiles.entries)
            () {
              final xy = e.key.split('/').map(int.parse).toList();
              return pw.Positioned(
                left: xy[0] * tileSize - originX,
                top: xy[1] * tileSize - originY,
                child: pw.SizedBox(width: tileSize, height: tileSize, child: pw.Image(e.value, fit: pw.BoxFit.fill)),
              );
            }(),
          for (final e in _labels.entries)
            () {
              final xy = e.key.split('/').map(int.parse).toList();
              return pw.Positioned(
                left: xy[0] * tileSize - originX,
                top: xy[1] * tileSize - originY,
                child: pw.SizedBox(width: tileSize, height: tileSize, child: pw.Image(e.value, fit: pw.BoxFit.fill)),
              );
            }(),
          // Cuadrícula y ruta
          pw.CustomPaint(
            size: PdfPoint(width, height),
            painter: (canvas, size) {
              canvas.setStrokeColor(PdfColor.fromHex('#A39E95'));
              canvas.setLineWidth(0.4);
              canvas.setLineDashPattern([2, 3]);
              for (var c = 1; c < cols; c++) {
                canvas
                  ..moveTo(c * cellW, 0)
                  ..lineTo(c * cellW, height);
              }
              for (var r = 1; r < rows; r++) {
                canvas
                  ..moveTo(0, r * cellH)
                  ..lineTo(width, r * cellH);
              }
              canvas.strokePath();
              canvas.setLineDashPattern([]);
              if (pins.length > 1) {
                final ordered = [...pins]..sort((a, b) => a.$3.compareTo(b.$3));
                void path() {
                  for (var i = 0; i < ordered.length; i++) {
                    final (x, y) = pos(ordered[i].$1, ordered[i].$2);
                    if (i == 0) {
                      canvas.moveTo(x, height - y);
                    } else {
                      canvas.lineTo(x, height - y);
                    }
                  }
                }

                canvas
                  ..setLineCap(PdfLineCap.round)
                  ..setLineJoin(PdfLineJoin.round)
                  ..setStrokeColor(PdfColors.white)
                  ..setLineWidth(6);
                path();
                canvas.strokePath();
                canvas
                  ..setStrokeColor(PdfColor.fromHex('#2C666E'))
                  ..setLineWidth(3);
                path();
                canvas.strokePath();
              }
            },
          ),
          // Pines numerados (si uno cae encima de otro, se recorre un poco para que ambos se lean)
          for (final (i, p) in pins.indexed)
            () {
              final (x, y) = _pinSpots(pins)[i];
              return pw.Positioned(
                left: x - 11,
                top: y - 11,
                child: pw.Container(
                  width: 22,
                  height: 22,
                  alignment: pw.Alignment.center,
                  decoration: pw.BoxDecoration(
                    color: colorFor(p.$3),
                    shape: pw.BoxShape.circle,
                    border: pw.Border.all(color: PdfColors.white, width: 2),
                  ),
                  child: pw.Text('${p.$3 + 1}', style: labelStyle),
                ),
              );
            }(),
          // Escala
          pw.Positioned(
            left: 12,
            bottom: 12,
            child: pw.Container(
              padding: const pw.EdgeInsets.fromLTRB(6, 4, 6, 4),
              color: PdfColors.white,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Row(children: [
                    pw.Container(width: barW / 2, height: 4, color: PdfColors.black),
                    pw.Container(
                      width: barW / 2,
                      height: 4,
                      decoration: pw.BoxDecoration(
                        color: PdfColors.white,
                        border: pw.Border.all(color: PdfColors.black, width: 0.6),
                      ),
                    ),
                  ]),
                  pw.Container(width: barW, height: 0.8, color: PdfColors.black),
                  pw.SizedBox(height: 2),
                  pw.Text(meters >= 1000 ? '${meters ~/ 1000} km' : '$meters m', style: smallStyle),
                ],
              ),
            ),
          ),
          // Norte
          pw.Positioned(
            right: 12,
            top: 12,
            child: pw.Container(
              width: 26,
              height: 34,
              padding: const pw.EdgeInsets.all(3),
              color: PdfColors.white,
              child: pw.Column(children: [
                pw.CustomPaint(
                  size: const PdfPoint(12, 14),
                  painter: (canvas, size) {
                    canvas
                      ..setFillColor(PdfColor.fromHex('#0A090C'))
                      ..moveTo(size.x / 2, size.y)
                      ..lineTo(size.x, 0)
                      ..lineTo(size.x / 2, 4)
                      ..lineTo(0, 0)
                      ..fillPath();
                  },
                ),
                pw.Text('N', style: gridStyle),
              ]),
            ),
          ),
        ],
      ),
    );

    // Marco con letras y números de la cuadrícula, como un atlas
    return pw.Column(
      children: [
        pw.Row(children: [
          pw.SizedBox(width: gutter),
          for (var c = 0; c < cols; c++)
            pw.SizedBox(width: cellW, child: pw.Center(child: pw.Text(String.fromCharCode(65 + c), style: gridStyle))),
        ]),
        pw.SizedBox(height: 2),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.SizedBox(
              width: gutter,
              child: pw.Column(children: [
                for (var r = 0; r < rows; r++)
                  pw.SizedBox(height: cellH, child: pw.Center(child: pw.Text('${r + 1}', style: gridStyle))),
              ]),
            ),
            pw.Container(
              decoration: pw.BoxDecoration(
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(14)),
                border: pw.Border.all(color: PdfColor.fromHex('#D6D1C8'), width: 0.8),
              ),
              child: pw.ClipRRect(horizontalRadius: 14, verticalRadius: 14, child: map),
            ),
          ],
        ),
      ],
    );
  }
}

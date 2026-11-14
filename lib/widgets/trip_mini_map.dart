import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/colors.dart';

/// Parada que se dibuja en el mini mapa.
class MiniMapStop {
  final double lat;
  final double lng;
  final int number;
  final bool visited;
  final bool isNext;

  /// Desvío (lugar no previsto): punto pequeño sin número.
  final bool unplanned;

  const MiniMapStop({
    required this.lat,
    required this.lng,
    required this.number,
    this.visited = false,
    this.isNext = false,
    this.unplanned = false,
  });
}

/// Mapa estático con teselas de OpenStreetMap, la ruta punteada y las paradas numeradas.
/// No captura gestos: quien lo usa decide qué pasa al tocarlo (p. ej. abrir la ruta completa).
class TripMiniMap extends StatelessWidget {
  final List<MiniMapStop> stops;
  final bool isDark;

  /// Centro por defecto cuando no hay paradas con ubicación (Centro Histórico).
  static const double _defaultLat = 19.4326;
  static const double _defaultLng = -99.1332;

  const TripMiniMap({super.key, required this.stops, this.isDark = false});

  static const double _tile = 256;

  static Offset _world(double lat, double lng, num zoom) {
    final scale = _tile * math.pow(2, zoom);
    final x = (lng + 180) / 360 * scale;
    final s = math.sin(lat * math.pi / 180).clamp(-0.9999, 0.9999);
    final y = (0.5 - math.log((1 + s) / (1 - s)) / (4 * math.pi)) * scale;
    return Offset(x, y);
  }

  /// Zoom (con decimales) que encuadra todas las paradas dentro de [size] con [pad] de margen.
  static double fitZoom(List<MiniMapStop> stops, Size size, {double pad = 30}) {
    if (stops.length < 2) return 15;
    double minX = double.infinity, minY = double.infinity, maxX = -double.infinity, maxY = -double.infinity;
    for (final s in stops) {
      final p = _world(s.lat, s.lng, 0);
      minX = math.min(minX, p.dx);
      maxX = math.max(maxX, p.dx);
      minY = math.min(minY, p.dy);
      maxY = math.max(maxY, p.dy);
    }
    final availW = math.max(40.0, size.width - pad * 2);
    final availH = math.max(40.0, size.height - pad * 2);
    final zx = math.log(availW / math.max(maxX - minX, 1e-9)) / math.ln2;
    final zy = math.log(availH / math.max(maxY - minY, 1e-9)) / math.ln2;
    return math.min(zx, zy).clamp(3.0, 16.0).toDouble();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final size = Size(box.maxWidth, box.maxHeight);
      final double fit = stops.isEmpty ? 12 : fitZoom(stops, size);
      final int zoom = fit.floor();
      // Escala entre el nivel entero de teselas y el encuadre exacto (1 ≤ k < 2).
      final double k = math.pow(2, fit - zoom).toDouble();

      // Centro: punto medio del encuadre (en píxeles del mundo).
      Offset center;
      if (stops.isEmpty) {
        center = _world(_defaultLat, _defaultLng, zoom);
      } else {
        double minX = double.infinity, minY = double.infinity, maxX = -double.infinity, maxY = -double.infinity;
        for (final s in stops) {
          final p = _world(s.lat, s.lng, zoom);
          minX = math.min(minX, p.dx);
          maxX = math.max(maxX, p.dx);
          minY = math.min(minY, p.dy);
          maxY = math.max(maxY, p.dy);
        }
        center = Offset((minX + maxX) / 2, (minY + maxY) / 2);
      }
      Offset toView(Offset world) => (world - center) * k + Offset(size.width / 2, size.height / 2);

      // En pantallas densas se piden teselas de un nivel más y se dibujan a la mitad: el mapa se ve nítido.
      final double dpr = MediaQuery.maybeOf(context)?.devicePixelRatio ?? 1;
      final int tileZoom = math.min(19, zoom + (dpr >= 1.5 ? 1 : 0));
      final double factor = math.pow(2, tileZoom - zoom).toDouble();
      final double shown = _tile / factor * k;
      final double left = (center.dx - size.width / 2 / k) * factor;
      final double top = (center.dy - size.height / 2 / k) * factor;
      final int maxIndex = (1 << tileZoom) - 1;

      final tiles = <Widget>[];
      for (int tx = (left / _tile).floor(); tx <= ((left + size.width / k * factor) / _tile).floor(); tx++) {
        for (int ty = (top / _tile).floor(); ty <= ((top + size.height / k * factor) / _tile).floor(); ty++) {
          if (ty < 0 || ty > maxIndex) continue;
          final wrappedX = ((tx % (maxIndex + 1)) + (maxIndex + 1)) % (maxIndex + 1);
          Widget img = Image.network(
            'https://tile.openstreetmap.org/$tileZoom/$wrappedX/$ty.png',
            fit: BoxFit.cover,
            filterQuality: FilterQuality.medium,
            gaplessPlayback: true,
            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
          );
          if (isDark) {
            img = ColorFiltered(
              colorFilter: const ColorFilter.matrix(<double>[
                -0.17, -0.57, -0.06, 0, 222, //
                -0.17, -0.57, -0.06, 0, 228, //
                -0.17, -0.57, -0.06, 0, 234, //
                0, 0, 0, 1, 0,
              ]),
              child: img,
            );
          }
          tiles.add(Positioned(
            left: (tx * _tile - left) / factor * k,
            top: (ty * _tile - top) / factor * k,
            width: shown + 0.5,
            height: shown + 0.5,
            child: img,
          ));
        }
      }

      final points = [for (final s in stops) toView(_world(s.lat, s.lng, zoom))];

      return ClipRect(
        child: Stack(
          children: [
            Positioned.fill(child: ColoredBox(color: isDark ? const Color(0xFF1E1E22) : const Color(0xFFE9ECEA))),
            ...tiles,
            // Velo suave para que la ruta resalte sobre el mapa.
            Positioned.fill(
              child: ColoredBox(color: (isDark ? Colors.black : Colors.white).withValues(alpha: isDark ? 0.18 : 0.22)),
            ),
            Positioned.fill(
              child: CustomPaint(painter: _RoutePainter(points: points, stops: stops, isDark: isDark)),
            ),
            Positioned(
              left: 6,
              bottom: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: (isDark ? Colors.black : Colors.white).withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text('© OpenStreetMap',
                    style: GoogleFonts.inter(fontSize: 9, color: isDark ? Colors.white70 : OhtliColors.subtleText)),
              ),
            ),
          ],
        ),
      );
    });
  }
}

class _RoutePainter extends CustomPainter {
  final List<Offset> points;
  final List<MiniMapStop> stops;
  final bool isDark;

  _RoutePainter({required this.points, required this.stops, required this.isDark});

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;
    const teal = OhtliColors.stormyTeal;
    final line = Paint()
      ..color = teal
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final halo = Paint()
      ..color = Colors.white.withValues(alpha: isDark ? 0.35 : 0.9)
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    for (int i = 0; i + 1 < points.length; i++) {
      final a = points[i];
      final b = points[i + 1];
      final d = b - a;
      final len = d.distance;
      if (len < 1) continue;
      final dir = d / len;
      const dash = 7.0, gap = 5.0;
      for (double t = 0; t < len; t += dash + gap) {
        final p1 = a + dir * t;
        final p2 = a + dir * math.min(t + dash, len);
        canvas.drawLine(p1, p2, halo);
        canvas.drawLine(p1, p2, line);
      }
    }

    for (int i = 0; i < points.length; i++) {
      final s = stops[i];
      final p = points[i];
      if (s.unplanned) {
        canvas.drawCircle(p, 6.5, Paint()..color = Colors.white);
        canvas.drawCircle(p, 4.5, Paint()..color = OhtliColors.cempasuchil);
        continue;
      }
      final Color fill = s.isNext ? OhtliColors.cempasuchil : (s.visited ? teal : Colors.white);
      canvas.drawCircle(p + const Offset(0, 1.5), 12.5, Paint()..color = Colors.black.withValues(alpha: 0.18));
      canvas.drawCircle(p, 12, Paint()..color = fill);
      canvas.drawCircle(
        p,
        12,
        Paint()
          ..color = s.visited || s.isNext ? Colors.white : teal
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
      final tp = TextPainter(
        text: TextSpan(
          text: '${s.number}',
          style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w800, color: s.visited || s.isNext ? Colors.white : teal),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, p - Offset(tp.width / 2, tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(covariant _RoutePainter old) => old.points != points || old.isDark != isDark || old.stops != stops;
}

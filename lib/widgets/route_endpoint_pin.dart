import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/colors.dart';

/// Qué extremo del recorrido marca el pin.
enum EndpointKind { start, end, both }

Color endpointColor(EndpointKind k) => k == EndpointKind.end ? OhtliColors.xoconostle : OhtliColors.stormyTeal;

String endpointLabel(EndpointKind k) => switch (k) {
      EndpointKind.start => 'Inicio',
      EndpointKind.end => 'Fin',
      EndpointKind.both => 'Inicio y fin',
    };

/// Pin de Ohtli (assets/pin.svg) para el inicio (verde azulado, «I»), el fin (morado, «F») o
/// los dos a la vez (sin letra). La punta queda abajo a la derecha: el pin va inclinado.
class RouteEndpointPin extends StatelessWidget {
  const RouteEndpointPin({super.key, required this.kind, this.height = 52});

  final EndpointKind kind;
  final double height;

  /// Proporción del pin (ancho / alto).
  static const double aspect = 28 / 52;

  double get width => height * aspect;

  @override
  Widget build(BuildContext context) {
    final color = endpointColor(kind);
    final letter = switch (kind) { EndpointKind.start => 'I', EndpointKind.end => 'F', EndpointKind.both => '' };
    final s = height / 52;
    return SizedBox(
      width: width,
      height: height,
      child: Stack(
        children: [
          Positioned.fill(
            child: SvgPicture.asset('assets/pin.svg', colorFilter: ColorFilter.mode(color, BlendMode.srcIn)),
          ),
          if (letter.isNotEmpty && height >= 26)
            Positioned(
              left: 8 * s,
              top: 8 * s,
              width: 12 * s,
              height: 14 * s,
              child: Center(
                child: Text(letter,
                    style: GoogleFonts.inter(fontSize: 9 * s, fontWeight: FontWeight.w900, color: color, height: 1)),
              ),
            ),
        ],
      ),
    );
  }
}

/// Color legible del texto de un extremo sobre el fondo (en modo oscuro, más claro).
Color endpointInk(EndpointKind k, bool isDark) {
  if (!isDark) return endpointColor(k);
  return k == EndpointKind.end ? OhtliColors.accentLight : Color.lerp(OhtliColors.stormyTeal, Colors.white, 0.45)!;
}

/// Etiqueta «Inicio» / «Fin» / «Inicio y fin» con el pin de Ohtli, para la parada en la que
/// empieza o termina el recorrido.
class EndpointTag extends StatelessWidget {
  const EndpointTag({super.key, required this.kind, this.isDark = false, this.label});

  final EndpointKind kind;
  final bool isDark;

  /// Texto en lugar del de [kind].
  final String? label;

  @override
  Widget build(BuildContext context) {
    final color = endpointColor(kind);
    final ink = endpointInk(kind, isDark);
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 2, 9, 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.24 : 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          RouteEndpointPin(kind: kind, height: 17),
          const SizedBox(width: 4),
          Flexible(
            child: Text(label ?? endpointLabel(kind),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w800, color: ink)),
          ),
        ],
      ),
    );
  }
}

EndpointKind? endpointKindOf(String? label) => switch (label) {
      'Inicio' => EndpointKind.start,
      'Fin' => EndpointKind.end,
      'Inicio y fin' => EndpointKind.both,
      _ => null,
    };

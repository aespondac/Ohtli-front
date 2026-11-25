import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/colors.dart';
import 'ohtli_ui.dart';

/// Texto del aviso para lugares que Google marca como cerrados por ahora.
const String kClosedTemporarilyLabel = 'Cerrado temporalmente';
const String kClosedPermanentlyLabel = 'Cerró definitivamente';

/// Píldora "Cerrado temporalmente" para tarjetas y portadas (se lee sobre foto y sobre fondo claro).
class PoiClosedBadge extends StatelessWidget {
  final bool small;
  /// Cerró definitivamente (en vez de por ahora).
  final bool permanent;

  const PoiClosedBadge({super.key, this.small = false, this.permanent = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: small ? 8 : 10, vertical: small ? 3 : 6),
      decoration: BoxDecoration(
        color: OhtliColors.warning,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.white.withValues(alpha: 0.22), width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(permanent ? Icons.block_rounded : Icons.pause_circle_filled_rounded, size: small ? 11 : 13, color: Colors.white),
          SizedBox(width: small ? 4 : 5),
          Flexible(
            child: Text(
              permanent ? kClosedPermanentlyLabel : kClosedTemporarilyLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(fontSize: small ? 10 : 11, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: 0.1),
            ),
          ),
        ],
      ),
    );
  }
}

/// Aviso del detalle de un lugar cerrado por ahora: qué pasa y qué conviene hacer.
class PoiClosedNotice extends StatelessWidget {
  /// Cerró definitivamente (en vez de por ahora).
  final bool permanent;

  const PoiClosedNotice({super.key, this.permanent = false});

  @override
  Widget build(BuildContext context) {
    const color = OhtliColors.warning;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.pause_circle_filled_rounded, size: 19, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(permanent ? kClosedPermanentlyLabel : kClosedTemporarilyLabel,
                    style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w800, color: OhtliColors.onyx)),
                const SizedBox(height: 3),
                Text(
                  permanent
                      ? 'Este lugar ya no existe. Ya no lo proponemos en rutas; si está en tu viaje, cámbialo por otro.'
                      : 'Google reporta que este lugar no está abriendo por ahora. Confirma antes de ir o de sumarlo a una ruta.',
                  style: OhtliUi.body(size: 13.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

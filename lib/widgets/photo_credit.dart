import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Crédito de una foto de Wikimedia Commons ("Foto: Autor · CC BY-SA 4.0 · Wikimedia Commons"),
/// pequeño sobre la esquina de la imagen; el texto completo, al pasar el cursor. Las licencias de
/// Commons (CC BY, CC BY-SA) piden atribuir autor y licencia junto a la foto.
class PhotoCredit extends StatelessWidget {
  final String credit;
  final double fontSize;

  const PhotoCredit(this.credit, {super.key, this.fontSize = 9});

  /// "Autor · Licencia" sin el prefijo ni la fuente, para que quepa en una miniatura.
  static String short(String credit) {
    var s = credit.trim();
    if (s.toLowerCase().startsWith('foto:')) s = s.substring(5).trim();
    s = s.replaceAll(RegExp(r'\s*·\s*Wikimedia Commons\s*$', caseSensitive: false), '');
    return s;
  }

  @override
  Widget build(BuildContext context) {
    if (credit.trim().isEmpty) return const SizedBox.shrink();
    return Tooltip(
      message: credit,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Text(
          '© ${short(credit)}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.inter(fontSize: fontSize, fontWeight: FontWeight.w500, color: Colors.white),
        ),
      ),
    );
  }
}

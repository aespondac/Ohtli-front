// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:html' as html;
import 'package:flutter/foundation.dart';
import '../theme/colors.dart';
import '../models/poi_model.dart';

class PoiDetailDialog extends StatelessWidget {
  final Poi poi;

  const PoiDetailDialog({super.key, required this.poi});

  static void show(BuildContext context, Poi poi) {
    showDialog(
      context: context,
      builder: (context) => PoiDetailDialog(poi: poi),
    );
  }

  void _openInMaps(double lat, double lng, String name) {
    final query = Uri.encodeComponent('$name ($lat,$lng)');
    final url = 'https://www.google.com/maps/search/?api=1&query=$query';
    if (kIsWeb) {
      html.window.open(url, '_blank');
    }
  }

  void _copyToClipboard(BuildContext context, String text, String message) {
    Clipboard.setData(ClipboardData(text: text)).then((_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message, style: GoogleFonts.inter(color: Colors.white)),
            backgroundColor: OhtliColors.stormyTeal,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isMobile = screenSize.width < 700;

    return Dialog(
      backgroundColor: OhtliColors.cardBg,
      insetPadding: EdgeInsets.symmetric(
        horizontal: isMobile ? 16 : 40,
        vertical: isMobile ? 24 : 40,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(28),
        side: BorderSide(color: OhtliColors.cardBorder),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 750,
          maxHeight: screenSize.height * 0.88,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header with color banner and title
            Container(
              padding: const EdgeInsets.fromLTRB(24, 20, 16, 20),
              decoration: BoxDecoration(
                color: poi.categoryColor.withValues(alpha: 0.12),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                border: Border(bottom: BorderSide(color: OhtliColors.cardBorder)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: poi.categoryColor.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(poi.categoryIcon, color: poi.categoryColor, size: 28),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: poi.categoryColor,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                poi.categoryDisplay.toUpperCase(),
                                style: GoogleFonts.inter(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: OhtliColors.innerCardBg,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: OhtliColors.cardBorder),
                              ),
                              child: Text(
                                poi.priceDisplay,
                                style: GoogleFonts.inter(
                                  color: OhtliColors.onyx,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            if (poi.hasVector) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF10B981).withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.hub_rounded, size: 12, color: Color(0xFF10B981)),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Vector 768d',
                                      style: GoogleFonts.inter(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                        color: const Color(0xFF10B981),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          poi.name,
                          style: GoogleFonts.outfit(
                            fontSize: isMobile ? 20 : 24,
                            fontWeight: FontWeight.w800,
                            color: OhtliColors.onyx,
                            height: 1.2,
                          ),
                        ),
                        if (poi.location.isValid) ...[
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              const Icon(Icons.location_on_rounded, size: 14, color: OhtliColors.stormyTeal),
                              const SizedBox(width: 4),
                              Text(
                                '${poi.location.lat.toStringAsFixed(6)}, ${poi.location.lng.toStringAsFixed(6)}',
                                style: GoogleFonts.firaCode(
                                  fontSize: 12,
                                  color: OhtliColors.subtleText,
                                ),
                              ),
                              const SizedBox(width: 8),
                              InkWell(
                                onTap: () => _copyToClipboard(
                                  context,
                                  '${poi.location.lat}, ${poi.location.lng}',
                                  'Coordenadas copiadas',
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(2),
                                  child: Icon(Icons.copy_rounded, size: 14, color: OhtliColors.subtleText),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(Icons.close_rounded, color: OhtliColors.onyx),
                    style: IconButton.styleFrom(
                      backgroundColor: OhtliColors.innerCardBg,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ],
              ),
            ),

            // Scrollable Content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Urban & Security Badge Row
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (poi.formalidad)
                          _buildAttributeChip(Icons.verified_rounded, 'Negocio Formal (SIAPEM)', const Color(0xFF10B981)),
                        if (poi.patrimonioHistorico)
                          _buildAttributeChip(Icons.account_balance_rounded, 'Patrimonio Histórico', OhtliColors.xoconostle),
                        if (poi.areaVerdeCercana)
                          _buildAttributeChip(Icons.park_rounded, 'Entorno con Áreas Verdes', const Color(0xFF2E7D32)),
                        if (poi.wheelchairAccessible)
                          _buildAttributeChip(Icons.accessible_rounded, 'Accesibilidad Universal', Colors.blue),
                        if (poi.coeficienteMovilidad > 0)
                          _buildAttributeChip(Icons.directions_bike_rounded, 'Ecobici / Red de Movilidad', OhtliColors.cempasuchil),
                        if (poi.musicaEnVivo)
                          _buildAttributeChip(Icons.music_note_rounded, 'Música en Vivo', const Color(0xFF9C27B0)),
                        if (poi.consumoAlcohol)
                          _buildAttributeChip(Icons.local_bar_rounded, 'Bebidas Alcohólicas', const Color(0xFFE91E63)),
                      ],
                    ),

                    if (poi.nivelSeguridad.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: OhtliColors.innerCardBg,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: OhtliColors.cardBorder),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.security_rounded, size: 18, color: OhtliColors.stormyTeal),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Seguridad urbana: ${poi.nivelSeguridad}',
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  color: OhtliColors.onyx,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    // Vibe Tags
                    if (poi.vibeTags.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      Text(
                        'Vibras & Atmósfera Detectadas',
                        style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w700, color: OhtliColors.onyx),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: poi.vibeTags.map((v) {
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: OhtliColors.stormyTeal.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: OhtliColors.stormyTeal.withValues(alpha: 0.2)),
                            ),
                            child: Text(
                              '#$v',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: OhtliColors.stormyTeal,
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],

                    // Semantic OEP Recipe Section (AI Distillation)
                    if (poi.semanticDescription.isNotEmpty || poi.oepAxes.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: OhtliColors.innerCardBg,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: OhtliColors.stormyTeal.withValues(alpha: 0.3)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: OhtliColors.stormyTeal,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 16),
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  'Receta Semántica OEP (Ohtli Entity Profile)',
                                  style: GoogleFonts.outfit(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: OhtliColors.onyx,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            if (poi.oepAxes.isNotEmpty) ...[
                              if (poi.oepAxes.containsKey('vocacion_cultural'))
                                _buildOepAxisItem('Vocación Cultural y Gastronómica', poi.oepAxes['vocacion_cultural']!),
                              if (poi.oepAxes.containsKey('atmosfera_sensorial'))
                                _buildOepAxisItem('Atmósfera y Experiencia Sensorial', poi.oepAxes['atmosfera_sensorial']!),
                              if (poi.oepAxes.containsKey('dinamica_social'))
                                _buildOepAxisItem('Dinámica Social y Perfil de Visitante', poi.oepAxes['dinamica_social']!),
                              if (poi.oepAxes.containsKey('entorno_urbano'))
                                _buildOepAxisItem('Micro-Entorno Urbano y Caminabilidad', poi.oepAxes['entorno_urbano']!),
                            ] else ...[
                              Text(
                                poi.semanticDescription,
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  height: 1.5,
                                  color: OhtliColors.onyx.withValues(alpha: 0.9),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],

                    // Wikipedia / Description Section
                    if (poi.description.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      Text(
                        'Contexto Histórico y Cultural',
                        style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.w700, color: OhtliColors.onyx),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        poi.description,
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          height: 1.5,
                          color: OhtliColors.subtleText,
                        ),
                      ),
                    ],

                    // Editorial summary
                    if (poi.editorialSummary.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      Text(
                        'Resumen Editorial',
                        style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.w700, color: OhtliColors.onyx),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        poi.editorialSummary,
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          height: 1.5,
                          color: OhtliColors.subtleText,
                        ),
                      ),
                    ],

                    // User Reviews / Tips Snippets
                    if (poi.reviewsSnippets.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      Text(
                        'Percepciones y Reseñas de Visitantes',
                        style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.w700, color: OhtliColors.onyx),
                      ),
                      const SizedBox(height: 10),
                      ...poi.reviewsSnippets.map((r) => Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: OhtliColors.innerCardBg,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: OhtliColors.cardBorder),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.format_quote_rounded, size: 16, color: OhtliColors.stormyTeal),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                r,
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  fontStyle: FontStyle.italic,
                                  color: OhtliColors.onyx,
                                  height: 1.4,
                                ),
                              ),
                            ),
                          ],
                        ),
                      )),
                    ],

                    // INEGI & Economic Data
                    if (poi.actividadEconomica.isNotEmpty || poi.tamanoEmpresa.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: OhtliColors.innerCardBg,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: OhtliColors.cardBorder),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Datos Estadísticos INEGI DENUE',
                              style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w700, color: OhtliColors.onyx),
                            ),
                            const SizedBox(height: 8),
                            if (poi.actividadEconomica.isNotEmpty)
                              Text('• Actividad: ${poi.actividadEconomica}', style: GoogleFonts.inter(fontSize: 12, color: OhtliColors.subtleText)),
                            if (poi.tamanoEmpresa.isNotEmpty)
                              Text('• Estrato de personal: ${poi.tamanoEmpresa}', style: GoogleFonts.inter(fontSize: 12, color: OhtliColors.subtleText)),
                          ],
                        ),
                      ),
                    ],

                    // Raw Metadata Footer
                    const SizedBox(height: 24),
                    Text(
                      'ID del Lugar: ${poi.poiId}',
                      style: GoogleFonts.firaCode(fontSize: 11, color: OhtliColors.subtleText),
                    ),
                  ],
                ),
              ),
            ),

            // Footer actions
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              decoration: BoxDecoration(
                color: OhtliColors.innerCardBg,
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28)),
                border: Border(top: BorderSide(color: OhtliColors.cardBorder)),
              ),
              child: Row(
                children: [
                  if (poi.location.isValid)
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => _openInMaps(poi.location.lat, poi.location.lng, poi.name),
                        icon: const Icon(Icons.map_rounded, size: 18),
                        label: const Text('Ver en Google Maps'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: OhtliColors.stormyTeal,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          elevation: 0,
                          textStyle: GoogleFonts.outfit(fontWeight: FontWeight.w600, fontSize: 14),
                        ),
                      ),
                    ),
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    onPressed: () => _copyToClipboard(context, poi.poiId, 'POI ID copiado'),
                    icon: const Icon(Icons.copy_rounded, size: 16),
                    label: const Text('Copiar ID'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: OhtliColors.onyx,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      side: BorderSide(color: OhtliColors.cardBorder),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAttributeChip(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOepAxisItem(String title, String content) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: OhtliColors.stormyTeal,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            content,
            style: GoogleFonts.inter(
              fontSize: 12.5,
              height: 1.45,
              color: OhtliColors.onyx,
            ),
          ),
        ],
      ),
    );
  }
}

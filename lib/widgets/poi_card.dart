// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:html' as html;
import 'package:flutter/foundation.dart';
import '../theme/colors.dart';
import '../models/poi_model.dart';
import 'poi_detail_dialog.dart';

class PoiCard extends StatefulWidget {
  final Poi poi;
  final VoidCallback? onTap;

  const PoiCard({
    super.key,
    required this.poi,
    this.onTap,
  });

  @override
  State<PoiCard> createState() => _PoiCardState();
}

class _PoiCardState extends State<PoiCard> {
  bool _isHovered = false;

  void _openInMaps(double lat, double lng, String name) {
    final query = Uri.encodeComponent('$name ($lat,$lng)');
    final url = 'https://www.google.com/maps/search/?api=1&query=$query';
    if (kIsWeb) {
      html.window.open(url, '_blank');
    }
  }

  void _copyCoords(BuildContext context) {
    if (!widget.poi.location.isValid) return;
    final messenger = ScaffoldMessenger.of(context);
    final text = '${widget.poi.location.lat}, ${widget.poi.location.lng}';
    Clipboard.setData(ClipboardData(text: text)).then((_) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('Coordenadas copiadas al portapapeles', style: GoogleFonts.inter(color: Colors.white)),
            backgroundColor: OhtliColors.stormyTeal,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final poi = widget.poi;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          color: OhtliColors.cardBg,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: _isHovered ? poi.categoryColor.withValues(alpha: 0.6) : OhtliColors.cardBorder,
            width: _isHovered ? 1.5 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: _isHovered
                  ? poi.categoryColor.withValues(alpha: 0.12)
                  : Colors.black.withValues(alpha: 0.04),
              blurRadius: _isHovered ? 20 : 10,
              offset: Offset(0, _isHovered ? 8 : 4),
            ),
          ],
        ),
        child: InkWell(
          onTap: widget.onTap ?? () => PoiDetailDialog.show(context, poi),
          borderRadius: BorderRadius.circular(24),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header: Category Badge + Price + Vector Badge
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: poi.categoryColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(poi.categoryIcon, size: 14, color: poi.categoryColor),
                          const SizedBox(width: 6),
                          Text(
                            poi.categoryDisplay,
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: poi.categoryColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: OhtliColors.innerCardBg,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: OhtliColors.cardBorder),
                      ),
                      child: Text(
                        poi.priceSymbols,
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: OhtliColors.onyx,
                        ),
                      ),
                    ),
                    const Spacer(),
                    if (poi.hasVector)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981).withValues(alpha: 0.12),
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
                ),
                const SizedBox(height: 14),

                // Name of POI
                Text(
                  poi.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.outfit(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: OhtliColors.onyx,
                    height: 1.25,
                  ),
                ),

                // Coordinates pill
                if (poi.location.isValid) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.location_on_outlined, size: 14, color: OhtliColors.stormyTeal),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          '${poi.location.lat.toStringAsFixed(4)}°, ${poi.location.lng.toStringAsFixed(4)}°',
                          style: GoogleFonts.firaCode(fontSize: 11, color: OhtliColors.subtleText),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      InkWell(
                        onTap: () => _copyCoords(context),
                        borderRadius: BorderRadius.circular(6),
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: Icon(Icons.copy_rounded, size: 12, color: OhtliColors.subtleText),
                        ),
                      ),
                    ],
                  ),
                ],

                const SizedBox(height: 12),

                // AI Receta / Semantic Description snippet
                if (poi.semanticDescription.isNotEmpty || poi.description.isNotEmpty) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: OhtliColors.innerCardBg,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: OhtliColors.cardBorder),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.auto_awesome_rounded,
                              size: 13,
                              color: poi.semanticDescription.isNotEmpty ? OhtliColors.stormyTeal : OhtliColors.subtleText,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              poi.semanticDescription.isNotEmpty ? 'Receta Semántica OEP' : 'Contexto Cultural',
                              style: GoogleFonts.inter(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.4,
                                color: poi.semanticDescription.isNotEmpty ? OhtliColors.stormyTeal : OhtliColors.subtleText,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          poi.semanticDescription.isNotEmpty ? poi.semanticDescription : poi.description,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            height: 1.4,
                            color: OhtliColors.onyx.withValues(alpha: 0.85),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],

                // Vibe tags
                if (poi.vibeTags.isNotEmpty) ...[
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: poi.vibeTags.take(4).map((vibe) {
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: OhtliColors.innerCardBg,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: OhtliColors.cardBorder),
                        ),
                        child: Text(
                          '#$vibe',
                          style: GoogleFonts.inter(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                            color: OhtliColors.subtleText,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 12),
                ],

                // Mini attribute indicators (Security, Ecobici, Formal, Patrimonio, etc.)
                Row(
                  children: [
                    if (poi.formalidad)
                      _buildMiniBadge(Icons.verified_rounded, 'Formal', const Color(0xFF10B981)),
                    if (poi.patrimonioHistorico)
                      _buildMiniBadge(Icons.account_balance_rounded, 'Patrimonio', OhtliColors.xoconostle),
                    if (poi.areaVerdeCercana)
                      _buildMiniBadge(Icons.park_rounded, 'Área Verde', const Color(0xFF2E7D32)),
                    if (poi.coeficienteMovilidad > 0)
                      _buildMiniBadge(Icons.directions_bike_rounded, 'Movilidad', OhtliColors.cempasuchil),
                    if (poi.wheelchairAccessible)
                      _buildMiniBadge(Icons.accessible_rounded, 'Accesible', Colors.blue),
                    const Spacer(),
                    if (poi.location.isValid)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: InkWell(
                          onTap: () => _openInMaps(poi.location.lat, poi.location.lng, poi.name),
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            padding: const EdgeInsets.all(7),
                            decoration: BoxDecoration(
                              color: OhtliColors.innerCardBg,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: OhtliColors.cardBorder),
                            ),
                            child: const Icon(Icons.map_rounded, size: 14, color: OhtliColors.stormyTeal),
                          ),
                        ),
                      ),
                    // Action button to view details
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: _isHovered ? OhtliColors.stormyTeal : OhtliColors.innerCardBg,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Detalles',
                            style: GoogleFonts.outfit(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: _isHovered ? Colors.white : OhtliColors.stormyTeal,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            Icons.arrow_forward_rounded,
                            size: 14,
                            color: _isHovered ? Colors.white : OhtliColors.stormyTeal,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMiniBadge(IconData icon, String tooltip, Color color) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Tooltip(
        message: tooltip,
        child: Container(
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 13, color: color),
        ),
      ),
    );
  }
}

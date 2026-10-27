// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/colors.dart';
import '../models/poi_model.dart';
import 'poi_detail_dialog.dart';

class PoiCard extends StatefulWidget {
  final Poi poi;
  final VoidCallback? onTap;
  final double? width;
  final double? height;
  final bool isDoubleWidth;

  const PoiCard({
    super.key,
    required this.poi,
    this.onTap,
    this.width,
    this.height,
    this.isDoubleWidth = false,
  });

  @override
  State<PoiCard> createState() => _PoiCardState();
}

class _PoiCardState extends State<PoiCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final poi = widget.poi;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: OhtliColors.cardBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _isHovered ? poi.categoryColor.withValues(alpha: 0.5) : OhtliColors.cardBorder,
            width: _isHovered ? 1.5 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: _isHovered
                  ? poi.categoryColor.withValues(alpha: 0.16)
                  : Colors.black.withValues(alpha: 0.08),
              blurRadius: _isHovered ? 20 : 12,
              offset: Offset(0, _isHovered ? 8 : 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            onTap: widget.onTap ?? () => PoiDetailDialog.show(context, poi),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // 1. Top half: 16:9 Photography of the place
                AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.network(
                        poi.imageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            color: OhtliColors.innerCardBg,
                            child: Center(
                              child: Icon(
                                poi.categoryIcon,
                                size: 36,
                                color: poi.categoryColor.withValues(alpha: 0.5),
                              ),
                            ),
                          );
                        },
                        loadingBuilder: (context, child, loadingProgress) {
                          if (loadingProgress == null) return child;
                          return Container(
                            color: OhtliColors.innerCardBg,
                            child: const Center(
                              child: SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: OhtliColors.stormyTeal,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                      // Subtle gradient overlay for polish
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        height: 40,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.transparent,
                                Colors.black.withValues(alpha: 0.35),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // 2. Card Content Body
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Title of the place (prominent, bold, legible)
                      Text(
                        poi.name,
                        maxLines: widget.isDoubleWidth ? 1 : 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.outfit(
                          fontSize: widget.isDoubleWidth ? 20 : 17,
                          fontWeight: FontWeight.w700,
                          color: OhtliColors.onyx,
                          height: 1.25,
                        ),
                      ),
                      const SizedBox(height: 8),

                      // Compact metadata badge: [🏛️ Museo • $$]
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                        decoration: BoxDecoration(
                          color: OhtliColors.innerCardBg,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: OhtliColors.cardBorder),
                        ),
                        child: Text(
                          poi.compactMetadata,
                          style: GoogleFonts.inter(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: poi.categoryColor,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),

                      // Location: Colonia y Alcaldía
                      Row(
                        children: [
                          const Icon(
                            Icons.location_on_rounded,
                            size: 14,
                            color: OhtliColors.stormyTeal,
                          ),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              poi.coloniaAlcaldiaDisplay,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: OhtliColors.subtleText,
                              ),
                            ),
                          ),
                        ],
                      ),

                      // Opening hours (if available)
                      const SizedBox(height: 5),
                      Row(
                        children: [
                          Icon(
                            Icons.access_time_rounded,
                            size: 13,
                            color: OhtliColors.subtleText.withValues(alpha: 0.8),
                          ),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              poi.openingHoursDisplay,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(
                                fontSize: 11.5,
                                color: OhtliColors.subtleText,
                              ),
                            ),
                          ),
                        ],
                      ),

                      // Hashtags at bottom
                      if (poi.vibeTags.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: poi.vibeTags.take(widget.isDoubleWidth ? 5 : 3).map((tag) {
                            final cleanTag = tag.startsWith('#') ? tag : '#$tag';
                            return Text(
                              cleanTag,
                              style: GoogleFonts.inter(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                                color: OhtliColors.subtleText.withValues(alpha: 0.75),
                              ),
                            );
                          }).toList(),
                        ),
                      ],

                      const SizedBox(height: 14),

                      // Solid Action CTA Button with wide click area & accent color
                      SizedBox(
                        width: double.infinity,
                        height: 40,
                        child: ElevatedButton(
                          onPressed: widget.onTap ?? () => PoiDetailDialog.show(context, poi),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: OhtliColors.cempasuchil,
                            foregroundColor: const Color(0xFF1A120B),
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                'Ver detalles',
                                style: GoogleFonts.outfit(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.2,
                                ),
                              ),
                              const SizedBox(width: 6),
                              const Icon(Icons.arrow_forward_rounded, size: 15),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

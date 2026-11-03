// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/colors.dart';
import '../models/poi_model.dart';
import 'poi_detail_dialog.dart';

class PoiCard extends StatefulWidget {
  final Poi poi;
  final VoidCallback? onTap;
  final VoidCallback? onCreateRoute;
  final VoidCallback? onToggleSave;
  final bool isSaved;
  final double? width;
  final double? height;
  final bool isDoubleWidth;

  const PoiCard({
    super.key,
    required this.poi,
    this.onTap,
    this.onCreateRoute,
    this.onToggleSave,
    this.isSaved = false,
    this.width,
    this.height,
    this.isDoubleWidth = false,
  });

  @override
  State<PoiCard> createState() => _PoiCardState();
}

class _PoiCardState extends State<PoiCard> with SingleTickerProviderStateMixin {
  bool _isHovered = false;
  late AnimationController _hoverExpandController;
  Timer? _openDetailsTimer;

  @override
  void initState() {
    super.initState();
    // Animación de expansión suave durante 5 segundos continuos de hover
    _hoverExpandController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    );

    _hoverExpandController.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted && _isHovered) {
        _openDetails();
        _resetHoverState();
      }
    });
  }

  @override
  void dispose() {
    _openDetailsTimer?.cancel();
    _hoverExpandController.dispose();
    super.dispose();
  }

  void _onHoverEnter() {
    if (!mounted) return;
    setState(() => _isHovered = true);
    _hoverExpandController.forward(from: 0.0);
  }

  void _onHoverExit() {
    if (!mounted) return;
    _openDetailsTimer?.cancel();
    _hoverExpandController.animateBack(0.0, duration: const Duration(milliseconds: 250));
    setState(() => _isHovered = false);
  }

  void _resetHoverState() {
    _openDetailsTimer?.cancel();
    _hoverExpandController.reset();
    if (mounted) {
      setState(() => _isHovered = false);
    }
  }

  void _openDetails() {
    if (widget.onTap != null) {
      widget.onTap!();
    } else {
      PoiDetailDialog.show(
        context,
        widget.poi,
        isSaved: widget.isSaved,
        onCreateRoute: widget.onCreateRoute,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final poi = widget.poi;
    final cardHeight = widget.height ?? (widget.isDoubleWidth ? 520.0 : 420.0);

    return MouseRegion(
      onEnter: (_) => _onHoverEnter(),
      onExit: (_) => _onHoverExit(),
      child: AnimatedBuilder(
        animation: _hoverExpandController,
        builder: (context, child) {
          final expandProgress = _hoverExpandController.value;
          // Expansión progresiva durante los 5 segundos (de 1.0 a 1.05)
          final scale = 1.0 + (expandProgress * 0.05);

          return Transform.scale(
            scale: scale,
            alignment: Alignment.center,
            child: Container(
              width: widget.width,
              height: cardHeight,
              decoration: BoxDecoration(
                color: OhtliColors.cardBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _isHovered
                      ? Color.lerp(
                          poi.categoryColor.withValues(alpha: 0.5),
                          OhtliColors.cempasuchil,
                          expandProgress,
                        )!
                      : OhtliColors.cardBorder,
                  width: _isHovered ? (1.5 + (expandProgress * 1.0)) : 1.0,
                ),
                boxShadow: [
                  BoxShadow(
                    color: _isHovered
                        ? poi.categoryColor.withValues(alpha: 0.14 + (expandProgress * 0.16))
                        : Colors.black.withValues(alpha: 0.08),
                    blurRadius: _isHovered ? (18.0 + (expandProgress * 14.0)) : 12.0,
                    offset: Offset(0, _isHovered ? (6.0 + (expandProgress * 4.0)) : 4.0),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  onTap: () {
                    _resetHoverState();
                    _openDetails();
                  },
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
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
                            // Subtle gradient overlay for contrast
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
                            // Bookmark toggle button on image
                            if (widget.onToggleSave != null)
                              Positioned(
                                top: 8,
                                right: 8,
                                child: InkWell(
                                  onTap: widget.onToggleSave,
                                  borderRadius: BorderRadius.circular(8),
                                  child: Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withValues(alpha: 0.55),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Icon(
                                      widget.isSaved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
                                      color: widget.isSaved ? OhtliColors.cempasuchil : Colors.white,
                                      size: 16,
                                    ),
                                  ),
                                ),
                              ),

                            // Barra de progreso sutil si el usuario mantiene el hover (hacia los 5 segundos)
                            if (_isHovered && expandProgress > 0.0)
                              Positioned(
                                top: 0,
                                left: 0,
                                right: 0,
                                height: 3.5,
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: FractionallySizedBox(
                                    widthFactor: expandProgress.clamp(0.0, 1.0),
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: OhtliColors.cempasuchil,
                                        boxShadow: [
                                          BoxShadow(
                                            color: OhtliColors.cempasuchil.withValues(alpha: 0.6),
                                            blurRadius: 4,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),

                      // 2. Card Content Body (Expanded para anclar el botón siempre abajo a la misma altura)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
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
                              const SizedBox(height: 8),

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
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 4,
                                  children: poi.vibeTags.take(widget.isDoubleWidth ? 5 : 3).map((tag) {
                                    final cleanTag = tag.startsWith('#') ? tag : '#$tag';
                                    return Text(
                                      cleanTag,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.inter(
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w600,
                                        color: OhtliColors.subtleText.withValues(alpha: 0.75),
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ],

                              // ESPACIADOR CLAVE: Empuja el botón al final para que siempre esté a la misma altura
                              const Spacer(),

                              // CTA Button: "Crear ruta desde aquí"
                              SizedBox(
                                width: double.infinity,
                                height: 40,
                                child: ElevatedButton.icon(
                                  onPressed: widget.onCreateRoute ??
                                      () {
                                        _resetHoverState();
                                        PoiDetailDialog.show(
                                          context,
                                          poi,
                                          isSaved: widget.isSaved,
                                        );
                                      },
                                  icon: const Icon(Icons.alt_route_rounded, size: 16),
                                  label: Text(
                                    widget.isDoubleWidth
                                        ? 'Crea una ruta desde este punto'
                                        : 'Crear ruta desde aquí',
                                    style: GoogleFonts.outfit(
                                      fontSize: widget.isDoubleWidth ? 13.5 : 12.5,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: OhtliColors.cempasuchil,
                                    foregroundColor: const Color(0xFF1A120B),
                                    elevation: 0,
                                    padding: const EdgeInsets.symmetric(horizontal: 14),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

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

  /// Porcentaje de afinidad con el perfil del usuario (se muestra como insignia si no es nulo).
  final int? affinity;

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
    this.affinity,
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

  Widget _glassChip({required Widget child, EdgeInsets padding = const EdgeInsets.symmetric(horizontal: 9, vertical: 5)}) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.48),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
      ),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final poi = widget.poi;
    final cardHeight = widget.height ?? (widget.isDoubleWidth ? 520.0 : 420.0);
    final accent = poi.categoryColor;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => _onHoverEnter(),
      onExit: (_) => _onHoverExit(),
      child: AnimatedBuilder(
        animation: _hoverExpandController,
        builder: (context, child) {
          final expandProgress = _hoverExpandController.value;
          // Elevación inmediata al enfocar + expansión progresiva durante los 5 segundos
          final lift = _isHovered ? 1.0 : 0.0;
          final scale = 1.0 + (lift * 0.01) + (expandProgress * 0.03);

          return Transform.translate(
            offset: Offset(0, -4 * lift),
            child: Transform.scale(
              scale: scale,
              alignment: Alignment.center,
              child: Container(
                width: widget.width,
                height: cardHeight,
                decoration: BoxDecoration(
                  color: OhtliColors.cardBg,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: _isHovered
                        ? Color.lerp(accent.withValues(alpha: 0.45), OhtliColors.cempasuchil, expandProgress)!
                        : OhtliColors.cardBorder,
                    width: _isHovered ? (1.4 + (expandProgress * 1.0)) : 1.0,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: _isHovered
                          ? accent.withValues(alpha: 0.16 + (expandProgress * 0.14))
                          : Colors.black.withValues(alpha: 0.06),
                      blurRadius: _isHovered ? (26.0 + (expandProgress * 12.0)) : 14.0,
                      offset: Offset(0, _isHovered ? 14.0 : 5.0),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () {
                        _resetHoverState();
                        _openDetails();
                      },
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 1. Fotografía del lugar (ocupa el espacio sobrante para que todas las tarjetas se alineen)
                          Expanded(
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                Container(color: OhtliColors.innerCardBg),
                                AnimatedScale(
                                  scale: _isHovered ? 1.06 : 1.0,
                                  duration: const Duration(milliseconds: 600),
                                  curve: Curves.easeOutCubic,
                                  child: Image.network(
                                    poi.imageUrl,
                                    fit: BoxFit.cover,
                                    gaplessPlayback: true,
                                    frameBuilder: (context, child, frame, wasSync) {
                                      if (wasSync) return child;
                                      return AnimatedOpacity(
                                        opacity: frame == null ? 0 : 1,
                                        duration: const Duration(milliseconds: 380),
                                        curve: Curves.easeOut,
                                        child: child,
                                      );
                                    },
                                    errorBuilder: (context, error, stackTrace) {
                                      return Container(
                                        color: accent.withValues(alpha: 0.08),
                                        child: Center(
                                          child: Icon(poi.categoryIcon, size: 40, color: accent.withValues(alpha: 0.5)),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                                // Degradados de contraste arriba y abajo
                                DecoratedBox(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      colors: [
                                        Colors.black.withValues(alpha: 0.38),
                                        Colors.transparent,
                                        Colors.transparent,
                                        Colors.black.withValues(alpha: 0.42),
                                      ],
                                      stops: const [0.0, 0.32, 0.62, 1.0],
                                    ),
                                  ),
                                ),
                                // Categoría (arriba-izquierda)
                                Positioned(
                                  top: 10,
                                  left: 10,
                                  right: 52,
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: _glassChip(
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(poi.categoryIcon, size: 13, color: Colors.white),
                                          const SizedBox(width: 5),
                                          Flexible(
                                            child: Text(
                                              poi.categoryDisplay,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: GoogleFonts.inter(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w700,
                                                color: Colors.white,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                // Guardar (arriba-derecha)
                                if (widget.onToggleSave != null)
                                  Positioned(
                                    top: 8,
                                    right: 8,
                                    child: Tooltip(
                                      message: widget.isSaved ? 'Quitar de Mis lugares' : 'Guardar en Mis lugares',
                                      child: Material(
                                        color: Colors.transparent,
                                        child: InkWell(
                                          onTap: widget.onToggleSave,
                                          customBorder: const CircleBorder(),
                                          child: AnimatedContainer(
                                            duration: const Duration(milliseconds: 200),
                                            width: 36,
                                            height: 36,
                                            decoration: BoxDecoration(
                                              color: widget.isSaved
                                                  ? OhtliColors.cempasuchil
                                                  : Colors.black.withValues(alpha: 0.48),
                                              shape: BoxShape.circle,
                                              border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                                            ),
                                            child: AnimatedSwitcher(
                                              duration: const Duration(milliseconds: 220),
                                              transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
                                              child: Icon(
                                                widget.isSaved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
                                                key: ValueKey(widget.isSaved),
                                                color: Colors.white,
                                                size: 18,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                // Afinidad + precio (abajo)
                                Positioned(
                                  left: 10,
                                  right: 10,
                                  bottom: 10,
                                  child: Row(
                                    children: [
                                      if (widget.affinity != null)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                                          decoration: BoxDecoration(
                                            color: OhtliColors.stormyTeal,
                                            borderRadius: BorderRadius.circular(20),
                                            boxShadow: [
                                              BoxShadow(
                                                color: Colors.black.withValues(alpha: 0.25),
                                                blurRadius: 8,
                                                offset: const Offset(0, 2),
                                              ),
                                            ],
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const Icon(Icons.auto_awesome_rounded, size: 12, color: Colors.white),
                                              const SizedBox(width: 4),
                                              Text(
                                                '${widget.affinity}% afín a ti',
                                                style: GoogleFonts.inter(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w800,
                                                  color: Colors.white,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      const Spacer(),
                                      _glassChip(
                                        child: Text(
                                          poi.priceSymbols,
                                          style: GoogleFonts.inter(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w800,
                                            color: Colors.white,
                                            letterSpacing: 0.5,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                // Barra de progreso sutil si el usuario mantiene el hover (hacia los 5 segundos)
                                if (_isHovered && expandProgress > 0.0)
                                  Positioned(
                                    top: 0,
                                    left: 0,
                                    right: 0,
                                    height: 3,
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

                          // 2. Contenido
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  poi.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.outfit(
                                    fontSize: widget.isDoubleWidth ? 21 : 17.5,
                                    fontWeight: FontWeight.w700,
                                    color: OhtliColors.onyx,
                                    height: 1.2,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                _infoRow(Icons.location_on_rounded, poi.coloniaAlcaldiaDisplay, OhtliColors.stormyTeal),
                                const SizedBox(height: 4),
                                _infoRow(Icons.access_time_rounded, poi.openingHoursDisplay,
                                    OhtliColors.subtleText.withValues(alpha: 0.8)),
                                const SizedBox(height: 10),
                                SizedBox(
                                  height: 22,
                                  child: poi.vibeTags.isEmpty
                                      ? const SizedBox.shrink()
                                      : ListView(
                                          scrollDirection: Axis.horizontal,
                                          physics: const NeverScrollableScrollPhysics(),
                                          children: poi.vibeTags.take(widget.isDoubleWidth ? 5 : 3).map((tag) {
                                            final cleanTag = tag.startsWith('#') ? tag.substring(1) : tag;
                                            return Container(
                                              margin: const EdgeInsets.only(right: 6),
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                              decoration: BoxDecoration(
                                                color: accent.withValues(alpha: 0.08),
                                                borderRadius: BorderRadius.circular(20),
                                              ),
                                              child: Text(
                                                cleanTag,
                                                maxLines: 1,
                                                style: GoogleFonts.inter(
                                                  fontSize: 10.5,
                                                  fontWeight: FontWeight.w600,
                                                  color: OhtliColors.onyx.withValues(alpha: 0.7),
                                                ),
                                              ),
                                            );
                                          }).toList(),
                                        ),
                                ),
                                const SizedBox(height: 14),
                                SizedBox(
                                  width: double.infinity,
                                  height: 42,
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
                                    icon: const Icon(Icons.alt_route_rounded, size: 17),
                                    label: Text(
                                      widget.isDoubleWidth ? 'Crea una ruta desde este punto' : 'Crear ruta desde aquí',
                                      style: GoogleFonts.outfit(
                                        fontSize: widget.isDoubleWidth ? 14 : 13,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: OhtliColors.cempasuchil,
                                      foregroundColor: const Color(0xFF1A120B),
                                      elevation: 0,
                                      padding: const EdgeInsets.symmetric(horizontal: 14),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _infoRow(IconData icon, String text, Color iconColor) {
    return Row(
      children: [
        Icon(icon, size: 14, color: iconColor),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
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
    );
  }
}

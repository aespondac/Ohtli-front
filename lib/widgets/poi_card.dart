// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/colors.dart';
import '../models/poi_model.dart';
import 'poi_detail_dialog.dart';

/// Estilos visuales de la tarjeta de lugar.
/// - [immersive]: foto a sangre completa con la información encima (sección "Para ti").
/// - [standard]: foto redondeada con la información debajo, estilo galería editorial.
/// - [compact]: fila horizontal con miniatura (historial "Revisita").
enum PoiCardVariant { immersive, standard, compact }

class PoiCard extends StatefulWidget {
  final Poi poi;
  final VoidCallback? onTap;
  final VoidCallback? onCreateRoute;
  final VoidCallback? onToggleSave;
  final bool isSaved;
  final double? width;
  final double? height;
  final bool isDoubleWidth;
  final PoiCardVariant? variant;

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
    this.variant,
  });

  PoiCardVariant get resolvedVariant => variant ?? (isDoubleWidth ? PoiCardVariant.immersive : PoiCardVariant.standard);

  @override
  State<PoiCard> createState() => _PoiCardState();
}

class _PoiCardState extends State<PoiCard> {
  bool _isHovered = false;

  /// Sin colonia conocida se muestra el horario en vez de repetir "Ciudad de México" en cada tarjeta.
  bool get _hasArea => widget.poi.coloniaAlcaldiaDisplay != 'Ciudad de México';
  String get _subtitleText => _hasArea ? widget.poi.coloniaAlcaldiaDisplay : widget.poi.openingHoursDisplay;
  IconData _subtitleIcon({bool outlined = false}) => _hasArea
      ? (outlined ? Icons.location_on_outlined : Icons.location_on_rounded)
      : Icons.schedule_rounded;

  void _setHover(bool v) {
    if (!mounted || _isHovered == v) return;
    setState(() => _isHovered = v);
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

  void _createRoute() {
    if (widget.onCreateRoute != null) {
      widget.onCreateRoute!();
    } else {
      _openDetails();
    }
  }

  @override
  Widget build(BuildContext context) {
    switch (widget.resolvedVariant) {
      case PoiCardVariant.immersive:
        return _buildImmersive();
      case PoiCardVariant.standard:
        return _buildStandard();
      case PoiCardVariant.compact:
        return _buildCompact();
    }
  }

  // ───────────────────────── Piezas compartidas ─────────────────────────

  Widget _hoverWrapper({required Widget child, double lift = 6}) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => _setHover(true),
      onExit: (_) => _setHover(false),
      child: AnimatedSlide(
        offset: Offset(0, _isHovered ? -lift / 400 : 0),
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _openDetails,
          child: child,
        ),
      ),
    );
  }

  Widget _photo({double zoom = 1.06}) {
    final poi = widget.poi;
    final accent = poi.categoryColor;
    return Stack(
      fit: StackFit.expand,
      children: [
        // Fondo de respaldo con el color de la categoría
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [accent.withValues(alpha: 0.85), Color.lerp(accent, Colors.black, 0.45)!],
            ),
          ),
          child: Center(child: Icon(poi.categoryIcon, size: 42, color: Colors.white.withValues(alpha: 0.55))),
        ),
        AnimatedScale(
          scale: _isHovered ? zoom : 1.0,
          duration: const Duration(milliseconds: 700),
          curve: Curves.easeOutCubic,
          child: Image.network(
            poi.imageUrl,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            frameBuilder: (context, child, frame, wasSync) {
              if (wasSync) return child;
              return AnimatedOpacity(
                opacity: frame == null ? 0 : 1,
                duration: const Duration(milliseconds: 420),
                curve: Curves.easeOut,
                child: child,
              );
            },
            errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
          ),
        ),
      ],
    );
  }

  Widget _glass({required Widget child, EdgeInsets padding = const EdgeInsets.symmetric(horizontal: 10, vertical: 6), double radius = 30}) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.38),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18), width: 0.8),
      ),
      child: child,
    );
  }

  Widget _categoryChip({bool onImage = true}) {
    final poi = widget.poi;
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(poi.categoryIcon, size: 13, color: onImage ? Colors.white : poi.categoryColor),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            poi.categoryDisplay,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: onImage ? Colors.white : poi.categoryColor,
              letterSpacing: 0.1,
            ),
          ),
        ),
      ],
    );
    return _glass(child: content);
  }

  Widget _saveButton({double size = 38}) {
    if (widget.onToggleSave == null) return const SizedBox.shrink();
    final saved = widget.isSaved;
    return Tooltip(
      message: saved ? 'Quitar de Mis lugares' : 'Guardar en Mis lugares',
      child: GestureDetector(
        onTap: widget.onToggleSave,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: saved ? OhtliColors.cempasuchil : Colors.black.withValues(alpha: 0.38),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withValues(alpha: saved ? 0.0 : 0.22), width: 0.8),
              boxShadow: saved
                  ? [BoxShadow(color: OhtliColors.cempasuchil.withValues(alpha: 0.45), blurRadius: 14, offset: const Offset(0, 4))]
                  : null,
            ),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 240),
              transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
              child: Icon(
                saved ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                key: ValueKey(saved),
                color: Colors.white,
                size: size * 0.47,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _affinityBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF2C666E), Color(0xFF3E8A8F)],
        ),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.white.withValues(alpha: 0.25), width: 0.8),
        boxShadow: [
          BoxShadow(color: OhtliColors.stormyTeal.withValues(alpha: 0.45), blurRadius: 14, offset: const Offset(0, 4)),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.auto_awesome_rounded, size: 12, color: Colors.white),
          const SizedBox(width: 5),
          Text(
            '${widget.affinity}% afín',
            style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.white),
          ),
        ],
      ),
    );
  }

  // ───────────────────────── Variante inmersiva ─────────────────────────

  Widget _buildImmersive() {
    final poi = widget.poi;
    final h = widget.height ?? 520.0;
    final tags = poi.vibeTags.take(3).map((t) => t.startsWith('#') ? t.substring(1) : t).toList();

    return _hoverWrapper(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
        width: widget.width,
        height: h,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: (_isHovered ? poi.categoryColor : Colors.black).withValues(alpha: _isHovered ? 0.32 : 0.14),
              blurRadius: _isHovered ? 36 : 22,
              spreadRadius: -4,
              offset: Offset(0, _isHovered ? 20 : 12),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: Stack(
            fit: StackFit.expand,
            children: [
              _photo(zoom: 1.05),
              // Velo superior + degradado inferior profundo para el texto
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.30),
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.35),
                      Colors.black.withValues(alpha: 0.88),
                    ],
                    stops: const [0.0, 0.28, 0.55, 1.0],
                  ),
                ),
              ),
              Positioned(
                top: 16,
                left: 16,
                right: 70,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _categoryChip(),
                    if (widget.affinity != null) _affinityBadge(),
                  ],
                ),
              ),
              Positioned(top: 14, right: 14, child: _saveButton(size: 42)),
              Positioned(
                left: 22,
                right: 22,
                bottom: 22,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      poi.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.outfit(
                        fontSize: 30,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        height: 1.05,
                        letterSpacing: -0.6,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Icon(_subtitleIcon(), size: 15, color: Colors.white.withValues(alpha: 0.85)),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            _subtitleText,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w500, color: Colors.white.withValues(alpha: 0.88)),
                          ),
                        ),
                        _dot(),
                        Text(
                          poi.priceSymbols,
                          style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w700, color: Colors.white),
                        ),
                      ],
                    ),
                    if (tags.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: tags
                            .map((t) => _glass(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                  child: Text(
                                    t,
                                    style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w600, color: Colors.white),
                                  ),
                                ))
                            .toList(),
                      ),
                    ],
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(child: _primaryRouteButton(label: 'Crear ruta desde aquí')),
                        const SizedBox(width: 10),
                        _circleArrowButton(),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dot() => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Container(width: 3, height: 3, decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.7), shape: BoxShape.circle)),
      );

  Widget _primaryRouteButton({required String label}) {
    return SizedBox(
      height: 48,
      child: ElevatedButton.icon(
        onPressed: _createRoute,
        icon: const Icon(Icons.alt_route_rounded, size: 18),
        label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        style: ElevatedButton.styleFrom(
          backgroundColor: OhtliColors.cempasuchil,
          foregroundColor: const Color(0xFF1A120B),
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          shape: const StadiumBorder(),
          textStyle: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }

  Widget _circleArrowButton() {
    return Tooltip(
      message: 'Ver detalles',
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 260),
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: _isHovered ? Colors.white : Colors.white.withValues(alpha: 0.16),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withValues(alpha: 0.3), width: 0.8),
        ),
        child: AnimatedRotation(
          turns: _isHovered ? 0 : -0.125,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutBack,
          child: Icon(Icons.arrow_forward_rounded, size: 20, color: _isHovered ? OhtliColors.stormyTeal : Colors.white),
        ),
      ),
    );
  }

  // ───────────────────────── Variante estándar ─────────────────────────

  Widget _buildStandard() {
    final poi = widget.poi;
    final h = widget.height ?? 380.0;
    final tags = poi.vibeTags.take(2).map((t) => t.startsWith('#') ? t.substring(1) : t).toList();

    return _hoverWrapper(
      lift: 4,
      child: SizedBox(
        width: widget.width,
        height: h,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOutCubic,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: _isHovered ? 0.22 : 0.08),
                      blurRadius: _isHovered ? 28 : 14,
                      spreadRadius: -4,
                      offset: Offset(0, _isHovered ? 16 : 8),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _photo(),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.black.withValues(alpha: 0.28),
                              Colors.transparent,
                              Colors.transparent,
                              Colors.black.withValues(alpha: 0.30),
                            ],
                            stops: const [0.0, 0.3, 0.7, 1.0],
                          ),
                        ),
                      ),
                      Positioned(
                        top: 12,
                        left: 12,
                        right: 60,
                        child: Align(alignment: Alignment.centerLeft, child: _categoryChip()),
                      ),
                      Positioned(top: 10, right: 10, child: _saveButton()),
                      if (widget.affinity != null)
                        Positioned(left: 12, bottom: 12, child: _affinityBadge()),
                      // Botón de ruta: círculo que se expande a píldora al pasar el cursor
                      Positioned(
                        right: 12,
                        bottom: 12,
                        child: Tooltip(
                          message: 'Crear ruta desde aquí',
                          child: GestureDetector(
                            onTap: _createRoute,
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 280),
                              curve: Curves.easeOutCubic,
                              height: 40,
                              padding: EdgeInsets.symmetric(horizontal: _isHovered ? 14 : 0),
                              constraints: const BoxConstraints(minWidth: 40),
                              decoration: BoxDecoration(
                                color: OhtliColors.cempasuchil,
                                borderRadius: BorderRadius.circular(30),
                                boxShadow: [
                                  BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 12, offset: const Offset(0, 4)),
                                ],
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.alt_route_rounded, size: 18, color: Color(0xFF1A120B)),
                                  AnimatedSize(
                                    duration: const Duration(milliseconds: 280),
                                    curve: Curves.easeOutCubic,
                                    child: _isHovered
                                        ? Padding(
                                            padding: const EdgeInsets.only(left: 6),
                                            child: Text(
                                              'Crear ruta',
                                              style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w800, color: const Color(0xFF1A120B)),
                                            ),
                                          )
                                        : const SizedBox.shrink(),
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
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 14, 4, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          poi.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.outfit(
                            fontSize: 17.5,
                            fontWeight: FontWeight.w700,
                            color: OhtliColors.onyx,
                            height: 1.2,
                            letterSpacing: -0.2,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        poi.priceSymbols,
                        style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: OhtliColors.stormyTeal),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      Icon(_subtitleIcon(outlined: true), size: 14, color: OhtliColors.subtleText),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          _subtitleText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w500, color: OhtliColors.subtleText),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 24,
                    child: Row(
                      children: tags
                          .map((t) => Flexible(
                                child: Container(
                                  margin: const EdgeInsets.only(right: 6),
                                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: OhtliColors.cardBg,
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(color: OhtliColors.cardBorder),
                                  ),
                                  child: Text(
                                    t,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: OhtliColors.onyx.withValues(alpha: 0.72)),
                                  ),
                                ),
                              ))
                          .toList(),
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

  // ───────────────────────── Variante compacta ─────────────────────────

  Widget _buildCompact() {
    final poi = widget.poi;
    return _hoverWrapper(
      lift: 3,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 240),
        width: widget.width ?? 320,
        height: widget.height ?? 96,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: OhtliColors.cardBg,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: _isHovered ? poi.categoryColor.withValues(alpha: 0.45) : OhtliColors.cardBorder),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: _isHovered ? 0.12 : 0.04),
              blurRadius: _isHovered ? 20 : 10,
              offset: Offset(0, _isHovered ? 10 : 4),
            ),
          ],
        ),
        child: Row(
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: ClipRRect(borderRadius: BorderRadius.circular(16), child: _photo(zoom: 1.1)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    poi.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.outfit(fontSize: 15.5, fontWeight: FontWeight.w700, color: OhtliColors.onyx),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(poi.categoryIcon, size: 13, color: poi.categoryColor),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          '${poi.categoryDisplay} · ${poi.priceSymbols}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: OhtliColors.subtleText),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    _subtitleText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(fontSize: 11.5, color: OhtliColors.subtleText.withValues(alpha: 0.8)),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            AnimatedContainer(
              duration: const Duration(milliseconds: 240),
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: _isHovered ? OhtliColors.stormyTeal : OhtliColors.innerCardBg,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.arrow_forward_rounded, size: 16, color: _isHovered ? Colors.white : OhtliColors.onyx),
            ),
          ],
        ),
      ),
    );
  }
}

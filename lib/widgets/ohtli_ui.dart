import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/colors.dart';
import 'ohtli_service_icon.dart';

/// Kit visual común de Ohtli, tomado de la landing, Lugares y el visor de viajes.
/// Úsalo en las secciones de la app para que todas compartan la misma línea visual:
/// encabezados con etiqueta + título + subtítulo, superficies neutras redondeadas,
/// botones tipo píldora, chips y estados vacíos.
class OhtliUi {
  OhtliUi._();

  static const double radiusCard = 24;
  static const double radiusLarge = 28;

  /// Margen horizontal de página según el ancho (igual que la landing).
  static double pagePadding(double width) => width < 700 ? 20 : (width < 1100 ? 40 : (width * 0.045).clamp(56.0, 120.0));

  static TextStyle eyebrow(Color color) =>
      GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 1.5, color: color);

  static TextStyle title({double size = 30}) =>
      GoogleFonts.outfit(fontSize: size, fontWeight: FontWeight.w800, color: OhtliColors.onyx, letterSpacing: -0.6, height: 1.1);

  static TextStyle body({double size = 14.5}) => GoogleFonts.inter(fontSize: size, color: OhtliColors.subtleText, height: 1.55);

  static List<BoxShadow> softShadow({Color? color, bool raised = false}) => [
        BoxShadow(
          color: (color ?? Colors.black).withValues(alpha: raised ? 0.16 : 0.05),
          blurRadius: raised ? 30 : 14,
          spreadRadius: -4,
          offset: Offset(0, raised ? 16 : 6),
        ),
      ];
}

/// Encabezado de sección: etiqueta con ícono, título, subtítulo y acción opcional.
class OhtliSectionHeader extends StatelessWidget {
  final String eyebrow;
  final String title;
  final String? subtitle;
  final IconData? icon;
  final Color? color;
  final Widget? trailing;
  final bool large;

  const OhtliSectionHeader({
    super.key,
    required this.eyebrow,
    required this.title,
    this.subtitle,
    this.icon,
    this.color,
    this.trailing,
    this.large = false,
  });

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 760;
    final c = color ?? OhtliColors.accentText;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[Icon(icon, size: 14, color: c), const SizedBox(width: 6)],
                  Text(eyebrow.toUpperCase(), style: OhtliUi.eyebrow(c)),
                ],
              ),
              const SizedBox(height: 8),
              Text(title, style: OhtliUi.title(size: large ? (isMobile ? 30 : 42) : (isMobile ? 24 : 30))),
              if (subtitle != null) ...[
                const SizedBox(height: 6),
                Text(subtitle!, style: OhtliUi.body(size: large ? 15.5 : 14)),
              ],
            ],
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 16), trailing!],
      ],
    );
  }
}

/// Superficie neutra (tarjeta) con borde suave; opcionalmente tocable con elevación al pasar el cursor.
class OhtliSurface extends StatefulWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final double radius;
  final Color? accent;
  final bool selected;

  const OhtliSurface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(22),
    this.onTap,
    this.radius = OhtliUi.radiusCard,
    this.accent,
    this.selected = false,
  });

  @override
  State<OhtliSurface> createState() => _OhtliSurfaceState();
}

class _OhtliSurfaceState extends State<OhtliSurface> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final accent = widget.accent ?? OhtliColors.stormyTeal;
    final interactive = widget.onTap != null;
    final active = widget.selected || (interactive && _hover);
    final box = AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      padding: widget.padding,
      transform: Matrix4.translationValues(0, interactive && _hover ? -3 : 0, 0),
      decoration: BoxDecoration(
        color: OhtliColors.cardBg,
        borderRadius: BorderRadius.circular(widget.radius),
        border: Border.all(
          color: widget.selected ? accent : (active ? accent.withValues(alpha: 0.45) : OhtliColors.cardBorder),
          width: widget.selected ? 1.6 : 1,
        ),
        boxShadow: OhtliUi.softShadow(color: active ? accent : null, raised: active),
      ),
      child: widget.child,
    );
    if (!interactive) return box;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(onTap: widget.onTap, behavior: HitTestBehavior.opaque, child: box),
    );
  }
}

/// Botón principal tipo píldora (cempasúchil para acciones clave, turquesa para el resto).
class OhtliPrimaryButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool highlight;
  final bool expand;
  final bool loading;

  const OhtliPrimaryButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.highlight = false,
    this.expand = false,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    final bg = highlight ? OhtliColors.cempasuchil : OhtliColors.stormyTeal;
    final fg = highlight ? const Color(0xFF1A120B) : Colors.white;
    final child = ElevatedButton(
      onPressed: loading ? null : onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: bg,
        foregroundColor: fg,
        disabledBackgroundColor: bg.withValues(alpha: 0.5),
        disabledForegroundColor: fg.withValues(alpha: 0.8),
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 17),
        shape: const StadiumBorder(),
        textStyle: GoogleFonts.outfit(fontWeight: FontWeight.w800, fontSize: 15.5),
      ),
      child: Row(
        mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (loading)
            SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.2, color: fg))
          else if (icon != null)
            Icon(icon, size: 18),
          if (loading || icon != null) const SizedBox(width: 8),
          Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
    return expand ? SizedBox(width: double.infinity, child: child) : child;
  }
}

/// Botón secundario tipo píldora con contorno.
class OhtliSecondaryButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;

  const OhtliSecondaryButton({super.key, required this.label, this.icon, this.onPressed});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: OhtliColors.onyx,
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 17),
        side: BorderSide(color: OhtliColors.onyx.withValues(alpha: 0.18)),
        shape: const StadiumBorder(),
        textStyle: GoogleFonts.outfit(fontWeight: FontWeight.w700, fontSize: 15),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 18), const SizedBox(width: 8)],
          Text(label),
        ],
      ),
    );
  }
}

/// Chip seleccionable tipo píldora (igual que los filtros de Lugares).
class OhtliChoiceChip extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool selected;
  final VoidCallback onTap;

  const OhtliChoiceChip({super.key, required this.label, required this.selected, required this.onTap, this.icon});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          decoration: BoxDecoration(
            color: selected ? OhtliColors.stormyTeal : OhtliColors.cardBg,
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: selected ? OhtliColors.stormyTeal : OhtliColors.cardBorder),
            boxShadow: selected ? [BoxShadow(color: OhtliColors.stormyTeal.withValues(alpha: 0.3), blurRadius: 14, offset: const Offset(0, 5))] : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 16, color: selected ? Colors.white : OhtliColors.accentText),
                const SizedBox(width: 7),
              ],
              Text(label,
                  style: GoogleFonts.inter(
                      fontSize: 13.5, fontWeight: selected ? FontWeight.w700 : FontWeight.w600, color: selected ? Colors.white : OhtliColors.onyx)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Píldora informativa pequeña (duración, costo, paradas…).
class OhtliMetaPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool onDark;

  const OhtliMetaPill({super.key, required this.icon, required this.label, this.onDark = false});

  @override
  Widget build(BuildContext context) {
    final fg = onDark ? Colors.white : OhtliColors.onyx;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        color: onDark ? Colors.black.withValues(alpha: 0.38) : OhtliColors.innerCardBg,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: onDark ? Colors.white.withValues(alpha: 0.18) : OhtliColors.cardBorder, width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: onDark ? Colors.white : OhtliColors.accentText),
          const SizedBox(width: 6),
          Text(label, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: fg)),
        ],
      ),
    );
  }
}

/// Estado vacío o informativo con ícono de servicio, título, mensaje y acción opcional.
class OhtliEmptyState extends StatelessWidget {
  final IconData icon;
  final Color? color;
  final String title;
  final String message;
  final Widget? action;

  const OhtliEmptyState({super.key, required this.icon, required this.title, required this.message, this.color, this.action});

  @override
  Widget build(BuildContext context) {
    final c = color ?? OhtliColors.stormyTeal;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(OhtliUi.radiusCard),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [c.withValues(alpha: 0.10), OhtliColors.cardBg],
        ),
        border: Border.all(color: c.withValues(alpha: 0.18)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          OhtliServiceIcon(icon: icon, color: c, size: 50),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: GoogleFonts.outfit(fontSize: 17, fontWeight: FontWeight.w700, color: OhtliColors.onyx)),
                const SizedBox(height: 4),
                Text(message, style: OhtliUi.body(size: 13.5)),
                if (action != null) ...[const SizedBox(height: 14), action!],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

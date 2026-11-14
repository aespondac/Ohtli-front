import 'package:flutter/material.dart';

/// Ícono de servicio "premium": baldosa con degradado, brillo superior, aro interior
/// y halo del color del servicio. Se usa en las landings de la API y de Labs.
class OhtliServiceIcon extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;

  /// Versión tenue (fondo translúcido e ícono de color) para listas secundarias.
  final bool soft;

  const OhtliServiceIcon({
    super.key,
    required this.icon,
    required this.color,
    this.size = 56,
    this.soft = false,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(size * 0.32);
    if (soft) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: radius,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [color.withValues(alpha: 0.20), color.withValues(alpha: 0.08)],
          ),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Icon(icon, size: size * 0.48, color: color),
      );
    }

    final deep = Color.lerp(color, Colors.black, 0.38)!;
    final light = Color.lerp(color, Colors.white, 0.22)!;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          BoxShadow(color: color.withValues(alpha: 0.40), blurRadius: size * 0.42, spreadRadius: -size * 0.08, offset: Offset(0, size * 0.18)),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Stack(
          fit: StackFit.expand,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [light, color, deep]),
              ),
            ),
            // Brillo superior
            Positioned(
              left: -size * 0.3,
              top: -size * 0.55,
              child: Container(
                width: size * 1.2,
                height: size * 0.9,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(colors: [Colors.white.withValues(alpha: 0.35), Colors.white.withValues(alpha: 0)]),
                ),
              ),
            ),
            // Aro interior
            DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: radius,
                border: Border.all(color: Colors.white.withValues(alpha: 0.28), width: 1),
              ),
            ),
            Center(
              child: Icon(
                icon,
                size: size * 0.46,
                color: Colors.white,
                shadows: [Shadow(color: deep.withValues(alpha: 0.6), blurRadius: 6, offset: const Offset(0, 1.5))],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

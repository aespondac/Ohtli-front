import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/colors.dart';

/// Botón para cambiar el tema: Sistema → Claro → Oscuro.
/// Por defecto la app sigue el modo del sistema operativo.
class OhtliThemeToggle extends StatelessWidget {
  /// Usa colores claros para colocarse sobre fotos o fondos oscuros.
  final bool onDark;

  const OhtliThemeToggle({super.key, this.onDark = false});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: OhtliSettings.instance,
      builder: (context, _) {
        final mode = OhtliSettings.instance.themeMode;
        final (IconData icon, String label) = switch (mode) {
          OhtliThemeMode.system => (Icons.brightness_auto_rounded, 'Tema: igual que el sistema'),
          OhtliThemeMode.light => (Icons.light_mode_rounded, 'Tema: claro'),
          OhtliThemeMode.dark => (Icons.dark_mode_rounded, 'Tema: oscuro'),
        };
        final fg = onDark ? Colors.white : OhtliColors.onyx;
        return Tooltip(
          message: '$label · toca para cambiar',
          textStyle: GoogleFonts.inter(fontSize: 12, color: Colors.white),
          child: Semantics(
            button: true,
            label: label,
            child: Material(
              color: onDark ? Colors.white.withValues(alpha: 0.14) : OhtliColors.cardBg,
              shape: CircleBorder(
                side: BorderSide(color: onDark ? Colors.white.withValues(alpha: 0.22) : OhtliColors.cardBorder),
              ),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: OhtliSettings.instance.cycleThemeMode,
                child: SizedBox(
                  width: 42,
                  height: 42,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    transitionBuilder: (child, anim) => RotationTransition(
                      turns: Tween(begin: 0.75, end: 1.0).animate(anim),
                      child: FadeTransition(opacity: anim, child: child),
                    ),
                    child: Icon(icon, key: ValueKey(mode), size: 20, color: fg),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/colors.dart';

/// Verde de marca para texto e iconos: en modo oscuro se aclara para mantener
/// buen contraste (el stormyTeal original casi no se lee sobre fondos oscuros).
Color get ohtliAccent => OhtliSettings.instance.isDarkMode ? const Color(0xFF7FC4CC) : OhtliColors.stormyTeal;

/// Contenido del panel rápido de accesibilidad.
class OhtliAccessibilityPanel extends StatelessWidget {
  final VoidCallback onMoreOptions;
  const OhtliAccessibilityPanel({super.key, required this.onMoreOptions});

  /// En celular: el mismo panel como hoja inferior.
  static Future<void> showSheet(BuildContext context, {required VoidCallback onMoreOptions}) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Center(
            heightFactor: 1,
            child: OhtliAccessibilityPanel(
              onMoreOptions: () {
                Navigator.of(ctx).pop();
                onMoreOptions();
              },
            ),
          ),
        ),
      ),
    );
  }

  static const _sizes = [
    (OhtliFontSize.small, 'Pequeño', 13.0),
    (OhtliFontSize.medium, 'Normal', 16.0),
    (OhtliFontSize.large, 'Grande', 19.0),
    (OhtliFontSize.extraLarge, 'Muy grande', 22.0),
  ];

  static const _themes = [
    (OhtliThemeMode.system, 'Sistema', Icons.brightness_auto_rounded),
    (OhtliThemeMode.light, 'Claro', Icons.light_mode_rounded),
    (OhtliThemeMode.dark, 'Oscuro', Icons.dark_mode_rounded),
  ];

  static Color _fg(bool selected) => selected ? ohtliAccent : OhtliColors.onyx.withOpacity(0.7);

  @override
  Widget build(BuildContext context) {
    final settings = OhtliSettings.instance;
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) {
        final labelStyle = GoogleFonts.inter(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: OhtliColors.onyx.withOpacity(0.7),
        );
        final sizeIndex = _sizes.indexWhere((e) => e.$1 == settings.fontSize);
        return Material(
          color: OhtliColors.cardBg,
          elevation: 12,
          shadowColor: Colors.black.withOpacity(0.25),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(color: OhtliColors.cardBorder),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
            child: SizedBox(
              width: 300,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.accessibility_new_rounded, color: ohtliAccent, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'Accesibilidad',
                        style: GoogleFonts.outfit(fontSize: 17, fontWeight: FontWeight.bold, color: OhtliColors.onyx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text('Tema', style: labelStyle),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      for (final t in _themes) ...[
                        Expanded(
                          child: _OptionChip(
                            selected: settings.themeMode == t.$1,
                            semanticsLabel: 'Tema ${t.$2}',
                            onTap: () => settings.themeMode = t.$1,
                            child: Column(
                              children: [
                                Icon(t.$3, size: 18, color: _fg(settings.themeMode == t.$1)),
                                const SizedBox(height: 4),
                                Text(
                                  t.$2,
                                  style: GoogleFonts.inter(fontSize: 11, color: _fg(settings.themeMode == t.$1)),
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (t != _themes.last) const SizedBox(width: 8),
                      ],
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Text('Tamaño de letra', style: labelStyle),
                      const Spacer(),
                      Text(
                        sizeIndex >= 0 ? _sizes[sizeIndex].$2 : '',
                        style: GoogleFonts.inter(fontSize: 12, color: ohtliAccent),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      for (final sz in _sizes) ...[
                        Expanded(
                          child: _OptionChip(
                            selected: settings.fontSize == sz.$1,
                            semanticsLabel: 'Letra ${sz.$2}',
                            onTap: () => settings.fontSize = sz.$1,
                            child: SizedBox(
                              height: 30,
                              child: Center(
                                child: Text(
                                  'A',
                                  // Sin escalar: la muestra se ve igual sin importar el ajuste actual.
                                  textScaler: TextScaler.noScaling,
                                  style: GoogleFonts.inter(
                                    fontSize: sz.$3,
                                    fontWeight: FontWeight.w600,
                                    color: _fg(settings.fontSize == sz.$1),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        if (sz != _sizes.last) const SizedBox(width: 8),
                      ],
                    ],
                  ),
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: onMoreOptions,
                      child: Text(
                        'Más preferencias en Mi cuenta',
                        style: GoogleFonts.inter(fontSize: 12, color: ohtliAccent),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _OptionChip extends StatelessWidget {
  final bool selected;
  final String semanticsLabel;
  final VoidCallback onTap;
  final Widget child;
  const _OptionChip({required this.selected, required this.semanticsLabel, required this.onTap, required this.child});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: semanticsLabel,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: selected ? OhtliColors.stormyTeal.withOpacity(0.12) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? ohtliAccent : OhtliColors.onyx.withOpacity(0.15),
              width: selected ? 1.5 : 1,
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

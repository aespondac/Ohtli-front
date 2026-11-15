// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'package:web/web.dart' as web;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../theme/colors.dart';
import '../widgets/ohtli_account_chip.dart';
import '../widgets/ohtli_theme_toggle.dart';

/// Secciones públicas de Ohtli Labs.
enum LabsSection { home, news, participate }

/// Barra superior común de Ohtli Labs (landing, noticias, resultados y participación),
/// para que labs.ohtli.quest, lab.ohtli.quest y /eval se sientan como un mismo sitio.
class LabsTopBar extends StatelessWidget implements PreferredSizeWidget {
  final LabsSection? current;

  /// Acción de "Ingresar a Labs". Si es nula, abre lab.ohtli.quest.
  final VoidCallback? onEnter;

  /// Acción extra a la derecha (p. ej. "Salir" cuando hay sesión).
  final Widget? trailing;

  const LabsTopBar({super.key, this.current, this.onEnter, this.trailing});

  @override
  Size get preferredSize => const Size.fromHeight(72);

  static String get _host => kIsWeb ? web.window.location.hostname : '';
  static bool get _isProd => _host.endsWith('ohtli.quest');

  /// URL de una sección pública. En producción vive en labs.ohtli.quest; en local usa
  /// los parámetros de prueba de la app.
  static String urlFor(LabsSection s) {
    if (_isProd) {
      return switch (s) {
        LabsSection.home => 'https://labs.ohtli.quest/',
        LabsSection.news => 'https://labs.ohtli.quest/news',
        LabsSection.participate => 'https://labs.ohtli.quest/eval',
      };
    }
    return switch (s) {
      LabsSection.home => '/?testLab',
      LabsSection.news => '/news?testLab',
      LabsSection.participate => '/eval?testEval',
    };
  }

  static void go(LabsSection s) {
    if (kIsWeb) web.window.location.href = urlFor(s);
  }

  static void openLab() {
    if (!kIsWeb) return;
    web.window.location.href = _isProd ? 'https://lab.ohtli.quest/' : '/?testLabApp';
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 820;
    final hPad = isMobile ? 16.0 : 40.0;

    Widget link(LabsSection s, String label) {
      final selected = s == current;
      return TextButton(
        onPressed: selected ? null : () => go(s),
        style: TextButton.styleFrom(
          foregroundColor: OhtliColors.onyx,
          disabledForegroundColor: OhtliColors.accentText,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          textStyle: GoogleFonts.inter(fontSize: 14, fontWeight: selected ? FontWeight.w700 : FontWeight.w500),
        ),
        child: Text(label),
      );
    }

    return Material(
      color: OhtliColors.cloudDancer.withValues(alpha: 0.92),
      child: Container(
        height: 72,
        padding: EdgeInsets.symmetric(horizontal: hPad),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: OhtliColors.cardBorder))),
        child: Row(
          children: [
            InkWell(
              onTap: current == LabsSection.home ? null : () => go(LabsSection.home),
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SvgPicture.asset('assets/logo.svg', height: 24, colorFilter: ColorFilter.mode(OhtliColors.onyx, BlendMode.srcIn)),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: OhtliColors.stormyTeal, borderRadius: BorderRadius.circular(8)),
                      child: Text('LABS', style: GoogleFonts.outfit(fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 1.0, color: Colors.white)),
                    ),
                  ],
                ),
              ),
            ),
            if (!isMobile) ...[
              const SizedBox(width: 28),
              link(LabsSection.home, 'Inicio'),
              link(LabsSection.news, 'Noticias'),
              link(LabsSection.participate, 'Participa'),
            ],
            const Spacer(),
            if (trailing != null) ...[trailing!, const SizedBox(width: 6)],
            // Con sesión: cuenta con "Cambiar de cuenta" y "Cerrar sesión".
            OhtliAccountChip(compact: isMobile),
            const OhtliThemeToggle(),
            const SizedBox(width: 10),
            if (isMobile)
              PopupMenuButton<LabsSection>(
                tooltip: 'Menú',
                icon: Icon(Icons.menu_rounded, color: OhtliColors.onyx),
                onSelected: go,
                itemBuilder: (_) => const [
                  PopupMenuItem(value: LabsSection.home, child: Text('Inicio')),
                  PopupMenuItem(value: LabsSection.news, child: Text('Noticias')),
                  PopupMenuItem(value: LabsSection.participate, child: Text('Participa')),
                ],
              ),
            ElevatedButton.icon(
              onPressed: onEnter ?? openLab,
              icon: const Icon(Icons.science_rounded, size: 16),
              label: Text(isMobile ? 'Labs' : 'Ingresar a Labs'),
              style: ElevatedButton.styleFrom(
                backgroundColor: OhtliColors.onyx,
                foregroundColor: OhtliColors.cloudDancer,
                elevation: 0,
                padding: EdgeInsets.symmetric(horizontal: isMobile ? 14 : 18, vertical: 13),
                shape: const StadiumBorder(),
                textStyle: GoogleFonts.outfit(fontWeight: FontWeight.w700, fontSize: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

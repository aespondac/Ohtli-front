import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/trip_transfers.dart';
import '../theme/colors.dart';

/// Modos de traslado agrupados para elegir sin una pared de botones.
const List<(String, List<String>)> kTransferModeGroups = [
  ('A pie o en bici', ['walking', 'bike', 'scooter']),
  ('Transporte público', ['metro', 'metrobus', 'bus', 'trolebus', 'tren_ligero', 'cablebus', 'suburbano', 'trajinera']),
  ('En auto', ['taxi', 'car']),
  ('Otro', ['other']),
];

/// Abre el selector de modo y devuelve el elegido (o null si se cierra).
Future<String?> showTransferModePicker(BuildContext context, {required String current, required bool isDark}) {
  final Color fg = isDark ? Colors.white : const Color(0xFF1F2A2A);
  final Color sub = isDark ? Colors.white60 : OhtliColors.subtleText;
  return showDialog<String>(
    context: context,
    builder: (ctx) => Dialog(
      backgroundColor: isDark ? const Color(0xFF1E1E22) : Colors.white,
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460, maxHeight: 640),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(child: Text('¿Cómo se mueven?', style: GoogleFonts.outfit(fontSize: 19, fontWeight: FontWeight.bold, color: fg))),
                  IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close_rounded)),
                ],
              ),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final g in kTransferModeGroups) ...[
                        Padding(
                          padding: const EdgeInsets.only(top: 10, bottom: 8),
                          child: Text(g.$1.toUpperCase(),
                              style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.6, color: sub)),
                        ),
                        LayoutBuilder(builder: (context, box) {
                          final double w = ((box.maxWidth - 2 * 8) / 3).floorToDouble();
                          return Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final id in g.$2)
                                () {
                                  final m = transferModeOf(id);
                                  final bool selected = m.id == current;
                                  return Material(
                                    color: selected
                                        ? OhtliColors.stormyTeal
                                        : (isDark ? Colors.white.withValues(alpha: 0.05) : const Color(0xFFF3F6F5)),
                                    borderRadius: BorderRadius.circular(14),
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(14),
                                      onTap: () => Navigator.pop(ctx, m.id),
                                      child: SizedBox(
                                        width: w,
                                        height: 66,
                                        child: Column(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Icon(m.icon, size: 22, color: selected ? Colors.white : OhtliColors.stormyTeal),
                                            const SizedBox(height: 5),
                                            Padding(
                                              padding: const EdgeInsets.symmetric(horizontal: 4),
                                              child: Text(m.label,
                                                  textAlign: TextAlign.center,
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: GoogleFonts.inter(
                                                      fontSize: 11.5, fontWeight: FontWeight.w600, color: selected ? Colors.white : fg)),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                }(),
                            ],
                          );
                        }),
                      ],
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
}

/// Botón con el modo actual (ícono, nombre y ▾) que abre el selector agrupado.
class TransferModeButton extends StatelessWidget {
  final String mode;
  final bool isDark;
  final ValueChanged<String> onChanged;

  const TransferModeButton({super.key, required this.mode, required this.isDark, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final m = transferModeOf(mode);
    return Material(
      color: OhtliColors.stormyTeal.withValues(alpha: isDark ? 0.18 : 0.08),
      shape: StadiumBorder(side: BorderSide(color: OhtliColors.stormyTeal.withValues(alpha: 0.35))),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: () async {
          final picked = await showTransferModePicker(context, current: mode, isDark: isDark);
          if (picked != null && picked != mode) onChanged(picked);
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(m.icon, size: 18, color: OhtliColors.stormyTeal),
              const SizedBox(width: 8),
              Text(m.label,
                  style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w700, color: isDark ? Colors.white : const Color(0xFF1F2A2A))),
              const SizedBox(width: 2),
              Icon(Icons.arrow_drop_down_rounded, color: isDark ? Colors.white70 : OhtliColors.subtleText),
            ],
          ),
        ),
      ),
    );
  }
}

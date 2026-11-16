import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../models/trip_model.dart';
import '../../../theme/colors.dart';
import '../../../widgets/ohtli_ui.dart';

/// Colores de las ramas cuando el grupo se separa: estables por la posición de la rama
/// (la primera siempre cempasúchil, la segunda xoconostle…). El turquesa queda para el grupo.
const List<Color> kBranchColors = [
  OhtliColors.cempasuchil,
  OhtliColors.xoconostle,
  Color(0xFF1971C2),
  Color(0xFF2B8A3E),
  Color(0xFF5F3DC4),
  Color(0xFFC2255C),
];

Color branchColor(int index) => kBranchColors[index.abs() % kBranchColors.length];

/// El color de la rama para texto e íconos (más claro en modo oscuro).
Color branchInk(Color c, bool isDark) => isDark ? Color.lerp(c, Colors.white, 0.45)! : c;

String branchName(TripBranch b, int index) => b.name.trim().isEmpty ? 'Grupo ${index + 1}' : b.name.trim();

/// Etiqueta de rama, reencuentro o llegada.
class BranchTag extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;
  final bool isDark;

  const BranchTag({super.key, required this.label, required this.color, this.icon, this.isDark = false});

  @override
  Widget build(BuildContext context) {
    final ink = branchInk(color, isDark);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.22 : 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 12, color: ink), const SizedBox(width: 4)],
          Flexible(
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w800, color: ink)),
          ),
        ],
      ),
    );
  }
}

/// Chip para elegir rama («¿Quién va?»): como [OhtliChoiceChip], pero del color de la rama.
class BranchChoiceChip extends StatelessWidget {
  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;
  final bool isDark;

  const BranchChoiceChip({
    super.key,
    required this.label,
    required this.color,
    required this.selected,
    required this.onTap,
    this.icon,
    this.isDark = false,
  });

  @override
  Widget build(BuildContext context) {
    final ink = branchInk(color, isDark);
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: selected ? color : OhtliColors.cardBg,
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: selected ? color : color.withValues(alpha: 0.45)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon ?? (selected ? Icons.check_rounded : Icons.circle), size: icon == null && !selected ? 9 : 15, color: selected ? Colors.white : ink),
              const SizedBox(width: 6),
              Text(label,
                  style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w700, color: selected ? Colors.white : (isDark ? Colors.white : OhtliColors.onyx))),
            ],
          ),
        ),
      ),
    );
  }
}

/// La separación en el viaje publicado: una bifurcación con cada rama, quiénes van y si se
/// reencuentran.
class SplitForkView extends StatelessWidget {
  final SplitSection split;

  /// uid → nombre de quienes viajan.
  final Map<String, String> names;
  final String? myUid;
  final bool isDark;

  const SplitForkView({super.key, required this.split, required this.names, required this.isDark, this.myUid});

  static const double _rowH = 62;

  @override
  Widget build(BuildContext context) {
    final branches = split.branches;
    final Color fg = isDark ? Colors.white : const Color(0xFF1F2A2A);
    final Color sub = isDark ? Colors.white60 : OhtliColors.subtleText;
    final bool anyRejoin = branches.any((b) => b.rejoins);
    String who(TripBranch b) {
      if (b.memberIds.isEmpty) return 'Sin asignar todavía';
      // Tú al final: «Van Ana y tú».
      final list = [
        for (final u in b.memberIds)
          if (u != myUid) names[u]?.trim().isNotEmpty == true ? names[u]!.trim().split(' ').first : 'alguien',
        if (myUid != null && b.memberIds.contains(myUid)) 'tú',
      ];
      if (list.length == 1) return list.single == 'tú' ? 'Vas tú' : 'Va ${list.single}';
      return 'Van ${list.take(list.length - 1).join(', ')} y ${list.last}';
    }

    return OhtliSurface(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
      accent: OhtliColors.xoconostle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.call_split_rounded, size: 15, color: branchInk(OhtliColors.xoconostle, isDark)),
              const SizedBox(width: 6),
              Text('EL GRUPO SE SEPARA', style: OhtliUi.eyebrow(branchInk(OhtliColors.xoconostle, isDark))),
            ],
          ),
          const SizedBox(height: 6),
          Text('Cada quien por su lado', style: OhtliUi.title(size: 22)),
          const SizedBox(height: 4),
          Text(
            anyRejoin ? 'Más adelante se reencuentran en el punto marcado.' : 'Desde aquí cada grupo termina el día por su cuenta.',
            style: OhtliUi.body(size: 13),
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 34,
                height: _rowH * branches.length,
                child: CustomPaint(painter: _ForkPainter([for (int i = 0; i < branches.length; i++) branchColor(i)], _rowH)),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  children: [
                    for (int i = 0; i < branches.length; i++)
                      SizedBox(
                        height: _rowH,
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(branchName(branches[i], i),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: branchInk(branchColor(i), isDark))),
                                  Text(who(branches[i]),
                                      maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.inter(fontSize: 12.5, color: branches[i].memberIds.isEmpty ? sub : fg)),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Tooltip(
                              message: branches[i].rejoins ? 'Llega al reencuentro' : 'No se reencuentra: termina en su última parada',
                              child: BranchTag(
                                label: branches[i].rejoins ? 'Se reencuentra' : 'Por su lado',
                                icon: branches[i].rejoins ? Icons.call_merge_rounded : Icons.flag_rounded,
                                color: branches[i].rejoins ? OhtliColors.stormyTeal : branchColor(i),
                                isDark: isDark,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Las líneas de la bifurcación: salen juntas de arriba y se abren hacia cada rama.
class _ForkPainter extends CustomPainter {
  final List<Color> colors;
  final double rowH;

  _ForkPainter(this.colors, this.rowH);

  @override
  void paint(Canvas canvas, Size size) {
    const start = Offset(6, 0);
    for (int i = colors.length - 1; i >= 0; i--) {
      final y = rowH * i + rowH / 2;
      final end = Offset(size.width - 4, y);
      final path = Path()
        ..moveTo(start.dx, start.dy)
        ..lineTo(start.dx, y - 18 < 0 ? 0.0 : y - 18)
        ..quadraticBezierTo(start.dx, y, start.dx + 14, y)
        ..lineTo(end.dx, end.dy);
      canvas.drawPath(
        path,
        Paint()
          ..color = colors[i]
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round,
      );
      canvas.drawCircle(end, 4.5, Paint()..color = colors[i]);
    }
  }

  @override
  bool shouldRepaint(covariant _ForkPainter old) => old.colors != colors || old.rowH != rowH;
}

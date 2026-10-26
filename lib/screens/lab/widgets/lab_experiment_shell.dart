import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../theme/colors.dart';

/// Shell estándar y prolijo para todas las pantallas de experimentos en Ohtli Labs.
/// Proporciona navegación consistente, migas de pan (breadcrumbs), indicación de
/// entorno de pruebas y soporte completo tanto en modo claro como en modo oscuro.
class LabExperimentShell extends StatelessWidget {
  final String title;
  final String subtitle;
  final String category;
  final String status;
  final Color statusColor;
  final String targetModule;
  final VoidCallback onBack;
  final List<Widget>? actions;
  final Widget child;
  final double maxWidth;

  const LabExperimentShell({
    super.key,
    required this.title,
    required this.subtitle,
    required this.category,
    required this.status,
    required this.statusColor,
    required this.targetModule,
    required this.onBack,
    this.actions,
    required this.child,
    this.maxWidth = 1100,
  });

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isMobile = screenSize.width < 768;

    return Scaffold(
      backgroundColor: OhtliColors.cloudDancer,
      appBar: AppBar(
        backgroundColor: OhtliColors.cardBg,
        elevation: 0,
        scrolledUnderElevation: 1,
        shadowColor: OhtliColors.cardBorder,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: OhtliColors.onyx),
          onPressed: onBack,
          tooltip: 'Volver al Workbench de Labs',
        ),
        titleSpacing: 0,
        title: Row(
          children: [
            InkWell(
              onTap: onBack,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: OhtliColors.stormyTeal.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Icon(Icons.science_rounded, size: 16, color: OhtliColors.stormyTeal),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Labs',
                      style: GoogleFonts.outfit(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: OhtliColors.subtleText,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Icon(Icons.chevron_right_rounded, size: 18, color: OhtliColors.cardBorder),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                title,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.outfit(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: OhtliColors.onyx,
                ),
              ),
            ),
          ],
        ),
        actions: [
          if (!isMobile) ...[
            // Badge de entorno de pruebas
            Container(
              margin: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: OhtliColors.innerCardBg,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: OhtliColors.cardBorder),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: statusColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    status,
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: OhtliColors.onyx,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
            // Badge de destino de integración en Ohtli.quest
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 12, right: 12),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: OhtliColors.stormyTeal.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: OhtliColors.stormyTeal.withValues(alpha: 0.25)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.rocket_launch_rounded, size: 12, color: OhtliColors.stormyTeal),
                  const SizedBox(width: 6),
                  Text(
                    targetModule,
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: OhtliColors.stormyTeal,
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (actions != null) ...actions!,
          const SizedBox(width: 8),
        ],
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.symmetric(
          horizontal: isMobile ? 16 : 32,
          vertical: isMobile ? 20 : 32,
        ),
        child: Center(
          child: Container(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Banner superior de contexto de laboratorio y objetivo de producción
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  margin: const EdgeInsets.only(bottom: 24),
                  decoration: BoxDecoration(
                    color: OhtliColors.cardBg,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: OhtliColors.cardBorder),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: statusColor.withValues(alpha: 0.14),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        category.toUpperCase(),
                                        style: GoogleFonts.inter(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 0.8,
                                          color: statusColor,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: OhtliColors.innerCardBg,
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(color: OhtliColors.cardBorder),
                                      ),
                                      child: Text(
                                        'ENTORNO DE PRUEBAS PRE-PRODUCCIÓN',
                                        style: GoogleFonts.inter(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: 0.5,
                                          color: OhtliColors.subtleText,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  title,
                                  style: GoogleFonts.outfit(
                                    fontSize: isMobile ? 22 : 28,
                                    fontWeight: FontWeight.w800,
                                    color: OhtliColors.onyx,
                                    letterSpacing: -0.5,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  subtitle,
                                  style: GoogleFonts.inter(
                                    fontSize: 14,
                                    color: OhtliColors.subtleText,
                                    height: 1.45,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Divider(height: 1, thickness: 1, color: OhtliColors.cardBorder),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          const Icon(Icons.info_outline_rounded, size: 16, color: OhtliColors.stormyTeal),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Objetivo: Validar precisión, latencia y casos límite antes de integrar esta capacidad en Ohtli.quest ($targetModule).',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: OhtliColors.subtleText,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Contenido del experimento
                child,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

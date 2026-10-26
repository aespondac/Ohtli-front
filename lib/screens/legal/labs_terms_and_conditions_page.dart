import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/colors.dart';

class LabsTermsAndConditionsPage extends StatelessWidget {
  final VoidCallback onBack;

  const LabsTermsAndConditionsPage({
    super.key,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0EEE9),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 1,
        shadowColor: const Color(0xFF0A090C).withValues(alpha: 0.08),
        foregroundColor: const Color(0xFF0A090C),
        title: Text(
          'Términos del Banco de Pruebas (Labs)',
          style: GoogleFonts.outfit(fontWeight: FontWeight.w700, fontSize: 18),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: onBack,
          tooltip: 'Regresar',
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: Container(
              padding: const EdgeInsets.all(40),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: const Color(0xFF0A090C).withValues(alpha: 0.08)),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF0A090C).withValues(alpha: 0.03),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: OhtliColors.stormyTeal.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.gavel_rounded, color: OhtliColors.stormyTeal, size: 24),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Marco Legal de Experimentación y Sandbox',
                              style: GoogleFonts.outfit(
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                                color: const Color(0xFF0A090C),
                              ),
                            ),
                            Text(
                              'Ohtli Labs · Banco de Pruebas Previo a Ohtli.quest',
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                color: const Color(0xFF0A090C).withValues(alpha: 0.6),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  const Divider(height: 1, thickness: 1, color: Color(0x0F0A090C)),
                  const SizedBox(height: 28),

                  _buildSection(
                    '1. Naturaleza Experimental del Software',
                    'Ohtli Labs es un banco de pruebas exclusivo para evaluar funcionalidades previas a su integración en Ohtli.quest. Usted reconoce y acepta expresamente que el software, las características y los experimentos disponibles en Labs son versiones en fase Alpha/Beta y pueden presentar inestabilidad o cambios de esquema.',
                  ),
                  _buildSection(
                    '2. Ausencia de Garantías de Nivel de Servicio (SLA)',
                    'Los experimentos se proporcionan "tal cual" (As Is). Ohtli renuncia a garantías explícitas sobre disponibilidad ininterrumpida o persistencia indefinida de datos en colecciones de prueba.',
                  ),
                  _buildSection(
                    '3. Aislamiento y Certificación para Producción',
                    'Las acciones ejecutadas en Ohtli Labs no alteran itinerarios de viajeros en producción en ohtli.quest, salvo que se invoque explícitamente una función de replicación certificada por el usuario.',
                  ),
                  _buildSection(
                    '4. Telemetría y Diagnóstico',
                    'El propósito esencial de Labs es recopilar telemetría de latencia, precisión y consistencia para garantizar la alta calidad de Ohtli.quest.',
                  ),
                  _buildSection(
                    '5. Confidencialidad y Propiedad Intelectual',
                    'Los algoritmos vectoriales, recetas semánticas y arquitectura de microservicios de Yollotl Engine son propiedad exclusiva de Ohtli.',
                  ),

                  const SizedBox(height: 24),
                  const Divider(height: 1, thickness: 1, color: Color(0x0F0A090C)),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Equipo de Ingeniería de Ohtli',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF0A090C).withValues(alpha: 0.7),
                        ),
                      ),
                      ElevatedButton(
                        onPressed: onBack,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0A090C),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('Volver al Laboratorio'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSection(String title, String content) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.outfit(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF0A090C),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            content,
            style: GoogleFonts.inter(
              fontSize: 14,
              color: const Color(0xFF0A090C).withValues(alpha: 0.75),
              height: 1.55,
            ),
          ),
        ],
      ),
    );
  }
}

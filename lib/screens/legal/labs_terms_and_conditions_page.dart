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
      backgroundColor: const Color(0xFFF0EEE9), // Fondo claro para la legalidad de Labs
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: const Color(0xFF0A090C),
        title: Text('Términos de Labs', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: onBack,
          tooltip: 'Regresar',
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 40.0),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Términos y Condiciones de Ohtli Labs',
                  style: GoogleFonts.outfit(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF0A090C),
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Última actualización: Noviembre 2023',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    color: const Color(0xFF0A090C).withValues(alpha: 0.6),
                  ),
                ),
                const SizedBox(height: 40),
                _buildSection(
                  '1. Naturaleza Experimental del Software',
                  'Ohtli Labs es un entorno de prueba para funcionalidades en fase de desarrollo (Beta). Usted reconoce y acepta expresamente que el software, las características y los experimentos disponibles en Labs no son versiones finales. Pueden contener errores, defectos ("bugs") o fallos de seguridad no detectados.',
                ),
                _buildSection(
                  '2. Ausencia de Garantías',
                  'Los experimentos de Ohtli Labs se proporcionan estrictamente "tal cual" (As Is). Ohtli renuncia a todas las garantías, ya sean expresas o implícitas, incluyendo, pero no limitadas a, la disponibilidad, precisión, fiabilidad o idoneidad para un propósito particular. No garantizamos que los experimentos de Labs funcionen de manera ininterrumpida o que los datos procesados en ellos no se pierdan o corrompan.',
                ),
                _buildSection(
                  '3. Uso y Riesgos Asumidos',
                  'El uso de Ohtli Labs es completamente voluntario y bajo su propio riesgo. Usted asume toda la responsabilidad por cualquier daño a su dispositivo, pérdida de datos o cualquier otro perjuicio resultante del uso de este entorno experimental.',
                ),
                _buildSection(
                  '4. Recopilación de Datos y Feedback',
                  'El propósito principal de Ohtli Labs es probar y mejorar nuevas funcionalidades. Al participar, usted consiente la recopilación extendida de datos de telemetría, métricas de uso y reportes de errores ("crash reports"). Además, Ohtli puede contactarlo periódicamente para solicitar su retroalimentación cualitativa sobre su experiencia.',
                ),
                _buildSection(
                  '5. Confidencialidad (NDAs implícitos)',
                  'Ciertas características de Ohtli Labs pueden ser información confidencial y patentable de Ohtli. Al obtener acceso a Labs, usted se compromete a no compartir capturas de pantalla, descripciones detalladas, ni ingeniería inversa de los algoritmos experimentales en foros públicos sin la autorización explícita de Ohtli.',
                ),
                _buildSection(
                  '6. Derecho de Modificación y Retiro',
                  'Ohtli se reserva el derecho absoluto de modificar, suspender o retirar cualquier funcionalidad de Labs en cualquier momento, sin previo aviso. Ohtli también puede revocar su acceso a Ohtli Labs a su entera discreción si considera que ha violado estos Términos o el espíritu de las pruebas beta.',
                ),
                _buildSection(
                  '7. Deslinde de Responsabilidad por Mal Uso',
                  'Ohtli se exime de cualquier tipo de responsabilidad civil, penal, administrativa o de cualquier otra índole, derivada del mal uso, uso ilícito o indebido que el usuario haga de las herramientas, algoritmos o productos experimentales de Labs. Usted es el único y exclusivo responsable de las acciones que realice utilizando nuestra plataforma.',
                ),
                _buildSection(
                  '8. Indemnización y Reposición de Perjuicios',
                  'Usted acepta expresamente defender, indemnizar y eximir a Ohtli de toda responsabilidad frente a cualquier reclamación, demanda, daño, obligación, pérdida, costo o gasto que surja directa o indirectamente de su uso de Ohtli Labs. En caso de que sus acciones causen daños directos, indirectos, tangibles o intangibles a terceros o a Ohtli, usted se compromete incondicionalmente a la reparación integral del daño, incluyendo la reposición monetaria, material o de cualquier otra índole requerida para subsanar los perjuicios causados.',
                ),
                const SizedBox(height: 40),
                Divider(color: const Color(0xFF0A090C).withValues(alpha: 0.2)),
                const SizedBox(height: 24),
                Text(
                  'Si tiene dudas sobre el entorno de Labs, póngase en contacto con el equipo de ingeniería de Ohtli.',
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    color: const Color(0xFF0A090C).withValues(alpha: 0.8),
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 40),
              ],
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
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF0A090C),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            content,
            style: GoogleFonts.inter(
              fontSize: 15,
              color: const Color(0xFF0A090C).withValues(alpha: 0.8),
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }
}
